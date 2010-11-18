LINKSCRIPT = link.lkr

OBJECTS = delay.o globals.o piceeprom.o

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
	picp $(SERIALDEV) 16f628a -ef && picp $(SERIALDEV) 16f628a -wc `./perl-flags-generator main.hex` -s -wp main.hex

copy:
	for i in *.asm *.inc *.lkr; do unixdos $$i /Volumes/share/$$i; done

pull:
	for i in *.asm *.inc *.lkr; do dosunix /Volumes/share/$$i $$i; done
