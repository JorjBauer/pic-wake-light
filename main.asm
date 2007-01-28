	Processor	16f628a
	Radix		DEC
	EXPAND

	include		"p16f628a.inc"
	include		"common.inc"
	include		"piceeprom.inc"
	include		"globals.inc"
	
	include		"delay.inc"

	__CONFIG ( _CP_OFF & _DATA_CP_OFF & _LVP_OFF & _BODEN_OFF & _MCLRE_OFF & _PWRTE_ON & _WDT_OFF & _LP_OSC )
	;; first version of this used _INTRC_OSC_NOCLKOUT. Turned out to be
	;; unstable based on room temperature. Now using XT_OSC. -- jorj
	;; moved to 32.768kHz low-power oscillator (LP_OSC).
_ResetVector	set	0x00
_InitVector	set	0x04

;;; ************************************************************************
;;; * TIMING ERROR NOTES
;;; *
;;; * prescaler of 1:16 on a 2MHz clock, where we cycle every 250 instead
;;; * of 256 segments, gives us 125 interrupts per second (0x7D). As long as
;;; * we have less than 255 interrupts per second, we can use this for PWM
;;; * on the LED as well.
;;; *
;;; * For 32768Hz clock, we cycle all 256 at a 1:1 prescaler which gives us
;;; * 32 interrupts per second (0x20).
;;; ************************************************************************
#if SLOW_CLOCK
#define INTERRUPTS_PER_SECOND 0x20
#else
#define INTERRUPTS_PER_SECOND 0x7D
#endif

#define MODEBUTTON PORTA, 2
#define SETBUTTON PORTA, 1

#define ALARM_IN_MINUTES 0x3C	; how long the alarm light stays on (minutes)
#define MODE_TIMEOUT 0x1E		; how long before 7-seg times out

#define MIN_BRIGHTNESS 0x00
#define MAX_BRIGHTNESS 0x0F

;;; * possible option_reg settings
#define NO_RBPU 0x80
#define YES_RBPU 0x00
#define NO_INTEDG 0x00
#define YES_INTEDG 0x40
#define T0CS_INTERNAL 0x00
#define T0CS_RA4 0x20
#define T0SE_HIGHTOLOW 0x10
#define T0SE_LOWTOHIGH 0x00
#define PRESCALER_WDT_1		0x08
#define PRESCALER_WDT_2		0x09
#define PRESCALER_WDT_4		0x0A
#define PRESCALER_WDT_8		0x0B
#define PRESCALER_WDT_16	0x0C
#define PRESCALER_WDT_32	0x0D
#define PRESCALER_WDT_64	0x0E
#define PRESCALER_WDT_128	0x0F
#define PRESCALER_TMR0_2	0x08
#define PRESCALER_TMR0_4	0x09
#define PRESCALER_TMR0_8	0x0A
#define PRESCALER_TMR0_16	0x0B
#define PRESCALER_TMR0_32	0x0C
#define PRESCALER_TMR0_64	0x0D
#define PRESCALER_TMR0_128	0x0E
#define PRESCALER_TMR0_256	0x0F


;;; ************************************************************************
;;; * PWM NOTES
;;; *
;;; * PORTB used to be wired exclusively to the 7-segment display, but the 
;;; * hardware PWM is on PORTB<3>. So there are some hacks in here to remap
;;; * B<3> to A<3>. TRISB<3> must be CLEARED at all times for the PWM to work.
;;; *
;;; * To enable PWM, we set the frequency via register PR2. We set the duty
;;; * cycle via CCPR1L and CCP1CON<5><4>. Clear TRISB<3>, set the TMR2 
;;; * prescaler, and enable TMR2 via T2CON.
;;; *
;;; * The PWM frequency is [ (PR2) + 1 ] * 4 * (1/Fosc) * prescaler. So for 
;;; *  a 20MHz xtal, PR2 of 0xFF, and prescaler of 16, that's 1.22kHz.
;;; *
;;; * The duty cycle is controlled by the 10-bit digit consisting of the high 
;;; * 8 bits in CCPR1L, and the low 2 bits in CCP1CON<5> and <4>.
;;; *   duty cycle = (10-bit CCP) * (1/Fosc) * prescaler
;;; *
;;; * The effective pwm resolution (in bits) is log(Fosc / (Fpwm * prescaler)) / log(2)
;;; *  so 5 bits of resolution for 32kHz xtal, PR2 of 0x08.
;;; *
;;; * -- this version uses a 2MHz xtal, PR2=0xFF, PS=1 resulting in almost 2kHz.
;;; *
;;; ************************************************************************

