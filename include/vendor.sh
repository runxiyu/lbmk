# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2022 Caleb La Grange <thonkpeasant@protonmail.com>
# Copyright (c) 2022 Ferass El Hafidi <vitali64pmemail@protonmail.com>
# Copyright (c) 2023-2025 Leah Rowe <leah@libreboot.org>

e6400_unpack="$PWD/src/bios_extract/dell_inspiron_1100_unpacker.py"
me7updateparser="$PWD/util/me7_update_parser/me7_update_parser.py"
pfs_extract="$PWD/src/biosutilities/Dell_PFS_Extract.py"
uefiextract="$PWD/elf/uefitool/uefiextract"
vendir="vendorfiles"
appdir="$vendir/app"
cbcfgsdir="config/coreboot"
hashfiles="vendorhashes blobhashes" # blobhashes for backwards compatibility
dontflash="!!! AN ERROR OCCURED! Please DO NOT flash if injection failed. !!!"
vfix="DO_NOT_FLASH_YET._FIRST,_INJECT_BLOBS_VIA_INSTRUCTIONS_ON_LIBREBOOT.ORG_"
vguide="https://libreboot.org/docs/install/ivy_has_common.html"
tmpromdel="$PWD/tmp/DO_NOT_FLASH"

cv="CONFIG_HAVE_ME_BIN CONFIG_ME_BIN_PATH CONFIG_INCLUDE_SMSC_SCH5545_EC_FW \
    CONFIG_SMSC_SCH5545_EC_FW_FILE CONFIG_KBC1126_FIRMWARE CONFIG_KBC1126_FW1 \
    CONFIG_KBC1126_FW2 CONFIG_KBC1126_FW1_OFFSET CONFIG_KBC1126_FW2_OFFSET \
    CONFIG_VGA_BIOS_FILE CONFIG_VGA_BIOS_ID CONFIG_BOARD_DELL_E6400 \
    CONFIG_HAVE_MRC CONFIG_MRC_FILE CONFIG_HAVE_REFCODE_BLOB \
    CONFIG_REFCODE_BLOB_FILE CONFIG_GBE_BIN_PATH CONFIG_IFD_BIN_PATH \
    CONFIG_LENOVO_TBFW_BIN CONFIG_FSP_FD_PATH CONFIG_FSP_M_FILE \
    CONFIG_FSP_S_FILE CONFIG_FSP_S_CBFS CONFIG_FSP_M_CBFS CONFIG_FSP_USE_REPO \
    CONFIG_FSP_FULL_FD"

eval "`setvars "" has_hashes EC_hash DL_hash DL_url_bkup MRC_refcode_gbe vcfg \
    E6400_VGA_DL_hash E6400_VGA_DL_url E6400_VGA_DL_url_bkup E6400_VGA_offset \
    E6400_VGA_romname SCH5545EC_DL_url_bkup SCH5545EC_DL_hash _dest tree \
    mecleaner kbc1126_ec_dump MRC_refcode_cbtree new_mac _dl SCH5545EC_DL_url \
    archive EC_url boarddir rom cbdir DL_url nukemode cbfstoolref FSPFD_hash \
    _7ztest ME11bootguard ME11delta ME11version ME11sku ME11pch tmpromdir \
    IFD_platform ifdprefix cdir sdir _me _metmp mfs TBFW_url_bkup TBFW_url \
    TBFW_hash TBFW_size hashfile xromsize xchanged EC_url_bkup need_files \
    vfile $cv`"

