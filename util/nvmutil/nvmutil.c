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
#ifdef HAVE_PLEDGE
#include <err.h>
#endif

ssize_t readFromFile(int *fd, uint8_t *buf, const char *path, int flags,
	size_t size);
void setmac(const char *strMac);
void cmd(const char *command);
int validChecksum(int partnum);
uint16_t word(int pos16, int partnum);
void setWord(int pos16, int partnum, uint16_t val);
void byteswap(uint8_t *byte);

#define FILENAME argv[1]
#define COMMAND argv[2]
#define MAC_ADDRESS argv[3]
#define PARTNUM argv[3]
#define SIZE_4KB 0x1000
#define SIZE_8KB 0x2000

uint8_t gbe[SIZE_8KB];
int part, modified = 0;

uint16_t test;
uint8_t little_endian;

int
main(int argc, char *argv[])
{
	int fd;
	int flags = O_RDWR;
	char *strMac = NULL;
	char *strRMac = "??:??:??:??:??:??";

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
		} else if (strcmp(COMMAND, "setmac") == 0) {
			strMac = strRMac;
		}
	} else if (argc == 4) {
		if (strcmp(COMMAND, "setmac") == 0)
			strMac = MAC_ADDRESS;
		else if ((!((part = PARTNUM[0] - '0') == 0 || part == 1))
				|| PARTNUM[1])
			errno = EINVAL;
	} else
		errno = EINVAL;

	if (errno != 0)
		goto nvmutil_exit;

	if (readFromFile(&fd, gbe, FILENAME, flags, SIZE_8KB)
		== SIZE_8KB)
	{
		if (strMac != NULL)
			setmac(strMac);
		else
			cmd(COMMAND);

		if (modified) {
			errno = 0;
			if (pwrite(fd, gbe, SIZE_8KB, 0) == SIZE_8KB)
				close(fd);
		}
	}

nvmutil_exit:
	if (errno == ENOTDIR)
		errno = 0;
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
		fstat((*fd), &st);
		if (st.st_size != SIZE_8KB) {
			fprintf(stderr, "Bad file size\n");
			errno = ECANCELED;
			return -1;
		}
	}
	return read((*fd), buf, size);
}

void
setmac(const char *strMac)
{
	uint8_t rmac[12];
	uint8_t o, ch, val8;
	uint16_t val16;
	int macfd, partnum, random, byte, nib;
	uint16_t mac[3] = {0, 0, 0};
	uint64_t total = 0;

	if (readFromFile(&macfd, rmac, "/dev/urandom", O_RDONLY, 12) != 12)
		return;
	else if (strnlen(strMac, 20) != 17)
		goto invalid_mac_address;
	for (o = 0, random = 0; o < 16; o += 3) {
		if (o != 15)
			if (strMac[o + 2] != ':')
				goto invalid_mac_address;
		byte = o / 3;
		for (nib = 0; nib < 2; nib++, total += val8) {
			ch = strMac[o + nib];
			if ((ch >= '0') && ch <= '9') {
				val8 = ch - '0';
			} else if ((ch >= 'A') && (ch <= 'F')) {
				val8 = ch - 'A' + 10;
			} else if ((ch >= 'a') && (ch <= 'f')) {
				val8 = ch - 'a' + 10;
			} else if (ch == '?') {
				val8 = rmac[random++] & 0xf;
				if ((byte == 0 && (nib == 1))) {
					val8 &= 0xE;
					val8 |= 2;
				}
			} else {
				goto invalid_mac_address;
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
		if (validChecksum(partnum)) {
			for (o = 0; o < 3; o++)
				setWord(o, partnum, mac[o]);
			part = partnum;
			cmd("setchecksum");
		}
	}
	return;
invalid_mac_address:
	fprintf(stderr, "Bad MAC address\n");
	errno = ECANCELED;
	return;
}

void
cmd(const char *command)
{
	int c, partnum, part0, part1, row, numInvalid;
	uint8_t *byte;
	uint16_t val16;

	if (strcmp(command, "dump") == 0) {
		numInvalid = 0;
		for (partnum = 0; partnum < 2; partnum++) {
			if (!validChecksum(partnum))
				++numInvalid;

			printf("Part %d:\n", partnum);

			printf("MAC: ");
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
		if (numInvalid < 2) {
			errno = 0;
		}
	} else if (strcmp(command, "setchecksum") == 0) {
		val16 = 0;
		for (c = 0; c < 0x3F; c++)
			val16 += word(c, part);
		setWord(0x3F, part, 0xBABA - val16);
	} else if (strcmp(command, "brick") == 0) {
		if (validChecksum(part))
			setWord(0x3F, part, (word(0x3F, part)) ^ 0xFF);
	} else if (strcmp(command, "swap") == 0) {
		part0 = validChecksum(0);
		part1 = validChecksum(1);
		if ((modified = (part0 | part1))) {
			for(part0 = 0; part0 < SIZE_4KB; part0++) {
				gbe[part0] ^= gbe[part1 = (part0 | SIZE_4KB)];
				gbe[part1] ^= gbe[part0];
				gbe[part0] ^= gbe[part1];
			}
		}
	} else if (strcmp(command, "copy") == 0) {
		if (validChecksum(part))
			memcpy(gbe + ((part ^ (modified = 1)) << 12),
				gbe + (part << 12), SIZE_4KB);
	} else
		errno = EINVAL;
}

int
validChecksum(int partnum)
{
	int w;
	uint16_t total = 0;

	for(w = 0; w <= 0x3F; w++)
		total += word(w, partnum);

	if (total != 0xBABA) {
		fprintf(stderr, "BAD checksum in part %d\n", partnum);
		errno = ECANCELED;
		return 0;
	}
	return 1;
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
	modified = 1;
}

void
byteswap(uint8_t *byte) {
	byte[0] ^= byte[1];
	byte[1] ^= byte[0];
	byte[0] ^= byte[1];
}
