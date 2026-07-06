; ---------------------------------------------------------------------------
; RDTEST2.COM - Extended-RAM ("PORTB banked memory") access test
; Reverse engineered from a 1097-byte Atari DOS binary load file.
;
; Layout on disk (Atari DOS "binary load" format):
;   FF FF              - binary load file signature
;   00 30 3C 34        - segment #1: start=$3000, end=$343C (1085 bytes)
;   ... 1085 bytes ...
;   E0 02 E1 02        - segment #2: start=$02E0, end=$02E1 (RUNAD, 2 bytes)
;   00 30              - value written into RUNAD: run address = $3000
;
; What it does: the program cycles through 16 bit-patterns written to PORTB
; ($D301), the PIA register that on XL/XE machines selects which physical
; RAM bank (or OS/BASIC ROM) is mapped into the CPU address space. For each
; pattern it writes and reads back a test pattern in the $4000-$40FF window,
; sounds a POKEY sweep tone, updates the on-screen "Bank N" label, and shows
; either "...Zugriff ist ok" (access OK) or "...Zugriff funktioniert nicht"
; (access failed) for that bank. This is a hardware diagnostic for testing
; bank-switched RAM expansions (130XE-style extended memory).
;
; $3000-$31B7 is 6502 code. $31B8-$3434 is data: a 16-byte PORTB bank-select
; table, small lookup tables of Atari "internal" (screen) character codes,
; a POKEY-driven VBI color-cycle routine (referenced only as data - no call
; site into it was found, so it is reproduced byte-exact but not asserted to
; be reachable), and several German status-message string fragments.
; $3435-$343C is a short deferred-VBI handler tail.
; ---------------------------------------------------------------------------

        .setcpu "6502"

        .segment "HEADER"
        .word   $FFFF           ; binary load file signature
        .word   CodeStart       ; segment start address ($3000)
        .word   CodeEnd-1       ; segment end address ($343C)

; Zero-page / OS variables used
RTCLOK2 = $14           ; OS jiffy clock, low byte (RTCLOK+2) - ticks once/VBI
InitDone= $08           ; one-shot "already initialized" guard
BankIdx = $E4           ; current bank index (0-15) being tested
BankLim = $E5           ; number of banks found readable/writable
AnyBank = $E6           ; "at least one non-base bank present" flag
BufPtr  = $E0           ; ($E0/$E1) test-pattern pointer, also reused as a
                        ; plain loop counter elsewhere in the same routines

