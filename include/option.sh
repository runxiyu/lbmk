# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: 2022 Caleb La Grange <thonkpeasant@protonmail.com>
# SPDX-FileCopyrightText: 2022 Ferass El Hafidi <vitali64pmemail@protonmail.com>
# SPDX-FileCopyrightText: 2020-2024 Leah Rowe <leah@libreboot.org>

export LC_COLLATE=C
export LC_ALL=C

tmpdir_was_set="y"
vendir="vendorfiles"
appdir="${vendir}/app"
cbdir="src/coreboot/default"
cbcfgsdir="config/coreboot"
ifdtool="cbutils/default/ifdtool"
cbfstool="cbutils/default/cbfstool"
grubcfgsdir="config/grub"
layoutdir="/boot/grub/layouts"
. "${grubcfgsdir}/modules.list"
tmpgit="${PWD}/tmp/gitclone"
err="err_"

err_()
{
	printf "ERROR %s: %s\n" "${0}" "${1}" 1>&2
	exit 1
}

setvars()
{
	_setvars=""
	[ $# -lt 2 ] && $err "setvars: too few arguments"
	val="${1}" && shift 1
	for var in $@; do
		_setvars="${var}=\"${val}\"; ${_setvars}"
	done
	printf "%s\n" "${_setvars% }"
}
eval "$(setvars "" CONFIG_BOARD_DELL_E6400 CONFIG_HAVE_MRC CONFIG_HAVE_ME_BIN \
    CONFIG_ME_BIN_PATH CONFIG_KBC1126_FIRMWARE CONFIG_KBC1126_FW1 versiondate \
    CONFIG_KBC1126_FW1_OFFSET CONFIG_KBC1126_FW2 CONFIG_KBC1126_FW2_OFFSET \
    CONFIG_VGA_BIOS_FILE CONFIG_VGA_BIOS_ID CONFIG_GBE_BIN_PATH tmpdir _nogit \
    CONFIG_INCLUDE_SMSC_SCH5545_EC_FW CONFIG_SMSC_SCH5545_EC_FW_FILE version \
    CONFIG_IFD_BIN_PATH CONFIG_MRC_FILE _dest board boarddir lbmk_release \
    CONFIG_HAVE_REFCODE_BLOB CONFIG_REFCODE_BLOB_FILE threads projectname)"

# if "y": a coreboot target won't be built if target.cfg says release="n"
# (this is used to exclude certain build targets from releases)
set | grep LBMK_RELEASE 1>/dev/null 2>/dev/null || lbmk_release="n" || :
[ -z "$lbmk_release" ] && lbmk_release="$LBMK_RELEASE"
[ "$lbmk_release" = "n" ] || [ "$lbmk_release" = "y" ] || lbmk_release="n"
export LBMK_RELEASE="$lbmk_release"

set | grep TMPDIR 1>/dev/null 2>/dev/null || tmpdir_was_set="n"
if [ "${tmpdir_was_set}" = "y" ]; then
	[ "${TMPDIR%_*}" = "/tmp/lbmk" ] || tmpdir_was_set="n"
fi
if [ "${tmpdir_was_set}" = "n" ]; then
	export TMPDIR="/tmp"
	tmpdir="$(mktemp -d -t lbmk_XXXXXXXX)"
	export TMPDIR="${tmpdir}"
else
	export TMPDIR="${TMPDIR}"
	tmpdir="${TMPDIR}"
fi

set | grep LBMK_THREADS 1>/dev/null 2>/dev/null && threads="$LBMK_THREADS"
[ -z "$threads" ] && threads=1
expr "X$threads" : "X-\{0,1\}[0123456789][0123456789]*$" \
    1>/dev/null 2>/dev/null || threads=1 # user specified a non-integer
export LBMK_THREADS="$threads"

items()
{
	rval=1
	if [ ! -d "${1}" ]; then
		printf "items: directory '%s' doesn't exist" "${1}" 1>&2
		return 1
	fi
	for x in "${1}/"*; do
		# -e used because this is for files *or* directories
		[ -e "${x}" ] || continue
		[ "${x##*/}" = "build.list" ] && continue
		printf "%s\n" "${x##*/}" 2>/dev/null
		rval=0
	done
	return ${rval}
}

scan_config()
{
	awkstr=" /\{.*${1}.*}{/ {flag=1;next} /\}/{flag=0} flag { print }"
	confdir="${2}"
	revfile="$(mktemp -t sources.XXXXXXXXXX)"
	cat "${confdir}/"* > "${revfile}" || \
	    $err "scan_config ${confdir}: Cannot concatenate files"
	while read -r line ; do
		set ${line} 1>/dev/null 2>/dev/null || :
		if [ "${1%:}" = "depend" ]; then
			depend="${depend} ${2}"
		else
			eval "${1%:}=\"${2}\""
		fi
	done << EOF
	$(eval "awk '${awkstr}' \"${revfile}\"")
EOF
	rm -f "$revfile" || $err "scan_config: Cannot remove tmpfile"
}

check_defconfig()
{
	for x in "${1}"/config/*; do
		[ -f "${x}" ] && return 1
	done
}

handle_coreboot_utils()
{
	for util in cbfstool ifdtool; do
		x_ ./update trees ${_f} "src/coreboot/${1}/util/${util}"
		[ -z "${mode}" ] && [ ! -f "cbutils/${1}/${util}" ] && \
			x_ mkdir -p "cbutils/${1}" && \
			x_ cp "src/coreboot/${1}/util/${util}/${util}" \
			    "cbutils/${1}"
		[ -z "${mode}" ] || x_ rm -Rf "cbutils/${1}"
	done
}

remkdir()
{
	rm -Rf "${1}" || $err "remkdir: !rm -Rf \"${1}\""
	mkdir -p "${1}" || $err "remkdir: !mkdir -p \"${1}\""
}

x_() {
	[ $# -lt 1 ] || ${@} || $err "Unhandled non-zero exit: $@"; return 0
}

check_git()
{
	which git 1>/dev/null 2>/dev/null || \
	    git_err "git not installed. please install git-scm."
	git config --global user.name 1>/dev/null 2>/dev/null || \
	    git_err "git config --global user.name \"John Doe\""
	git config --global user.email 1>/dev/null 2>/dev/null || \
	    git_err "git config --global user.email \"john.doe@example.com\""
}

git_err()
{
	printf "You need to set git name/email, like so:\n%s\n\n" "$1" 1>&2
	$err "Git name/email not configured"
}

check_project()
{
	read -r projectname < projectname || :

	[ ! -f version ] || read -r version < version || :
	version_="${version}"
	[ ! -e ".git" ] || version="$(git describe --tags HEAD 2>&1)" || \
	    version="git-$(git rev-parse HEAD 2>&1)" || version="${version_}"

	[ ! -f versiondate ] || read -r versiondate < versiondate || :
	versiondate_="${versiondate}"
	[ ! -e ".git" ] || versiondate="$(git show --no-patch --no-notes \
	    --pretty='%ct' HEAD)" || versiondate="${versiondate_}"

	for p in projectname version versiondate; do
		eval "[ -n \"\$$p\" ] || $err \"$p unset\""
		eval "x_ printf \"%s\\n\" \"\$$p\" > $p"
	done
	export LOCALVERSION="-${projectname}-${version%%-*}"
}

mktar_release()
{
	x_ insert_version_files "$1"
	mktarball "$1" "${1}.tar.xz"
	x_ rm -Rf "$1"
}

mktarball()
{
	# preserve timestamps for reproducible tarballs
	tar_implementation=$(tar --version | head -n1) || :

	[ "${2%/*}" = "${2}" ] || \
		mkdir -p "${2%/*}" || $err "mk, !mkdir -p \"${2%/*}\""
	printf "\nCreating archive: %s\n\n" "$2"
	if [ "${tar_implementation% *}" = "tar (GNU tar)" ]; then
		tar --sort=name --owner=root:0 --group=root:0 \
		    --mtime="UTC 2024-05-04" -c "$1" | xz -T$threads -9e \
		    > "$2" || $err "mktarball 1, ${1}"
	else
		# TODO: reproducible tarballs on non-GNU systems
		tar -c "$1" | xz -T$threads -9e > "$2" || \
		    $err "mktarball 2, $1"
	fi
	mksha512sum "${2}" "${2##*/}.sha512"
}

mksha512sum()
{
	(
	[ "${1%/*}" != "${1}" ] && x_ cd "${1%/*}"
	sha512sum ./"${1##*/}" >> "${2}" || \
	    $err "!sha512sum \"${1}\" > \"${2}\""
	) || $err "failed to create tarball checksum"
}

insert_version_files()
{
	printf "%s\n" "${version}" > "${1}/version" || return 1
	printf "%s\n" "${versiondate}" > "${1}/versiondate" || return 1
	printf "%s\n" "${projectname}" > "${1}/projectname" || return 1
}
