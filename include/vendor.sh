# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2022 Caleb La Grange <thonkpeasant@protonmail.com>
# Copyright (c) 2022 Ferass El Hafidi <vitali64pmemail@protonmail.com>
# Copyright (c) 2023-2024 Leah Rowe <leah@libreboot.org>

e6400_unpack="$PWD/src/bios_extract/dell_inspiron_1100_unpacker.py"
me7updateparser="$PWD/util/me7_update_parser/me7_update_parser.py"
pfs_extract="$PWD/src/biosutilities/Dell_PFS_Extract.py"
uefiextract="$PWD/elf/uefitool/uefiextract"
vendir="vendorfiles"
appdir="$vendir/app"
cbcfgsdir="config/coreboot"

cv="CONFIG_HAVE_ME_BIN CONFIG_ME_BIN_PATH CONFIG_INCLUDE_SMSC_SCH5545_EC_FW \
    CONFIG_SMSC_SCH5545_EC_FW_FILE CONFIG_KBC1126_FIRMWARE CONFIG_KBC1126_FW1 \
    CONFIG_KBC1126_FW2 CONFIG_KBC1126_FW1_OFFSET CONFIG_KBC1126_FW2_OFFSET \
    CONFIG_VGA_BIOS_FILE CONFIG_VGA_BIOS_ID CONFIG_BOARD_DELL_E6400 \
    CONFIG_HAVE_MRC CONFIG_MRC_FILE CONFIG_HAVE_REFCODE_BLOB \
    CONFIG_REFCODE_BLOB_FILE CONFIG_GBE_BIN_PATH CONFIG_IFD_BIN_PATH \
    CONFIG_LENOVO_TBFW_BIN CONFIG_FSP_FD_PATH CONFIG_FSP_M_FILE \
    CONFIG_FSP_S_FILE CONFIG_FSP_S_CBFS CONFIG_FSP_M_CBFS CONFIG_FSP_USE_REPO \
    CONFIG_FSP_FULL_FD"

eval `setvars "" EC_url_bkup EC_hash DL_hash DL_url_bkup MRC_refcode_gbe vcfg \
    E6400_VGA_DL_hash E6400_VGA_DL_url E6400_VGA_DL_url_bkup E6400_VGA_offset \
    E6400_VGA_romname SCH5545EC_DL_url_bkup SCH5545EC_DL_hash _dest tree \
    mecleaner kbc1126_ec_dump MRC_refcode_cbtree new_mac _dl SCH5545EC_DL_url \
    archive EC_url boarddir rom cbdir DL_url nukemode cbfstoolref vrelease \
    verify _7ztest ME11bootguard ME11delta ME11version ME11sku ME11pch \
    IFD_platform ifdprefix cdir sdir _me _metmp mfs TBFW_url_bkup TBFW_url \
    TBFW_hash TBFW_size FSPFD_hash $cv`

