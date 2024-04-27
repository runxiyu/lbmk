# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2022, 2023 Leah Rowe <leah@libreboot.org>

export LC_COLLATE=C
export LC_ALL=C

version=""; versiondate=""; projectname=""; _nogit=""
err="err_"; tmpdir=""; release_type=""; lbmk_status=""

# if "y": a coreboot target won't be built if target.cfg says release="n"
# (this is used to exclude certain build targets from releases)
lbmk_release=
set | grep LBMK_RELEASE 1>/dev/null 2>/dev/null || lbmk_release="n" || :
[ -z "$lbmk_release" ] && lbmk_release="$LBMK_RELEASE"
[ "$lbmk_release" = "n" ] || [ "$lbmk_release" = "y" ] || lbmk_release="n"
export LBMK_RELEASE="$lbmk_release"

# valid values:
# empty / not set
# value: stable
# value: unstable
# e.g. export LBMK_VERSION_TYPE=stable
set | grep LBMK_VERSION_TYPE 1>/dev/null 2>/dev/null && \
    release_type="$LBMK_VERSION_TYPE"
[ -z "$release_type" ] || [ "$release_type" = "stable" ] || \
    [ "$release_type" = "unstable" ] || release_type=""
export LBMK_VERSION_TYPE="$release_type"

# if set to n via export, status checks will be skipped during
# all builds, and all targets will be built regardless of status.
# this replicates the old behaviour of lbmk, prior to the checks.
set | grep LBMK_STATUS 1>/dev/null 2>/dev/null && lbmk_status="$LBMK_STATUS"
[ "$lbmk_status" = "y" ] || [ "$lbmk_status" = "n" ] || lbmk_status="y"
export LBMK_STATUS="$lbmk_status"

tmpdir_was_set="y"
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

err_()
{
	printf "ERROR %s: %s\n" "${0}" "${1}" 1>&2
	exit 1
}
