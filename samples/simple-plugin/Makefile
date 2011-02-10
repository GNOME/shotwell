
PROGRAM := simple-plugin
VERSION := 0.1.0

all: $(PROGRAM).so

clean:
	rm -f $(PROGRAM).c $(PROGRAM).so

install:
	@ [ `whoami` != "root" ] || ( echo 'Run make install as yourself, not as root.' ; exit 1 )
	mkdir -p ~/.gnome2/shotwell/plugins
	install -m 644 $(PROGRAM).so ~/.gnome2/shotwell/plugins

uninstall:
	@ [ `whoami` != "root" ] || ( echo 'Run make install as yourself, not as root.' ; exit 1 )
	rm -f ~/.gnome2/shotwell/plugins/$(PROGRAM).so

$(PROGRAM).so: $(PROGRAM).vala Makefile
	valac --save-temps --main=dummy_main -X -D_VERSION='"$(VERSION)"' --pkg=shotwell-plugin-dev-1.0 \
		-X --shared -X -fPIC $< -o $@

