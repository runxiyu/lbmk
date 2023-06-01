/* Copyright (c) 2022, 2023 Leah Rowe <info@minifree.org> */
/* SPDX-License-Identifier: MIT */

#include <sys/stat.h>

#include <dirent.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void openFiles(const char *path);
void readGbeFile(const char *path);
void cmd_setmac(const char *strMac);
int invalidMacAddress(const char *strMac, uint16_t *mac);
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
void setWord(int pos16, int partnum, uint16_t val16);
void xorswap_buf(int partnum);
void writeGbeFile(const char *filename);

#define FILENAME argv[1]
#define COMMAND argv[2]
#define MAC_ADDRESS argv[3]
#define PARTNUM argv[3]
#define SIZE_4KB 0x1000
#define SIZE_8KB 0x2000

uint16_t buf16[SIZE_4KB];
uint8_t *buf = (uint8_t *) &buf16;
size_t nf = 128, gbe[2];
uint8_t skipread[2] = {0, 0};

int flags = O_RDWR, fd = -1, part, gbeFileModified = 0;
uint8_t nvmPartModified[2] = {0, 0};

int test = 1;
int big_endian;

#define ERR() errno = errno ? errno : ECANCELED
#define err_if(x) if (x) err(ERR(), NULL)

#define xopen(f,l,p) if (opendir(l) != NULL) err(errno = EISDIR, "%s", l); \
	if ((f = open(l, p)) == -1) err(ERR(), "%s", l); \
	struct stat st; if (fstat(f, &st) == -1) err(ERR(), "%s", l)
#define xpread(f, b, n, o, l) if (pread(f, b, n, o) == -1) err(ERR(), "%s", l)
#define handle_endianness() if (big_endian) xorswap_buf(p)
#define xpwrite(f, b, n, o, l) if (pwrite(f, b, n, o) == -1) err(ERR(), "%s", l)
#define xclose(f, l) if (close(f) == -1) err(ERR(), "%s", l)

#define xorswap(x, y) x ^= y, y ^= x, x ^= y
#define word(pos16, partnum) buf16[pos16 + (partnum << 11)]

void
xpledge(const char *promises, const char *execpromises)
{
	(void)promises; (void)execpromises;
#ifdef __OpenBSD__
	if (pledge(promises, execpromises) == -1)
		err(ERR(), "pledge");
#endif
}

void
xunveil(const char *path, const char *permissions)
{
	(void)path; (void)permissions;
#ifdef __OpenBSD__
	if (unveil(path, permissions) == -1)
		err(ERR(), "unveil");
#endif
}
