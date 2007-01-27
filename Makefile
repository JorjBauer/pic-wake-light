LINKSCRIPT = link.lkr

OBJECTS = delay.o globals.o piceeprom.o

all:main.hex

main.hex:$(OBJECTS) main.o $(LINKSCRIPT)
	gplink --map -c -s $(LINKSCRIPT) -o main.hex $(OBJECTS) main.o

%.o:%.asm
	gpasm -c $<

clean:
	rm -f *~ *.o *.lst *.map *.hex *.cod *.cof

install: main.hex
	picp /dev/tty.usbserial 16f628a -s -wp main.hex

copy:
	for i in *.asm *.inc *.lkr; do unixdos $$i /Volumes/share/$$i; done

pull:
	for i in *.asm *.inc *.lkr; do dosunix /Volumes/share/$$i $$i; done