vendor_download()
{
	[ $# -gt 0 ] || $err "No argument given"; export PATH="$PATH:/sbin"
	board="$1"; readcfg && readkconfig && bootstrap && getfiles; :
}

readkconfig()
{
	check_defconfig "$boarddir" 1>"$TMPDIR/vendorcfg.list" && return 1

	rm -f "$TMPDIR/tmpcbcfg" || $err "!rm -f \"$TMPDIR/tmpcbcfg\""
	while read -r cbcfgfile; do
		for cbc in $cv; do
			rm -f "$TMPDIR/tmpcbcfg2" || \
			    $err "!rm $TMPDIR/tmpcbcfg2"
			grep "$cbc" "$cbcfgfile" 1>"$TMPDIR/tmpcbcfg2" \
			    2>/dev/null || :
			[ -f "$TMPDIR/tmpcbcfg2" ] || continue
			cat "$TMPDIR/tmpcbcfg2" >> "$TMPDIR/tmpcbcfg" || \
			    $err "!cat $TMPDIR/tmpcbcfg2"
		done
	done < "$TMPDIR/vendorcfg.list"

	eval `setcfg "$TMPDIR/tmpcbcfg"`

	for c in CONFIG_HAVE_MRC CONFIG_HAVE_ME_BIN CONFIG_KBC1126_FIRMWARE \
	    CONFIG_VGA_BIOS_FILE CONFIG_INCLUDE_SMSC_SCH5545_EC_FW \
	    CONFIG_LENOVO_TBFW_BIN CONFIG_FSP_M_FILE CONFIG_FSP_S_FILE; do
		eval "[ \"\${$c}\" = \"/dev/null\" ] && continue"
		eval "[ -z \"\${$c}\" ] && continue"
		eval `setcfg "config/vendor/$vcfg/pkg.cfg"`; return 0
	done
	printf "Vendor files not needed for: %s\n" "$board" 1>&2; return 1
}

bootstrap()
{
	x_ ./mk -f coreboot ${cbdir##*/}
	mk -b uefitool biosutilities bios_extract
	[ -d "${kbc1126_ec_dump%/*}" ] && x_ make -C "$cbdir/util/kbc1126"
	[ -n "$MRC_refcode_cbtree" ] && \
	    cbfstoolref="elf/cbfstool/$MRC_refcode_cbtree/cbfstool" && \
	    x_ ./mk -d coreboot $MRC_refcode_cbtree; return 0
}

getfiles()
{
	[ -z "$CONFIG_HAVE_ME_BIN" ] || fetch intel_me "$DL_url" \
	    "$DL_url_bkup" "$DL_hash" "$CONFIG_ME_BIN_PATH"
	[ -z "$CONFIG_INCLUDE_SMSC_SCH5545_EC_FW" ] || fetch sch5545ec \
	    "$SCH5545EC_DL_url" "$SCH5545EC_DL_url_bkup" "$SCH5545EC_DL_hash" \
	    "$CONFIG_SMSC_SCH5545_EC_FW_FILE"
	[ -z "$CONFIG_KBC1126_FIRMWARE" ] || fetch kbc1126ec "$EC_url" \
	    "$EC_url_bkup" "$EC_hash" "$CONFIG_KBC1126_FW1"
	[ -z "$CONFIG_VGA_BIOS_FILE" ] || fetch e6400vga "$E6400_VGA_DL_url" \
	  "$E6400_VGA_DL_url_bkup" "$E6400_VGA_DL_hash" "$CONFIG_VGA_BIOS_FILE"
	[ -z "$CONFIG_HAVE_MRC" ] || fetch "mrc" "$MRC_url" "$MRC_url_bkup" \
	    "$MRC_hash" "$CONFIG_MRC_FILE"
	[ -z "$CONFIG_LENOVO_TBFW_BIN" ] || fetch "tbfw" "$TBFW_url" \
	    "$TBFW_url_bkup" "$TBFW_hash" "$CONFIG_LENOVO_TBFW_BIN"
	#
	# in the future, we might have libre fsp-s and then fsp-m.
	# therefore, handle them separately, in case one of them is libre; if
	# one of them was, the path wouldn't be set.
	#
	[ -z "$CONFIG_FSP_M_FILE" ] || fetch "fspm" "$CONFIG_FSP_FD_PATH" \
	    "$CONFIG_FSP_FD_PATH" "$FSPFD_hash" "$CONFIG_FSP_M_FILE" copy
	[ -z "$CONFIG_FSP_S_FILE" ] || fetch "fsps" "$CONFIG_FSP_FD_PATH" \
	    "$CONFIG_FSP_FD_PATH" "$FSPFD_hash" "$CONFIG_FSP_S_FILE" copy; :
}

fetch()
{
	dl_type="$1"; dl="$2"; dl_bkup="$3"; dlsum="$4"; _dest="${5##*../}"
	[ "$5" = "/dev/null" ] && return 0; _dl="$XBMK_CACHE/file/$dlsum"
	if [ "$dl_type" = "fspm" ] || [ "$dl_type" = "fsps" ]; then
		# HACK: if grabbing fsp from coreboot, fix the path for lbmk
		for _cdl in dl dl_bkup; do
			eval "$_cdl=\"\${$_cdl##*../}\"; _cdp=\"\$$_cdl\""
			[ -f "$_cdp" ] || _cdp="$cbdir/$_cdp"
			[ -f "$_cdp" ] && eval "$_cdl=\"$_cdp\""
		done
	fi

	dlop="curl" && [ $# -gt 5 ] && dlop="$6"
	download "$dl" "$dl_bkup" "$_dl" "$dlsum" "$dlop"

	rm -Rf "${_dl}_extracted" || $err "!rm -Rf ${_ul}_extracted"
	e "$_dest" f && return 0

	mkdir -p "${_dest%/*}" || $err "mkdirs: !mkdir -p ${_dest%/*}"
	remkdir "$appdir"; extract_archive "$_dl" "$appdir" "$dl_type" || \
	    [ "$dl_type" = "e6400vga" ] || $err "mkd $_dest $dl_type: !extract"

	eval "extract_$dl_type"; set -u -e
	e "$_dest" f missing && $err "!extract_$dl_type"; :
}

extract_intel_me()
{
	e "$mecleaner" f not && $err "$cbdir: me_cleaner missing"

	cdir="$PWD/$appdir"
	_me="$PWD/$_dest"
	_metmp="$PWD/tmp/me.bin"

	mfs="" && [ "$ME11bootguard" = "y" ] && mfs="--whitelist MFS" && \
	    chkvars ME11delta ME11version ME11sku ME11pch
	[ "$ME11bootguard" = "y" ] && x_ ./mk -f deguard

	x_ mkdir -p tmp

	extract_intel_me_bruteforce
	if [ "$ME11bootguard" = "y" ]; then
		apply_me11_deguard_mod
	else
		mv "$_metmp" "$_me" || $err "!mv $_metmp" "$_me"
	fi
}

extract_intel_me_bruteforce()
{
	[ $# -gt 0 ] && cdir="$1"

	e "$_metmp" f && return 0

	[ -z "$sdir" ] && sdir="$(mktemp -d)"
	mkdir -p "$sdir" || $err "extract_intel_me: !mkdir -p \"$sdir\""

	set +u +e
	(
	[ "${cdir#/a}" != "$cdir" ] && cdir="${cdir#/}"
	cd "$cdir" || $err "extract_intel_me: !cd \"$cdir\""
	for i in *; do
		[ -f "$_metmp" ] && break
		[ -L "$i" ] && continue
		if [ -f "$i" ]; then
			_r="-r" && [ -n "$mfs" ] && _r=""
			"$mecleaner" $mfs $_r -t -O "$sdir/vendorfile" \
			    -M "$_metmp" "$i" && break
			"$mecleaner" $mfs $_r -t -O "$_metmp" "$i" && break
			"$me7updateparser" -O "$_metmp" "$i" && break
			_7ztest="${_7ztest}a"
			extract_archive "$i" "$_7ztest" || continue
			extract_intel_me_bruteforce "$cdir/$_7ztest"
		elif [ -d "$i" ]; then
			extract_intel_me_bruteforce "$cdir/$i"
		else
			continue
		fi
		cdir="$1"; [ "${cdir#/a}" != "$cdir" ] && cdir="${cdir#/}"
		cd "$cdir" || :
	done
	)
	rm -Rf "$sdir" || $err "extract_intel_me: !rm -Rf $sdir"
}

apply_me11_deguard_mod()
{
	(
	x_ cd src/deguard/
	./finalimage.py --delta "data/delta/$ME11delta" \
	    --version "$ME11version" \
	    --pch "$ME11pch" --sku "$ME11sku" --fake-fpfs data/fpfs/zero \
	    --input "$_metmp" --output "$_me" || \
	    $err "Error running deguard for $_me"
	) || $err "Error running deguard for $_me"
}

extract_archive()
{
	if [ $# -gt 2 ]; then
		if [ "$3" = "fspm" ] || [ "$3" = "fsps" ]; then
			decat_fspfd "$1" "$2"
			return 0
		fi
	fi

	innoextract "$1" -d "$2" || python "$pfs_extract" "$1" -e || 7z x \
	    "$1" -o"$2" || unar "$1" -o "$2" || unzip "$1" -d "$2" || return 1

	[ ! -d "${_dl}_extracted" ] || cp -R "${_dl}_extracted" "$2" || \
	    $err "!mv '${_dl}_extracted' '$2'"; :
}

decat_fspfd()
{
	_fspfd="$1"
	_fspdir="$2"
	_fspsplit="$cbdir/3rdparty/fsp/Tools/SplitFspBin.py"

	$python "$_fspsplit" split -f "$_fspfd" -o "$_fspdir" -n "Fsp.fd" || \
	    $err "decat_fspfd '$1' '$2': Cannot de-concatenate"; :
}

extract_kbc1126ec()
{
	e "$kbc1126_ec_dump" f missing && $err "$cbdir: kbc1126 util missing"
	(
	x_ cd "$appdir/"; mv Rompaq/68*.BIN ec.bin || :
	if [ ! -f "ec.bin" ]; then
		unar -D ROM.CAB Rom.bin || unar -D Rom.CAB Rom.bin || \
		    unar -D 68*.CAB Rom.bin || $err "can't extract Rom.bin"
		x_ mv Rom.bin ec.bin
	fi
	[ -f ec.bin ] || $err "extract_kbc1126_ec $board: can't extract"
	"$kbc1126_ec_dump" ec.bin || $err "!1126ec $board extract ecfw"
	) || $err "can't extract kbc1126 ec firmware"

	e "$appdir/ec.bin.fw1" f not && $err "$board: kbc1126ec fetch failed"
	e "$appdir/ec.bin.fw2" f not && $err "$board: kbc1126ec fetch failed"

	cp "$appdir/"ec.bin.fw* "${_dest%/*}/" || $err "!cp 1126ec $_dest"
}

extract_e6400vga()
{
	set +u +e
	chkvars E6400_VGA_offset E6400_VGA_romname
	tail -c +$E6400_VGA_offset "$_dl" | gunzip > "$appdir/bios.bin" || :
	(
	x_ cd "$appdir"
	[ -f "bios.bin" ] || $err "extract_e6400vga: can't extract bios.bin"
	"$e6400_unpack" bios.bin || printf "TODO: fix dell extract util\n"
	) || $err "can't extract e6400 vga rom"
	cp "$appdir/$E6400_VGA_romname" "$_dest" || \
	    $err "extract_e6400vga $board: can't copy vga rom to $_dest"
}

extract_sch5545ec()
{
	# full system ROM (UEFI), to extract with UEFIExtract:
	_bios="${_dl}_extracted/Firmware/1 $dlsum -- 1 System BIOS vA.28.bin"
	# this is the SCH5545 firmware, inside of the extracted UEFI ROM:
	_sch5545ec_fw="$_bios.dump/4 7A9354D9-0468-444A-81CE-0BF617D890DF"
	_sch5545ec_fw="$_sch5545ec_fw/54 D386BEB8-4B54-4E69-94F5-06091F67E0D3"
	_sch5545ec_fw="$_sch5545ec_fw/0 Raw section/body.bin" # <-- this!

	"$uefiextract" "$_bios" || $err "sch5545 !extract"
	cp "$_sch5545ec_fw" "$_dest" || $err "$_dest: !sch5545 copy"
}

# Lenovo ThunderBolt firmware updates:
# https://pcsupport.lenovo.com/us/en/products/laptops-and-netbooks/thinkpad-t-series-laptops/thinkpad-t480-type-20l5-20l6/20l5/solutions/ht508988
extract_tbfw()
{
	chkvars TBFW_size # size in bytes, matching TBFW's flash IC
	x_ mkdir -p tmp
	x_ rm -f tmp/tb.bin
	find "$appdir" -type f -name "TBT.bin" > "tmp/tb.txt" || \
	    $err "extract_tbfw $_dest: Can't extract TBT.bin"
	while read -r f; do
		[ -f "$f" ] || continue
		[ -L "$f" ] && continue
		cp "$f" "tmp/tb.bin" || \
		    $err "extract_tbfw $_dest: Can't copy TBT.bin"
		break
	done < "tmp/tb.txt"
	dd if=/dev/null of=tmp/tb.bin bs=1 seek=$TBFW_size || \
	    $err "extract_tbfw $_dest: Can't pad TBT.bin"
	cp "tmp/tb.bin" "$_dest" || $err "extract_tbfw $_dest: copy error"; :
}

extract_fspm()
{
	copy_fsp M; :
}

extract_fsps()
{
	copy_fsp S; :
}

# this copies the fsp s/m; re-base is handled by ./mk inject
copy_fsp()
{
	cp "$appdir/Fsp_$1.fd" "$_dest" || \
	    $err "copy_fsp: Can't copy $1 to $_dest"; :
}

vendor_inject()
{
	set +u +e; [ $# -lt 1 ] && $err "No options specified."
	[ "$1" = "listboards" ] && eval "ls -1 config/coreboot || :; return 0"

	archive="$1"; while getopts n:r:b:m: option; do
		case "$option" in
		n) nukemode="$OPTARG" ;;
		r) rom="$OPTARG" ;;
		b) board="$OPTARG" ;;
		m) new_mac="$OPTARG"; chkvars new_mac ;;
		*) : ;;
		esac
	done

	check_board || return 0
	[ "$nukemode" = "nuke" ] || x_ ./mk download $board
	if [ "$vrelease" = "y" ]; then
		patch_release_roms
		printf "\nPatched images saved to bin/release/%s/\n" \
		    "$board"
	else
		patch_rom "$rom" || :
	fi; :
}

check_board()
{
	failcheck="y" && check_release "$archive" && failcheck="n"
	if [ "$failcheck" = "y" ]; then
		[ -f "$rom" ] || $err "check_board \"$rom\": invalid path"
		[ -z "${rom+x}" ] && $err "check_board: no rom specified"
		[ -n "${board+x}" ] || board="$(detect_board "$rom")"
	else
		vrelease="y"; board="$(detect_board "$archive")"
	fi
	readcfg || return 1; return 0
}

check_release()
{
	[ -f "$archive" ] || return 1
	[ "${archive##*.}" = "xz" ] || return 1
	printf "%s\n" "Release archive $archive detected"
}

# This function tries to determine the board from the filename of the rom.
# It will only succeed if the filename is not changed from the build/download
detect_board()
{
	path="$1"; filename="$(basename "$path")"
	case "$filename" in
	grub_*|seagrub_*|custom_*)
		board="$(echo "$filename" | cut -d '_' -f2-3)" ;;
	seabios_withgrub_*)
		board="$(echo "$filename" | cut -d '_' -f3-4)" ;;
	*.tar.xz) _stripped_prefix="${filename#*_}"
		board="${_stripped_prefix%.tar.xz}" ;;
	*) $err "detect_board $filename: could not detect board type"
	esac; printf "%s\n" "$board"
}

