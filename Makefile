CCC=gcc
CCFLAGS=-Wall -Werror -g -I.
SOURCES=    $(wildcard src/*.m) 
OBJECTS=    $(addprefix build/,$(SOURCES:.m=.o))
FRAMEWORKS:= -framework AppKit -framework IOKit -framework Foundation -framework ScriptingBridge
LIBRARIES:= -lobjc
LDFLAGS=$(LIBRARIES) $(FRAMEWORKS)
EXECUTABLE= build/usb-lock
PREFIX=/usr/local

all: $(SOURCES) $(EXECUTABLE)

clean:
	rm -f $(OBJECTS) $(EXECUTABLE)

install: $(EXECUTABLE)
	install -m 0755 $(EXECUTABLE) $(PREFIX)/bin

$(EXECUTABLE): $(OBJECTS)
	$(CCC) -o $@ $(OBJECTS) $(CFLAGS) $(LDFLAGS) -o $(EXECUTABLE)

$(OBJECTS) : $(SOURCES)
	mkdir -p $(dir $@)
	$(CCC) $(CCFLAGS) -c -o $@ $^

.PHONY: install
