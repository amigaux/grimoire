---
title: Writing an Amix Driver with an LLM Tool
summary: What to give an LLM coding tool (Claude Code, Codex and the like) before it writes an Amix driver — the documents, the build container, packaging with apkg, the emulation-first test loop and how to report results — for kernel modules, STREAMS and character drivers, and X backends.
status: draft
---

# Writing an Amix driver with an LLM tool

This page is for a developer who wants to write a driver for Amiga UNIX (Amix) with an LLM coding
tool such as Claude Code or Codex doing much of the typing. Such a tool writes plausible code for
any Unix. Amix is an SVR4.0 kernel from 1990 with Amiga-specific traps, and much of the lore about it
is wrong, so the tool needs grounded documents more than it needs prompts. Give it the documents
below, the build container and a test loop it can run itself. It will then do most of the work, and
you check what it claims.

The same approach covers three kinds of driver:

- a **kernel module**: a character, block or STREAMS driver loaded into a running kernel;
- an **X backend**: a card driver inside the X server, in user space, on top of a kernel driver
  that gives a device node;
- a **user-space tool or library** for a device, shipped as a package.

The companion pages:

- [Worked example: an X backend](x-backend-example.md), a new card under the X11R6.3 server's RTG
  layer;
- [Real hardware with an LLM tool](real-hardware.md), for a device that cannot be emulated;
- [An AGENTS.md for a driver repository](agents-template.md), a template to copy into your
  repository so the tool follows these rules every session.

## 1. What to point the tool at

Start the tool's session by having it read these, in this order, and tell it to name the page behind
each platform fact it uses.

