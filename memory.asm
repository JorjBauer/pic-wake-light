	include "processor_def.inc"

	GLOBAL	init_memory
	
memory	CODE

	CONSTANT	_block_start = $
check_start_memory:	
	;; this code is self-contained. As long as it doesn't cross a page
	;; boundary, it's fine. It should be able to live in any page.
	
;;; clear all file registers in all banks. This processor has 4 banks.
init_memory:
	bcf	STATUS, RP0
	bcf	STATUS, RP1

clear_next_page:	
	movlw   0x20
	movwf   FSR
clear_next_byte:	
	clrf    INDF
	incf    FSR, F
	btfss   FSR, 7
	goto    clear_next_byte

	btfsc	STATUS, RP0
	goto	roll_to_rp1
	bsf	STATUS, RP0
	goto	clear_next_page
roll_to_rp1
	btfsc	STATUS, RP1
	return			; all done
	bsf	STATUS, RP1
	bcf	STATUS, RP0
	goto	clear_next_page

check_end_memory:

	if ( ((_block_start & 0x1800) >> 11) != (($ & 0x1800) >> 11) )
	ERROR	"memory.asm crosses a page boundary"
	endif
	
	END
	