# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: 2022 Caleb La Grange <thonkpeasant@protonmail.com>
# SPDX-FileCopyrightText: 2022 Ferass El Hafidi <vitali64pmemail@protonmail.com>
# SPDX-FileCopyrightText: 2023-2024 Leah Rowe <leah@libreboot.org>

_ua="Mozilla/5.0 (Windows NT 10.0; rv:91.0) Gecko/20100101 Firefox/91.0"
_7ztest="a"

e6400_unpack="${PWD}/src/bios_extract/dell_inspiron_1100_unpacker.py"
me7updateparser="${PWD}/util/me7_update_parser/me7_update_parser.py"
pfs_extract="${PWD}/src/biosutilities/Dell_PFS_Extract.py"
uefiextract="${PWD}/src/uefitool/uefiextract"
nvmutil="util/nvmutil/nvm"
vendir="vendorfiles"
appdir="${vendir}/app"

eval "$(setvars "" _b EC_url_bkup EC_hash DL_hash DL_url_bkup MRC_refcode_gbe \
    E6400_VGA_DL_hash E6400_VGA_DL_url E6400_VGA_DL_url_bkup E6400_VGA_offset \
    E6400_VGA_romname SCH5545EC_DL_url SCH5545EC_DL_url_bkup SCH5545EC_DL_hash \
    mecleaner kbc1126_ec_dump MRC_refcode_cbtree new_mac _dl CONFIG_HAVE_MRC \
    CONFIG_BOARD_DELL_E6400 CONFIG_HAVE_ME_BIN archive EC_url modifygbe \
    CONFIG_ME_BIN_PATH CONFIG_KBC1126_FIRMWARE CONFIG_KBC1126_FW1 _dest tree \
    CONFIG_KBC1126_FW1_OFFSET CONFIG_KBC1126_FW2 CONFIG_KBC1126_FW2_OFFSET rom \
    CONFIG_VGA_BIOS_FILE CONFIG_VGA_BIOS_ID CONFIG_GBE_BIN_PATH release DL_url \
    CONFIG_INCLUDE_SMSC_SCH5545_EC_FW CONFIG_SMSC_SCH5545_EC_FW_FILE nukemode \
    CONFIG_IFD_BIN_PATH CONFIG_MRC_FILE CONFIG_HAVE_REFCODE_BLOB cbfstoolref \
    CONFIG_REFCODE_BLOB_FILE)"

