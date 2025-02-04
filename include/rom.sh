# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2014-2016,2020-2021,2023-2025 Leah Rowe <leah@libreboot.org>
# Copyright (c) 2021-2022 Ferass El Hafidi <vitali64pmemail@protonmail.com>
# Copyright (c) 2022 Caleb La Grange <thonkpeasant@protonmail.com>
# Copyright (c) 2022-2023 Alper Nebi Yasak <alpernebiyasak@gmail.com>
# Copyright (c) 2023-2024 Riku Viitanen <riku.viitanen@protonmail.com>

mkserprog()
{
	[ $# -lt 1 ] && $err "mkserprog: no arguments provided"
	[ "$_f" = "-d" ] && return 0 # dry run

	[ "$1" = "pico" ] && mkpicotool

	basename -as .h "$serdir/"*.h > "$TMPDIR/ser" || $err "!mk $1 $TMPDIR"

	while read -r sertarget; do
		[ "$1" = "pico" ] &&
		    x_ rm -rf "$sersrc/build" \
		    && (pt=$(x_ grep "pico_cmake_set" \
		          "$picosdk/src/boards/include/boards/$sertarget.h" \
		        | grep "PICO_PLATFORM" | cut -d= -f2 | tr -d [:blank:])
		        mkdir -p "$sersrc/build_$pt"
			ln -srf "$sersrc/build_$pt/" "$sersrc/build") \
		    && x_ cmake -DPICO_BOARD="$sertarget" \
		    -DPICO_SDK_PATH="$picosdk" -B "$sersrc/build" "$sersrc" \
		    -Dpicotool_DIR="$picotool/picotool" \
		    && x_ cmake --build "$sersrc/build"
		[ "$1" = "stm32" ] && x_ make -C "$sersrc" \
		    libopencm3-just-make BOARD=$sertarget && x_ make -C \
		    "$sersrc" BOARD=$sertarget; x_ mkdir -p "bin/serprog_$1"
		x_ mv "$serx" "bin/serprog_$1/serprog_$sertarget.${serx##*.}"
	done < "$TMPDIR/ser"

	[ "$XBMK_RELEASE" = "y" ] && mkrom_tarball "bin/serprog_$1"; return 0
}

mkpicotool()
{
	rm -Rf "$picotool" || $err "Can't remove picotool builddir"
	(
	x_ cd src/picotool
	cmake -DCMAKE_INSTALL_PREFIX=xbmkbin -DPICOTOOL_FLAT_INSTALL=1 \
	    -DPICO_SDK_PATH=../pico-sdk || \
	    $err "Can't prep picotool"
	make install || $err "Can't build picotool"; :
	) || $err "Can't build picotool"; :
}

copyps1bios()
{
	x_ rm -Rf bin/playstation
	x_ mkdir -p bin/playstation
	x_ cp src/pcsx-redux/src/mips/openbios/openbios.bin bin/playstation

	printf "MIT License\n\nCopyright (c) 2019-2024 PCSX-Redux authors\n\n" \
	    > bin/playstation/COPYING.txt || $err "!pcsx-redux copyright"
	cat config/snippet/mit >>bin/playstation/COPYING.txt || $err "!pcsx MIT"
}

mkpayload_grub()
{
	eval "`setvars "" grub_modules grub_install_modules`"
	$dry eval "`setcfg "$grubdata/module/$tree"`"
	$dry x_ rm -f "$srcdir/grub.elf"; $dry \
	"$srcdir/grub-mkstandalone" --grub-mkimage="$srcdir/grub-mkimage" \
	    -O i386-coreboot -o "$srcdir/grub.elf" -d "${srcdir}/grub-core/" \
	    --fonts= --themes= --locales=  --modules="$grub_modules" \
	    --install-modules="$grub_install_modules" \
	    "/boot/grub/grub_default.cfg=${srcdir}/.config" \
	    "/boot/grub/grub.cfg=$grubdata/memdisk.cfg" || \
	    $err "$tree: cannot build grub.elf"; return 0
}

mkvendorfiles()
{
	[ -z "$mode" ] && $dry cook_coreboot_config
	check_coreboot_utils "$tree"
	printf "%s\n" "${version%%-*}" > "$srcdir/.coreboot-version" || \
	    $err "!mk $srcdir .coreboot-version"
	[ -z "$mode" ] && [ "$target" != "$tree" ] && \
	    x_ ./mk download "$target"; return 0
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
		if [ -z "$mode" ] && [ ! -f "$utilelfdir/$util" ]; then
			x_ mkdir -p "$utilelfdir"
			x_ cp "$utilsrcdir/$util" "$utilelfdir"
			[ "$util" = "cbfstool" ] || continue
			x_ cp "$utilsrcdir/rmodtool" "$utilelfdir"
		elif [ -n "$mode" ]; then
			x_ rm -Rf "$utilelfdir"
		fi; continue
	done; return 0
}

mkcorebootbin()
{
	[ "$target" = "$tree" ] && return 0

	tmprom="$TMPDIR/coreboot.rom"
	$dry x_ cp "$srcdir/build/coreboot.rom" "$tmprom"

	initmode="${defconfig##*/}"; displaymode="${initmode##*_}"
	[ "$displaymode" = "$initmode" ] && displaymode="" # "normal" config
	initmode="${initmode%%_*}"
	cbfstool="elf/cbfstool/$tree/cbfstool"

	[ "$payload_uboot_i386" = "y" ] && \
	    [ "$payload_uboot_amd64" = "y" ] && \
		$err "'$target' enables 32- and 64-bit x86 U-Boot"

	if [ "$payload_uboot_i386" = "y" ] || \
	    [ "$payload_uboot_amd64" = "y" ]; then
		printf "'%s' has x86 U-Boot; assuming SeaBIOS=y\n" \
		    "$target" 1>&2
		payload_seabios="y"
	fi

	[ -n "$uboot_config" ] || uboot_config="default"
	[ "$payload_uboot" = "y" ] || payload_seabios="y"
	[ "$payload_grub" = "y" ] && payload_seabios="y"
	[ "$payload_seabios" = "y" ] && [ "$payload_uboot" = "y" ] && \
	    $dry $err "$target: U-Boot(arm64) and SeaBIOS/GRUB both enabled."

	[ -z "$grub_scan_disk" ] && grub_scan_disk="nvme ahci ata"

	[ -n "$grubtree" ] || grubtree="default"
	grubelf="elf/grub/$grubtree/payload/grub.elf"

	[ "$payload_memtest" = "y" ] || payload_memtest="n"
	[ "$(uname -m)" = "x86_64" ] || payload_memtest="n"

	[ "$payload_grubsea" = "y" ] && [ "$initmode" = "normal" ] && \
	    payload_grubsea="n"
	[ "$payload_grub" = "y" ] || payload_grubsea="n"

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
	if [ "$payload_uboot_i386" = "y" ] || \
	    [ "$payload_uboot_amd64" = "y" ]; then
		$dry add_uboot
	fi

	_seabioself="elf/seabios/default/$initmode/bios.bin.elf"

	_seaname="fallback/payload" && [ "$payload_grubsea" = "y" ] && \
	    _seaname="seabios.elf"
	cbfs "$tmprom" "$_seabioself" "$_seaname"
	x_ "$cbfstool" "$tmprom" add-int -i 3000 -n etc/ps2-keyboard-spinup

	_z="2"; [ "$initmode" = "vgarom" ] && _z="0"
	x_ "$cbfstool" "$tmprom" add-int -i $_z -n etc/pci-optionrom-exec
	x_ "$cbfstool" "$tmprom" add-int -i 0 -n etc/optionroms-checksum
	[ "$initmode" = "libgfxinit" ] && \
	    cbfs "$tmprom" "$seavgabiosrom" vgaroms/seavgabios.bin raw

	[ "$payload_memtest" = "y" ] && cbfs "$tmprom" \
	    "elf/memtest86plus/memtest.bin" img/memtest

	[ "$payload_grub" = "y" ] && add_grub

	[ "$payload_grubsea" != "y" ] && cprom
	[ "$payload_uboot_amd64" = "y" ] && [ "$displaymode" != "txtmode" ] && \
	    [ "$initmode" != "normal" ] && [ "$payload_grubsea" != "y" ] && \
	    pname="seauboot" && cprom "seauboot"
	[ "$payload_grub" = "y" ] && pname="seagrub" && mkseagrub; :
}

add_grub()
{
	_grubname="img/grub2" && [ "$payload_grubsea" = "y" ] && \
	    _grubname="fallback/payload"
	cbfs "$tmprom" "$grubelf" "$_grubname"
	printf "set grub_scan_disk=\"%s\"\n" "$grub_scan_disk" \
	    > "$TMPDIR/tmpcfg" || $err "$target: !insert scandisk"
	cbfs "$tmprom" "$TMPDIR/tmpcfg" scan.cfg raw
	[ "$initmode" != "normal" ] && [ "$displaymode" != "txtmode" ] && \
	    cbfs "$tmprom" "$grubdata/background/background1280x800.png" \
	    "background.png" raw; :
}

mkseagrub()
{
	if [ "$payload_grubsea" = "y" ]; then
		pname="grub"
	else
		cbfs "$tmprom" "$grubdata/bootorder" bootorder raw
	fi
	for keymap in config/data/grub/keymap/*.gkb; do
		[ -f "$keymap" ] && cprom "${keymap##*/}"; :
	done; :
}

