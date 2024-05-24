# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: 2022 Caleb La Grange <thonkpeasant@protonmail.com>
# SPDX-FileCopyrightText: 2022 Ferass El Hafidi <vitali64pmemail@protonmail.com>
# SPDX-FileCopyrightText: 2020-2024 Leah Rowe <leah@libreboot.org>

export LC_COLLATE=C
export LC_ALL=C

tmpdir_was_set="y"
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
eval "$(setvars "" versiondate tmpdir _nogit version board boarddir \
    xbmk_release threads projectname relname)"

# if "y": a coreboot target won't be built if target.cfg says release="n"
# (this is used to exclude certain build targets from releases)
set | grep XBMK_RELEASE 1>/dev/null 2>/dev/null || xbmk_release="n" || :
[ -z "$xbmk_release" ] && xbmk_release="$XBMK_RELEASE"
[ "$xbmk_release" = "n" ] || [ "$xbmk_release" = "y" ] || xbmk_release="n"
export XBMK_RELEASE="$xbmk_release"

set | grep TMPDIR 1>/dev/null 2>/dev/null || tmpdir_was_set="n"
if [ "${tmpdir_was_set}" = "y" ]; then
	[ "${TMPDIR%_*}" = "/tmp/xbmk" ] || tmpdir_was_set="n"
fi
if [ "${tmpdir_was_set}" = "n" ]; then
	export TMPDIR="/tmp"
	tmpdir="$(mktemp -d -t xbmk_XXXXXXXX)"
	export TMPDIR="${tmpdir}"
else
	export TMPDIR="${TMPDIR}"
	tmpdir="${TMPDIR}"
fi

set | grep XBMK_THREADS 1>/dev/null 2>/dev/null && threads="$XBMK_THREADS"
[ -z "$threads" ] && threads=1
expr "X$threads" : "X-\{0,1\}[0123456789][0123456789]*$" \
    1>/dev/null 2>/dev/null || threads=1 # user specified a non-integer
export XBMK_THREADS="$threads"

x_() {
	[ $# -lt 1 ] || ${@} || $err "Unhandled non-zero exit: $@"; return 0
}

[ -e ".git" ] || [ -d "version" ] || printf "unknown\n" > version || \
    $err "Cannot generate unknown version file"
[ -e ".git" ] || [ -d "versiondate" ] || printf "1716415872\n" > versiondate || \
    $err "Cannot generate unknown versiondate file"

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
relname="${projectname}-${version}"
export LOCALVERSION="-${projectname}-${version%%-*}"

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
	[ -d "$1" ] || $err "Target '$1' not defined."
	for x in "${1}"/config/*; do
		[ -f "${x}" ] && printf "%s\n" "$x" && return 1
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

git_err()
{
	printf "You need to set git name/email, like so:\n%s\n\n" "$1" 1>&2
	$err "Git name/email not configured"
}

mkrom_tarball()
{
	printf "%s\n" "${version}" > "${1}/version" || $err "$1 !version"
	printf "%s\n" "${versiondate}" > "${1}/versiondate" || $err "$1 !vdate"
	printf "%s\n" "${projectname}" > "${1}/projectname" || $err "$1 !pname"

	mktarball "$1" "${1%/*}/${relname}_${1##*/}.tar.xz"
	x_ rm -Rf "$1"
}

mktarball()
{
	[ "${2%/*}" = "${2}" ] || \
		mkdir -p "${2%/*}" || $err "mk, !mkdir -p \"${2%/*}\""
	printf "\nCreating archive: %s\n\n" "$2"
	tar -c "$1" | xz -T$threads -9e > "$2" || \
	    $err "mktarball 2, $1"
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

rmgit()
{
	(
	cd "$1" || $err "!cd gitrepo $1"
	find . -name ".git" -exec rm -Rf {} + || $err "!rm .git $1"
	find . -name ".gitmodules" -exec rm -Rf {} + || $err "!rm .gitmod $1"
	) || $err "Cannot remove .git/.gitmodules in $1"
}
