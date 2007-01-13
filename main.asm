	Processor	16f628a
	Radix		DEC
	EXPAND

	include		"p16f628a.inc"
	include		"common.inc"
	include		"piceeprom.inc"
	include		"globals.inc"
	
	include		"delay.inc"

	__CONFIG ( _CP_OFF & _DATA_CP_OFF & _LVP_OFF & _BODEN_OFF & _MCLRE_OFF & _PWRTE_ON & _WDT_OFF & _XT_OSC )
	;; first version of this used _INTRC_OSC_NOCLKOUT. Turned out to be
	;; unstable based on room temperature. Now using XT_OSC. -- jorj
	
_ResetVector	set	0x00
_InitVector	set	0x04

;;; ************************************************************************
;;; * TIMING ERROR NOTES
;;; *
;;; * prescalar of 1:16 on a 2MHz clock, where we cycle every 250 instead
;;; * of 256 segments, gives us 125 interrupts per second (0x7D).
;;; ************************************************************************
#define INTERRUPTS_PER_SECOND 0x7D
		
#define MODEBUTTON PORTA, 5
#define SETBUTTON PORTA, 4

#define ALARM_IN_MINUTES 0x3C	; how long the alarm light stays on (minutes)
#define MODE_TIMEOUT 0x1E		; how long before 7-seg times out

;;; ************************************************************************
;;; * VARIABLES

	udata

save_w	res	1		; used to save regs in interrupt svc routine
save_status	res	1	; used to save regs in interrupt svc routine
save_pclath	res	1	; used to save regs in interrupt svc routine
tmrcnt		res	1	; counts interrupts to count out whole seconds
	
brightness	res	1	; 4-bit value for brightness of LED
pulsate		res	1	; information on pulsate status (only 1 bit)

mode		res	1	; current mode-button setting
mode_timer	res	1	; how long before 7-segment display times out

alarming	res	1	; alarm state

rollover	res	1	; temporary rollover pointer

#define EEPROM_TENS_ERROR 0x00	; eeprom location 0x00
#define EEPROM_ONES_ERROR 0x01	; eeprom location 0x01
		
;;; ************************************************************************
	code

	ORG	_ResetVector
	goto	Main

	ORG	_InitVector
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
;;; *
;;; * Note that this is a general-purpose interrupt routine, which could be
;;; * used for interrupts other than TMR0. We save the current state of the
;;; * registers and then check for the reason that we're being called. To
;;; * add another interrupt mechanism, we could just check for it and branch.
;;; *
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

;;; ************************************************************************
;;; * INT_TMR0
;;; *
;;; * This is the Timer0 interrupt. It handles all of the clockwork.
	
INT_TMR0:
	bcf	INTCON, T0IF	; turn off interrupt flag

	;; add 6 spare cycles to TMR0 (decreasing its length a bit) because
	;; the clock freq isn't evenly divisible by 256 (into a second), but
	;; works fine if we divide by 250.
	movlw	0x06
	addwf	TMR0, F
	
	incf	tmrcnt, F
	movfw	tmrcnt
	xorlw	INTERRUPTS_PER_SECOND
	skpz
	goto	check_int	; not time yet! Finish up.

	;; it's been a second (within the crystal's accuracy, at least).
	clrf	tmrcnt		; reset the timer loop counter

	;; ACTUAL START OF INTERRUPT 0 PROCESSING (once per second)
	call pulsate_led ; DEBUGGING - FIXME - REMOVE
	
	movwf	mode_timer	; see if the mode timer has expired
	xorlw	0x00
	skpz
	call	mode_timer_check ; only call it if mode_timer != 0

	call	run_clock
	goto	check_int	; be sure to loop in case of missed interrupt

;;; ************************************************************************
;;; * pulsate_led
;;; *
;;; * Make the LED pulsate up/down with successive calls to pulsate_led.
;;; * This was used for initial debugging. I've left it because it's cool. :)

pulsate_led:
	btfss	pulsate, 0	; if bit0 is set, we're pulsating down
	goto	pulsate_up
pulsate_down:
	movfw	brightness
	sublw	0
	skpz
	goto	decrease_brightness
	bcf	pulsate, 0	; set to pulsate up next time
	return
