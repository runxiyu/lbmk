# 
# Makefile for compatibility purposes
# You can use this, but it's recommended to run build system commands directly
#
# See docs/maintain/ and docs/git/ for information about the build system
#
# Copyright (C) 2020, 2021 Leah Rowe <info@minifree.org>
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

.PHONY: all download modules ich9m-descriptors payloads roms release clean \
	crossgcc-clean install-dependencies-ubuntu

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
	./build clean rom_images
	./build clean tianocore

crossgcc-clean:
	./build clean crossgcc

install-dependencies-ubuntu:
	./build dependencies ubuntu2004
