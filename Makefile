
BISON	   = bison
BISONFLAGS = -g --debug --defines
CFLAGS	   = -g -O0
LDFLAGS	   = -g

.y.c:	
	$(BISON) $(BISONFLAGS) $<

rfmt:	rfmt-scan.o rfmt-gram.o
		$(CC) -o $@ $^ 

rfmt-scan.o:	rfmt-scan.l rfmt-gram.h
rfmt-gram.h:	rfmt-gram.c

clean:
	rm -f rfmt-scan.o rfmt-scan.c rfmt-gram.o rfmt-gram.c rfmt-gram.vcg rfmt rfmt-gram.h