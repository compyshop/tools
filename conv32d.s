; ---------------------------------------------------------------------------
; CONV32D.COM - "DOS 3/DOS 2 Konvertierung" file copy utility
; Reverse engineered from a 1372-byte Atari DOS binary load file.
;
; Layout on disk (Atari DOS "binary load" format):
;   FF FF              - binary load file signature
;   00 24 55 29        - segment: start=$2400, end=$2955 (1366 bytes)
;   ... 1366 bytes ...
; There is no RUNAD segment; like RDTEST2.COM this is one of the menu items
; loaded (at the fixed address $2400) and run by AUTORUN.SYS's RunFile
; loader (see FN_CONV32D in autorun.s), not run directly from DOS.
;
; What it does: copies a single file between two disk drives, one file at a
; time, converting between the "DOS 3" and "DOS 2" directory/sector layout
; along the way (hence the name: CONVert dos3/dos2, D). The on-screen menu
; ([1] Set Source Drive, [2] Set Destination Drive, [3] Copy File, [4] Exit)
; toggles the source/destination drive numbers between 1 and 2, reads the
; destination directory sector (via a raw SIO Read-Sector DCB call, not
; CIO), lets the user pick a file from a list with the A-Z keys, then reads
; it 128 bytes at a time into $0400-$047F and writes it back out to the
; other drive, opening the destination file over CIOV (IOCB #1).
;
; Only one embedded coding trick needed unwinding to disassemble this file:
; most on-screen text is stored *inline* right after "jsr PrintInline"
; ($287A) - that routine pulls its own return address off the stack,
; prints characters starting there until it hits an $EA (NOP) sentinel
; byte, then resumes execution at the byte after the sentinel. All such
; inline strings are reproduced verbatim below, immediately following the
; call that prints them. A byte-identical rebuild was verified with
; ca65/ld65 and cmp against the original CONV32D.COM.
;
; A handful of internal zero-page/page-2 scratch addresses ($52/$53, $D0-
; $D1/$D4-$D5/$F3, $02A3, $0340-range IOCB slots, $02E6) and two external
; OS/DOS entry points ($E46E, $E474, and the DOS-resident SIO dispatcher at
; $070C) are reproduced as raw addresses rather than named: they aren't
; standard, well-known OS ROM vectors and their exact roles are inferred
; from context, not verified against OS ROM contents (which aren't part of
; this file).
; ---------------------------------------------------------------------------

        .setcpu "6502"

        .segment "HEADER"
        .word   $FFFF           ; binary load file signature
        .word   Entry           ; segment start address ($2400)
        .word   CodeEnd-1       ; segment end address ($2955)

; Zero-page / scratch variables used
StrPtr  = $00CB         ; ($CB/$CC) return-address pointer used by PrintInline

; Standard Atari SIO Device Control Block ($0300-$030B)
DDEVIC  = $0300
DUNIT   = $0301
DCOMND  = $0302
DSTATS  = $0303
DBUFLO  = $0304
DBUFHI  = $0305
DBYTLO  = $0308
DBYTHI  = $0309
DAUX1   = $030A
DAUX2   = $030B

SKCTL   = $D20F         ; POKEY serial port control register
CIOV    = $E456         ; OS ROM: Central I/O Vector (used for the final
                        ; destination-file OPEN, via IOCB #1 at $0350)
GetKeyVec  = $E424      ; low/high byte pair of the K: (keyboard) "GET
                        ; byte" CIO vector, read directly and RTS-jumped
                        ; into (same trick used by AUTORUN.SYS/RDTEST2.COM)
EditPutVec = $E406      ; low/high byte pair of the E: (screen editor) "PUT
                        ; byte" CIO vector, same trick

; Called but not part of this file (OS ROM / resident DOS code); addresses
; reproduced as-is, not standard well-known OS ROM vectors.
DosProbe = $E46E        ; called once at startup
DosWarm  = $E474        ; jumped to from the [4] Exit handler
SioEntry = $070C        ; DOS-resident SIO dispatcher
ShowDate = $D9AA        ; called from ShowNamePad (purpose not identified)
ShowExt  = $D8E6        ; called from ShowNamePad (purpose not identified)

        .segment "CODE"
        .org $2400
Entry:
        jsr     DosProbe
        lda     #$B1            ; 'B1' = inverse-video '1'
        sta     L247F
        lda     #$53            ; 'S' = SIO Status command
        sta     DCOMND
        lda     #$02
        sta     DUNIT
        ora     #$B0            ; A was $02 -> $B2 = inverse-video '2'
        sta     L2486
        jsr     GetStatus
        bpl     L241F
        dec     L2486           ; drive 2 didn't answer -> guess drive 1
L241F:  dec     DUNIT
        jsr     GetStatus
        bpl     MainMenu
        lda     L2486
        sta     L247F           ; drive 1 didn't answer either -> same guess

; ---------------------------------------------------------------------------
; Main menu: draw the boxed menu (source/dest drive numbers are the two
; inverse-video digits embedded in the string below), read a key 1-4,
; echo it, and dispatch through the jump table below.
; ---------------------------------------------------------------------------
MainMenu:
        lda     #$01
        sta     $52
        sta     $02A3
        lda     #$26
        sta     $53
MenuLoop:
        jsr     PrintInline
        .byte   $7D, $A0, $AA, $AA, $AA, $A0, $C4, $CF, $D3, $A0, $C9, $C9, $C9, $A0, $AD, $AD
        .byte   $BE, $A0, $C4, $CF, $D3, $A0, $C9, $C9, $A0, $C3, $EF, $EE, $F6, $E5, $F2, $F4
        .byte   $E5, $F2, $A0, $AA, $AA, $AA, $A0, $A0, $A8, $E3, $A9, $A0, $C2, $E9, $E2, $EF
        .byte   $F3, $EF, $E6, $F4, $A0, $B7, $AF, $B1, $B9, $B8, $B7, $A0, $DF, $DF, $DF, $DF
        .byte   $A0, $D3, $C4, $BD
L247F:  ; source drive number (inverse-video digit char)
        .byte   $B1, $A0, $AF, $A0, $C4, $C4, $BD
L2486:  ; destination drive number (inverse-video digit char)
        .byte   $B2, $A0, $9B, $7F, $99, $B1, $19, $20, $53, $65, $74, $20, $53, $6F, $75, $72
        .byte   $63, $65, $5F, $5F, $5F, $5F, $5F, $5F, $44, $72, $69, $76, $65, $9B, $7F, $99
        .byte   $B2, $19, $20, $53, $65, $74, $20, $44, $65, $73, $74, $69, $6E, $61, $74, $69
        .byte   $6F, $6E, $5F, $44, $72, $69, $76, $65, $9B, $7F, $99, $B3, $19, $20, $43, $6F
        .byte   $70, $79, $5F, $46, $69, $6C, $65, $9B, $7F, $99, $B4, $19, $20, $45, $78, $69
        .byte   $74, $9B, $9B, $7F, $3F, $EA
        jsr     ReadKey
        jsr     PutCharSafe
        cmp     #$31            ; '1'
        bcc     BadKey
        cmp     #$35            ; '5'
        bcc     Dispatch
BadKey: jmp     MenuLoop

; ---------------------------------------------------------------------------
; Dispatch key '1'-'4' through a 4-entry (low,high) address-1 table using
; the classic push-then-RTS trick.
; ---------------------------------------------------------------------------
Dispatch:
        sec
        sbc     #$31
        asl     a
        tax
        lda     L24FC,x
        pha
        lda     L24FB,x
        pha
        rts

; Jump table (interleaved low,high bytes of target-1, x = (key-'1')*2):
; x=0 -> $2502 -> ToggleSrc  ($2503); x=2 -> $250C -> ToggleDst ($250D)
; x=4 -> $2523 -> CopyFile   ($2524); x=6 -> $2516 -> Exit      ($2517)
L24FB:  .byte   $02
L24FC:  .byte   $25, $0C, $25, $23, $25, $16, $25

ToggleSrc:
        lda     L247F
        eor     #$03            ; B1 <-> B2
        sta     L247F
        bne     BadKey

ToggleDst:
        lda     L2486
        eor     #$03
        sta     L2486
        bne     BadKey

Exit:
L2517:  lda     SKCTL
        cmp     #$FF
        bne     L2517
        sta     $02FC
        jmp     DosWarm

; ---------------------------------------------------------------------------
; [3] Copy File: read directory sector 16 (the DOS directory start sector)
; from the destination drive into $2956, page through it 8 entries at a
; time letting the user browse with A-Z, pick a file, then copy it.
; ---------------------------------------------------------------------------
CopyFile:
        lda     L247F
        and     #$03
        sta     DUNIT
        lda     #$56
        sta     DBUFLO
        lda     #$29
        sta     DBUFHI          ; buffer = $2956 (directory sector)
        lda     #$10
        sta     DAUX1
        lda     #$00
        sta     DAUX2           ; sector 16
L2540:  lda     #$52            ; 'R' = Read Sector
        sta     DCOMND
        jsr     GetSector
        bpl     L254D
        jmp     ShowError

L254D:  lda     DBUFLO
        clc
        adc     #$80
        sta     DBUFLO
        bcc     L255B
        inc     DBUFHI
L255B:  inc     DAUX1
        lda     DAUX1
        cmp     #$14
        bne     L2540
        jsr     PrintInline
        .byte   $7D, $53, $45, $4C, $20, $46, $49, $4C, $45, $4E, $41, $4D, $20, $45, $58, $54
        .byte   $20, $42, $4C, $4F, $20, $4C, $45, $4E, $20, $20, $20, $44, $9B, $EA
        lda     #$41
        sta     L25A2
        lda     #$66
        sta     $D0
        lda     #$29
        sta     $D1              ; BufPtr ($D0/$D1) = $2966 (dir entries)

; ---------------------------------------------------------------------------
; List directory entries, one per screen line, prefixed with an
; inverse-video letter A, B, C... to select with.
; ---------------------------------------------------------------------------
L2593:  ldy     #$01
L2595:  lda     ($D0),y
        beq     L25EB           ; flags byte 0 -> unused slot -> stop
        cpy     #$01
        bne     L25A9
        jsr     PrintInline
        .byte   $9B, $5B
L25A2:  ; currently-highlighted directory-entry letter
        .byte   $41, $5D, $20, $EA
        inc     L25A2
L25A9:  jsr     PutCharSafe
        iny
        cpy     #$0C
        bne     L2595
        lda     ($D0),y
        jsr     ShowNamePad
        jsr     PrintInline
        .byte   $20, $24, $EA
        ldy     #$0F
        lda     ($D0),y
        jsr     PrintHexDigit
        dey
        lda     ($D0),y
        jsr     PrintHexDigit
        ldy     #$00
        lda     ($D0),y
        tax
        lda     $D0
        clc
        adc     #$10
        sta     $D0
        bcc     L25D9
        inc     $D1
L25D9:  txa
        and     #$40
        bne     L25E4
        jsr     PrintInline
        .byte   $20, $44, $EA
L25E4:  lda     L25A2
        cmp     #$5B            ; past 'Z'?
        bcc     L2593
L25EB:  lda     #$9B
        jsr     PutChar

; ---------------------------------------------------------------------------
; Wait for an A-Z key selecting a listed file (or ESC/other to redraw).
; ---------------------------------------------------------------------------
L25F0:  jsr     PrintInline
        .byte   $9C, $99, $D3, $C5, $CC, $C5, $C3, $D4, $19, $6F, $72, $99, $D2, $C5, $D4, $D5
        .byte   $D2, $CE, $19, $20, $EA
        jsr     ReadKey
        jsr     PutChar
        cmp     #$9B
        bne     L2615
        jmp     MainMenu

L2615:  cmp     #$41
        bcc     L25F0
        cmp     L25A2
        bcs     L25F0
        pha
        ldx     #$29
        and     #$10
        beq     L2626
        inx
L2626:  pla
        and     #$0F
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #$57
        sta     $D0
        bcc     L2635
        inx
L2635:  stx     $D1             ; BufPtr -> selected directory entry

; ---------------------------------------------------------------------------
; Build the "D1:FILENAME.EXT" filename into L2941 from the raw 8.3
; directory-entry name (space padded, high bit stripped as it copies).
; ---------------------------------------------------------------------------
        ldx     #$00
        ldy     #$00
L263B:  lda     ($D0),y
        cmp     #$20
        bne     L2649
        cpy     #$08
        bcs     L2649
L2645:  lda     #$2E
        ldy     #$07
L2649:  sta     L2944,x
        inx
        cmp     #$2E
        beq     L2655
        cpy     #$07
        beq     L2645
L2655:  iny
        cpy     #$0B
        bne     L263B
        lda     #$9B
        sta     L2944,x
        iny
        lda     ($D0),y         ; sector-count byte of the directory entry
        sta     DAUX1
        lda     #$00
        sta     DAUX2
        ldx     #$02
L266C:  asl     DAUX1
        rol     DAUX2
        dex
        bpl     L266C
        lda     DAUX1
        clc
        adc     #$19
        sta     DAUX1
        bcc     L2683
        inc     DAUX2
L2683:  iny
        lda     ($D0),y
        sta     L2954
        iny
        lda     ($D0),y
        sta     L2955
        jsr     PrintInline
        .byte   $7D, $1D, $43, $4F, $50, $59, $20, $3A, $9B, $9B, $EA
        lda     L247F
        and     #$33
        sta     L2942
        jsr     PrintCmdWord
        lda     L2486
        and     #$33
        sta     L2942
        ora     #$B0
        cmp     L247F
        beq     L26C3
        jsr     PrintInline
        .byte   $20, $2D, $2D, $3E, $20, $EA
        jsr     PrintCmdWord
L26C3:  jsr     PrintInline
        .byte   $9B, $9B, $EA

; ---------------------------------------------------------------------------
; Read the file from the source drive, 128 bytes at a time into $0400, and
; buffer each block into the directory-sector area for later writing out.
; ---------------------------------------------------------------------------
L26C9:  lda     #$56
        sta     $D0
        lda     #$29
        sta     $D1
        lda     L247F
        and     #$03
        sta     DUNIT
        lda     #$00
        sta     DBUFLO
        lda     #$04
        sta     DBUFHI          ; read target = $0400
L26E3:  lda     #$52
        sta     DCOMND
        jsr     GetSector
        bpl     L26F0
        jmp     ShowError

L26F0:  inc     DAUX1
        bne     L26F8
        inc     DAUX2
L26F8:  ldy     #$00
L26FA:  lda     $0400,y
        sta     ($D0),y
        iny
        cpy     L2954
        beq     L2725
L2705:  tya
        bpl     L26FA
        jsr     L2834
        ldy     #$00
        lda     L2954
        sec
        sbc     #$80
        sta     L2954
        bcs     L271B
        dec     L2955
L271B:  ldx     $D1
        inx
        cpx     $02E6
        bcc     L26E3
        bcs     L2728
L2725:  ldx     L2955
L2728:  stx     L2951
        bne     L2705
        jsr     L2834
        lda     DAUX1
        sta     L2952
        lda     DAUX2
        sta     L2953
        lda     L247F
        cmp     L2486
        bne     L2773
        jsr     PrintInline
        .byte   $49, $6E, $73, $65, $72, $74, $20, $44, $65, $73, $74, $2E, $20, $44, $69, $73
        .byte   $6B, $20, $69, $6E, $20, $44, $72, $69, $76, $65, $20, $EA
        lda     L2486
        and     #$33
        jsr     PutCharSafe
        jsr     ReadKey
        lda     #$9C
        jsr     PutCharSafe
L2773:  ldx     #$10            ; IOCB #1
        lda     $0340,x
        cmp     #$FF
        bne     L2798
        lda     #$03            ; ICCOM = open
        sta     $0342,x
        lda     #$08            ; ICAX1 = open for output
        sta     $034A,x
        lda     #$41
        sta     $0344,x         ; ICBAL/ICBAH -> filename buffer (L2941)
        lda     #$29
        sta     $0345,x
        jsr     CIOV
        bpl     L2798
        jmp     ShowError

L2798:  lda     #$0B            ; ICCOM = put record (or similar write call)
        sta     $0342,x
        lda     #$56
        sta     $0344,x         ; ICBAL/ICBAH -> buffered file data ($2956)
        lda     #$29
        sta     $0345,x
        lda     $D0
        sec
        sbc     #$56
        sta     $0348,x         ; ICBLL/ICBLH = bytes buffered so far
        lda     $D1
        sbc     #$29
        sta     $0349,x
        jsr     CIOV
        bpl     L27BE
        jmp     ShowError

L27BE:  lda     L2951
        beq     AllDone
        lda     L247F
        cmp     L2486
        bne     L27FB
        jsr     PrintInline
        .byte   $49, $6E, $73, $65, $72, $74, $20, $53, $6F, $75, $72, $63, $65, $20, $44, $69
        .byte   $73, $6B, $20, $69, $6E, $20, $44, $72, $69, $76, $65, $20, $EA
        lda     L247F
        and     #$33
        jsr     PutCharSafe
        jsr     ReadKey
        lda     #$9C
        jsr     PutCharSafe
L27FB:  lda     L2952
        sta     DAUX1
        lda     L2953
        sta     DAUX2
        jmp     L26C9

AllDone:
        jsr     CloseIocb
        jsr     PrintInline
        .byte   $9B, $54, $72, $61, $6E, $73, $66, $65, $72, $20, $4F, $4B, $2E, $20, $20, $50
        .byte   $72, $65, $73, $73, $20, $61, $6E, $79, $20, $4B, $65, $79, $20, $EA
        jsr     ReadKey
        jmp     MainMenu

; ---------------------------------------------------------------------------
; Small helpers
; ---------------------------------------------------------------------------
L2834:  tya
        clc
        adc     $D0
        sta     $D0
        bcc     L283E
        inc     $D1
L283E:  rts

CloseIocb:
        ldx     #$10
        lda     #$0C            ; ICCOM = close
        sta     $0342,x
        jmp     CIOV

ReadKey:
        lda     GetKeyVec+1
        pha
        lda     GetKeyVec
        pha
        rts

        ; Unused leftover: RTS-jump into the E: OPEN vector, byte-exact but
        ; never called (same pattern seen, also unused, in RDTEST2.COM).
        lda     $E401
        pha
        lda     $E400
        pha
        rts

PutCharSafe:
        jsr     SaveRegs
        jsr     PutChar
RestoreRegs:
        ldx     $CD
        ldy     $CE
        lda     $CF
        rts

SaveRegs:
        stx     $CD
        sty     $CE
        sta     $CF
        rts

PutChar:
        tax
        lda     EditPutVec+1
        pha
        lda     EditPutVec
        pha
        txa
        rts

; ---------------------------------------------------------------------------
; PrintInline: pull the return address off the stack, print characters
; starting there (through the PutChar CIO-vector trick) until an $EA (NOP)
; sentinel byte, then resume execution right after the sentinel.
; ---------------------------------------------------------------------------
PrintInline:
        jsr     SaveRegs
        pla
        sta     StrPtr
        pla
        sta     $CC
L2883:  inc     StrPtr
        bne     L2889
        inc     $CC
L2889:  ldy     #$00
        lda     (StrPtr),y
        cmp     #$EA
        beq     L2897
        jsr     PutChar
        jmp     L2883

L2897:  jsr     RestoreRegs
        jmp     (StrPtr)

; ---------------------------------------------------------------------------
; PrintHexDigit: print A (a byte with two BCD-ish nibbles) as two hex
; digits 0-9/A-F via PrintNibble/PutCharSafe.
; ---------------------------------------------------------------------------
PrintHexDigit:
        tax
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     PrintNibble
        txa
        and     #$0F
PrintNibble:
        cmp     #$0A
        bcc     L28AE
        adc     #$06
L28AE:  adc     #$30
        jmp     PutCharSafe

; ---------------------------------------------------------------------------
; ShowNamePad: print the 8.3 filename at (DirEnt),y (DirEnt = A*... + $2703,
; see below) as a space-prefixed string with the high bit stripped,
; stopping at the first '.'; ShowDate/ShowExt print additional fields
; whose exact format isn't identified.
; ---------------------------------------------------------------------------
ShowNamePad:
        clc
        adc     #$E8
        sta     $D4
        lda     #$03
        adc     #$00
        sta     $D5             ; DirEnt ($D4/$D5) -> directory entry name
        lda     #$20
        jsr     PutChar
        jsr     ShowDate
        jsr     ShowExt
        inc     $F3
L28CB:  ldy     #$00
        lda     ($F3),y
        and     #$7F
        cmp     #$2E
        beq     L291A           ; (forward ref: shared return point below,
        jsr     PutChar         ;  at the end of PrintCmdWord)
        inc     $F3
        jmp     L28CB

; ---------------------------------------------------------------------------
; ShowError: print "...ERROR #" + status byte + "Press any Key".
; ---------------------------------------------------------------------------
ShowError:
        jsr     PrintInline
        .byte   $9B, $FD, $45, $52, $52, $4F, $52, $20, $23, $EA
        tya
        jsr     ShowNamePad
        jsr     PrintInline
        .byte   $20, $20, $50, $72, $65, $73, $73, $20, $61, $6E, $79, $20, $4B, $65, $79, $20
        .byte   $EA
        jsr     CloseIocb
        jsr     ReadKey
        jmp     MainMenu

; ---------------------------------------------------------------------------
; PrintCmdWord: print each byte of the 16-byte string at L2941,x, stopping
; at $9B (EOL). L291A (this routine's rts) is also ShowNamePad's "done"
; return point above.
; ---------------------------------------------------------------------------
PrintCmdWord:
        ldx     #$00
L290D:  lda     L2941,x
        cmp     #$9B
        beq     L291A
        jsr     PutCharSafe
        inx
        bne     L290D
L291A:  rts

; ---------------------------------------------------------------------------
; GetStatus: SIO "S" (status) call, 4-byte reply into $02EA. GetSector
; (falls into the same tail) instead does an "R" (read sector) call, using
; whatever DCOMND/DUNIT/DBUFLO/DBUFHI/DAUX1/DAUX2 the caller has already
; set up, with a fixed 128-byte (one sector) transfer.
; ---------------------------------------------------------------------------
GetStatus:
        lda     #$EA
        sta     DBUFLO
        lda     #$02
        sta     DBUFHI          ; buffer = $02EA
        asl     a
        sta     DBYTLO          ; byte count = 4
        lda     #$00
        sta     DBYTHI
        beq     SioCommon
GetSector:
        lda     #$80
        sta     DBYTLO          ; byte count = 128 (one sector)
        asl     a
        sta     DBYTHI
SioCommon:
        lda     #$40
        sta     DSTATS          ; read direction
        jmp     SioEntry

; ---------------------------------------------------------------------------
; Mutable filename buffer, initialized with a template and patched in place
; ("D1:" prefix and ".EXT"/EOL suffix kept; NAME portion overwritten in
; place by the filename-building loop above, which addresses it as
; L2944 = L2941+3). $2942 doubles as an unrelated scratch byte elsewhere
; (the source/destination drive digit shown in the "COPY :" line).
; ---------------------------------------------------------------------------
L2941:  .byte   $44
L2942:  .byte   $31, $3A
L2944:  .byte   $46, $49, $4C, $45, $4E, $41, $4D, $45, $2E, $45, $58, $54, $9B

; Scratch counters, zero-initialized at assembly time (matches the
; original file, which stores these as static zero bytes rather than
; clearing them at runtime).
L2951:  .byte   $00     ; "any file copied yet" flag / block count
L2952:  .byte   $00     ; saved DAUX1 (sector number to resume at)
L2953:  .byte   $00     ; saved DAUX2
L2954:  .byte   $00     ; file length, low byte
L2955:  .byte   $00     ; file length, high byte

CodeEnd:
