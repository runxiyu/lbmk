# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2022 Caleb La Grange <thonkpeasant@protonmail.com>
# SPDX-FileCopyrightText: 2022 Ferass El Hafidi <vitali64pmemail@protonmail.com>
# SPDX-FileCopyrightText: 2023 Leah Rowe <leah@libreboot.org>

board=""
boards=""
displaymodes=""
payloads=""
keyboard_layouts=""

main()
{
	[ $# -lt 1 ] && usage && err "target not specified"

	first="${1}"
	[ "${first}" = "help" ] && usage && exit 0
	[ "${first}" = "list" ] && \
	    listitems config/coreboot && exit 0

	while [ $# -gt 0 ]; do
		case ${1} in
		-d)
			displaymodes="${2} ${displaymodes}"
			shift ;;
		-p)
			payloads="${2} ${payloads}"
			shift ;;
		-k)
			keyboard_layouts="${2} ${keyboard_layouts}"
			shift ;;
		all)
			first="all" ;;
		*)
			boards="${1} ${boards}" ;;
		esac
		shift
	done

	handle_targets
}