vendor_download()
{
	[ $# -gt 0 ] || $err "No argument given"; export PATH="$PATH:/sbin"
	board="$1"; readcfg && readkconfig && bootstrap && getfiles; :
}

readkconfig()
{
	check_defconfig "$boarddir" 1>"$TMPDIR/vendorcfg.list" && return 1

	rm -f "$TMPDIR/tmpcbcfg" || $err "!rm $TMPDIR/tmpcbcfg - $dontflash"
	while read -r cbcfgfile; do
		for cbc in $cv; do
			rm -f "$TMPDIR/tmpcbcfg2" || \
			    $err "!rm $TMPDIR/tmpcbcfg2 - $dontflash"
			grep "$cbc" "$cbcfgfile" 1>"$TMPDIR/tmpcbcfg2" \
			    2>/dev/null || :
			[ -f "$TMPDIR/tmpcbcfg2" ] || continue
			cat "$TMPDIR/tmpcbcfg2" >> "$TMPDIR/tmpcbcfg" || \
			    $err "!cat $TMPDIR/tmpcbcfg2 - $dontflash"
		done
	done < "$TMPDIR/vendorcfg.list"

	eval "`setcfg "$TMPDIR/tmpcbcfg"`"

	for c in CONFIG_HAVE_MRC CONFIG_HAVE_ME_BIN CONFIG_KBC1126_FIRMWARE \
	    CONFIG_VGA_BIOS_FILE CONFIG_INCLUDE_SMSC_SCH5545_EC_FW \
	    CONFIG_LENOVO_TBFW_BIN CONFIG_FSP_M_FILE CONFIG_FSP_S_FILE; do
		eval "[ \"\${$c}\" = \"/dev/null\" ] && continue"
		eval "[ -z \"\${$c}\" ] && continue"
		eval "`setcfg "$vfile"`"; return 0
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
	    x_ ./mk -d coreboot "$MRC_refcode_cbtree"; return 0
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

	rm -Rf "${_dl}_extracted" || $err "!rm ${_ul}_extracted. $dontflash"
	e "$_dest" f && return 0

	mkdir -p "${_dest%/*}" || \
	    $err "mkdirs: !mkdir -p ${_dest%/*} - $dontflash"
	remkdir "$appdir"; extract_archive "$_dl" "$appdir" "$dl_type" || \
	    [ "$dl_type" = "e6400vga" ] || \
	    $err "mkd $_dest $dl_type: !extract. $dontflash"

	eval "extract_$dl_type"; set -u -e
	e "$_dest" f missing && $err "!extract_$dl_type. $dontflash"; :
}

extract_intel_me()
{
	e "$mecleaner" f not && $err "$cbdir: me_cleaner missing. $dontflash"

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
		mv "$_metmp" "$_me" || $err "!mv $_metmp $_me - $dontflash"
	fi
}

extract_intel_me_bruteforce()
{
	[ $# -gt 0 ] && cdir="$1"

	e "$_metmp" f && return 0

	[ -z "$sdir" ] && sdir="$(mktemp -d)"
	mkdir -p "$sdir" || \
	    $err "extract_intel_me: !mkdir -p \"$sdir\" - $dontflash"

	set +u +e
	(
	[ "${cdir#/a}" != "$cdir" ] && cdir="${cdir#/}"
	cd "$cdir" || $err "extract_intel_me: !cd \"$cdir\" - $dontflash"
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
	rm -Rf "$sdir" || $err "extract_intel_me: !rm -Rf $sdir - $dontflash"
}

apply_me11_deguard_mod()
{
	(
	x_ cd src/deguard/
	./finalimage.py --delta "data/delta/$ME11delta" \
	    --version "$ME11version" \
	    --pch "$ME11pch" --sku "$ME11sku" --fake-fpfs data/fpfs/zero \
	    --input "$_metmp" --output "$_me" || \
	    $err "Error running deguard for $_me - $dontflash"
	) || $err "Error running deguard for $_me - $dontflash"
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
	    $err "!mv '${_dl}_extracted' '$2' - $dontflash"; :
}

decat_fspfd()
{
	_fspfd="$1"
	_fspdir="$2"
	_fspsplit="$cbdir/3rdparty/fsp/Tools/SplitFspBin.py"

	$python "$_fspsplit" split -f "$_fspfd" -o "$_fspdir" -n "Fsp.fd" || \
	    $err "decat_fspfd '$1' '$2': Can't de-concatenate; $dontflash"; :
}

extract_kbc1126ec()
{
	e "$kbc1126_ec_dump" f missing && \
	    $err "$cbdir: kbc1126 util missing - $dontflash"
	(
	x_ cd "$appdir/"; mv Rompaq/68*.BIN ec.bin || :
	if [ ! -f "ec.bin" ]; then
		unar -D ROM.CAB Rom.bin || unar -D Rom.CAB Rom.bin || \
		    unar -D 68*.CAB Rom.bin || \
		    $err "can't extract Rom.bin - $dontflash"
		x_ mv Rom.bin ec.bin
	fi
	[ -f ec.bin ] || \
	    $err "extract_kbc1126_ec $board: can't extract - $dontflash"
	"$kbc1126_ec_dump" ec.bin || \
	    $err "!1126ec $board extract ecfw - $dontflash"
	) || $err "can't extract kbc1126 ec firmware - $dontflash"

	e "$appdir/ec.bin.fw1" f not && \
	    $err "$board: kbc1126ec fetch failed - $dontflash"
	e "$appdir/ec.bin.fw2" f not && \
	    $err "$board: kbc1126ec fetch failed - $dontflash"

	cp "$appdir/"ec.bin.fw* "${_dest%/*}/" || \
	    $err "!cp 1126ec $_dest - $dontflash"; :
}

extract_e6400vga()
{
	set +u +e
	chkvars E6400_VGA_offset E6400_VGA_romname
	tail -c +$E6400_VGA_offset "$_dl" | gunzip > "$appdir/bios.bin" || :
	(
	x_ cd "$appdir"
	[ -f "bios.bin" ] || \
	    $err "extract_e6400vga: can't extract bios.bin - $dontflash"
	"$e6400_unpack" bios.bin || printf "TODO: fix dell extract util\n"
	) || $err "can't extract e6400 vga rom - $dontflosh"
	cp "$appdir/$E6400_VGA_romname" "$_dest" || \
	    $err "extract_e6400vga $board: can't cp $_dest - $dontflash"; :
}

extract_sch5545ec()
{
	# full system ROM (UEFI), to extract with UEFIExtract:
	_bios="${_dl}_extracted/Firmware/1 $dlsum -- 1 System BIOS vA.28.bin"
	# this is the SCH5545 firmware, inside of the extracted UEFI ROM:
	_sch5545ec_fw="$_bios.dump/4 7A9354D9-0468-444A-81CE-0BF617D890DF"
	_sch5545ec_fw="$_sch5545ec_fw/54 D386BEB8-4B54-4E69-94F5-06091F67E0D3"
	_sch5545ec_fw="$_sch5545ec_fw/0 Raw section/body.bin" # <-- this!

	"$uefiextract" "$_bios" || $err "sch5545 !extract - $dontflash"
	cp "$_sch5545ec_fw" "$_dest" || \
	    $err "$_dest: !sch5545 copy - $dontflash"; :
}

# Lenovo ThunderBolt firmware updates:
# https://pcsupport.lenovo.com/us/en/products/laptops-and-netbooks/thinkpad-t-series-laptops/thinkpad-t480-type-20l5-20l6/20l5/solutions/ht508988
extract_tbfw()
{
	chkvars TBFW_size # size in bytes, matching TBFW's flash IC
	x_ mkdir -p tmp
	x_ rm -f tmp/tb.bin
	find "$appdir" -type f -name "TBT.bin" > "tmp/tb.txt" || \
	    $err "extract_tbfw $_dest: Can't extract TBT.bin - $dontflash"
	while read -r f; do
		[ -f "$f" ] || continue
		[ -L "$f" ] && continue
		cp "$f" "tmp/tb.bin" || \
		    $err "extract_tbfw $_dest: Can't copy TBT.bin - $dontflash"
		break
	done < "tmp/tb.txt"
	dd if=/dev/null of=tmp/tb.bin bs=1 seek=$TBFW_size || \
	    $err "extract_tbfw $_dest: Can't pad TBT.bin - $dontflash"
	cp "tmp/tb.bin" "$_dest" || \
	    $err "extract_tbfw $_dest: copy error - $dontflash "; :
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
	    $err "copy_fsp: Can't copy $1 to $_dest - $dontflash"; :
}

fail_inject()
{
	[ -L "$tmpromdel" ] || [ ! -d "$tmpromdel" ] || \
	    rm -Rf "$tmpromdel" || :
	printf "\n\n%s\n\n" "$dontflash" 1>&2
	printf "WARNING: File '%s' was NOT modified.\n\n" "$archive" 1>&2
	printf "Please MAKE SURE vendor files are inserted before flashing\n\n"
	fail "$1"
}

vendor_inject()
{
	need_files="n" # will be set to "y" if vendorfiles needed
	_olderr="$err"
	err="fail_inject"
	remkdir "$tmpromdel"

	set +u +e; [ $# -lt 1 ] && $err "No options specified. - $dontflash"
	eval "`setvars "" nukemode new_mac xchanged`"

	archive="$1";
	[ $# -gt 1 ] && case "$2" in
	nuke) nukemode="nuke" ;;
	setmac)
		new_mac="??:??:??:??:??:??"
		[ $# -gt 2 ] && new_mac="$3" ;;
	*) $err "Unrecognised inject mode: '$2'"
	esac

	check_release "$archive" || \
	    $err "You must run this script on a release archive. - $dontflash"

	readcfg && need_files="y"
	if [ "$need_files" = "y" ] || [ -n "$new_mac" ]; then
		[ "$nukemode" = "nuke" ] || x_ ./mk download "$board"
		patch_release_roms
	fi
	[ "$need_files" != "y" ] && printf \
	    "\nTarball '%s' (board '%s) doesn't need vendorfiles.\n" \
	    "$archive" "$board" 1>&2

	xtype="patched" && [ "$nukemode" = "nuke" ] && xtype="nuked"
	[ "$xchanged" != "y" ] && \
		printf "\nRelease archive '%s' was *NOT* modified.\n" \
		    "$archive" && [ "$has_hashes" = "y" ] && \
		    printf "WARNING: '%s' contains '%s'. DO NOT FLASH!\n" \
		    "$archive" "$hashfile" 1>&2 && \
		    printf "(vendorfiles may be needed and aren't there)\n" \
		    1>&2
	[ "$xchanged" = "y" ] && \
		printf "\nRelease archive '%s' successfully %s.\n" \
		    "$archive" "$xtype" && [ "$nukemode" != "nuke" ] && \
		printf "You may now extract '%s' and flash images from it.\n" \
		    "$archive"
	[ "$xchanged" = "y" ] && [ "$nukemode" = "nuke" ] && \
		printf "WARNING! Vendorfiles *removed*. DO NOT FLASH.\n" 1>&2 \
		    && printf "DO NOT flash images from '%s'\n" \
		    "$archive" 1>&2

	#
	# catch-all error handler, for libreboot release opsec:
	#
	# if vendor files defined, and a hash file was missing, that means
	# a nuke must succeed, if specified. if no hashfile was present,
	# that means vendorfiles had been injected, so a nuke must succeed.
	# this check is here in case of future bugs in lbmk's handling
	# of vendorfile deletions on release archives, which absolutely
	# must always be 100% reliable, so paranoia is paramount:
	#
	if [ "$xchanged" != "y" ] && [ "$need_files" = "y" ] && \
	    [ "$nukemode" = "nuke" ] && [ "$has_hashes" != "y" ]; then
		printf "FAILED NUKE: tarball '$archive', board '$board'\n" 1>&2
		$err "Unhandled vendorfile deletion: DO NOT RELEASE TO RSYNC"
	fi # of course, we assume that those variables are also set right

	err="$_olderr"
	return 0
}

check_release()
{
	[ -L "$archive" ] && \
	    $err "'$archive' is a symlink, not a file - $dontflash"
	[ -f "$archive" ] || return 1
	archivename="`basename "$archive"`"
	[ -z "$archivename" ] && \
	    $err "Cannot determine archive file name - $dontflash"

	case "$archivename" in
	*_src.tar.xz)
		$err "'$archive' is a src archive, silly!" ;;
	grub_*|seagrub_*|custom_*|seauboot_*|seabios_withgrub_*)
		return 1 ;;
	*.tar.xz) _stripped_prefix="${archivename#*_}"
		board="${_stripped_prefix%.tar.xz}" ;;
	*) $err "'$archive': could not detect board type - $dontflash"
	esac; :
}

