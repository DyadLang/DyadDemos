# Stage 1. Override CC/CFLAGS in the usual make fashion.
CC ?= cc
CFLAGS ?= -O2 -fPIC -Wall -Wextra
ifeq ($(shell uname -s),Darwin)
EXT = dylib
SHARED = -dynamiclib
else
EXT = so
SHARED = -shared
endif

all: build/libtiremodel.$(EXT)

build/libtiremodel.$(EXT): tiremodel.c tiremodel.h
	mkdir -p build
	$(CC) $(CFLAGS) $(SHARED) -o $@ tiremodel.c -lm

.PHONY: all
