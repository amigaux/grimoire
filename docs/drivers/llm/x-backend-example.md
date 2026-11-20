---
title: "Worked Example: an X Backend for the RTG Layer"
summary: How a new graphics card gets an X server on Amix — a card driver under the X11R6.3 server's card-neutral RTG layer (x11r63 6.3-10 and later), the rtgCardOps record, the card file for xstart, the kernel driver it sits on and how it is tested — with the VA2000 and ZZ9000/Z3660 backends as patterns.
status: draft
---

# Worked example: an X backend for the RTG layer

This is the [LLM driver guide](driver-guide.md) applied to one job: X on a graphics card that Amix
has no X server for yet. Since x11r63 6.3-10, the package's one server, `Xrtg`, has a card-neutral
RTG layer, and a card is added by writing one record of operations, not a server ✅. Two cards show
the pattern: the MNT ZZ9000 and the Z3660's RTG (one driver), and the MNT VA2000 (a driver kept in a
fork of its own) ✅.

Everything on this page is ✅ from the x11r6.3 package's README and patches in amix
`userland/packages/x11r6.3`, the card files and READMEs of amix `kernel/drivers/z3660rtg` and
`kernel/drivers/va2000`, amix-base's `display.d(4)`, and the VA2000 card directory's README in the
[amigaux/xrtg-amix](https://github.com/amigaux/xrtg-amix) fork, unless a line says otherwise.

## The stack

From the hardware up:

| Layer | Where | What it does |
|---|---|---|
| Kernel driver | a module, `/dev/<card>` | finds the board, gives `mmap` of the framebuffer (and the registers, where the server drives them) and the card's ioctls |
| Card driver | `programs/Xserver/hw/amix/rtg/<card>/` in the X tree | one `rtgCardOps` record: probe, modes, set up and tear down the hardware, and the blitter's fill, copy and flush |
| RTG layer | `rtg/rtgInit.c`, `rtgscreen.c`, `rtgdraw.c`, `rtgcards.c` | the screen on X's own 16-bit framebuffer code (cfb16), CPU fills and copies, the box order of a region copy, the direct PutImage, and when to call the card |
| Server | `Xrtg`, also installed as `Xzz9000` and `X` | the X11R6.3 server with the Amiga DDX (`hw/amix`): input, the screen manager, the monitor switch |
| Start-up | amix-base's `xstart`, `/etc/display`, `/etc/display.d/<card>` | which card is there, which server to run on it, with which arguments |

The layer runs cfb16 on the card's mapped framebuffer, so a card driver has no drawing code of its
own beyond fill and copy. A card without a blitter leaves those out, and the layer draws everything
on the CPU.

## The card record

`rtg.h` (patch 29) declares the record, version `RTG_CARD_VERSION` 1:

| Field | What the card gives |
|---|---|
| `name`, `device`, `modes` | `-card`'s name (`"va2000"`), the device for messages, the mode list for messages |
| `caps` | depth and bits per pixel (16), the TrueColor masks and bits per RGB value, `-blitmin`'s default, and flags: `RTG_CAP_BLITTER` (fill and copy drive a blitter), `RTG_CAP_USERREGS` (the card's registers are mapped into the server), `RTG_CAP_NOMOVE16` (no move16 into this framebuffer) |
| `probe()` | is the card there? Open, ask, close, with no side effects that last |
| `setMode(name)`, `modeSize(&w, &h)` | select `-mode WxH` for the next `initHW`, and report the selected size |
| `initHW(pRTG)` | open the device, set the mode, map the framebuffer, and fill in the screen record (base, pitch, size, depth, the device fd for the monitor switch); `FALSE` means no screen and everything undone |
| `closeHW(pRTG)` | undo `initHW`, also at a server reset |
| `fillBox`, `copyBox` | one box each; the layer orders the boxes of a region, and copies may overlap |
| `flush(pRTG)` | return when every queued fill and copy has finished on the card |
| `monitorSwitch(fd, which)` | the monitor to the card or back to the Amiga picture; `NULL` for none |

The contract the card keeps:

- `fillBox` and `copyBox` may queue and return early. The layer calls them only for areas of
  `rtgBlitMin` pixels or more, and flushes before any CPU access the queue could meet and before
  every screen entry point returns, so outside the layer the queue is always empty.
- A hook that returns `FALSE` has taken nothing, and the layer draws that operation on the CPU.
- A card whose blitter fails its self-test in `initHW` clears `RTG_CAP_BLITTER` in its caps, and the
  layer reads the caps again after `initHW`. A card that loses its blitter later draws what it still
  holds with `rtgCpuFill`/`rtgCpuCopy` and sets `rtgBlitMin` to 0.
- How the monitor switch passes its argument is the card's business: the ZZ9000 driver's ioctl reads
  an `int`, the VA2000 driver's an `unsigned short`. An `int` sent to the VA2000 reads as 0 on m68k.

