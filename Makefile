PROGRAM = shotwell
VERSION = 0.3.1
GETTEXT_PACKAGE = $(PROGRAM)
BUILD_ROOT = 1

VALAC = valac
MIN_VALAC_VERSION = 0.7.7
INSTALL_PROGRAM = install
INSTALL_DATA = install -m 644

# defaults that may be overridden by configure.mk
PREFIX=/usr/local
BUILD_RELEASE=1

SUPPORTED_LANGUAGES=fr
LOCAL_LANG_DIR=locale-langpack
SYSTEM_LANG_DIR=/usr/share/locale-langpack

-include configure.mk

VALAFLAGS = -g --enable-checking --thread $(USER_VALAFLAGS)
DEFINES=_PREFIX='"$(PREFIX)"' _VERSION='"$(VERSION)"' GETTEXT_PACKAGE='"$(GETTEXT_PACKAGE)"' \
     _LANG_SUPPORT_DIR='"$(SYSTEM_LANG_DIR)"'

SRC_FILES = \
	main.vala \
	AppWindow.vala \
	CollectionPage.vala \
	Thumbnail.vala \
	DatabaseTables.vala \
	ThumbnailCache.vala \
	image_util.vala \
	CheckerboardLayout.vala \
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
	Dialogs.vala \
	Resources.vala \
	Debug.vala \
	Sidebar.vala \
	ColorTransformation.vala \
	EditingTools.vala \
	DataObject.vala \
	DataCollection.vala \
	LibraryWindow.vala \
	CameraTable.vala \
	DirectWindow.vala \
	Properties.vala \
	CustomComponents.vala \
	Config.vala \
	Event.vala \
	International.vala \
	Workers.vala

VAPI_FILES = \
	libexif.vapi \
	FStream.vapi \
	libgphoto2.vapi \
	FixedKeyFile.vapi \
	ExtendedPosix.vapi

RESOURCE_FILES = \
	photo.ui \
	collection.ui \
	import.ui \
	fullscreen.ui \
	import_queue.ui \
	events_directory.ui \
	event.ui \
	direct.ui

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
	./src \
	./vapi

HEADER_DIRS = \
	./src

LOCAL_PKGS = \
	FStream \
	FixedKeyFile \
	ExtendedPosix \
	posix

EXT_PKGS = \
	gtk+-2.0 \
	sqlite3 \
	gee-1.0 \
	hal \
	dbus-glib-1 \
	unique-1.0 \
	libexif \
	libgphoto2 \
	gconf-2.0

EXT_PKG_VERSIONS = \
	gtk+-2.0 >= 2.14.4 \
	sqlite3 >= 3.5.9 \
	gee-1.0 >= 0.5.0 \
	hal >= 0.5.11 \
	dbus-glib-1 >= 0.76 \
	unique-1.0 >= 1.0.0 \
	libexif >= 0.6.16 \
	libgphoto2 >= 2.4.2 \
	gconf-2.0 >= 2.24.1

PKGS = $(EXT_PKGS) $(LOCAL_PKGS)

ifndef BUILD_DIR
BUILD_DIR=src
endif

EXPANDED_PO_FILES = $(foreach po,$(SUPPORTED_LANGUAGES),po/$(po).po)
EXPANDED_SRC_FILES = $(foreach src,$(SRC_FILES),src/$(src))
EXPANDED_C_FILES = $(foreach src,$(SRC_FILES),$(BUILD_DIR)/$(src:.vala=.c))
EXPANDED_SAVE_TEMPS_FILES = $(foreach src,$(SRC_FILES),$(BUILD_DIR)/$(src:.vala=.vala.c))
EXPANDED_OBJ_FILES = $(foreach src,$(SRC_FILES),$(BUILD_DIR)/$(src:.vala=.o))
EXPANDED_VAPI_FILES = $(foreach vapi,$(VAPI_FILES),src/$(vapi))
EXPANDED_SRC_HEADER_FILES = $(foreach header,$(SRC_HEADER_FILES),src/$(header))
EXPANDED_RESOURCE_FILES = $(foreach res,$(RESOURCE_FILES),ui/$(res))
VALA_STAMP = $(BUILD_DIR)/.stamp
LANG_STAMP = $(LOCAL_LANG_DIR)/.langstamp