vendor_download()
{
	set +u +e
	export PATH="${PATH}:/sbin"

	[ $# -gt 0 ] || $err "No argument given"
	board="${1}"
	boarddir="${cbcfgsdir}/${board}"
	_b="${board%%_*mb}" # shorthand (no duplication per rom size)

	detect_firmware && exit 0
	scan_config "${_b}" "config/vendor"

	build_dependencies_download
	download_vendorfiles
}

detect_firmware()
{
	[ -d "$boarddir" ] || $err "Target '$board' not defined."
	check_defconfig "${boarddir}" && exit 0

	set -- "${boarddir}/config/"*
	. "${1}" 2>/dev/null
	. "${boarddir}/target.cfg" 2>/dev/null

	[ -z "$tree" ] && $err "detect_firmware $boarddir: tree undefined"
	cbdir="src/coreboot/$tree"
	cbfstool="cbutils/$tree/cbfstool"

	mecleaner="${PWD}/${cbdir}/util/me_cleaner/me_cleaner.py"
	kbc1126_ec_dump="${PWD}/${cbdir}/util/kbc1126/kbc1126_ec_dump"

	for c in CONFIG_HAVE_MRC CONFIG_HAVE_ME_BIN CONFIG_KBC1126_FIRMWARE \
	    CONFIG_VGA_BIOS_FILE CONFIG_INCLUDE_SMSC_SCH5545_EC_FW; do
		eval "[ -z \"\${${c}}\" ] || return 1"
	done
	printf "Vendor files not needed for: %s\n" "${board}" 1>&2
}

build_dependencies_download()
{
	[ -d "${cbdir}" ] || x_ ./update trees -f coreboot ${cbdir##*/}
	for d in uefitool biosutilities bios_extract; do
		[ -d "src/${d}" ] && continue
		x_ ./update trees -f "${d}"
	done
	[ -f "${uefiextract}" ] || x_ ./update trees -b uefitool
	[ ! -d "${kbc1126_ec_dump%/*}" ] || [ -f "${kbc1126_ec_dump}" ] || x_ \
	    make -C "${cbdir}/util/kbc1126"
	[ -n "$MRC_refcode_cbtree" ] && \
		cbfstoolref="cbutils/$MRC_refcode_cbtree/cbfstool"
	[ -z "$cbfstoolref" ] || [ -f "$cbfstoolref" ] || \
	    x_ ./update trees -b coreboot utils $MRC_refcode_cbtree
	[ -f "${cbfstool}" ] && [ -f "${ifdtool}" ] && return 0
	x_ ./update trees -b coreboot utils $tree
}

download_vendorfiles()
{
	[ -z "${CONFIG_HAVE_ME_BIN}" ] || \
		fetch intel_me "$DL_url" "$DL_url_bkup" "$DL_hash" \
		    "${CONFIG_ME_BIN_PATH}"
	[ -z "${CONFIG_INCLUDE_SMSC_SCH5545_EC_FW}" ] || \
		fetch sch5545ec "$SCH5545EC_DL_url" "$SCH5545EC_DL_url_bkup" \
		    "$SCH5545EC_DL_hash" "$CONFIG_SMSC_SCH5545_EC_FW_FILE"
	[ -z "${CONFIG_KBC1126_FIRMWARE}" ] || \
		fetch kbc1126ec "$EC_url" "$EC_url_bkup" "$EC_hash" \
		    "${CONFIG_KBC1126_FW1}"
	[ -z "${CONFIG_VGA_BIOS_FILE}" ] || \
		fetch "e6400vga" "$E6400_VGA_DL_url" "$E6400_VGA_DL_url_bkup" \
		    "$E6400_VGA_DL_hash" "$CONFIG_VGA_BIOS_FILE"
	[ -z "${CONFIG_HAVE_MRC}" ] && return 0
	fetch "mrc" "$MRC_url" "$MRC_url_bkup" "$MRC_hash" "$CONFIG_MRC_FILE"
}

fetch()
{
	dl_type="${1}"
	dl="${2}"
	dl_bkup="${3}"
	dlsum="${4}"
	[ "${5}" = "/dev/null" ] && return 0
	[ "${5# }" = "$5" ] || $err "fetch: space not allowed in _dest: '$5'"
	[ "${5#/}" = "$5" ] || $err "fetch: absolute path not allowed: '$5'"
	_dest="${5##*../}"
	_dl="${vendir}/cache/${dlsum}"
	dl_fail="n"

	x_ mkdir -p "${_dl%/*}"

	dl_fail="y"
	vendor_checksum "${dlsum}" "${_dl}" || dl_fail="n"
	for url in "${dl}" "${dl_bkup}"; do
		[ "${dl_fail}" = "n" ] && break
		[ -z "${url}" ] && continue
		x_ rm -f "${_dl}"
		curl --location --retry 3 -A "$_ua" "$url" -o "$_dl" || \
		    wget --tries 3 -U "$_ua" "$url" -O "$_dl" || continue
		vendor_checksum "${dlsum}" "${_dl}" || dl_fail="n"
	done
	[ "${dl_fail}" = "y" ] && \
		$err "fetch ${dlsum}: matched file unavailable"

	x_ rm -Rf "${_dl}_extracted"
	mkdirs "${_dest}" "extract_${dl_type}" || return 0
	eval "extract_${dl_type}"

	[ -f "${_dest}" ] && return 0
	$err "extract_${dl_type} (fetch): missing file: '${_dest}'"
}

vendor_checksum()
{
	[ "$(sha512sum "$2" | awk '{print $1}')" != "$1" ] || return 1
	printf "Bad checksum for file: %s\n" "$2" 1>&2
	rm -f "$2" || :
}

mkdirs()
{
	if [ -f "${1}" ]; then
		printf "mkdirs %s %s: already downloaded\n" "$1" "$2" 1>&2
		return 1
	fi
	mkdir -p "${1%/*}" || $err "mkdirs: !mkdir -p ${1%/*}"
	remkdir "${appdir}"
	extract_archive "${_dl}" "${appdir}" || \
	    [ "${2}" = "extract_e6400vga" ] || \
	    $err "mkdirs ${1} ${2}: !extract"
}

extract_intel_me()
{
	[ ! -f "$mecleaner" ] && \
		$err "extract_intel_me $cbdir: me_cleaner missing"

	_me="${PWD}/${_dest}" # must always be an absolute path
	cdir="${PWD}/${appdir}" # must always be an absolute path
	[ $# -gt 0 ] && _me="${1}" && cdir="${2}"
	[ -f "${_me}" ] && return 0

	sdir="$(mktemp -d)"
	[ -z "$sdir" ] && return 0
	mkdir -p "$sdir" || $err "extract_intel_me: !mkdir -p \"$sdir\""
	(
	[ "${cdir#/a}" != "$cdir" ] && cdir="${cdir#/}"
	cd "$cdir" || $err "extract_intel_me: !cd \"$cdir\""
	for i in *; do
		[ -f "$_me" ] && break
		[ -L "$i" ] && continue
		if [ -f "$i" ]; then
			"$mecleaner" -r -t -O "${sdir}/vendorfile" \
			    -M "$_me" "$i" && break
			"$mecleaner" -r -t -O "$_me" "$i" && break
			"$me7updateparser" -O "$_me" "$i" && break
			_7ztest="${_7ztest}a"
			extract_archive "$i" "$_7ztest" || continue
			extract_intel_me "$_me" "${cdir}/${_7ztest}"
		elif [ -d "$i" ]; then
			extract_intel_me "$_me" "${cdir}/${i}"
		else
			continue
		fi
		cdir="${1}"
		[ "${cdir#/a}" != "$cdir" ] && cdir="${cdir#/}"
		cd "${cdir}" || :
	done
	)
	rm -Rf "${sdir}" || $err "extract_intel_me: !rm -Rf ${sdir}"
}

extract_archive()
{
	innoextract "$1" -d "$2" || python "$pfs_extract" "$1" -e || 7z x "$1" \
	    -o"$2" || unar "$1" -o "$2" || unzip "$1" -d "$2" || return 1
}

extract_kbc1126ec()
{
	[ ! -f "$kbc1126_ec_dump" ] && \
		$err "extract_kbc1126ec $cbdir: kbc1126_ec_dump missing"
	(
	x_ cd "${appdir}/"
	mv Rompaq/68*.BIN ec.bin || :
	if [ ! -f ec.bin ]; then
		unar -D ROM.CAB Rom.bin || unar -D Rom.CAB Rom.bin || \
		    unar -D 68*.CAB Rom.bin || $err "can't extract Rom.bin"
		x_ mv Rom.bin ec.bin
	fi
	[ -f ec.bin ] || $err "extract_kbc1126_ec ${board}: can't extract"
	"${kbc1126_ec_dump}" ec.bin || \
	    $err "extract_kbc1126_ec ${board}: can't extract ecfw1/2.bin"
	) || $err "can't extract kbc1126 ec firmware"
	ec_ex="y"
	for i in 1 2; do
		[ -f "${appdir}/ec.bin.fw${i}" ] || ec_ex="n"
	done
	[ "${ec_ex}" = "y" ] || \
	    $err "extract_kbc1126_ec ${board}: didn't extract ecfw1/2.bin"
	cp "${appdir}/"ec.bin.fw* "${_dest%/*}/" || \
	    $err "extract_kbc1126_ec ${board}: can't copy ec binaries"
}

extract_e6400vga()
{
	for v in E6400_VGA_offset E6400_VGA_romname; do
		eval "[ -z \"\$$v\" ] && $err \"extract_e6400vga: $v undefined\""
	done
	tail -c +$E6400_VGA_offset "$_dl" | gunzip > "$appdir/bios.bin" || :
	(
	x_ cd "${appdir}"
	[ -f "bios.bin" ] || $err "extract_e6400vga: can't extract bios.bin"
	"${e6400_unpack}" bios.bin || printf "TODO: fix dell extract util\n"
	[ -f "${E6400_VGA_romname}" ] || \
		$err "extract_e6400vga: can't extract vga rom from bios.bin"
	) || $err "can't extract e6400 vga rom"
	cp "${appdir}/${E6400_VGA_romname}" "${_dest}" || \
	    $err "extract_e6400vga ${board}: can't copy vga rom to ${_dest}"
}

extract_sch5545ec()
{
	# full system ROM (UEFI), to extract with UEFIExtract:
	_bios="${_dl}_extracted/Firmware/1 ${dlsum} -- 1 System BIOS vA.28.bin"
	# this is the SCH5545 firmware, inside of the extracted UEFI ROM:
	_sch5545ec_fw="${_bios}.dump/4 7A9354D9-0468-444A-81CE-0BF617D890DF"
	_sch5545ec_fw="${_sch5545ec_fw}/54 D386BEB8-4B54-4E69-94F5-06091F67E0D3"
	_sch5545ec_fw="${_sch5545ec_fw}/0 Raw section/body.bin" # <-- this!

	# this makes the file defined by _sch5545ec_fw available to copy
	"${uefiextract}" "${_bios}" || \
	    $err "extract_sch5545ec: cannot extract from uefi image"
	cp "${_sch5545ec_fw}" "${_dest}" || \
	    $err "extract_sch5545ec: cannot copy sch5545ec firmware file"
}

vendor_inject()
{
	set +u +e

	[ $# -lt 1 ] && $err "No options specified."
	[ "${1}" = "listboards" ] && eval "items config/coreboot || :; exit 0"

	archive="${1}"

	while getopts n:r:b:m: option; do
		case "${option}" in
		n) nukemode="${OPTARG}" ;;
		r) rom=${OPTARG} ;;
		b) board=${OPTARG} ;;
		m) modifygbe=true
		   new_mac=${OPTARG} ;;
		*) : ;;
		esac
	done

	check_board
	build_dependencies_inject
	inject_vendorfiles
	[ "${nukemode}" = "nuke" ] && return 0
	printf "Friendly reminder (this is *not* an error message):\n"
	printf "Please ensure that the files were inserted correctly.\n"
}

