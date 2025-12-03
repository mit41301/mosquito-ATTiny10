;
; mosquito.asm
;
; Created: 03-12-2025 19:03:44
; Author : Mosquito
;
;--------------------------------------------------------
;here is the assembly code
;--------------------------------------------------------
;
; The rick rolling mosquito
;
; Copyright 2012 Eric Heisler
;  This program is free software: you can redistribute it and/or modify
;  it under the terms of the GNU General Public License version 3 as published by
;  the Free Software Foundation.
;
;  This program is distributed in the hope that it will be useful,
;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;  GNU General Public License for more details.
;
; receives data up to 64 bits plus a header
; waits for 30 sec
; transmits the received data
; waits a second
; rick rolls
;
; >pin 1(PB0) piezo
; >pin 3(PB1) tx
; >pin 4(PB2) rx
; >pin 6(PB3) reset
;
;
; registers
; r16-18 are for temp use

.DEF rinLength = r19 ; number of bits
.DEF rinstop = r20 ; flags: bit0-stop receiving (timed out), 1-confirmed 1 on, 2-confirmed 1 off
.DEF rlongshort = r21 ; the longest or shortest length read from ram
.DEF rrxtimer = r22 ; for timing rx bits
.DEF rseqbitmask = r23 ; holds a useful bitmask
.DEF rtxonseq = r24 ; holds the current on seq
.DEF rtxoffseq = r25 ; holds the current off seq
;.DEF rnotelength = r26 ; the time to play the note
#define rnotelength XL

.EQU rxpin = PB2
.EQU txpin = PB1
.EQU sppin = PB0

.EQU noteAb = 9632
.EQU noteBb = 8580
.EQU noteC = 7644
.EQU noteDb = 7215
.EQU noteEb = 6428
.EQU noteF = 5728
.EQU noteAbp = 4816

.EQU onebeat = 3
.EQU twobeat = 6
.EQU threebeat = 9
.EQU fourbeat = 12
.EQU sixbeat = 18
.EQU littlepause = 3

; data stored in SRAM
; these are SRAM addresses
; the start signal length
.EQU startOn = SRAM_START
.EQU startOff = SRAM_START+1
; longest on and off times
.EQU longon = SRAM_START+2
.EQU longoff = SRAM_START+3
.EQU shorton = SRAM_START+4
.EQU shortoff = SRAM_START+5
.EQU onseq1 = SRAM_START+6
.EQU onseq2 = SRAM_START+7
.EQU onseq3 = SRAM_START+8
.EQU onseq4 = SRAM_START+9
.EQU onseq5 = SRAM_START+10
.EQU onseq6 = SRAM_START+11
.EQU onseq7 = SRAM_START+12
.EQU onseq8 = SRAM_START+13
.EQU offseq1 = SRAM_START+14
.EQU offseq2 = SRAM_START+15
.EQU offseq3 = SRAM_START+16
.EQU offseq4 = SRAM_START+17
.EQU offseq5 = SRAM_START+18
.EQU offseq6 = SRAM_START+19
.EQU offseq7 = SRAM_START+20
.EQU offseq8 = SRAM_START+21

.CSEG ; code section
.ORG $0000 ; the start address
    ; interrupt vectors
    rjmp main ; reset vector
    reti ; external interrupt 0
    reti ; pin change
    reti ; timer input capture
    reti ; timer overflow
    reti ; timer compare match A
    reti ; timer compare match B
    reti ; analog comparator
    reti ; watchdog timer
    reti ; Vcc voltage level monitor
    reti ; ADC conversion complete

; interrupt service routines
;isr_pcint:
    ;reti ; return and enable int

main:
    ; set up the stack
    ldi r16, HIGH(RAMEND)
    out SPH, r16
    ldi r16, LOW(RAMEND)
    out SPL, r16

    ; set clock divider
    ldi r16, 0x00 ; clock divided by 1
    ldi r17, 0xD8 ; the key for CCP
    out CCP, r17 ; Configuration Change Protection, allows protected changes
    out CLKPSR, r16 ; sets the clock divider

    ; setup pins
    ldi r16, (1<<txpin)|(1<<sppin)
    out DDRB, r16

    ; setup interrupt
    ldi r16, 1
    out PCICR, r16
    ldi r16, (1<<PCINT2)
    out PCMSK, r16
   
    ; enable sleep
    ldi r16, (1<<SM1)|(1<<SE) ; power down sleep
    out SMCR, r16

    ; delay for a second to let things settle
    ldi r16, 0x1F
    rcall tripledelayr16

    rcall resetData

    sei
   
