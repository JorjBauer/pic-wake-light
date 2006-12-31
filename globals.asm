        Processor       16f628
	Radix           DEC
	EXPAND

        include         "p16f628.inc"

        GLOBAL  arg1
        GLOBAL  arg2
        GLOBAL  temp1
        GLOBAL  temp2
	GLOBAL	tens_hours
	GLOBAL	ones_hours
	GLOBAL	tens_minutes
	GLOBAL	ones_minutes
	GLOBAL	tens_seconds
	GLOBAL	ones_seconds

;;; ; ************************************************************************
        udata
arg1    res     1
arg2    res     1

temp1   res     1
temp2   res     1
;;; ; ************************************************************************

tens_hours	res	1
ones_hours	res	1
tens_minutes	res	1
ones_minutes	res	1
tens_seconds	res	1
ones_seconds	res	1


	END
	