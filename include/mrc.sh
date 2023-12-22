# SPDX-License-Identifier: GPL-2.0-only

# Logic based on util/chromeos/crosfirmware.sh in coreboot cfc26ce278.
# Modifications in this version are Copyright 2021 and 2023 Leah Rowe.
# Original copyright detailed in repo: https://review.coreboot.org/coreboot/

eval "$(setvars "" MRC_url MRC_url_bkup MRC_hash MRC_board SHELLBALL)"

extract_mrc()
{
	[ -z "${MRC_board}" ] && err "extract_mrc $MRC_hash: MRC_board not set"
	[ -z "${CONFIG_MRC_FILE}" ] && \
		err "extract_mrc $MRC_hash: CONFIG_MRC_FILE not set"

	SHELLBALL="chromeos-firmwareupdate-${MRC_board}"

	(
	x_ cd "${appdir}"
	extract_partition "${MRC_url##*/}"
	extract_archive "${SHELLBALL}" .
	) || err "mrc download/extract failure"

	"${cbfstool}" "${appdir}/"bios.bin extract -n mrc.bin \
	    -f "${_dest}" -r RO_SECTION || err "extract_mrc: cbfstool ${_dest}"
}

extract_partition()
{
	printf "Extracting ROOT-A partition\n"
	ROOTP=$( printf "unit\nB\nprint\nquit\n" | \
	    parted "${1%.zip}" 2>/dev/null | grep "ROOT-A" )

	START=$(( $( echo ${ROOTP} | cut -f2 -d\ | tr -d "B" ) ))
	SIZE=$(( $( echo ${ROOTP} | cut -f4 -d\ | tr -d "B" ) ))

	dd if="${1%.zip}" of="root-a.ext2" bs=1024 \
	    skip=$(( ${START} / 1024 )) count=$(( ${SIZE} / 1024 )) || \
	    err "extract_partition, dd ${1%.zip}, root-a.ext2"

	printf "cd /usr/sbin\ndump chromeos-firmwareupdate ${SHELLBALL}\nquit" \
	    | debugfs "root-a.ext2" || err "extract_mrc: can't extract shellball"
}
