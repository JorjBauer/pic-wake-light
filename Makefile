PIC = 16f628a
LINKSCRIPT = /usr/local/share/gputils/lkr/$(PIC).lkr

OBJECTS = delay.o piceeprom.o memory.o

# Keyspan 19-HS serial dongle on MacOS X
#SERIALDEV = /dev/tty.KeySerial1
# other serial dongle on MacOS X
#SERIALDEV = /dev/tty.usbserial
SERIALDEV = `ls /dev/tty.PL2303-*|head -1`

all:main.hex

main.hex:$(OBJECTS) main.o $(LINKSCRIPT)
	gplink --map -c -s $(LINKSCRIPT) -o main.hex $(OBJECTS) main.o

%.o:%.asm
	gpasm -c $<

clean:
	rm -f *~ *.o *.lst *.map *.hex *.cod *.cof

install: main.hex
	picp $(SERIALDEV) $(PIC) -ef && picp $(SERIALDEV) $(PIC) -wc `./perl-flags-generator main.hex` -s -wp main.hex

install-prebuilt:
	picp $(SERIALDEV) $(PIC) -ef && picp $(SERIALDEV) $(PIC) -wc 0x3F00 -s -wp prebuilt.hex

memory.hint:
	./build-hints.pl > memory.hint

disassemble: main.hex
	pic-disassemble -d -D 4 -a -s -I .string -S dummy:\.org:^_ -i main.hex -m main.map -g main.gif

