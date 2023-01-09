
; Microprocessors laboratory [8607] - Course 3
;             
; Final project
;
; Objetivo : Develop a program which allows to
; analyze, by means of a graph, the charge and
; discharge of a RC which is fed by a signal 
; generated and verified by the same micro.
;
; Authors:
;	Sofía Pistone - 102456
;	Álvaro Scarramberg - 103370
;
; Project submission date : 23-07-2021
;***********************************************************

; 
; Laboratorio de microprocesadores[8607] - Curso 3
;             
; Trabajo Práctico Integrador
;
; Objetivo : Desarrollar un programa el cual permite 
; analizar, mediante un grafico, la carga y descarga
; de un RC el cual es alimentado mediante una señal 
; generada y verificada por el mimsmo micro.
;
; Autores:
;	Sofía Pistone - 102456
;	Álvaro Scarramberg - 103370
;
; Fecha de entrega: 23-07-2021
;***********************************************************

;.include "m328pdef.inc"

; Defino constantes 
.equ baud=8 ;Para tener un baud rate de 115200 con un 
              ;clock de 16MHz se usa este valor

; Definiciones de registros
.def temp=R16
.def contador=R20

; Macros
.macro setStack
	ldi r16, low(@0)
	out SPL, r16
	ldi r16, high(@0)
	out SPH, r16
.endmacro

.dseg
.org SRAM_START

SREG_RAM: .byte 1

.cseg
.org 0x0000
	rjmp	main
.org INT0addr
	rjmp	Handler_Int_Ext0
.org ICP1addr		
	rjmp	Handler_Int_T1_Capt
.org OVF1addr	
	rjmp	Handler_Int_OVF1
.org UTXCaddr
	rjmp	Handler_TXC
.org ADCCaddr
	rjmp	Handler_Int_ADCC

.org INT_VECTORS_SIZE

main: 
	setStack RAMEND
	rcall configurar_puertos
	rcall configurar_serial
	rcall configurar_timers
	rcall configurar_ADC
	rcall configurar_int0

	; Se almacena a SREG en  
	; RAM de forma auxiliar
	in temp, SREG
	sts SREG_RAM, temp

	sei

main_loop:
	sleep
	jmp main_loop

;***********************************************************
configurar_puertos:

	;PB0 como puerto de salida para 
	;poder activar la captura del T1

	in temp, DDRB
	ori temp, (1<<DDB0)         ;salidas
	out DDRB, temp
 
	;PC0 entrada al ADC
 
	in temp, DDRC
	andi temp, ~(1 << DDC0)     ;entradas
	out DDRC, temp

	;PD2 entrada a int0
	;PD6 salida del pwm
	
	in temp, DDRD
	andi temp, ~(1 << DDD2)     ;entradas
	ori temp,   (1 << DDD6)     ;salidas
	out DDRD, temp

	ret

;*************************************************************************
configurar_serial:
	ldi r16, LOW(baud)		
	ldi r17, HIGH(baud)		
	sts UBRR0L, r16	; Cargar el prescaler
	sts UBRR0H, r17	; a UBRR0

	; 8N1: 8 bits de datos
	; sin paridad y 1 bit de stop

	; configurar modo de transmisión: Asincrónico-->UMSEL=00
	; Paridad: desactivada-->UPM0=00
	; stop bits: 1 bit-->USBS0=0
	; Cantidad de bits del mensaje: 8-->UCSZ0=011

	ldi R16, (0<<UMSEL00)|(0<<UPM00)|(0<<USBS0)|(3<<UCSZ00) 
	sts UCSR0C, R16

	; Habilitar transmitter
	ldi R16, (0<<RXEN0) | (1<<TXEN0) | (0<<UCSZ02)
	sts UCSR0B, R16

	; Baudrate = 115200 bit/s --> FT= 11.52kByte/s
	; Un byte tarda en enviarse: TT=86.8us

	; Habilito la interrupción por Tr. completa
	lds R17, UCSR0B
	ori R17, (1<<TXCIE0)	
	sts UCSR0B, R17

	ret

;**************************************************************************
configurar_timers:
	
;--------------------------------------------------------------------------
; TIMER 1 - Modo Fast PWM ---> Genera la señal PWM
;--------------------------------------------------------------------------

	; Se configura al timer 0 en modo Fast PWM
	; Con TOP=OCR0A
		; WGM0 = 111

	; Para obtener el DC del 50%
	; OC0A --> Toggle on compare match
		; COM0A = 01

	; Cada 2 comparaciones se tiene un periodo 
	; de la señal de salida por lo tanto:

	; FPWM =  Fclk / ( 2 * (OCROA+1) * prescaler )

	; OCR0A = 129 - Prescaler=1024 --> FPWM = 60.096 Hz  ERROR = 0.16%

	in temp, TCCR0A 
	andi temp, ~(1<<COM0A1) 
	ori temp, (1<<WGM01)|(1<<WGM00)|(1<<COM0A0) 	
	out TCCR0A, temp

	in temp, TCCR0B
	andi temp, ~(1<<CS01)
	ori temp, (1<<CS02)|(1<<CS00)|(1<<WGM02)
	out TCCR0B, temp

	ldi temp, 129
	out OCR0A, temp

