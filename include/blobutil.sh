# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: 2023 Leah Rowe <leah@libreboot.org>

_ua="Mozilla/5.0 (Windows NT 10.0; rv:91.0) Gecko/20100101 Firefox/91.0"

_7ztest="a"
blobdir="blobs"
appdir="${blobdir}/app"
cbdir="coreboot/default"
cbcfgsdir="config/coreboot"
ifdtool="cbutils/default/ifdtool"
cbfstool="cbutils/default/cbfstool"
nvmutil="util/nvmutil/nvm"
pciromsdir="pciroms"

mecleaner="$(pwd)/me_cleaner/me_cleaner.py"
me7updateparser="$(pwd)/util/me7_update_parser/me7_update_parser.py"
e6400_unpack="$(pwd)/bios_extract/dell_inspiron_1100_unpacker.py"
kbc1126_ec_dump="$(pwd)/${cbdir}/util/kbc1126/kbc1126_ec_dump"
pfs_extract="$(pwd)/biosutilities/Dell_PFS_Extract.py"
uefiextract="$(pwd)/uefitool/uefiextract"

eval "$(setvars "" EC_url EC_url_bkup EC_hash DL_hash DL_url DL_url_bkup _dest \
    E6400_VGA_DL_hash E6400_VGA_DL_url E6400_VGA_DL_url_bkup E6400_VGA_offset \
    E6400_VGA_romname SCH5545EC_DL_url SCH5545EC_DL_url_bkup SCH5545EC_DL_hash \
    MRC_url MRC_url_bkup MRC_hash MRC_board archive rom board modifygbe _dl \
    new_mac release releasearchive _b boarddir)"

eval "$(setvars "" CONFIG_BOARD_DELL_E6400 CONFIG_HAVE_MRC CONFIG_HAVE_ME_BIN \
    CONFIG_ME_BIN_PATH CONFIG_KBC1126_FIRMWARE CONFIG_KBC1126_FW1 \
    CONFIG_KBC1126_FW1_OFFSET CONFIG_KBC1126_FW2 CONFIG_KBC1126_FW2_OFFSET \
    CONFIG_VGA_BIOS_FILE CONFIG_VGA_BIOS_ID CONFIG_GBE_BIN_PATH \
    CONFIG_INCLUDE_SMSC_SCH5545_EC_FW CONFIG_SMSC_SCH5545_EC_FW_FILE \
    CONFIG_IFD_BIN_PATH CONFIG_MRC_FILE)"

check_defconfig()
{
	for x in "${1}"/config/*; do
		[ -f "${x}" ] && return 0
	done
	return 1
}

fetch()
{
	dl_type="${1}"
	dl="${2}"
	dl_bkup="${3}"
	dlsum="${4}"
	[ "${5# }" = "${5}" ] || err "fetch: space not allowed in _dest: '${5}'"
	[ "${5#/}" = "${5}" ] || err "fetch: absolute path not allowed: '${5}'"
	_dest="${5##*../}"
	_dl="${blobdir}/cache/${dlsum}"

	mkdir -p "${_dl%/*}" || err "fetch: !mkdir ${_dl%/*}"

	dl_fail="y"
	vendor_checksum "${dlsum}" "${_dl}" && dl_fail="n"
	for url in "${dl}" "${dl_bkup}"; do
		[ "${dl_fail}" = "n" ] && break
		[ -z "${url}" ] && continue
		rm -f "${_dl}" || err "fetch: !rm -f ${_dl}"
		curl --location --retry 3 -A "${_ua}" "${url}" -o "${_dl}" || \
		    wget --tries 3 -U "${_ua}" "${url}" -O "${_dl}" || \
		    continue
		vendor_checksum "${dlsum}" "${_dl}" && dl_fail="n"
	done
	[ "${dl_fail}" = "y" ] && \
		err "fetch ${dlsum}: matched file unavailable"

	rm -Rf "${_dl}_extracted" || err "!rm ${_dl}_extracted"
	mkdirs "${_dest}" "extract_${dl_type}" || return 0
	eval "extract_${dl_type}"

	[ -f "${_dest}" ] && return 0
	err "extract_${dl_type} (fetch): missing file: '${_dest}'"
}

vendor_checksum()
{
	if [ "$(sha512sum ${2} | awk '{print $1}')" != "${1}" ]; then
		printf "Bad checksum for file: %s\n" "${2}" 1>&2
		rm -f "${2}" || :
		return 1
	fi
}

mkdirs()
{
	[ -f "${1}" ] && \
		printf "mkdirs ${1} ${2}: already downloaded\n" 1>&2 && return 1
	mkdir -p "${1%/*}" || err "mkdirs ${1} ${2}: !mkdir ${1%/*}"
	rm -Rf "${appdir}" || err "mkdirs ${1} ${2}: can't remove ${appdir}"
	mkdir -p "${appdir}/" || err "mkdirs ${1} ${2}: !mkdir ${appdir}"
	extract_archive "${_dl}" "${appdir}" || \
	    [ "${2}" = "extract_e6400vga" ] || err "mkdirs ${1} ${2}: !extract"
}

extract_archive()
{
	innoextract "${1}" -d "${2}" || python "${pfs_extract}" "${1}" -e || \
	    7z x "${1}" -o"${2}" || unar "${1}" -o "${2}" || \
	    unzip "${1}" -d "${2}" || return 1
}