Choosing the card: `-card NAME`, else the server's name (`Xzz9000` means the ZZ9000), else, with
`-card auto` or under `Xrtg` or `X`, the first card in `rtgCards[]` whose probe succeeds. A card the
server has no driver for stops it with the list of cards. `-dev PATH` names the device node, for a
machine with two cards (a ZZ9000 beside a Z3660 is `/dev/zz9001`). A card's probe and `initHW` open
`rtgCardDevice(card)`, never a fixed path, so `-dev` reaches them (patch 33).

## Two patterns

**ZZ9000 and Z3660** (`rtg/zz9000/`, patch 30). The device, mode, framebuffer map and blitter
queue sit behind `zz9000CardOps`. The blitter is reached through the kernel driver, which takes a
batch of operations in one `ZZ9KIOC_BLITS` ioctl. The monitor switch is an `int` ioctl. It is the
pattern for a card whose kernel driver owns the blitter.

**VA2000** (`rtg/va2000/`, from the xrtg-amix fork at a pin). It is the pattern for a card the
server drives from user space:

- the driver maps two windows, the 4 KB register page and the mode's framebuffer, each checked
  against the mode and the board's aperture (4 MB in Zorro II, 32 MB in Zorro III, from
  `SVGAIOCGetFBufSize`); a mode that does not fit is refused;
- it writes the mode registers from user space, in the order of the card's older X11R5 driver;
- every blitter wait is bounded (500000 status reads, about 100 ms), and a wait that reaches the
  bound gives up the blitter for the rest of the server's life;
- a self-test at every `initHW`: the blitter idle, and a 1x1 fill that finishes and appears;
- its caps carry `RTG_CAP_NOMOVE16`, because move16 bursts are not proven on the card's Zorro III bus;
- its probe takes a node as a VA2000 only if it answers `VA2IOC_GETFW`, which every version of the
  VA2000 kernel driver answers and no other driver does, and it refuses before mapping or writing
  anything otherwise.

The VA2000's card files are `va2000.h` (memory map, ioctls, mode records, registers), `va2000hw.c`
(the record, modes, probe, mappings, mode registers, monitor switch), `va2000blit.c` (fill, copy,
flush, the bounded wait, the self-test) and an `Imakefile` that builds `libva2000.a`.

## How the package takes a card in

A card driver kept in its own repository goes into the X build without a patch to its files:

1. The package's `package.sh` names it in `FORKDIRS`, a triple of pin file, path in the fork and path
   in the tree:
   `userland/packages/x11r6.3/xrtg-amix.pin x11r6.3/hw/amix/rtg/va2000 programs/Xserver/hw/amix/rtg/va2000`.
   The pin file is one line, `<git URL> <40-hex commit>`; the build fetches that commit by hash and
   copies the directory in after unpacking and before the patches ✅ (`build/pkg/README.md`).
2. A patch (patch 32 for the VA2000) wires it in: the card in `rtg/Imakefile`'s `SUBDIRS`,
   `-DRTG_<CARD>` in `RTGCARDS`, the card's library after the rtg library in the server's
   `Imakefile`, and the name in the `-card` usage line. `rtgcards.c` lists each card's record under
   `#ifdef RTG_<CARD>`, in the order `-card auto` probes them; the ZZ9000 comes first, then the
   VA2000.
3. `make recipes/x11r6.3` builds the package in the container. A change to the card's files is a
   change in its repository and a new pin.

The whole server compiles under the package's GCC 14 strict gate: no implicit declarations, no
pointer and integer conversions, `-mno-strict-align` on every compile line. The VA2000 files also
compile clean with `-Wstrict-prototypes`.

## The card file

The card's kernel-driver package installs `/etc/display.d/<card>`, which tells `xstart` how to
find the card and run its server (`display.d(4)`). Which card is used, and in which mode, is in
`/etc/display` (`card auto`, or `card va2000`). The VA2000's file:

```text
# /etc/display.d/va2000 -- the MNT VA2000 RTG card (display.d(4))
name      MNT VA2000
node      /dev/va2000
module    va2000
server    /opt/amix/X11R6/bin/Xrtg
modes     1024x768 640x480 800x600 1280x720 1280x1024 1920x1080
depths    16
args      -card va2000 -mode %m -kb
monsw     no
```

The first mode is the default. Other keys: `probe` (a command, by full path, for a card whose node
alone cannot tell, such as the Z3660's `zz9k_probe z3660`), `limits` (raise `vmem` and `data` for a
server that maps the whole board), `monswtool` and `restore` (the Z3660 hands the keyboard back with
`rtg-kbdback`), `env`, `once`, and `%m %w %h %d %n %p` in `args`. A probe must return at once, change
nothing, be safe as any user with no board fitted and inside the installer's `chroot`, and read the
board's identity from the driver rather than from a node opening. A probe line needs amix-base 1.0-35
or later; earlier bases, as on the 1.1 and 1.1.1 install media, stop at it.

