; 76E003 ADC test program: Reads channel 7 on P1.1, pin 14

$NOLIST
$MODN76E003
$LIST

;  N76E003 pinout:
;                               -------
;       PWM2/IC6/T0/AIN4/P0.5 -|1    20|- P0.4/AIN5/STADC/PWM3/IC3
;               TXD/AIN3/P0.6 -|2    19|- P0.3/PWM5/IC5/AIN6
;               RXD/AIN2/P0.7 -|3    18|- P0.2/ICPCK/OCDCK/RXD_1/[SCL]
;                    RST/P2.0 -|4    17|- P0.1/PWM4/IC4/MISO
;        INT0/OSCIN/AIN1/P3.0 -|5    16|- P0.0/PWM3/IC3/MOSI/T1
;              INT1/AIN0/P1.7 -|6    15|- P1.0/PWM2/IC2/SPCLK
;                         GND -|7    14|- P1.1/PWM1/IC1/AIN7/CLO
;[SDA]/TXD_1/ICPDA/OCDDA/P1.6 -|8    13|- P1.2/PWM0/IC0
;                         VDD -|9    12|- P1.3/SCL/[STADC]
;            PWM5/IC7/SS/P1.5 -|10   11|- P1.4/SDA/FB/PWM1
;                               -------
;

CLK               EQU 16600000       ; MCU frequency in Hz
BAUD              EQU 115200         ; UART baud rate
TIMER1_RELOAD     EQU (0x100-(CLK/(16*BAUD)))
TIMER0_RELOAD_1MS EQU (0x10000-(CLK/1000))

ORG 0x0000
    LJMP main

; Messages
test_message:  DB '--Thermometer---',0
value_message: DB 'Temp =',0

; LCD pins
LCD_RS EQU P1.3
LCD_E  EQU P1.4
LCD_D4 EQU P0.0
LCD_D5 EQU P0.1
LCD_D6 EQU P0.2
LCD_D7 EQU P0.3
TEMP_LIMIT_C EQU 3000   ; 30.00°C (because you multiply by 100)


$NOLIST
$INCLUDE(LCD_4bit.inc)
$LIST

DSEG AT 30H
x:   DS 4
y:   DS 4
bcd: DS 5

BSEG
mf: 	DBIT 1
isF:    DBIT 1   ; 0 = Celsius, 1 = Fahrenheit

$NOLIST
$INCLUDE(math32.inc)
$LIST

;-----------------------------
; Initialize MCU, timers, UART, ADC, pins
;-----------------------------
Init_All:
    ; Configure all GPIO pins as bidirectional
    MOV P3M1,#0x00
    MOV P3M2,#0x00
    MOV P1M1,#0x00
    MOV P1M2,#0x00
    MOV P0M1,#0x00
    MOV P0M2,#0x00

    ; UART init
    ORL CKCON,#0x10
    ORL PCON,#0x80  ; SMOD=1 double baud
    MOV SCON,#0x52
    ANL T3CON,#0b11011111
    ANL TMOD,#0x0F
    ORL TMOD,#0x20   ; Timer1 mode 2
    MOV TH1,#TIMER1_RELOAD
    SETB TR1

    ; Timer0 for delay
    CLR TR0
    ORL CKCON,#0x08
    ANL TMOD,#0xF0
    ORL TMOD,#0x01   ; Timer0 mode1 16-bit

    ; ADC pin P1.1 input
    ORL P1M1,#0b00000010
    ANL P1M2,#0b11111101

    ; ADC init
    ANL ADCCON0,#0xF0
    ORL ADCCON0,#0x07     ; channel 7
    MOV AINDIDS,#0x00
    ORL AINDIDS,#0b10000000
    ORL ADCCON1,#0x01     ; enable ADC

    RET

;-----------------------------
; 1ms wait using Timer0
;-----------------------------
wait_1ms:
    CLR TR0
    CLR TF0
    MOV TH0,#HIGH(TIMER0_RELOAD_1MS)
    MOV TL0,#LOW(TIMER0_RELOAD_1MS)
    SETB TR0
    JNB TF0,$
    RET