readcfg()
{
	if [ "$board" = "serprog_rp2040" ] || \
	    [ "$board" = "serprog_stm32" ] || \
	    [ "$board" = "serprog_pico" ]; then
		return 1
	fi; boarddir="$cbcfgsdir/$board"
	eval `setcfg "$boarddir/target.cfg"`; chkvars vcfg tree

	cbdir="src/coreboot/$tree"
	cbfstool="elf/cbfstool/$tree/cbfstool"
	rmodtool="elf/cbfstool/$tree/rmodtool"
	mecleaner="$PWD/$cbdir/util/me_cleaner/me_cleaner.py"
	kbc1126_ec_dump="$PWD/$cbdir/util/kbc1126/kbc1126_ec_dump"
	cbfstool="elf/cbfstool/$tree/cbfstool"
	ifdtool="elf/ifdtool/$tree/ifdtool"
	[ -n "$IFD_platform" ] && ifdprefix="-p $IFD_platform"

	x_ ./mk -d coreboot $tree
}

patch_release_roms()
{
	remkdir "tmp/romdir"; tar -xf "$archive" -C "tmp/romdir" || \
	    $err "patch_release_roms: !tar -xf \"$archive\" -C \"tmp/romdir\""

	for x in "tmp/romdir/bin/"*/*.rom ; do
		patch_rom "$x" || return 0
	done

	(
	cd "tmp/romdir/bin/"* || $err "patch roms: !cd tmp/romdir/bin/*"

	# NOTE: For compatibility with older rom releases, defer to sha1
	[ "$verify" != "y" ] || [ "$nukemode" = "nuke" ] || \
	    sha512sum --status -c vendorhashes || \
	    sha1sum --status -c vendorhashes || sha512sum --status -c \
	    blobhashes || sha1sum --status -c blobhashes || \
	    $err "patch_release_roms: ROMs did not match expected hashes"
	) || $err "can't verify vendor hashes"

	[ -n "$new_mac" ] && for x in "tmp/romdir/bin/"*/*.rom ; do
		[ -f "$x" ] && modify_gbe "$x"
	done

	x_ mkdir -p bin/release
	mv tmp/romdir/bin/* bin/release/ || $err "$board: !mv release roms"
}

patch_rom()
{
	rom="$1"
	readkconfig || return 1

	[ -n "$CONFIG_HAVE_REFCODE_BLOB" ] && inject "fallback/refcode" \
	    "$CONFIG_REFCODE_BLOB_FILE" "stage"
	[ "$CONFIG_HAVE_MRC" = "y" ] && inject "mrc.bin" "$CONFIG_MRC_FILE" \
	    "mrc" "0xfffa0000"
	[ "$CONFIG_HAVE_ME_BIN" = "y" ] && inject IFD "$CONFIG_ME_BIN_PATH" me
	[ "$CONFIG_KBC1126_FIRMWARE" = "y" ] && inject ecfw1.bin \
	    "$CONFIG_KBC1126_FW1" raw "$CONFIG_KBC1126_FW1_OFFSET" && inject \
	    ecfw2.bin "$CONFIG_KBC1126_FW2" raw "$CONFIG_KBC1126_FW2_OFFSET"
	[ -n "$CONFIG_VGA_BIOS_FILE" ] && [ -n "$CONFIG_VGA_BIOS_ID" ] && \
	  inject "pci$CONFIG_VGA_BIOS_ID.rom" "$CONFIG_VGA_BIOS_FILE" optionrom
	[ "$CONFIG_INCLUDE_SMSC_SCH5545_EC_FW" = "y" ] && \
	    [ -n "$CONFIG_SMSC_SCH5545_EC_FW_FILE" ] && \
		inject sch5545_ecfw.bin "$CONFIG_SMSC_SCH5545_EC_FW_FILE" raw
	#
	# coreboot adds FSP-M first. so we shall add it first, then S:
	# NOTE:
	# We skip the fetch if CONFIG_FSP_USE_REPO or CONFIG_FSP_FULL_FD is set
	# but only for inject/nuke. we still run fetch (see above) because on
	# _fsp targets, coreboot still needs them, but coreboot Kconfig uses
	# makefile syntax and puts $(obj) in the path, which makes no sense
	# in sh. So we modify the path there, but lbmk only uses the file
	# in vendorfiles/ if neither CONFIG_FSP_USE_REPO nor CONFIG_FSP_FULL_FD
	# are set
	#
	[ -z "$CONFIG_FSP_USE_REPO" ] && [ -z "$CONFIG_FSP_FULL_FD" ] && \
	   [ -n "$CONFIG_FSP_M_FILE" ] && \
		inject "$CONFIG_FSP_M_CBFS" "$CONFIG_FSP_M_FILE" fsp --xip
	[ -z "$CONFIG_FSP_USE_REPO" ] && [ -z "$CONFIG_FSP_FULL_FD" ] && \
	   [ -n "$CONFIG_FSP_S_FILE" ] && \
		inject "$CONFIG_FSP_S_CBFS" "$CONFIG_FSP_S_FILE" fsp
	[ -n "$new_mac" ] && [ "$vrelease" != "y" ] && modify_gbe "$rom"

	printf "ROM image successfully patched: %s\n" "$rom"
}

inject()
{
	[ $# -lt 3 ] && $err "$@, $rom: usage: inject name path type (offset)"
	[ "$2" = "/dev/null" ] && return 0; verify="y"

	eval `setvars "" cbfsname _dest _t _offset`
	cbfsname="$1"; _dest="${2##*../}"; _t="$3"

	if [ "$_t" = "fsp" ]; then
		[ $# -gt 3 ] && _offset="$4"
	else
		[ $# -gt 3 ] && _offset="-b $4" && [ -z "$4" ] && \
		    $err "inject $@, $rom: offset given but empty (undefined)"
	fi

	e "$_dest" f n && [ "$nukemode" != "nuke" ] && $err "!inject $dl_type"

	if [ "$cbfsname" = "IFD" ]; then
		[ "$nukemode" = "nuke" ] || "$ifdtool" $ifdprefix -i \
		    $_t:$_dest "$rom" -O "$rom" || \
		    $err "failed: inject '$_t' '$_dest' on '$rom'"
		[ "$nukemode" != "nuke" ] || "$ifdtool" $ifdprefix --nuke $_t \
		    "$rom" -O "$rom" || $err "$rom: !nuke IFD/$_t"; return 0
	elif [ "$nukemode" = "nuke" ]; then
		"$cbfstool" "$rom" remove -n "$cbfsname" || \
		    $err "inject $rom: can't remove $cbfsname"; return 0
	fi
	if [ "$_t" = "stage" ]; then # the only stage we handle in refcode
		x_ mkdir -p tmp; x_ rm -f "tmp/refcode"
		"$rmodtool" -i "$_dest" -o "tmp/refcode" || "!reloc refcode"
		"$cbfstool" "$rom" add-stage -f "tmp/refcode" -n "$cbfsname" \
		    -t stage || $err "$rom: !add ref"
	else
		"$cbfstool" "$rom" add -f "$_dest" -n "$cbfsname" \
		    -t $_t $_offset || $err "$rom !add $_t ($_dest)"
	fi; :
}

modify_gbe()
{
	chkvars CONFIG_GBE_BIN_PATH

	e "${CONFIG_GBE_BIN_PATH##*../}" f n && $err "missing gbe file"
	x_ make -C util/nvmutil

	x_ cp "${CONFIG_GBE_BIN_PATH##*../}" "$TMPDIR/gbe"
	x_ "util/nvmutil/nvm" "$TMPDIR/gbe" setmac $new_mac
	"$ifdtool" $ifdprefix -i GbE:"$TMPDIR/gbe" "$1" -O "$1" || \
	    $err "Cannot insert modified GbE region into target image."
}
