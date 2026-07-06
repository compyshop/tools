; ---------------------------------------------------------------------------
; MFCOPY.COM - "Multi Filecopy II" (c) 1988 BIBOSOFT
; Reverse engineered from a 3727-byte Atari DOS binary load file.
;
; Layout on disk (Atari DOS "binary load" format), no repeated FF FF
; signature between segments:
;   FF FF              - binary load file signature
;   00 05 47 05        - segment #1: start=$0500, end=$0547 (72 bytes)
;   00 06 CE 06        - segment #2: start=$0600, end=$06CE (207 bytes)
;   00 2A 63 37        - segment #3: start=$2A00, end=$3763 (3428 bytes)
;   E0 02 E1 02 00 05  - RUNAD segment: run address = $0500
;
; Architecture: this program is much larger than fits comfortably alongside
; DOS/BASIC in a menu-launched utility slot, so it relocates most of itself
; into the memory normally shadowed by the OS ROM at $E000-$F7FF (visible
; as RAM once PORTB, $D301, has the OS ROM banked out), using PORTB
; bank-switch tricks like the ones seen in RDTEST2.COM:
;   - Segment #1 ($0500, the RUNAD entry point) does three block moves via
;     a small page-copy routine, toggling PORTB (through segment #2's
;     wrapper routines) around them, then relocates segment #3's on-disk
;     bytes ($2A00-$3763) to $EA00-$F7FF and jumps into segment #2 to
;     finish switching PORTB back before entering the relocated program.
;   - Segment #2 ($0600) is glue: small PORTB on/off wrapper routines used
;     by both segment #1 and (via direct calls) segment #3, plus a
;     self-modified "return to caller" trampoline and a filename buffer.
;   - Segment #3 is disassembled here at its *run* address, $EA00 (not its
;     on-disk load address $2A00) since that's the address space its own
;     internal references resolve in; the linker config places its bytes
;     at $2A00 in the output file while keeping symbols resolved at $EA00.
;
; Same inline-string-printing trick as CONV32D.COM/RDTEST2.COM/AUTOGEN.COM,
; but with two entry points: "jsr PrintInlineSetup" ($EB1E, which also
; resets a screen color/position pair before printing) and "jsr PrintInline"
; ($EB21) directly. Both pull the return address off the stack, print
; bytes from there through ScreenPoke (a direct screen-memory writer, not
; a CIO PUT vector call - this program manages its own screen output) until
; an $EA (NOP) sentinel, then resume execution right after it. All 20 such
; strings in segment #3 are reproduced verbatim below, immediately after
; the call that prints them.
;
; What it does: an interactive dual-drive directory browser and multi-file
; copier - "D1:*.* -> D1:*.*", pick source/destination drives, browse and
; multi-select files with Up/Down/Space/A(ll)/Return, then copy with
; progress messages, format-destination-disk support, and read/write/
; write-protect/format error handling with retry/continue/abort prompts.
;
; A byte-identical rebuild was verified with ca65/ld65 and cmp against the
; original MFCOPY.COM. Several PORTB bank-switch/relocation details (the
; exact effect of the $FF/$FE writes, a handful of internal zero-page/page
; -7 scratch addresses, and a cross-reference to $454D that isn't part of
; this file) are reproduced byte-exact but not claimed to be fully
; understood.
; ---------------------------------------------------------------------------

        .setcpu "6502"

        .segment "HEADER1"
        .word   $FFFF           ; binary load file signature
        .word   Seg1Start       ; segment #1 start ($0500)
        .word   Seg1End-1       ; segment #1 end ($0547)

