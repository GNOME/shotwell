PROGRAM = shotwell
all: $(PROGRAM)

VERSION = 0.4.2
GETTEXT_PACKAGE = $(PROGRAM)
BUILD_ROOT = 1

VALAC = valac
MIN_VALAC_VERSION = 0.7.9
INSTALL_PROGRAM = install
INSTALL_DATA = install -m 644

# defaults that may be overridden by configure.mk
PREFIX=/usr/local
SCHEMA_FILE_DIR=/etc/gconf/schemas
BUILD_RELEASE=1

UNAME := $(shell uname)
SYSTEM := $(UNAME:MINGW32_%=MinGW)

ifeq "$(SYSTEM)" "Linux"
  LINUX = 1
endif

ifeq "$(SYSTEM)" "MinGW"
  WINDOWS = 1
endif

ifeq "$(SYSTEM)" "Darwin"
  MAC = 1
endif

-include configure.mk

VALAFLAGS = -g --enable-checking --thread $(USER_VALAFLAGS)
DEFINES=_PREFIX='"$(PREFIX)"' _VERSION='"$(VERSION)"' GETTEXT_PACKAGE='"$(GETTEXT_PACKAGE)"' \
     _LANG_SUPPORT_DIR='"$(SYSTEM_LANG_DIR)"'

SUPPORTED_LANGUAGES=fr de it pl et sv sk lv pt bg
LOCAL_LANG_DIR=locale-langpack
SYSTEM_LANG_DIR=$(DESTDIR)$(PREFIX)/share/locale

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
	Workers.vala \
	system.vala \
	AppDirs.vala \
	PixbufCache.vala \
	WebConnectors.vala \
	FacebookConnector.vala \
	CommandManager.vala \
	Commands.vala \
	SlideshowPage.vala \
	LibraryFiles.vala \
    FlickrConnector.vala

ifndef LINUX
SRC_FILES += \
    GConf.vala
endif

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
	./vapi

HEADER_DIRS = \
	./vapi

LOCAL_PKGS = \
	FStream \
	FixedKeyFile \
	ExtendedPosix \
	posix

EXT_PKGS = \
	atk \
	gdk-2.0 \
	gee-1.0 \
	gtk+-2.0 \
	libexif \
	sqlite3
	
ifdef LINUX
EXT_PKGS += \
	dbus-glib-1 \
	gconf-2.0 \
	hal \
	libgphoto2 \
	libsoup-2.4 \
	libxml-2.0 \
	unique-1.0 \
	webkit-1.0
endif

ifdef MAC
EXT_PKGS += \
    ige-mac-integration
endif

EXT_PKG_VERSIONS = \
	gee-1.0 >= 0.5.0 \
	gtk+-2.0 >= 2.14.4 \
	libexif >= 0.6.16 \
	sqlite3 >= 3.5.9
	
ifdef LINUX
EXT_PKG_VERSIONS += \
	dbus-glib-1 >= 0.76 \
	gconf-2.0 >= 2.22.0 \
	hal >= 0.5.11 \
	libgphoto2 >= 2.4.2 \
	libsoup-2.4 >= 2.26.0 \
	libxml-2.0 >= 2.6.32 \
	unique-1.0 >= 1.0.0 \
	webkit-1.0 >= 1.1.5
endif

PKGS = $(EXT_PKGS) $(LOCAL_PKGS)

ifndef BUILD_DIR
BUILD_DIR=src
endif

EXPANDED_PO_FILES = $(foreach po,$(SUPPORTED_LANGUAGES),po/$(po).po)
EXPANDED_SRC_FILES = $(foreach src,$(SRC_FILES),src/$(src))
EXPANDED_C_FILES = $(foreach src,$(SRC_FILES),$(BUILD_DIR)/$(src:.vala=.c))
EXPANDED_SAVE_TEMPS_FILES = $(foreach src,$(SRC_FILES),$(BUILD_DIR)/$(src:.vala=.vala.c))
EXPANDED_OBJ_FILES = $(foreach src,$(SRC_FILES),$(BUILD_DIR)/$(src:.vala=.o))