; main loop
loop:
    ; wait for input
    sleep
    nop
    cli
   
    ; if it was just noise
    sbic PINB, rxpin
    rjmp endLoop

    ; Receive
    rcall receive
    ;rcall adjustdata
   
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    ;wait about 30 seconds
    ldi r16, 0xFF
    rcall tripledelayr16
    ldi r16, 0xFF
    rcall tripledelayr16
    ldi r16, 0xFF
    rcall tripledelayr16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; transmit the sequence
    rcall transmit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; wait
    ldi r16, 0x1F
    rcall tripledelayr16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    rcall play

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
endLoop:
    rcall resetData
    sei
    rjmp loop
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

resetData:
    clr rinLength
    clr rinStop
    ldi rseqbitmask, 1

    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
receive:
    ; at this point we are in the start bit
    ; wait for rise
    rcall timeOn
    sts startOn, rrxtimer

    ; wait for fall
    rcall timeOff
    sts startOff, rrxtimer

    ; time the first bit
    rcall timeOn
    sbrc rinStop, 0
    rjmp finishedReceiving
    ldi r18, 1
    sts onseq1, r18
    sts longon, rrxtimer
    sts shorton, rrxtimer

    rcall timeOff
    sbrc rinStop, 0
    rjmp finishedreceiving
    ldi r18, 1
    sts offseq1, r18
    sts longoff, rrxtimer
    sts shortoff, rrxtimer

    inc rinlength
    lsl rseqbitmask

    ; time the rest of the bits
receiveBits:
    rcall timeOn

    sbrc rinStop, 0
    rjmp finishedReceiving

    ; load up the current sequence
    lds rtxonseq, onseq1
    lds rtxoffseq, offseq1
    cpi rinLength, 8
    brlo sequenceloaded
    lds rtxonseq, onseq2
    lds rtxoffseq, offseq2
    cpi rinLength, 16
    brlo sequenceloaded
    lds rtxonseq, onseq3
    lds rtxoffseq, offseq3
    cpi rinLength, 24
    brlo sequenceloaded
    lds rtxonseq, onseq4
    lds rtxoffseq, offseq4
    cpi rinLength, 32
    brlo sequenceloaded
    lds rtxonseq, onseq5
    lds rtxoffseq, offseq5
    cpi rinLength, 40
    brlo sequenceloaded
    lds rtxonseq, onseq6
    lds rtxoffseq, offseq6
    cpi rinLength, 48
    brlo sequenceloaded
    lds rtxonseq, onseq7
    lds rtxoffseq, offseq7
    cpi rinLength, 56
    brlo sequenceloaded
    lds rtxonseq, onseq8
    lds rtxoffseq, offseq8

sequenceloaded:
   
    ; check against longest
    lds rlongshort, longon
    cp rlongshort, rrxtimer
    ;not longer
    brsh notlonger
    ;longer
    mov r18, rlongshort
    lsr r18
    add r18, rlongshort
    cp rrxtimer, r18
    sbrs rinstop, 1
    ;new 1 level (more than 1.5*long)
    brsh newonelevel
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;just a little longer. set as longest and set 1
setlongestandsetoneon:
    sts longon, rrxtimer
setoneon:
    or rtxonseq, rseqbitmask
    rjmp onbitdone
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
newonelevel:
    sbr rinstop, 2
    ; all previous bits must be zero
    clr rtxonseq
    sts onseq1, rtxonseq
    sts onseq2, rtxonseq
    sts onseq3, rtxonseq
    sts onseq4, rtxonseq
    sts onseq5, rtxonseq
    sts onseq6, rtxonseq
    sts onseq7, rtxonseq
    sts onseq8, rtxonseq

    rjmp setlongestandsetoneon
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
notlonger:
    ; compare against shortest
    lds rlongshort, shorton
    cp rlongshort, rrxtimer
    brlo notlongersetvalue
    sts shorton, rrxtimer
notlongersetvalue:
    ;if much shorter than longest
    lds r18, longon
    mov r17, r18
    lsr r18
    lsr r18
    sub r17, r18
    cp r17, rrxtimer
    ;zero bit if less than 0.75*long
    brlo setoneon

