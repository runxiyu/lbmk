/* Copyright (c) 2022, 2023 Leah Rowe <info@minifree.org> */
/* SPDX-License-Identifier: MIT */

void readGbeFile(int *fd, const char *path, int flags,
	size_t nr);
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
void xorswap_buf(int n, int partnum);
void writeGbeFile(int *fd, const char *filename, size_t nw);

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

int part, gbeFileModified = 0;
uint8_t nvmPartModified[2] = {0, 0};

uint16_t test;
uint8_t big_endian;

#define word(pos16, partnum) buf16[pos16 + (partnum << 11)]
#define ERR() errno = errno ? errno : ECANCELED
#define xorswap(x, y) x ^= y, y ^= x, x ^= y
#define xopen(fd, loc, p) if ((fd = open(loc, p)) == -1) err(ERR(), "%s", loc)
#define err_if(x) if (x) err(ERR(), NULL)

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
