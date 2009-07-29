
PROGRAM = shotwell
VERSION = 0.1.2
BUILD_ROOT = 1

VALAC = valac
MIN_VALAC_VERSION = 0.7.4
INSTALL_PROGRAM = install
INSTALL_DATA = install -m 644

VALAFLAGS = -g --enable-checking

# defaults that may be overridden by configure.mk
PREFIX=/usr/local
BUILD_RELEASE=1

-include configure.mk

DEFINES=_PREFIX='"$(PREFIX)"' _VERSION='"$(VERSION)"'

SRC_FILES = \
	main.vala \
	AppWindow.vala \
	CollectionPage.vala \
	Thumbnail.vala \
	DatabaseTables.vala \
	ThumbnailCache.vala \
	image_util.vala \
	CollectionLayout.vala \
	PhotoPage.vala \
	Exif.vala \
	Page.vala \
	ImportPage.vala \
	GPhoto.vala \
	SortedList.vala \
	EventsDirectoryPage.vala \
	Dimensions.vala \
	Box.vala \
	Photo.vala \
	Orientation.vala \
	util.vala \
	BatchImport.vala \
	ExportDialog.vala \
	Resources.vala \
	Debug.vala \
	Sidebar.vala \
	EditingTools.vala

VAPI_FILES = \
	libexif.vapi \
	fstream.vapi \
	libgphoto2.vapi

RESOURCE_FILES = \
	photo.ui \
	collection.ui \
	import.ui \
	fullscreen.ui \
	import_queue.ui \
	events_directory.ui \
	event.ui

SRC_HEADER_FILES = \
	gphoto.h

TEXT_FILES = \
	AUTHORS \
	COPYING \
	INSTALL \
	MAINTAINERS \
	NEWS \
	README \
	THANKS

VAPI_DIRS = \
	./src

HEADER_DIRS = \
	./src

LOCAL_PKGS = \
	fstream \

EXT_PKGS = \
	gtk+-2.0 \
	sqlite3 \
	gee-1.0 \
	hal \
	dbus-glib-1 \
	unique-1.0 \
	libexif \
	libgphoto2

EXT_PKG_VERSIONS = \
	gtk+-2.0 >= 2.14.4 \
	sqlite3 >= 3.5.9 \
	gee-1.0 >= 0.1.3 \
	hal >= 0.5.11 \
	dbus-glib-1 >= 0.76 \
	unique-1.0 >= 1.0.0 \
	libexif >= 0.6.16 \
	libgphoto2 >= 2.4.2

PKGS = $(EXT_PKGS) $(LOCAL_PKGS)

ifndef BUILD_DIR
BUILD_DIR=src
endif

EXPANDED_SRC_FILES = $(foreach src,$(SRC_FILES),src/$(src))
EXPANDED_C_FILES = $(foreach src,$(SRC_FILES),$(BUILD_DIR)/$(src:.vala=.c))
EXPANDED_SAVE_TEMPS_FILES = $(foreach src,$(SRC_FILES),$(BUILD_DIR)/$(src:.vala=.vala.c))
EXPANDED_OBJ_FILES = $(foreach src,$(SRC_FILES),$(BUILD_DIR)/$(src:.vala=.o))
EXPANDED_VAPI_FILES = $(foreach vapi,$(VAPI_FILES),src/$(vapi))
EXPANDED_SRC_HEADER_FILES = $(foreach header,$(SRC_HEADER_FILES),src/$(header))
EXPANDED_RESOURCE_FILES = $(foreach res,$(RESOURCE_FILES),ui/$(res))
VALA_STAMP = $(BUILD_DIR)/.stamp

