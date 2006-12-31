        Processor       16f628a
        Radix           DEC
        EXPAND

        include         "p16f628a.inc"
        include         "common.inc"
        include         "globals.inc"
        
	include		"delay.inc"

	__CONFIG ( _CP_OFF & _DATA_CP_OFF & _LVP_OFF & _BODEN_OFF & _MCLRE_OFF & _PWRTE_ON & _WDT_OFF & _INTRC_OSC_NOCLKOUT )

_ResetVector	set	0x00
_InitVector	set	0x04

;;; ************************************************************************
        udata

save_w	res	1
save_status	res	1
save_pclath	res	1

tmrcnt		res	1	; timer counter
	
brightness	res	1	; 4-bit value for brightness of LED
pulsate		res	1	; information on pulsate status
	
;;; ************************************************************************
        code

        ORG     _ResetVector
        goto    Main

        ORG     _InitVector
	goto	Interrupt

;;; ************************************************************************
;;; * Lookup Tables
;;; *
;;; * The lookup tables must not be broken by a page boundary, so they're
;;; * safely tucked in here. This also prevents them from affecting the
;;; * allocation of program space (if they had an ORG somewhere in memory,
;;; * any code compiled after that point would continue using later
;;; * program memory... which would result in a big wasted gap in the
;;; * middle somewhere).
;;; ************************************************************************

        include "lookup-tables.asm"
	
;;; ************************************************************************
;;; * INTERRUPT
Interrupt:	
	;; save register variables before anything else
	movwf	save_w
	swapf	STATUS, W	; doesn't modify STATUS -- important
	movwf	save_status
	bcf	STATUS, RP0	; move to bank0
	movf	PCLATH, W
	movwf	save_pclath
	clrf	PCLATH		; set to page 0

check_int:			
	;; Now figure out why we were called. TMR0?
	btfsc	INTCON, T0IF
	goto	INT_TMR0	; yes; branch

	;; not TMR0; restore state and exit

done_int:	
	movf	save_pclath, W
	movwf	PCLATH
	swapf	save_status, W
	movwf	STATUS
	swapf	save_w, F
	swapf	save_w, W	; done this way to preserve STATUS
	retfie

INT_TMR0:
	bcf	INTCON, T0IF	; turn off interrupt flag

	incf	tmrcnt, F
	movfw	tmrcnt
	xorlw	9		; 9 interrupts per second
	skpz
	goto	check_int	; not time yet! Finish up.

	;; it's been a second, more or less. We'll drift 13-ish seconds an hour
	;; because of the clock inaccuracy.
	clrf	tmrcnt		; reset the timer count

		
	;; ***###*** FIXME: do something useful here
	call pulsate_led
	goto	check_int	; be sure to loop in case of missed interrupt

;;; ************************************************************************
;;; * Subroutines
;;; *

;;; ************************************************************************
;;; *
;;; * Make the LED pulsate up/down with successive calls to pulsate_led.

pulsate_led:
	;; DEBUGGING: show the value on the 7-seg (FIXME)
	movfw	brightness
	call	display_digit
	;; END DEBUGGING
	
	btfss	pulsate, 0	; if bit0 is set, we're pulsating down
	goto	pulsate_up
pulsate_down:
	movfw	brightness
	sublw	0
	skpz
	goto	decrease_brightness
	bcf	pulsate, 0	; set to pulsate up next time, and fall thru...
pulsate_up:
	movfw	brightness
	sublw	0x0F
	skpz
	goto	increase_brightness
	bsf	pulsate, 0	; set to pulsate down next time
	goto	pulsate_down	; loop back to do the down thing
	
;;; ************************************************************************
;;; *
;;; * Increase LED brightness, unless it's at max.

increase_brightness:
	movfw	brightness
	sublw	0x0F
	skpz
	goto	_do_inc
	return
_do_inc:
	incf	brightness, F
	movfw	brightness
	movwf	PORTA
	return

;;; ************************************************************************
;;; *
;;; * Decrease LED brightness, unless it's at 0.
	
decrease_brightness:
	movfw	brightness
	sublw	0
	skpz
	goto	_do_dec
	return
_do_dec:
	decf	brightness, F
	movfw	brightness
	movwf	PORTA
	return

;;; ************************************************************************
;;; *
;;; * Put a number on the 7-segment display (valid: 0-F)
;;; *
;;; *    INPUT:	 number to display is in W
;;; *

display_digit:
	andlw	0x0F		; protect from overflow in lookup table
	call	get_digit_segments

	xorlw	0xFF		; invert value; we're using a common-positive
	
	;; And now for something tricky! For our common-positive 7-seg display
	;; we leave the pins floating high-Z ("input mode") to leave the
	;; segment off, and turn on an output of 0 in order to enable the
	;; segment. So we write the data to TRISB, instead of PORTB, and then
	;; clear PORTB to enable 0 on the outputs.
        bcf     STATUS, RP1
        bsf     STATUS, RP0     ; TRISB is in page 1
	movwf	TRISB
        bcf     STATUS, RP0     ; back to page 0
	clrf	PORTB
	return	
		
;;; ************************************************************************
;;; * Main
;;; *
;;; * Main program. Sets up registers, handles main loop.
;;; ************************************************************************

Main:
        clrwdt
        clrf    INTCON          ; turn off interrupts

        bcf     STATUS, RP1
        bsf     STATUS, RP0     ; set up the page 1 registers
        bsf     OPTION_REG, NOT_RBPU ;  turn off pullups
        movlw   TRISA_DATA
        movwf   TRISA
        movlw   TRISB_DATA
        movwf   TRISB
	bcf	PCON, OSCF	; set internal oscillator to 37kHz
	bcf	OPTION_REG, PSA	; assign prescalar to TMR0
	bcf	OPTION_REG, PS2	; set PS2..PS0 to 001 for 1:4; that means about
	bsf	OPTION_REG, PS1	;   9 interrupts per second (9.033, give
	bcf	OPTION_REG, PS0	;   take based on 37kHz clock).
	bcf	OPTION_REG, T0CS	; set TMR0 to timer mode

        bcf     STATUS, RP0     ; set up the page 0 registers
        movlw   0x07		; turn off comparators
        movwf   CMCON
        clrf    PORTA		; set default values on porta, b (== 0)
        clrf    PORTB

        bcf     STATUS, IRP     ; indirect addressing to page 0/1, not 2/3

        movlw   0xFA            ; 500mS delay
        call    delay_ms
        movlw   0xFA
        call    delay_ms

	;; enable TMR0 interrupts
	bsf	INTCON, T0IE	; enable TMR0
	bsf	INTCON, GIE	; and turn on all interrupts.
	
        banksel PORTA

	;; initialize variables
	clrf	tmrcnt
	clrf	brightness
	clrf	pulsate

main_loop:	
	;; look for presses of either button. Delay, and do it again...
	;; ***###*** FIXME:	 write this
	goto main_loop

	

	END
	