pulsate_up:
	movfw	brightness
	sublw	0x0F
	skpz
	goto	increase_brightness
	bsf	pulsate, 0	; set to pulsate down next time
	return

;;; ************************************************************************
;;; *
;;; * turn off the LED and reset brightness counter.
	
turn_off_led:
	clrf	brightness
	clrf	PORTA
	return
		
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
;;; *	 INPUT:	 number to display is in W
;;; *		sanity-checked (&= 0x0F) just in case.

display_digit:
	andlw	0x0F		; protect from overflow in lookup table
	call	get_digit_segments

	xorlw	0xFF		; invert value; we're using a common-positive
	
	;; And now for something tricky! For our common-positive 7-seg display
	;; we leave the pins floating high-Z ("input mode") to leave the
	;; segment off, and turn on an output of 0 in order to enable the
	;; segment. So we write the data to TRISB, instead of PORTB, and then
	;; clear PORTB to enable 0 on the outputs.
	bcf	STATUS, RP1
	bsf	STATUS, RP0	; TRISB is in page 1
	movwf	TRISB
	bcf	STATUS, RP0	; back to page 0
	clrf	PORTB
	return	

;;; ************************************************************************
;;; *
;;; * check the alarm state, and increase the brightness. We do this once a
;;; * minute while the alarm is going off. Note that we do this before we
;;; * call run_clock, so seconds may be 0 from last run.
;;; * ... only called when secs == 00.
;;; * (the turn_off_alarm entrypoint is also used to force the alarm off.)
run_alarm:
	movfw	alarming
	xorlw	0
	skpnz
	return			; no alarm, so nothing to do.

	incf	alarming, F	; move to next alarm phase

	;; if alarming == 60, then we'll bail (turn off alarm).
	movfw	alarming
	xorlw	ALARM_IN_MINUTES
	skpz
	goto	increase_brightness ; not at alarming == 60, so just inc

	;; turn off brightness, reset alarm state.
turn_off_alarm: 
	clrf	alarming
	goto	turn_off_led	; ... and return.
	
;;; ************************************************************************
;;; *
;;; * add a second to the clock. If it's an hour, add 13 seconds more. If
;;; * it's midnight, add an extra 5 seconds.
;;; *
;;; * if the alarm should go off, then start it as well.

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

	;; 60 seconds hit. Reset it to 00, and run alarm state for next min.
	clrf	tens_seconds
	call	run_alarm
	;; ... then update the minutes and continue the regular clock work.
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

	;; 60 minutes hit. Adjust for the hourly error rate (per config)
	movfw	tens_error
	movwf	tens_seconds
	movfw	ones_error
	movwf	ones_seconds

	;; clear the tens of minutes and continue.
	clrf	tens_minutes
	
	incf	ones_hours, F
	movfw	ones_hours
	xorlw	0x0A
	skpz
	goto	check_for_midnight

	;; ones-of-hours rollover
	clrf	ones_hours
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

	;; reached the end of the day (24:00:00)
	clrf	ones_hours
	clrf	tens_hours
	;; fall through

check_alarm_and_return:
	movfw	ones_hours
	subwf	ones_alarm_hours, W
	skpz
	return			; not the same, so bail

	movfw	tens_hours
	subwf	tens_alarm_hours, W
	skpz
	return			; bail

	movfw	ones_minutes
	subwf	ones_alarm_minutes, W
	skpz
	return			; bail

	movfw	tens_minutes
	subwf	tens_alarm_minutes, W
	skpz
	return			; bail

	;; start off the alarm!
	incf	alarming, F
	goto	increase_brightness ; ... and return when done

;;; ************************************************************************
;;; *
;;; * If the mode button is pressed, then call this. We cycle through the
;;; * 7-segment-display modes, which are:
;;; *	0: off
;;; *	1: C  (stands for "Current")
;;; *	2: clock hours, tens digit
;;; *	3: clock hours, ones digit
;;; *	4: clock minutes, tens digit
;;; *	5: clock minutes, ones digit
;;; *	6: A  (stands for "Alarm")
;;; *	7: alarm hours, tens digit
;;; *	8: alarm hours, ones digit
;;; *	9: alarm minutes, tens digit
;;; *	10: alarm minutes, ones digit
;;; *	11: E (stands for "Error correction")
;;; *	12: EC tens digit
;;; *	13: EC ones digit
;;; *
;;; * Whenever the mode button is pressed, any alarm which is currently going
;;; * off is cancelled. We also start a 30-second timer; if the timer expires
;;; * without another button press, everything is set back to mode 0.
;;; *
;;; * The error correction is a number of seconds that are added to the clock
;;; * at the top of every hour. 0 is probably correct, since we're crystal-
;;; * controlled.

