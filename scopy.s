; ---------------------------------------------------------------------------
; SCOPY.COM - "Sektor Kopierer" (Sector Copier)
; Reverse engineered from a 3240-byte Atari DOS binary load file.
;
; Layout on disk (Atari DOS "binary load" format), no repeated FF FF
; signature between segments:
;   FF FF              - binary load file signature
;   00 2F A3 2F        - segment #1: start=$2F00, end=$2FA3 (164 bytes)
;   00 34 E9 3F        - segment #2: start=$3400, end=$3FE9 (3050 bytes)
;   FA 3F FF 3F        - segment #3: start=$3FFA, end=$3FFF (6 bytes)
;   E0 02 E1 02 00 2F  - RUNAD segment: run address = $2F00
;
; Architecture: same relocate-into-OS-ROM-shadow-RAM trick as RDTEST2.COM/
; MFCOPY.COM, but relocating to the very top of the address space instead
; of $EA00-$F7FF:
;   - Segment #1 ($2F00, the RUNAD entry point) copies $E000-$E3FF (4
;     pages) to a scratch buffer at $3000, flips PORTB ($D301) bits 0-1
;     to (old & $FE) | $02, then copies 16 pages starting at $3000 (the
;     saved $E000-$E3FF plus, from $3400 on, segment #2's own on-disk
;     bytes) up to $F000-$FFFF. It then copies a small (0x47-byte) stub
;     out of its own tail into page 1 ($0100, the stack page - ordinary
;     RAM regardless of PORTB state) and jumps there.
;   - The $0100 stub resets NMIEN/POKEY/GTIA/ANTIC hardware registers,
;     sets PORTB to (old & $FE) | $FC (a different bank), and jumps into
;     the relocated segment #2 at $F4ED.
;   - Segment #2 is disassembled here at its *run* address, $F400 (not
;     its on-disk load address $3400), using a ca65/ld65 load/run segment
;     split like MFCOPY.COM's.
;   - Segment #3 (6 bytes at $3FFA-$3FFF, just below the $4000 boundary)
;     is reproduced byte-exact; its purpose was not identified.
;
; Same inline-string-printing trick as the other files: "jsr PrintInline"
; ($FC41 once relocated) pulls the return address off the stack, copies
; bytes from there into a buffer at $FEAA (rather than printing them
; directly - this program builds a message before displaying it) until an
; $EA (NOP) sentinel, then resumes execution right after it. All 13 such
; strings are reproduced verbatim below, immediately after the call.
;
; $F400-$F4EC (before the entry point at $F4ED) is a data area: a handful
; of small address/pointer tables, the identifying string "sectorcopy",
; a "QNU" marker, and a German options/menu word table ("einstellen"=set,
; "formatieren"=format, "original diskette", "ziel diskette", "disketten
; einlegen"=insert disks, "disk fehler"=disk error, "sector") using $80 as
; a field separator - reproduced byte-exact; not further decoded since it
; isn't accessed through the inline-string convention above.
;
; A byte-identical rebuild was verified with ca65/ld65 and cmp against the
; original SCOPY.COM. A few PORTB bit-pattern effects, the $0100 stub's
; internal layout, and two external references ($0810, $4448, not part of
; this file) are reproduced byte-exact but not claimed to be fully
; understood.
; ---------------------------------------------------------------------------

        .setcpu "6502"

        .segment "HEADER1"
        .word   $FFFF           ; binary load file signature
        .word   Seg1Start       ; segment #1 start ($2F00)
        .word   Seg1End-1       ; segment #1 end ($2FA3)

PORTB   = $D301                 ; PIA port B - bank/ROM select on XL/XE
NMIEN   = $D40E                 ; ANTIC NMI enable register
VVBLKD  = $0226                 ; OS deferred VBI vector (word)
StrPtr  = $0043                 ; ($43/$44) return-address pointer used by
                                ; PrintInline (in segment #2)

        .segment "SEG1"
        .org $2F00
Seg1Start:
        sei
        lda     #$00
        tay
        sty     NMIEN
        sta     $F0
        sta     $F2
        lda     #$E0
        sta     $F1
        lda     #$30
        sta     $F3
SavePageLp:
        lda     ($F0),y
        sta     ($F2),y
        iny
        bne     SavePageLp
        inc     $F3
        inc     $F1
        lda     $F1
        cmp     #$E4
        bne     SavePageLp      ; saved $E000-$E3FF -> $3000-$33FF

        lda     PORTB
        and     #$FE
        ora     #$02
        sta     PORTB
        lda     #$F0
        sta     $F1
        lda     #$30
        sta     $F3
RelocateLp:
        lda     ($F2),y
        sta     ($F0),y
        iny
        bne     RelocateLp
        inc     $F3
        inc     $F1
        lda     $F1
        bne     RelocateLp      ; relocate $3000-$3FFF (16 pages) -> $F000-$FFFF

        ldy     #$46
CopyStubLp:
        lda     Stub,y
        sta     $0100,y
        dey
        bpl     CopyStubLp      ; copy the stub below into page 1 ($0100-$0146)
        iny
        sty     $0244
        sty     $0C
        iny
        sty     $09
        sty     $0D
        jmp     $0100

; ---------------------------------------------------------------------------
; Stub: copied to $0100 (ordinary RAM, unaffected by the PORTB switch
; below) so it keeps running no matter which bank is currently mapped in.
; Resets NMIEN/POKEY/GTIA/ANTIC, switches PORTB again, then jumps into the
; relocated segment #2.
; ---------------------------------------------------------------------------
Stub:
        sei
        lda     #$00
        tay
ClearChipsLp:
        sta     $D400,y
        sta     $D000,y
        sta     $D200,y
        iny
        bne     ClearChipsLp
        lda     PORTB
        and     #$FE
        ora     #$FC
        sta     PORTB
        lda     #$3C
        sta     $D303           ; PBCTL
        lda     #$F0
        sta     $D409
        lda     #$02
        sta     $D401
        lda     #$22
        sta     $D400           ; DMACTL
        lda     #$03
        sta     $D20F           ; SKCTL
        lda     #$40
        sta     NMIEN
        jsr     $FE03           ; OS ROM (not part of this file)
        jmp     $F4ED           ; enter the relocated segment #2

; ---------------------------------------------------------------------------
; Unused leftover (not reached from the stub above; kept for byte-exact
; reproduction - the same pattern seen in the other files' unused vector
; RTS-jump leftovers).
; ---------------------------------------------------------------------------
        lda     #$FF
        sta     PORTB
        jmp     $E477           ; OS ROM (not part of this file)
Seg1End:

; ---------------------------------------------------------------------------
; Segment #2 ($3400-$3FE9 on disk; runs relocated at $F400-$FFE9).
; ---------------------------------------------------------------------------
        .segment "HEADER2"
        .word   $3400           ; segment #2 start - load address (run
                                 ; address is $F400; see Seg2Start below)
        .word   $3FE9           ; segment #2 end - load address

        .segment "SEG2"
        .org $F400
Seg2Start:
; Data area ($F400-$F4EC): small address/pointer tables, the identifying
; string "sectorcopy", a "QNU" marker, and a German options/menu word
; table (see file header comment) using $80 as a field separator.
        .byte   $70, $70, $70, $46, $58, $F4, $47, $30, $F4, $40, $06, $10, $46, $58, $F4, $70
        .byte   $42, $AA, $FE, $30, $02, $30, $70, $02, $70, $50, $02, $70, $20, $02, $70, $20
        .byte   $02, $70, $20, $46, $58, $F4, $46
LF427:  .byte   $6C
LF428:  .byte   $F4, $10, $46, $58, $F4, $41, $00, $F4, $00, $00, $00, $73, $65, $63, $74, $6F
        .byte   $72, $63, $6F, $70, $79, $00, $51, $4E, $55, $00, $00, $00, $80, $C8, $E3, $C9
        .byte   $80, $D0, $D7, $CF, $D8, $D8, $80, $E2, $E9, $E2, $EF, $F3, $EF, $E6, $F4, $80
        .byte   $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D
        .byte   $0D, $0D, $0D, $0D, $80, $80, $80, $80, $80, $E5, $E9, $EE, $F3, $F4, $E5, $EC
        .byte   $EC, $E5, $EE, $80, $80, $80, $80, $80, $80, $E6, $EF, $F2, $ED, $E1, $F4, $E9
        .byte   $E5, $F2, $E5, $EE, $80, $80, $80, $80, $80, $EF, $F2, $E9, $E7, $E9, $EE, $E1
        .byte   $EC, $80, $E4, $E9, $F3, $EB, $E5, $F4, $F4, $E5, $80, $80, $80, $80, $FA, $E9
        .byte   $E5, $EC, $80, $E4, $E9, $F3, $EB, $E5, $F4, $F4, $E5, $80, $80, $80, $E4, $E9
        .byte   $F3, $EB, $E5, $F4, $F4, $E5, $EE, $80, $E5, $E9, $EE, $EC, $E5, $E7, $E5, $EE
LF4C8:  .byte   $80, $80, $E4, $E9, $F3, $EB, $80, $E6, $E5, $E8, $EC, $E5, $F2, $80, $C3, $80
        .byte   $80, $80, $80, $80, $80, $80, $F3, $E5, $E3, $F4, $EF, $F2, $80, $80, $80, $80
        .byte   $80, $80, $80, $80, $80

LF4ED:  ldx     #$FF
        txs
        sei
        lda     #$00
        sta     $D402
        lda     #$F4
        sta     $D403
        ldy     #$04
LF4FD:  lda     LFB9F,y
        sta     $D016,y
        dey
        bpl     LF4FD
        sty     $76
        lda     #$F4
        sta     LF428
        jsr     LFC5E
        ldx     #$04
        stx     $75
        lda     #$28
LF516:  sta     $1B,x
        dex
        bne     LF516
        stx     $74
        ldx     #$80
LF51F:  lda     $D40B
        bne     LF51F
        dex
        bpl     LF51F
        stx     $4000
        dex
        stx     $D301
        ldy     #$0F
        sty     $68
LF532:  ldy     $68
        jsr     LF56E
        sty     $4000
        dec     $68
        bpl     LF532
        lda     #$FE
        sta     $D301
        ldy     #$00
        sty     $7A
        sty     $68
        lda     $4000
        cmp     #$FF
        bne     LF58A
LF550:  ldy     $68
        cpy     #$10
        bcs     LF567
        jsr     LF56E
        lda     $4000
        cmp     $7A
        bmi     LF567
        sta     $7A
        inc     $68
        jmp     LF550

LF567:  lda     #$FE
        sta     $D301
        bne     LF58A
LF56E:  lda     $D301
        and     #$23
        ora     LF57A,y
        sta     $D301
        rts

LF57A:  cpy     $C4C8
        cpy     #$8C
        dey
        sty     $80
        jmp     $4448

        rti

        .byte   $0C
        php
        .byte   $04
        brk
LF58A:  lda     #$80
        ldy     $8000
        inc     $8000
        cpy     $8000
        beq     LF5A6
        lda     #$A0
        ldy     $A000
        inc     $A000
        cpy     $A000
        beq     LF5A6
        lda     #$C0
LF5A6:  sta     $6A
        ldx     #$01
        jsr     LFCAA
        bcc     LF5B2
        jmp     LF4ED

LF5B2:  sty     $72
        lda     $E1
        sta     $70
        ora     #$10
        sta     LF600
        ldx     #$40
        ldy     #$00
LF5C1:  dey
        bne     LF5C1
        dex
        bne     LF5C1
        inc     $E1
        ldx     $E1
        jsr     LFCAA
        bcs     LF5D4
        lda     $E1
        bne     LF5D8
LF5D4:  lda     $70
        ldy     $72
LF5D8:  sta     $71
        sty     $73
        ora     #$10
        sta     LF61E
LF5E1:  jsr     LFC5E
        ldy     #$08
        jsr     PrintInline
        .byte   $2F, $72, $69, $67, $69, $6E, $61, $6C, $00, $2C, $61, $75, $66, $77, $65, $72
        .byte   $6B, $0E, $0E, $0E, $0E, $00, $24
LF600:
        .byte   $11, $EA
        ldy     #$30
        jsr     PrintInline
        .byte   $3A, $69, $65, $6C, $00, $2C, $61, $75, $66, $77, $65, $72, $6B, $0E, $0E, $0E
        .byte   $0E, $0E, $0E, $0E, $0E, $00, $24
LF61E:
        .byte   $11, $EA
LF620:  ldx     #$6C
        stx     LF427
        ldy     #$78
        jsr     LFC60
        ldy     #$5E
        jsr     PrintInline
        .byte   $33, $70, $65, $69, $63, $68, $65, $72, $1A, $00, $EA
        lda     $6A
        and     #$60
        lsr     a
        lsr     a
        lsr     a
        ldx     $68
        cpx     #$04
        bcc     LF64A
        clc
        adc     #$0C
LF64A:  cpx     #$08
        bcc     LF651
        clc
        adc     #$0C
LF651:  cpx     #$10
        bcc     LF658
        clc
        adc     #$0C
LF658:  tax
        lda     #$04
        sta     $7A
LF65D:  lda     LFBA4,x
        sta     LFEAA,y
        iny
        inx
        dec     $7A
        bne     LF65D
        lda     $76
        bne     LF693
        ldy     #$7D
        jsr     PrintInline
        .byte   $D9, $AF, $B0, $B4, $A9, $AF, $AE, $59, $0E, $36, $6F, $6E, $00, $32, $61, $6D
        .byte   $64, $69, $73, $6B, $00, $73, $63, $68, $72, $65, $69, $62, $65, $6E, $EA
        beq     LF6BD
LF693:  lda     $70
        cmp     $71
        beq     LF6BD
        ldy     #$7D
        jsr     PrintInline
        .byte   $D9, $AF, $B0, $B4, $A9, $AF, $AE, $59, $0E, $2C, $61, $75, $66, $77, $65, $72
        .byte   $6B, $65, $00, $61, $75, $73, $74, $61, $75, $73, $63, $68, $65, $6E, $EA
LF6BD:  ldy     #$A5
        jsr     PrintInline
        .byte   $D9, $B3, $A5, $AC, $A5, $A3, $B4, $59, $0E, $0E, $0E, $0E, $0E, $26, $6F, $72
        .byte   $6D, $61, $74, $69, $65, $72, $65, $6E, $1A, $00, $EA
        lda     $74
        beq     LF6EB
        jsr     PrintInline
        .byte   $2E, $25, $29, $2E, $EA
        beq     LF6F3
LF6EB:  jsr     PrintInline
        .byte   $00, $2A, $21, $00, $EA
LF6F3:  ldy     #$CD
        jsr     PrintInline
        .byte   $D9, $B3, $B4, $A1, $B2, $B4, $59, $0E, $0E, $0E, $0E, $0E, $0E, $24, $69, $73
        .byte   $6B, $65, $74, $74, $65, $00, $6B, $6F, $70, $69, $65, $72, $65, $6E, $EA
        jsr     LFC80
        cmp     #$05
        beq     LF771
        cmp     #$06
        beq     LF77A
        lda     $76
        beq     LF745
        ldy     $70
        ldx     $71
        sty     $71
        stx     $70
        tya
        ora     #$10
        sta     LF61E
        txa
        ora     #$10
        sta     LF600
        ldy     $72
        ldx     $73
        sty     $73
        stx     $72
        jmp     LF5E1

LF745:  ldy     #$CB
        sty     $3B
        ldx     #$FF
        stx     $7E
        inx
        stx     $3C
        stx     $3D
        stx     $7C
        stx     $3F
        ldy     #$78
        jsr     LFC60
        ldy     #$78
LF75D:  lda     LFF9A,x
        sta     LFEAA,y
        inx
        iny
        cpy     #$C8
        bne     LF75D
        lda     #$37
        sta     LFF73
        jmp     LF8E7

LF771:  lda     $74
        eor     #$FF
        sta     $74
        jmp     LF620

LF77A:  lda     $70
        eor     $71
        sta     $7C
        lda     #$00
        sta     $7F
        sta     $3F
        ldy     #$06
LF788:  sta     $37,y
        dey
        bpl     LF788
        sty     $7E
        lda     #$A3
        sta     $37
        lda     #$CB
        sta     $3B
        ldy     #$78
        jsr     LFC60
        lda     #$32
        sta     LFF4B
        lda     #$37
        sta     LFF73
        sta     $75
        ldx     #$01
        stx     $60
        dex
        stx     $61
LF7B0:  lda     $7C
        beq     LF7C5
        ldx     #$B5
LF7B6:  stx     LF427
        lda     #$20
        jsr     LFC6B
        cmp     #$06
        beq     LF7C9
        jmp     LF620

LF7C5:  ldx     #$8F
        bne     LF7B6
LF7C9:  lda     $7E
        bmi     LF7D0
        jmp     LF86A

LF7D0:  lda     #$00
        tax
LF7D3:  sta     $037E,x
        inx
        cpx     #$82
        bcc     LF7D3
        lda     #$A8
        sta     $41
        lda     #$53
        sta     $E2
        lda     #$04
        sta     $E8
        lda     #$40
        sta     $E3
        jsr     LFB38
        ldy     $70
        jsr     LFA99
        ldy     #$85
        jsr     PrintInline
        .byte   $24, $65, $6E, $73, $69, $74, $79, $1A, $00, $00, $EA
        lda     $0400
        and     #$A0
        sta     $7D
        bmi     LF820
        lda     #$05
        sta     $3E
        lda     $7D
        bne     LF830
        jsr     PrintInline
        .byte   $33, $29, $2E, $27, $2C, $25, $EA
        beq     LF83A
LF820:  ldx     #$08
        stx     $3E
        jsr     PrintInline
        .byte   $2D, $25, $24, $29, $35, $2D, $EA
        beq     LF83A
LF830:  jsr     PrintInline
        .byte   $24, $2F, $35, $22, $2C, $25, $EA
LF83A:  lda     $7C
        beq     LF86A
        lda     $74
        bne     LF86A
        bit     $73
        bpl     LF86A
        jsr     LF9D3
        sec
        jsr     LFA01
        tya
        bmi     LF86A
LF850:  lda     #$20
        sta     $E2
        lda     #$00
        sta     $E3
        ldy     $71
        jsr     LFA99
        tya
        bpl     LF868
        jsr     LFB4D
        bcc     LF850
        jmp     LF620

LF868:  inc     $3F
LF86A:  lda     $60
        sta     $64
        lda     $61
        sta     $65
        ldy     $70
        sty     $E1
        lda     $1B,y
        sta     $69
        jsr     LFB38
        lda     #$A8
        sta     $41
LF882:  ldy     $E1
        lda     $69
        sta     $1B,y
        ldx     $37
        ldy     $38
        lda     $39
        jsr     LFB7C
        sta     $39
        sty     $38
        stx     $37
LF898:  ldx     #$D9
        stx     LF427
        lda     #$40
        sta     $E3
        lda     $60
        sta     $EA
        lda     $61
        sta     $EB
        lda     #$52
        sta     $E2
        jsr     LFA55
        jsr     LFA7E
        bcc     LF8DB
        lda     $7F
        bpl     LF8D0
        sta     $EF
        jsr     LFB4D
        cmp     #$06
        beq     LF898
        cmp     #$05
        beq     LF8DB
        ldy     $E1
        lda     $69
        sta     $1B,y
        jmp     LF620

LF8D0:  ldy     $E1
        lda     #$28
        sta     $1B,y
        dec     $7F
        bne     LF898
LF8DB:  lda     #$00
        sta     $7F
        jsr     LFBF8
        jsr     LFAAD
        bcc     LF882
LF8E7:  lda     $60
        sta     $62
        lda     $61
        sta     $63
        lda     $7C
        bne     LF90B
        ldx     #$A2
        stx     LF427
        lda     #$20
        jsr     LFC6B
        cmp     #$05
        bcc     LF908
        lsr     a
        jsr     LFA01
        jmp     LF90B

LF908:  jmp     LF620

LF90B:  lda     $64
        sta     $60
        lda     $65
        sta     $61
        lda     $71
        sta     $E1
        lda     $7E
        bpl     LF958
        lda     $3F
        bne     LF958
        lda     $74
        bne     LF958
LF923:  ldx     #$7C
        stx     LF427
        jsr     LF9D3
        lda     #$80
        sta     $E8
        lda     #$22
        ldx     $7D
        bmi     LF93B
        beq     LF939
        asl     $E8
LF939:  lda     #$21
LF93B:  sta     $E2
        lda     #$A8
        sta     $41
        lda     #$D5
        sta     $E5
        lda     #$40
        sta     $E3
        ldy     $71
        jsr     LFA99
        bcc     LF958
        jsr     LFB4D
        bcc     LF923
        jmp     LF620

LF958:  lda     #$50
        sta     $E2
        inc     $7E
        jsr     LFB38
        lda     #$A8
        sta     $41
LF965:  ldx     #$D9
        stx     LF427
        lda     #$80
        sta     $E3
        lda     $60
        sta     $EA
        lda     $61
        sta     $EB
        jsr     LFA55
        jsr     LFC1B
        lda     $74
        bne     LF984
        lda     $EF
        beq     LF991
LF984:  jsr     LFA7E
        bcc     LF991
        jsr     LFB4D
        bcc     LF965
        jmp     LF620

LF991:  ldx     $3B
        ldy     $3C
        lda     $3D
        jsr     LFB7C
        sta     $3D
        sty     $3C
        stx     $3B
        jsr     LFAAD
        bcc     LF965
        php
        lda     $73
        bpl     LF9BE
        lda     #$51
        sta     $E2
        ldy     #$00
        sty     $E3
        sty     $41
        dey
        sty     $EA
        sty     $EB
        ldy     $71
        jsr     LFA99
LF9BE:  plp
        beq     LFA18
        lda     $62
        sta     $60
        lda     $63
        sta     $61
        lda     $7C
        bne     LF9D0
        jmp     LF7B0

LF9D0:  jmp     LF86A

LF9D3:  lda     $7D
        beq     LF9E5
        bpl     LF9DF
        ldx     #$EC
        ldy     #$FB
        bne     LF9E9
LF9DF:  ldx     #$E0
        ldy     #$FB
        bne     LF9E9
LF9E5:  ldx     #$D4
        ldy     #$FB
LF9E9:  stx     $E4
        sty     $E5
        lda     #$4F
        sta     $E2
        lda     #$0C
        sta     $E8
        lda     #$80
        sta     $E3
        asl     a
        sta     $41
        ldy     $71
        jmp     LFA99

LFA01:  lda     #$10
        bcs     LFA07
        ora     #$20
LFA07:  sta     $EA
        lda     #$00
        sta     $41
        sta     $E3
        lda     #$44
        sta     $E2
        ldy     $71
        jmp     LFA99

LFA18:  ldy     #$78
        ldx     #$00
LFA1C:  lda     LFEAA,y
        sta     LFF9A,x
        inx
        iny
        cpy     #$C8
        bne     LFA1C
        lda     $7E
        sta     $76
        lda     #$00
        sta     $D208
        ldy     #$EF
LFA33:  sty     $D201
        sty     $7A
        jsr     LFA45
        ldy     $7A
        dey
        cpy     #$DF
        bne     LFA33
        jmp     LF620

LFA45:  ldx     #$08
LFA47:  stx     $D200
        ldy     #$00
LFA4C:  dey
        bne     LFA4C
        inx
        cpx     #$50
        bne     LFA47
        rts

LFA55:  lda     #$80
        sta     $E8
        lda     #$00
        sta     $E9
        ldy     #$1E
        lda     $EB
        jsr     LFB6F
        lda     $EA
        jsr     LFB64
        lda     $7D
        cmp     #$20
        bne     LFA7D
        lda     $EB
        bne     LFA79
        lda     $EA
        cmp     #$04
        bcc     LFA7D
LFA79:  asl     $E8
        rol     $E9
LFA7D:  rts

LFA7E:  lda     #$02
        sta     $7A
        lda     $E3
        sta     $7B
LFA86:  jsr     LFCE2
        bpl     LFA97
        lda     $7B
        sta     $E3
        dec     $7A
        bne     LFA86
        sty     $E3
        sec
        rts

LFA97:  clc
        rts

LFA99:  sty     $E1
        lda     $1B,y
        pha
        lda     #$28
        sta     $1B,y
        jsr     LFA7E
        ldx     $E1
        pla
        sta     $1B,x
        rts

LFAAD:  bit     $7D
        bpl     LFABF
        lda     $60
        cmp     #$10
        bne     LFACD
        lda     $61
        cmp     #$04
        bne     LFACD
        sec
        rts

LFABF:  lda     $60
        cmp     #$D0
        bne     LFACD
        lda     $61
        cmp     #$02
        bne     LFACD
        sec
        rts

LFACD:  inc     $60
        bne     LFAD3
        inc     $61
LFAD3:  lda     $EF
        beq     LFB02
        lda     $E4
        clc
        adc     $E8
        sta     $E4
        lda     $E5
        adc     $E9
        sta     $E5
        bit     $66
        bmi     LFB2A
        tay
        iny
        cpy     #$F1
        beq     LFB05
        cpy     #$D1
        beq     LFAFA
        cpy     $6A
        bne     LFB02
        lda     #$C0
        bne     LFAFC
LFAFA:  lda     #$D8
LFAFC:  sta     $E5
        lda     #$00
        sta     $E4
LFB02:  clc
        bcc     LFB0A
LFB05:  lda     $68
        bne     LFB0D
LFB09:  sec
LFB0A:  lda     #$FF
        rts

LFB0D:  ldy     #$FF
        sty     $66
        iny
        sty     $67
LFB14:  lda     $D301
        and     #$23
        ora     LF57A,y
        sta     $D301
        lda     #$00
        sta     $E4
        lda     #$40
        sta     $E5
        clc
        bcc     LFB0A
LFB2A:  cmp     #$80
        bcc     LFB0A
        inc     $67
        ldy     $67
        cpy     $68
        beq     LFB09
        bne     LFB14
LFB38:  lda     #$00
        sta     $E4
        lda     #$04
        sta     $E5
        lda     #$00
        sta     $66
        lda     $D301
        ora     #$10
        sta     $D301
        rts

LFB4D:  ldx     #$C8
        stx     LF427
        ldy     #$0F
        lda     $E3
        jsr     LFB64
        lda     #$80
        jsr     LFC6B
        beq     LFB62
        sec
        rts

LFB62:  clc
        rts

LFB64:  pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     LFB6F
        pla
LFB6D:  and     #$0F
LFB6F:  cmp     #$0A
        bcc     LFB75
        adc     #$06
LFB75:  adc     #$D0
        sta     LF4C8,y
        iny
        rts

LFB7C:  sty     $3A
        tay
        iny
        cpy     $3E
        bcc     LFB97
        ldy     $3A
        iny
        cpy     #$04
        bcc     LFB8E
        inx
        ldy     #$00
LFB8E:  lda     LFB9B,y
        sta     LFEAA,x
        lda     #$00
        rts

LFB97:  tya
        ldy     $3A
        rts

LFB9B:  lsr     $59,x
        .byte   $C2
        .byte   $80
LFB9F:  .byte   $FA
        txa
        bpl     LFB6D
        .byte   $10
LFBA4:  .byte   $14
        bpl     LFC12
        brk
        .byte   $14
        clc
        .byte   $6B
        brk
        ora     $16,x
        .byte   $6B
        brk
        ora     ($10),y
        .byte   $14
        .byte   $6B
        ora     ($11),y
        .byte   $12
        .byte   $6B
        ora     ($12),y
        bpl     LFC27
        ora     ($16),y
        clc
        .byte   $6B
        ora     ($17),y
        asl     $6B,x
        ora     ($18),y
        .byte   $14
        .byte   $6B
        .byte   $12
        ora     $6B16,y
        .byte   $13
        bpl     LFBE3
        .byte   $6B
        .byte   $13
        ora     ($12),y
        .byte   $6B
        plp
        brk
        brk
        .byte   $12
        brk
        brk
        brk
        .byte   $80
        .byte   $FF
        brk
        brk
        brk
        plp
        brk
        brk
LFBE3:  .byte   $12
        brk
        .byte   $04
        ora     ($00,x)
        .byte   $FF
        brk
        brk
        brk
        plp
        brk
        brk
        .byte   $1A
        brk
        .byte   $04
        brk
        .byte   $80
        .byte   $FF
        brk
        brk
        brk
LFBF8:  lda     $EA
        and     #$07
        tax
        lda     $EA
        lsr     $EB
        ror     a
        lsr     $EB
        ror     a
        lsr     $EB
        ror     a
        tay
        lda     $61
        sta     $EB
        lda     $EF
        beq     LFC14
        .byte   $BD
LFC12:  .byte   $39
        .byte   $FC
LFC14:  ora     $037E,y
        sta     $037E,y
        rts

LFC1B:  lda     $EA
        and     #$07
        tax
        lda     $EA
        lsr     $EB
        ror     a
        lsr     $EB
LFC27:  ror     a
        lsr     $EB
        ror     a
        tay
        lda     $61
        sta     $EB
        lda     $037E,y
        and     LFC39,x
        sta     $EF
        rts

LFC39:  .byte   $80
        rti

        jsr     $0810
        .byte   $04
        .byte   $02
        .byte   $01
PrintInline:  pla
        sta     StrPtr
        pla
        sta     $44
LFC47:  inc     StrPtr
        bne     LFC4D
        inc     $44
LFC4D:  ldx     #$00
        lda     (StrPtr,x)
        cmp     #$EA
        beq     LFC5B
        sta     LFEAA,y
        iny
        bne     LFC47
LFC5B:  jmp     (StrPtr)

LFC5E:  ldy     #$00
LFC60:  lda     #$00
LFC62:  sta     LFEAA,y
        iny
        cpy     #$F0
        bne     LFC62
        rts

LFC6B:  sta     $D200
        ldy     #$EF
LFC70:  ldx     #$FF
LFC72:  stx     $D40A
        dex
        bne     LFC72
        dey
        sty     $D201
        cpy     #$E0
        bne     LFC70
LFC80:  lda     $D01F
        cmp     #$07
        bne     LFC80
LFC87:  ldx     #$00
LFC89:  dex
        stx     $D40A
        bne     LFC89
LFC8F:  lda     $D01F
        cmp     #$07
        beq     LFC8F
LFC96:  cmp     $D01F
        bne     LFC87
        dex
        bne     LFC96
        ldy     #$40
LFCA0:  sta     $D40A
        sty     $D01F
        dey
        bne     LFCA0
        rts

LFCAA:  stx     $E1
        lda     #$A8
        sta     $41
        lda     #$3F
        sta     $E2
        lda     #$01
        sta     $E8
        lda     #$40
        sta     $E3
        jsr     LFB38
        jsr     LFCE2
        bpl     LFCD6
        cpy     #$8B
        beq     LFCD2
        inc     $E1
        ldx     $E1
        cpx     #$05
        bcc     LFCAA
        sec
        rts

LFCD2:  ldy     #$00
        clc
        rts

LFCD6:  lda     $0400
        ldy     $E1
        sta     $1B,y
        ldy     #$FF
        clc
        rts

LFCE2:  ldy     $E1
        tya
        ora     #$30
        sta     $A0
        lda     $E2
        sta     $A1
        lda     $EA
        sta     $A2
        lda     $EB
        sta     $A3
        lda     $1B,y
        sta     $D204
        lda     #$00
        sta     $D206
        tsx
        stx     $0318
        lda     $75
        sta     $36
LFD08:  lda     #$00
        sta     $30
        sta     $0319
        sta     $33
        lda     #$A0
        sta     $32
        lda     #$04
        sta     $34
        lda     #$34
        sta     $D303
        jsr     LFD51
        lda     $E4
        sta     $32
        lda     $E5
        sta     $33
        lda     $E8
        sta     $34
        bit     $E3
        bpl     LFD34
        jsr     LFD51
LFD34:  dec     $0319
        jsr     LFDD3
        bit     $E3
        bvc     LFD41
        jsr     LFD93
LFD41:  jsr     LFE03
        stx     $D20E
        lda     #$A0
        sta     $D207
        ldy     $30
        sty     $E3
        rts

LFD51:  ldy     #$80
LFD53:  iny
        bne     LFD53
        lda     #$23
        jsr     LFE53
LFD5B:  lda     $34
        bmi     LFD61
        bne     LFD65
LFD61:  lda     $EF
        beq     LFD67
LFD65:  lda     ($32),y
LFD67:  cpy     #$00
        bne     LFD72
        sta     $31
        sta     $D20D
        beq     LFD75
LFD72:  jsr     LFE37
LFD75:  iny
        cpy     $34
        bne     LFD5B
        lda     $31
        jsr     LFE37
LFD7F:  lda     $D20E
        and     #$08
        bne     LFD7F
        sta     $D20E
        ldx     #$00
        ldy     #$03
        jsr     LFE05
        jmp     LFDE2

LFD93:  ldy     #$32
        jsr     LFE05
        ldy     #$00
        sty     $31
        sty     $EF
LFD9E:  jsr     LFE18
        sta     ($32),y
        tax
        ora     $EF
        sta     $EF
        txa
        jsr     LFE4B
        iny
        cpy     $34
        bne     LFD9E
        jsr     LFE18
        cmp     $31
        bne     LFDB9
        rts

LFDB9:  lda     #$8A
LFDBB:  sta     $30
        jsr     LFE03
        ldx     $0318
        txs
        bit     $0319
        bmi     LFDD0
        dec     $36
        beq     LFDD0
        jmp     LFD08

LFDD0:  jmp     LFD41

LFDD3:  ldx     #$01
        lda     $E2
        cmp     #$30
        bcs     LFDDD
        ldx     #$0C
LFDDD:  ldy     #$60
        jsr     LFE07
LFDE2:  lda     #$13
        jsr     LFE53
        lda     #$3C
        sta     $D303
        jsr     LFE18
        cmp     #$41
        beq     LFE03
        cmp     #$43
        beq     LFE03
        cmp     #$45
        beq     LFDFF
        lda     #$8B
        bne     LFDBB
LFDFF:  lda     #$90
        sta     $30
LFE03:  ldy     #$00
LFE05:  ldx     #$00
LFE07:  lda     #$B9
        sta     VVBLKD
        lda     #$FD
        sta     $0227
        stx     $0219
        sty     $0218
        rts

LFE18:  lda     $D20E
        and     #$20
        bne     LFE18
        sta     $D20E
        lda     #$38
        sta     $D20E
        lda     $D20F
        sta     $D20A
        bpl     LFDB9
        and     #$20
        beq     LFDB9
        lda     $D20D
        rts

LFE37:  tax
LFE38:  lda     $D20E
        and     #$10
        bne     LFE38
        sta     $D20E
        lda     #$38
        sta     $D20E
        txa
        sta     $D20D
LFE4B:  clc
        adc     $31
        adc     #$00
        sta     $31
        rts

LFE53:  sta     $D20F
        sta     $D20A
        lda     #$28
        sta     $D208
        lda     $41
        sta     $D207
        lda     #$38
        sta     $D20E
        rts

        pha
        lda     $D40F
        sta     $D40F
        and     #$20
        beq     LFE77
        jmp     $0100

LFE77:  lda     $0218
        bne     LFE84
        lda     $0219
        beq     LFE8E
        dec     $0219
LFE84:  dec     $0218
        bne     LFE8E
        lda     $0219
        beq     LFE9F
LFE8E:  lda     $D209
        cmp     #$EC
        bne     LFE98
        jmp     $013E

LFE98:  lda     #$08
        sta     $D01F
        pla
        rti

LFE9F:  jmp     (VVBLKD)

        pha
        lda     #$00
        sta     $D20E
        pla
        rti

LFEAA:  brk
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
LFF4B:  brk
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
LFF73:  brk
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
LFF9A:  brk
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
Seg2End:

; ---------------------------------------------------------------------------
; Segment #3 ($3FFA-$3FFF, 6 bytes): reproduced byte-exact; purpose not
; identified (not the 6502 hardware vector table, which lives at
; $FFFA-$FFFF; this is just below the $4000 boundary).
; ---------------------------------------------------------------------------
        .segment "HEADER3"
        .word   $3FFA
        .word   $3FFF

        .segment "SEG3"
        .byte   $69, $FE, $00, $00, $A2, $FE

; ---------------------------------------------------------------------------
; Atari DOS "binary load" RUNAD framing: run address = $2F00 (segment #1).
; ---------------------------------------------------------------------------
        .segment "RUNAD"
        .word   $02E0
        .word   $02E1
        .word   Seg1Start
