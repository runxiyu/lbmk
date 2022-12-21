/* 
 * Copyright (C) 2022 Leah Rowe <info@minifree.org>
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

ssize_t readFromFile(int *fd, uint8_t *buf, const char *path, int flags,
	size_t size);
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
void setWord(int pos16, int partnum, uint16_t val);
void byteswap(uint8_t *byte);
void writeGbeFile(int *fd, const char *filename);

#define FILENAME argv[1]
#define COMMAND argv[2]
#define MAC_ADDRESS argv[3]
#define PARTNUM argv[3]
#define SIZE_4KB 0x1000
#define SIZE_8KB 0x2000

uint8_t gbe[SIZE_8KB];
int part, gbeFileModified = 0;
uint8_t nvmPartModified[2];

uint16_t test;
uint8_t little_endian;

int
main(int argc, char *argv[])
{
	int fd;
	int flags = O_RDWR;
	char *strMac = NULL;
	char *strRMac = "??:??:??:??:??:??";
	void (*cmd)(void) = NULL;

	nvmPartModified[0] = 0;
	nvmPartModified[1] = 0;

	test = 1;
	little_endian = ((uint8_t *) &test)[0];

#ifdef HAVE_PLEDGE
	if (pledge("stdio wpath", NULL) == -1)
		err(1, "pledge");
#endif
	if (argc == 3) {
		if (strcmp(COMMAND, "dump") == 0) {
#ifdef HAVE_PLEDGE
			if (pledge("stdio rpath", NULL) == -1)
				err(1, "pledge");
#endif
			flags = O_RDONLY;
			cmd = &cmd_dump;
		} else if (strcmp(COMMAND, "setmac") == 0)
			strMac = strRMac;
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
	else if (readFromFile(&fd, gbe, FILENAME, flags, SIZE_8KB) != SIZE_8KB)
		goto nvmutil_exit;

	if (errno == 0) {
		if (strMac != NULL)
			cmd_setmac(strMac);
		else if (cmd != NULL)
			(*cmd)();

		if (gbeFileModified)
			writeGbeFile(&fd, FILENAME);
	}

nvmutil_exit:
	if (!((errno == ECANCELED) && (flags == O_RDONLY)))
		if (errno != 0)
			fprintf(stderr, "%s\n", strerror(errno));

	return errno;
}

ssize_t
readFromFile(int *fd, uint8_t *buf, const char *path, int flags, size_t size)
{
	struct stat st;

	if (opendir(path) != NULL) {
		errno = EISDIR;
		return -1;
	} else if (((*fd) = open(path, flags)) == -1) {
		return -1;
	} else if (size == SIZE_8KB) {
		if (fstat((*fd), &st) == -1)
			return -1;
		if ((st.st_size != SIZE_8KB) && strcmp(path, "/dev/urandom")) {
			fprintf(stderr, "Bad file size\n");
			errno = ECANCELED;
			return -1;
		}
	}

	if (errno == ENOTDIR)
		errno = 0;
	else if (errno != 0)
		return -1;

	return read((*fd), buf, size);
}

void
cmd_setmac(const char *strMac)
{
	uint8_t o, val8;
	uint16_t val16;
	int partnum, byte, nib;
	uint16_t mac[3] = {0, 0, 0};
	uint64_t total = 0;

	if (strnlen(strMac, 20) != 17)
		goto invalid_mac_address;

	for (o = 0; o < 16; o += 3) {
		if (o != 15)
			if (strMac[o + 2] != ':')
				goto invalid_mac_address;
		byte = o / 3;
		for (nib = 0; nib < 2; nib++, total += val8) {
			if ((val8 = hextonum(strMac[o + nib])) > 15) {
				if (errno != 0)
					return;
				goto invalid_mac_address;
			} else if ((byte == 0) && (nib == 1)) {
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
	static uint8_t *rbuf = NULL;
	static size_t rindex = BUFSIZ;

	if (rindex == BUFSIZ) {
		rindex = 0;
		if (rbuf == NULL)
			if ((rbuf = (uint8_t *) malloc(BUFSIZ)) == NULL)
				err(1, NULL);
		if (rfd != -1) {
			if (close(rfd))
				err(errno, "/dev/urandom");
			rfd = -1;
		}
		if (readFromFile(&rfd, rbuf, "/dev/urandom", O_RDONLY, BUFSIZ)
		    != BUFSIZ) {
			warn("%s", "/dev/urandom");
			return 16;
		}
		if (errno != 0)
			return 16;
	}

	return rbuf[rindex++] & 0xf;
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
	uint16_t val16 = 0;

	for (c = 0; c < 0x3F; c++)
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
	int part0, part1;

	part0 = validChecksum(0);
	part1 = validChecksum(1);

	if (part0 || part1) {
		for(part0 = 0; part0 < SIZE_4KB; part0++) {
			gbe[part0] ^= gbe[part1 = (part0 | SIZE_4KB)];
			gbe[part1] ^= gbe[part0];
			gbe[part0] ^= gbe[part1];
		}

		gbeFileModified = 1;
		nvmPartModified[0] = 1;
		nvmPartModified[1] = 1;

		errno = 0;
	}
}

void
cmd_copy(void)
{
	int src = (part << 12);

	int destPart = (part ^ 1);
	int dest = (destPart << 12);

	if (validChecksum(part)) {
		memcpy((gbe + dest), (gbe + src), SIZE_4KB);

		gbeFileModified = 1;
		nvmPartModified[destPart] = 1;
	}
}

int
validChecksum(int partnum)
{
	int w;
	uint16_t total = 0;

	for(w = 0; w <= 0x3F; w++)
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
	uint16_t val16 = ((uint16_t *) gbe)[pos16 + (partnum << 11)];
	if (!little_endian)
		byteswap((uint8_t *) &val16);

	return val16;
}

void
setWord(int pos16, int partnum, uint16_t val)
{
	((uint16_t *) gbe)[pos16 + (partnum << 11)] = val;
	if (!little_endian)
		byteswap(gbe + (pos16 << 1) + (partnum << 12));

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
	int partnum;
	errno = 0;

	if (pwrite((*fd), gbe, SIZE_8KB, 0) == SIZE_8KB)
		if (close((*fd)))
			err(errno, "%s", filename);
	if (errno != 0)
		return;

	for (partnum = 0; partnum < 2; partnum++) {
		if (nvmPartModified[partnum])
			printf("Part %d modified\n", partnum);
		else
			fprintf (stderr,
				"Part %d NOT modified\n", partnum);
	}
	printf("File `%s` successfully modified\n", filename);
}
