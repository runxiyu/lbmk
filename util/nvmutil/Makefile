# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2022,2025 Leah Rowe <leah@libreboot.org>
# SPDX-FileCopyrightText: 2023 Riku Viitanen <riku.viitanen@protonmail.com>

CC?=cc
CFLAGS?=-Os -Wall -Wextra -Werror -pedantic
PREFIX?=/usr/bin

nvm: nvmutil.c
	$(CC) $(CFLAGS) nvmutil.c -o nvm

install: nvm
	install nvm $(PREFIX)/nvm

uninstall: clean
	rm -f $(PREFIX)/nvm

distclean:
	rm -f nvm

clean:
	rm -f nvm
