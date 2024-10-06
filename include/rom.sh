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

copyps1bios()
{
	x_ rm -Rf bin/playstation
	x_ mkdir -p bin/playstation
	x_ cp src/pcsx-redux/src/mips/openbios/openbios.bin bin/playstation
}

mkpayload_grub()
{
	eval `setvars "" grub_modules grub_install_modules`
	$dry eval `setcfg "$grubdata/module/$tree"`
	$dry x_ rm -f "$srcdir/grub.elf"; $dry \
	"$srcdir/grub-mkstandalone" --grub-mkimage="$srcdir/grub-mkimage" \
	    -O i386-coreboot -o "$srcdir/grub.elf" -d "${srcdir}/grub-core/" \
	    --fonts= --themes= --locales=  --modules="$grub_modules" \
	    --install-modules="$grub_install_modules" \
	    "/boot/grub/grub_default.cfg=${srcdir}/.config" \
	    "/boot/grub/grub.cfg=$grubdata/memdisk.cfg" \
	    "/background.png=$grubdata/background/background1280x800.png" || \
	    $err "$tree: cannot build grub.elf"; return 0
}

mkvendorfiles()
{
	[ -z "$mode" ] && $dry cook_coreboot_config
	check_coreboot_utils "$tree"
	printf "%s\n" "${version%%-*}" > "$srcdir/.coreboot-version" || \
	    $err "!mk $srcdir .coreboot-version"
	[ -z "$mode" ] && [ "$target" != "$tree" ] && \
	    x_ ./vendor download $target; return 0
}

cook_coreboot_config()
{
	[ -f "$srcdir/.config" ] || return 0
	printf "CONFIG_CCACHE=y\n" >> "$srcdir/.config" || \
	    $err "$srcdir/.config: Could not enable ccache"
	make -C "$srcdir" oldconfig || $err "Could not cook $srcdir/.config"; :
}

check_coreboot_utils()
{
	for util in cbfstool ifdtool; do
		[ "$badhash" = "y" ] && x_ rm -f "elf/$util/$1/$util"
		e "elf/$util/$1/$util" f && continue

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

mkcorebootbin()
{
	[ "$target" = "$tree" ] && return 0

	tmprom="$TMPDIR/coreboot.rom"
	$dry x_ cp "$srcdir/build/coreboot.rom" "$tmprom"

	initmode="${defconfig##*/}"; displaymode="${initmode##*_}"
	initmode="${initmode%%_*}"
	[ -n "$displaymode" ] && displaymode="_$displaymode"
	cbfstool="elf/cbfstool/$tree/cbfstool"

	[ -n "$uboot_config" ] || uboot_config="default"
	[ "$payload_uboot" = "y" ] || payload_seabios="y"
	[ "$payload_grub" = "y" ] && payload_seabios="y"
	[ "$payload_seabios" = "y" ] && [ "$payload_uboot" = "y" ] && \
	    $dry $err "$target: U-Boot and SeaBIOS/GRUB are both enabled."

	[ -z "$grub_scan_disk" ] && grub_scan_disk="nvme ahci ata"

	[ -n "$grubtree" ] || grubtree="default"
	grubelf="elf/grub/$grubtree/payload/grub.elf"

	[ "$payload_memtest" = "y" ] || payload_memtest="n"
	[ "$(uname -m)" = "x86_64" ] || payload_memtest="n"
	if $dry grep "CONFIG_PAYLOAD_NONE=y" "$defconfig"; then
		[ "$payload_seabios" = "y" ] && pname="seabios" && \
		    $dry add_seabios
		[ "$payload_uboot" = "y" ] && pname="uboot" && $dry add_uboot
	else
		pname="custom" && $dry cprom; :
	fi; :
}

add_seabios()
{
	[ -n "$seabiosname" ] || seabiosname="fallback/payload"
	_seabioself="elf/seabios/default/$initmode/bios.bin.elf"

	cbfs "$tmprom" "$_seabioself" "$seabiosname"
	x_ "$cbfstool" "$tmprom" add-int -i 3000 -n etc/ps2-keyboard-spinup

	_z="2"; [ "$initmode" = "vgarom" ] && _z="0"
	x_ "$cbfstool" "$tmprom" add-int -i $_z -n etc/pci-optionrom-exec
	x_ "$cbfstool" "$tmprom" add-int -i 0 -n etc/optionroms-checksum
	[ "$initmode" = "libgfxinit" ] && \
	    cbfs "$tmprom" "$seavgabiosrom" vgaroms/seavgabios.bin raw

	[ "$payload_memtest" = "y" ] && cbfs "$tmprom" \
	    "elf/memtest86plus/memtest.bin" img/memtest

	[ "$payload_grub" = "y" ] && add_grub

	[ "$seabiosname" = "fallback/payload" ] && cprom
	[ "$payload_grub" = "y" ] && pname="seagrub" && mkseagrub; :
}

add_grub()
{
	[ -n "$grubname" ] || grubname="img/grub2"
	cbfs "$tmprom" "$grubelf" "$grubname"
	printf "set grub_scan_disk=\"%s\"\n" "$grub_scan_disk" \
	    > "$TMPDIR/tmpcfg" || $err "$target: !insert scandisk"
	cbfs "$tmprom" "$TMPDIR/tmpcfg" scan.cfg raw
}

mkseagrub()
{
	[ "$grubname" = "fallback/payload" ] && pname="grub"
	cbfs "$tmprom" "$grubdata/bootorder" bootorder raw
	for keymap in config/data/grub/keymap/*.gkb; do
		[ -f "$keymap" ] && cprom "${keymap##*/}"; :
	done; :
}

add_uboot()
{
	ubdir="elf/u-boot/$target/$uboot_config"
	ubootelf="$ubdir/u-boot.elf" && [ ! -f "$ubootelf" ] && \
	    ubootelf="$ubdir/u-boot"
	[ -f "$ubootelf" ] || $err "cb/$target: Can't find u-boot"

	cbfs "$tmprom" "$ubootelf" "fallback/payload"; cprom
}

cprom()
{
	newrom="bin/$target/${pname}_${target}_$initmode$displaymode.rom"
	[ $# -gt 0 ] && newrom="${newrom%.rom}_${1%.gkb}.rom"

	x_ mkdir -p "bin/$target"
	x_ cp "$tmprom" "$newrom" && [ $# -gt 0 ] && \
	    cbfs "$newrom" "config/data/grub/keymap/$1" keymap.gkb raw

	[ "$XBMK_RELEASE" = "y" ] || return 0
	$dry mksha512sum "$newrom" "vendorhashes"; $dry ./vendor inject \
	    -r "$newrom" -b "$target" -n nuke || $err "!nuke $newrom"
}

mkcoreboottar()
{
	[ "$target" = "$tree" ] && return 0; [ "$XBMK_RELEASE" = "y" ] && \
	    [ "$release" != "n" ] && $dry mkrom_tarball "bin/$target"; :
}
