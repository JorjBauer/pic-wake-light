	GLOBAL	get_digit_segments
	;; return the 7-segment display encoded for the given number (with
	;; a '1' for any segment that should be enabled).
get_digit_segments:	
	ADDWF    PCL, F
	RETLW	0x3F
	RETLW	0x06
	RETLW	0x5B
	RETLW	0x4F
	RETLW	0x66
	RETLW	0x6D
	RETLW	0x7D
	RETLW	0x07
	RETLW	0x7F
	RETLW	0x6F
	RETLW	0x77
	RETLW	0x7C
	RETLW	0x39
	RETLW	0x5E
	RETLW	0x79
	RETLW	0x71

#if SLOW_CLOCK == 0
;;; get_brightness only used for 2MHz xtals (the "fast" setting)
get_brightness:
	ADDWF	PCL, F
	RETLW	0x00
	RETLW	0x10
	RETLW	0x20
	RETLW	0x30
	RETLW	0x40
	RETLW	0x50
	RETLW	0x60
	RETLW	0x70
	RETLW	0x80
	RETLW	0x90
	RETLW	0xA0
	RETLW	0xB0
	RETLW	0xC0
	RETLW	0xD0
	RETLW	0xE0
	RETLW	0XFF
	RETLW	0XFF
#endif
	