## The kernel side

The VA2000's module is demand class: it loads at the first open of `/dev/va2000` (character major
68) and stays only when it finds a board ✅ (`kernel/drivers/va2000/README.md`). A new card's driver
needs a major from the [registry](../../reference/major-number-registry.md), an ioctl that gives the
board's identity so probes can tell boards apart, and, on the 68040/68060 line, its framebuffer
registered with `DDI_FB_REGISTER` so the user mapping gets the fast non-cacheable class ✅
([loadable modules](../loadable-modules.md), amix `kernel/dlm/docs/abi/writing-a-module.md`).

## Testing

A graphics card cannot be tested in Amiberry: the VA2000 cannot be emulated, and the emulator has
no ZZ9000 or Z3660 RTG either 🟡 (no such device in the [Amiberry page](../../getting-started/emulation-amiberry.md)).
So the card driver is tested on the host against a software model, then on the card:

- **Host model.** The VA2000 fork's `make -C tests/va2000 check` builds the card files for the host,
  twice (with and without the counters), and runs them against a model of `/dev/va2000` and of the
  card. The model covers open, close, the ioctls, `mmap` over a Zorro II, Zorro III or unknown
  aperture, the register page and a blitter that can be made to stick, do nothing or misread. It
  checks results against a plain CPU fill and copy, checks that probe and `initHW` refuse a node of
  another driver before mapping or writing, and checks the caps flags after a passing self-test, a
  failing one and a blitter lost later. Give a new card's driver the same kind of model first: it is
  where an LLM tool can iterate fast and safely.
- **Emulation.** The packages' install and a boot with the module present and no board.
- **The card.** Under [the rules for real hardware](real-hardware.md). The VA2000 status to copy as
  a model of a status line: on an Amiga 3000 with a 68060 (kernel k46 -67, va2000-k46 1.1.0-2, x11r63
  6.3-11) the module loads at the first open and stays, the card's test tools work (7 of the 9
  modes; the monitor refused two), and `Xrtg`, started by `xstart card=va2000`, drives the card at
  1024x768 and 1280x720 with mouse and keyboard. Not yet run on a real card: the 68030 package, XDM,
  unloading and reloading the module, a boot with the module in the boot set, and long runs ✅.

## Steps for a new card

The plan to give the tool:

1. Read this page, `rtg.h` (patch 29), the VA2000 card directory and its README, and `display.d(4)`.
2. Check the kernel driver gives what the backend needs: a node, `mmap`, an identity ioctl, the
   blitter's interface if the kernel owns it.
3. Write the card directory: `<card>.h`, `<card>hw.c` (record, probe, modes, `initHW`, `closeHW`,
   monitor switch), `<card>blit.c` if there is a blitter (bounded waits, a self-test), `Imakefile`.
4. Write the host model and its tests, and make them pass.
5. Wire it in: `FORKDIRS` and a pin, a patch for `SUBDIRS`, `RTGCARDS` and the server libraries,
   `make recipes/x11r6.3`.
6. Write the card file and add it to the kernel driver's package.
7. Test the install in emulation, then the card; report what ran and what did not.

## See also

- [Writing an Amix driver with an LLM tool](driver-guide.md)
- [X11 RTG graphics drivers](../x11-rtg-drivers.md) and [X11 & the desktop](../../how-it-works/x11-and-desktop.md)
- Case studies: [va2000](../case-studies/va2000.md), [xrtg](../case-studies/xrtg.md),
  [zz9000](../case-studies/zz9000.md), [x11r6.3 (Xzz9000)](../case-studies/x11r63-zz9000.md)

## Sources

- amix `userland/packages/x11r6.3`: `README.md`, `package.sh` (`PKGREV` 12, `FORKDIRS`),
  `patches/29-rtg-card-ops.patch` (the record and its contract), `patches/30-rtg-card-neutral.patch`
  (the layer, `rtgcards.c`, card choice), `patches/32-rtg-va2000.patch`, `patches/33-rtg-dev.patch`,
  `xrtg-amix.pin` (`552968e`), `man/Xrtg.1`; `kernel/drivers/va2000/README.md` and
  `pkg/va2000.display`; `kernel/drivers/z3660rtg/README.md` and `pkg/z3660.display`;
  `userland/base/display/display.d.4`; `build/pkg/README.md` (`FORKDIRS`); at amix `397b868f`, read
  2026-11-20 ✅.
- amigaux/xrtg-amix at `552968e`: `x11r6.3/hw/amix/rtg/va2000/README.md` and `Imakefile` ✅.
- No ZZ9000, Z3660 RTG or VA2000 device in Amiberry: absence from this site's Amiberry page, not a
  check of the emulator's source 🟡.
