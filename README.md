Libreboot
=========

Find libreboot documentation at <https://libreboot.org/>

The `libreboot` project provides
[libre](https://libreboot.org/freedom-status.html) *boot
firmware* that initializes the hardware (e.g. memory controller, CPU,
peripherals) on specific Intel/AMD x86 and ARM targets, which
then starts a bootloader for your operating system. Linux/BSD are
well-supported. It replaces proprietary BIOS/UEFI firmware. Help is available
via [\#libreboot IRC](https://web.libera.chat/#libreboot)
on [Libera](https://libera.chat/) IRC.

Why use Libreboot?
==================

Why should you use *libreboot*?
----------------------------

Libreboot gives you freedoms that you otherwise can't get with most other
boot firmware. It's extremely powerful and configurable for many use cases.

You have rights. The right to privacy, freedom of thought, freedom of speech
and the right to read. In this context, Libreboot gives you these rights.
Your freedom matters.
[Right to repair](https://vid.puffyan.us/watch?v=Npd_xDuNi9k) matters.
Many people use proprietary (non-libre)
boot firmware, even if they use [a libre OS](https://www.openbsd.org/).
Proprietary firmware often contains backdoors (more info on the FAQ), and it
and can be buggy. The libreboot project was founded in in December 2013,
with the express purpose of making coreboot firmware accessible for
non-technical users.

The `libreboot` project uses [coreboot](https://www.coreboot.org/) for [hardware
initialisation](https://doc.coreboot.org/getting_started/architecture.html).
Coreboot is notoriously difficult to install for most non-technical users; it
handles only basic initialization and jumps to a separate
[payload](https://doc.coreboot.org/payloads.html) program (e.g.
[GRUB](https://www.gnu.org/software/grub/),
[Tianocore](https://www.tianocore.org/)), which must also be configured.
*The libreboot software solves this problem*; it is a *coreboot distribution* with
an automated build system (named *lbmk*) that builds complete *ROM images*, for
more robust installation. Documentation is provided.

How does Libreboot differ from coreboot?
========================================

In the same way that *Debian* is a GNU+Linux distribution, `libreboot` is
a *coreboot distribution*. If you want to build a ROM image from scratch, you
otherwise have to perform expert-level configuration of coreboot, GRUB and
whatever other software you need, to prepare the ROM image. With *libreboot*,
you can literally download from Git or a source archive, and run `make`, and it
will build entire ROM images. An automated build system, named `lbmk`
(Libreboot MaKe), builds these ROM images automatically, without any user input
or intervention required. Configuration has already been performed in advance.

If you were to build regular coreboot, without using libreboot's automated
build system, it would require a lot more intervention and decent technical
knowledge to produce a working configuration.

Regular binary releases of `libreboot` provide these
ROM images pre-compiled, and you can simply install them, with no special
knowledge or skill except the ability to follow installation instructions
and run commands BSD/Linux.

Project goals
=============

-   *Support as much hardware as possible!* Libreboot aims to eventually
    have *maintainers* for every board supported by coreboot, at every
    point in time.
-   *Make coreboot easy to use*. Coreboot is notoriously difficult
    to install, due to an overall lack of user-focused documentation
    and support. Most people will simply give up before attempting to
    install coreboot. Libreboot's automated build system and user-friendly
    installation instructions solves this problem.

Libreboot attempts to bridge this divide by providing a build system
automating much of the coreboot image creation and customization.
Secondly, the project produces documentation aimed at non-technical users.
Thirdly, the project attempts to provide excellent user support via IRC.

Libreboot already comes with a payload (GRUB), flashrom and other
needed parts. Everything is fully integrated, in a way where most of
the complicated steps that are otherwise required, are instead done
for the user in advance.

You can download ROM images for your libreboot system and install
them without having to build anything from source. If, however, you are
interested in building your own image, the build system makes it relatively
easy to do so.

Not a coreboot fork!
--------------------

Libreboot is not a fork of coreboot. Every so often, the project
re-bases on the latest version of coreboot, with the number of custom
patches in use minimized. Tested, *stable* (static) releases are then provided
in Libreboot, based on specific coreboot revisions.

How to help
===========

You can check bugs listed on
the [bug tracker](https://codeberg.org/libreboot/lbmk/issues).

If you spot a bug and have a fix, the website has instructions for how to send
patches, and you can also report it. Also, this entire website is
written in Markdown and hosted in a [separate
repository](https://codeberg.org/libreboot/lbwww) where you can send patches.

Any and all development discussion and user support are all done on the IRC
channel. More information is on the contact page of libreboot.org.

LICENSE FOR THIS README
=======================

It's just a README file. This README file is released under the terms of the
Creative Commons Zero license, version 1.0 of the license, which you can
read here:

<https://creativecommons.org/publicdomain/zero/1.0/legalcode.txt>
