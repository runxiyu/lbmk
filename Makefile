# 
# Makefile for meme purposes
# You can use this, but it just runs lbmk commands.
#
# See docs/maintain/ and docs/git/ for information about the build system:
# https://libreboot.org/docs/maintain/
# https://libreboot.org/docs/build/
#
# Copyright (C) 2020, 2021, 2023 Leah Rowe <info@minifree.org>
# Copyright (C) 2022 Ferass El Hafidi <vitali64pmemail@protonmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

.POSIX:

#.PHONY: all check download modules ich9m-descriptors payloads roms release \
#	clean crossgcc-clean install-dependencies-ubuntu \
#	install-dependencies-debian install-dependencies-arch \
#	install-dependencies-void install-dependencies-fedora38 \
#	install-dependencies-parabola

all: roms

download:
	./download all

modules:
	./build module all

ich9m-descriptors:
	./build descriptors ich9m

payloads:
	./build payload all

roms:
	./build boot roms all

release:
	./build release src
	./build release roms

clean:
	./build clean cbutils
	./build clean flashrom
	./build clean ich9utils
	./build clean payloads
	./build clean seabios
	./build clean grub
	./build clean memtest86plus
	./build clean rom_images
	./build clean u-boot
	./build clean bios_extract

crossgcc-clean:
	./build clean crossgcc

install-dependencies-ubuntu:
	./build dependencies ubuntu2004

install-dependencies-debian:
	./build dependencies debian

install-dependencies-arch:
	./build dependencies arch

install-dependencies-void:
	./build dependencies void

install-dependencies-fedora38:
	./build dependencies fedora38

install-dependencies-parabola:
	./build dependencies parabola
