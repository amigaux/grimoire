---
title: An AGENTS.md for a Driver Repository
summary: A ready-to-copy AGENTS.md for an Amix driver repository, so an LLM coding tool follows the same rules every session — read this site first and trust its tags, build only in amix's container, write for the stock SVR4 shell and grep, keep box command lines short, brief commits, hardware safety, and how to report — with the reason behind each rule.
status: draft
---

# An AGENTS.md for a driver repository

LLM coding tools read a file in the repository's root at the start of a session: `AGENTS.md` for
Codex and most others, `CLAUDE.md` for Claude Code (which can simply contain a line pointing at
`AGENTS.md`). Copy the template below into your driver repository, fill in the bracketed parts, and
the rules of the [LLM driver guide](driver-guide.md) bind every session without your repeating them.
The reasons and sources for each rule are [below the template](#why-each-rule).

## The template

````markdown
# AGENTS.md — rules for AI coding tools in this repository

This repository is [driver name]: a driver for [the device] on Amiga UNIX (Amix), the SVR4.0
system for 68030 and 68040/68060 Amigas. [One line: kernel module, STREAMS driver, X backend,
user-space tool.] Follow these rules exactly.

## 1. Read before you write

- Platform facts come from the Amix grimoire, https://grimoire.amigaux.org: start at its
  llms.txt, search llms-full.txt, and find each fact's source in sources/research-brief.md.
- Trust its confidence tags: ✅ verified, 🟡 reported but not checked first-hand, 🔴 unverified.
  Rely on ✅. Say so when you rely on 🟡. Never raise a tag yourself.
- For modules: amix kernel/dlm/docs (spec/, abi/writing-a-module.md, abi/ddi.md, contracts/)
  and the examples in amix kernel/modules. For X backends: the grimoire's worked example and the
  x11r6.3 package in amix userland/packages/x11r6.3.
- Do not carry over facts from Linux, the BSDs or later SVR4 releases. If the grimoire and the
  amix docs do not say it, it is a question to test, not an assumption.
- Name the page or file behind each platform fact in your commit or report.

## 2. Build only in amix's container

- Build with amix's build container (`make tools`, then `make kit`, `make modules`,
  `make drivers/<name>` or `make recipes/<name>`). Never install or build a cross compiler of
  your own, and never build with whatever compiler the host has.
- Kernel space (modules, drivers) is gcc-cross-amix, GCC 2.7.2.3; userland is gcc14-cross-amix,
  GCC 14. Both are in the container at their pins.