readcfg()
{
	if [ "$board" = "serprog_rp2040" ] || \
	    [ "$board" = "serprog_stm32" ] || \
	    [ "$board" = "serprog_pico" ]; then
		return 1
	fi
	boarddir="$cbcfgsdir/$board"

	eval "`setcfg "$boarddir/target.cfg"`"
	chkvars tree
	x_ ./mk -d coreboot "$tree" # even if vendorfiles not used, see: setmac

	[ -z "$vcfg" ] && return 1
	vfile="config/vendor/$vcfg/pkg.cfg"
	[ -L "$vfile" ] && $err "'$archive', '$board': $vfile is a symlink"
	[ -f "$vfile" ] || $err "'$archive', '$board': $vfile doesn't exist"

	cbdir="src/coreboot/$tree"
	cbfstool="elf/cbfstool/$tree/cbfstool"
	rmodtool="elf/cbfstool/$tree/rmodtool"
	mecleaner="$PWD/$cbdir/util/me_cleaner/me_cleaner.py"
	kbc1126_ec_dump="$PWD/$cbdir/util/kbc1126/kbc1126_ec_dump"
	cbfstool="elf/cbfstool/$tree/cbfstool"
	ifdtool="elf/ifdtool/$tree/ifdtool"
	[ -n "$IFD_platform" ] && ifdprefix="-p $IFD_platform"; :
}