check_board()
{
	failcheck="n"
	check_release "${archive}" || failcheck="y"
	if [ "${failcheck}" = "y" ]; then
		[ -f "$rom" ] || $err "check_board \"$rom\": invalid path"
		[ -z "${rom+x}" ] && $err "check_board: no rom specified"
		[ -n "${board+x}" ] || board=$(detect_board "${rom}")
	else
		release="y"
		board=$(detect_board "${archive}")
	fi

	boarddir="${cbcfgsdir}/${board}"
	[ -d "$boarddir" ] || $err "check_board: board $board missing"
	[ -f "$boarddir/target.cfg" ] || \
		$err "check_board $board: target.cfg missing"
	. "$boarddir/target.cfg" 2>/dev/null
	[ -z "$tree" ] && $err "check_board $board: tree undefined"; return 0
}

check_release()
{
	[ -f "${archive}" ] || return 1
	[ "${archive##*.}" = "xz" ] || return 1
	printf "%s\n" "Release archive ${archive} detected"
}

# This function tries to determine the board from the filename of the rom.
# It will only succeed if the filename is not changed from the build/download
detect_board()
{
	path="${1}"
	filename=$(basename "${path}")
	case ${filename} in
	grub_*)
		board=$(echo "${filename}" | cut -d '_' -f2-3) ;;
	seabios_withgrub_*)
		board=$(echo "${filename}" | cut -d '_' -f3-4) ;;
	*.tar.xz)
		_stripped_prefix=${filename#*_}
		board="${_stripped_prefix%.tar.xz}" ;;
	*)
		$err "detect_board $filename: could not detect board type"
	esac
	printf "%s\n" "${board}"
}