EXPANDED_VAPI_FILES = $(foreach vapi,$(VAPI_FILES),vapi/$(vapi))
EXPANDED_SRC_HEADER_FILES = $(foreach header,$(SRC_HEADER_FILES),vapi/$(header))
EXPANDED_RESOURCE_FILES = $(foreach res,$(RESOURCE_FILES),ui/$(res))
VALA_STAMP = $(BUILD_DIR)/.stamp
LANG_STAMP = $(LOCAL_LANG_DIR)/.langstamp

DIST_FILES = Makefile configure minver $(EXPANDED_SRC_FILES) $(EXPANDED_VAPI_FILES) \
	$(EXPANDED_SRC_HEADER_FILES) $(EXPANDED_RESOURCE_FILES) $(TEXT_FILES) icons/* misc/* \
	$(EXPANDED_PO_FILES) po/shotwell.pot vapi/*

DIST_TAR = $(PROGRAM)-$(VERSION).tar
DIST_TAR_BZ2 = $(DIST_TAR).bz2
DIST_TAR_GZ = $(DIST_TAR).gz
PACKAGE_ORIG_GZ = $(PROGRAM)_`parsechangelog | grep Version | sed 's/.*: //'`.orig.tar.gz

VALA_CFLAGS = `pkg-config --cflags $(EXT_PKGS)` $(foreach hdir,$(HEADER_DIRS),-I$(hdir)) \
	$(foreach def,$(DEFINES),-D$(def))

VALA_LDFLAGS = `pkg-config --libs $(EXT_PKGS)` -lgthread-2.0

ifdef WINDOWS
  VALA_DEFINES = -D WINDOWS -D NO_CAMERA -D NO_PUBLISHING -D NO_LIBUNIQUE -D NO_EXTENDED_POSIX
  EXPANDED_OBJ_FILES += src/windows.o
  RESOURCES = shotwell.res

ifndef BUILD_DEBUG
# -mwindows prevents a console window from appearing when we run Shotwell, but also hides
# all logging/debugging output, so we specify it only in a release build.
  VALA_LDFLAGS += -mwindows
endif  

shotwell.res: windows/shotwell.rc
	windres windows/shotwell.rc -O coff -o shotwell.res

endif

ifdef MAC
  VALA_DEFINES = -D MAC -D NO_CAMERA -D NO_PUBLISHING -D NO_LIBUNIQUE -D NO_SVG
  EXPANDED_OBJ_FILES += src/mac.o
endif

# setting CFLAGS in configure.mk overrides build type
ifndef CFLAGS
ifdef BUILD_DEBUG
CFLAGS = -O0 -g -pipe
else
CFLAGS = -O2 -g -pipe -mfpmath=sse -march=nocona
endif
endif

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
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	$(INSTALL_PROGRAM) $(PROGRAM) $(DESTDIR)$(PREFIX)/bin
	mkdir -p $(DESTDIR)$(PREFIX)/share/shotwell/icons
	$(INSTALL_DATA) icons/* $(DESTDIR)$(PREFIX)/share/shotwell/icons
	mkdir -p $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps
	$(INSTALL_DATA) icons/shotwell.svg $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps
ifndef DISABLE_ICON_UPDATE
	-gtk-update-icon-cache $(DESTDIR)$(PREFIX)/share/icons/hicolor || :
endif
	mkdir -p $(DESTDIR)$(PREFIX)/share/shotwell/ui
	$(INSTALL_DATA) ui/* $(DESTDIR)$(PREFIX)/share/shotwell/ui
	mkdir -p $(DESTDIR)$(PREFIX)/share/applications
	$(INSTALL_DATA) misc/shotwell.desktop $(DESTDIR)$(PREFIX)/share/applications
	$(INSTALL_DATA) misc/shotwell-viewer.desktop $(DESTDIR)$(PREFIX)/share/applications
ifndef DISABLE_DESKTOP_UPDATE
	-update-desktop-database || :
endif
ifdef LINUX
ifndef DISABLE_SCHEMAS_INSTALL
	GCONF_CONFIG_SOURCE=`gconftool-2 --get-default-source` gconftool-2 --makefile-install-rule misc/shotwell.schemas
else
	mkdir -p $(DESTDIR)$(SCHEMA_FILE_DIR)
	$(INSTALL_DATA) misc/shotwell.schemas $(DESTDIR)$(SCHEMA_FILE_DIR)
endif
endif
	-$(foreach lang,$(SUPPORTED_LANGUAGES),`mkdir -p $(SYSTEM_LANG_DIR)/$(lang)/LC_MESSAGES ; \
        $(INSTALL_DATA) $(LOCAL_LANG_DIR)/$(lang)/LC_MESSAGES/shotwell.mo \
            $(SYSTEM_LANG_DIR)/$(lang)/LC_MESSAGES/shotwell.mo`)

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/$(PROGRAM)
	rm -fr $(DESTDIR)$(PREFIX)/share/shotwell
	rm -fr $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/shotwell.svg
	rm -f $(DESTDIR)$(PREFIX)/share/applications/shotwell.desktop
	rm -f $(DESTDIR)$(PREFIX)/share/applications/shotwell-viewer.desktop
ifndef DISABLE_DESKTOP_UPDATE
	-update-desktop-database || :
endif
ifdef LINUX
ifndef DISABLE_SCHEMAS_INSTALL
	GCONF_CONFIG_SOURCE=`gconftool-2 --get-default-source` gconftool-2 --makefile-uninstall-rule misc/shotwell.schemas
else
	rm -f $(DESTDIR)$(SCHEMA_FILE_DIR)/shotwell.schemas
endif
endif
	$(foreach lang,$(SUPPORTED_LANGUAGES),`rm -f $(SYSTEM_LANG_DIR)/$(lang)/LC_MESSAGES/shotwell.mo`)

$(VALA_STAMP): $(EXPANDED_SRC_FILES) $(EXPANDED_VAPI_FILES) $(EXPANDED_SRC_HEADER_FILES) Makefile \
	$(CONFIG_IN)
	@ ./minver `valac --version | awk '{print $$2}'` $(MIN_VALAC_VERSION) || ( echo 'Shotwell requires Vala compiler $(MIN_VALAC_VERSION) or greater.  You are running' `valac --version` '\b.'; exit 1 )
ifndef ASSUME_PKGS
ifdef EXT_PKG_VERSIONS
	pkg-config --print-errors --exists '$(EXT_PKG_VERSIONS)'
else ifdef EXT_PKGS
	pkg-config --print-errors --exists $(EXT_PKGS)
endif
endif
	@ type msgfmt > /dev/null || ( echo 'msgfmt (usually found in the gettext package) is missing and is required to build Shotwell. ' ; exit 1 )
	mkdir -p $(BUILD_DIR)
	$(VALAC) --ccode --directory=$(BUILD_DIR) --basedir=src $(VALAFLAGS) \
	$(foreach pkg,$(PKGS),--pkg=$(pkg)) \
	$(foreach vapidir,$(VAPI_DIRS),--vapidir=$(vapidir)) \
	$(foreach def,$(DEFINES),-X -D$(def)) \
	$(foreach hdir,$(HEADER_DIRS),-X -I$(hdir)) \
	$(VALA_DEFINES) \
	$(EXPANDED_SRC_FILES)
	touch $@

# Do not remove hard tab or at symbol; necessary for dependencies to complete.  (Possible make
# bug.)
$(EXPANDED_C_FILES): $(VALA_STAMP)
	@

$(EXPANDED_OBJ_FILES): %.o: %.c $(CONFIG_IN) Makefile
	$(CC) -c $(VALA_CFLAGS) $(CFLAGS) -o $@ $<

$(PROGRAM): $(EXPANDED_OBJ_FILES) $(RESOURCES) $(LANG_STAMP)
	$(CC) $(EXPANDED_OBJ_FILES) $(CFLAGS) $(RESOURCES) $(VALA_LDFLAGS) -o $@

shotwell-setup-$(VERSION).exe: $(PROGRAM) windows/winstall.iss
	iscc windows\winstall.iss
	mv setup.exe shotwell-setup-$(VERSION).exe

winstaller: shotwell-setup-$(VERSION).exe

