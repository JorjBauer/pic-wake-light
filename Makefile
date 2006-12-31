SCRIPT = /usr/local/share/gputils/lkr/16f628.lkr

OBJECTS = delay.o globals.o

all:main.hex

main.hex:$(OBJECTS) main.o $(SCRIPT)
	gplink --map -c -s $(SCRIPT) -o main.hex $(OBJECTS) main.o

%.o:%.asm
	gpasm -c $<

clean:
	rm -f *~ *.o *.lst *.map *.hex *.cod *.cof

install: main.hex
	picp /dev/tty.usbserial 16f628 -s -wp main.hex

