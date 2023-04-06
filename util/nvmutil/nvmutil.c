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
int parseMacAddress(const char *strMac, uint16_t *mac);
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
void byteswap(int n, int partnum);
void writeGbeFile(int *fd, const char *filename);

#define FILENAME argv[1]
#define COMMAND argv[2]
#define MAC_ADDRESS argv[3]
#define PARTNUM argv[3]
#define SIZE_4KB 0x1000
#define SIZE_8KB 0x2000

uint16_t buf16[SIZE_4KB];
uint8_t *buf;
size_t gbe[2];
uint8_t skipread[2] = {0, 0};

int part, gbeWriteAttempted = 0, gbeFileModified = 0;
uint8_t nvmPartModified[2] = {0, 0};

uint16_t test;
uint8_t big_endian;

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

	buf = (uint8_t *) &buf16;
	gbe[1] = (gbe[0] = (size_t) buf) + SIZE_4KB;

	test = 1;
	big_endian = ((uint8_t *) &test)[0] ^ 1;

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

	nr = SIZE_4KB; /* copy/swap commands need everything to be read */
	if ((cmd != &cmd_copy) && (cmd != &cmd_swap))
		nr = 128; /* read only the nvm part */

	if ((cmd == &cmd_copy) || (cmd == &cmd_setchecksum) ||
	    (cmd == &cmd_brick))
		skipread[part ^ 1] = 1; /* skip reading the unused part */

	readGbeFile(&fd, FILENAME, flags, nr);

	if (strMac != NULL)
		cmd_setmac(strMac);
	else if (cmd != NULL)
		(*cmd)();

	if (gbeFileModified)
		writeGbeFile(&fd, FILENAME);
	else if (gbeWriteAttempted && (cmd != &cmd_dump))
		errno = 0;

nvmutil_exit:
	if ((errno != 0) && (cmd != &cmd_dump))
		err(errno, NULL);
	return errno;
}

void
readGbeFile(int *fd, const char *path, int flags, size_t nr)
{
	struct stat st;
	int p, r;

	if (opendir(path) != NULL)
		err(errno = EISDIR, "%s", path);
	else if (((*fd) = open(path, flags)) == -1)
		err(errno, "%s", path);
	else if (fstat((*fd), &st) == -1)
		err(errno, "%s", path);
	else if ((st.st_size != SIZE_8KB))
		err(errno = ECANCELED, "File \"%s\" not of size 8KiB", path);
	else if (errno == ENOTDIR)
		errno = 0;
	else if (errno != 0)
		err(errno, "%s", path);

	for (p = 0; p < 2; p++) {
		if (skipread[p])
			continue;
		if ((r = pread((*fd), (uint8_t *) gbe[p], nr, p << 12)) == -1)
			err(errno, "%s", path);
		if (big_endian)
			byteswap(nr, p);
	}
}

void
cmd_setmac(const char *strMac)
{
	uint16_t mac[3] = {0, 0, 0};
	if (parseMacAddress(strMac, mac) == -1)
		err(errno = ECANCELED, "Bad MAC address");

	/* nvm words are little endian, *except* the mac address. swap bytes */
	for (int w = 0; w < 3; w++) {
		uint8_t *b = (uint8_t *) &mac[w];
		b[0] ^= b[1];
		b[1] ^= b[0];
		b[0] ^= b[1];
	}

	for (int partnum = 0; partnum < 2; partnum++) {
		if (!validChecksum(partnum))
			continue;
		for (int w = 0; w < 3; w++)
			setWord(w, partnum, mac[w]);
		part = partnum;
		cmd_setchecksum();
	}
}