setzeroon:
    sbr rinstop, 2
    mov r17, rseqbitmask
    com r17
    and rtxonseq, r17

onbitdone:
    ; the bit is set, now for the off time

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   
    rcall timeOff

    sbrc rinStop, 0
    rjmp offbitdone

    ; check against longest
    lds rlongshort, longoff
    cp rlongshort, rrxtimer
    ;not longer
    brsh notlongeroff
    ;longer
    mov r18, rlongshort
    lsr r18
    add r18, rlongshort
    cp rrxtimer, r18
    sbrs rinstop, 2
    ;new 1 level (more than 1.5*long)
    brsh newoneleveloff
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;just a little longer. set as longest and set 1
setlongestandsetoneoff:
    sts longoff, rrxtimer
setoneoff:
    or rtxoffseq, rseqbitmask
    rjmp offbitdone
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
newoneleveloff:
    sbr rinstop, 4

    clr rtxoffseq
    sts offseq1, rtxoffseq
    sts offseq2, rtxoffseq
    sts offseq3, rtxoffseq
    sts offseq4, rtxoffseq
    sts offseq5, rtxoffseq
    sts offseq6, rtxoffseq
    sts offseq7, rtxoffseq
    sts offseq8, rtxoffseq

    rjmp setlongestandsetoneoff
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
notlongeroff:
    ; compare against shortest
    lds rlongshort, shortoff
    cp rlongshort, rrxtimer
    brlo notlongersetvalueoff
    sts shortoff, rrxtimer
notlongersetvalueoff:
    ;if much shorter than longest
    lds r18, longoff
    mov r17, r18
    lsr r18
    lsr r18
    sub r17, r18
    cp r17, rrxtimer
    ;zero bit if less than 0.75*long
    brlo setoneoff

setzerooff:
    sbr rinstop, 4
    mov r17, rseqbitmask
    com r17
    and rtxoffseq, r17

offbitdone:
    ; store the sequence
    cpi rinLength, 8
    brlo stsseq1
    cpi rinLength, 16
    brlo stsseq2
    cpi rinLength, 24
    brlo stsseq3
    cpi rinLength, 32
    brlo stsseq4
    cpi rinLength, 40
    brlo stsseq5
    cpi rinLength, 48
    brlo stsseq6
    cpi rinLength, 56
    brlo stsseq7
    rjmp stsseq8

stsseq1:
    sts onseq1, rtxonseq
    sts offseq1, rtxoffseq
    rjmp sequencestored
stsseq2:
    sts onseq2, rtxonseq
    sts offseq2, rtxoffseq
    rjmp sequencestored
stsseq3:
    sts onseq3, rtxonseq
    sts offseq3, rtxoffseq
    rjmp sequencestored
stsseq4:
    sts onseq4, rtxonseq
    sts offseq4, rtxoffseq
    rjmp sequencestored
stsseq5:
    sts onseq5, rtxonseq
    sts offseq5, rtxoffseq
    rjmp sequencestored
stsseq6:
    sts onseq6, rtxonseq
    sts offseq6, rtxoffseq
    rjmp sequencestored
stsseq7:
    sts onseq7, rtxonseq
    sts offseq7, rtxoffseq
    rjmp sequencestored
stsseq8:
    sts onseq8, rtxonseq
    sts offseq8, rtxoffseq

sequencestored:
    ; the bit is set, now update count and bitmask and do the next bit
    inc rinlength
    cpi rinlength, 64
    brsh finishedreceiving
    sbrc rinstop, 0
    rjmp finishedreceiving

    lsl rseqbitmask
    brne gobacktoreceivebits
    ldi rseqbitmask, 1
gobacktoreceivebits:
    rjmp receivebits
   
finishedReceiving:
    ret

timeOn:
    ; each tic is 400 cycles(50us) timeout at 12ms
    ldi rrxtimer, 0x00
timeOnLoop:
    ldi r16, 131 ; 393 cycles
timeOnDelay:
    subi r16, 1
    brne timeOnDelay

    inc rrxtimer
    cpi rrxtimer, 0xFF
    breq escapeReceive
    sbis PINB, rxpin
    rjmp timeOnLoop
    ret

timeOff:
    ; each tic is 400 cycles(50us) timeout at 12ms
    ldi rrxtimer, 0x00
timeOffLoop:
    ldi r16, 131 ; 393 cycles