- A module must pass the kit's checker (modcheck.py); read what it says before you change code.
- Run the host tests before every commit: [this repository's test command].

## 3. Write for the stock system on the box

Scripts that run on Amix (install scripts, tests, rc files) run under the stock 1990 /bin/sh and
the stock tools:

- no `$(...)`: use backticks;
- no `grep -q`, `grep -e`, `grep -E` or `\|` in a pattern: redirect grep to /dev/null and test
  `$?`, and use egrep or two greps for alternatives;
- `false` exits 255, `mkdir -p` fails on an existing directory, a `while read` loop fed by `<`
  runs in a subshell, and an EXIT trap replaces the exit status: see the grimoire's quirk 12.

## 4. Commands sent to the box

- Keep every command line sent over telnet under about 250 characters. A line over the tty's
  256-byte limit runs nothing and wedges the login (grimoire quirk 99). Split long work into
  several lines or a script copied over by ftp.
- Never end a command sent through a transport with a bare `&`; use nohup and poll a log
  (grimoire quirk 39).
- A remote halt that drops the connection has usually worked. Check with the next boot, never
  by running it again.

## 5. Commits

- Brief messages: a subject of at most 72 characters in the imperative, saying what changed;
  a body only for what the diff cannot show (why, measured numbers, hashes).
- Describe the change, never the conversation that produced it.
- [Your attribution policy for AI tools.]

## 6. Hardware safety

The device under test cannot be emulated, so the last tests run on a real Amiga. Follow the
grimoire's page "Real hardware with an LLM tool" (drivers/llm/real-hardware). In short:

- Read [path to the devices file] first. Name the machine in every hardware command.
- Write only to the targets it marks writable. Read back what you wrote.
- Clean shutdown before power-off, then 10 s quiet. Log every power action with a time stamp.
- Firmware writes: CRC-checked, the old image saved, a tested way back.
- A warm reset is not a clean start: power-cycle, 15–20 s off, when a run must start from a
  known state. Never warm-reset a real 68060 and carry on.
- If the hands-on flag is set, make no power or reset action. Report and wait.
- Cables, cards, disks and anything you cannot see are the human's. Ask.

## 7. Reporting results

Each result says: what ran (commits, package versions), where (emulator and version, or the
machine: model, CPU, kernel line, slot), the exact commands and the output that matters, the
result tagged ✅ reproduced / 🟡 seen once / 🔴 unexplained, and what was not run. Keep "passes
in emulation" and "runs on the device" apart. Bugs in amix go to github.com/amigaux/amix/issues,
new platform facts to github.com/amigaux/grimoire.
````

## Why each rule

| Rule | Why | Source |
|---|---|---|
| Read the grimoire first, trust its tags | Much of the Amix lore is wrong, and a tool falls back on Linux habits without grounded documents | this site's [`AGENTS.md`](https://github.com/amigaux/grimoire/blob/master/AGENTS.md) |
| Build only in the container | The cross compilers are pinned and built inside it; the fixed `/src` path keeps the period compiler from building your checkout's location into the bytes, so a result can be rebuilt exactly ✅ | amix `docs/BUILDING.md` |
| No `$(...)`, no `grep -q` | The stock `/bin/sh` predates POSIX, and its grep has no `-q` ✅ | [quirk 12](../../how-it-works/quirks.md#12-binsh-is-pre-posix) |
| No `grep -E` | The stock SVR4 grep's `-E` is shaky ✅ (amix's grep package README); prefer `egrep` | amix `userland/packages/grep/README.md` |
| No `grep -e`, no `\|` | `\|` is a GNU extension of basic regular expressions, and the stock grep is not GNU; `-e` is kept out for the same caution 🟡 (not measured here) | — |
| `false`, `mkdir -p`, `while read`, EXIT trap | Measured on the stock shell ✅ | [quirk 12](../../how-it-works/quirks.md#12-binsh-is-pre-posix) |
| Lines under about 250 characters | `MAX_CANON` is 256; a 237-byte line answered, 260- and 269-byte lines ran nothing and wedged the login ✅ | [quirk 99](../../how-it-works/quirks.md#99-canonical-line-wedge) |
| No bare trailing `&` | A bare trailing `&` sent to the box's transport silently never runs ✅ | [quirk 39](../../how-it-works/quirks.md#39-transport-ampersand-law) |
| A dropped connection after a halt | `uadmin 2 0` kills the session that sent it; the next boot's `fsck` is the proof ✅ | [quirk 47](../../how-it-works/quirks.md#47-halt-looks-like-failure) |
| Brief commits | amix's own rule for commit messages ✅ | amix `CONTRIBUTING.md` |
| Hardware safety | A wrong power action or write on a real machine costs hours; a warm reset is not a clean start 🟡 | [real hardware](real-hardware.md), [quirk 49](../../how-it-works/quirks.md#49-power-cycle-law) |
| Reporting | Another person, or the next session, must be able to rebuild and rerun what you claim | [the guide](driver-guide.md#6-how-to-report) |

## See also

- [Writing an Amix driver with an LLM tool](driver-guide.md)
- [Worked example: an X backend](x-backend-example.md)
- [Real hardware with an LLM tool](real-hardware.md)
- [Writing for LLM consumers](../../contributing/writing-for-llms.md)

## Sources

- This site's `AGENTS.md` and quirks 12, 39, 47, 49 and 99, with their own sources ✅/🟡 as tagged
  there.
- amix `docs/BUILDING.md`, `CONTRIBUTING.md` and `userland/packages/grep/README.md`, at amix
  `397b868f`, read 2026-11-20 ✅.
- The `grep -e` and `\|` rule is a precaution, not a measurement on the box 🟡.
