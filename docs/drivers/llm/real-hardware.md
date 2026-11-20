---
title: Real Hardware with an LLM Tool
summary: When a device cannot be emulated — what to let an LLM coding tool do on a real Amiga running Amix and how to keep it safe: a dedicated machine with scratch disks, remote access (serial console, telnet/ftp, a smart plug, KVM capture), a devices file that describes the machine, the rules the tool follows, a hands-on flag, and what stays the human's.
status: draft
---

# Real hardware with an LLM tool

Some devices cannot be emulated: a graphics card, a network or SCSI board without an emulator model,
an accelerator's own hardware. Then the driver's last tests run on a real Amiga, and an LLM tool
that can power-cycle, type and write disks on that machine needs rules. This page generalises one
working practice. The rules come from experience with Amix on real machines; the ones that rest on a
measured fact link to it, and the rest are marked as practice 🟡.

## The machine

- **A dedicated development machine, with nothing valuable on it.** Everything it holds can be
  rebuilt from git and the release media in minutes. Then a wrong write costs a reinstall, not data,
  and you can give the tool full access to it without asking each time 🟡 (practice).
- **Scratch disks and images only.** The tool writes only to targets you have named as scratch: a
  spare disk, an SD card in a SCSI emulator, an image file. Keep the disks you care about out of the
  machine, or out of the tool's list.
- **Rebuildable state.** Keep the install images, kernels and configuration the machine boots from
  in version control or on the release media, so "start again from known" is one step.

## Remote access

The tool works through the same channels you would use from another room:

| Channel | Use | Know this |
|---|---|---|
| Serial console | boot messages, kernel panics, firmware menus, a login when the network is down | Let one program own it: two programs reading a USB-serial adapter take each other's bytes 🟡 (practice) |
| telnet and ftp over the network | commands and file transfer once Amix is up | A command line over the tty's 256-byte limit runs nothing and wedges the login, so keep lines under about 250 characters ✅ ([quirk 99](../../how-it-works/quirks.md#99-canonical-line-wedge)); a successful remote halt looks like a dropped connection ✅ ([quirk 47](../../how-it-works/quirks.md#47-halt-looks-like-failure)) |
| A smart plug | power off and on | The only reset that is always clean (below) |
| KVM capture | the screen and keyboard, for what the serial line does not show (an X display, a graphical boot menu) | The Amiga's own keyboard is a second live input into an accelerator's firmware menu, where one key can start a destructive operation ✅ ([real hardware](../../getting-started/real-hardware.md)) |

The scripted helpers in [`tools/host-net/`](https://github.com/amigaux/grimoire/tree/master/tools/host-net/)
(`amixsh.py`, `amixput.py`) work the same against a real machine as against an emulator ✅.

## Describe the machine to the tool

Give the tool one file that says what the machine is and how to reach it, so it never guesses a
board, a slot or a power socket. A devices file in your repository, for example (every value here is
a placeholder):

```yaml
machines:
  devbox:
    model: Amiga 4000            # the machine
    cpu: 68060 on an accelerator # and the CPU mode it boots in
    kernel_line: k46             # k30 for a 68030
    boards:
      - { slot: "Zorro III #1", board: "the card under test", node: /dev/<card> }
      - { slot: "Zorro II #2",  board: "network card", note: "the telnet path" }
    disks:
      - { id: 6, what: "boot disk", writable: false }
      - { id: 5, what: "scratch disk", writable: true }
    consoles:
      serial: { device: <host serial device>, speed: 9600 }
      network: { address: <machine address>, login: root }
      kvm: { unit: <capture unit>, input: 1 }
    power:
      plug: <smart plug name>    # off/on only
    hands_on: false              # set true while a person works at the machine
```

Tell the tool to read it at the start of every session and to name the machine in every command
that touches hardware.

## The rules the tool follows

Put these in the repository's [`AGENTS.md`](agents-template.md) so they bind every
session:

- **Clean shutdown before power-off.** While Amix is up, halt it over telnet or the console first
  (`sync; sync; /sbin/uadmin 2 0`) 🟡 (practice). The halt is proven clean only by the next boot's
  `fsck` repairing nothing ✅ ([quirk 47](../../how-it-works/quirks.md#47-halt-looks-like-failure)). A
  run-level change requested over telnet while the console sits at `login:` stalls in the stock
  `init`, so keep a root shell logged in on the console, or halt rather than reboot ✅
  ([quirk 58](../../how-it-works/quirks.md#58-console-getty-shutdown-stall)).
- **A 10 s quiet after the halt** before the power goes off 🟡 (practice).
- **Every power action logged**, with a time stamp and the reason, in a file the human can read.
- **Write only to scratch targets**, the ones the devices file marks writable.
- **Read back what was written** when it is small or the link is fast: a disk image's hash, a
  configuration file's bytes.
- **Firmware writes are CRC-checked, with a rollback ready**: the old image saved, the way back
  tested, and a failsafe boot path known before the write 🟡 (practice).
- **Never warm-reset a real 68060 and carry on.** A warm reset is not a clean-state reset: on one
  accelerator the firmware's warm reset gave a valid reset vector 0 times in 3, where a power cycle
  gave it 5 times in 5 🟡 ([quirk 49](../../how-it-works/quirks.md#49-power-cycle-law), one unit).
  Plan on a power cycle, with 15–20 s off, whenever the next run must start from a known state.
- **Send a command and its confirmation in one write** to a firmware prompt, so a keystroke from the
  machine's keyboard cannot answer it first ✅ ([real hardware](../../getting-started/real-hardware.md)).
- **Stop and report** on anything the tool cannot explain from what it sees, rather than retrying
  power actions.

## The hands-on flag

When a person works at the machine (changing a card, reseating a cable, reading the screen), they
set a flag that stops the tool's power and reset actions. It does not need to stop reading the
serial line or the screen. Keep it simple and checkable: a line in the devices file (`hands_on:
true`), a file the power script tests, or a lock in whatever tool runs the plug. The power script
checks the flag before every action and refuses while it is set; the tool reports the refusal and
waits, and never works around it 🟡 (practice).

## What stays the human's

- Plugging and unplugging cables, inserting and removing cards and disks, setting jumpers.
- Anything the tool cannot see: a smell, a noise, a light on a board, a monitor that shows nothing
  the capture can see.
- Clearing the hands-on flag.
- Deciding when a result is good enough to publish.

## See also

- [Writing an Amix driver with an LLM tool](driver-guide.md)
- [An AGENTS.md for a driver repository](agents-template.md)
- [Running Amix on real hardware](../../getting-started/real-hardware.md)
- [Quirks 47](../../how-it-works/quirks.md#47-halt-looks-like-failure),
  [49](../../how-it-works/quirks.md#49-power-cycle-law) and
  [58](../../how-it-works/quirks.md#58-console-getty-shutdown-stall): halts, resets and remote
  run-level changes

## Sources

- This site's quirks 47, 49, 58 and 99 and the real-hardware page, with their own sources ✅/🟡 as
  tagged there.
- The rules marked 🟡 (practice) are one project's working practice on its development machines,
  not measured platform facts.