#if SLOW_CLOCK
#define PR2_VALUE 0x08
#else
#define PR2_VALUE 0xFF
#endif

;;; ************************************************************************
;;; * VARIABLES

	udata

save_w	res	1		; used to save regs in interrupt svc routine
save_status	res	1	; used to save regs in interrupt svc routine
save_pclath	res	1	; used to save regs in interrupt svc routine
tmrcnt		res	1	; counts interrupts to count out whole seconds
	
brightness	res	1	; PWM brightness of the LED. 0 is off, and
				; full brightness is INTERRUPTS_PER_SECOND.

pulsate		res	1	; information on pulsate status: <0> is on/off, <1> is test mode
#define PULSATE_DIRECTION pulsate, 0
#define PULSATE_TEST pulsate, 1

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
#ifndef SLOW_CLOCK
	movlw	0x06
	addwf	TMR0, F
#endif
	
	incf	tmrcnt, F
	movfw	tmrcnt
	xorlw	INTERRUPTS_PER_SECOND
	skpz
	goto	check_int	; not time yet! Finish up.

	;; it's been a second (within the crystal's accuracy, at least).
	clrf	tmrcnt		; reset the timer loop counter

	;; if the LED test mode is active, then pulsate the LED.
	btfsc PULSATE_TEST
	call	pulsate_led

	movfw	mode_timer	; see if the mode timer has expired
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
	btfss	PULSATE_DIRECTION	; if bit0 is set, we're pulsating down
	goto	pulsate_up
pulsate_down:
	movfw	brightness
	xorlw	MIN_BRIGHTNESS
	skpz
	goto	decrease_brightness
	bcf	PULSATE_DIRECTION	; set to pulsate up next time
	return
pulsate_up:
	movfw	brightness
	xorlw	MAX_BRIGHTNESS
	skpz
	goto	increase_brightness
	bsf	PULSATE_DIRECTION	; set to pulsate down next time
	return

;;; ************************************************************************
;;; *
;;; * turn off the LED and reset brightness counter.
	
turn_off_led:
	clrf	brightness
	clrf	CCPR1L
	bcf	CCP1CON, CCP1X
	bcf	CCP1CON, CCP1Y
	return
		
;;; ************************************************************************
;;; * increase_brightness (and set_brightness)
;;; *
;;; * Increase LED brightness, unless it's at max.
;;; *
;;; * This is also the entry to set_brightness, the only function that sets
;;; * the LED brightness in the program. It sets the PWM appropriately for the
;;; * given brightness level (0-15).
;;  *
;;; * If we're running with a very fast clock (say, 2MHz) then we call 
;;; * get_brightness to convert it to an appropriate PWM value. The PWM is 
;;; * controlled by a 10-bit value: the high 8 are in CCPR1L, which come from
;;; * get_brightness directly. The low 2 are in [ CCP1X | CCP1Y ], and can be 
;;; * 0 when running at 2MHz. We can also check if the brightness is 0xFF and 
;;; * set the low 2 bits to 1, or something.
;;; *
;;; * When running with a slow clock (32.768kHz), the PWM only has about 5 bits
;;; * of resolution so the lookup table is useless. We use brightness directly,
;;; * and have to set the low 2 bits in CCP1[XY] and the low 2 bits in CCPR1L.

increase_brightness:
	movfw	brightness
	xorlw	MAX_BRIGHTNESS
	skpz
	incf	brightness, F
#if SLOW_CLOCK
;;; set_brightness for 32.768kHz:
set_brightness:
	movfw	brightness
	btfss	brightness, 0
	bcf		CCP1CON, CCP1Y
	btfsc	brightness, 0
	bsf		CCP1CON, CCP1Y
	btfss	brightness, 1
	bcf		CCP1CON, CCP1X
	btfsc	brightness, 1
	bsf		CCP1CON, CCP1X
	
	btfss	brightness, 2
	bcf		CCPR1L, 0
	btfsc	brightness, 2
	bsf		CCPR1L, 0
	btfss	brightness, 3
	bcf		CCPR1L, 1
	btfsc	brightness, 3
	bsf		CCPR1L, 1
	bcf		CCPR1L, 2
	bcf		CCPR1L, 3
	bcf		CCPR1L, 4
	bcf		CCPR1L, 5
	bcf		CCPR1L, 6
	bcf		CCPR1L, 7
	
	return
