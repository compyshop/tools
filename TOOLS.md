# Atari 8-bit binaries: ca65 reverse engineering

This repo contains two Atari 8-bit binaries reverse engineered into
[cc65](https://cc65.github.io/)/`ca65` assembler source. Each `.s`/`.cfg`
pair reassembles to a **byte-identical** copy of the original binary:

```sh
ca65 autorun.s  -o autorun.o  && ld65 -C autorun.cfg  autorun.o  -o AUTORUN.SYS
ca65 rdtest2.s  -o rdtest2.o  && ld65 -C rdtest2.cfg  rdtest2.o  -o RDTEST2.COM
cmp AUTORUN.SYS AUTORUN.SYS.orig   # identical
cmp RDTEST2.COM RDTEST2.COM.orig   # identical
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
