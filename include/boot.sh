# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2022 Caleb La Grange <thonkpeasant@protonmail.com>
# SPDX-FileCopyrightText: 2022 Ferass El Hafidi <vitali64pmemail@protonmail.com>
# SPDX-FileCopyrightText: 2023 Leah Rowe <leah@libreboot.org>

eval "$(setvars "" first board boards _displaymode _payload _keyboard targets)"

main()
{
	[ $# -lt 1 ] && usage && err "target not specified"

	while [ $# -gt 0 ]; do
		case ${1} in
		help) usage && exit 0 ;;
		list) listitems config/coreboot && exit 0 ;;
		-d) _displaymode="${2}" ;;
		-p) _payload="${2}" ;;
		-k) _keyboard="${2}" ;;
		all)
			boards="$(listitems config/coreboot)"
			shift && continue ;;
		*)
			boards="${1} ${boards}"
			shift && continue ;;
		esac
		shift 2
	done

	check_target
	prepare_target
}

usage()
{
	cat <<- EOF
	USAGE:	./build boot roms target
	To build *all* boards, do this: ./build boot roms all
	To list *all* boards, do this: ./build boot roms list
	
	Optional Flags:
	-d: displaymode
	-p: payload
	-k: keyboard layout

	Example commands:
		./build boot roms x60
		./build boot roms x200_8mb x60
		./build boot roms x60 -p grub -d corebootfb -k usqwerty

	possible values for 'target':
	$(listitems "config/coreboot")

	Refer to the ${projectname} documentation for more information.
	EOF
}