; Wait R2 ms
waitms:
    LCALL wait_1ms
    DJNZ R2,waitms
    RET

;-----------------------------
; UART: send character in A
;-----------------------------
putchar:
    JNB TI,$
    CLR TI
    MOV SBUF,A
    RET



;-----------------------------
; Send temperature via UART: Fits Display_formated_BCD
; Expected format on LCD: [bcd+2].[bcd+1][bcd+0]
;-----------------------------

Send_Temp_Serial:
    ; 1. Send Whole Number Part (from bcd+2)
    ; Assuming bcd+2 has Tens in high nibble and Ones in low nibble
    ; Or just a single digit. Let's send both nibbles:
    mov a, bcd+2
    swap a
    anl a, #0x0F
    orl a, #0x30    ; Convert to ASCII
    lcall putchar
    
    mov a, bcd+2
    anl a, #0x0F
    orl a, #0x30
    lcall putchar

    ; 2. Send Decimal Point
    mov a, #'.'
    lcall putchar

    ; 3. Send Fractional Part (from bcd+1 and bcd+0)
    ; To keep Python happy, we send the digits immediately after the dot
    mov a, bcd+1
    swap a
    anl a, #0x0F
    orl a, #0x30
    lcall putchar
    
    mov a, bcd+1
    anl a, #0x0F
    orl a, #0x30
    lcall putchar

    mov a, #' '
    lcall putchar
    jb isF, SendF_Serial
    mov a, #'C'
    sjmp Send_LineEnd
SendF_Serial:
    mov a, #'F'

Send_LineEnd:
    lcall putchar

    ; 5. End of Line (CR + LF)
    mov a, #0x0D
    lcall putchar
    mov a, #0x0A
    lcall putchar
    ret
    
 Display_formated_BCD:
	Set_Cursor(2, 10)
	Display_BCD(bcd+2)
	Display_char(#'.')
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	ret
	
 Debounce:
    MOV R2,#20
    LCALL waitms
    RET

main:
	CLR isF     
	mov sp, #0x7f
	lcall Init_All
    lcall LCD_4BIT
    
    ; initial messages in LCD
	Set_Cursor(1, 1)
    Send_Constant_String(#test_message)
	Set_Cursor(2, 1)
    Send_Constant_String(#value_message)
  
    
Forever:
    
    Check_Button:
    JB  P1.5, NoPress      ; if P1.5 = 1 ? not pressed
    CPL isF                ; toggle C/F mode
    LCALL Debounce
	WaitRelease:
    JNB P1.5, WaitRelease  ; wait until button released
	NoPress:
    
	clr ADCF
	setb ADCS ;  ADC start trigger signal
    jnb ADCF, $ ; Wait for conversion complete
    

    ; Read the ADC result and store in [R1, R0]
    mov a, ADCRH   
    swap a
    push acc
    anl a, #0x0f
    mov R1, a
    pop acc
    anl a, #0xf0
    orl a, ADCRL
    mov R0, A
    
    ; Convert to voltage
	mov x+0, R0
	mov x+1, R1
	mov x+2, #0
	mov x+3, #0
	Load_y(50240) ; VCC voltage measured
	lcall mul32
	Load_y(4095)
	lcall div32
 	Load_y(27300)
 	lcall sub32
    Load_y(100)
   
    lcall mul32
    

	JB isF, ConvertToF
	SJMP SkipF
	
	ConvertToF:
	
	    Load_Y(9)
	    LCALL mul32       
	    Load_Y(5)
	    LCALL div32       
	    Load_Y(320000)
	    LCALL add32       
	
	SkipF:
	

	lcall hex2bcd
	lcall Display_formated_BCD
	lcall Send_Temp_Serial


	Set_Cursor(2,15)
	
	MOV A, #0DFh     
	LCALL ?WriteData
	
	Set_Cursor(2,16)
	JB  isF, ShowF2
	MOV A, #'C'
	SJMP WriteUnit2
	
	ShowF2:
	MOV A, #'F'
	
	WriteUnit2:
	LCALL ?WriteData

	mov R2, #250
	lcall waitms
	mov R2, #250
	lcall waitms
	
	ljmp Forever
	
END
