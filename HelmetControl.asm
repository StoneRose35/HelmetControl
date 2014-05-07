/*
 * HelmetControl.asm
 *
 *  Created: 14.11.2013 23:21:52
 *   Author: fuerh_000
 * Connection: LED drivers are on PORTA:PORTC with PORTA corresponding to the first entry of a program value number
 * additional input (from the alesis vortex leds) is on PD0:PD2, 
 * program change up button in on pd3, program change down button is on pd4
 *
 * Architecture:
 * Counter1 is used as a timing counter for the leds, working rougly at 100 Hz
 * using the output compare match A interrupt
 * Counter0 serves as a debounce counter for the buttons,
 * 
 * memory management:
 * all global variables are kept in sram having a clearly labelled address
 * the Data segment is organized as follows:
 * A first block of 2-byte integers hold the memory address offsets of the individual programs
 * the MSB of the integers serves as a end of block flag, 1 means that the current integer is the last
 * offset indicating block, after this block the programs block starts
 * each program consists of a 16-bit integer defining the number of steps in the program, this number must be even
  followed by a block of three bytes in which the first byte holds the duration and the nex bytes the byte pattern to display
  special case: a program with 0 steps behaves specially:
  it reads PD0:2 and converts the bits to the following pattern  PD0 PD0 PD0 PD0 PD0 PD1 PD1 PD1 PD1 PD2 PD2 PD2 PD2 PD2 
  which is then output
 */ 


 // define registers
 .def t1 = r16
 .def t2 = r17
 .def t3 = r18
 .def t4 = r19
 .def t5 = r20
 

 .org 0x000
 jmp reset 
 
 // output compare interrupt address
  .org OC1Aaddr
 jmp counter_interrupt

 // timer 0 overflow interrupt
 .org OVF0addr
 jmp debounce_overflow

 .org 0x038
 reset:
 // initialize stack pointer
 ldi t1, high(RAMEND)
 out SPH, t1
 ldi t1, low(RAMEND)
 out SPL, t1


 // configure PORTA and PORTC for output
 ldi t1,0xFF
 out DDRA,t1
 out DDRC,t1

 // configure PD0:4 as input with PD3:4 having pull-ups enabled
 ldi t1,0xE0
 out DDRD,t1
 ldi t1,0x18
 out PORTD,t1

 // configure main counter
 ldi t1,0x00
 out TCNT1H,t1
 out TCNT1L,t1

 // this value sets the total interval time for the update of the leds
 //roughly 100 Hz (1000000/100/64)
 ldi t1,0x00
 out OCR1AH,t1
 ldi t1,0x9D
 out OCR1AL,t1

 // enabling output compare interrupt a for timer 1 and overflow interrupt for timer 0
 ldi t1,(1<<OCIE1A)|(1<<TOIE0)
 out TIMSK,t1
 
 // this starts the counter
ldi t1,0x03
 out TCCR1B,t1

 // reset the ram values
 ldi t1,0x00
 sts program_counter,t1
 sts pulses_counter,t1
 sts program_index,t1
 ldi t1,0x03
 sts program_index+1,t1
 ldi t1,0x00
 sts old_programup,t1
 sts old_programdown,t1
 // enable interrupts
 sei
 
 //************************
 //************************
 //   main program loop
 //************************
 //************************
main:
// checking state change of program down
in t1,PIND
sbrc t1,3
rjmp reset_debouncecounter_progdown
rjmp check_programdown
main2:
in t1,PIND
sbrc t1,4
rjmp reset_debouncecounter_progup
rjmp check_programup
rjmp main




reset_debouncecounter_progdown:
sts old_programdown,t1
rjmp main2

reset_debouncecounter_progup:
sts old_programup,t1
rjmp main

check_programdown:
in t2,TCCR0
sbrc t2,CS02 // counter is still running, no action
rjmp main2

lds t2,old_programdown //check if state has changed
sbrs t2,3
rjmp switchon_debounce2
sts old_programdown,t1
ldi t1,(1<<CS02)|(1<<CS00)
out TCCR0,t1


// reset program to start
ldi t1,0x00
sts program_counter,t1
sts pulses_counter,t1

// decrease program counter
lds t1,program_index
lds t2,program_index+1
ldi t3,0x01
ldi t4,0x00
sub t2,t3
sbc t1,t4
brcc check_programdown_end
ldi t1,0x00
ldi t2,0x00
check_programdown_end:
sts program_index,t1
sts program_index+1,t2

rjmp main2

switchon_debounce:
sts old_programdown,t1
ldi t1,(1<<CS02)|(1<<CS00)
out TCCR0,t1
rjmp main

switchon_debounce2:
sts old_programdown,t1
ldi t1,(1<<CS02)|(1<<CS00)
out TCCR0,t1
rjmp main2

check_programup:
in t2,TCCR0
sbrc t2,CS02 // counter is still running, no action
rjmp main

lds t2,old_programup //check if state has changed
sbrs t2,4
rjmp switchon_debounce
sts old_programup,t1

ldi t1,(1<<CS02)|(1<<CS00)
out TCCR0,t1

// reset program to start
ldi t1,0x00
sts program_counter,t1
sts pulses_counter,t1

 ldi ZH,high(2*lighting_programs)
 ldi ZL,low(2*lighting_programs)


lds t1,program_index
lds t2,program_index+1
lsl t2
add ZL,t2
adc ZH,t1

lpm R0,Z+
mov t1,R0
sbrs t1,7
rjmp increase_progindex
rjmp main

increase_progindex:
ldi t3,0x01
ldi t4,0x00
lsr t2
add t2,t3
adc t1,t4
sts program_index,t1
sts program_index+1,t2

rjmp main

