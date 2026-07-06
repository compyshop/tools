# Atari 8-bit binaries: ca65 reverse engineering

This repo contains two Atari 8-bit binaries reverse engineered into
[cc65](https://cc65.github.io/)/`ca65` assembler source. Each `.s`/`.cfg`
pair reassembles to a **byte-identical** copy of the original binary:

```sh
ca65 autorun.s  -o autorun.o  && ld65 -C autorun.cfg  autorun.o  -o AUTORUN.SYS
ca65 rdtest2.s  -o rdtest2.o  && ld65 -C rdtest2.cfg  rdtest2.o  -o RDTEST2.COM
ca65 conv32d.s  -o conv32d.o  && ld65 -C conv32d.cfg  conv32d.o  -o CONV32D.COM
ca65 autogen.s  -o autogen.o  && ld65 -C autogen.cfg  autogen.o  -o AUTOGEN.COM
ca65 mfcopy.s   -o mfcopy.o   && ld65 -C mfcopy.cfg   mfcopy.o   -o MFCOPY.COM
ca65 scopy.s    -o scopy.o    && ld65 -C scopy.cfg    scopy.o    -o SCOPY.COM
cmp AUTORUN.SYS AUTORUN.SYS.orig   # identical
cmp RDTEST2.COM RDTEST2.COM.orig   # identical
cmp CONV32D.COM CONV32D.COM.orig   # identical
cmp AUTOGEN.COM AUTOGEN.COM.orig   # identical
cmp MFCOPY.COM MFCOPY.COM.orig     # identical
cmp SCOPY.COM SCOPY.COM.orig       # identical
```

Both originals are Atari DOS "binary load" files: a `FF FF` signature,
followed by one or more `start/end` address segments, optionally ending in
a `$02E0/$02E1` (RUNAD) segment that sets the program's entry point.

## AUTORUN.SYS

`autorun.s` / `autorun.cfg` — source: `AUTORUN.SYS` (471 bytes).

A "BIBO-DOS Anwender-Disk" boot menu. Loads at `$2400`:

- `$2400-$254C`: an ATASCII screen/text buffer, printed character by
  character (the on-screen menu).
- `$254D-$25CA`: 6502 code — reads a keypress (A-F), echoes it, and hands
  off to an external file loader (`RunFile` at `$070F`, outside this file)
  with a pointer to the chosen `D:`-prefixed filename.
- Entry point (RUNAD) is `$2561`, partway into the code; the bytes before
  it (`$254D-$2560`) are a small helper subroutine used by the entry code.

## RDTEST2.COM

`rdtest2.s` / `rdtest2.cfg` — source: `RDTEST2.COM` (1097 bytes).

An extended-RAM ("PORTB banked memory") access test / hardware diagnostic.
Loads at `$3000`, entry point (RUNAD) is `$3000`:

- `$3000-$31B7`: 6502 code. Cycles through 16 bit-patterns written to
  `PORTB` ($D301, the PIA register that selects which physical RAM/ROM
  bank is mapped into the CPU address space on XL/XE machines), writes and
  reads back a test pattern in the `$4000-$40FF` window for each pattern,
  sounds a POKEY sweep tone, and updates an on-screen "Bank N" status.
- `$31B8-$3434`: data — the 16-byte PORTB bank-select table, small lookup
  tables of Atari "internal" (screen) character codes, a POKEY/VBI
  color-cycle routine (present as data only; no call site into it was
  found in the reachable code), and German status-message string
  fragments ("...Zugriff ist ok" / "...funktioniert nicht" / "...keine
  Diskette vorhanden").
- `$3435-$343C`: a short deferred-VBI handler tail, installed via `SETVBV`.

## CONV32D.COM

`conv32d.s` / `conv32d.cfg` — source: `CONV32D.COM` (1372 bytes).

The "DOS 3/DOS 2 Konvertierung" file copy utility. Loads at `$2400`, no
RUNAD segment (like `RDTEST2.COM`, it's one of the menu items launched by
`AUTORUN.SYS`'s `RunFile`, not run directly by DOS):

- On-screen menu: `[1]` Set Source Drive, `[2]` Set Destination Drive,
  `[3]` Copy File, `[4]` Exit — options `1`/`2` just toggle the
  source/destination drive number between 1 and 2.
- `[3]` reads directory sector 16 from the destination drive via a raw SIO
  "Read Sector" DCB call (not CIO), lists files with an inverse-video
  `A`-`Z` prefix to pick one, then copies it 128 bytes at a time from the
  source drive into `$0400` and out to the destination drive, opening the
  destination file over CIOV (IOCB #1) — converting between the DOS
  3/DOS 2 directory layouts along the way.
- Most on-screen text is stored *inline*, immediately after the call that
  prints it (`jsr PrintInline` at `$287A`): that routine pulls its own
  return address off the stack, prints bytes starting there until an `$EA`
  (NOP) sentinel, then resumes code execution right after the sentinel.
  This is unwound explicitly in the source rather than left for the
  disassembler, which otherwise misinterprets the embedded text as code.

## AUTOGEN.COM

`autogen.s` / `autogen.cfg` — source: `AUTOGEN.COM` (552 bytes).

The "AUTORUN.SYS Generator": prompts "Basic Befehl eingeben:" (Enter BASIC
command:), reads up to 40 typed characters, then writes a brand-new,
self-contained `AUTORUN.SYS` to `D:` that automatically "types" that
command into BASIC at the next boot. Loads at `$4000`, no RUNAD segment
(same launch convention as `RDTEST2.COM`/`CONV32D.COM`).

The generated file is embedded verbatim in this one (`$41A0` to end of
file) as a complete, separate ~130-byte Atari DOS binary load file for a
tiny program of its own, loaded at `$0680`. That program is a type-ahead
trick: it copies the OS ROM's E: device vector table into RAM, patches
the copy's GET-byte vector to a replacement routine, and redirects
HATABS's E: entry at `$0321/$0322` to the patched copy — so every
keyboard read returns the next character of a stored 40-byte buffer
instead of an actual keypress, until it hits the EOL byte and restores
normal E: operation. `autogen.s` documents this nested program's behavior
in comments, using its own `$0680`-relative addresses, while still
reproducing every byte of the outer file exactly.

Same inline-string-printing trick as `CONV32D.COM` (`jsr PrintInline` +
text terminated by an `$EA` sentinel) is used here too.

## MFCOPY.COM

`mfcopy.s` / `mfcopy.cfg` — source: `MFCOPY.COM` (3727 bytes), "Multi
Filecopy II (c) 1988 BIBOSOFT". By far the largest and most sophisticated
of these five files, in 4 DOS binary-load segments (72 + 207 + 3428 bytes,
plus a RUNAD segment).

It's an interactive dual-drive directory browser and multi-file copier
("D1:\*.\* -> D1:\*.\*", pick source/destination drives, browse and
multi-select files with Up/Down/Space/A(ll)/Return, copy with progress
messages, format-destination-disk support, and read/write/write-protect/
format error handling). Being much bigger than a menu-launched utility
slot comfortably allows, it relocates almost all of itself into the
memory normally shadowed by the OS ROM at $E000-$F7FF (exposed as RAM via
`PORTB`, $D301 bank-switching, the same register used by `RDTEST2.COM`):
a small ($0500) relocator segment copies the large ($2A00-on-disk)
segment to $EA00-$F7FF and jumps into it, using a second small ($0600)
segment of PORTB on/off wrapper routines along the way. `mfcopy.s`
disassembles that large segment at its *run* address ($EA00), and the
linker config places its bytes at its *load* address ($2A00) in the
output file — a `load`/`run` segment split, same idea used for
bank-switched ROM code on other 6502 systems.

Same inline-string-printing trick as the other files, but with a small
twist: this program has two call sites, one that also resets a screen
color/position pair before printing, and one that prints directly; both
print through a direct screen-memory write routine rather than a CIO PUT
vector call, since this program manages its own screen output.

## SCOPY.COM

`scopy.s` / `scopy.cfg` — source: `SCOPY.COM` (3240 bytes), "Sektor
Kopierer" (Sector Copier). In 4 DOS binary-load segments (164 + 3050 + 6
bytes, plus a RUNAD segment).

Uses the same relocate-into-OS-ROM-shadow-RAM trick as `RDTEST2.COM`/
`MFCOPY.COM`, but relocates to the very top of the address space
($F000-$FFFF) instead of $EA00-$F7FF: a small ($2F00) segment saves
$E000-$E3FF, flips `PORTB` ($D301), relocates its own tail plus the large
on-disk segment up to $F000-$FFFF, copies a small stub into page 1
(`$0100`, ordinary RAM unaffected by the bank switch) to survive the
handoff, then jumps into the relocated program at $F4ED. `scopy.s`
disassembles that large segment at its *run* address ($F400); the linker
config places its bytes at its *load* address ($3400) - the same
load/run segment split used for `MFCOPY.COM`.

Same inline-string-printing trick as the other files, but this one builds
messages into a buffer (`$FEAA`) rather than printing character-by-
character directly. A German menu/options word table ("einstellen"=set,
"formatieren"=format, "original diskette", "ziel diskette", "disketten
einlegen"=insert disks, "disk fehler"=disk error) sits in a small data
area before the entry point.

## Notes on accuracy

Both sources reproduce every byte of their originals exactly (verified
with `cmp`), including in regions that are ambiguous or unreachable by
any code path found. Where the disassembly is confident about semantics
(known OS/hardware register names, well-known idioms like the OS
jiffy-clock wait or the CIO vector RTS-jump trick), the source says so
directly. Where it isn't — a handful of internal zero-page variables, some
data table boundaries, and the exact intent of a couple of message
strings — the comments say so too, rather than asserting a specific
meaning that isn't verifiable from the binary alone.

Toolchain used: cc65 2.19 (`ca65`/`ld65`), Ubuntu package `cc65`.