mode_button:
	call	turn_off_alarm	; turn off the alarm if it's going off.
	movlw	MODE_TIMEOUT	; we'll leave the current mode on for 30 secs
	movwf	mode_timer
	
	incf	mode, F		; move to the next mode
	movfw	mode
	xorlw	0x0E		; there are 13 modes. If we reach 14, turn off.
	skpnz
set_mode0:
	clrf	mode		; set back to mode 0.

	movfw	mode		; mode 0: disable TRISB and return
	xorlw	0x00
	skpnz
	goto	disable_trisb

;;; ************************************************************************
;;; *
;;; * show the current mode data on the 7-segment display. Note that we do
;;; * this via INDF (the "pointer" indirect reference register) to keep the
;;; * code simple. That requires that the variables be sequentially allocated
;;; * in RAM. There's nothing currently forcing that to happen; the linker
;;; * just happens to do it correctly at the moment.

display_current_mode:	
	;; not mode 0. Figure out what to display and display it!
	movlw	time_current - 1 ; start of our data block
	addwf	mode, W		; add the current mode to it
	movwf	FSR
	movfw	INDF		; grab indirected pointer data

	goto display_digit	; display that digit and return

;;; ************************************************************************
;;; *
;;; * On a press of the set button, we turn off the alarm and reset the
;;; * mode timer (just like when the mode button is pressed). Then we see
;;; * whether or not our current mode supports being changed. If it does, then
;;; * increment the value by 1 and update the display.
	
set_button:
	call	turn_off_alarm	; turn off the alarm if it's going off.
	movlw	MODE_TIMEOUT	; we'll leave the current mode on for 30 secs
	movwf	mode_timer
	
	;; see what mode we're in. If it's 2, 3, 4, 5 or 7, 8, 9, 10 or
	;; 12 or 13 then increment the digit, roll over to zero. Update the
	;; display.

	movfw	mode
	xorlw	0x00
	skpnz
	return			; if mode == 0, return
	movfw	mode
	xorlw	0x01
	skpnz
	return			; if mode == 1, return
	movfw	mode
	xorlw	0x06
	skpnz
	return			; if mode == 6, return
	movfw	mode
	xorlw	0x0B
	skpnz
	return			; if mode == 11, return

	;; otherwise increment the pointed-to value, rolling over at 10,
	;; update the display, and return

	movlw	time_current - 1 ; start of our data block
	addwf	mode, W		; add the current mode to it
	movwf	FSR
	incf	INDF, F 

	;; figure out the rollover amount. Depends on what mode we're in. Most
	;; roll over at 10, but some roll over at 3 or 6.
	movfw	mode
	xorlw	0x02		; mode 2 rolls over a 3 (tens hours).
	skpnz
	goto	rollover_3
	movfw	mode
	xorlw	0x07		; mode 7 also rolls over at 3 (tens hours alarm).
	skpnz
	goto	rollover_3
	
	movfw	mode
	xorlw	0x04		; modes 4, 9, 12 roll over at 6 (tens of mins, secs)
	skpnz
	goto	rollover_6
	movfw	mode
	xorlw	0x09
	skpnz
	goto	rollover_6
	movfw	mode
	xorlw	0x0C
	skpnz
	goto	rollover_6
	
	;; everything else rolls over at 10 (the majority of cases)
rollover_10:
	movwf	INDF
	xorlw	0x0A
	skpnz
	clrf	INDF		; set back to 0; it rolled over
	goto	write_back_error
rollover_6:
	movwf	INDF
	xorlw	0x06
	skpnz
	clrf	INDF		; set back to 0; it rolled over
	goto	write_back_error
