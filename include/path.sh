# SPDX-License-Identifier: MIT
# Copyright (c) 2024 Leah Rowe <leah@libreboot.org>

# fix mismatching gcc/gnat versions on debian trixie/sid
check_gnat_path()
{
	eval `setvars "" gccver gccfull gnatver gnatfull gccdir`
	command -v gcc 1>/dev/null || $err "Command 'gcc' unavailable."

	for _util in gcc gnat; do
		eval "$_util --version 1>/dev/null 2>/dev/null || continue"
		eval "${_util}ver=\"`$_util --version 2>/dev/null | head -n1`\""
		eval "${_util}ver=\"\${${_util}ver##* }\""
		eval "${_util}full=\"\${$_util}ver\""
		eval "${_util}ver=\"\${${_util}ver%%.*}\""
	done

	[ -z "$gccver" ] && $err "Cannot detect host GCC version"
	[ "$gnatfull" = "$gccfull" ] && return 0

	gccdir="$(dirname "$(command -v gcc)")"
	[ -d "$gccdir" ] || $err "gcc PATH dir \"$gccdir\" does not exist."

	for _gnatbin in "$gccdir/gnat-"*; do
		[ -f "$_gnatbin" ] || continue
		[ "${_gnatbin#"$gccdir/gnat-"}" = "$gccver" ] || continue
		gnatver="${_gnatbin#"$gccdir/gnat-"}"
		break
	done
	[ -x "$gccdir/gnat-$gccver" ] || \
	    $err "$gccdir/gnat-$gccver not executable"
	gnatfull="`"$gccdir/gnat-$gccver" --version | head -n1`"
	gnatfull="${gnatfull##* }"
	[ "${gnatfull%%.*}" = "$gnatver" ] || \
	    $err "$gccdir/gnat-$gccver v${gnatfull%%.*}; expected v$gnatver"

	[ "$gnatfull" = "$gccfull" ] || $err "GCC/GNAT versions do not match."

	(
	x_ cd xbmkpath
	for _gnatbin in "$gccdir/gnat"*"-$gccver"; do
		[ -e "$_gnatbin" ] || continue
		_gnatutil="${_gnatbin##*/}"
		ln -s "$_gnatbin" "${_gnatutil%"-$gccver"}" || \
		    $err "E: ln -s \"$_gnatbin\" \"${_gnatutil%"-$gccver"}\""
	done
	) || $err "Cannot create gnat-$gccver link in $gccdir"
}
