# SPDX-License-Identifier: GPL-2.0-only

# Logic based on util/chromeos/crosfirmware.sh in coreboot cfc26ce278.
# Modifications in this version are Copyright 2021, 2023 and 2024 Leah Rowe.
# Original copyright detailed in repo: https://review.coreboot.org/coreboot/

eval "$(setvars "" MRC_url MRC_url_bkup MRC_hash MRC_board SHELLBALL)"

extract_ref()
{
	# refcode needed on broadwell, but not needed on haswell

	# we check mrc twice, because each check only verifies one file,
	# but refcode is downloaded alongside mrc. in cases where lbmk
	# erred, downloading only mrc, we must ensure downloading refcode
	[ -n "$CONFIG_MRC_FILE" ] || \
		$err "extract_ref $board: CONFIG_MRC_FILE not defined"

	# the extract_mrc function actually downloads the refcode
	fetch "mrc" "$MRC_url" "$MRC_url_bkup" "$MRC_hash" "$CONFIG_MRC_FILE"
}

extract_mrc()
{
	[ -z "$MRC_board" ] && $err "extract_mrc $MRC_hash: MRC_board not set"
	[ -z "${CONFIG_MRC_FILE}" ] && \
		$err "extract_mrc $MRC_hash: CONFIG_MRC_FILE not set"

	SHELLBALL="chromeos-firmwareupdate-${MRC_board}"

	(
	x_ cd "${appdir}"
	extract_partition "${MRC_url##*/}"
	extract_archive "${SHELLBALL}" .
	) || $err "mrc download/extract failure"

	"${cbfstool}" "${appdir}/"bios.bin extract -n mrc.bin \
	    -f "$_dest" -r RO_SECTION || $err "extract_mrc: cbfstool $_dest"

	[ -n "$CONFIG_REFCODE_BLOB_FILE" ] && extract_refcode; return 0
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
	    $err "extract_partition, dd ${1%.zip}, root-a.ext2"

	printf "cd /usr/sbin\ndump chromeos-firmwareupdate ${SHELLBALL}\nquit" \
	    | debugfs "root-a.ext2" || $err "can't extract shellball"
}

extract_refcode()
{
	_refdest="${CONFIG_REFCODE_BLOB_FILE##*../}"
	[ -f "$_refdest" ] && return 0

	# cbfstool changed the attributes scheme for stage files,
	# incompatible with older versions before coreboot 4.14,
	# so we need coreboot 4.13 cbfstool for certain refcode files
	[ -n "$cbfstoolref" ] || \
		$err "extract_refcode $board: MRC_refcode_cbtree not set"
	mkdir -p "${_refdest%/*}" || \
	    $err "extract_refcode $board: !mkdir -p ${_refdest%/*}"

	"$cbfstoolref" "$appdir/bios.bin" extract \
	    -m x86 -n fallback/refcode -f "$_refdest" -r RO_SECTION \
	    || $err "extract_refcode $board: !cbfstoolref $_refdest"

	# enable the Intel GbE device, if told by offset MRC_refcode_gbe
	[ -z "$MRC_refcode_gbe" ] || dd if="config/ifd/hp820g2/1.bin" \
	    of="$_refdest" bs=1 seek=$MRC_refcode_gbe count=1 conv=notrunc || \
	    $err "extract_refcode $_refdest: byte $MRC_refcode_gbe"; return 0
}