| Source | What it gives |
|---|---|
| This site's [`llms.txt`](https://github.com/amigaux/grimoire/blob/master/llms.txt), then [`llms-full.txt`](https://github.com/amigaux/grimoire/blob/master/llms-full.txt) | The map of these pages, then the whole site in one file to search |
| [`sources/research-brief.md`](https://github.com/amigaux/grimoire/blob/master/sources/research-brief.md) | Every fact with its source and confidence tag |
| [Driver model](../driver-model.md), [loadable modules](../loadable-modules.md), [character driver](../writing-a-char-driver.md), [STREAMS driver](../writing-a-streams-driver.md), [Zorro AUTOCONFIG](../zorro-autoconfig.md), [X11 RTG drivers](../x11-rtg-drivers.md), [toolchain](../toolchain.md) | How Amix drivers work, and the kernel facts a module author needs |
| [Quirks](../../how-it-works/quirks.md), [emulation fidelity](../../how-it-works/emulation-fidelity.md), [major-number registry](../../reference/major-number-registry.md) | The traps, what an emulator does and does not reproduce, and which majors are free |
| amix [`kernel/dlm/docs/`](https://github.com/amigaux/amix/tree/master/kernel/dlm/docs): `spec/` (from `00-overview.md`), `abi/writing-a-module.md`, `abi/ddi.md`, `contracts/` | The module system's specification, how to build a module with the ABI kit, every kernel name a module may use, and the contracts a module meets ✅ |
| amix [`kernel/modules/`](https://github.com/amigaux/amix/tree/master/kernel/modules) | Example modules: `monsw` (the worked example, a demand-class character driver), `ramdisk` (a root-class block driver), `random` (character), `zz9kbus` and `zz9ksvc` (one module calling another) ✅ |
| amix [`kernel/drivers/`](https://github.com/amigaux/amix/tree/master/kernel/drivers) | Hardware drivers as modules: `a4091`, `z3660scsi`, `z3660eth` and `xsurf` as source, and pinned forks (`cdfs`, `gayle-ide`, `paula`, `va2000`, `z3660rtg`) ✅ |
| amix [`build/pkg/README.md`](https://github.com/amigaux/amix/blob/master/build/pkg/README.md) and [`docs/BUILDING.md`](https://github.com/amigaux/amix/blob/master/docs/BUILDING.md) | The package recipe format and the build ✅ |

Tell the tool what the tags mean: ✅ is verified (primary source, repository source or reproduced),
🟡 is reported but not checked first-hand, 🔴 is unverified or disputed. It may rely on ✅, must say
when it relies on 🟡, and must never raise a tag itself. A fact it cannot find anywhere is a question
to answer by experiment, not something to assume from Linux or the BSDs.

## 2. Which kind of driver

### A kernel module

A module is one ELF relocatable object built with the ABI kit of one kernel line: `k30` for the
68030, `k46` for the 68040 and 68060. One source gives two objects and two packages ✅. The kit's
`sample/hello` is the template, and a driver uses `MOD_DRV_WRAPPER` with its `cdevsw` or `bdevsw`
row in `<prefix>_drvdata[]`; a STREAMS driver fills only `d_str` ✅. The `Master` file gives the
module's class (`boot`, `demand` or `root`), its majors (each registered to its name in the kit's
registry) and its `$match` for a board ✅. `kernel/dlm/docs/abi/writing-a-module.md` has the whole
form.

The facts an LLM gets wrong unless told ✅ (the module guide and the
[loadable-modules page](../loadable-modules.md#kernel-facts-a-module-or-any-driver-author-needs)):

- `_load` finds and sets up the board and returns `ENXIO` when there is none, leaving nothing
  behind; `_unload` undoes everything; `_halt` stops a board that can interrupt or write memory.
- A level-6 interrupt handler calls no kernel function: it acknowledges, masks and flags, and the
  work runs at level 4 or below.
- A STREAMS open runs at level 4, so a self-test that waits there for a level-2 interrupt by
  spinning never sees it.
- The console goes through `cons_hook_set`, never `conputc`.
- There is no DMA interface in DDI v1.0: never give a board the address of the module's own memory.
- A module image is at most 256 KiB, and one `kmem_alloc` at most 256 KiB.
- On k46, a framebuffer that a user maps is registered with `DDI_FB_REGISTER` from `_load`.
- Headers are included by their path in the kit's stock tree, never by a relative path.

### An X backend

An X backend is a card driver inside the X server. Since x11r63 6.3-10 the `Xrtg` server has a
card-neutral RTG layer, and a card is one `rtgCardOps` record plus a card file for `xstart` ✅. It
needs a kernel driver for the card that gives a device node, `mmap` of the framebuffer and the
ioctls the backend uses. The [worked example](x-backend-example.md) goes through it.

### A user-space tool or library

A package under `userland/packages/<name>/`, with its facts in `package.sh` and its payload in a
hand-written `prototype`; userland builds with GCC 14 ✅ (`build/pkg/README.md`).

## 3. The build: amix's container, not your own toolchain

Build inside amix's published build container. Don't install a cross compiler on your host, and
don't let the tool build one. The container holds both cross compilers at their pins ✅:

- **gcc-cross-amix**, the period GCC 2.7.2.3 (`m68k-cbm-sysv4`), for kernel space: kernels,
  modules, drivers;
- **gcc14-cross-amix**, GCC 14, for userland, with the Commodore system files as its sysroot.

The steps, on Linux x86-64 with docker ✅ (`docs/BUILDING.md`):

```sh
git clone https://github.com/amigaux/amix.git && cd amix
system/fetch-amix-system ../amix-system
make tools SYSTEM=../amix-system      # pulls the published images by digest (or TOOLS_FROM_SOURCE=1)
make kit   SYSTEM=../amix-system      # the ABI kits, out/kit/{k30,k46}
```

Then build only your part: `make modules`, `make drivers/<name>` or `make recipes/<name>` ✅. Each
step runs in the container as you, with the checkout at `/src`; the fixed path keeps the period
compiler, which cannot remap paths, from building your checkout's location into its bytes ✅. So two
builds of one commit give the same bytes, and a result someone else reports can be rebuilt exactly.
`DIST_HOST=1` runs the steps on the host for development, with whatever toolchains it finds; a
release is built in the container ✅.

Shape your work as an amix directory, copying the nearest example:

| You write | Shape | Example |
|---|---|---|
| a generic module | `kernel/modules/<name>/`: `src/`, `module/{keys,Master,Makefile,VERSION}`, `pkg/`, `man/`, `test/` | `kernel/modules/monsw` ✅ |
| a hardware driver kept in amix | `kernel/drivers/<name>/` with `module/` and `pkg/` | `kernel/drivers/xsurf` ✅ |
| a driver in your own repository | `kernel/drivers/<name>/` with a README, `pkg/` and `<name>.pin` (`<git URL> <40-hex commit>`) | `kernel/drivers/va2000` ✅ |
| a userland package | `userland/packages/<name>/package.sh`, `prototype`, `patches/` | `userland/packages/grep` ✅ |

A new hardware driver is also added to `DRIVERS` in `build/dist.sh` ✅. The host tests need no Amiga
and no cross compiler: `make -C build test`, `make -C build check-packages` after a recipe change, and
a directory's own tests (`make -C kernel/dlm test`) ✅ (`CONTRIBUTING.md`). The kit's checker,
`modcheck.py`, names each rule a module breaks, and the module core makes the same refusals at load
time ✅.

## 4. Packaging with apkg

- **A module** ships as two kernel-space packages, `<name>-k30` and `<name>-k46`, with the object at
  `/etc/conf/mod.d/<name>` and its defaults at `/etc/conf/modreg.d/<name>` ✅. A driver directory's
  `pkg/build.sh` is three lines around `build/pkg/common/kdrv.sh` ✅. On the box, `kbootset build`
  then `kbootset commit` put it into the next boot generation, and the core loads only modules of
  the booted generation's manifest, checked by SHA-256, unless the boot menu's development load is
  on ✅. After a transaction that changes a kernel-space package, apkg runs `kbootset build && kbootset
  commit` itself when `bootset=auto`, the default ✅ (`spec/40-generations-and-composer.md`).
- **A userland package** is rolled from `package.sh`: `PKG` at most 9 characters, because stock
  `pkgadd` drops longer names without a word; `TOOLCHAIN=gcc14`, or `period` for a tool that must link
  only the stock libraries; `CONFFILES` for files an administrator edits ✅ (`build/pkg/README.md`).
- **A package you built** goes onto a test box by FTP and in with the stock tool,
  `pkgadd -d <file>.pkg <PKG>`, as apkg itself is bootstrapped ✅. Released packages come from the
  repository with `apkg install`. See [package management](../../how-it-works/package-management.md)
  and [the repository format](../../how-it-works/package-repository.md).
- **A display card** also ships its card file, `/etc/display.d/<card>`, in the driver's package, so
  `xstart` can find it ✅ ([worked example](x-backend-example.md#the-card-file)).

## 5. The test loop: emulation first

Let the tool run the whole loop itself, in this order:

1. **Host tests.** Logic that does not need the hardware runs on the build host. Where the board
   cannot be emulated, test the driver against a software model of the device, as the VA2000 card
   driver's harness does ✅ ([worked example](x-backend-example.md#testing)).
2. **Build** in the container, and read the checker's output.
3. **Install and boot in an emulator** where the hardware can be emulated. Amiberry 8.3.0 or newer
   runs and installs Amix, with the A3000's SCSI disk and tape, A2065 networking and an A4091 ✅
   ([Amix on Amiberry](../../getting-started/emulation-amiberry.md)). Know what the emulator does
   not reproduce ([emulation fidelity](../../how-it-works/emulation-fidelity.md)). Even for a board
   that cannot be emulated, the emulator still tests the package's install and a boot with the
   module present and no board, as the VA2000 packages are tested ✅.
4. **Drive the box from the host**: [`tools/host-net/`](https://github.com/amigaux/grimoire/tree/master/tools/host-net/)
   has `amixsh.py` (scripted commands over telnet, with an exit status) and `amixput.py` (upload by
   FTP), and [`tools/amishot.sh`](https://github.com/amigaux/grimoire/blob/master/tools/amishot.sh) takes an Amiberry screenshot ✅.
   Keep each command line under about 250 characters: a telnet line over the tty's 256-byte limit
   runs nothing and wedges the login ✅ ([quirk 99](../../how-it-works/quirks.md#99-canonical-line-wedge)).
5. **Real hardware** last, and only under [the rules for real hardware](real-hardware.md).

Have the tool say, for each result, where it ran. "Passes in emulation" and "runs on the card" are
different claims, and a driver's README should keep them apart, as the VA2000 driver's does: run on a
real card on the 68040/68060 line, with a list of what has not yet run ✅.

## 6. How to report

A report, whether from you or from the tool, says:

- **what ran**: the commit of your driver, the amix commit, the package versions;
- **where**: the emulator and its version and config, or the machine (model, CPU, accelerator,
  kernel line and version, the slot the board is in);
- **the exact commands and their output**, cut to what matters;
- **the result**, tagged: ✅ reproduced, 🟡 seen once, 🔴 unexplained;
- **what was not run**, so the next person knows where the edge is.

Send bugs, hardware support and feature requests as an issue with one of the forms at
[github.com/amigaux/amix/issues/new/choose](https://github.com/amigaux/amix/issues/new/choose), questions to its
[Discussions](https://github.com/amigaux/amix/discussions), and changes as a pull request: one topic
each, MIT, no CLA or sign-off line, and CI must pass ✅ (`CONTRIBUTING.md`). The privacy check in CI
refuses Commodore system files, Kickstart ROMs, disk and card images and large binaries ✅. A new
platform fact, or a correction to this site, goes to
[amigaux/grimoire](https://github.com/amigaux/grimoire) as an issue or pull request under its
[`AGENTS.md`](https://github.com/amigaux/grimoire/blob/master/AGENTS.md): with its source and
confidence tag.

## See also

- [Worked example: an X backend](x-backend-example.md)
- [Real hardware with an LLM tool](real-hardware.md)
- [An AGENTS.md for a driver repository](agents-template.md)
- [Loadable modules](../loadable-modules.md) and [toolchain](../toolchain.md)
- [Writing for LLM consumers](../../contributing/writing-for-llms.md), how this site is written for tools

## Sources

- amix `kernel/dlm/docs/README.md` and `kernel/dlm/docs/abi/writing-a-module.md` (the kit, `Master`
  keys, the driver wrapper, the module rules, shipping a module), `kernel/dlm/docs/spec/40-generations-and-composer.md`
  (kbootset, apkg integration), `kernel/modules/README.md`, `kernel/drivers/README.md`,
  `kernel/drivers/va2000/README.md`, `build/pkg/README.md`, `build/dist.sh` (`DRIVERS`),
  `docs/BUILDING.md`, `CONTRIBUTING.md` and `userland/pkgtools/README.md`, at amix `397b868f`, read
  2026-11-20 ✅.
- This site's pages linked above, with their own sources; quirk 99 for the line limit ✅.