build_dependencies_inject()
{
	cbdir="src/coreboot/$tree"
	cbfstool="cbutils/$tree/cbfstool"
	ifdtool="cbutils/$tree/ifdtool"
	[ -d "${cbdir}" ] || x_ ./update trees -f coreboot $tree
	if [ ! -f "${cbfstool}" ] || [ ! -f "${ifdtool}" ]; then
		x_ ./update trees -b coreboot utils $tree
	fi
	[ -z "$new_mac" ] || [ -f "$nvmutil" ] || x_ make -C util/nvmutil
	[ "$nukemode" = "nuke" ] || x_ ./vendor download $board; return 0
}

inject_vendorfiles()
{
	[ "${release}" != "y" ] && eval "patch_rom \"$rom\"; return 0"
	patch_release_roms
}

patch_release_roms()
{
	_tmpdir="tmp/romdir"
	remkdir "${_tmpdir}"
	tar -xf "${archive}" -C "${_tmpdir}" || \
	    $err "patch_release_roms: !tar -xf \"$archive\" -C \"$_tmpdir\""

	for x in "${_tmpdir}"/bin/*/*.rom ; do
		printf "patching rom: %s\n" "$x"
		patch_rom "${x}"
	done

	(
	cd "${_tmpdir}/bin/"* || \
	    $err "patch_release_roms: !cd ${_tmpdir}/bin/*"

	# NOTE: For compatibility with older rom releases, defer to sha1
	[ "${nukemode}" = "nuke" ] || sha512sum --status -c vendorhashes || \
	    sha1sum --status -c vendorhashes || sha512sum --status -c \
	    blobhashes || sha1sum --status -c blobhashes || \
	    $err "patch_release_roms: ROMs did not match expected hashes"
	) || $err "can't verify vendor hashes"

	[ "${modifygbe}" = "true" ] && \
		for x in "${_tmpdir}"/bin/*/*.rom ; do
			modify_gbe "${x}"
		done

	[ -d bin/release ] || x_ mkdir -p bin/release
	x_ mv "${_tmpdir}"/bin/* bin/release/
	x_ rm -Rf "${_tmpdir}"

	printf "Success! Your ROMs are in bin/release\n"
}

patch_rom()
{
	rom="${1}"

	check_defconfig "$boarddir" && $err "patch_rom $boarddir: no configs"

	set -- "${boarddir}/config/"*
	. "${1}" 2>/dev/null

	[ "$CONFIG_HAVE_MRC" = "y" ] && \
		inject "mrc.bin" "${CONFIG_MRC_FILE}" "mrc" "0xfffa0000"
	[ -n "$CONFIG_HAVE_REFCODE_BLOB" ] && \
		inject "fallback/refcode" "$CONFIG_REFCODE_BLOB_FILE" "stage"
	[ "${CONFIG_HAVE_ME_BIN}" = "y" ] && \
		inject "IFD" "${CONFIG_ME_BIN_PATH}" "me"
	[ "${CONFIG_KBC1126_FIRMWARE}" = "y" ] && \
		inject "ecfw1.bin" "$CONFIG_KBC1126_FW1" "raw" \
		    "${CONFIG_KBC1126_FW1_OFFSET}" && \
		inject "ecfw2.bin" "$CONFIG_KBC1126_FW2" "raw" \
		    "${CONFIG_KBC1126_FW2_OFFSET}"
	[ -n "$CONFIG_VGA_BIOS_FILE" ] && [ -n "$CONFIG_VGA_BIOS_ID" ] && \
		inject "pci${CONFIG_VGA_BIOS_ID}.rom" \
		    "${CONFIG_VGA_BIOS_FILE}" "optionrom"
	[ "${CONFIG_INCLUDE_SMSC_SCH5545_EC_FW}" = "y" ] && \
	    [ -n "${CONFIG_SMSC_SCH5545_EC_FW_FILE}" ] && \
		inject "sch5545_ecfw.bin" "$CONFIG_SMSC_SCH5545_EC_FW_FILE" raw
	[ "${modifygbe}" = "true" ] && ! [ "${release}" = "y" ] && \
		inject "IFD" "${CONFIG_GBE_BIN_PATH}" "GbE"

	printf "ROM image successfully patched: %s\n" "${rom}"
}

inject()
{
	[ $# -lt 3 ] && \
		$err "inject $@, $rom: usage: inject name path type (offset)"

	eval "$(setvars "" cbfsname _dest _t _offset)"
	cbfsname="${1}"
	_dest="${2##*../}"
	_t="${3}"
	[ $# -gt 3 ] && _offset="-b ${4}" && [ -z "${4}" ] && \
	    $err "inject $@, $rom: offset passed, but empty (not defined)"

	[ -z "${_dest}" ] && $err "inject $@, ${rom}: empty destination path"
	[ ! -f "${_dest}" ] && [ "${nukemode}" != "nuke" ] && \
		$err "inject_${dl_type}: file missing, ${_dest}"

	[ "$nukemode" = "nuke" ] || \
		printf "Inserting %s/%s in file: %s\n" "$cbfsname" "$_t" "$rom"

	if [ "${_t}" = "GbE" ]; then
		x_ mkdir -p tmp
		cp "${_dest}" "tmp/gbe.bin" || \
		    $err "inject: !cp \"${_dest}\" \"tmp/gbe.bin\""
		_dest="tmp/gbe.bin"
		"${nvmutil}" "${_dest}" setmac "${new_mac}" || \
		    $err "inject ${_dest}: can't change mac address"
	fi
	if [ "${cbfsname}" = "IFD" ]; then
		if [ "${nukemode}" != "nuke" ]; then
			"$ifdtool" -i ${_t}:${_dest} "$rom" -O "$rom" || \
			    $err "inject: can't insert $_t ($dest) into $rom"
		else
			"$ifdtool" --nuke $_t "$rom" -O "$rom" || \
			    $err "inject $rom: can't nuke $_t in IFD"
		fi
	else
		if [ "${nukemode}" != "nuke" ]; then
			if [ "$_t" = "stage" ]; then # broadwell refcode
				"$cbfstool" "$rom" add-stage -f "$_dest" \
				    -n "$cbfsname" -t stage -c lzma
			else
				"$cbfstool" "$rom" add -f "$_dest" \
				    -n "$cbfsname" -t $_t $_offset || \
				    $err "$rom: can't insert $_t file $_dest"
			fi
		else
			"$cbfstool" "$rom" remove -n "$cbfsname" || \
			    $err "inject $rom: can't remove $cbfsname"
		fi
	fi
}