patch_release_roms()
{
	has_hashes="n"

	tmpromdir="tmp/DO_NOT_FLASH/bin/$board"
	remkdir "${tmpromdir%"/bin/$board"}"
	tar -xf "$archive" -C "${tmpromdir%"/bin/$board"}" || \
		$err "Can't extract '$archive'"

	for _hashes in $hashfiles; do
		[ -L "$tmpromdir/$_hashes" ] && \
		    $err "'$archive' -> the hashfile is a symlink. $dontflash"
		[ -f "$tmpromdir/$_hashes" ] && has_hashes="y" && \
		    hashfile="$_hashes" && break; :
	done

	x_ mkdir -p "tmp"; [ -L "tmp/rom.list" ] && \
	    $err "'$archive' -> tmp/rom.list is a symlink - $dontflash"
	x_ rm -f "tmp/rom.list" "tmp/zero.1b"
	x_ dd if=/dev/zero of=tmp/zero.1b bs=1 count=1

	find "$tmpromdir" -maxdepth 1 -type f -name "*.rom" > "tmp/rom.list" \
	    || $err "'$archive' -> Can't make tmp/rom.list - $dontflash"

	if readkconfig; then
		while read -r _xrom ; do
			process_release_rom "$_xrom" || break
		done < "tmp/rom.list"
		rm -f "$tmpromdir/README.md" || :
		[ "$nukemode" != "nuke" ] || \
		    printf "Make sure you inserted vendor files: %s\n" \
		    "$vguide" > "$tmpromdir/README.md" || :
	else
		printf "Skipping vendorfiles on '%s'\n" "$archive" 1>&2
	fi

	(
	cd "$tmpromdir" || $err "patch '$archive': can't cd $tmpromdir"
	# NOTE: For compatibility with older rom releases, defer to sha1
	if [ "$has_hashes" = "y" ] && [ "$nukemode" != "nuke" ]; then
		sha512sum --status -c "$hashfile" || \
		    sha1sum --status -c "$hashfile" || \
		    $err "'$archive' -> Can't verify vendor hashes. $dontflash"
		rm -f "$hashfile" || \
		    $err "$archive: Can't rm hashfile. $dontflash"
	fi
	) || $err "'$archive' -> Can't verify vendor hashes. $dontflash"

	if [ -n "$new_mac" ]; then
		if ! modify_mac_addresses; then
			printf "\nNo GbE region defined for '%s'\n" "$board" \
			    1>&2
			printf "Therefore, changing the MAC is impossible.\n" \
			    1>&2
			printf "This board probably lacks Intel ethernet.\n" \
			    1>&2
			printf "(or it's pre-IFD Intel with Intel GbE NIC)\n" \
			    1>&2
		fi
	fi

	[ "$xchanged" = "y" ] || rm -Rf "$tmpromdel" || :
	[ "$xchanged" = "y" ] || return 0
	(
		cd "${tmpromdir%"/bin/$board"}" || \
		    $err "Can't cd '${tmpromdir%"/bin/$board"}'; $dontflash"
		# ../../ is the root of lbmk
		mkrom_tarball "bin/$board"
	) || $err "Cannot re-generate '$archive' - $dontflash"

	mv "${tmpromdir%"/bin/$board"}/bin/${relname}_${board}.tar.xz" \
	    "$archive" || \
	    $err "'$archive' -> Cannot overwrite - $dontflash"; :
}