#else
;;; set_brightness for 2MHz:
set_brightness:
	movfw	brightness
	call	get_brightness	; lookup the right PWM value...
	movwf	CCPR1L		; the low two bits of the PWM are always off. The rest follow brightness.
	bcf	CCP1CON, CCP1X	; brightness == 0 means "clear the bottom 2 bits"
	bcf	CCP1CON, CCP1Y
	return
#endif

;;; ************************************************************************
;;; *
;;; * Decrease LED brightness, unless it's at 0.
	
decrease_brightness:
	movfw	brightness
	xorlw	MIN_BRIGHTNESS
	skpz
	decf	brightness, F
	goto	set_brightness

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
	btfss	TRISB, 3	; TRISB<3> is part of PWM0 now, so if we wanted
	bcf		TRISA, 3	; to change it we need to change TRISA<3> instead.
	btfsc	TRISB, 3	; And we leave TRISB<3> clear when done.
	bsf		TRISA, 3
	bcf		TRISB, 3
	bcf	STATUS, RP0	; back to page 0
	clrf	PORTB
	return	

;;; ************************************************************************
;;; *
;;; * check the alarm state, and increase the brightness. We do this once a
;;; * second while the alarm is going off. Note that we do this before we
;;; * call run_clock, so seconds may be 0 from last run.
;;; * 
;;; * (the turn_off_alarm entrypoint is also used to force the alarm off.)
increase_alarm:
	incf	alarming, F	; move to next alarm phase
	;; if alarm has gone its max length, then we'll bail (turn off alarm).
	movfw	alarming
	xorlw	ALARM_IN_MINUTES
	skpz
	goto	increase_brightness
	;; else fall through: turn off brightness, reset alarm state.
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

	;; 60 seconds hit. Reset it to 00.
	clrf	tens_seconds
	;; ... then update the minutes
	incf	ones_minutes, F
	movfw	ones_minutes
	xorlw	0x0A
	skpz
	return	;not 60 secs, so continue
	
	call	check_alarm_and_return	; at top of every minute, increase alarm if req'd

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
	return

check_alarm_and_return:
	;; if the alarm is already running, then keep running it.
	movfw	alarming
	xorlw	0x00
	skpz
	goto	increase_alarm

	;; otherwise check to see if the alarm needs to start.
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
	goto	increase_alarm 	; and return when done

;;; ************************************************************************
;;; * init_variables
;;; *
;;; * initialize all variables to default values

init_variables:
	call	disable_trisb

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

	;; if the default error rate is invalid, then reset it
	movlw	0x03
	movwf	arg2	; temp variable: if != 0 when done, then EEPROM_*_ERROR is invalid

	movfw	tens_error
	sublw	0x05
	skpwgt				; if tens_error > 0x05, then skip
	bcf		arg2, 0
	
	movfw	ones_error
	sublw	0x09
	skpwgt				; if ones_error > 0x09, then skip
	bcf		arg2, 1

	movfw	arg2		; if arg2 is still set at all, then we need to reset the eeprom
	xorlw	0x00
	skpz
	call	reset_eeprom
	
	;; set the static display values for the 7-seg display
	movlw	0x0C		; 'C' for 'Current'
	movwf	time_current
	movlw	0x0A		; 'A' for 'Alarm'
	movwf	time_alarm
	movlw	0x0E		; 'E' for 'Error'
	movwf	time_error

	movlw	0x02
	movwf	tens_hours
	movlw	0x02
	movwf	ones_hours
	movlw	0x05
	movwf	ones_alarm_hours
	movlw	0x03
	movwf	tens_alarm_minutes
	
	return
	
init_pwm:
	;; enable TMR2 for the PWM (no interrupt)
	clrf	T2CON
	clrf	INTCON
	movlw	PR2_VALUE
	bsf	STATUS, RP0	; set up the page 1 registers
	movwf	PR2		; set timer2 period register
	bcf	STATUS, RP0	; set up the page 0 registers
	clrf	CCPR1L	; set initial duty cycle to 0%
	bcf	CCP1CON, 5
	bcf	CCP1CON, 4
	bcf	STATUS, RP1
	
	bsf	STATUS, RP0	; set up the page 1 registers
	bcf	TRISB, 3	;; enable CCP1 output for PWM
	bcf	STATUS, RP0	; set up the page 0 registers

	movlw	0x0C		; turn on PWM
	movwf	CCP1CON
	movlw	0x04	; prescaler = 1:1, enabled, no postscaler
	movwf	T2CON	;; enable timer, which (finally) enables PWM

	return
	
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
	;; standard initialization for the 16F62[78] series
	clrwdt
	clrf	INTCON		; turn off interrupts
	bcf	STATUS, RP1 ; got, I hate page 2/3 variables. Stay in 0/1.
	bsf	STATUS, RP0	; about to set page1 variables
	movlw TRISA_DATA
	movwf TRISA
	movlw TRISB_DATA
	movwf TRISB
	bcf TRISB, 3    ; (enable PWM explicitly)
	bsf	TRISA, 3	; (and substitute A<3> for B<3>)
    ;; if we needed to set the internal oscillator speed, we'd do it here
    ;; bsf PCON, OSCF ; set for high-speed, clear for low-speed