int
parseMacAddress(const char *strMac, uint16_t *mac)
{
	uint8_t h;
	uint64_t total = 0;

	if (strnlen(strMac, 20) != 17)
		return -1;

	for (int i = 0; i < 16; i += 3) {
		if (i != 15)
			if (strMac[i + 2] != ':')
				return -1;
		int byte = i / 3;
		for (int nib = 0; nib < 2; nib++, total += h) {
			if ((h = hextonum(strMac[i + nib])) > 15)
				return -1;
			if ((byte == 0) && (nib == 1))
				if (strMac[i + nib] == '?')
					h = (h & 0xE) | 2;
			mac[byte >> 1] |= ((uint16_t ) h)
				<< ((8 * ((byte % 2) ^ 1)) + (4 * (nib ^ 1)));
		}
	}

	/* Disallow multicast and all-zero MAC addresses */
	return ((total == 0) || (mac[0] & 0x100))
		? -1 : 0;
}

uint8_t
hextonum(char ch)
{
	if ((ch >= '0') && (ch <= '9'))
		return ch - '0';
	else if ((ch >= 'A') && (ch <= 'F'))
		return ch - 'A' + 10;
	else if ((ch >= 'a') && (ch <= 'f'))
		return ch - 'a' + 10;
	else if (ch == '?')
		return rhex();
	else
		return 16;
}

uint8_t
rhex(void)
{
	static int rfd = -1;
	static uint64_t rnum = 0;
	if (rnum == 0) {
		if (rfd == -1)
			if ((rfd = open("/dev/urandom", O_RDONLY)) == -1)
				err(errno, "/dev/urandom");
		if (read(rfd, (uint8_t *) &rnum, 8) == -1)
			err(errno, "/dev/urandom");
	}
	uint8_t rval = (uint8_t) (rnum & 0xf);
	rnum >>= 4;
	return rval;
}

void
cmd_dump(void)
{
	int partnum, numInvalid = 0;
	for (partnum = 0; partnum < 2; partnum++) {
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
	uint16_t val16;
	for (int c = 0; c < 3; c++) {
		val16 = word(c, partnum);
		printf("%02x:%02x", val16 & 0xff, val16 >> 8);
		if (c == 2)
			printf("\n");
		else
			printf(":");
	}
}

void
hexdump(int partnum)
{
	uint16_t val16;
	for (int row = 0; row < 8; row++) {
		printf("%07x ", row << 4);
		for (int c = 0; c < 8; c++) {
			val16 = word((row << 3) + c, partnum);
			printf("%02x%02x ", val16 >> 8, val16 & 0xff);
		}
		printf("\n");
	}
}

void
cmd_setchecksum(void)
{
	uint16_t val16 = 0;
	for (int c = 0; c < 0x3F; c++)
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
	uint16_t total = 0;
	for(int w = 0; w <= 0x3F; w++)
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
	return buf16[pos16 + (partnum << 11)];
}

void
setWord(int pos16, int partnum, uint16_t val16)
{
	gbeWriteAttempted = 1;
	if (word(pos16, partnum) == val16)
		return;
	buf16[pos16 + (partnum << 11)] = val16;
	gbeFileModified = 1;
	nvmPartModified[partnum] = 1;
}

void
byteswap(int n, int partnum)
{
	int b1, b2, wcount = n >> 1;
	uint8_t *nbuf = (uint8_t *) gbe[partnum];
	for (int w = 0; w < wcount; w++) {
		b1 = b2 = w << 1;
		nbuf[b1] ^= nbuf[++b2];
		nbuf[b2] ^= nbuf[b1];
		nbuf[b1] ^= nbuf[b2];
	}
}

void
writeGbeFile(int *fd, const char *filename)
{
	int p, nw;
	errno = 0;
	if ((gbe[0] != gbe[1]) && (gbe[0] < gbe[1]))
		nw = 128; /* copy/swap command, so only write the nvm part */
	else
		nw = SIZE_4KB;

	for (p = 0; p < 2; p++) {
		if (gbe[0] > gbe[1])
			p ^= 1;
		if (!nvmPartModified[p])
			goto next_part;
		if (big_endian)
			byteswap(nw, p);
		if (pwrite((*fd), (uint8_t *) gbe[p], nw, p << 12) != nw)
			err(errno, "%s", filename);
next_part:
		if (gbe[0] > gbe[1])
			p ^= 1;
	}
	if (close((*fd)))
		err(errno, "%s", filename);
}
