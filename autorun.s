; ---------------------------------------------------------------------------
; AUTORUN.SYS - "BIBO-DOS Anwender-Disk" boot menu
; Reverse engineered from a 471-byte Atari DOS binary load file.
;
; Layout on disk (Atari DOS "binary load" format):
;   FF FF              - binary load file signature
;   00 30 CA 25        - segment #1: start=$2400, end=$25CA (459 bytes)
;   ... 459 bytes ...
;   E0 02 E1 02        - segment #2: start=$02E0, end=$02E1 (RUNAD, 2 bytes)
;   61 25              - value written into RUNAD: run address = $2561
;
; $2400-$254C is pure data: an ATASCII screen/text buffer that gets printed
; character-by-character. $254D-$25CA is 6502 code. Program entry (RUNAD)
; is $2561, partway into the code -- the bytes before it ($254D-$2560) are
; a small helper subroutine used by the entry code.
; ---------------------------------------------------------------------------

        .setcpu "6502"

        .segment "HEADER"
        .word   $FFFF           ; binary load file signature
        .word   MenuText        ; segment start address ($2400)
        .word   CodeEnd-1       ; segment end address ($25CA)

EOL     = $9B          ; ATASCII end-of-line character

; Zero-page / OS variables used
TxtPtr  = $E0           ; ($E0/$E1) pointer used while printing the menu text
Mode    = $52           ; scratch flag, passed on to the external file loader
GuardFl = $02FC         ; one-shot "already ran" guard (DOS/CIO scratch page)
ClrFlag = $0735         ; cleared before handing off to the external loader
COLOR1  = $02C5         ; OS shadow register for GTIA/ANTIC COLOR1 (playfield)
COLOR2  = $02C6         ; OS shadow register for COLOR2
COLOR4  = $02C8         ; OS shadow register for COLOR4 (background)

; These fall inside the Atari OS ROM's handler-vector tables ($E400-$E42F:
; EDITRV / KEYBDV). The code below reads the 2 address bytes of a handler
; entry directly and RTS-jumps into it -- a common trick in fast Atari boot
; menus to print/read a character without going through full CIO. The exact
; sub-offset naming (GET/PUT) is inferred from call context, not verified
; against OS ROM contents (which aren't part of this file).
EditPutVec = $E406      ; presumed E: (screen editor) "PUT byte" vector bytes
KeybdGetVec = $E424     ; presumed K: (keyboard) "GET byte" vector bytes

; External entry point, not part of this file. Called with A/Y = pointer
; to a D:-prefixed, EOL-terminated filename to load and run.
RunFile = $070F

        .segment "CODE"
        .org $2400

; ---------------------------------------------------------------------------
; Menu screen data ($2400-$254C), printed character by character.
; ---------------------------------------------------------------------------
; Raw ATASCII screen data (mixes inverse-video high-bit-set characters for
; the title bar with plain-ASCII menu text), reproduced byte-exact from the
; original file. Trailing comments show the decoded text (| = ATASCII EOL,
; high-bit-set chars shown as their plain letter).
MenuText:
        .byte   $7D,$9B,$9B,$91,$92,$92,$92,$92          ; }||.....
        .byte   $92,$92,$92,$92,$92,$92,$92,$92          ; ........
        .byte   $92,$92,$92,$92,$92,$92,$92,$92          ; ........
        .byte   $92,$92,$92,$92,$85,$9B,$FC,$A0          ; .....||
        .byte   $C2,$C9,$C2,$CF,$AD,$C4,$CF,$D3          ; BIBO-DOS
        .byte   $A0,$C1,$EE,$F7,$E5,$EE,$E4,$E5          ;  Anwende
        .byte   $F2,$AD,$C4,$E9,$F3,$EB,$A0,$FC          ; r-Disk |
        .byte   $9B,$9A,$92,$92,$92,$92,$92,$92          ; |.......
        .byte   $92,$92,$92,$92,$92,$92,$92,$92          ; ........
        .byte   $92,$92,$92,$92,$92,$92,$92,$92          ; ........
        .byte   $92,$92,$83,$9B,$9B,$9B,$9B,$5B          ; ...||||[
        .byte   $41,$5D,$20,$44,$55,$50,$2D,$4D          ; A] DUP-M
        .byte   $65,$6E,$75,$65,$9B,$9B,$5B,$42          ; enue||[B
        .byte   $5D,$20,$53,$65,$6B,$74,$6F,$72          ; ] Sektor
        .byte   $20,$4B,$6F,$70,$69,$65,$72,$65          ;  Kopiere
        .byte   $72,$20,$28,$31,$30,$35,$30,$29          ; r (1050)
        .byte   $9B,$9B,$5B,$43,$5D,$20,$4D,$75          ; ||[C] Mu
        .byte   $6C,$74,$69,$20,$46,$69,$6C,$65          ; lti File
        .byte   $2D,$43,$6F,$70,$79,$20,$28,$31          ; -Copy (1
        .byte   $30,$35,$30,$29,$9B,$9B,$5B,$44          ; 050)||[D
        .byte   $5D,$20,$44,$4F,$53,$20,$33,$2F          ; ] DOS 3/
        .byte   $44,$4F,$53,$20,$32,$20,$4B,$6F          ; DOS 2 Ko
        .byte   $6E,$76,$65,$72,$74,$65,$72,$9B          ; nverter|
        .byte   $9B,$5B,$45,$5D,$20,$52,$61,$6D          ; |[E] Ram
        .byte   $44,$69,$73,$6B,$20,$54,$65,$73          ; Disk Tes
        .byte   $74,$65,$72,$9B,$9B,$5B,$46,$5D          ; ter||[F]
        .byte   $20,$41,$55,$54,$4F,$52,$55,$4E          ;  AUTORUN
        .byte   $2E,$53,$59,$53,$20,$47,$65,$6E          ; .SYS Gen
        .byte   $65,$72,$61,$74,$6F,$72,$9B,$9B          ; erator||
        .byte   $9B,$20,$20,$53,$65,$6C,$65,$63          ; |  Selec
        .byte   $74,$20,$50,$72,$6F,$67,$72,$61          ; t Progra
        .byte   $6D,$6D,$20,$2E,$2E,$2E                  ; mm ...