#if SLOW_CLOCK
	; by setting the prescaler to the WDT, it makes TMR0 use no prescaler
    movlw	NO_RBPU | NO_INTEDG | T0CS_INTERNAL | PRESCALER_WDT_1
#else
    movlw	NO_RBPU | NO_INTEDG | T0CS_INTERNAL | PRESCALER_TMR0_16
#endif
    movwf	OPTION_REG
	bcf	STATUS, RP0	; back to page0 variables
	movlw	0x07		; turn off comparators
	movwf	CMCON
	clrf	PORTA		; set default values on PORTA and PORTB
	clrf	PORTB
	bcf	STATUS, IRP	; indirect addressing to page 0/1, not 2/3
	; end standard init sequence

	movlw	0xFA		; 250mS delay
	call	delay_ms
	movlw	0xFA		; 250mS delay
	call	delay_ms
	movlw	0xFA		; 250mS delay
	call	delay_ms
	movlw	0xFA		; 250mS delay
	call	delay_ms

	call	init_pwm
	
	banksel PORTA

	call	init_variables

	;; enable TMR0 interrupts
	bsf	INTCON, T0IE	; enable TMR0
	bsf	INTCON, GIE	; and turn on all interrupts.

main_loop:
	;; look for presses of either button. Delay, and do it again...
	btfsc	MODEBUTTON
	call	mode_button
	btfsc	SETBUTTON
	call	set_button

	movlw	0xFA		; delay 250mS
	call	delay_ms
	
	goto main_loop

	
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
	xorlw	0x0B	; is it mode 11?
	skpz
	goto	increment_selection	; not mode 11; skip to the normal increment code
	; the 'E' mode (11) is a little strange. We use it to toggle the pulsate test mode.
	btfss	PULSATE_TEST
	goto	setit
	bcf	PULSATE_TEST
	return
setit:
	bsf	PULSATE_TEST
	return

increment_selection:
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
	movfw	INDF
	xorlw	0x0A
	skpnz
	clrf	INDF		; set back to 0; it rolled over
	goto	write_back_error
rollover_6:
	movfw	INDF
	xorlw	0x06
	skpnz
	clrf	INDF		; set back to 0; it rolled over
	goto	write_back_error
rollover_3:
	movfw	INDF
	xorlw	0x03
	skpnz
	clrf	INDF		; set back to 0; it rolled over
	;; fall through

write_back_error:
	;; if we just changed the tens of error, then write it back to the eeprom
	movfw	mode
	xorlw	0x0C
	skpnz
	call	write_error_tens	

	;; if we just changed the ones of error, then write it back
	movfw	mode
	xorlw	0x0D
	skpnz
	call	write_error_ones
	
	;; all done: go display the new digit and return
	goto display_current_mode

;; take the value at *FSR (INDF) and write it into the tens error
write_error_tens:
	movlw	EEPROM_TENS_ERROR
	movwf	arg2
	movfw	INDF
	call	eep_write
	return
	
;; take the value at *FSR (INDF) and write it into the tens error
write_error_ones:
	movlw	EEPROM_ONES_ERROR
	movwf	arg2
	movfw	INDF
	call	eep_write
	return

;; reset the error value and update the EEPROM as well
reset_eeprom:
	clrf	tens_error
	clrf	ones_error

	movlw	EEPROM_TENS_ERROR
	movwf	arg2
	movlw	0x00
	call	eep_write
	movlw	EEPROM_ONES_ERROR
	movwf	arg2
	movlw	0x00
	goto	eep_write	; and return

disable_trisb:
	movlw	0xFF		; set to all INPUTS
	bcf	STATUS, RP1
	bsf	STATUS, RP0	; TRISB is in page 1
	movwf	TRISB
	bcf	TRISB, 3	; ... but we don't care about TRISB<3> (b/c PWM)
	bsf	TRISA, 3	; ... and we do care about TRISA<3> (substitute for B<3>)
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
			

	END
	
