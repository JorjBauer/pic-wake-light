;;; *********************************************************************
;;; * Global defines
;;; *

;; define the direction of the data registers...
#define TRISA_DATA 0xF0 ; low 4 are output; high 4 are input.
#define TRISB_DATA 0xFF ; set to all input. Yes. See comments re: 7-seg disp

;;; *********************************************************************
;;; * Useful macros:
;;; *
;;; *
;;; * SKPWGT: skip if W greater than
;;; * SKPWLE: skip if W less than
;;; *
;;; * Usage: 
;;; *
;;; * movlw (value1)
;;; * sublw (value2)
;;; * skpwgt            ; will skip if (value1) > (value2)
;;; *

#define SKPWGT  SKPNC
#define skpwgt  skpnc
#define SKPWLE SKPC
#define skpwle skpc
