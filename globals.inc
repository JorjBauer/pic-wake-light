;;; *********************************************************************
;;; * Global variables
;;; *

 ;; 1 == 32.768kHz clock, 0 == 2MHz clock
#define SLOW_CLOCK 1

        EXTERN  arg1
        EXTERN  arg2

        EXTERN  temp1
        EXTERN  temp2

	EXTERN time_current
	EXTERN tens_hours
	EXTERN ones_hours
	EXTERN tens_minutes
	EXTERN ones_minutes
	EXTERN tens_seconds
	EXTERN ones_seconds

	EXTERN time_alarm
	EXTERN tens_alarm_hours
	EXTERN ones_alarm_hours
	EXTERN tens_alarm_minutes
	EXTERN ones_alarm_minutes

	EXTERN	time_error
	EXTERN	tens_error
	EXTERN	ones_error