rollover_3:
	movwf	INDF
	xorlw	0x03
	skpnz
	clrf	INDF		; set back to 0; it rolled over
	;; fall through

write_back_error:
	;; if we just changed the tens of error, then write it back to the eeprom
	movwf	mode
	xorlw	0x0C
	skpnz
	call	write_error_tens	

	;; if we just changed the ones of error, then write it back
	movwf	mode
	xorlw	0x0D
	skpnz
	call	write_error_ones
	
	;; all done: go display the new digit and return
	goto display_current_mode

write_error_tens:
	movlw	EEPROM_TENS_ERROR
	movwf	arg2
	movfw	INDF
	call	eep_write
	return
	
write_error_ones:
	movlw	EEPROM_ONES_ERROR
	movwf	arg2
	movfw	INDF
	call	eep_write
	return

disable_trisb:
	movlw	0xFF		; set to all INPUTS
	bcf	STATUS, RP1
	bsf	STATUS, RP0	; TRISB is in page 1
	movwf	TRISB
	bcf	STATUS, RP0	; back to page 0
	clrf	PORTB
	return	

;;; ************************************************************************
;;; *
;;; * check the mode timer (only called when mode_timer != 0). If it reached
;;; * 0 then set back to mode 0 and blank the display.

mode_timer_check:
	decfsz	mode_timer, F
	return
	goto	set_mode0	; if we reached 0, set back to mode0.
			
;;; ************************************************************************
;;; * Main
;;; *
;;; * Main program. Sets up registers, handles main loop. The main loop
;;; * is responsible for detecting button presses; it's a bunch of busy-
;;; * waits with periodic tests for button-down. This means we don't have
;;; * to worry about handling repeats or debounces. Quite simple! The length
;;; * of the busy-wait also determines the repeat speed of holding down the
;;; * button. 250mS was my first guess and it seems okay... -- jorj
;;; ************************************************************************

Main:
	clrwdt
	clrf	INTCON		; turn off interrupts

	bcf	STATUS, RP1
	bsf	STATUS, RP0	; set up the page 1 registers
	bsf	OPTION_REG, NOT_RBPU ;	turn off pullups
	movlw TRISA_DATA
	movwf TRISA
	movlw TRISB_DATA
	movwf TRISB
	bcf	PCON, OSCF	; set internal oscillator to 37kHz
	bcf	OPTION_REG, PSA ; assign prescalar to TMR0
	bcf	OPTION_REG, PS2 ; set PS2..PS0 to 011 for 1:16
	bsf	OPTION_REG, PS1 
	bsf	OPTION_REG, PS0 
	
	bcf	OPTION_REG, T0CS	; set TMR0 to timer mode

	bcf	STATUS, RP0	; set up the page 0 registers
	movlw	0x07		; turn off comparators
	movwf	CMCON
	clrf	PORTA		; set default values on porta, b (== 0)
	clrf	PORTB

	bcf	STATUS, IRP	; indirect addressing to page 0/1, not 2/3

	movlw	0xFA		; 500mS delay
	call	delay_ms
	movlw	0xFA
	call	delay_ms

	;; enable TMR0 interrupts
	bsf	INTCON, T0IE	; enable TMR0
	bsf	INTCON, GIE	; and turn on all interrupts.
	
	banksel PORTA

	;; ***
	;; initialize all variables.
	;; ***
	
	clrf	tmrcnt
	clrf	brightness
	clrf	pulsate
	clrf	mode
	clrf	alarming
	
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

	;; set the default error rate
	movlw	EEPROM_TENS_ERROR
	call	eep_read
	movwf	tens_error
	movlw	EEPROM_ONES_ERROR
	call	eep_read
	movwf	ones_error
	
	;; set the static display values for the 7-seg display
	movlw	0x0C		; 'C' for 'Current'
	movwf	time_current
	movlw	0x0A		; 'A' for 'Alarm'
	movwf	time_alarm
	movlw	0x0E		; 'E' for 'Error'
	movwf	time_error
	
main_loop:	
	;; look for presses of either button. Delay, and do it again...
	btfsc	MODEBUTTON
	call	mode_button
	btfsc	SETBUTTON
	call	set_button

	movlw	0xFA		; delay 250mS
	call	delay_ms
	
	goto main_loop

	
	END
	