DIST_FILES = Makefile configure $(EXPANDED_SRC_FILES) $(EXPANDED_VAPI_FILES) \
	$(EXPANDED_SRC_HEADER_FILES) $(EXPANDED_RESOURCE_FILES) $(TEXT_FILES) icons/* misc/* \
	$(EXPANDED_PO_FILES) vapi/*

DIST_TAR = $(PROGRAM)-$(VERSION).tar
DIST_TAR_BZ2 = $(DIST_TAR).bz2
DIST_TAR_GZ = $(DIST_TAR).gz
PACKAGE_ORIG_GZ = $(PROGRAM)_`parsechangelog | grep Version | sed 's/.*: //'`.orig.tar.gz

VALA_CFLAGS = `pkg-config --cflags $(EXT_PKGS)` $(foreach hdir,$(HEADER_DIRS),-I$(hdir)) \
	$(foreach def,$(DEFINES),-D$(def))

VALA_LDFLAGS = `pkg-config --libs $(EXT_PKGS)`

# setting CFLAGS in configure.mk overrides build type
ifndef CFLAGS
ifdef BUILD_DEBUG
CFLAGS = -g -O0
else
CFLAGS = -g -O2 -mfpmath=sse -march=nocona
endif
endif

all: $(PROGRAM)

$(LANG_STAMP): $(EXPANDED_PO_FILES)
	$(foreach po,$(SUPPORTED_LANGUAGES),`mkdir -p $(LOCAL_LANG_DIR)/$(po)/LC_MESSAGES ; \
        msgfmt -o $(LOCAL_LANG_DIR)/$(po)/LC_MESSAGES/shotwell.mo po/$(po).po`)
	touch $(LANG_STAMP)

clean:
	rm -f $(EXPANDED_C_FILES)
	rm -f $(EXPANDED_SAVE_TEMPS_FILES)
	rm -f $(EXPANDED_OBJ_FILES)
	rm -f $(VALA_STAMP)
	rm -rf $(PROGRAM)-$(VERSION)
	rm -f $(PROGRAM)
	rm -rf $(LOCAL_LANG_DIR)
	rm -f $(LANG_STAMP)

cleantemps:
	rm -f $(EXPANDED_C_FILES)
	rm -f $(EXPANDED_SAVE_TEMPS_FILES)
	rm -f $(EXPANDED_OBJ_FILES)
	rm -f $(VALA_STAMP)
	rm -f $(LANG_STAMP)

package:
	$(MAKE) dist
	cp $(DIST_TAR_GZ) $(PACKAGE_ORIG_GZ)
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
	$(INSTALL_DATA) misc/shotwell-viewer.desktop $(DESTDIR)/usr/share/applications
	-update-desktop-database
	GCONF_CONFIG_SOURCE=`gconftool-2 --get-default-source` gconftool --makefile-install-rule misc/shotwell.schemas
	killall -HUP gconfd-2
	$(foreach lang,$(SUPPORTED_LANGUAGES),`mkdir -p $(SYSTEM_LANG_DIR)/$(lang)/LC_MESSAGES ; \
        $(INSTALL_DATA) $(LOCAL_LANG_DIR)/$(lang)/LC_MESSAGES/shotwell.mo \
            $(SYSTEM_LANG_DIR)/$(lang)/LC_MESSAGES/shotwell.mo`)

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/$(PROGRAM)
	rm -fr $(DESTDIR)$(PREFIX)/share/shotwell
	rm -fr $(DESTDIR)/usr/share/icons/hicolor/scalable/apps/shotwell.svg
	rm -f $(DESTDIR)/usr/share/applications/shotwell.desktop
	rm -f $(DESTDIR)/usr/share/applications/shotwell-viewer.desktop
	-update-desktop-database
	GCONF_CONFIG_SOURCE=`gconftool-2 --get-default-source` gconftool --makefile-uninstall-rule misc/shotwell.schemas
	killall -HUP gconfd-2
	$(foreach lang,$(SUPPORTED_LANGUAGES),`rm -f $(SYSTEM_LANG_DIR)/$(lang)/LC_MESSAGES/shotwell.mo`)

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

$(EXPANDED_OBJ_FILES): %.o: %.c $(CONFIG_IN) Makefile
	$(CC) -c $(VALA_CFLAGS) $(CFLAGS) -o $@ $<

$(PROGRAM): $(EXPANDED_OBJ_FILES) $(LANG_STAMP)
	$(CC) $(VALA_LDFLAGS) $(EXPANDED_OBJ_FILES) $(CFLAGS) -o $@

