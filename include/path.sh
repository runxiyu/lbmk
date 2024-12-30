# SPDX-License-Identifier: MIT
# Copyright (c) 2024 Leah Rowe <leah@libreboot.org>

eval `setvars "" gccver gccfull gnatver gnatfull gccdir`

# fix mismatching gcc/gnat versions on debian trixie/sid
check_gnat_path()
{
	rm -f xbmkpath/* || $err "Cannot clear xbmkpath/"

	eval `setvars "" gccver gccfull gnatver gnatfull gccdir`
	gnu_setver gcc gcc || $err "Command 'gcc' unavailable."
	gnu_setver gnat gnat || :

	[ -z "$gccver" ] && $err "Cannot detect host GCC version"
	[ "$gnatfull" = "$gccfull" ] && return 0

	gccdir="$(dirname "$(command -v gcc)")"
	for _gnatbin in "$gccdir/gnat-"*; do
		[ -f "$_gnatbin" ] || continue
		[ "${_gnatbin#"$gccdir/gnat-"}" = "$gccver" ] || continue
		gnatver="${_gnatbin#"$gccdir/gnat-"}"; break
	done
	gnu_setver "gnat" "$gccdir/gnat-$gccver" || $err "Unknown gnat version"
	[ "$gnatfull" = "$gccfull" ] || $err "GCC/GNAT versions do not match."

	(
	x_ cd xbmkpath
	for _gnatbin in "$gccdir/gnat"*"-$gccver"; do
		[ -e "$_gnatbin" ] || continue; _gnatutil="${_gnatbin##*/}"
		x_ ln -s "$_gnatbin" "${_gnatutil%"-$gccver"}"
	done
	) || $err "Cannot create gnat-$gccver link in $gccdir"; :
}

gnu_setver()
{
	eval "$2 --version 1>/dev/null 2>/dev/null || return 1"
	eval "${1}ver=\"`$2 --version 2>/dev/null | head -n1`\""
	eval "${1}ver=\"\${${1}ver##* }\""
	eval "${1}full=\"\${$1}ver\""
	eval "${1}ver=\"\${${1}ver%%.*}\""; :
}