DIST_FILES = Makefile configure $(EXPANDED_SRC_FILES) $(EXPANDED_VAPI_FILES) \
	$(EXPANDED_SRC_HEADER_FILES) $(EXPANDED_RESOURCE_FILES) $(TEXT_FILES) icons/* misc/*

DIST_TAR = $(PROGRAM)-$(VERSION).tar
DIST_TAR_BZ2 = $(DIST_TAR).bz2
DIST_TAR_GZ = $(DIST_TAR).gz
PACKAGE_ORIG_GZ = $(PROGRAM)_$(VERSION).orig.tar.gz

VALA_CFLAGS = `pkg-config --cflags $(EXT_PKGS)` $(foreach hdir,$(HEADER_DIRS),-I$(hdir)) \
	$(foreach def,$(DEFINES),-D$(def))

VALA_LDFLAGS = `pkg-config --libs $(EXT_PKGS)`

# setting CFLAGS in configure.mk overrides build type
ifndef CFLAGS
ifdef BUILD_DEBUG
CFLAGS = -g -O0
else
CFLAGS = -g -O2
endif
endif

all: $(PROGRAM)

clean:
	rm -f $(EXPANDED_C_FILES)
	rm -f $(EXPANDED_SAVE_TEMPS_FILES)
	rm -f $(EXPANDED_OBJ_FILES)
	rm -f $(VALA_STAMP)
	rm -rf $(PROGRAM)-$(VERSION)
	rm -f $(PROGRAM)

cleantemps:
	rm -f $(EXPANDED_C_FILES)
	rm -f $(EXPANDED_SAVE_TEMPS_FILES)
	rm -f $(EXPANDED_OBJ_FILES)
	rm -f $(VALA_STAMP)

package:
	$(MAKE) dist
	cp $(DIST_TAR_GZ) ../$(PACKAGE_ORIG_GZ)
	rm -f $(DIST_TAR_GZ)
	rm -f $(DIST_TAR_BZ2)

dist: $(DIST_FILES)
	mkdir -p $(PROGRAM)-$(VERSION)
	cp --parents $(DIST_FILES) $(PROGRAM)-$(VERSION)
	tar --bzip2 -cvf $(DIST_TAR_BZ2) $(PROGRAM)-$(VERSION)
	tar --gzip -cvf $(DIST_TAR_GZ) $(PROGRAM)-$(VERSION)
	rm -rf $(PROGRAM)-$(VERSION)

distclean: clean
	rm -f configure.mk

install:
	$(INSTALL_PROGRAM) $(PROGRAM) $(DESTDIR)$(PREFIX)/bin
	mkdir -p $(DESTDIR)$(PREFIX)/share/shotwell/icons
	$(INSTALL_DATA) icons/* $(DESTDIR)$(PREFIX)/share/shotwell/icons
	mkdir -p $(DESTDIR)/usr/share/icons/hicolor/scalable/apps
	$(INSTALL_DATA) icons/shotwell.svg $(DESTDIR)/usr/share/icons/hicolor/scalable/apps
	-update-icon-caches $(DESTDIR)/usr/share/icons/hicolor
	mkdir -p $(DESTDIR)$(PREFIX)/share/shotwell/ui
	$(INSTALL_DATA) ui/* $(DESTDIR)$(PREFIX)/share/shotwell/ui
	$(INSTALL_DATA) misc/shotwell.desktop $(DESTDIR)/usr/share/applications
	-update-desktop-database

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/$(PROGRAM)
	rm -fr $(DESTDIR)$(PREFIX)/share/shotwell
	rm -fr $(DESTDIR)/usr/share/icons/hicolor/scalable/apps/shotwell.svg
	rm -f $(DESTDIR)/usr/share/applications/shotwell.desktop
	-update-desktop-database

$(VALA_STAMP): $(EXPANDED_SRC_FILES) $(EXPANDED_VAPI_FILES) $(EXPANDED_SRC_HEADER_FILES) Makefile \
	$(CONFIG_IN)
	@ bash -c "[ '`valac --version`' '>' 'Vala $(MIN_VALAC_VERSION)' ]" || bash -c "[ '`valac --version`' '==' 'Vala $(MIN_VALAC_VERSION)' ]" || ( echo 'Shotwell requires Vala compiler $(MIN_VALAC_VERSION) or greater.  You are running' `valac --version` '\b.'; exit 1 )
ifndef ASSUME_PKGS
ifdef EXT_PKG_VERSIONS
	pkg-config --print-errors --exists '$(EXT_PKG_VERSIONS)'
else ifdef EXT_PKGS
	pkg-config --print-errors --exists $(EXT_PKGS)
endif
endif
	mkdir -p $(BUILD_DIR)
	$(VALAC) --ccode --directory=$(BUILD_DIR) --basedir=src $(VALAFLAGS) \
	$(foreach pkg,$(PKGS),--pkg=$(pkg)) \
	$(foreach vapidir,$(VAPI_DIRS),--vapidir=$(vapidir)) \
	$(foreach def,$(DEFINES),-X -D$(def)) \
	$(foreach hdir,$(HEADER_DIRS),-X -I$(hdir)) \
	$(EXPANDED_SRC_FILES)
	touch $@

# Do not remove hard tab or at symbol; necessary for dependencies to complete.  (Possible make
# bug.)
$(EXPANDED_C_FILES): $(VALA_STAMP)
	@

$(EXPANDED_OBJ_FILES): %.o: %.c $(CONFIG_IN)
	$(CC) -c $(VALA_CFLAGS) $(CFLAGS) -o $@ $<

$(PROGRAM): $(EXPANDED_OBJ_FILES)
	$(CC) $(VALA_LDFLAGS) $(EXPANDED_OBJ_FILES) $(CFLAGS) -o $@

