/* 
 * Copyright (C) 2022, 2023 Leah Rowe <info@minifree.org>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <dirent.h>
#include <err.h>

void readGbeFile(int *fd, const char *path, int flags,
	size_t nr);
void cmd_setmac(const char *strMac);
uint8_t hextonum(char chs);
uint8_t rhex(void);
void cmd_dump(void);
void showmac(int partnum);
void hexdump(int partnum);
void cmd_setchecksum(void);
void cmd_brick(void);
void cmd_swap(void);
void cmd_copy(void);
int validChecksum(int partnum);
uint16_t word(int pos16, int partnum);
void setWord(int pos16, int partnum, uint16_t val16);
void byteswap(uint8_t *byte);
void writeGbeFile(int *fd, const char *filename);

#define FILENAME argv[1]
#define COMMAND argv[2]
#define MAC_ADDRESS argv[3]
#define PARTNUM argv[3]
#define SIZE_4KB 0x1000
#define SIZE_8KB 0x2000

uint8_t buf[SIZE_8KB];
size_t gbe[2];
uint8_t skipread[2] = {0, 0};

int part, gbeWriteAttempted = 0, gbeFileModified = 0;
uint8_t nvmPartModified[2] = {0, 0};

uint16_t test;
uint8_t little_endian;

int
main(int argc, char *argv[])
{
	size_t nr;
	int fd, flags = O_RDWR;
	void (*cmd)(void) = NULL;
	const char *strMac = NULL, *strRMac = "??:??:??:??:??:??";

#ifdef HAVE_PLEDGE
	if (pledge("stdio wpath", NULL) == -1)
		err(errno, "pledge");
#endif

	gbe[1] = (gbe[0] = (size_t) buf) + SIZE_4KB;

	test = 1;
	little_endian = ((uint8_t *) &test)[0];

	if (argc == 3) {
		if (strcmp(COMMAND, "dump") == 0) {
#ifdef HAVE_PLEDGE
			if (pledge("stdio rpath", NULL) == -1)
				err(errno, "pledge");
#endif
			flags = O_RDONLY;
			cmd = &cmd_dump;
		} else if (strcmp(COMMAND, "setmac") == 0)
			strMac = (char *) strRMac;
		else if (strcmp(COMMAND, "swap") == 0)
			cmd = &cmd_swap;
	} else if (argc == 4) {
		if (strcmp(COMMAND, "setmac") == 0)
			strMac = MAC_ADDRESS;
		else if ((!((part = PARTNUM[0] - '0') == 0 || part == 1))
				|| PARTNUM[1])
			errno = EINVAL;
		else if (strcmp(COMMAND, "setchecksum") == 0)
			cmd = &cmd_setchecksum;
		else if (strcmp(COMMAND, "brick") == 0)
			cmd = &cmd_brick;
		else if (strcmp(COMMAND, "copy") == 0)
			cmd = &cmd_copy;
	}

	if ((strMac == NULL) && (cmd == NULL))
		errno = EINVAL;
	if (errno != 0)
		goto nvmutil_exit;

	if ((cmd == &cmd_copy) || (cmd == &cmd_swap))
		nr = SIZE_4KB;
	else
		nr = 128;

	if ((cmd == &cmd_copy) || (cmd == &cmd_setchecksum) ||
	    (cmd == &cmd_brick))
		skipread[part ^ 1] = 1;

	readGbeFile(&fd, FILENAME, flags, nr);

	if (strMac != NULL)
		cmd_setmac(strMac);
	else if (cmd != NULL)
		(*cmd)();

	if (gbeFileModified) {
		writeGbeFile(&fd, FILENAME);
	} else if ((cmd != &cmd_dump)) {
		printf("File `%s` not modified.\n", FILENAME);
		if (gbeWriteAttempted)
			errno = 0;
	}

nvmutil_exit:
	if ((errno != 0) && (cmd != &cmd_dump))
		err(errno, NULL);
	else
		return errno;
}

void
readGbeFile(int *fd, const char *path, int flags, size_t nr)
{
	struct stat st;
	int p, r, tr;

	if (opendir(path) != NULL)
		err(errno = EISDIR, "%s", path);
	if (((*fd) = open(path, flags)) == -1)
		err(errno, "%s", path);
	if (fstat((*fd), &st) == -1)
		err(errno, "%s", path);
	if ((st.st_size != SIZE_8KB)) {
		fprintf(stderr, "%s: Bad file size (must be 8KiB)\n", path);
		err(errno = ECANCELED, NULL);
	}

	if (errno == ENOTDIR)
		errno = 0;
	if (errno != 0)
		err(errno, "%s", path);

	for (tr = 0, p = 0; p < 2; p++) {
		if (skipread[p])
			continue;
		if ((r = pread((*fd), (uint8_t *) gbe[p], nr, p << 12)) == -1)
			err(errno, "%s", path);
		tr += r;
	}
	printf("%d bytes read from file: `%s`\n", tr, path);
}

void
cmd_setmac(const char *strMac)
{
	int partnum, byte, nib;
	uint8_t o, val8;
	uint16_t val16, mac[3] = {0, 0, 0};
	uint64_t total;

	if (strnlen(strMac, 20) != 17)
		goto invalid_mac_address;

	for (o = 0; o < 16; o += 3) {
		if (o != 15)
			if (strMac[o + 2] != ':')
				goto invalid_mac_address;
		byte = o / 3;
		for (total = 0, nib = 0; nib < 2; nib++, total += val8) {
			if ((val8 = hextonum(strMac[o + nib])) > 15)
				goto invalid_mac_address;
			if ((byte == 0) && (nib == 1)) {
				if (strMac[o + nib] == '?')
					val8 = (val8 & 0xE) | 2;
			}

			val16 = val8;
			if ((byte % 2) ^ 1)
				byteswap((uint8_t *) &val16);
			val16 <<= 4 * (nib ^ 1);
			mac[byte >> 1] |= val16;
		}
	}

	test = mac[0];
	if (little_endian)
		byteswap((uint8_t *) &test);
	if (total == 0 || (((uint8_t *) &test)[0] & 1))
		goto invalid_mac_address;

	if (little_endian)
		for (o = 0; o < 3; o++)
			byteswap((uint8_t *) &mac[o]);

	for (partnum = 0; partnum < 2; partnum++) {
		if (!validChecksum(partnum))
			continue;
		for (o = 0; o < 3; o++)
			setWord(o, partnum, mac[o]);
		part = partnum;
		cmd_setchecksum();
	}

	return;
invalid_mac_address:
	fprintf(stderr, "Bad MAC address\n");
	errno = ECANCELED;
}

uint8_t
hextonum(char chs)
{
	uint8_t val8, ch;
	ch = (uint8_t) chs;

	if ((ch >= '0') && (ch <= '9'))
		val8 = ch - '0';
	else if ((ch >= 'A') && (ch <= 'F'))
		val8 = ch - 'A' + 10;
	else if ((ch >= 'a') && (ch <= 'f'))
		val8 = ch - 'a' + 10;
	else if (ch == '?')
		val8 = rhex();
	else
		return 16;

	return val8;
}

uint8_t
rhex(void)
{
	static int rfd = -1;
	static uint64_t rnum = 0;
	uint8_t rval;

	if (rnum == 0) {
		if (rfd == -1)
			if ((rfd = open("/dev/urandom", O_RDONLY)) == -1)
				err(errno, "/dev/urandom");
		if (read(rfd, (uint8_t *) &rnum, 8) == -1)
			err(errno, "/dev/urandom");
	}

	rval = (uint8_t) (rnum & 0xf);
	rnum >>= 4;

	return rval;
}

void
cmd_dump(void)
{
	int numInvalid, partnum;

	numInvalid = 0;
	for (partnum = 0; (partnum < 2); partnum++) {
		if (!validChecksum(partnum))
			++numInvalid;

		printf("MAC (part %d): ", partnum);
		showmac(partnum);

		hexdump(partnum);
	}
	if (numInvalid < 2)
		errno = 0;
}

void
showmac(int partnum)
{
	int c;
	uint16_t val16;
	uint8_t *byte;

	for (c = 0; c < 3; c++) {
		val16 = word(c, partnum);
		byte = (uint8_t *) &val16;

		if (!little_endian)
			byteswap(byte);

		printf("%02x:%02x", byte[0], byte[1]);
		if (c == 2)
			printf("\n");
		else
			printf(":");
	}
}

void
hexdump(int partnum)
{
	int row, c;
	uint16_t val16;
	uint8_t *byte;

	for (row = 0; row < 8; row++) {
		printf("%07x ", row << 4);
		for (c = 0; c < 8; c++) {
			val16 = word((row << 3) + c, partnum);
			byte = (uint8_t *) &val16;

			if (!little_endian)
				byteswap(byte);

			printf("%02x%02x ", byte[1], byte[0]);
		}
		printf("\n");
	}
}

void
cmd_setchecksum(void)
{
	int c;
	uint16_t val16;

	for (val16 = 0, c = 0; c < 0x3F; c++)
		val16 += word(c, part);

	setWord(0x3F, part, 0xBABA - val16);
}

void
cmd_brick(void)
{
	if (validChecksum(part))
		setWord(0x3F, part, (word(0x3F, part)) ^ 0xFF);
}

void
cmd_swap(void)
{
	if (validChecksum(1) || validChecksum(0)) {
		gbe[0] ^= gbe[1];
		gbe[1] ^= gbe[0];
		gbe[0] ^= gbe[1];

		gbeFileModified = 1;
		nvmPartModified[0] = 1;
		nvmPartModified[1] = 1;

		errno = 0;
	}
}

void
cmd_copy(void)
{
	if (validChecksum(part)) {
		gbe[part ^ 1] = gbe[part];

		gbeFileModified = 1;
		nvmPartModified[part ^ 1] = 1;
	}
}

int
validChecksum(int partnum)
{
	int w;
	uint16_t total;

	for(total = 0, w = 0; w <= 0x3F; w++)
		total += word(w, partnum);

	if (total == 0xBABA)
		return 1;

	fprintf(stderr, "WARNING: BAD checksum in part %d\n", partnum);
	errno = ECANCELED;
	return 0;
}

uint16_t
word(int pos16, int partnum)
{
	uint8_t *nbuf;
	uint16_t pos8, val16;

	nbuf = (uint8_t *) gbe[partnum];
	pos8 = pos16 << 1;
	val16 = nbuf[pos8 + 1];
	val16 <<= 8;
	val16 |= nbuf[pos8];

	return val16;
}

void
setWord(int pos16, int partnum, uint16_t val16)
{
	uint8_t val8[2], *nbuf;
	uint16_t pos8;

	gbeWriteAttempted = 1;
	if (word(pos16, partnum) == val16)
		return;

	nbuf = (uint8_t *) gbe[partnum];
	val8[0] = (uint8_t) (val16 & 0xff);
	val8[1] = (uint8_t) (val16 >> 8);
	pos8 = pos16 << 1;

	nbuf[pos8] = val8[0];
	nbuf[pos8 + 1] = val8[1];

	gbeFileModified = 1;
	nvmPartModified[partnum] = 1;
}

void
byteswap(uint8_t *byte)
{
	byte[0] ^= byte[1];
	byte[1] ^= byte[0];
	byte[0] ^= byte[1];
}

void
writeGbeFile(int *fd, const char *filename)
{
	int p, nw, tw;
	errno = 0;

	/* if copy/swap not performed, write only the nvm part */
	if ((gbe[0] != gbe[1]) && (gbe[0] < gbe[1]))
		nw = 128;
	else
		nw = SIZE_4KB;

	for (tw = 0, p = 0; p < 2; p++) {
		if (gbe[0] > gbe[1])
			p ^= 1;
		if (nvmPartModified[p]) {
			printf("Part %d modified\n", p);
		} else {
			fprintf (stderr,
				"Part %d NOT modified\n", p);
			goto next_part;
		}
		if (pwrite((*fd), (uint8_t *) gbe[p], nw, p << 12) != nw)
			err(errno, "%s", filename);
		tw += nw;
next_part:
		if (gbe[0] > gbe[1])
			p ^= 1;
	}
	if (close((*fd)))
		err(errno, "%s", filename);

	printf("%d bytes written to file: `%s`\n", tw, filename);
}
