# SPDX-License-Identifier: MIT
# Copyright (c) 2024 Leah Rowe <leah@libreboot.org>

# fix mismatching gcc/gnat versions on debian trixie/sid
check_gnat_path()
{
	eval `setvars "" gccver gnatver gccdir`
	command -v gcc 1>/dev/null || $err "Command 'gcc' unavailable."

	for _util in gcc gnat; do
		eval "$_util --version 1>/dev/null 2>/dev/null || continue"
		eval "${_util}ver=\"`$_util --version 2>/dev/null | head -n1`\""
		eval "${_util}ver=\"\${${_util}ver##* }\""
		eval "${_util}ver=\"\${${_util}ver%%.*}\""
	done

	[ -z "$gccver" ] && $err "Cannot detect host GCC version"
	[ "$gnatver" = "$gccver" ] && return 0

	gccdir="$(dirname "$(command -v gcc)")"
	for _gnatbin in "$gccdir/gnat-"*; do
		[ -f "$_gnatbin" ] || continue
		[ "${_gnatbin#"$gccdir/gnat-"}" = "$gccver" ] || continue
		gnatver="${_gnatbin#"$gccdir/gnat-"}"
		break
	done
	[ "$gnatver" = "$gccver" ] || $err "GCC/GNAT versions do not match."

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
