	include		"processor_def.inc"

	include		"common.inc"
	include		"globals.inc"
	include		"memory.inc"
	
	GLOBAL	delay_ms

;;; ************************************************************************
	code
	
;;; ************************************************************************
;;; * delay_ms
;;; *
;;; * Input
;;; *	W:	contains number of milliseconds to delay
;;; *
;;; * Each instruction takes (4 / speed) seconds, unless it branches and then
;;; * it's (8 / speed) seconds. So each is about 108.1uS at 37kHz.
;;; *
;;; * At 48kHz, each instruction is .0000833 seconds (.083333 mS). 12 cycles
;;; * are exactly 1mS.
;;; *
;;; * At 32.768kHz, each instruction is .0001220703125 seconds. 8 cycles are
;;; * .9765625mS, and 9 are 1.0986328125 mS. 10 are obviously ~1.22mS.
;;; ************************************************************************

	
;;; Inner loop: 2 cycles startup + (3 * delay2)-1
;;; Outer loop: 1 + (((Inner loop's delay) + 3) * delay1) - 1
;;; Total delay: (((3*delay2)+4)*delay1)
;;; 
;;; Target number of inner cycles for one mS: .001/(4/clock speed)
	
delay_ms:

;;; So, taking the total delay formula from above, we can turn it in to this:
#define DELAY2 ((((0.001/(4/CLOCK))-4)/3)+1)

;;; Would be nice to make this check here...
;;; #if (DELAY2 > 255)
;;; #error Delay too long for a one-byte timer!
;;; #endif

	movwf	delay1		; 1 cycle
	
loop1:	
	movlw	0x03		; 1 cycle
	movwf	delay2		; 1 cycle
loop2:
	decfsz	delay2, F	; Inner loop: 3 cycles*delay2-1 cycle
	goto	loop2		;  (1 cycle for decfsz, 2 more for goto)

	decfsz	delay1, F	; 2 cycles (1 from previous decfsz)
	goto	loop1		; 2 cycles

	return			; 3 cycles (2 for goto, 1 from prev. decfsz)

	END
	