;----------------------------------------------------------------------------
; TIMER 1 - Modo Captura
;----------------------------------------------------------------------------
	clr temp; contador inicializado en 0 
	sts TCNT1H, temp
	sts TCNT1L, temp

; Configuro modo normal (0) (WGM1=0000)
	ldi temp, (0 << WGM11 ) |(0 << WGM10 )
	sts TCCR1A , temp

; Prescaler 1024 - Rising edge 
	ldi temp, (0<<WGM13)|(0<<WGM12)|(1<<CS02)|(0<<CS01)|(1<<CS00)|(1<<ICES1)
	sts TCCR1B, temp

; Habilito interrupción por captura
	ldi temp, (1 << ICIE1 )
	sts TIMSK1, temp

;	ldi temp, 0x01
;	clr r17
;	sts OCR1AH , temp
;	sts OCR1AL , r17

; Habilito la interrupción por overflow

	lds temp, TIMSK1
	ori temp, (1<<TOIE1)
	sts TIMSK1, temp

	ret


;***********************************************************
configurar_ADC:

	; Se necesita que el tiempo que se tarda
	; por conversión sea mayor al tiempo que 
	; se tarda en enviar el resultado

	; TC>TT = 86.8us FC<FT = 11.52kHz
	
	; FC = FADC/13 = FClk/(13*prescaler)
	; Prescaler = 128 --> FC = 9.62kHz < FT --> ok!

	; ADLAR = 1
	; Se usa VCC como REF--> REFS=01
	; Se selecciona el canal 0 --> MUX=0b000 
	lds temp, ADMUX
	andi temp, ~((1<<REFS1)|(1<<MUX2)|(1<<MUX1)|(1<<MUX0))
	ori temp, (1<<REFS0)|(1<<ADLAR)
	sts ADMUX, temp

	; Desactivo los puertos del ADC que no 
	; se utilizan para minimizar el consumo
	lds temp, DIDR0
	andi temp, ~ (1<<ADC0D)
	ori temp, 0b00111110
	sts DIDR0, temp

	; Prescaler=128:                     DPS=111
	; Se habilita al ADC:                ADEN=1
	; Se habilita su interr.:            ADIE=1
	; Se borra el flag:                  ADIF=0
	; Se habilita el disparo automático: ADATE=1
	lds temp, ADCSRA
	andi temp, ~((1<<ADIF))
	ori temp, (1<<ADEN)|(1<<ADATE)|(1<<ADIE)|(1<<ADPS2)|(1<<ADPS0)|(1<<ADPS1)
	sts ADCSRA, temp

	ret

;***********************************************************************
configurar_int0 :	; Se configura por Pin change
	ldi temp, (0 << ISC01 )|(1 << ISC00 )
	sts EICRA , temp

	ldi temp, (1 << INT0 )
	out EIMSK, temp
	
	ret

;***********************************************************
; Rutina que se encarga de comenzar el envío del mensaje
; inicial que indica el resultado de la verificación de
; la señal medida por int0
;
; Se utiliza a T como flag para decidir cual de los 
; mensajes se debe enviar
;
;***********************************************************
Enviar_Mensaje_Inicial:

	; Se verifica con el Flag cual 
	; mensaje se debe enviar
	brts Msj_Frecuencia_Incorrecta

Msj_Frecuencia_Correcta:
	ldi ZH, high(VerificacionCorrecta<<1)
	ldi ZL, low(VerificacionCorrecta<<1)
	rjmp Enviar_Primer_Caracter

Msj_Frecuencia_Incorrecta:
	ldi ZH, high(VerificacionIncorrecta<<1)
	ldi ZL, low(VerificacionIncorrecta<<1)

Enviar_Primer_Caracter:	
	lpm temp, Z+
	sts UDR0, temp

Enviar_Mensaje_Inicial_End:
	ret

;***********************************************************
; Rutina que se encarga de comenzar las conversiones del 
; ADC y el envio de los resultados
;
;***********************************************************
ComenzarTransmision:

	; Realizar la primera conversión del ADC
	lds temp, ADCSRA
	ori temp, (1<<ADSC)
	sts ADCSRA, temp

	ret

;************************************************************************
; Rutina que se encarga de comenzar el conteo y
; activar la interrupcion por captura
;
; Se reinicia T1 ante el primer flanco asc. o desc.
; detectado para comenzar a contar el primer semi-periodo
;
; Uso T como flag para saber si ya comenzó el conteo
;
;************************************************************************
Handler_Int_Ext0:
	push temp
	in temp, SREG
	push temp
	lds temp, SREG_RAM
	out SREG, temp

	brtc comenzar_conteo

; Activar Captura del timer 1
	sbi PINB ,0
	rjmp fin_int

comenzar_conteo:
	clr temp
	sts TCNT1H , temp
	sts TCNT1L , temp
	SET

fin_int:
	in temp, SREG
	sts SREG_RAM, temp
	pop temp
	out SREG, temp
	pop temp
	reti

