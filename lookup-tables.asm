	GLOBAL	get_digit_segments
	;; return the 7-segment display encoded for the given number.
;;; *  0 = a,b,c,e,f,g = 1110111
;;; *  1 = c,f = 0100100
;;; *  2 = a,c,d,e,g = 1011101
;;; *  3 = a,c,d,f,g = 1101101
;;; *  4 = b,c,d,f = 0101110
;;; *  5 = a,b,d,f,g = 1101011
;;; *  6 = a,b,d,e,f,g = 1111011
;;; *  7 = a,c,f = 0100101
;;; *  8 = a,b,c,d,e,f,g = 1111111
;;; *  9 = a,b,c,d,f,g = 1101111
;;; *  A = a,b,c,d,e,f = 0111111
;;; *  B = b,d,e,f,g = 1111010
;;; *  C = a,b,e,g = 1010011
;;; *  D = c,d,e,f,g = 1111100
;;; *  E = a,b,d,e,g = 1011011
;;; *  F = a,b,d,e = 0011011
get_digit_segments:	
	ADDWF    PCL, F
	RETLW	0x77		; 0 = %0111 0111
	RETLW	0x24		; 1 = %0010 0100
	RETLW	0x5D		; 2 = %0101 1101
	RETLW	0x6D		; 3 = %0110 1101
	RETLW	0x2E		; 4 = %0010 1110
	RETLW	0x6B		; 5 = %0110 1011
	RETLW	0x7B		; 6 = %0111 1011
	RETLW	0x25		; 7 = %0010 0101
	RETLW	0x7F		; 8 = %0111 1111
	RETLW	0x6F		; 9 = %0110 1111
	RETLW	0x3F		; A = %0011 1111
	RETLW	0x7A		; B = %0111 1010
	RETLW	0x53		; C = %0101 0011
	RETLW	0x7C		; D = %0111 1100
	RETLW	0x5B		; E = %0101 1011
	RETLW	0x1B		; F = %0001 1011

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
	