debounce_overflow:
in t5,SREG
push t1
push t5
ldi t1,0x00
out TCCR0,t1
out TCNT0,t1
pop t5
pop t1
out SREG,t5
reti

 counter_interrupt:
 in t5,SREG
 push t1
 push t2
 push t3 
 push t4
 push t5

 // reset timer 1 counter
  ldi t1,0x00
 out TCNT1H,t1
 out TCNT1L,t1

 lds t3,pulses_counter
 ldi ZH,high(2*lighting_programs)
 ldi ZL,low(2*lighting_programs)
 // add program index
 lds t3,program_index
 lds t2,program_index+1
 lsl t2
 add ZL,t2
 adc ZH,t3

 // read offset address of current program
 lpm R0,Z+
 mov t1,R0
 lpm R0,Z+
 mov t2,R0

 ldi t3,0x7F
 and t1,t3
 ldi ZH,high(2*lighting_programs)
 ldi ZL,low(2*lighting_programs)
 add ZL,t2
 adc ZH,t1
 
 // read number of steps of the program, number of steps is in is t1:t2
 lpm R0,Z+
 mov t1,R0
 lpm R0,Z+
 mov t2,R0
 tst t1
 breq test_lsbyte_for_zero
 rjmp cont4
 test_lsbyte_for_zero:
 tst t2
 breq special_mode
 cont4:
 lds t3,program_counter // get the current program counter then multiply by three

 mov t4,t3
 add t3,t4
 add t3,t4
 ldi t4,0x00

 // add 3*program_counter to the current index (which is now just two bytes after the program start)
 add ZL,t3
 adc ZH,t4

 lpm R0,Z+
 mov t3,R0
 lds t4,pulses_counter
  // increase the pulses counter
 inc t4
 sts pulses_counter,t4

 cp t3,t4 // compare the pulses counter to the number of pulses of the actual step
 brcs increase_program_counter
 rjmp set_leds

 increase_program_counter:
 ldi t4,0x00
 sts pulses_counter,t4
 lds t3,program_counter
 inc t3
 sts program_counter,t3

 dec t2
 cp t2,t3 
 brcs reset_program_counter
 rjmp set_leds

 reset_program_counter:
 ldi t3,0x00
 sts program_counter,t3
 rjmp set_leds
 // compare the program counter with the number of steps in the program

 special_mode: // for vortex

 set_leds:
 lpm R0,Z+
 mov t1,R0
 lpm R0,Z+
 mov t2,R0
 set_leds2:
 out PORTA,t1
 out PORTC,t2
 the_end:
 pop t5
 pop t4
 pop t3
 pop t2
 pop t1
 out SREG,t5
 reti


 lighting_programs:
 // header
 .db 0x00,0x0C// prog 1
 .db 0x00,0x14 // prog 2
 .db 0x00,0x40 //prog 3
 .db 0x00,0x72 // prog 4
 .db 0x00,0x7A // prog 5
 .db 0x80,0x88 //prog 6
 // program 1, length: 8
 .db 0x00,0x02 // number of steps in the program (16bit)
 .db 0x20,0xFF // length of first step followed by value for PORTA the value for PORTC
 .db 0xFF,0x04 // values of portB followed by length of next step
 .db 0x00,0x00 // values of next step 
 // program 2, length: 44
 .db 0x00,0x0E
 .db 0x10,0b00000001,0b00000000,0x10,0b00000010,0b00000000
 .db 0x10,0b00000100,0b00000000,0x10,0b00001000,0b00000000
 .db 0x10,0b00010000,0b00000000,0x10,0b00100000,0b00000000
 .db 0x10,0b01000000,0b00000000,0x10,0b10000000,0b00000000
 .db 0x10,0b00000000,0b00000001,0x10,0b00000000,0b00000010
 .db 0x10,0b00000000,0b00000100,0x10,0b00000000,0b00001000
 .db 0x10,0b00000000,0b00010000,0x10,0b00000000,0b00100000
 // program 3, length: 50 
 .db 0x00,0x10
 .db 0x18,0xFF,0x00,0x30,0x00,0x00
 .db 0x18,0x00,0xFF,0x30,0x00,0x00
 .db 0x28,0xFF,0x00,0x30,0x00,0x00
 .db 0x28,0x00,0xFF,0x30,0x00,0x00
 .db 0x38,0xFF,0x00,0x30,0x00,0x00
 .db 0x38,0x00,0xFF,0x30,0x00,0x00
 .db 0x08,0xFF,0x00,0x30,0x00,0x00
 .db 0x08,0x00,0xFF,0x30,0x00,0x00
 // program 4, length: 8
 .db 0x00,0x02 // number of steps in the program (16bit)
 .db 0x10,0xFF // length of first step followed by value for PORTA the value for PORTC
 .db 0xFF,0x10 // values of portB followed by length of next step
 .db 0x00,0x00 // values of next step 
  // program 5, length: 14
 .db 0x00,0x04 // number of steps in the program (16bit)
 .db 0x08,0b01001010,0x01011010,0x08,0b11011010,0b11010111
 .db 0x08,0b10001001,0b01011101,0x08,0b10001101,0b01110101
 // program 6,length 8
 .db 0x00,0x02 // number of steps in the program (16bit)
 .db 0x20,0xFF // length of first step followed by value for PORTA the value for PORTC
 .db 0xFF,0x20 // values of portB followed by length of next step
 .db 0xFF,0xFF // values of next step 
 .dseg
 .org SRAM_START
 program_index: // program index as msb then lsb
 .byte 2
 program_counter:
 .byte 1
 pulses_counter:
 .byte 1
 old_programup:
 .byte 1
 old_programdown:
 .byte 1


