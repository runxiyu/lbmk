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
void cmd_setmac(void);
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

uint16_t buf16[SIZE_4KB], mac[3] = {0, 0, 0};
uint8_t *buf = (uint8_t *) &buf16;
size_t nf = 128, gbe[2];
uint8_t nvmPartModified[2] = {0, 0}, skipread[2] = {0, 0};
int endian = 1, flags = O_RDWR, rfd, fd, part, gbeFileModified = 0;

const char *strMac = NULL, *strRMac = "??:??:??:??:??:??";

typedef struct op {
	char *str;
	void (*cmd)(void);
	int args;
} op_t;
op_t op[] = {
{ .str = "dump", .cmd = cmd_dump, .args = 3},
{ .str = "setmac", .cmd = cmd_setmac, .args = 3},
{ .str = "swap", .cmd = cmd_swap, .args = 3},
{ .str = "copy", .cmd = cmd_copy, .args = 4},
{ .str = "brick", .cmd = cmd_brick, .args = 4},
{ .str = "setchecksum", .cmd = cmd_setchecksum, .args = 4},
};
void (*cmd)(void) = NULL;

#define ERR() errno = errno ? errno : ECANCELED
#define err_if(x) if (x) err(ERR(), NULL)

#define xopen(f,l,p) if (opendir(l) != NULL) err(errno = EISDIR, "%s", l); \
	if ((f = open(l, p)) == -1) err(ERR(), "%s", l); \
	if (fstat(f, &st) == -1) err(ERR(), "%s", l)
#define xpread(f, b, n, o, l) if (pread(f, b, n, o) == -1) err(ERR(), "%s", l)
#define handle_endianness(r) if (((uint8_t *) &endian)[0] ^ 1) xorswap_buf(r)
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