PORTB   = $D301                 ; PIA port B - bank/ROM select on XL/XE
NMIEN   = $D40E                 ; ANTIC NMI enable register
VVBLKD  = $0226                 ; OS deferred VBI vector (word)
CIOV    = $E456                 ; OS ROM: Central I/O Vector
StrPtr  = $00E9                 ; ($E9/$EA) return-address pointer used by
                                 ; PrintInline (in segment #3)

        .segment "SEG1"
        .org $0500
Seg1Start:
        sei
        inc     $42
        lda     PORTB
        sta     SavedPortB      ; ($0639 in segment #2)
        ldy     #$00
        sty     NMIEN
        lda     #$E0
        ldy     #$3C
        ldx     #$04
        jsr     BlockMove       ; copy $E000-$E3FF -> $3C00-$3FFF
        jsr     Seg2BankOn      ; ($0689 in segment #2)
        lda     #$3C
        ldy     #$E0
        ldx     #$04
        jsr     BlockMove       ; copy $3C00-$3FFF -> $E000-$E3FF (restore)
        lda     #$2A
        ldy     #$EA
        ldx     #$0E
        jsr     BlockMove       ; relocate $2A00-$37FF (14 pages) -> $EA00-$F7FF
        jmp     Seg2Start       ; ($0600 in segment #2)

; ---------------------------------------------------------------------------
; BlockMove: copy X 256-byte pages from (A*256) to (Y*256).
; ---------------------------------------------------------------------------
BlockMove:
        sta     $E1
        sty     $D1
        ldy     #$00
        sty     $E0
        sty     $D0
CopyPageLp:
        lda     ($E0),y
        sta     ($D0),y
        iny
        bne     CopyPageLp
        inc     $E1
        inc     $D1
        dex
        bne     CopyPageLp
        rts
Seg1End:

; ---------------------------------------------------------------------------
; Segment #2 ($0600-$06CE): PORTB on/off wrappers shared by segment #1 and
; segment #3, a self-modified "return to caller-supplied vector" trampoline,
; and a small filename/pattern buffer.
; ---------------------------------------------------------------------------
        .segment "HEADER2"
        .word   Seg2Start       ; segment #2 start ($0600)
        .word   Seg2End-1       ; segment #2 end ($06CE)

        .segment "SEG2"
        .org $0600
Seg2Start:
        lda     $0C
        sta     SavedPtrLo
        lda     $0D
        sta     SavedPtrHi      ; save caller's $0C/$0D pointer
        lda     #<Seg2InitPart2
        sta     $0C
        lda     #>Seg2InitPart2
        sta     $0D
        ldx     #$01
        stx     $09
        dex
        stx     $0244
        jmp     $ED6B           ; OS ROM (not part of this file)

Seg2BankOffCiov:
        jsr     Seg2BankOff
        jsr     $E453           ; OS ROM CIO-adjacent entry (not part of this file)
        jmp     Seg2BankOn

Seg2BankOffCiov2:
        jsr     Seg2BankOff
        jsr     CIOV
        jmp     Seg2BankOn

Seg2BankOffCiov3:
        jsr     Seg2BankOff
        jsr     $E459           ; OS ROM CIO-adjacent entry (not part of this file)
        jmp     Seg2BankOn

Seg2Entry2:
        lda     #$FF
        sta     PORTB
        lda     SavedPtrLo
        sta     $0C
        lda     SavedPtrHi
        sta     $0D
        ldx     #$00
        stx     $0736
        stx     $0737
        jsr     Seg2RetTramp
        jsr     Seg2BankOn
        jmp     Seg2Start

Seg2RetTramp:
        jmp     ($000A)         ; indirect jump through a caller-supplied vector

; ---------------------------------------------------------------------------
; Seg2Start2: self-modified "return to X" jump - the JMP operand below
; (initially a leftover/placeholder $1000) gets overwritten at runtime by
; whoever wants control transferred back to a saved address.
; ---------------------------------------------------------------------------
Seg2Start2:
        jmp     $1000           ; self-modified target (operand patched by callers)
Seg2InitPart2:
        lda     #$00
        sta     $F762
        sta     $F763
        lda     #$3C
        sta     $D303
        jsr     Seg2BankOff
        lda     #$FF
        sta     $08
        jsr     Seg2Start2
        sei
        inc     $42
        lda     #$00
        sta     NMIEN
        jsr     Seg2BankOn
        jmp     $ED6B           ; OS ROM (not part of this file)

Seg2BankOff:
        lda     #$FF
        sta     PORTB
        rts

Seg2BankOn:
        php
        lda     #$FE
        sta     PORTB
        plp
        rts

; ---------------------------------------------------------------------------
; Small static table / scratch bytes (purpose not fully identified), and a
; wildcard/filename buffer template used by the directory browser.
; ---------------------------------------------------------------------------
        .byte   $70, $70, $70, $42, $00, $22
        .byte   $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02
        .byte   $02, $02, $02, $02, $02, $02, $02
DirPattern:
        .byte   $41, $91, $06, $44, $38, $3A, $2A, $2E, $2A, $9B  ; "A".."D8:*.*"
DestPattern:
        .byte   $44, $31, $3A                                    ; "D1:"
        .res    20, $20                                          ; space-padded filename area
Seg2End:
SavedPtrLo = $065C
SavedPtrHi = $065D
SavedPortB = $0639

; ---------------------------------------------------------------------------
; Segment #3 ($2A00-$3763 on disk; runs relocated at $EA00-$F7FF).
; ---------------------------------------------------------------------------
        .segment "HEADER3"
        .word   $2A00           ; segment #3 start - load address (run
                                 ; address is $EA00; see Seg3Start below)
        .word   $3763           ; segment #3 end - load address

        .segment "SEG3"
        .org $EA00
Seg3Start:
LEA00:  cpy     $E8
        bcs     LEA0C
        lda     $E900,y
        bne     LEA0C
        iny
        bcc     LEA00
LEA0C:  rts

LEA0D:  lda     LEEF8
        and     #$0F
        cmp     $0722
        bne     LEA1F
        rts

LEA18:  and     #$0F
        cmp     $0722
        beq     LEA49
LEA1F:  sta     $0301
        lda     #$31
        sta     $0300
        lda     #$53
        sta     $0302
        jsr     Seg2BankOffCiov
        ldx     #$00
        stx     LEA86
        inx
        stx     LEA8B
        lda     $02EA
        and     #$20
        bne     LEA45
        lsr     LEA8B
        ror     LEA86
LEA45:  ldy     $0303
        rts

LEA49:  ora     #$30
        sta     $06B2
        ldx     #$10
        lda     #$FF
        sta     $0340,x
        lda     #$03
        sta     $0342,x
        lda     #$B1
        sta     $0344,x
        lda     #$06
        sta     $0345,x
        lda     #$06
        sta     $034A,x
        jsr     Seg2BankOffCiov2
        lda     #$FF
        sta     $0340,x
        tya
        rts

LEA73:  lda     $0301
        cmp     $0722
        beq     LEA9B
        lda     #$31
        sta     $0300
        lda     #$52
        sta     $0302
        .byte   $A9
LEA86:  .byte   $80
        sta     $0308
        .byte   $A9
LEA8B:  brk
        sta     $0309
        lda     #$40
        sta     $0303
        .byte   $20
LEA95:  .byte   $0C
LEA96:  .byte   $07
        ldy     $0303
        rts

LEA9B:  lda     $030A
        sta     $32
        lda     $030B
        sta     $33
        lda     #$00
        tay
        lsr     $33
        rol     a
        lsr     $33
        rol     a
        asl     $32
        rol     a
        asl     $32
        rol     a
        tax
        lda     LEAF4,x
        sta     $D301
        lda     $030A
        and     #$3F
        ora     #$40
        sta     $33
        sty     $32
LEAC6:  lda     ($32),y
        sta     $0400,y
        iny
        bne     LEAC6
        lda     #$FE
        sta     $D301
        lda     $0304
        sta     $32
        lda     $0305
        sta     $33
LEADD:  lda     $0400,y
        sta     ($32),y
        iny
        bne     LEADD
        sty     $0308
        iny
        sty     $0309
        lda     $11
        bmi     LEAF2
        ldy     #$80
LEAF2:  tya
        rts

LEAF4:  inc     $E6EA
        .byte   $E2
        ror     $666A
        .byte   $62
        ldx     $A6AA
        ldx     #$2E
        rol     a
        rol     $22
LEB04:  lda     #$03
        sta     $E6
LEB08:  lda     #$15
        sta     $E5
        ldx     #$12
LEB0E:  jsr     ScreenPokeSp
        dex
        bne     LEB0E
        jsr     LEB9B
        lda     $E6
        cmp     #$15
        bcc     LEB08
        rts

PrintInlineSetup:  jsr     LEB49
PrintInline:  pla
        sta     StrPtr
        pla
        sta     $EA
        ldx     #$00
LEB29:  inc     StrPtr
        bne     LEB2F
        inc     $EA
LEB2F:  lda     (StrPtr,x)
        cmp     #$EA
        beq     LEB3B
        jsr     ScreenPoke
        jmp     LEB29

LEB3B:  jmp     (StrPtr)

LEB3E:  ldx     #$26
        lda     #$12
LEB42:  jsr     ScreenPoke
        dex
        bne     LEB42
        rts

LEB49:  ldy     #$01
        sty     $E5
        lda     #$16
        sta     $E6
        lda     LEBC1
        sta     $E2
        lda     LEBD9
        sta     $E3
        lda     #$00
LEB5D:  sta     ($E2),y
        iny
        cpy     #$27
        bcc     LEB5D
        rts

ScreenPokeSp:  lda     #$20
ScreenPoke:  stx     $EC
        sty     $ED
        tax
        cmp     #$9B
        beq     LEB9B
        rol     a
        rol     a
        rol     a
        rol     a
        and     #$03
        tay
        txa
        and     #$9F
        ora     LEBA7,y
        sta     $E4
        ldy     $E6
        lda     LEBAB,y
        sta     $E2
        lda     LEBC3,y
        sta     $E3
        lda     $E4
        eor     $F3
        ldy     $E5
        sta     ($E2),y
        inc     $E5
        lda     $E5
        cmp     #$28
        bcc     LEBA1
LEB9B:  lda     $F4
        sta     $E5
        inc     $E6
LEBA1:  txa
        ldx     $EC
        ldy     $ED
        rts

LEBA7:  rti

        brk
        .byte   $20
        rts

LEBAB:  brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
LEBC1:  brk
        brk
LEBC3:  brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
        brk
LEBD9:  brk
        brk
LEBDB:  jsr     LEC0D
LEBDE:  lda     $02FC
        cmp     #$FF
        beq     LEBE9
        and     #$3F
        bne     LEBFA
LEBE9:  ldy     $D01F
        cpy     #$07
        bne     LEBFA
        beq     LEBDE
LEBF2:  ldy     #$20
LEBF4:  jsr     LEBFA
        dey
        bne     LEBF4
LEBFA:  ldx     #$4F
LEBFC:  stx     $D01F
        stx     $D40A
        dex
        bpl     LEBFC
        stx     $11
        ldx     #$08
        stx     $D01F
        rts

LEC0D:  ldx     #$30
LEC0F:  lda     #$08
        sta     $D01F
        lda     $D01F
        sta     $D40A
        cmp     #$07
        bne     LEC0D
        dex
        bne     LEC0F
        ldx     #$FF
        stx     $02FC
        rts

LEC27:  sta     $D6
        stx     $D7
        lda     #$00
        sta     $D8
        sta     $D9
        ldx     #$03
LEC33:  lda     $D6
        sec
        sbc     LEC66,x
        tay
        lda     $D7
        sbc     LEC6A,x
        bcc     LEC58
        sty     $D6
        sta     $D7
        clc
        lda     $D8
        clc
        adc     LEC62,x
        sta     $D8
        lda     $D9
        adc     LEC60,x
        sta     $D9
        jmp     LEC33

LEC58:  dex
        bpl     LEC33
        lda     $D8
        ldx     $D9
        rts

LEC60:  ora     ($10,x)
LEC62:  brk
        brk
        ora     ($10,x)
LEC66:  ora     ($0A,x)
        .byte   $64
        inx
LEC6A:  brk
        brk
        brk
        .byte   $03
LEC6E:  jsr     LEC72
        txa
LEC72:  tay
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     LEC7D
        tya
        and     #$0F
LEC7D:  ora     #$30
        jmp     ScreenPoke

LEC82:  lda     #$00
        sta     $E7
        sta     $E1
        ldx     $F0
        stx     $EB
        cpx     #$12
        bcc     LEC99
        txa
        sbc     #$11
        tax
        lda     #$11
        sta     $EB
        txa
LEC99:  sta     $F1
        asl     a
        asl     a
        asl     a
        rol     $E1
        asl     a
        rol     $E1
        adc     #$00
        sta     $E0
        lda     $E1
        adc     #$E5
        sta     $E1
LECAD:  lda     #$01
        sta     $E5
        lda     $E7
        tay
        clc
        adc     #$03
        sta     $E6
        lda     #$20
        cpy     $EB
        bne     LECD4
        lda     $E0
        sta     $D4
        lda     $E1
        sta     $D5
        lda     $F2
        beq     LECD4
        jsr     PrintInline
        .byte   $3D, $3D, $3E, $EA
        beq     LECDD
LECD4:  jsr     ScreenPokeSp
        jsr     ScreenPokeSp
        jsr     ScreenPokeSp
LECDD:  tya
        clc
        adc     $F1
        tax
        lda     $E900,x
        sta     $F3
        ldy     #$04
LECE9:  lda     ($E0),y
        jsr     ScreenPoke
        iny
        cpy     #$0F
        bcc     LECE9
        jsr     ScreenPokeSp
        ldy     #$01
        lda     ($E0),y
        tax
        dey
        lda     ($E0),y
        jsr     LEC6E
        lda     #$00
        sta     $F3
        lda     #$10
        clc
        adc     $E0
        sta     $E0
        bcc     LED10
        inc     $E1
LED10:  inc     $E7
        lda     $E7
        cmp     #$12
        bcs     LED1E
        adc     $F1
        cmp     $E8
        bcc     LECAD
LED1E:  rts

LED1F:  ldx     #$00
        ldy     #$04
LED23:  lda     ($D4),y
        cmp     #$20
        beq     LED31
        jsr     LED48
        iny
        cpy     #$0C
        bcc     LED23
LED31:  lda     #$2E
        jsr     LED48
        ldy     #$0C
LED38:  lda     ($D4),y
        cmp     #$20
        beq     LED46
        jsr     LED48
        iny
        cpy     #$0F
        bcc     LED38
LED46:  lda     #$9B
LED48:  sta     $06BB,x
        inx
        rts

LED4D:  brk
LED4E:  lsr     $204F
        .byte   $44
        .byte   $42
        jmp     $454D

        .byte   $44
        .byte   $53
        lsr     $4347
        .byte   $4C
LED5C:  .byte   $52
        ora     ($02,x)
        brk
        .byte   $80
LED61:  ldx     #$10
        lda     #$0C
        sta     $0342,x
        jmp     Seg2BankOffCiov2

        lda     #$80
        sta     $FFFE
        lda     #$F6
        sta     $FFFF
        lda     #$92
        sta     $FFFA
        lda     #$F6
        sta     $FFFB
        lda     #$00
        sta     LF74B
        sta     $42
        lda     #$40
        sta     $D40E
        lda     #$C0
        sta     $10
        sta     $D20E
        cli
        lda     #$4C
        sta     $E459
        sta     $E45C
        ldx     #$59
        ldy     #$E4
        cmp     $070C
        beq     LEDAA
        stx     LEA95
        sty     LEA96
LEDAA:  lda     #$2F
        sta     $E45A
        lda     #$06
        sta     $E45B
        lda     #$4E
        sta     $E45D
        lda     #$F7
        sta     $E45E
        lda     #$A2
        sta     $02C8
        lda     #$00
        sta     $02C6
        lda     #$0A
        sta     $02C5
        ldy     #$00
        lda     #$40
        sty     $DE
        sta     $DF
LEDD5:  lda     ($DE),y
        eor     #$FF
        sta     ($DE),y
        cmp     ($DE),y
        bne     LEDEE
        eor     #$FF
        sta     ($DE),y
        lda     $DF
        clc
        adc     #$04
        sta     $DF
        cmp     #$C0
        bcc     LEDD5
LEDEE:  lda     #$00
        ldx     #$22
LEDF2:  sta     LEBAB,y
        clc
        adc     #$28
        pha
        txa
        sta     LEBC3,y
        adc     #$00
        tax
        pla
        iny
        cpy     #$18
        bcc     LEDF2
        lda     #$31
        sta     LEEF8
        sta     LEF02
LEE0E:  ldx     #$FF
        txs
        inx
        stx     $E5
        stx     $E6
        stx     $F3
        stx     $F4
        stx     LED4D
        lda     #$A2
        sta     $02C8
        ldx     #$C0
        ldy     #$03
LEE26:  jsr     ScreenPokeSp
        dex
        bne     LEE26
        dey
        bpl     LEE26
        lda     #$91
        sta     $0230
        lda     #$06
        sta     $0231
        stx     $E6
        lda     #$11
        jsr     ScreenPoke
        jsr     LEB3E
        jsr     PrintInline
        .byte   $05, $7C, $99, $CD, $F5, $EC, $F4, $E9, $A0, $C6, $E9, $EC, $E5, $E3, $EF, $F0
        .byte   $F9, $A0, $C9, $C9, $A0, $A0, $A8, $E3, $A9, $A0, $B1, $B9, $B8, $B8, $A0, $C2
        .byte   $C9, $C2, $CF, $D3, $CF, $C6, $D4, $19, $7C, $01, $EA
        jsr     LEB3E
        lda     #$04
        jsr     ScreenPoke
        ldx     #$14
        stx     $E5
        dec     $E6
        lda     #$17
        jsr     ScreenPoke
        jsr     LEB9B
        lda     #$7C
LEE89:  jsr     ScreenPoke
        ldx     #$14
        stx     $E5
        jsr     ScreenPoke
        ldx     #$27
        stx     $E5
        jsr     ScreenPoke
        ldy     $E6
        cpy     #$15
        bcc     LEE89
        lda     #$01
        jsr     ScreenPoke
        jsr     LEB3E
        lda     #$04
        jsr     ScreenPoke
        ldx     #$14
        stx     $E5
        dec     $E6
        lda     #$18
        jsr     ScreenPoke
        jsr     LEB9B
        lda     #$7C
        jsr     ScreenPoke
        ldx     #$27
        stx     $E5
        jsr     ScreenPoke
        lda     #$1A
        jsr     ScreenPoke
        jsr     LEB3E
        lda     #$03
        jsr     ScreenPoke
        lda     $070C
        cmp     #$4C
        beq     LEEDF
        lda     #$02
        bne     LEEE2
LEEDF:  lda     $0722
LEEE2:  ora     #$30
        sta     $EF
LEEE6:  jsr     LEB04
LEEE9:  lda     #$15
        sta     $F4
        sta     $E5
        lda     #$04
        sta     $E6
        jsr     PrintInline
        .byte   $20, $44
LEEF8:
        .byte   $31, $3A, $2A, $2E, $2A, $20, $2D, $3E, $20, $44
LEF02:
        .byte   $31, $3A, $2A, $2E, $2A, $9B, $9B, $99, $CF, $D0, $D4, $C9, $CF, $CE, $A0, $BA
        .byte   $19, $9B, $20, $53, $6F, $75, $72, $63, $65, $5F, $5F, $5F, $5F, $5F, $5F, $44
        .byte   $69, $73, $6B, $9B, $9B, $99, $D3, $C5, $CC, $C5, $C3, $D4, $A0, $BA, $19, $9B
        .byte   $20, $44, $65, $73, $74, $69, $6E, $61, $74, $69, $6F, $6E, $5F, $44, $69, $73
        .byte   $6B, $9B, $9B, $99, $D3, $D4, $C1, $D2, $D4, $A0, $A0, $BA, $19, $9B, $20, $20
        .byte   $44, $69, $72, $65, $63, $74, $6F, $72, $79, $9B, $9B, $20, $C6, $6F, $72, $6D
        .byte   $61, $74, $20, $3A, $20, $20, $20, $EA
        lda     LED4D
        asl     a
        adc     LED4D
        tax
        ldy     #$03
LEF74:  lda     LED4E,x
        jsr     ScreenPoke
        inx
        dey
        bne     LEF74
        jsr     PrintInline
        .byte   $9B, $20, $20, $44, $65, $73, $74, $69, $6E, $61, $74, $69, $6F, $6E, $9B, $9B
        .byte   $9B, $20, $20, $99, $C5, $D3, $C3, $19, $20, $3D, $20, $45, $78, $69, $74, $EA
LEFA1:  jsr     LEBDB
        cmp     #$1C
        bne     LEFAE
        jsr     LEC0D
        jmp     Seg2Entry2

LEFAE:  cmp     #$38
        bne     LEFC4
        inc     LED4D
        lda     LED4D
        cmp     #$05
        bcc     LEFC1
        lda     #$00
        sta     LED4D
LEFC1:  jmp     LEEE9

LEFC4:  cpy     #$07
        beq     LEFA1
        cpy     #$05
        beq     LEFDC
        cpy     #$06
        beq     LEFFB
        ldx     LEEF8
        jsr     LEFE8
        stx     LEEF8
        jmp     LEEE9

LEFDC:  ldx     LEF02
        jsr     LEFE8
        stx     LEF02
        jmp     LEEE9

LEFE8:  cpx     $EF
        bcc     LEFEE
LEFEC:  ldx     #$30
LEFEE:  cpx     #$32
        bne     LEFF9
        ldx     $EF
        cpx     #$39
        bcs     LEFEC
        rts

LEFF9:  inx
        rts

LEFFB:  jsr     LEB04
        lda     #$00
        sta     $E8
        lda     LEF02
        jsr     LEA18
        bmi     LF04E
        lda     LEEF8
        jsr     LEA18
        bmi     LF04E
        lda     #$00
        sta     $E0
        lda     #$E5
        sta     $E1
        ldx     #$69
        ldy     #$01
        lda     $0301
        cmp     $0722
        bne     LF02A
        ldx     #$02
        ldy     #$00
LF02A:  stx     $030A
        sty     $030B
        lda     #$08
        sta     $EB
        sta     $41
LF036:  lda     #$00
        tax
LF039:  sta     $0400,x
        inx
        bpl     LF039
        lda     #$00
        sta     $0304
        lda     #$04
        sta     $0305
        jsr     LEA73
        bpl     LF058
LF04E:  jsr     LEBF2
        lda     $E8
        bne     LF0AF
        jmp     LEEE6

LF058:  lda     #$00
        sta     $E7
LF05C:  ldx     $E7
        lda     $0400,x
        beq     LF0AF
        bmi     LF09A
        cmp     #$43
        beq     LF09A
        ldy     #$00
LF06B:  inx
        lda     $0400,x
        sta     ($E0),y
        iny
        cpy     #$0F
        bcc     LF06B
        lda     #$00
        sta     ($E0),y
        ldy     #$01
        lda     ($E0),y
        tax
        dey
        lda     ($E0),y
        jsr     LEC27
        ldy     #$00
        sta     ($E0),y
        txa
        iny
        sta     ($E0),y
        inc     $E8
        lda     $E0
        clc
        adc     #$10
        sta     $E0
        bcc     LF09A
        inc     $E1
LF09A:  lda     $E7
        clc
        adc     #$10
        sta     $E7
        bpl     LF05C
        lda     $0303
        bmi     LF0AF
        inc     $030A
        dec     $EB
        bne     LF036
LF0AF:  ldx     #$68
        lda     $0301
        cmp     $0722
        bne     LF0BB
        ldx     #$01
LF0BB:  stx     $030A
        jsr     LEA73
        bmi     LF116
        lda     $030B
        beq     LF0F4
        lda     $0402
        cmp     #$03
        bcc     LF0F4
        lda     #$00
        sta     $030A
        lda     #$04
        sta     $030B
        inc     $0305
        jsr     LEA73
        bmi     LF0F4
        lda     $057A
        clc
        adc     $0403
        sta     $0403
        lda     $057B
        adc     $0404
        sta     $0404
LF0F4:  jsr     PrintInlineSetup
        .byte   $20, $EA
        lda     $0403
        ldx     $0404
        jsr     LEC27
        jsr     LEC6E
        jsr     PrintInline
        .byte   $20, $46, $72, $65, $65, $20, $53, $65, $63, $74, $6F, $72, $73, $EA
LF116:  lda     $E8
        bne     LF121
        lda     #$13
        sta     $E5
        jmp     LF510

LF121:  lda     #$03
        sta     $E6
        jsr     PrintInline
        .byte   $9B, $20, $4B, $65, $79, $27, $73, $20, $74, $6F, $20, $75, $73, $65, $20, $3A
        .byte   $9B, $9B, $20, $99, $9C, $19, $5F, $5F, $5F, $55, $70, $9B, $9B, $20, $99, $9D
        .byte   $19, $5F, $5F, $5F, $44, $6F, $77, $6E, $9B, $9B, $99, $D3, $D0, $C1, $C3, $C5
        .byte   $19, $2B, $99, $D2, $C5, $D4, $D5, $D2, $CE, $19, $9B, $20, $20, $20, $20, $20
        .byte   $20, $20, $74, $6F, $9B, $20, $53, $65, $6C, $65, $63, $74, $2F, $44, $65, $73
        .byte   $65, $6C, $65, $63, $74, $9B, $9B, $20, $99, $C1, $19, $5F, $5F, $53, $65, $6C
        .byte   $65, $63, $74, $20, $41, $6C, $6C, $9B, $9B, $9B, $99, $D3, $D4, $C1, $D2, $D4
        .byte   $19, $5F, $5F, $5F, $43, $6F, $70, $79, $9B, $9B, $99, $CF, $D0, $D4, $C9, $CF
        .byte   $CE, $19, $5F, $5F, $52, $65, $73, $74, $61, $72, $74, $EA
        lda     #$00
        ldx     #$3F
LF1B8:  sta     $E900,x
        dex
        bpl     LF1B8
        sta     $F0
LF1C0:  lda     #$3F
        sta     $F2
        jsr     LEC82
        jsr     LEBDB
        cpy     #$03
        bne     LF1D1
        jmp     LEE0E

LF1D1:  cpy     #$06
        beq     LF21A
        tay
        cpy     #$21
        beq     LF1DE
        cpy     #$0C
        bne     LF1EC
LF1DE:  ldx     $F0
        lda     $E900,x
        eor     #$80
        sta     $E900,x
        cpy     #$0C
        beq     LF200
LF1EC:  cpy     #$0F
        beq     LF200
        cpy     #$3F
        beq     LF20B
        cpy     #$0E
        bne     LF1C0
        lda     $F0
        beq     LF1C0
        dec     $F0
        bpl     LF1C0
LF200:  ldx     $F0
        inx
        cpx     $E8
        bcs     LF1C0
        stx     $F0
        bcc     LF1C0
LF20B:  lda     $E900
        eor     #$80
        ldx     $E8
LF212:  sta     $E8FF,x
        dex
        bne     LF212
        beq     LF1C0
LF21A:  ldy     #$00
        jsr     LEA00
        bcs     LF1C0
        sty     $F0
        jsr     LEC0D
        jsr     LEB04
        lda     #$08
        sta     $E6
        jsr     PrintInline
        .byte   $9B, $20, $20, $50, $72, $65, $73, $73, $20, $99, $C2, $D2, $C5, $C1, $CB, $19
        .byte   $9B, $9B, $20, $20, $20, $20, $20, $20, $20, $74, $6F, $9B, $9B, $20, $20, $20
        .byte   $41, $62, $6F, $72, $74, $20, $43, $6F, $70, $79, $2E, $EA
        sta     $0301
LF25F:  lda     #$C0
        sta     $D0
        lda     #$25
        sta     $D1
        lda     $F0
        sta     LF36D
        lda     #$00
        sta     $D9
        lda     #$64
        sta     $02C8
        lda     LEEF8
        sta     $06B9
        sta     LF2A8
        and     #$0F
        cmp     $0301
        sta     $0301
        bne     LF2B2
        jsr     PrintInlineSetup
        .byte   $20, $49, $6E, $73, $65, $72, $74, $20, $53, $6F, $75, $72, $63, $65, $2D, $44
        .byte   $69, $73, $6B, $20, $69, $6E, $20, $44, $72, $69, $76, $65, $20
LF2A8:
        .byte   $31, $20, $A0, $EA
        jsr     LEBDB
        jsr     LEA0D
LF2B2:  jsr     LEC82
        jsr     LED1F
        ldy     #$0F
        lda     ($D4),y
        bmi     LF2CB
        ldy     #$02
        lda     ($D4),y
        sta     $030A
        iny
        lda     ($D4),y
        sta     $030B
LF2CB:  ldx     $D9
        lda     $D0
        sta     $E940,x
        lda     $D1
        sta     $E981,x
        lda     $DE
        sec
        sbc     $D0
        sta     $D2
        lda     $DF
        sbc     $D1
        sta     $D3
        bcc     LF2E8
        bne     LF2EB
LF2E8:  jmp     LF371

LF2EB:  jsr     LF5C9
LF2EE:  lda     $D2
        cmp     $0308
        lda     $D3
        sbc     $0309
        bcc     LF371
        lda     $D0
        sta     $0304
        lda     $D1
        sta     $0305
LF304:  jsr     LEA73
        bpl     LF30C
        jmp     LF52C

LF30C:  ldy     $0308
        dey
        lda     ($D0),y
        sta     $EB
        dey
        lda     ($D0),y
        sta     $030A
        dey
        lda     ($D0),y
        and     #$03
        sta     $030B
        lda     $D0
        clc
        adc     $EB
        sta     $D0
        bcc     LF32D
        inc     $D1
LF32D:  lda     $D2
        sec
        sbc     $EB
        sta     $D2
        lda     $D3
        sbc     #$00
        sta     $D3
        lda     $030A
        ora     $030B
        bne     LF2EE
LF342:  ldy     #$0F
        lda     #$01
        sta     ($D4),y
        lda     $D2
        cmp     $0308
        lda     $D3
        sbc     $0309
        bcc     LF377
LF354:  ldy     $F0
        iny
        jsr     LEA00
        bcc     LF366
        lda     #$00
        sta     $F2
        jsr     LEC82
        jmp     LF377

LF366:  sty     $F0
        inc     $D9
        jmp     LF2B2

LF36D:  brk
LF36E:  brk
LF36F:  brk
LF370:  brk
LF371:  ldy     #$0F
        lda     #$80
        sta     ($D4),y
LF377:  lda     $030A
        sta     LF36F
        lda     $030B
        sta     LF370
        ldx     $D9
        inx
        lda     $D0
        sta     $E940,x
        lda     $D1
        sta     $E981,x
        lda     #$28
        sta     $02C8
        lda     $F0
        sta     LF36E
        lda     LF36D
        sta     $F0
        lda     LEF02
        sta     LF3D2
        sta     $06B9
        cmp     LEEF8
        bne     LF3D9
        jsr     PrintInlineSetup
        .byte   $20, $49, $6E, $73, $65, $72, $74, $20, $44, $65, $73, $74, $69, $6E, $61, $74
        .byte   $69, $6F, $6E, $20, $44, $69, $73, $6B, $20, $69, $6E, $20, $44, $72, $69, $76
        .byte   $65, $20
LF3D2:
        .byte   $38, $20, $A0, $EA
        jsr     LEBDB
LF3D9:  ldx     LED4D
        beq     LF440
        jsr     LF607
        ldx     LED4D
        lda     LED5C,x
        ldx     #$10
        sta     $034B,x
        lda     #$FF
        sta     $0340,x
        lda     #$FE
        sta     $0342,x
        lda     #$B8
        sta     $0344,x
        lda     #$06
        sta     $0345,x
        jsr     Seg2BankOffCiov2
        bpl     LF43D
        jsr     LEBF2
        jsr     PrintInlineSetup
        .byte   $20, $99, $C6, $EF, $F2, $ED, $E1, $F4, $A0, $C5, $F2, $F2, $EF, $F2, $A0, $BA
        .byte   $19, $20, $20, $D2, $65, $74, $72, $79, $20, $6F, $72, $20, $C1, $62, $6F, $72
        .byte   $74, $20, $A0, $EA
LF42F:  jsr     LEBDB
        cmp     #$28
        beq     LF3D9
        cmp     #$3F
        bne     LF42F
        jmp     LEE0E

LF43D:  jsr     LED61
LF440:  jsr     LF5E4
        sta     $F2
        lda     #$00
        sta     LED4D
        sta     $D9
LF44C:  jsr     LEC82
        jsr     LED1F
        jsr     LF626
        ldx     #$10
        lda     $0340,x
        cmp     #$FF
        bne     LF477
        lda     #$03
        sta     $0342,x
        lda     #$B8
        sta     $0344,x
        lda     #$06
        sta     $0345,x
        lda     #$08
        sta     $034A,x
        jsr     Seg2BankOffCiov2
        bmi     LF4CF
LF477:  lda     #$0B
        sta     $0342,x
        ldy     $D9
        lda     $E940,y
        sta     $0344,x
        lda     $E981,y
        sta     $0345,x
        lda     $E941,y
        sec
        sbc     $0344,x
        sta     $0348,x
        lda     $E982,y
        sbc     $0345,x
        sta     $0349,x
        jsr     Seg2BankOffCiov2
        bmi     LF4CF
        ldy     #$0F
        lda     ($D4),y
        bmi     LF4C0
        jsr     LED61
        ldy     $F0
        iny
        jsr     LEA00
        bcs     LF4F0
        lda     $F0
        sty     $F0
        cmp     LF36E
        bcs     LF4CC
        inc     $D9
        bcc     LF44C
LF4C0:  lda     LF36F
        sta     $030A
        lda     LF370
        sta     $030B
LF4CC:  jmp     LF25F

LF4CF:  jsr     LED61
        jsr     LEB04
        jsr     LEBF2
        jsr     PrintInlineSetup
        .byte   $20, $20, $20, $20, $57, $72, $69, $74, $65, $20, $45, $72, $72, $6F, $72, $20
        .byte   $20, $20, $EA
        beq     LF510
LF4F0:  lda     #$00
        sta     $F2
        jsr     LEC82
        jsr     LEB04
        jsr     PrintInlineSetup
        .byte   $20, $20, $20, $43, $6F, $70, $79, $20, $43, $6F, $6D, $70, $6C, $65, $74, $65
        .byte   $2E, $20, $EA
LF510:  jsr     PrintInline
        .byte   $20, $20, $20, $50, $72, $65, $73, $73, $20, $61, $6E, $79, $20, $4B, $65, $79
        .byte   $20, $A0, $EA
        jsr     LEBDB
        jmp     LEE0E

LF52C:  lda     #$3C
        sta     $D303
        jsr     LEBF2
        jsr     PrintInlineSetup
        .byte   $20, $D2, $E5, $E1, $E4, $A0, $C5, $F2, $F2, $EF, $F2, $3A, $20, $20, $D2, $65
        .byte   $74, $72, $79, $2C, $20, $C3, $6F, $6E, $74, $20, $6F, $72, $20, $C1, $62, $6F
        .byte   $72, $74, $20, $A0, $EA
LF55C:  jsr     LEBDB
        pha
        jsr     LEA0D
        pla
        cmp     #$28
        beq     LF572
        cmp     #$12
        beq     LF578
        cmp     #$3F
        beq     LF5B0
        bne     LF55C
LF572:  jsr     LF5C9
        jmp     LF304

LF578:  ldx     $D9
        lda     $E940,x
        sta     $D0
        lda     $E981,x
        sta     $D1
        lda     $DE
        sec
        sbc     $D0
        sta     $D2
        lda     $DF
        sbc     $D1
        sta     $D3
        ldy     #$0F
        lda     ($D4),y
        bmi     LF5AD
        dec     $D9
        ldy     $F0
        lda     #$00
        sta     $E900,y
        tya
        bne     LF5AA
        iny
        jsr     LEA00
        sty     LF36D
LF5AA:  jmp     LF354

LF5AD:  jmp     LF342

LF5B0:  jsr     PrintInlineSetup
        .byte   $20, $20, $20, $43, $6F, $70, $79, $20, $41, $62, $6F, $72, $74, $65, $64, $2E
        .byte   $20, $20, $EA
        jmp     LF510

LF5C9:  jsr     PrintInlineSetup
        .byte   $20, $52, $65, $61, $64, $69, $6E, $67, $20, $53, $6F, $75, $72, $63, $65, $2D
        .byte   $44, $69, $73, $6B, $20, $A0, $EA
        rts

LF5E4:  jsr     PrintInlineSetup
        .byte   $20, $57, $72, $69, $74, $69, $6E, $67, $20, $6F, $6E, $20, $44, $65, $73, $74
        .byte   $69, $6E, $61, $74, $69, $6F, $6E, $2D, $44, $69, $73, $6B, $20, $A0, $EA
        rts

LF607:  jsr     PrintInlineSetup
        .byte   $20, $46, $6F, $72, $6D, $61, $74, $20, $44, $65, $73, $74, $69, $6E, $61, $74
        .byte   $69, $6F, $6E, $2D, $44, $69, $73, $6B, $20, $A0, $EA
        rts

LF626:  lda     LEF02
        and     #$0F
        cmp     $0722
        beq     LF67F
        ldx     #$08
        stx     $02EA
        jsr     LEA1F
        lda     $02EA
        and     #$08
        beq     LF67F
        jsr     LEBF2
        jsr     PrintInlineSetup
        .byte   $57, $72, $69, $74, $65, $2D, $50, $72, $6F, $74, $65, $63, $74, $65, $64, $20
        .byte   $44, $69, $73, $6B, $2E, $20, $D2, $65, $74, $72, $79, $20, $6F, $72, $20, $C1
        .byte   $62, $6F, $72, $74, $20, $A0, $EA
LF66C:  jsr     LEBDB
        cmp     #$3F
        beq     LF67C
        cmp     #$28
        bne     LF66C
        jsr     LF5E4
        beq     LF626
LF67C:  jmp     LF5B0

LF67F:  rts

        pha
        bit     $D20E
        bvs     LF686
LF686:  lda     #$00
        sta     $D20E
        lda     $10
        sta     $D20E
        pla
        rti

        pha
        lda     $D40F
        sta     $D40F
        and     #$20
        beq     LF6A0
        jmp     Seg2InitPart2

LF6A0:  lda     LF762
        bne     LF6AD
        lda     LF763
        beq     LF6BA
        dec     LF763
LF6AD:  dec     LF762
        bne     LF6BA
        lda     LF763
        bne     LF6BA
        jmp     (VVBLKD)

LF6BA:  lda     $42
        beq     LF6C0
        pla
        rti

LF6C0:  lda     #$08
        sta     $D01F
        lda     $02C5
        sta     $D017
        lda     $02C6
        sta     $D018
        lda     $02C8
        sta     $D01A
        lda     $0230
        sta     $D402
        lda     $0231
        sta     $D403
        lda     $D20F
        and     #$04
        bne     LF72B
        lda     $D209
        cmp     LF74C
        beq     LF6FC
        sta     LF74C
        lda     #$09
        sta     LF74A
        bne     LF719
LF6FC:  lda     LF74A
        beq     LF70F
        cmp     #$0A
        bne     LF70A
        dec     LF74A
        bne     LF719
LF70A:  dec     LF74A
        bpl     LF730
LF70F:  lda     LF749
        beq     LF719
        dec     LF749
        bpl     LF730
LF719:  lda     $D209
        sta     LF74D
        inc     LF74B
        lda     #$02
        sta     LF749
        sta     $4D
        bne     LF730
LF72B:  lda     #$0A
        sta     LF74A
LF730:  lda     $02FC
        eor     #$FF
        bne     LF742
        lda     LF74B
        beq     LF742
        lda     LF74D
        sta     $02FC
LF742:  lda     #$00
        sta     LF74B
        pla
        rti

LF749:  brk
LF74A:  brk
LF74B:  brk
LF74C:  brk
LF74D:  brk
        cmp     #$01
        bne     LF761
        lda     $0302
        cmp     #$23
        bcs     LF75B
        ldx     #$0B
LF75B:  stx     LF763
        sty     LF762
LF761:  rts

LF762:  brk
LF763:  brk
Seg3End:

; ---------------------------------------------------------------------------
; Atari DOS "binary load" RUNAD framing: run address = $0500 (segment #1).
; ---------------------------------------------------------------------------
        .segment "RUNAD"
        .word   $02E0
        .word   $02E1
        .word   Seg1Start
