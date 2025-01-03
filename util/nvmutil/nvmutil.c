/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2022-2025 Leah Rowe <leah@libreboot.org> */
/* Copyright (c) 2023 Riku Viitanen <riku.viitanen@protonmail.com> */

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

void cmd_setchecksum(void), cmd_brick(void), swap(int partnum), writeGbe(void),
    cmd_dump(void), cmd_setmac(void), readGbe(void), cmd_copy(void),
    macf(int partnum), hexdump(int partnum), openFiles(const char *path);
int macAddress(const char *strMac, uint16_t *mac), goodChecksum(int partnum);
uint8_t hextonum(char chs), rhex(void);

#define COMMAND argv[2]
#define MAC_ADDRESS argv[3]
#define PARTN argv[3]
#define SIZE_4KB 0x1000

uint16_t buf16[SIZE_4KB], mac[3] = {0, 0, 0};
uint8_t *buf = (uint8_t *) &buf16;
size_t nf = 128, gbe[2];
uint8_t nvmPartChanged[2] = {0, 0}, skipread[2] = {0, 0};
int e = 1, flags = O_RDWR, rfd, fd, part, gbeFileChanged = 0;

const char *strMac = NULL, *strRMac = "??:??:??:??:??:??", *filename = NULL;

typedef struct op {
	char *str;
	void (*cmd)(void);
	int args;
} op_t;
op_t op[] = {
{ .str = "dump", .cmd = cmd_dump, .args = 3},
{ .str = "setmac", .cmd = cmd_setmac, .args = 3},
{ .str = "swap", .cmd = writeGbe, .args = 3},
{ .str = "copy", .cmd = cmd_copy, .args = 4},
{ .str = "brick", .cmd = cmd_brick, .args = 4},
{ .str = "setchecksum", .cmd = cmd_setchecksum, .args = 4},
};
void (*cmd)(void) = NULL;

#define ERR() errno = errno ? errno : ECANCELED
#define err_if(x) if (x) err(ERR(), "%s", filename)

#define xopen(f,l,p) if (opendir(l) != NULL) err(errno = EISDIR, "%s", l); \
    if ((f = open(l, p)) == -1) err(ERR(), "%s", l); \
    if (fstat(f, &st) == -1) err(ERR(), "%s", l)

#define word(pos16, partnum) buf16[pos16 + (partnum << 11)]
#define setWord(pos16, p, val16) if ((gbeFileChanged = 1) && \
    word(pos16, p) != val16) nvmPartChanged[p] = 1 | (word(pos16, p) = val16)

int
main(int argc, char *argv[])
{
	if (argc < 3) {
		fprintf(stderr, "USAGE:\n");
		fprintf(stderr, " %s FILE dump\n", argv[0]);
		fprintf(stderr, " %s FILE setmac [MAC]\n", argv[0]);
		fprintf(stderr, " %s FILE swap\n", argv[0]);
		fprintf(stderr, " %s FILE copy 0|1\n", argv[0]);
		fprintf(stderr, " %s FILE brick 0|1\n", argv[0]);
		fprintf(stderr, " %s FILE setchecksum 0|1\n", argv[0]);
		err(errno = ECANCELED, "Too few arguments");
	}
	flags = (strcmp(COMMAND, "dump") == 0) ? O_RDONLY : flags;
	filename = argv[1];
#ifdef __OpenBSD__
	err_if(unveil("/dev/urandom", "r") == -1);
	if (flags == O_RDONLY) {
		err_if(unveil(filename, "r") == -1);
		err_if(pledge("stdio rpath", NULL) == -1);
	} else {
		err_if(unveil(filename, "rw") == -1);
		err_if(pledge("stdio rpath wpath", NULL) == -1);
	}
#endif
	openFiles(filename);
#ifdef __OpenBSD__
	err_if(pledge("stdio", NULL) == -1);
#endif

	for (int i = 0; i < 6; i++)
		if (strcmp(COMMAND, op[i].str) == 0)
			if ((cmd = argc >= op[i].args ? op[i].cmd : NULL))
				break;
	if (cmd == cmd_setmac)
		strMac = (argc > 3) ? MAC_ADDRESS : strRMac;
	else if ((cmd != NULL) && (argc > 3))
		err_if((errno = (!((part = PARTN[0] - '0') == 0 || part == 1))
		    || PARTN[1] ? EINVAL : errno));
	err_if((errno = (cmd == NULL) ? EINVAL : errno));

	readGbe();
	(*cmd)();

	if ((gbeFileChanged) && (flags != O_RDONLY) && (cmd != writeGbe))
		writeGbe();
	err_if((errno != 0) && (cmd != cmd_dump));
	return errno;
}

void
openFiles(const char *path)
{
	struct stat st;
	xopen(fd, path, flags);
	if ((st.st_size != (SIZE_4KB << 1)))
		err(errno = ECANCELED, "File `%s` not 8KiB", path);
	xopen(rfd, "/dev/urandom", O_RDONLY);
	errno = errno != ENOTDIR ? errno : 0;
}

