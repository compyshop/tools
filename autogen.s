; ---------------------------------------------------------------------------
; AUTOGEN.COM - "AUTORUN.SYS Generator" (auto-type a BASIC command at boot)
; Reverse engineered from a 552-byte Atari DOS binary load file.
;
; Layout on disk (Atari DOS "binary load" format):
;   FF FF              - binary load file signature
;   00 40 21 42        - segment: start=$4000, end=$4221 (546 bytes)
;   ... 546 bytes ...
; There is no RUNAD segment; like RDTEST2.COM/CONV32D.COM this is one of
; the menu items loaded (at the fixed address $4000) and run by
; AUTORUN.SYS's RunFile loader (see FN_AUTOGEN in autorun.s), not run
; directly by DOS.
;
; What it does: prompts "Basic Befehl eingeben:" (Enter BASIC command:),
; reads up to 40 characters of typed text (terminated by RETURN/$9B or by
; running out of room), then writes a *new*, self-contained AUTORUN.SYS to
; D: that will automatically "type" that command into BASIC's input at the
; next boot - a classic auto-type/type-ahead trick, not simulated
; keypresses in this file itself.
;
; The written file (embedded here verbatim as data, from $41A0 to the end
; of this file) is itself a complete Atari DOS binary load file for a tiny
; ~118-byte program loaded at $0680 with RUNAD=$0680:
;   - copies the OS ROM E: device's 6-entry vector table (EDITRV, $E400-
;     $E40F) into a RAM shadow at $06E6-$06F5;
;   - patches the shadow's GET-byte vector (offset 4-5, i.e. $06EA/$06EB)
;     to point at a small replacement GET routine appended after it;
;   - redirects HATABS's E: handler-table pointer ($0321/$0322, the 3rd
;     HATABS slot) from $E400 to the $06E6 shadow table, so every E: GET
;     call runs the replacement routine instead of reading the keyboard;
;   - the replacement routine returns one character at a time from a
;     40-byte buffer at $06BD (patched, before writing, with the user's
;     typed command, space-padded) until it hits a $9B (EOL) byte, at
;     which point it restores HATABS's E: pointer back to $E400 (real
;     ROM table) so normal keyboard input resumes.
;   That's how the "auto-generated" AUTORUN.SYS makes BASIC (or DOS)
;   receive the stored command as though it had been typed by hand.
;
; Same inline-string-printing trick as CONV32D.COM/RDTEST2.COM: on-screen
; text is stored immediately after "jsr PrintInline" ($411B), which pulls
; its own return address off the stack, prints bytes from there until an
; $EA (NOP) sentinel, then resumes execution right after the sentinel. All
; three such strings are reproduced verbatim below. A byte-identical
; rebuild was verified with ca65/ld65 and cmp against the original
; AUTOGEN.COM.
; ---------------------------------------------------------------------------

        .setcpu "6502"

        .segment "HEADER"
        .word   $FFFF           ; binary load file signature
        .word   Entry           ; segment start address ($4000)
        .word   CodeEnd-1       ; segment end address ($4221)

; Zero-page / scratch variables used
StrPtr  = $00F0         ; ($F0/$F1) return-address pointer used by PrintInline

