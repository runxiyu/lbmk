/* Copyright (c) 2022, 2023 Leah Rowe <info@minifree.org> */
/* SPDX-License-Identifier: MIT */

#include "nvmutil.h"

int
main(int argc, char *argv[])
{
	xpledge("stdio rpath wpath unveil", NULL);
	xunveil("/dev/urandom", "r");
	err_if((errno = argc < 3 ? EINVAL : errno));
	if ((flags = (strcmp(COMMAND, "dump") == 0) ? O_RDONLY : flags)
	    == O_RDONLY) {
		xunveil(FILENAME, "r");
		xpledge("stdio rpath", NULL);
	} else {
		xunveil(FILENAME, "rw");
		xpledge("stdio rpath wpath", NULL);
	}
	openFiles(FILENAME);
	xpledge("stdio", NULL);

	for (int i = 0; i < 6; i++)
		if (strcmp(COMMAND, op[i].str) == 0)
			if ((cmd = argc >= op[i].args ? op[i].cmd : NULL))
				break;
	if (cmd == cmd_setmac)
		strMac = (argc > 3) ? MAC_ADDRESS : strRMac;
	else if ((cmd != NULL) && (argc > 3))
		err_if((errno = (!((part = PARTNUM[0] - '0') == 0 || part == 1))
		    || PARTNUM[1] ? EINVAL : errno));
	err_if((errno = (cmd == NULL) ? EINVAL : errno));

	readGbeFile(FILENAME);
	(*cmd)();

	if ((gbeFileModified) && (flags != O_RDONLY))
		writeGbeFile(FILENAME);
	err_if((errno != 0) && (cmd != &cmd_dump));
	return errno;
}

void
openFiles(const char *path)
{
	struct stat st;
	xopen(fd, path, flags);
	if ((st.st_size != SIZE_8KB))
		err(errno = ECANCELED, "File `%s` not 8KiB", path);
	xopen(rfd, "/dev/urandom", O_RDONLY);
	errno = errno != ENOTDIR ? errno : 0;
}

void
readGbeFile(const char *path)
{
	nf = ((cmd == cmd_swap) || (cmd == cmd_copy)) ? SIZE_4KB : nf;
	skipread[part ^ 1] = (cmd == &cmd_copy) | (cmd == &cmd_setchecksum)
	    | (cmd == &cmd_brick);
	gbe[1] = (gbe[0] = (size_t) buf) + SIZE_4KB;
	for (int p = 0; p < 2; p++) {
		if (skipread[p])
			continue;
		xpread(fd, (uint8_t *) gbe[p], nf, p << 12, path);
		handle_endianness(p);
	}
}

void
cmd_setmac(void)
{
	if (invalidMacAddress(strMac, mac))
		err(errno = ECANCELED, "Bad MAC address");
	for (int partnum = 0; partnum < 2; partnum++) {
		if (!validChecksum(part = partnum))
			continue;
		for (int w = 0; w < 3; w++)
			setWord(w, partnum, mac[w]);
		cmd_setchecksum();
	}
}

int
invalidMacAddress(const char *strMac, uint16_t *mac)
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
		xpread(rfd, (uint8_t *) &rnum, (n = 15) + 1, 0, "/dev/urandom");
	return rnum[n--] & 0xf;
}

void
cmd_dump(void)
{
	for (int partnum = 0, numInvalid = 0; partnum < 2; partnum++) {
		if (!validChecksum(partnum))
			++numInvalid;
		printf("MAC (part %d): ", partnum);
		showmac(partnum), hexdump(partnum);
		errno = ((numInvalid < 2) && (partnum)) ? 0 : errno;
	}
}

void
showmac(int partnum)
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
			printf(" %02x%02x", val16 >> 8, val16 & 0xff);
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
	if (validChecksum(part))
		setWord(0x3F, part, (word(0x3F, part)) ^ 0xFF);
}

void
cmd_swap(void)
{
	if ((gbeFileModified = nvmPartModified[0] = nvmPartModified[1]
	    = validChecksum(1) | validChecksum(0)))
		xorswap(gbe[0], gbe[1]); /* speedhack: swap ptr, not words */
}

void
cmd_copy(void)
{
	if ((gbeFileModified = nvmPartModified[part ^ 1] = validChecksum(part)))
		gbe[part ^ 1] = gbe[part]; /* speedhack: copy ptr, not words */
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
xorswap_buf(int partnum)
{
	uint8_t *nbuf = (uint8_t *) gbe[partnum];
	for (size_t w = 0; w < (nf >> 1); w++)
		xorswap(nbuf[w << 1], nbuf[(w << 1) + 1]);
}

void
writeGbeFile(const char *filename)
{
	errno = 0;
	for (int x = gbe[0] > gbe[1] ? 1 : 0, p = 0; p < 2; p++, x ^= 1) {
		if (!nvmPartModified[x])
			continue;
		handle_endianness(x);
		xpwrite(fd, (uint8_t *) gbe[x], nf, x << 12, filename);
	}
	xclose(fd, filename);
}
