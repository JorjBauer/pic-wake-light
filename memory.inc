	extern	init_memory

;;; This is a manual map of all file registers, so that we have control over
;;; the bank alignment. I wish the banks could be individually addressed
;;; (perhaps "udata_bank0") -- then each code chunk could define the page it
;;; wants to work in. But since that doesn't seem to exist, the next best way
;;; to handle the problem seems to be this.

#define	      time_current	0x30
#define	      tens_hours	0x31
#define	      ones_hours	0x32
#define	      tens_minutes	0x33
#define	      ones_minutes	0x34
#define	      time_alarm	0x35
#define	      tens_alarm_hours	0x36
#define	      ones_alarm_hours	0x37
#define	      tens_alarm_minutes	0x38
#define	      ones_alarm_minutes	0x39
#define	      time_error		0x3a
#define	      tens_error		0x3b
#define	      ones_error		0x3c
#define	      tens_seconds		0x3d
#define	      ones_seconds		0x3e

#define	      delay1			0x40
#define	      delay2			0x41
#define	      delay3			0x42

#define mode_change_delay 0x43

;;; service routine variables
#define	      save_w	  0x70
#define	      save_status 0x71
#define	      save_pclath 0x72
;;; counts interrupts, to count out whole seconds
#define	      tmrcnt	  0x73
;;; PWM brightness, from MIN_BRIGHTNESS to MAX_BRIGHTNESS.
#define	      brightness  0x74
;;; pulsate status: 0 is on/off, 1 is test mode
#define	      pulsate	  0x75
;;; current mode-button setting
#define	    mode	0x76
;;; how long before 7-segment display times out
#define mode_timer 0x77
;;; alarm state
#define alarming	0x78
;;; temporary rollover pointer
#define	      rollover 0x79


#define	      arg1     0x7a
#define	      arg2     0x7b
#define	      temp1    0x7c
#define	      temp2    0x7d
