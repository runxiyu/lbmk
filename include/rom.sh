#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2014-2016,2020-2021,2023-2024 Leah Rowe <leah@libreboot.org>
# Copyright (c) 2021-2022 Ferass El Hafidi <vitali64pmemail@protonmail.com>
# Copyright (c) 2022 Caleb La Grange <thonkpeasant@protonmail.com>
# Copyright (c) 2022-2023 Alper Nebi Yasak <alpernebiyasak@gmail.com>
# Copyright (c) 2023 Riku Viitanen <riku.viitanen@protonmail.com>

mkserprog()
{
	[ "$_f" = "-d" ] && return 0 # dry run
	basename -as .h "$serdir/"*.h > "$TMPDIR/ser" || $err "!mk $1 $TMPDIR"

	while read -r sertarget; do
		[ "$1" = "rp2040" ] && x_ cmake -DPICO_BOARD="$sertarget" \
		    -DPICO_SDK_PATH="$picosdk" -B "$sersrc/build" "$sersrc" \
		    && x_ cmake --build "$sersrc/build"
		[ "$1" = "stm32" ] && x_ make -C "$sersrc" \
		    libopencm3-just-make BOARD=$sertarget && x_ make -C \
		    "$sersrc" BOARD=$sertarget; x_ mkdir -p "bin/serprog_$1"
		x_ mv "$serx" "bin/serprog_$1/serprog_$sertarget.${serx##*.}"
	done < "$TMPDIR/ser"

	[ "$XBMK_RELEASE" = "y" ] && mkrom_tarball "bin/serprog_$1"; return 0
}

mkpayload_grub()
{
	[ "$_f" = "-d" ] && return 0 # dry run
	eval `setvars "" grub_modules grub_install_modules`
	eval `setcfg "$grubdata/module/$tree"`

	x_ rm -f "$cdir/grub.elf"

	"${cdir}/grub-mkstandalone" --grub-mkimage="${cdir}/grub-mkimage" \
	    -O i386-coreboot -o "${cdir}/grub.elf" -d "${cdir}/grub-core/" \
	    --fonts= --themes= --locales=  --modules="$grub_modules" \
	    --install-modules="$grub_install_modules" \
	    "/boot/grub/grub_default.cfg=${cdir}/.config" \
	    "/boot/grub/grub.cfg=$grubdata/memdisk.cfg" \
	    "/background.png=$grubdata/background/background1280x800.png" || \
	    $err "$tree: cannot build grub.elf"; return 0
}

check_coreboot_utils()
{
	for util in cbfstool ifdtool; do
		utilelfdir="elf/$util/$1"
		utilsrcdir="src/coreboot/$1/util/$util"

		utilmode="" && [ -n "$mode" ] && utilmode="clean"
		x_ make -C "$utilsrcdir" $utilmode -j$XBMK_THREADS $makeargs
		[ -z "$mode" ] && [ ! -f "$utilelfdir/$util" ] && \
			x_ mkdir -p "$utilelfdir" && \
			x_ cp "$utilsrcdir/$util" "elf/$util/$1"
		[ -z "$mode" ] || x_ rm -Rf "$utilelfdir"; continue
	done; return 0
}

mkvendorfiles()
{
	if [ "$_f" = "-d" ]; then
		check_coreboot_utils "$tree"
	elif [ "$_f" = "-b" ]; then
		printf "%s\n" "${version%%-*}" > "$cdir/.coreboot-version"
	fi
	[ -z "$mode" ] && [ "$target" != "$tree" ] && \
	    x_ ./vendor download $target; return 0
}

mkcorebootbin()
{
	[ "$_f" = "-d" ] && return 0 # dry run
	[ "$target" = "$tree" ] && return 0

	tmprom="$cdir/build/coreboot.rom"
	initmode="${defconfig##*/}"; displaymode="${initmode##*_}"
	initmode="${initmode%%_*}"
	[ -n "$displaymode" ] && displaymode="_$displaymode"
	cbfstool="elf/cbfstool/$tree/cbfstool"

	[ -n "$uboot_config" ] || uboot_config="default"
	[ "$payload_uboot" = "y" ] || payload_seabios="y"
	[ "$payload_grub" = "y" ] && payload_seabios="y"
	[ "$payload_seabios" = "y" ] && [ "$payload_uboot" = "y" ] && \
	    $err "$target: U-Boot and SeaBIOS/GRUB are both enabled."

	[ -z "$grub_scan_disk" ] && grub_scan_disk="nvme ahci ata"

	[ -n "$grubtree" ] || grubtree="default"
	grubelf="elf/grub/$grubtree/payload/grub.elf"

	[ "$payload_memtest" = "y" ] || payload_memtest="n"
	[ "$(uname -m)" = "x86_64" ] || payload_memtest="n"

	x_ ./update trees -d coreboot $tree

	[ "$payload_seabios" = "y" ] && pname="seabios" && add_seabios
	[ "$payload_uboot" = "y" ] && pname="uboot" && add_uboot

	newrom="bin/$target/${pname}_${target}_$initmode$displaymode.rom"
	x_ mkdir -p "${newrom%/*}"; x_ mv "$tmprom" "$newrom"

	[ "$XBMK_RELEASE" = "y" ] || return 0
	mksha512sum "$newrom" "vendorhashes"
	./vendor inject -r "$newrom" -b "$target" -n nuke || $err "!n $newrom"
}

add_seabios()
{
	_seabioself="elf/seabios/default/$initmode/bios.bin.elf"

	cbfs "$tmprom" "$_seabioself" "fallback/payload"
	x_ "$cbfstool" "$tmprom" add-int -i 3000 -n etc/ps2-keyboard-spinup

	_z="2"; [ "$initmode" = "vgarom" ] && _z="0"
	x_ "$cbfstool" "$tmprom" add-int -i $_z -n etc/pci-optionrom-exec
	x_ "$cbfstool" "$tmprom" add-int -i 0 -n etc/optionroms-checksum
	[ "$initmode" = "libgfxinit" ] && \
	    cbfs "$tmprom" "$seavgabiosrom" vgaroms/seavgabios.bin raw

	[ "$payload_memtest" = "y" ] && cbfs "$tmprom" \
	    "elf/memtest86plus/memtest.bin" img/memtest

	[ "$payload_grub" = "y" ] && pname="seagrub" && add_grub; return 0
}

add_grub()
{
	cbfs "$tmprom" "$grubelf" "img/grub2"
	printf "set grub_scan_disk=\"%s\"\n" "$grub_scan_disk" \
	    > "$TMPDIR/tmpcfg" || $err "$target: !insert scandisk"
	cbfs "$tmprom" "$TMPDIR/tmpcfg" scan.cfg raw
	cbfs "$tmprom" "$grubdata/bootorder" bootorder raw
}

add_uboot()
{
	ubdir="elf/u-boot/$target/$uboot_config"
	ubootelf="$ubdir/u-boot.elf" && [ ! -f "$ubootelf" ] && \
	    ubootelf="$ubdir/u-boot"
	[ -f "$ubootelf" ] || $err "cb/$target: Can't find u-boot"

	cbfs "$tmprom" "$ubootelf" "fallback/payload"
}

mkcoreboottar()
{
	[ "$_f" = "-d" ] && return 0 # dry run
	[ "$target" = "$tree" ] && return 0; [ "$XBMK_RELEASE" = "y" ] && \
	    [ "$release" != "n" ] && mkrom_tarball "bin/$target"; return 0
}