timeOffDelay:
    subi r16, 1
    brne timeOffDelay

    inc rrxtimer
    cpi rrxtimer, 0xFF
    breq escapeReceive
    sbic PINB, rxpin
    rjmp timeOffLoop
    ret

escapeReceive:
    ldi rinStop, 1
    ret

adjustdata:
    ; if not confirmed 1, average long and short
    sbrs rinstop, 1
    rjmp dontaverageon
    lds r16, shorton
    lds r17, longon
    add r17, r16
    lsr r17
    sts shorton, r17
    sts longon, r17

dontaverageon:
    sbrs rinstop, 2
    rjmp dontaverageoff
    lds r16, shortoff
    lds r17, longoff
    add r17, r16
    lsr r17
    sts shortoff, r17
    sts longoff, r17

dontaverageoff:
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
transmit:
    ; start on
    lds rrxtimer, starton
    rcall txtime

    ; start off
    lds rrxtimer, startoff
    rcall offtime

    ; then the data
    ldi rinstop, 0xFF
   
txloadseq1:
    lds rtxonseq, onseq1
    lds rtxoffseq, offseq1
    rjmp txbitloop
txloadseq2:
    lds rtxonseq, onseq2
    lds rtxoffseq, offseq2
    rjmp txbitloop
txloadseq3:
    lds rtxonseq, onseq3
    lds rtxoffseq, offseq3
    rjmp txbitloop
txloadseq4:
    lds rtxonseq, onseq4
    lds rtxoffseq, offseq4
    rjmp txbitloop
txloadseq5:
    lds rtxonseq, onseq5
    lds rtxoffseq, offseq5
    rjmp txbitloop
txloadseq6:
    lds rtxonseq, onseq6
    lds rtxoffseq, offseq6
    rjmp txbitloop
txloadseq7:
    lds rtxonseq, onseq7
    lds rtxoffseq, offseq7
    rjmp txbitloop
txloadseq8:
    lds rtxonseq, onseq8
    lds rtxoffseq, offseq8
    rjmp txbitloop

txbitloop:
    inc rinstop
    cp rinstop, rinlength
    brsh endtransmission

    ; tx on
    lds rrxtimer, shorton
    sbrc rtxonseq, 0
    lds rrxtimer, longon
    rcall txtime

    ; tx off
    lds rrxtimer, shortoff
    sbrc rtxoffseq, 0
    lds rrxtimer, longoff
    rcall offtime

    cpi rinstop, 7
    breq txloadseq2
    cpi rinstop, 15
    breq txloadseq3
    cpi rinstop, 23
    breq txloadseq4
    cpi rinstop, 31
    breq txloadseq5
    cpi rinstop, 39
    breq txloadseq6
    cpi rinstop, 47
    breq txloadseq7
    cpi rinstop, 55
    breq txloadseq8

    lsr rtxonseq
    lsr rtxoffseq
    rjmp txbitloop

endtransmission:
    ret


txtime:
    ldi r17, (1<<txpin)
txtimeLoop:
    ; toggle txpin every 105 cycles
    ; do this 4 times for each tic
    ; use delayr16 with 32 (0x20) for 103 cycles (use 30(0x1E) with other stuff)
    rcall txtoggle
    rcall txtoggle
    rcall txtoggle
    rcall txtoggle

    dec rrxtimer
    brne txtimeLoop

    cbi PORTB, txpin
    ret

txtoggle:
    ldi r16, 0x1B ; use 0x1B for about 100 cycles total.
    rcall delayr16
    in r18, PORTB
    eor r18, r17
    out PORTB, r18
    ret

offtime:
    ; do nothing for rrxtimer * 400 cycles
    ldi r16, 129
    rcall delayr16
    dec rrxtimer
    brne offtime
    ret