void
readGbe(void)
{
	nf = ((cmd == writeGbe) || (cmd == cmd_copy)) ? SIZE_4KB : nf;
	skipread[part ^ 1] = (cmd == cmd_copy) | (cmd == cmd_setchecksum)
	    | (cmd == cmd_brick);
	gbe[1] = (gbe[0] = (size_t) buf) + SIZE_4KB;
	for (int p = 0; p < 2; p++) {
		if (skipread[p])
			continue;
		err_if(pread(fd, (uint8_t *) gbe[p], nf, p << 12) == -1);
		swap(p);
	}
}

void
cmd_setmac(void)
{
	if (macAddress(strMac, mac))
		err(errno = ECANCELED, "Bad MAC address");
	for (int partnum = 0; partnum < 2; partnum++) {
		if (!goodChecksum(part = partnum))
			continue;
		for (int w = 0; w < 3; w++)
			setWord(w, partnum, mac[w]);
		cmd_setchecksum();
	}
}

int
macAddress(const char *strMac, uint16_t *mac)
{
	uint64_t total = 0;
	if (strnlen(strMac, 20) == 17) {
	for (uint8_t h, i = 0; i < 16; i += 3) {
		if (i != 15)
			if (strMac[i + 2] != ':')
				return 1;
		int byte = i / 3;
		for (int nib = 0; nib < 2; nib++, total += h) {
			if ((h = hextonum(strMac[i + nib])) > 15)
				return 1;
			if ((byte == 0) && (nib == 1))
				if (strMac[i + nib] == '?')
					h = (h & 0xE) | 2; /* local, unicast */
			mac[byte >> 1] |= ((uint16_t ) h)
			    << ((8 * (byte % 2)) + (4 * (nib ^ 1)));
		}
	}}
	return ((total == 0) | (mac[0] & 1)); /* multicast/all-zero banned */
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
	return (ch == '?') ? rhex() : 16;
}

uint8_t
rhex(void)
{
	static uint8_t n = 0, rnum[16];
	if (!n)
		err_if(pread(rfd, (uint8_t *) &rnum, (n = 15) + 1, 0) == -1);
	return rnum[n--] & 0xf;
}

void
cmd_dump(void)
{
	for (int partnum = 0, numInvalid = 0; partnum < 2; partnum++) {
		if (!goodChecksum(partnum))
			++numInvalid;
		printf("MAC (part %d): ", partnum);
		macf(partnum), hexdump(partnum);
		errno = ((numInvalid < 2) && (partnum)) ? 0 : errno;
	}
}

void
macf(int partnum)
{
	for (int c = 0; c < 3; c++) {
		uint16_t val16 = word(c, partnum);
		printf("%02x:%02x", val16 & 0xff, val16 >> 8);
		printf(c == 2 ? "\n" : ":");
	}
}

void
hexdump(int partnum)
{
	for (int row = 0; row < 8; row++) {
		printf("%07x", row << 4);
		for (int c = 0; c < 8; c++) {
			uint16_t val16 = word((row << 3) + c, partnum);
			printf(" %02x%02x", val16 & 0xff, val16 >> 8);
		} printf("\n");
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
	if (goodChecksum(part))
		setWord(0x3F, part, ((word(0x3F, part)) ^ 0xFF));
}

void
cmd_copy(void)
{
	if ((gbeFileChanged = nvmPartChanged[part ^ 1] = goodChecksum(part)))
		gbe[part ^ 1] = gbe[part]; /* speedhack: copy ptr, not words */
}

int
goodChecksum(int partnum)
{
	uint16_t total = 0;
	for(int w = 0; w <= 0x3F; w++)
		total += word(w, partnum);
	if (total == 0xBABA)
		return 1;
	fprintf(stderr, "WARNING: BAD checksum in part %d\n", partnum);
	return (errno = ECANCELED) & 0;
}

void
writeGbe(void)
{
	err_if((cmd == writeGbe) && !(goodChecksum(0) || goodChecksum(1)));
	for (int p = 0, x = (cmd == writeGbe) ? 1 : 0; p < 2; p++) {
		if ((!nvmPartChanged[p]) && (cmd != writeGbe))
			continue;
		swap(p^x);
		err_if(pwrite(fd, (uint8_t *) gbe[p^x], nf, p << 12) == -1);
	}
	errno = 0;
	err_if(close(fd) == -1);
}

void
swap(int partnum)
{
	size_t w, x;
	uint8_t *n = (uint8_t *) gbe[partnum];
	for (w = nf * ((uint8_t *) &e)[0], x = 1; w < nf; w += 2, x += 2)
		n[w] ^= n[x], n[x] ^= n[w], n[w] ^= n[x];
}