; Hardware / OS ROM equates
NMIEN   = $D40E         ; ANTIC NMI enable register
PORTB   = $D301         ; PIA port B - bank/ROM select on XL/XE
AUDF1   = $D200         ; POKEY channel 1 frequency
AUDC1   = $D201         ; POKEY channel 1 control
AUDCTL  = $D208         ; POKEY audio control
WSYNC   = $D40A         ; ANTIC "wait for horizontal sync"
COLOR0  = $02C4         ; OS shadow register for COLPF0
COLOR4  = $02C8         ; OS shadow register for COLBK (background)
SETVBV  = $E45C         ; OS ROM: install a VBI handler
XITVBV  = $E462         ; OS ROM: exit a deferred VBI handler
EditPutVec = $E406      ; low/high byte pair of the E: (screen editor) "PUT
                        ; character" CIO vector, read directly and RTS-jumped
                        ; into (same trick used by AUTORUN.SYS's PutChar)

        .segment "CODE"
        .org $3000
CodeStart:

        lda     #$00
        sta     $0C             ; zero-page pointer, low byte
        lda     #$30
        sta     $0D             ; ...high byte -> $3000 (points at program
                                 ; start; not read again in this file)
        ldx     #$01
        stx     $09
        stx     $03F8
        dex
        stx     $0244
        lda     #$00
        sta     InitDone
        sta     AnyBank

Init:   lda     #$00
        sta     NMIEN           ; disable VBI/DLI while (re)installing them
        lda     #$D6
        sta     $0200           ; VDSLST low byte
        lda     #$32
        sta     $0201           ; VDSLST high byte -> DLI vector = $32D6
        ldx     #$C9
        ldy     #$31
        stx     $0230           ; internal pointer, low byte  -> $31C9
        sty     $0231           ; ...high byte
        lda     #$21
        sta     $022F
        lda     #$88
        sta     COLOR0
        lda     #$10
        sta     COLOR4
        ldx     #$34
        ldy     #$35
        lda     #$07            ; A=7: deferred VBI
        jsr     SETVBV          ; install deferred VBI at $3435 (X:Y=$34:$35)
        lda     #$C0
        sta     NMIEN           ; re-enable DLI + VBI
        lda     #$00
        sta     RTCLOK2
        lda     InitDone
        bne     WaitTick
        ldx     #$FF
        stx     PORTB
        inx
        txa
FillAsc:
        sta     $4000,x         ; fill $4000-$407F with an ascending pattern
        inx
        bpl     FillAsc
        ldx     #$0F
ClrMsg: sta     Msg,x           ; clear the 16-byte "Bank N ..." message line
        dex
        bpl     ClrMsg
        stx     InitDone        ; X=$FF here -> InitDone = "already run" guard
        sta     $E4             ; A still holds the last ascending byte ($80)
        jsr     Wait1Tick

WaitTick:
        lda     RTCLOK2
        bpl     WaitTick

; ---------------------------------------------------------------------------
; Probe all 16 PORTB bank-select patterns; count how many give a distinct,
; writable $4000-$41FF window (i.e. how many extra RAM banks are present).
; ---------------------------------------------------------------------------
        ldx     #$FF
        stx     PORTB
        inx
        stx     $4100
        ldx     #$0F
ProbeLp:
        lda     BankTab,x
        sta     PORTB
        sta     $4100
        lda     #$00
        sta     Msg,x
        dex
        bpl     ProbeLp
        stx     PORTB
        lda     $4100
        beq     Path1
        jmp     Path2

Path1:
        inx
Path1Copy:
        lda     Screen1A,x
        sta     $4000,x
        inx
        bpl     Path1Copy
        lda     #$10
        sta     BankLim
        lda     #$A2
        sta     COLOR4
        lda     #$00
        sta     BankIdx
        sta     BufPtr

; ---------------------------------------------------------------------------
; Pass 1: for each of the 16 bank patterns, write a PORTB-derived test byte
; throughout a 64-byte window and record which banks are distinct/present.
; ---------------------------------------------------------------------------
ScanLp: lda     RTCLOK2
WaitA:  cmp     RTCLOK2
        beq     WaitA           ; wait exactly one jiffy between banks
        ldx     BankIdx
        cpx     BankLim
        bcs     Done1
        lda     BankTab,x
        beq     Done1
        sta     PORTB
        cmp     $4100
        bne     ShowNum
        lda     #$33
        ldx     BankIdx
        sta     Msg,x
        ldy     #$00
        ldx     #$40
        stx     $E1
WriteLp:
        txa
        eor     PORTB
StoreB: sta     (BufPtr),y
        clc
        adc     #$01
        iny
        bne     StoreB
        inc     $E1
        dex
        bne     WriteLp
        inc     BankIdx
        lda     AnyBank
        bne     ScanLp
        jsr     Wait1Tick
        bne     ScanLp
Done1:  stx     BankLim
        jsr     Wait1Tick
        sty     AnyBank

; ---------------------------------------------------------------------------
; Pass 2: re-read back each bank's test pattern and compare; report OK/FAIL
; per bank via the on-screen "Bank N" message.
; ---------------------------------------------------------------------------
ScanLp2:
        lda     #$00
        sta     BankIdx
CheckLp:
        lda     RTCLOK2
WaitB:  cmp     RTCLOK2
        beq     WaitB
        ldx     BankIdx
        cpx     BankLim
        beq     AllDone
        lda     BankTab,x
        sta     PORTB
        lda     #$2C
        ldx     BankIdx
        sta     Msg,x
        ldy     #$00
        ldx     #$40
        stx     $E1
CmpLp:  txa
        eor     PORTB
DoCmp:  cmp     (BufPtr),y
        bne     Beep
        clc
        adc     #$01
        iny
        bne     DoCmp
        inc     $E1
        dex
        bne     CmpLp
        lda     #$0E
SetMsg: ldx     BankIdx
        sta     Msg,x
        inc     BankIdx
        bne     CheckLp
ShowNum:
        ldx     BankIdx
        ldy     BankIdx
        lda     #$0D
NumLp:  sta     Msg,y
        iny
        cpy     #$10
        bcc     NumLp
        jmp     ScanLp2

Path2:
        ldx     #$00
Path2Copy:
        lda     Screen1B,x
        sta     $4000,x
        inx
        bpl     Path2Copy
        jmp     Init

AllDone:
        ldx     #$00
AllDoneCopy:
        lda     Screen2,x
        sta     $4000,x
        inx
        bpl     AllDoneCopy
        jmp     Init

; ---------------------------------------------------------------------------
; POKEY "sweep" tone, also used to signal a mismatch during pass 2 (Beep is
; reached both on the initial-scan branch below and via the CmpLp/DoCmp
; mismatch above).
; ---------------------------------------------------------------------------
Beep:
        lda     #$50
        sta     AUDF1
        ldx     #$00
        stx     AUDCTL
SweepLp:
        txa
        and     #$0F
        ora     #$A0
        sta     AUDC1
        sta     WSYNC
        inx
        bne     SweepLp
        stx     AUDF1
        stx     AUDC1
        lda     #$A5
        jmp     SetMsg

; ---------------------------------------------------------------------------
; Wait1Tick: copy a 3-byte "digit triple" for the current bank number out of
; DigitTab into MsgBuf (used to render "Bank N" on screen), then wait for one
; full jiffy clock tick before returning.
; ---------------------------------------------------------------------------
Wait1Tick:
        lda     BankIdx
        asl     a
        clc
        adc     BankIdx
        tax
        ldy     #$00
CopyDig:
        lda     DigitTab,x
        sta     MsgBuf,y
        inx
        iny
        cpy     #$03
        bcc     CopyDig
        sta     RTCLOK2
WaitC:  cmp     RTCLOK2
        beq     WaitC
        rts

; ---------------------------------------------------------------------------
; PutChar: RTS-jump into the OS E: "PUT byte" handler (reads its vector out
; of OS ROM directly rather than going through CIO). Not called from
; anywhere else in this file; kept for byte-exact reproduction.
; ---------------------------------------------------------------------------
PutChar:
        tax
        lda     EditPutVec+1
        pha
        lda     EditPutVec
        pha
        txa
        rts

; ---------------------------------------------------------------------------
; BankTab: 16 PORTB bit-patterns, one per candidate RAM/ROM bank.
; ---------------------------------------------------------------------------
BankTab:
        .byte   $CF, $CB, $C7, $C3, $8F, $8B, $87, $83
        .byte   $4F, $4B, $47, $43, $0F, $0B, $07, $03

; ---------------------------------------------------------------------------
; Screen/text data ($31C8-$3434). Reproduced byte-exact from the original
; file. Recognizable fragments (German, using a mix of plain ASCII and
; Atari "internal" screen codes) are called out below; the surrounding
; bytes are believed to be screen-position/attribute values for a small
; custom print routine rather than a simple linear string, and are not
; further decoded.
; ---------------------------------------------------------------------------
        .byte   $00, $70, $70, $70, $70, $70, $F0, $70, $10, $46, $EA, $31, $30, $02, $F0, $70
        .byte   $02, $A0, $02, $02, $00, $02, $70, $F0, $10, $42, $00, $40, $02, $02, $02, $41
        .byte   $C9, $31, $00, $32, $21, $2D, $24, $29, $33, $2B, $00, $34, $25, $33, $34, $00
        .byte   $12, $00, $00, $08, $23, $09, $00, $11, $19, $18, $17, $00, $22, $29, $22, $2F
        .byte   $33, $2F, $26, $34, $00, $0F, $00, $23, $2F, $2D, $30, $39, $00, $33, $28, $2F
        .byte   $30, $00, $1D, $1D, $1D, $1D, $1D, $1E, $00
MsgBuf: ; overwritten at runtime by Wait1Tick with a 3-byte "digit triple"
        .byte   $00, $00, $00, $00, $2B, $22, $79, $74, $65, $00, $32, $61, $6D, $24, $69, $73
        .byte   $6B, $00, $00, $1C, $1D, $1D, $1D, $1D, $1D, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $10, $00, $00, $00, $00
        .byte   $11, $00, $00, $00, $00, $11, $00, $00, $00, $00, $00, $00, $22, $61, $6E, $6B ; "ank"
        .byte   $00, $1D, $1E, $00, $00, $00, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19
        .byte   $10, $11, $12, $13, $14, $15, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $00, $00
Msg:    ; 16-byte "Bank N ..." status line, cleared/filled at runtime
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00
DigitTab: ; screen-code "digit triple" table, indexed by BankIdx*3 in Wait1Tick
        .byte   $00, $00, $10, $00, $11, $16, $00, $13, $12, $00, $14, $18, $00, $16, $14, $00
        .byte   $18, $10, $00, $19, $16, $11, $11, $12, $11, $12, $18, $11, $14, $14, $11, $16
        .byte   $10, $11, $17, $16, $11, $19, $12, $12, $10, $18, $12, $12, $14, $12, $14, $10
        .byte   $12, $15, $16, $00, $00
; ---------------------------------------------------------------------------
; Data below resembles a VBI-style routine (PHA/TXA/PHA/TYA/PHA ... RTI) that
; cycles COLPF3/COLBK ($D017/$D018) from two 1-byte-per-frame tables and
; increments a frame counter - but no JSR/JMP anywhere in the code above
; targets $32D6, so it is reproduced as inert data rather than asserted
; to be a reachable interrupt handler.
; ---------------------------------------------------------------------------
        .byte   $08, $0A, $08, $4A, $12, $02, $80, $48, $8A, $48, $98, $48, $AE, $CD, $32, $86
        .byte   $4D, $BD, $CE, $32, $BC, $D2, $32, $8D, $17, $D0, $8C, $18, $D0, $EE, $CD, $32
        .byte   $68, $A8, $68, $AA, $68, $40
; ---------------------------------------------------------------------------
; Screen1A ($32F5-$3374, 128 bytes): copied to $4000 by Path1Copy. Contains
; the German fragment "...ugriff.funktioniert..nicht" ("...access doesn't
; work") mixed with position/attribute bytes.
; ---------------------------------------------------------------------------
Screen1A:
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $24, $65, $72, $00, $21, $2E, $34, $29, $23, $0D, $3A, $75, $67, $72, $69 ; "$er...ugri"
        .byte   $66, $66, $00, $66, $75, $6E, $6B, $74, $69, $6F, $6E, $69, $65, $72, $74, $00 ; "ff.funktioniert."
        .byte   $00, $6E, $69, $63, $68, $74, $00, $01, $00, $00, $00, $00, $00, $00, $00, $00 ; ".nicht."
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
; ---------------------------------------------------------------------------
; Screen2 ($3355-$33D4, 128 bytes): copied to $4000 by AllDoneCopy when pass
; 2 finishes scanning every bank. Overlaps the tail of Screen1A and the head
; of Screen1B (all three are read as raw 128-byte windows over the same
; underlying byte stream). Contains "...ugriff.ist.ok" ("...access is ok").
; ---------------------------------------------------------------------------
Screen2:
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00, $24, $65, $72, $00, $21, $2E, $34, $29, $23, $0D, $3A, $75, $67 ; "$er...ug"
        .byte   $72, $69, $66, $66, $00, $69, $73, $74, $00, $6F, $6B, $0E, $00, $00, $00, $00 ; "riff.ist.ok."
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
; ---------------------------------------------------------------------------
; Screen1B ($33B5-$3434, 128 bytes): copied to $4000 by Path2Copy. Contains
; "...eine...am Disk.vorhanden" (fragment of "keine Diskette vorhanden" -
; "no diskette present") plus a run of screen-code $52 ('R') bytes.
; ---------------------------------------------------------------------------
Screen1B:
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $2B, $65, $69, $6E, $65, $00, $32, $61, $6D, $24, $69, $73 ; "+eine.2am$is"
        .byte   $6B, $00, $76, $6F, $72, $68, $61, $6E, $64, $65, $6E, $0E, $00, $00, $00, $00 ; "k.vorhanden."
        .byte   $00, $00, $00, $00, $52, $52, $52, $52, $52, $52, $52, $52, $52, $52, $52, $52
        .byte   $52, $52, $52, $52, $52, $52, $52, $52, $52, $52, $52, $52, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

; ---------------------------------------------------------------------------
; Deferred VBI handler, installed above via SETVBV (X:Y = $34:$35 -> $3435).
; ---------------------------------------------------------------------------
VbiTail:
        lda     #$00
        sta     $32CD
        jmp     XITVBV
CodeEnd:

; ---------------------------------------------------------------------------
; Atari DOS "binary load" framing. This produces a file byte-identical to
; the original RDTEST2.COM when built with the accompanying rdtest2.cfg.
; ---------------------------------------------------------------------------
        .segment "RUNAD"
        .word   $02E0
        .word   $02E1
        .word   CodeStart