play:
    ; load each note and call playnote
    ; note is stored in r17:r16
    ; timing is stored in r18
    ;
    ; delay some time for rests
    ;
    ;notes:
    ;Ab Bb Db Bb F F Eb
    ;Ab Bb Db Bb Eb Eb Db
    ;Ab Bb Db Bb Db Eb C Bb Ab Ab Eb Db
    ;Ab Bb Db Bb F F Eb
    ;Ab Bb Db Bb Ab+ C Db C Bb
    ;Ab Bb Db Bb Db Eb C Bb Ab Ab Eb Db
    ;
    ;freq.
    ;Ab = 415.3
    ;Bb = 466.2
    ;Db = 554.4
    ;F = 698.3
    ;Eb = 622.3
    ;C = 523.3
    ;Ab+ = 830.6
    ;
    ;8MHz, 1prescaler
    ;Ab = 9632
    ;Bb = 8580
    ;Db = 7215
    ;F = 5728
    ;Eb = 6428
    ;C = 7644
    ;Ab+ = 4816

    ; setup timer
    ; CTC with prescaler 1
    ldi r16, (1<<COM0A0)
    out TCCR0A, r16

    rcall playABDB
    rcall playFFE

    rcall playABDB
    ldi rnotelength, twobeat
    rcall playEb
    ldi r16, littlepause
    rcall tripledelayr16
    rcall playEb
    ldi r16, littlepause
    rcall tripledelayr16
    ldi rnotelength, sixbeat
    rcall playDb

    ldi r16, littlepause
    rcall tripledelayr16

    rcall playABDB
    rcall playDECBAAED

    rcall playABDB
    rcall playFFE

    rcall playABDB
    ldi rnotelength, twobeat
    rcall playAbp
    ldi r16, littlepause
    rcall tripledelayr16
    rcall playC
    ldi r16, littlepause
    rcall tripledelayr16
    ldi rnotelength, fourbeat
    rcall playDb
    ldi rnotelength, onebeat
    rcall playC
    rcall playBb

    ldi r16, littlepause
    rcall tripledelayr16

    rcall playABDB
    rcall playDECBAAED

    ret

playFFE:
    ldi rnotelength, twobeat
    rcall playF
    ldi r16, littlepause
    rcall tripledelayr16
    rcall playF
    ldi r16, littlepause
    rcall tripledelayr16
    ldi rnotelength, sixbeat
    rcall playEb
   
    ldi r16, littlepause
    rcall tripledelayr16
    ret

playABDB:
    ldi rnotelength, onebeat
    rcall playAb
    rcall playBb
    rcall playDb
    rcall playBb
    ret

playDECBAAED:
    ldi rnotelength, threebeat
    rcall playDb
    rcall playEb
    ldi rnotelength, threebeat
    rcall playC
    ldi rnotelength, onebeat
    rcall playBb
    ldi rnotelength, twobeat
    rcall playAb
    ldi r16, littlepause
    rcall tripledelayr16
    rcall playAb
    ldi rnotelength, fourbeat
    rcall playEb
    rcall playDb

    ldi r16, littlepause
    rcall tripledelayr16
    ret

playAb:
    ldi r17, HIGH(noteAb)
    ldi r16, LOW(noteAb)
    rcall playnote
    ret

playBb:
    ldi r17, HIGH(noteBb)
    ldi r16, LOW(noteBb)
    rcall playnote
    ret

playC:
    ldi r17, HIGH(noteC)
    ldi r16, LOW(noteC)
    rcall playnote
    ret

playDb:
    ldi r17, HIGH(noteDb)
    ldi r16, LOW(noteDb)
    rcall playnote
    ret

playEb:
    ldi r17, HIGH(noteEb)
    ldi r16, LOW(noteEb)
    rcall playnote
    ret

playF:
    ldi r17, HIGH(noteF)
    ldi r16, LOW(noteF)
    rcall playnote
    ret

playAbp:
    ldi r17, HIGH(noteAbp)
    ldi r16, LOW(noteAbp)
    rcall playnote
    ret

playnote:
    out OCR0AH, r17
    out OCR0AL, r16
    ldi r16, (1<<WGM02)|(1<<CS00) ;this turns it on
    out TCCR0B, r16

    mov r16, rnotelength
    rcall tripledelayr16

    ldi r16, (1<<WGM02) ;this turns it off
    out TCCR0B, r16
    ldi r16, 0
    out PORTB, r16

    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; utilities
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; short delay loop, 3 * r16 + 7 cycles (1~96us)
delayr16:
    subi r16, 1
    brne delayr16
    ret

; long delay loop, 5 * r16 * 0xff * 0xff + 16 cycles (40642~10363361us)
tripledelayr16:
    push r17
    push r18
    ldi r17, 0xFF
    ldi r18, 0xFF
tripledelayr16Loop:
    subi r18, 1
    sbci r17, 0
    sbci r16, 0
    brne tripledelayr16Loop
    pop r18
    pop r17

    ret
