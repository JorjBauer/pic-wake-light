        Processor       16f628
        Radix           DEC
        EXPAND

        include         "p16f628.inc"
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

brightness	res	1	; 4-bit value for brightness of LED
pulsate		res	1	; information on pulsate status
	
;;; ************************************************************************
        code

        ORG     _ResetVector
        goto    Main

        ORG     _InitVector

;;; ************************************************************************
;;; * INTERRUPT

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

	;; ***###*** FIXME:	 write this!
	call pulsate_led
		
	goto	check_int	; be sure to loop in case of missed interrupt

;;; ************************************************************************
;;; * Subroutines
;;; *

pulsate_led:
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
	sublw	16
	skpz
	goto	increase_brightness
	bsf	pulsate, 0	; set to pulsate down next time
	goto	pulsate_down	; loop back to do the down thing
	
;;; ************************************************************************
;;; *
;;; * Increase LED brightness, unless it's at max.

increase_brightness:
	movfw	brightness
	sublw	16
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
	bcf	OPTION_REG, PSA	; assign prescalar to TMR0
	bcf	OPTION_REG, PS2	; set PS2..PS0 to 010 for 1:8; that means about
	bsf	OPTION_REG, PS1	;   271 interrupts per second (270.996, give
	bcf	OPTION_REG, PS0	;   take based on 37kHz clock).
	bcf	OPTION_REG, T0CS	; set TMR0 to timer mode
	bsf	INTCON, T0IE	; enable TMR0
	bsf	INTCON, GIE	; and turn on all interrupts.
	
        banksel PORTA

main_loop:	
	;; look for presses of either button. Delay, and do it again...
	;; ***###*** FIXME:	 write this
	goto main_loop

	

	END
	