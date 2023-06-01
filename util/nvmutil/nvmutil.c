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

#include "nvmutil.h"

int
main(int argc, char *argv[])
{
	xpledge("stdio rpath wpath unveil", NULL);
	size_t nr = 128;
	int fd, flags = O_RDWR;
	void (*cmd)(void) = NULL;
	const char *strMac = NULL, *strRMac = "??:??:??:??:??:??";
	buf = (uint8_t *) &buf16;
	gbe[1] = (gbe[0] = (size_t) buf) + SIZE_4KB;

	test = 1;
	big_endian = ((uint8_t *) &test)[0] ^ 1;

	if (argc == 3) {
		if (strcmp(COMMAND, "dump") == 0) {
			xpledge("stdio rpath unveil", NULL);
			flags = O_RDONLY;
			cmd = &cmd_dump;
		} else if (strcmp(COMMAND, "setmac") == 0) {
			strMac = (char *) strRMac; /* random mac address */
		} else if (strcmp(COMMAND, "swap") == 0) {
			cmd = &cmd_swap;
			nr = SIZE_4KB;
		}
	} else if (argc == 4) {
		if (strcmp(COMMAND, "setmac") == 0) {
			strMac = MAC_ADDRESS; /* user-supplied mac address */
		} else if ((!((part = PARTNUM[0] - '0') == 0 || part == 1))
		|| PARTNUM[1]) { /* only allow '1' or '0' */
			errno = EINVAL;
		} else if (strcmp(COMMAND, "setchecksum") == 0) {
			cmd = &cmd_setchecksum;
		} else if (strcmp(COMMAND, "brick") == 0) {
			cmd = &cmd_brick;
		} else if (strcmp(COMMAND, "copy") == 0) {
			cmd = &cmd_copy;
			nr = SIZE_4KB;
		}
	}

	err_if((errno = ((strMac == NULL) && (cmd == NULL)) ? EINVAL : errno));

	skipread[part ^ 1] = (cmd == &cmd_copy) |
		(cmd == &cmd_setchecksum) | (cmd == &cmd_brick);
	readGbeFile(&fd, FILENAME, flags, nr);
	(void)rhex();
	xunveil("/dev/urandom", "r");
	if (flags == O_RDONLY) {
		xpledge("stdio", NULL);
	} else {
		xpledge("stdio wpath unveil", NULL);
		xunveil(FILENAME, "w");
	}

	if (strMac != NULL)
		cmd_setmac(strMac); /* nvm gbe.bin setmac */
	else if (cmd != NULL)
		(*cmd)(); /* all other commands except setmac */
	writeGbeFile(&fd, FILENAME, nr);

	err_if((errno != 0) && (cmd != &cmd_dump));
	return errno;
}

void
readGbeFile(int *fd, const char *path, int flags, size_t nr)
{
	struct stat st;
	if (opendir(path) != NULL)
		err(errno = EISDIR, "%s", path);
	xopen(*fd, path, flags);
	if (fstat((*fd), &st) == -1)
		err(ERR(), "%s", path);
	else if ((st.st_size != SIZE_8KB))
		err(errno = ECANCELED, "File `%s` not 8KiB", path);
	else if (errno == ENOTDIR)
		errno = 0;

	for (int p = 0; p < 2; p++) {
		if (skipread[p])
			continue;
		if (pread((*fd), (uint8_t *) gbe[p], nr, p << 12) == -1)
			err(ERR(), "%s", path);
		if (big_endian)
			xorswap_buf(nr, p);
	}
}

void
cmd_setmac(const char *strMac)
{
	uint16_t mac[3] = {0, 0, 0};
	if (invalidMacAddress(strMac, mac))
		err(errno = ECANCELED, "Bad MAC address");

	for (int partnum = 0; partnum < 2; partnum++) {
		if (validChecksum(part = partnum)) {
			for (int w = 0; w < 3; w++)
				setWord(w, partnum, mac[w]);
			cmd_setchecksum();
		}
	}
}

int
invalidMacAddress(const char *strMac, uint16_t *mac)
{
	uint8_t h;
	uint64_t total = 0;
	if (strnlen(strMac, 20) == 17) {
	for (int i = 0; i < 16; i += 3) {
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
	else if (ch == '?')
		return rhex(); /* random number */
	else
		return 16;
}

uint8_t
rhex(void)
{
	static int rfd = -1, n = 0;
	static uint8_t rnum[16];
	if (!n) {
		if (rfd == -1)
			xopen(rfd, "/dev/urandom", O_RDONLY);
		if (read(rfd, (uint8_t *) &rnum, (n = 15) + 1) == -1)
			err(ERR(), "/dev/urandom");
	}
	return rnum[n--] & 0xf;
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
			printf(" %02x%02x", val16 >> 8, val16 & 0xff);
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
	xorswap(gbe[0], gbe[1]); /* speedhack: swap ptr, not words */
	gbeFileModified = nvmPartModified[0] = nvmPartModified[1]
		= validChecksum(1) | validChecksum(0);
}

void
cmd_copy(void)
{
	gbe[part ^ 1] = gbe[part]; /* speedhack: copy ptr, not words */
	gbeFileModified = nvmPartModified[part ^ 1] = validChecksum(part);
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
	return (errno = ECANCELED) & 0;
}

void
setWord(int pos16, int partnum, uint16_t val16)
{
	if ((gbeFileModified = 1) && word(pos16, partnum) != val16)
		nvmPartModified[partnum] = 1 | (word(pos16, partnum) = val16);
}

void
xorswap_buf(int n, int partnum)
{
	uint8_t *nbuf = (uint8_t *) gbe[partnum];
	for (int w = 0; w < (n >> 1); w++)
		xorswap(nbuf[w << 1], nbuf[(w << 1) + 1]);
}

void
writeGbeFile(int *fd, const char *filename, size_t nw)
{
	if (gbeFileModified)
		errno = 0;
	for (int p = 0; p < 2; p++) {
		if (gbe[0] > gbe[1])
			p ^= 1; /* speedhack: write sequentially on-disk */
		if (!nvmPartModified[p])
			goto next_part;
		if (big_endian)
			xorswap_buf(nw, p);
		if (pwrite((*fd), (uint8_t *) gbe[p], nw, p << 12) == -1)
			err(ERR(), "%s", filename);
next_part:
		if (gbe[0] > gbe[1])
			p ^= 1; /* speedhack: write sequentially on-disk */
	}
	if (close((*fd)))
		err(ERR(), "%s", filename);
	xpledge("stdio", NULL);
}

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
