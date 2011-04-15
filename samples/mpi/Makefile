CC = mpicc
CCFLAGS = 
VLIBS = -L/usr/local/apps/vampirtrace/lib -lVT -lnsl -lm -lpthread
LIBS =  -lm
OBJS = hw2.o hw2harness.o


all: hw2

hw2: $(OBJS)
	$(CC) $(CCFLAGS) -o hw2 $(OBJS) $(LIBS)

hw2_v4: $(OBJS)
	$(CC) $(CCFLAGS) -o hw2_v4 $(OBJS) $(VLIBS)

hw2_v16: $(OBJS)
	$(CC) $(CCFLAGS) -o hw2_v16 $(OBJS) $(VLIBS)

clean:
	-rm $(OBJS)

.c.o:;  $(CC) $(CCFLAGS) -c $<