add_uboot()
{
	if [ "$displaymode" = "txtmode" ]; then
		printf "cb/%s: Cannot use U-Boot in text mode\n" \
		    "$target" 1>&2
		return 0
	elif [ "$initmode" = "normal" ]; then
		printf "cb/%s: Cannot use U-Boot in normal initmode\n" \
		    "$target" 1>&2
		return 0
	fi

	# TODO: re-work to allow each coreboot target to say which ub tree
	# instead of hardcoding as in the current logic below:

	# aarch64 targets:
	ubcbfsargs=""
	ubpath="fallback/payload"
	ubtarget="$target"
	# override for x86/x86_64 targets:
	if [ "$payload_uboot_i386" = "y" ] || \
	    [ "$payload_uboot_amd64" = "y" ]; then
		ubcbfsargs="-l 0x1110000 -e 0x1110000" # 64-bit and 32-bit
			# on 64-bit, 0x1120000 is the SPL, and stub before that
		ubpath="img/u-boot" # 64-bit
		ubtarget="amd64coreboot"
		[ "$payload_uboot_i386" = "y" ] && ubpath="u-boot" # 32-bit
		[ "$payload_uboot_i386" = "y" ] && ubtarget="i386coreboot"; :
	fi

	ubdir="elf/u-boot/$ubtarget/$uboot_config"

	# aarch64 targets:
	ubootelf="$ubdir/u-boot.elf" && [ ! -f "$ubootelf" ] && \
	    ubootelf="$ubdir/u-boot"
	# override for x86/x86_64 targets:
	[ "$payload_uboot_i386" = "y" ] && ubootelf="$ubdir/u-boot-dtb.bin"
	[ "$payload_uboot_amd64" = "y" ] && \
	    ubootelf="$ubdir/u-boot-x86-with-spl.bin" # EFI-compatible

	[ -f "$ubootelf" ] || $err "cb/$ubtarget: Can't find u-boot"
	cbfs "$tmprom" "$ubootelf" "$ubpath" $ubcbfsargs
	[ "$payload_seabios" = "y" ] || cprom; :
}

cprom()
{
	newrom="bin/$target/${pname}_${target}_$initmode.rom"
	[ -n "$displaymode" ] && newrom="${newrom%.rom}_$displaymode.rom"
	[ $# -gt 0 ] && [ "$1" != "seauboot" ] && \
	    newrom="${newrom%.rom}_${1%.gkb}.rom"

	x_ mkdir -p "bin/$target"
	x_ cp "$tmprom" "$newrom" && [ $# -gt 0 ] && [ "$1" != "seauboot" ] && \
	    cbfs "$newrom" "config/data/grub/keymap/$1" keymap.gkb raw
	[ $# -gt 0 ] && [ "$1" = "seauboot" ] && \
	    cbfs "$newrom" "config/data/grub/bootorder_uboot" bootorder raw; :
}

mkcoreboottar()
{
	[ "$target" = "$tree" ] && return 0
	[ "$XBMK_RELEASE" = "y" ] || return 0
	[ "$release" != "n" ] || return 0
	$dry mkrom_tarball "bin/$target"
	$dry ./mk inject "bin/${relname}_${target}.tar.xz" nuke || \
	    $err "Can't delete vendorfiles in 'bin/${relname}_$target.tar.xz'"
	return 0
}
