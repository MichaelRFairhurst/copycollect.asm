gc : gc.o
	ld gc.o -o gc -lc

gc.o : gc.asm
	nasm -f macho64 gc.asm -o gc.o

