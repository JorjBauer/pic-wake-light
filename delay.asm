	Processor	16f628a
	Radix		DEC
	EXPAND

	include		"p16f628a.inc"
	include		"common.inc"

	GLOBAL	delay_ms

;;; ************************************************************************
	udata
delay1	res	1
delay2	res	1
delay3	res	1
	
;;; ************************************************************************
	code
	
;;; ************************************************************************
;;; * delay_ms
;;; *
;;; * Input
;;; *	W:	contains number of milliseconds to delay
;;; *
;;; * This function is tuned for a 2MHz processor. Other speeds will
;;; * need to have the magic constant tweaked.
;;; *
;;; * Each instruction takes (4 / speed) seconds, unless it branches and then
;;; * it's (8 / speed) seconds. So each is about 108.1uS at 37kHz. Multiply by
;;; * 10 should get us into the right ballpark (about 10mS).
;;; * ... and at 2MHz we need about 512 times.
;;; ************************************************************************

	
delay_ms:
	movwf	delay1

loop1:	
	movlw	0x01
	movwf	delay2
	
loop2:	
	movlw	0xFF
	movwf	delay3
	
loop3:
	decfsz	delay3, F
	goto	loop3

	decfsz	delay2, F
	goto	loop2

	decfsz	delay1, F
	goto	loop1

	return
	

	END
	