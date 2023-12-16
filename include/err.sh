# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2022, 2023 Leah Rowe <leah@libreboot.org>

version=""; versiondate=""; projectname=""; _nogit=""

x_() {
	[ $# -lt 1 ] || ${@} || err_exit err ${@}
}
xx_() {
	[ $# -lt 1 ] || ${@} || err_exit fail ${@}
}

err_exit()
{
	_fail="${1}" && shift 1
	echo "Non-zero exit: $@"
	$_fail "Unhandled error"
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
	printf "You need to set git name/email, like so:\n%s\n\n" "${1}" 1>&2
	fail "Git name/email not configured" || \
	    err "Git name/email not configured"
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

	[ -n "${versiondate}" ] || fail "Unknown version date" || \
	    err "Unknown version date"
	[ -n "${version}" ] || fail "Unknown version" || \
	    err "Unknown version"
	[ -n "${projectname}" ] || fail "Unknown project" || \
	    err "Unknown project"

	xx_ printf "%s\n" "${version}" > version || \
	    x_ printf "%s\n" "${version}" > version
	xx_ printf "%s\n" "${versiondate}" > versiondate || \
	    x_ printf "%s\n" "${versiondate}" > versiondate
}

setvars()
{
	_setvars=""
	[ $# -lt 2 ] && err "setvars: too few arguments"
	val="${1}"
	shift 1
	for var in $@; do
		_setvars="${var}=\"${val}\"; ${_setvars}"
	done
	printf "%s\n" "${_setvars% }"
}

err()
{
	printf "ERROR %s: %s\n" "${0}" "${1}" 1>&2
	exit 1
}