CIOV    = $E456         ; OS ROM: Central I/O Vector (IOCB #1, $0350)

        .segment "CODE"
        .org $4000
Entry:
        jsr     PrintInline
        .byte   $7D, $9B, $A0, $C1, $D5, $D4, $CF, $D2, $D5, $CE, $AE, $D3, $D9, $D3, $A0, $C7
        .byte   $C5, $CE, $C5, $D2, $C1, $D4, $CF, $D2, $A0, $9B, $9B, $41, $62, $62, $72, $75
        .byte   $63, $68, $20, $6D, $69, $74, $20, $42, $52, $45, $41, $4B, $20, $21, $9B, $9B
        .byte   $42, $61, $73, $69, $63, $20, $42, $65, $66, $65, $68, $6C, $20, $65, $69, $6E
        .byte   $67, $65, $62, $65, $6E, $3A, $9B, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D
        .byte   $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $9B, $EA
        jsr     GetKeyLine
        bpl     L4068
        rts

; ---------------------------------------------------------------------------
; If the typed line is a single RETURN (nothing entered), just quit.
; Otherwise print "OK. SCHREIBE AUTORUN.SYS DATEI..." and write the file.
; ---------------------------------------------------------------------------
L4068:  lda     TypedLine
        cmp     #$9B
        bne     L4070
        rts

L4070:  jsr     PrintInline
        .byte   $9B, $9B, $4F, $4B, $2E, $20, $53, $43, $48, $52, $45, $49, $42, $45, $20, $41
        .byte   $55, $54, $4F, $52, $55, $4E, $2E, $53, $59, $53, $20, $44, $41, $54, $45, $49
        .byte   $2E, $2E, $2E, $9B, $9B, $EA
        ldy     #$00
CopyCmd:
        lda     TypedLine,y
        sta     CmdBuf,y        ; patch the typed command into the template
        cmp     #$9B
        beq     CopyDone
        iny
        bne     CopyCmd
CopyDone:
        ldx     #$00
        stx     CmdIndex
        ldx     #$10            ; IOCB #1
        lda     #$03            ; ICCOM = open
        sta     $0342,x
        lda     #$0D            ; ICAX1 = open for output, directory
        sta     $0344,x
        lda     #$41
        sta     $0345,x         ; ICBAL/ICBAH -> "D:AUTORUN.SYS" filename
        lda     #$08
        sta     $034A,x
        jsr     CIOV
        bmi     WriteFail
        lda     #$0B            ; ICCOM = put record (write)
        sta     $0342,x
        lda     #$A0
        sta     $0344,x         ; ICBAL/ICBAH -> embedded template ($41A0)
        lda     #$41
        sta     $0345,x
        lda     #$82
        sta     $0348,x         ; ICBLL/ICBLH = $0082 = 130 bytes
        lda     #$00
        sta     $0349,x
        jsr     CIOV
        bmi     WriteFail
CloseIocb:
        ldx     #$10
        lda     #$0C            ; ICCOM = close
        sta     $0342,x
        jmp     CIOV

WriteFail:
        jsr     CloseIocb
        jsr     PrintInline
        .byte   $9B, $9B, $53, $43, $48, $52, $45, $49, $42, $46, $45, $48, $4C, $45, $52, $20
        .byte   $21, $21, $21, $9B, $9B, $EA
        rts

; ---------------------------------------------------------------------------
; Static "D:AUTORUN.SYS" filename (used as the ICBAL/ICBAH target above).
; ---------------------------------------------------------------------------
        .byte   $44, $3A, $41, $55, $54, $4F, $52, $55, $4E, $2E, $53, $59, $53, $9B

; ---------------------------------------------------------------------------
; PrintInline: pull the return address off the stack, print characters
; starting there (through the PutChar CIO-vector trick) until an $EA (NOP)
; sentinel byte, then resume execution right after the sentinel.
; ---------------------------------------------------------------------------
PrintInline:
        pla
        sta     StrPtr
        pla
        sta     StrPtr+1
PrintLp:
        inc     StrPtr
        bne     PrintChk
        inc     StrPtr+1
PrintChk:
        ldx     #$00
        lda     (StrPtr,x)
        cmp     #$EA
        beq     PrintDone
        jsr     PutChar
        jmp     PrintLp

PrintDone:
        jmp     (StrPtr)

; ---------------------------------------------------------------------------
; PutChar: RTS-jump into the OS E: "PUT byte" handler (reads its vector out
; of OS ROM directly rather than going through CIO). Same trick used by
; AUTORUN.SYS/RDTEST2.COM/CONV32D.COM.
; ---------------------------------------------------------------------------
PutChar:
        tax
        lda     $E407
        pha
        lda     $E406
        pha
        txa
        rts

; ---------------------------------------------------------------------------
; GetKeyLine: open E: (IOCB #1) for input, read up to 40 chars into
; TypedLine (below).
; ---------------------------------------------------------------------------
GetKeyLine:
        ldx     #$00
        lda     #$05            ; ICCOM = get record
        sta     $0342,x
        lda     #$60
        sta     $0344,x         ; ICBAL/ICBAH -> TypedLine ($4160)
        lda     #$41
        sta     $0345,x
        lda     #$40            ; ICBLL/ICBLH = 40 (max length)
        sta     $0348,x
        txa
        sta     $0349,x
        jmp     CIOV

; ---------------------------------------------------------------------------
; TypedLine: 64-byte input buffer, cleared to zero at assembly time (the
; original file stores it pre-zeroed rather than clearing it at runtime).
; Only the first 40 bytes are used by the CIO "get record" call above.
; ---------------------------------------------------------------------------
TypedLine:
        .res    64, $00

; ---------------------------------------------------------------------------
; Embedded "generated AUTORUN.SYS" template ($41A0-$4221, 130 bytes),
; written byte-for-byte to D:AUTORUN.SYS by the code above. It is itself a
; complete Atari DOS binary load file: FF FF signature, a RUNAD segment
; (run address = $0680), and one program segment ($0680-$06F5, 118 bytes).
; See the file header comment above for what the $0680 program does; its
; addresses are in *its own* address space, not this file's.
; ---------------------------------------------------------------------------
EmbeddedFile:
        .byte   $FF, $FF                        ; embedded file signature
        .byte   $E0, $02, $E1, $02              ; RUNAD segment header
        .byte   $80, $06                        ; RUNAD value = $0680
        .byte   $80, $06, $F5, $06              ; program segment: $0680-$06F5
        .byte   $A0, $0F, $B9, $00, $E4, $99, $E6, $06, $88, $10, $F7, $A9, $9F, $8D, $EA, $06
        .byte   $A9, $06, $8D, $EB, $06, $A9, $E6, $8D, $21, $03, $A9, $06, $8D, $22, $03, $60
        .byte   $AC, $E5, $06, $B9, $BD, $06, $C9, $9B, $F0, $06, $EE, $E5, $06, $A0, $01, $60
        .byte   $A0, $00, $8C, $21, $03, $A0, $E4, $8C, $22, $03, $A0, $01, $60
; CmdBuf ($06BD in the embedded program): 40-byte space-padded command-text
; buffer, patched with the user's typed command (CopyCmd loop above) before
; the file is written.
CmdBuf:
        .res    40, $20
; CmdIndex ($06E5 in the embedded program): read index into CmdBuf while
; "typing"; zeroed here before writing (reused by CopyDone above as an
; unrelated one-shot flag in *this* file's address space).
CmdIndex:
        .byte   $00
; $06E6-$06F5 in the embedded program: space for the RAM-shadowed copy of
; the E: device's OS ROM vector table, populated at runtime by the
; embedded program itself; blank (zero) in the on-disk template.
        .res    16, $00
CodeEnd:
