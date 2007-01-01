        Processor       16f628a
	Radix           DEC
	EXPAND

        include         "p16f628a.inc"

        GLOBAL  arg1
        GLOBAL  arg2
        GLOBAL  temp1
        GLOBAL  temp2

	GLOBAL	time_current
	GLOBAL	tens_hours
	GLOBAL	ones_hours
	GLOBAL	tens_minutes
	GLOBAL	ones_minutes

	GLOBAL	time_alarm
	GLOBAL	tens_alarm_hours
	GLOBAL	ones_alarm_hours
	GLOBAL	tens_alarm_minutes
	GLOBAL	ones_alarm_minutes
	
	GLOBAL	time_error
	GLOBAL	tens_error
	GLOBAL	ones_error
	
	GLOBAL	tens_seconds
	GLOBAL	ones_seconds
;;; ; ************************************************************************
        udata
arg1    res     1
arg2    res     1

temp1   res     1
temp2   res     1
;;; ; ************************************************************************

	;; the time data is accessed via INDF -- so order is important

time_current	res	1
tens_hours	res	1
ones_hours	res	1
tens_minutes	res	1
ones_minutes	res	1

time_alarm	res	1
tens_alarm_hours	res	1
ones_alarm_hours	res	1
tens_alarm_minutes	res	1
ones_alarm_minutes	res	1

time_error	res	1
tens_error	res	1
ones_error	res	1
	
	;; yes, we need these AFTER the alarm time!
tens_seconds	res	1
ones_seconds	res	1


	END
	