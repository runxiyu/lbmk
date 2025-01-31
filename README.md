Libreboot
=========

* Documentation: [libreboot.org](https://libreboot.org)
* Support: [\#libreboot](https://web.libera.chat/#libreboot) on
  [Libera](https://libera.chat/) IRC

Libreboot provides 
[libre](https://libreboot.org/freedom-status.html)
boot firmware on
[supported motherboards](https://libreboot.org/docs/install/#which-systems-are-supported-by-libreboot). It replaces proprietary vendor BIOS/UEFI implementations, by
* Using coreboot to initialize the hardware (e.g. memory controller, CPU, etc.) while
  minimizing unwanted functionality (e.g. backdoors such as the Intel Management Engine)
* ... which runs a payload such as SeaBIOS, GRUB, or U-Boot
* ... which loads your operating system's boot loader (BSD and Linux-based
  [systems](systems) are supported).

Why use Libreboot, and what is coreboot?
----------------------------------------

A lot of users who use libre operating systems still use proprietary boot
firmware, which often contain backdoors and bugs, hampering
[user freedom](https://writefreesoftware.org) and
[right to repair](https://vid.puffyan.us/watch?v=Npd_xDuNi9k).

[coreboot](https://coreboot.org) provides libre boot firmware by initializing
the hardware then running a payload. However, coreboot is notoriously difficult
to configure and install for most non-technical users, requiring detailed
technical knowledge of hardware.

Libreboot solves this by being **a coreboot distribution** (in the same way
that Alpine Linux is a Linux distribution). It provides a fully automated build
system that downloads and compiles pre-configured ROM images for supported
motherboards, so end-users could easily fetch images to flash onto their
devices.

Libreboot also produces documentation aimed at non-technical users and
excellent user support via IRC.

Contribute
----------

You can check bugs listed on
the [bug tracker](https://codeberg.org/libreboot/lbmk/issues).

You may use Codeberg pull requests to send patches with bug fixes or other
improvements. This repository hosts the code for the main build system.
The website lives in [a separate repository](https://codeberg.org/libreboot/lbwww).

Development is also done on the IRC channel.

License for this README
-----------------------

It's just a README file. It is released under
[Creative Commons Zero, version 1.0](https://creativecommons.org/publicdomain/zero/1.0/legalcode.txt).

