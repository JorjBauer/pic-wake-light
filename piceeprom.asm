        include         "processor_def.inc"

	include		"common.inc"
	include		"globals.inc"
	include		"memory.inc"
	
	GLOBAL	eep_read
	GLOBAL	eep_write

	code
	
;;; ************************************************************************
;;; * eep_read
;;; *
;;; * Input
;;; *	W:	contains address to read
;;; *
;;; * Output
;;; *	W:	contains byte read
;;; ************************************************************************
	
eep_read:
	bsf	STATUS, RP0	; NOTE:	 we're in page 1 now, boys!
	movwf	EEADR
	bsf	EECON1, RD
	movfw	EEDATA
	bcf	STATUS, RP0	; Back to page 0 before returning
	return
	
;;; ************************************************************************
;;; * eep_write
;;; *
;;; * Input
;;; *	W:	contains data to write
;;; *   arg2:	contains address to write
;;; *
;;; * Output
;;; *	W:	contains byte read
;;; ************************************************************************

eep_write:
	movwf	arg1
	btfsc	EECON1, WR	; wait for EECON's write bit to be clear
	goto	eep_write

	movfw	arg2
	movwf	EEADR
	
	movfw	arg1
	movwf	EEDATA

	bcf	STATUS, C	; Use the Carry flag as a test for whether or
	btfsc	INTCON, GIE	; not interrupts were originally enabled so 
	bsf	STATUS, C	; we can put them back afterwards.


	bsf	STATUS, RP0	; Start of magic code from docs; do not alter
	bsf	EECON1, WREN
	bcf	INTCON, GIE
	movlw	0x55
	movwf	EECON2
	movlw	0xAA
	movwf	EECON2
	bsf	EECON1, WR	; End of magic code
	
	bcf	EECON1, WREN	; Disable writes

	bcf	STATUS, RP0
	
	btfsc	STATUS, C	; re-enable interrupts if they had been on
	bsf	INTCON, GIE

	return

	END
	