;****************************************************************************
; Rutina que se encarga de verificar que el el Duty - Cycle y F sean correctos.
;
; Mido 2 semiperiodos, si ambos son iguales entonces el duty cycle es 
; correcto y si ademas el tiempo de duración de estos pertenece a cierto 
; rango se comprueba que la frecuencia también es adecuada.
;
; Uso C como flag para indicar cual de los semi-periodos se está midiendo
;
;****************************************************************************
Handler_Int_T1_Capt:
; guardo registro de estado
	push temp
	in temp, SREG
	push temp
	lds temp, SREG_RAM
	out SREG, temp

; apagar PB0 ( ICP1 )
	sbi PINB ,0

	brcs Almaceno_Semi_Periodo_2

Almaceno_Semi_Periodo_1:
; Leer ICR1L e ICR1H
	lds r24 , ICR1L
	lds r25 , ICR1H
	SEC
	clr temp
	sts TCNT1H , temp
	sts TCNT1L , temp
	rjmp fin_Int_T1_Capt 

Almaceno_Semi_Periodo_2:
	lds r22 , ICR1L
	lds r23 , ICR1H

	; Compruebo la frecuencia con 
	; una tolerancia del 5%
	
	; El semiperiodo debe ser de 8,33ms 
	; --> T/2 e [7.92ms ; 8.75ms ]

verificar_frecuencia:
	; menor a 8,75ms = > ICR1L < 137 si es mayor hay un error
	cpi r24, 137
	brsh error
	; mayor a 7.92ms = > ICR1L > 123 si es menor o igual hay un error
	cpi r24, 123
	brlo error

verificar_DC0:
	; Compruebo si ambos semi-periodos son iguales 
	cp R25, R23
	brne error

	; Se admite una cierta tolerancia: |R24-R22|<7
	; Para los valores esperados es de ~5%

	cp R24, R22
	breq correcto
	brlo verificar_DC2

verificar_DC1:
	sub R24, R22
	cpi R24, 7
	brsh error
	rjmp correcto

verificar_DC2:
	sub R22, R24
	cpi R22, 7
	brsh error

correcto:
	clt
	rjmp Enviar_Verificacion

error:
	set		

Enviar_Verificacion:
	rcall Enviar_Mensaje_Inicial

	; Apago int0
	ldi temp, (0 << INT0 )
	out EIMSK, temp

	; Apago timer1
	ldi contador, (0 << CS02 ) |(0 << CS01 ) |(0 << CS00 )
	sts TCCR1B , contador
	clr temp
	sts TCNT1H , temp
	sts TCNT1L , temp

fin_Int_T1_Capt:
; Recupero registro de estado
	in temp, SREG 
	sts SREG_RAM, temp
	pop temp
	out SREG, temp
	pop temp
	reti


;*************************************************************************
; Handler de la int. por Overflow del timer 1
;
; Si el timer 1 llega a overflow la señal medida tiene un periodo
; demasiado grande por lo que se asume que se tiene un error
;
;*************************************************************************
Handler_Int_OVF1:
	push R16
	push R17
	in R16, SREG
	push R16

	; Indico error con T
	SET
	
	; Envío el mensaje de verificación
	rcall	Enviar_Mensaje_Inicial
	
	; Apago int0
	ldi temp, (0 << INT0 )
	out EIMSK, temp

	; Apago al timer 1
	ldi contador, (0 << CS02 ) |(0 << CS01 ) |(0 << CS00 )
	sts TCCR1B, contador
	clr temp
	sts TCNT1H, temp
	sts TCNT1L, temp


Handler_Int_OVF1_End:
	pop R16
	out SREG, R16
	pop R17
	pop R16

	reti

;*************************************************************************
; Handler de la int. por transmisión completa 
;
; Se encarga de realizar el envio del mensaje de verificación
;
;*************************************************************************
Handler_TXC:
	push R16
	push R17
	in R16, SREG
	push R16

	lpm R16, Z+	; Cargar caracter de la tabla
	cpi R16, 0	; Revisar si se llegó al final del string
	breq Fin_del_mensaje_inicial

	sts UDR0, r16 ; Enviar el caracter
	rjmp Handler_TXC_End 

Fin_del_mensaje_inicial:
    ; Desactivo la interrupción por transmisión completa
	lds R17, UCSR0B
	andi R17, ~(1<<TXCIE0) 
	sts UCSR0B, R17
	rcall ComenzarTransmision

Handler_TXC_End:
	pop R16
	out SREG, R16
	pop R17
	pop R16

	reti

;*********************************************************************
; Handler de la int. por conversión completa del ADC
; 
; Al terminar una conversión simplemente se envía el resultado
;
;*********************************************************************
Handler_Int_ADCC:
	push R17
	push temp
	in temp, SREG
	push temp

	; Enviar la parte alta del ADC
	lds temp, ADCH
	sts	UDR0, temp 

Handler_Int_ADCC_End:
	pop temp
	out SREG, temp
	pop temp
	pop R17

	reti

;***********************************************************

VerificacionCorrecta: .db "** El duty cycle es de 50% y la frecuencia de la señal PWM es de 60Hz **",0,0

VerificacionIncorrecta: .db "** La señal medida no es la esperada **",0

