# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2022 Caleb La Grange <thonkpeasant@protonmail.com>
# Copyright (c) 2022 Ferass El Hafidi <vitali64pmemail@protonmail.com>
# Copyright (c) 2020-2024 Leah Rowe <leah@libreboot.org>

export LC_COLLATE=C
export LC_ALL=C

_ua="Mozilla/5.0 (Windows NT 10.0; rv:91.0) Gecko/20100101 Firefox/91.0"
kbnotice="Insert a .gkb file from config/data/grub/keymap/ as keymap.gkb \
if you want a custom keymap in GRUB; use cbfstool from elf/cbfstool."

tmpdir_was_set="y"
cbdir="src/coreboot/default"
cbelfdir="elf/coreboot_nopayload_DO_NOT_FLASH"
ifdtool="elf/ifdtool/default/ifdtool"
cbfstool="elf/cbfstool/default/cbfstool"
tmpgit="$PWD/tmp/gitclone"
grubdata="config/data/grub"
err="err_"

badcmd()
{
	errmsg="Bad command"
	[ $# -gt 0 ] && errmsg="Bad command ($1)"

	dstr="See $projectname build system docs: ${projectsite}docs/maintain/"
	[ -d "docs" ] && dstr="$dstr (local docs available via docs/)"
	$err "$errmsg. $dstr"
}
err_()
{
	printf "ERROR %s: %s\n" "$0" "$1" 1>&2
	exit 1
}

setvars()
{
	_setvars=""
	[ $# -lt 2 ] && $err "setvars: too few arguments"
	val="$1" && shift 1
	for var in $@; do
		_setvars="$var=\"$val\"; $_setvars"
	done
	printf "%s\n" "${_setvars% }"
}
chkvars()
{
	for var in $@; do
		eval "[ -n "\${$var+x}" ] || \$err \"$var unset\""
	done
}

eval "$(setvars "" xbmk_release tmpdir _nogit version board boarddir relname \
    versiondate threads projectname projectsite aur_notice cfgsdir datadir)"

read -r projectname < projectname || :
read -r projectsite < projectsite || :

install_packages()
{
	[ $# -lt 2 ] && badcmd "fewer than two arguments"
	[ -f "config/dependencies/$2" ] || badcmd "unsupported target"

	. "config/dependencies/$2" || $err "! . config/dependencies/$2"

	$pkg_add $pkglist || $err "Cannot install packages"

	[ -n "$aur_notice" ] && \
	printf "You need AUR packages: %s\n" "$aur_notice" 1>&2; return 0
}
[ $# -gt 0 ] && [ "$1" = "dependencies" ] && install_packages $@ && return 0

id -u 1>/dev/null 2>/dev/null || $err "suid check failed (id -u)"
[ "$(id -u)" != "0" ] || $err "this command as root is not permitted"

[ -z "${TMPDIR+x}" ] && tmpdir_was_set="n"
if [ "$tmpdir_was_set" = "y" ]; then
	[ "${TMPDIR%_*}" = "/tmp/xbmk" ] || tmpdir_was_set="n"
fi
if [ "$tmpdir_was_set" = "n" ]; then
	[ -f "lock" ] && \
	    $err "$PWD/lock exists. If a build isn't going, delete and re-run."
	export TMPDIR="/tmp"
	tmpdir="$(mktemp -d -t xbmk_XXXXXXXX)"
	export TMPDIR="$tmpdir"
	touch lock || $err "cannot create 'lock' file"
else
	export TMPDIR="$TMPDIR"
	tmpdir="$TMPDIR"
fi

# if "y": a coreboot target won't be built if target.cfg says release="n"
# (this is used to exclude certain build targets from releases)
[ -z "${XBMK_RELEASE+x}" ] && xbmk_release="n"
[ -z "$xbmk_release" ] && xbmk_release="$XBMK_RELEASE"
[ "$xbmk_release" = "n" ] || [ "$xbmk_release" = "y" ] || xbmk_release="n"
export XBMK_RELEASE="$xbmk_release"

[ -z "${XBMK_THREADS+x}" ] || threads="$XBMK_THREADS"
[ -z "$threads" ] && threads=1
expr "X$threads" : "X-\{0,1\}[0123456789][0123456789]*$" \
    1>/dev/null 2>/dev/null || threads=1 # user specified a non-integer
export XBMK_THREADS="$threads"

x_() {
	[ $# -lt 1 ] || $@ || $err "Unhandled non-zero exit: $@"; return 0
}

[ -e ".git" ] || [ -f "version" ] || printf "unknown\n" > version || \
    $err "Cannot generate unknown version file"
[ -e ".git" ] || [ -f "versiondate" ] || printf "1716415872\n" > versiondate || \
    $err "Cannot generate unknown versiondate file"

[ ! -f version ] || read -r version < version || :
version_="$version"
[ ! -e ".git" ] || version="$(git describe --tags HEAD 2>&1)" || \
    version="git-$(git rev-parse HEAD 2>&1)" || version="$version_"
[ ! -f versiondate ] || read -r versiondate < versiondate || :
versiondate_="$versiondate"
[ ! -e ".git" ] || versiondate="$(git show --no-patch --no-notes \
    --pretty='%ct' HEAD)" || versiondate="$versiondate_"
for p in projectname version versiondate projectsite; do
	chkvars "$p"
	eval "x_ printf \"%s\\n\" \"\$$p\" > $p"
done
relname="$projectname-$version"
export LOCALVERSION="-$projectname-${version%%-*}"

scan_config()
{
	awkstr=" /\{.*$1.*}{/ {flag=1;next} /\}/{flag=0} flag { print }"
	confdir="$2"
	revfile="$(mktemp -t sources.XXXXXXXXXX)"
	cat "$confdir/"* > "$revfile" || $err "$confdir: can't cat files"
	while read -r line ; do
		set $line 1>/dev/null 2>/dev/null || :
		if [ "${1%:}" = "depend" ]; then
			depend="$depend $2"
		else
			eval "${1%:}=\"$2\""
		fi
	done << EOF
	$(eval "awk '$awkstr' \"$revfile\"")
EOF
	rm -f "$revfile" || $err "scan_config: Cannot remove tmpfile"
}

check_defconfig()
{
	[ -d "$1" ] || $err "Target '$1' not defined."
	for x in "$1"/config/*; do
		[ -f "$x" ] && printf "%s\n" "$x" && return 1
	done
}

remkdir()
{
	rm -Rf "$1" || $err "remkdir: !rm -Rf \"$1\""
	mkdir -p "$1" || $err "remkdir: !mkdir -p \"$1\""
}

git_err()
{
	printf "You need to set git name/email, like so:\n%s\n\n" "$1" 1>&2
	$err "Git name/email not configured"
}

mkrom_tarball()
{
	printf "%s\n" "$version" > "$1/version" || $err "$1 !version"
	printf "%s\n" "$versiondate" > "$1/versiondate" || $err "$1 !vdate"
	printf "%s\n" "$projectname" > "$1/projectname" || $err "$1 !pname"

	mktarball "$1" "${1%/*}/${relname}_${1##*/}.tar.xz"
	x_ rm -Rf "$1"
}

mktarball()
{
	[ "${2%/*}" = "$2" ] || \
		mkdir -p "${2%/*}" || $err "mk, !mkdir -p \"${2%/*}\""
	printf "\nCreating archive: %s\n\n" "$2"
	tar -c "$1" | xz -T$threads -9e > "$2" || \
	    $err "mktarball 2, $1"
	mksha512sum "$2" "${2##*/}.sha512"
}

mksha512sum()
{
	(
	[ "${1%/*}" != "$1" ] && x_ cd "${1%/*}"
	sha512sum ./"${1##*/}" >> "$2" || \
	    $err "!sha512sum \"$1\" > \"$2\""
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

e()
{
	es_t="e"
	[ $# -gt 1 ] && es_t="$2"
	es2="already exists"
	estr="[ -$es_t \"\$1\" ] || return 1"
	[ $# -gt 2 ] && estr="[ -$es_t \"\$1\" ] && return 1" && es2="missing"

	eval "$estr"
	printf "%s %s\n" "$1" "$es2" 1>&2
}

# return 0 if project is single-tree, otherwise 1
# e.g. coreboot is multi-tree, so 1
singletree()
{
	for targetfile in "config/${1}/"*/target.cfg; do
		[ -e "$targetfile" ] || continue
		[ -f "$targetfile" ] && return 1
	done
}

download()
{
	dl_fail="y" # 1 url, 2 url backup, 3 destination, 4 checksum
	vendor_checksum "$4" "$3" 2>/dev/null || dl_fail="n"
	[ "$dl_fail" = "n" ] && e "$3" f && return 0
	x_ mkdir -p "${3%/*}" && for url in "$1" "$2"; do
		[ "$dl_fail" = "n" ] && break
		[ -z "$url" ] && continue
		x_ rm -f "$3"
		curl --location --retry 3 -A "$_ua" "$url" -o "$3" || \
		    wget --tries 3 -U "$_ua" "$url" -O "$3" || continue
		vendor_checksum "$4" "$3" || dl_fail="n"
	done;
	[ "$dl_fail" = "y" ] && $err "$1 $2 $3 $4: not downloaded"; return 0
}

vendor_checksum()
{
	[ "$(sha512sum "$2" | awk '{print $1}')" != "$1" ] || return 1
	printf "Bad checksum for file: %s\n" "$2" 1>&2
	rm -f "$2" || :
}

cbfs()
{
	ccmd="add-payload" && [ $# -gt 3 ] && ccmd="add"
	lzma="-c lzma" && [ $# -gt 3 ] && lzma="-t raw"
	x_ "$cbfstool" "$1" $ccmd -f "$2" -n "$3" $lzma
}