; Table of pointers to the filename strings below, indexed by
; (chosen letter - 'A') * 2. Entry 0 (letter 'A', "DUP-Menue") is never
; used -- option A just returns without loading anything -- so its slot
; is left as leftover/unused data (the trailing space + terminator of the
; prompt string above happen to occupy it).
FilePtrTab:
        .byte   " ",0           ; unused slot for option 'A'
        .word   FN_SCOPY        ; [B]
        .word   FN_MFCOPY       ; [C]
        .word   FN_CONV32D      ; [D]
        .word   FN_RDTEST2      ; [E]
        .word   FN_AUTOGEN      ; [F]

FN_SCOPY:       .byte "D:SCOPY.COM",EOL
FN_MFCOPY:      .byte "D:MFCOPY.COM",EOL
FN_CONV32D:     .byte "D:CONV32D.COM",EOL
FN_RDTEST2:     .byte "D:RDTEST2.COM",EOL
FN_AUTOGEN:     .byte "D:AUTOGEN.COM",EOL

; ---------------------------------------------------------------------------
; Code ($254D-$25CA)
; ---------------------------------------------------------------------------

; Print the character in A to the screen via a direct vector call.
; Uses X as scratch to survive the vector-address push; the target address
; is read out of the OS handler vector table and "returned into" via RTS.
PutChar:
        tax
        lda     EditPutVec+1
        pha
        lda     EditPutVec
        pha
        txa
        rts

; Read one character from the keyboard the same way.
GetChar:
        lda     KeybdGetVec+1
        pha
        lda     KeybdGetVec
        pha
        rts

; --- RUNAD entry point ($2561) -----------------------------------------
Entry:
        lda     GuardFl
        cmp     #$21
        bne     ShowMenu
        lda     #$FF
        sta     GuardFl
        rts                     ; already ran once - skip the menu

ShowMenu:
        lda     #$10
        sta     COLOR4
        lda     #$90
        sta     COLOR2
        lda     #$CA
        sta     COLOR1
        lda     #$07
        sta     Mode
        lda     #<MenuText
        sta     TxtPtr
        lda     #>MenuText
        sta     TxtPtr+1

PrintLoop:
        ldx     #$00
        lda     (TxtPtr,x)
        beq     ReadKey
        jsr     PutChar
        inc     TxtPtr
        bne     PrintLoop
        inc     TxtPtr+1
        bne     PrintLoop

ReadKey:
        jsr     GetChar
        cmp     #$20            ; space -> treat as 'A'
        bne     :+
        lda     #$41
:       cmp     #$41
        bcc     ReadKey         ; below 'A' - ignore, read another key
        tax
        sbc     #$41
        cmp     #$06            ; only 6 options (A-F)
        bcs     ReadKey
        asl     a               ; *2 -> word index into FilePtrTab
        pha
        txa
        jsr     PutChar         ; echo the chosen key
        lda     #$02
        sta     Mode
        pla
        bne     Dispatch
        rts                     ; option 'A' (DUP-Menue) - just return

Dispatch:
        tax
        lda     #$00
        sta     ClrFlag
        lda     FilePtrTab,x
        ldy     FilePtrTab+1,x
        jmp     RunFile         ; hand off (A,Y)=filename pointer to the loader

CodeEnd:

; ---------------------------------------------------------------------------
; Atari DOS "binary load" framing. This produces a file byte-identical to
; the original AUTORUN.SYS when built with the accompanying autorun.cfg.
; ---------------------------------------------------------------------------
        .segment "RUNAD"
        .word   $02E0
        .word   $02E1
        .word   Entry
