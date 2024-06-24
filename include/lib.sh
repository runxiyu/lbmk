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

err_()
{
	printf "ERROR %s: %s\n" "$0" "$1" 1>&2
	exit 1
}

setvars()
{
	_setvars="" && [ $# -lt 2 ] && $err "setvars: too few arguments"
	val="$1" && shift 1 && for var in $@; do
		_setvars="$var=\"$val\"; $_setvars"
	done; printf "%s\n" "${_setvars% }"
}
chkvars()
{
	for var in $@; do
		eval "[ -n "\${$var+x}" ] || \$err \"$var unset\""
	done
}

eval `setvars "" tmpdir _nogit board boarddir relname versiondate projectsite \
    projectname aur_notice cfgsdir datadir version`

for fv in projectname projectsite version versiondate; do
	eval "[ ! -f "$fv" ] || read -r $fv < \"$fv\" || :"
done

setcfg()
{
	if [ $# -gt 1 ]; then
		printf "e \"%s\" f missing && return %s;\n" "$1" "$2"
	else
		printf "e \"%s\" f missing && %s \"Missing config\";\n" "$1" \
		    "$err"
	fi
	printf ". \"%s\" || %s \"Could not read config\";\n" "$1" "$err"
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

install_packages()
{
	[ $# -lt 2 ] && $err "fewer than two arguments"
	eval `setcfg "config/dependencies/$2"`

	$pkg_add $pkglist || $err "Cannot install packages"

	[ -n "$aur_notice" ] && \
	printf "You need AUR packages: %s\n" "$aur_notice" 1>&2; return 0
}
[ $# -gt 0 ] && [ "$1" = "dependencies" ] && install_packages $@ && exit 0

id -u 1>/dev/null 2>/dev/null || $err "suid check failed (id -u)"
[ "$(id -u)" != "0" ] || $err "this command as root is not permitted"

[ -z "${TMPDIR+x}" ] && tmpdir_was_set="n"
if [ "$tmpdir_was_set" = "y" ]; then
	[ "${TMPDIR%_*}" = "/tmp/xbmk" ] || tmpdir_was_set="n"
fi
if [ "$tmpdir_was_set" = "n" ]; then
	[ -f "lock" ] && $err "$PWD/lock exists. Is a build running?"
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
[ -z "${XBMK_RELEASE+x}" ] && export XBMK_RELEASE="n"
[ "$XBMK_RELEASE" = "y" ] || export XBMK_RELEASE="n"

[ -z "${XBMK_THREADS+x}" ] && export XBMK_THREADS=1
expr "X$XBMK_THREADS" : "X-\{0,1\}[0123456789][0123456789]*$" \
    1>/dev/null 2>/dev/null || export XBMK_THREADS=1 # user gave a non-integer

x_() {
	[ $# -lt 1 ] || $@ || $err "Unhandled non-zero exit: $@"; return 0
}

[ -e ".git" ] || [ -f "version" ] || printf "unknown\n" > version || \
    $err "Cannot generate unknown version file"
[ -e ".git" ] || [ -f "versiondate" ] || printf "1716415872\n" > versiondate || \
    $err "Cannot generate unknown versiondate file"

version_="$version"
[ ! -e ".git" ] || version="$(git describe --tags HEAD 2>&1)" || \
    version="git-$(git rev-parse HEAD 2>&1)" || version="$version_"
versiondate_="$versiondate"
[ ! -e ".git" ] || versiondate="$(git show --no-patch --no-notes \
    --pretty='%ct' HEAD)" || versiondate="$versiondate_"
for p in projectname version versiondate projectsite; do
	chkvars "$p"
	eval "x_ printf \"%s\\n\" \"\$$p\" > $p"
done
relname="$projectname-$version"
export LOCALVERSION="-$projectname-${version%%-*}"

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
	tar -c "$1" | xz -T$XBMK_THREADS -9e > "$2" || $err "mktarball 2, $1"
	mksha512sum "$2" "${2##*/}.sha512"
}

mksha512sum()
{
	(
	[ "${1%/*}" != "$1" ] && x_ cd "${1%/*}"
	sha512sum ./"${1##*/}" >> "$2" || $err "!sha512sum \"$1\" > \"$2\""
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