process_release_rom()
{
	_xrom="$1"; _xromname="${1##*/}"
	[ -L "$_xrom" ] && \
	    $err "$archive -> '${_xrom#"tmp/DO_NOT_FLASH/"}' is a symlink"
	[ -f "$_xrom" ] || return 0

	[ -z "${_xromname#"$vfix"}" ] && \
	    $err "'$_xromname'->'"${_xromname#"$vfix"}"' empty. $dontflash"
	# Remove the prefix and 1-byte pad
	if [ "$nukemode" != "nuke" ] && \
	    [ "${_xromname#"$vfix"}" != "$_xromname" ]; then
		_xromnew="${_xrom%/*}/${_xromname#"$vfix"}"

		# Remove the 1-byte padding
		stat -c '%s' "$_xrom" > "tmp/rom.size" || \
		    $err "$_xrom: Can't get rom size. $dontflash"
		read -r xromsize < "tmp/rom.size" || \
		    $err "$_xrom: Can't read rom size. $dontflash"

		expr "X$xromsize" : "X-\{0,1\}[0123456789][0123456789]*$" \
		    1>/dev/null 2>/dev/null || $err "$_xrom size non-integer"
		[ $xromsize -lt 2 ] && $err \
		    "$_xrom: Will not create empty file. $dontflash"

		# TODO: check whether the size would be a multiple of 64KB
		# the smallest rom images we do are 512kb	
		xromsize="`expr $xromsize - 1`"
		[ $xromsize -lt 524288 ] && \
		    $err "$_xrom size too small; likely not a rom. $dontflash"

		dd if="$_xrom" of="$_xromnew" bs=$xromsize count=1 || \
		    $err "$_xrom: Can't resize. $dontflash"
		rm -f "$_xrom" || $err "Can't rm $_xrom - $dontflash"

		_xrom="$_xromnew"
	fi

	[ "$nukemode" = "nuke" ] && \
		mksha512sum "$_xrom" "vendorhashes"

	patch_rom "$_xrom" || return 1 # if break return, can still change MAC
	[ "$nukemode" != "nuke" ] && return 0

	# Rename the file, prefixing a warning saying not to flash
	# the target image, which now has vendor files removed. Also
	# pad it so that flashprog returns an error if the user tries
	# to flash it, due to mismatching ROM size vs chip size
	cat "$_xrom" tmp/zero.1b > "${_xrom%/*}/$vfix${_xrom##*/}" || \
	    $err "'$archive' -> can't pad/rename '$_xrom'. $dontflash"
	rm -f "$_xrom" || $err "'$archive' -> can't rm '$_xrom'. $dontflash"
}

patch_rom()
{
	rom="$1"

	# regarding ifs below:
	# if a hash file exists, we only want to allow inject.
	# if a hash file is missing, we only want to allow nuke.
	# this logical rule prevents double-nuke and double-inject

	# if injecting without a hash file i.e. inject what was injected
	# (or inject where no vendor files are needed, covered previously)
	if [ "$has_hashes" != "y" ] && [ "$nukemode" != "nuke" ]; then
		printf "inject: '%s' has no hash file. Skipping.\n" \
		    "$archive" 1>&2
		return 1
	fi
	# nuking *with* a hash file, i.e. nuking what was nuked before
	if [ "$has_hashes" = "y" ] && [ "$nukemode" = "nuke" ]; then
		printf "inject nuke: '%s' has a hash file. Skipping nuke.\n" \
		    "$archive" 1>&2
		return 1
	fi

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
	# TODO: modify gbe *after checksum verification only*
	# TODO: insert default gbe if doing -n nuke

	printf "ROM image successfully patched: %s\n" "$rom"
	xchanged="y"
}

inject()
{
	[ $# -lt 3 ] && $err "$*, $rom: usage: inject name path type (offset)"
	[ "$2" = "/dev/null" ] && return 0

	eval "`setvars "" cbfsname _dest _t _offset`"
	cbfsname="$1"; _dest="${2##*../}"; _t="$3"

	if [ "$_t" = "fsp" ]; then
		[ $# -gt 3 ] && _offset="$4"
	else
		[ $# -gt 3 ] && _offset="-b $4" && [ -z "$4" ] && \
		    $err "inject $*, $rom: offset given but empty (undefined)"
	fi

	e "$_dest" f n && [ "$nukemode" != "nuke" ] && $err "!inject $dl_type"

	if [ "$cbfsname" = "IFD" ]; then
		[ "$nukemode" = "nuke" ] || "$ifdtool" $ifdprefix -i \
		    $_t:$_dest "$rom" -O "$rom" || \
		    $err "failed: inject '$_t' '$_dest' on '$rom'"
		[ "$nukemode" != "nuke" ] || "$ifdtool" $ifdprefix --nuke $_t \
		    "$rom" -O "$rom" || $err "$rom: !nuke IFD/$_t"
		xchanged="y"
		return 0
	elif [ "$nukemode" = "nuke" ]; then
		"$cbfstool" "$rom" remove -n "$cbfsname" || \
		    $err "inject $rom: can't remove $cbfsname"
		xchanged="y"
		return 0
	fi
	if [ "$_t" = "stage" ]; then # the only stage we handle is refcode
		x_ mkdir -p tmp; x_ rm -f "tmp/refcode"
		"$rmodtool" -i "$_dest" -o "tmp/refcode" || "!reloc refcode"
		"$cbfstool" "$rom" add-stage -f "tmp/refcode" -n "$cbfsname" \
		    -t stage || $err "$rom: !add ref"
	else
		"$cbfstool" "$rom" add -f "$_dest" -n "$cbfsname" \
		    -t $_t $_offset || $err "$rom !add $_t ($_dest)"
	fi; xchanged="y"; :
}

modify_mac_addresses()
{
	[ "$nukemode" = "nuke" ] && \
	    $err "Cannot modify MAC addresses while nuking vendor files"

	# chkvars CONFIG_GBE_BIN_PATH
	[ -n "$CONFIG_GBE_BIN_PATH" ] || return 1
	e "${CONFIG_GBE_BIN_PATH##*../}" f n && $err "missing gbe file"

	x_ make -C util/nvmutil
	x_ mkdir -p tmp
	[ -L "tmp/gbe" ] && $err "tmp/gbe exists but is a symlink"
	[ -d "tmp/gbe" ] && $err "tmp/gbe exists but is a directory"
	if [ -e "tmp/gbe" ]; then
		[ -f "tmp/gbe" ] || $err "tmp/gbe exists and is not a file"
	fi
	x_ cp "${CONFIG_GBE_BIN_PATH##*../}" "tmp/gbe"

	x_ "util/nvmutil/nvm" "tmp/gbe" setmac "$new_mac"

	find "$tmpromdir" -maxdepth 1 -type f -name "*.rom" > "tmp/rom.list" \
	    || $err "'$archive' -> Can't make tmp/rom.list - $dontflash"

	while read -r _xrom; do
		[ -L "$_xrom" ] && continue
		[ -f "$_xrom" ] || continue
		"$ifdtool" $ifdprefix -i GbE:"tmp/gbe" "$_xrom" -O \
		    "$_xrom" || $err "'$_xrom': Can't insert new GbE file"
		xchanged="y"
	done < "tmp/rom.list"
	printf "\nThe following GbE NVM words were written in '%s':\n" \
	    "$archive"
	x_ util/nvmutil/nvm tmp/gbe dump
}
