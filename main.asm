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
;;; *
;;; * TIMING ERROR NOTES
;;; *
;;; *   We're counting 59.779459-ish seconds per minute. That's 3586.77-ish
;;; *   seconds per hour, so we need to make up 13-ish seconds an hour. or
;;; *   we can count sub-seconds per minute, and set the prescalar lower...
;;; *
;;; *   ... but instead of that, we're just going to add 13 seconds to the
;;; *   start of every hour. Which will leave us 5.57904 seconds short on a
;;; *   day. So once a day, we'll add 5. We'll drift about 2 minutes a month.
;;; *   Not fantastic, but tolerable.
;;; ************************************************************************
	

;;; ************************************************************************
        udata

save_w	res	1
save_status	res	1
save_pclath	res	1

tmrcnt		res	1	; timer counter
	
brightness	res	1	; 4-bit value for brightness of LED
pulsate		res	1	; information on pulsate status

mode		res	1	; current mode-button setting
	
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

	call	run_clock
	goto	check_int	; be sure to loop in case of missed interrupt

;;; ************************************************************************
;;; * Subroutines
;;; *

;;; ************************************************************************
;;; *
;;; * Make the LED pulsate up/down with successive calls to pulsate_led.

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
;;; *
;;; * add a second to the clock. If it's an hour, add 13 seconds more. If
;;; * it's midnight, add an extra 5 seconds.
;;; *
;;; * if the alarm is going off, then figure out what to do!

run_clock:
	incf	ones_seconds, F
	movfw	ones_seconds
	xorlw	0x0A
	skpz
	return

	;; ones-of-seconds rollover
	clrf	ones_seconds
	incf	tens_seconds, F
	movfw	tens_seconds
	xorlw	0x06
	skpz
	return

	;; 60 seconds hit
	clrf	tens_seconds
	incf	ones_minutes, F
	movfw	ones_minutes
	xorlw	0x0A
	skpz
	goto	check_alarm_and_return

	;; ones-of-minutes rollover
	clrf	ones_minutes
	incf	tens_minutes, F
	movfw	tens_minutes
	xorlw	0x06
	skpz
	goto	check_alarm_and_return

	;; 60 minutes hit
	movlw	0x03		; fudge the missing time-per-hour
	movwf	ones_seconds
	movlw	0x01
	movwf	tens_seconds
	clrf	tens_minutes
	
	incf	ones_hours, F
	movfw	ones_hours
	xorlw	0x0A
	skpz
	goto	check_for_midnight

	;; ones-of-hours rollover
	incf	tens_hours, F
	goto	check_alarm_and_return ; day ends at 24 hours, not 10 or 20...

check_for_midnight:
	movfw	tens_hours
	xorlw	0x02
	skpz
	goto	check_alarm_and_return
	movfw	ones_hours
	xorlw	0x04
	skpz
	goto	check_alarm_and_return

	;; reached the end of the day (24:00:00, which is now 24:00:13).
	clrf	ones_hours
	clrf	tens_hours
	movlw	0x05
	addwf	ones_seconds, F	; add more fudge...
	;; fall through

check_alarm_and_return:	
	;; FIXME: CHECK FOR THE ALARM CONDITION HERE!
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
	bcf	OPTION_REG, PS1	;   9 interrupts per second (9.033, give
	bsf	OPTION_REG, PS0	;   take based on 37kHz clock).
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
	clrf	mode

	clrf	tens_hours
	clrf	ones_hours
	clrf	tens_minutes
	clrf	ones_minutes
	clrf	tens_seconds
	clrf	ones_seconds

	clrf	tens_alarm_hours
	movlw	0x06
	movwf	ones_alarm_hours
	clrf	tens_alarm_minutes
	clrf	ones_alarm_minutes

	movlw	0x0C		; 'C' for 'Current'
	movwf	time_current
	movlw	0x0A
	movwf	time_alarm
	
main_loop:	
	;; look for presses of either button. Delay, and do it again...

	;; The "mode" button is RA<4>, and the "set" button is RA<6>.
	btfsc	PORTA, 4
	call	mode_button
	btfsc	PORTA, 6
	call	set_button

	movlw	0xFA		; delay 250mS
	call	delay_ms
	
	goto main_loop

	;; MODES:[0] C HhMm A HhMm
mode_button:
	incf	mode, F
	movfw	mode
	xorlw	0x0B		; there are 10 modes. If we reach 11, turn off.
	skpnz
	clrf	mode		; set back to mode 0.

	movfw	mode		; mode 0: disable TRISB and return
	xorlw	0x00
	skpnz
	goto	disable_trisb

	;; not mode 0. Figure out what to display and display it!
	movlw	time_current - 1 ; start of our data block
	addwf	mode, W		; add the current mode to it
	movwf	FSR
	movfw	INDF		; grab indirected pointer data

	goto display_digit	; display that digit and return
	
set_button:	
	return	

disable_trisb:
	movlw	0xFF		; set to all INPUTS
        bcf     STATUS, RP1
        bsf     STATUS, RP0     ; TRISB is in page 1
	movwf	TRISB
        bcf     STATUS, RP0     ; back to page 0
	clrf	PORTB
	return	

	
	END
	