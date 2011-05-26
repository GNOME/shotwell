PROGRAM = shotwell
PROGRAM_THUMBNAILER = shotwell-video-thumbnailer

VERSION = 0.10.0+trunk
GETTEXT_PACKAGE = $(PROGRAM)
BUILD_ROOT = 1

VALAC := valac
VALAC_VERSION := `$(VALAC) --version | awk '{print $$2}'`
MIN_VALAC_VERSION := 0.11.7
INSTALL_PROGRAM := install
INSTALL_DATA := install -m 644

# needed for testing
VALADATE_PKG_NAME := valadate-1.0
MIN_VALADATE_VERSION := 0.1.1

# defaults that may be overridden by configure.mk
PREFIX=/usr/local
SCHEMA_FILE_DIR=/etc/gconf/schemas
BUILD_RELEASE=1
LIB=lib

-include configure.mk

CORE_SUPPORTED_LANGUAGES=fr de it es pl et sv sk lv pt bg bn nl da zh_CN el ru pa hu en_GB uk \
    ja fi zh_TW cs nb id th sl hr ar ast ro sr lt gl tr ca ko kk pt_BR eu he mk te ta

EXTRAS_SUPPORTED_LANGUAGES=fr de it es pl et sv sk lv pt bg bn nl da zh_CN el ru pa hu en_GB uk \
    ja fi zh_TW cs nb id th sl hr ar ast ro sr lt gl tr ca ko kk pt_BR eu he mk te ta

LOCAL_LANG_DIR=locale-langpack
SYSTEM_LANG_DIR := $(DESTDIR)$(PREFIX)/share/locale

VALAFLAGS := -g --enable-checking --thread --fatal-warnings $(USER_VALAFLAGS)
DEFINES := _PREFIX='"$(PREFIX)"' _VERSION='"$(VERSION)"' GETTEXT_PACKAGE='"$(GETTEXT_PACKAGE)"' \
	_LANG_SUPPORT_DIR='"$(SYSTEM_LANG_DIR)"' _LIB='"${LIB}"'

EXPORT_FLAGS = -export-dynamic

include units.mk
include plugins/plugins.mk

UNUNITIZED_SRC_FILES = \
	main.vala \
	AppWindow.vala \
	CollectionPage.vala \
	Thumbnail.vala \
	ThumbnailCache.vala \
	CheckerboardLayout.vala \
	PhotoPage.vala \
	Page.vala \
	SortedList.vala \
	SortedListTests.vala \
	Dimensions.vala \
	Box.vala \
	Photo.vala \
	Orientation.vala \
	BatchImport.vala \
	Dialogs.vala \
	Resources.vala \
	Debug.vala \
	ColorTransformation.vala \
	EditingTools.vala \
	Properties.vala \
	CustomComponents.vala \
	Config.vala \
	Event.vala \
	International.vala \
	AppDirs.vala \
	PixbufCache.vala \
	CommandManager.vala \
	Commands.vala \
	SlideshowPage.vala \
	LibraryFiles.vala \
	Printing.vala \
	Tag.vala \
	Screensaver.vala \
	MimicManager.vala \
	Exporter.vala \
	DirectoryMonitor.vala \
	LibraryMonitor.vala \
	VideoSupport.vala \
	Tombstone.vala \
	MetadataWriter.vala \
	Application.vala \
	TimedQueue.vala \
	MediaPage.vala \
	MediaDataRepresentation.vala \
	DesktopIntegration.vala \
	MediaInterfaces.vala \
	MediaMetadata.vala \
	VideoMetadata.vala \
	MediaMonitor.vala \
	PhotoMonitor.vala \
	VideoMonitor.vala \
	SearchFilter.vala \
	MediaViewTracker.vala

THUMBNAILER_SRC_FILES = \
	shotwell-video-thumbnailer.vala

VAPI_FILES = \
	libexif.vapi \
	libgphoto2.vapi \
	ExtendedPosix.vapi \
	LConv.vapi \
	libraw.vapi

RESOURCE_FILES = \
	collection.ui \
	direct.ui \
	events_directory.ui \
	event.ui \
	fullscreen.ui \
	import_queue.ui \
	import.ui \
	media.ui \
	offline.ui \
	photo.ui \
	savedsearch.ui \
	search_bar.ui \
	set_background_dialog.glade \
	shotwell.glade \
	shotwell.xml \
	sidebar_default.ui \
	tags.ui \
	trash.ui

SYS_INTEGRATION_FILES = \
	shotwell.desktop.head \
	shotwell-viewer.desktop.head \
	shotwell.schemas

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

ICON_FILES = \
	all-rejected.png \
	crop-pivot-reticle.png \
	crop.svg \
	drag_nub.png \
	enhance.png \
	five-star-filter.svg \
	five-stars.svg \
	flag-page.png \
	flag-trinket.png \
	four-star-filter-plus.svg \
	four-stars.svg \
	image-adjust.svg \
	import-all.png \
	import.svg \
	make-primary.svg \
	merge.svg \
	multiple-events.png \
	multiple-tags.png \
	noninterpretable-video.png \
	one-event.png \
	one-star-filter-plus.svg \
	one-star.svg \
	one-tag.png \
	pin-toolbar.svg \
	publish.png \
	redeye.png \
	rejected.svg \
	searchbox-clear.svg \
	searchbox-find.svg \
	shotwell-16.svg \
	shotwell-24.svg \
	shotwell.ico \
	shotwell-street.jpg \
	shotwell.svg \
	sprocket.png \
	three-star-filter-plus.svg \
	three-stars.svg \
	two-star-filter-plus.svg \
	two-stars.svg \
	videos-page.png \
	zoom-in.png \
	zoom-out.png \
	slideshow-extension-point.png \
	generic-plugin.png \
	filter-raw.png \
	filter-photos.png \
	filter-videos.png \
	filter-flagged.png

HELP_FILES = \
	edit-adjustments.page \
	edit-crop.page \
	edit-enhance.page \
	edit-external.page \
	edit-nondestructive.page \
	edit-redeye.page \
	edit-rotate.page \
	edit-time-date.page \
	edit-undo.page \
	formats.page \
	import-camera.page \
	import-file.page \
	import-f-spot.page \
	import-memorycard.page \
	index.page \
	organize-event.page \
	organize-flag.page \
	organize-rating.page \
	organize-remove.page \
	organize-search.page \
	organize-tag.page \
	organize-title.page \
	other-files.page \
	other-missing.page \
	other-multiple.page \
	running.page \
	share-background.page \
	share-export.page \
	share-print.page \
	share-send.page \
	share-slideshow.page \
	share-upload.page \
	view-displaying.page \
	view-information.page \
	view-sidebar.page

HELP_IMAGES = \
	crop_thirds.jpg \
	editing_overview.png \
	edit_toolbar.png \
	shotwell_logo.png \
	trash_process.png

VAPI_DIRS = \
	./vapi

HEADER_DIRS = \
	./vapi

LOCAL_PKGS = \
	ExtendedPosix \
	posix \
	LConv

# libraw is not listed (see note below); when libraw-config is no longer needed, it should be
# added to this list
EXT_PKGS = \
	atk \
	gconf-2.0 \
	gdk-2.0 \
	gdk-x11-2.0 \
	gee-1.0 \
	gexiv2 \
	gio-unix-2.0 \
	glib-2.0 \
	gmodule-2.0 \
	gstreamer-0.10 \
	gstreamer-base-0.10 \
	gtk+-2.0 \
	gudev-1.0 \
	libexif \
	libgphoto2 \
	libsoup-2.4 \
	libxml-2.0 \
	sqlite3 \
	unique-1.0 \
	webkit-1.0

THUMBNAILER_PKGS = \
    gtk+-2.0 \
    gee-1.0 \
    gstreamer-0.10 \
    gstreamer-base-0.10

DIRECT_LIBS =

LIBRAW_PKG = \
	libraw

# libraw is handled separately (see note below); when libraw-config is no longer needed, the version
# should be added to this list
EXT_PKG_VERSIONS = \
	gconf-2.0 >= 2.22.0 \
	gee-1.0 >= 0.5.0 \
	gexiv2 >= 0.2.0 \
	gio-unix-2.0 >= 2.20 \
	glib-2.0 >= 2.26.0 \
	gmodule-2.0 >= 2.24.0 \
	gstreamer-0.10 >= 0.10.28 \
	gstreamer-base-0.10 >= 0.10.28 \
	gtk+-2.0 >= 2.18.0 \
	gudev-1.0 >= 145 \
	libexif >= 0.6.16 \
	libgphoto2 >= 2.4.2 \
	libsoup-2.4 >= 2.26.0 \
	libxml-2.0 >= 2.6.32 \
	sqlite3 >= 3.5.9 \
	unique-1.0 >= 1.0.0 \
	webkit-1.0 >= 1.1.5

ifdef ENABLE_TESTS
EXT_PKGS += valadate-1.0
EXT_PKG_VERSIONS += valadate-1.0 >= 0.1.1
endif
DIRECT_LIBS_VERSIONS =

LIBRAW_VERSION = \
	0.9.0

VALA_PKGS = $(EXT_PKGS) $(LOCAL_PKGS) $(LIBRAW_PKG)

ifndef BUILD_DIR
BUILD_DIR=src
endif

DESKTOP_APP_SHORT_NAME="Shotwell"
DESKTOP_APP_FULL_NAME="Shotwell Photo Manager"
DESKTOP_APPLICATION_COMMENT="Organize your photos"
DESKTOP_APPLICATION_CLASS="Photo Manager"
DIRECT_EDIT_DESKTOP_APP_SHORT_NAME="Shotwell"
DIRECT_EDIT_DESKTOP_APP_FULL_NAME="Shotwell Photo Viewer"
DIRECT_EDIT_DESKTOP_APPLICATION_CLASS="Photo Viewer"
TEMPORARY_DESKTOP_FILES = misc/shotwell.desktop misc/shotwell-viewer.desktop

# Process the units
UNIT_MKS := $(foreach unit,$(UNITS),src/$(unit)/mk/$(notdir $(unit)).mk)
include $(UNIT_MKS)

UNITIZE_DIR := src/.unitize
UNITIZE_ENTRIES := $(foreach unit,$(APP_UNITS),$(UNITIZE_DIR)/_$(unit)_unitize_entry.vala)
UNITIZE_INITS := $(foreach nm,$(UNIT_NAMESPACES),$(UNITIZE_DIR)/_$(nm)Internals.vala)
UNITIZE_STAMP := $(UNITIZE_DIR)/.unitized

PLUGINS_DIR := plugins
PLUGINS_SO := $(foreach plugin,$(PLUGINS),$(PLUGINS_DIR)/$(plugin)/$(plugin).so)
EXTRA_PLUGINS_SO := $(foreach plugin,$(EXTRA_PLUGINS),$(PLUGINS_DIR)/$(plugin)/$(plugin).so)
PLUGINS_DIST_FILES := `$(MAKE) --directory=plugins --no-print-directory listfiles`

THUMBNAILER_DIR := thumbnailer
THUMBNAILER_BIN := $(THUMBNAILER_DIR)/$(PROGRAM_THUMBNAILER)
EXPANDED_THUMBNAILER_SRC_FILES := $(foreach file, $(THUMBNAILER_SRC_FILES), $(THUMBNAILER_DIR)/$(file))

EXPANDED_CORE_PO_FILES := $(foreach po,$(CORE_SUPPORTED_LANGUAGES),po/shotwell-core/$(po).po)
EXPANDED_EXTRAS_PO_FILES := $(foreach po,$(EXTRAS_SUPPORTED_LANGUAGES),po/shotwell-extras/$(po).po)

EXPANDED_SRC_FILES := $(UNITIZED_SRC_FILES) $(foreach src,$(UNUNITIZED_SRC_FILES),src/$(src)) \
	$(UNITIZE_INITS) $(UNITIZE_ENTRIES)
EXPANDED_DIST_SRC_FILES := $(UNITIZED_SRC_FILES) $(foreach src,$(UNUNITIZED_SRC_FILES),src/$(src))
EXPANDED_C_FILES := $(foreach file,$(subst src,$(BUILD_DIR),$(EXPANDED_SRC_FILES)),$(file:.vala=.c))
EXPANDED_OBJ_FILES := $(foreach file,$(subst src,$(BUILD_DIR),$(EXPANDED_SRC_FILES)),$(file:.vala=.o))
EXPANDED_SYS_INTEGRATION_FILES := $(foreach file,$(SYS_INTEGRATION_FILES),misc/$(file))
EXPANDED_ICON_FILES := $(foreach file,$(ICON_FILES),icons/$(file))
EXPANDED_VAPI_FILES := $(foreach vapi,$(VAPI_FILES),vapi/$(vapi))
EXPANDED_SRC_HEADER_FILES := $(foreach header,$(SRC_HEADER_FILES),vapi/$(header))
EXPANDED_RESOURCE_FILES := $(foreach res,$(RESOURCE_FILES),ui/$(res))
EXPANDED_HELP_FILES := $(foreach file,$(HELP_FILES),help/C/$(file))
EXPANDED_HELP_IMAGES := $(foreach file,$(HELP_IMAGES),help/C/figures/$(file))
VALA_STAMP := $(BUILD_DIR)/.stamp
LANG_STAMP := $(LOCAL_LANG_DIR)/.langstamp
MAKE_FILES := Makefile $(CONFIG_IN) $(UNIT_MKS) unitize.mk units.mk
PC_INPUT := shotwell-plugin-dev-1.0.m4
PC_FILE := $(PC_INPUT:.m4=.pc)

DIST_FILES = Makefile configure chkver $(EXPANDED_DIST_SRC_FILES) $(EXPANDED_VAPI_FILES) \
	$(EXPANDED_SRC_HEADER_FILES) $(EXPANDED_RESOURCE_FILES) $(TEXT_FILES) $(EXPANDED_ICON_FILES) \
	$(EXPANDED_SYS_INTEGRATION_FILES) $(EXPANDED_CORE_PO_FILES) $(EXPANDED_EXTRAS_PO_FILES) \
	po/shotwell-core/shotwell.pot po/shotwell-extras/shotwell-extras.pot libraw-config \
	$(EXPANDED_HELP_FILES) $(EXPANDED_HELP_IMAGES) apport/shotwell.py $(UNIT_RESOURCES) $(UNIT_MKS) \
	unitize.mk units.mk $(PC_INPUT) $(PLUGINS_DIST_FILES) \
	$(EXPANDED_THUMBNAILER_SRC_FILES)
	

DIST_TAR = $(PROGRAM)-$(VERSION).tar
DIST_TAR_BZ2 = $(DIST_TAR).bz2
DIST_TAR_GZ = $(DIST_TAR).gz
PACKAGE_ORIG_GZ = $(PROGRAM)_`parsechangelog | grep Version | sed 's/.*: //'`.orig.tar.gz

VALAFLAGS := $(VALAFLAGS) --vapidir=plugins/

ifdef ENABLE_TESTS
VALAFLAGS := $(VALAFLAGS) --vapi=libshotwell.vapi --define=ENABLE_TESTS 
DEFINES := $(DEFINES) ENABLE_TESTS=true
endif

VALA_CFLAGS := `pkg-config --cflags $(EXT_PKGS) $(DIRECT_LIBS) gthread-2.0` \
	$(foreach hdir,$(HEADER_DIRS),-I$(hdir)) \
	$(foreach def,$(DEFINES),-D$(def))

VALA_LDFLAGS := `pkg-config --libs $(EXT_PKGS) $(DIRECT_LIBS) gthread-2.0`

# REQUIRED_CFLAGS absolutely get appended to CFLAGS, whatever the
# the value of CFLAGS in the environment
REQUIRED_CFLAGS := -fPIC

# setting CFLAGS in configure.mk overrides build type
ifndef CFLAGS
ifdef BUILD_DEBUG
CFLAGS = -O0 -g -pipe
PLUGIN_CFLAGS = -O0 -g -pipe
else
CFLAGS = -O2 -g -pipe
PLUGIN_CFLAGS = -O2 -g -pipe
endif
endif

CFLAGS += $(REQUIRED_CFLAGS)
PLUGIN_CFLAGS += $(REQUIRED_CFLAGS)

# Required for gudev-1.0
CFLAGS += -DG_UDEV_API_IS_SUBJECT_TO_CHANGE

# Packaged libraw is not widely available, so we must fake what would be in its .pc file
# if not available.
LIBRAW_CONFIG=./libraw-config

define check_valac_version
	@ ./chkver min $(VALAC_VERSION) $(MIN_VALAC_VERSION) || ( echo 'Shotwell requires Vala compiler $(MIN_VALAC_VERSION) or greater.  You are running' $(VALAC_VERSION) '\b.'; exit 1 )
	$(if $(MAX_VALAC_VERSION),\
		@ ./chkver max $(VALAC_VERSION) $(MAX_VALAC_VERSION) || ( echo 'Shotwell cannot be built by Vala compiler $(MAX_VALAC_VERSION) or greater.  You are running' $(VALAC_VERSION) '\b.'; exit 1 ),)
endef

define check_valadate_version
	@ pkg-config $(VALADATE_PKG_NAME) --atleast-version=$(MIN_VALADATE_VERSION) || ( echo 'Shotwell testing requires Valadate $(MIN_VALADATE_VERSION) or greater.  You are running' `pkg-config --modversion $(VALADATE_PKG_NAME)` '\b.'; exit 1 )
endef

all: pkgcheck

ifdef ENABLE_BUILD_FOR_GLADE
all: $(PLUGINS_DIR) lib$(PROGRAM).so $(PROGRAM) $(PC_FILE)
else
ifdef ENABLE_TESTS
all: $(PLUGINS_DIR) $(PROGRAM) $(PC_FILE)

valadate_check: 
	$(call check_valadate_version)

check: valadate_check $(PLUGINS_DIR) lib$(PROGRAM).so $(PROGRAM) $(PC_FILE)
	valadate -L shotwell --dir=vapi --dir=. --verbose-search -f src/libshotwell.vapi

else
all: $(PLUGINS_DIR) $(PROGRAM) $(PC_FILE)
endif
endif


include src/plugins/mk/interfaces.mk

$(LANG_STAMP): $(EXPANDED_CORE_PO_FILES) $(EXPANDED_EXTRAS_PO_FILES)
	@$(foreach po,$(CORE_SUPPORTED_LANGUAGES),`mkdir -p $(LOCAL_LANG_DIR)/$(po)/LC_MESSAGES ; \
		msgfmt -o $(LOCAL_LANG_DIR)/$(po)/LC_MESSAGES/shotwell.mo po/shotwell-core/$(po).po`)
	@$(foreach po,$(EXTRAS_SUPPORTED_LANGUAGES),`mkdir -p $(LOCAL_LANG_DIR)/$(po)/LC_MESSAGES ; \
		msgfmt -o $(LOCAL_LANG_DIR)/$(po)/LC_MESSAGES/shotwell-extras.mo po/shotwell-extras/$(po).po`)
	@touch $(LANG_STAMP)

clean:
	rm -f $(EXPANDED_C_FILES)
	rm -f $(EXPANDED_OBJ_FILES)
	rm -f $(VALA_STAMP)
	rm -rf $(PROGRAM)-$(VERSION)
	rm -f $(PROGRAM)
	rm -f $(THUMBNAILER_DIR)/$(PROGRAM_THUMBNAILER)
	rm -rf $(LOCAL_LANG_DIR)
	rm -f $(LANG_STAMP)
	rm -f $(TEMPORARY_DESKTOP_FILES)
	rm -f lib$(PROGRAM).so
	rm -rf $(UNITIZE_DIR)
	rm -f $(PLUGIN_VAPI)
	rm -f $(PLUGIN_HEADER)
	rm -f $(PLUGIN_DEPS)
	rm -f $(PLUGINS_SO)
	rm -f $(EXTRA_PLUGINS_SO)
	@$(MAKE) --directory=plugins clean
	rm -f $(PC_FILE)

cleantemps:
	rm -f $(EXPANDED_C_FILES)
	rm -f $(EXPANDED_OBJ_FILES)
	rm -f $(VALA_STAMP)
	rm -f $(LANG_STAMP)
	rm -f $(TEMPORARY_DESKTOP_FILES)
	@$(MAKE) --directory=plugins cleantemps

package:
	$(MAKE) dist
	cp $(DIST_TAR_GZ) $(PACKAGE_ORIG_GZ)
	rm -f $(DIST_TAR_GZ)
	rm -f $(DIST_TAR_BZ2)

.PHONY: dist
dist:
	mkdir -p $(PROGRAM)-$(VERSION)
	cp --parents --preserve $(DIST_FILES) $(PROGRAM)-$(VERSION)
	tar --bzip2 -cvf $(DIST_TAR_BZ2) $(PROGRAM)-$(VERSION)
	tar --gzip -cvf $(DIST_TAR_GZ) $(PROGRAM)-$(VERSION)
	rm -rf $(PROGRAM)-$(VERSION)

distclean: clean
	rm -f configure.mk
	rm -f $(DIST_TAR_BZ2)
	rm -f $(DIST_TAR_GZ)
	@$(MAKE) --directory=plugins distclean

.PHONY: install
install:
	cp misc/shotwell.desktop.head misc/shotwell.desktop
	cp misc/shotwell-viewer.desktop.head misc/shotwell-viewer.desktop
	$(foreach lang,$(CORE_SUPPORTED_LANGUAGES), echo X-GNOME-FullName[$(lang)]=`TEXTDOMAINDIR=locale-langpack \
		LANGUAGE=$(lang) gettext --domain=shotwell $(DESKTOP_APP_FULL_NAME)` \
		>> misc/shotwell.desktop ; \
		echo GenericName[$(lang)]=`TEXTDOMAINDIR=locale-langpack LANGUAGE=$(lang) \
		gettext --domain=shotwell $(DESKTOP_APPLICATION_CLASS)` >> misc/shotwell.desktop ; \
		echo Comment[$(lang)]=`TEXTDOMAINDIR=locale-langpack LANGUAGE=$(lang) gettext \
		--domain=shotwell $(DESKTOP_APPLICATION_COMMENT)` >> misc/shotwell.desktop ; \
		echo X-GNOME-FullName[$(lang)]=`TEXTDOMAINDIR=locale-langpack LANGUAGE=$(lang) gettext \
		--domain=shotwell $(DIRECT_EDIT_DESKTOP_APP_FULL_NAME)` >> misc/shotwell-viewer.desktop ; \
		echo GenericName[$(lang)]=`TEXTDOMAINDIR=locale-langpack LANGUAGE=$(lang) gettext \
		--domain=shotwell $(DIRECT_EDIT_DESKTOP_APPLICATION_CLASS)` >> misc/shotwell-viewer.desktop ;)
	touch $(LANG_STAMP)
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	$(INSTALL_PROGRAM) $(PROGRAM) $(DESTDIR)$(PREFIX)/bin
	$(INSTALL_PROGRAM) $(THUMBNAILER_BIN) $(DESTDIR)$(PREFIX)/bin
	mkdir -p $(DESTDIR)$(PREFIX)/share/shotwell/icons
	$(INSTALL_DATA) icons/* $(DESTDIR)$(PREFIX)/share/shotwell/icons
	mkdir -p $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps
	$(INSTALL_DATA) icons/shotwell.svg $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps
	mkdir -p $(DESTDIR)$(PREFIX)/share/icons/hicolor/16x16/apps
	$(INSTALL_DATA) icons/shotwell-16.svg $(DESTDIR)$(PREFIX)/share/icons/hicolor/16x16/apps/shotwell.svg
	mkdir -p $(DESTDIR)$(PREFIX)/share/icons/hicolor/24x24/apps
	$(INSTALL_DATA) icons/shotwell-24.svg $(DESTDIR)$(PREFIX)/share/icons/hicolor/24x24/apps/shotwell.svg
ifndef DISABLE_ICON_UPDATE
	-gtk-update-icon-cache -t -f $(DESTDIR)$(PREFIX)/share/icons/hicolor || :
endif
	mkdir -p $(DESTDIR)$(PREFIX)/share/shotwell/ui
	$(INSTALL_DATA) ui/* $(DESTDIR)$(PREFIX)/share/shotwell/ui
	mkdir -p $(DESTDIR)$(PREFIX)/share/applications
	$(INSTALL_DATA) misc/shotwell.desktop $(DESTDIR)$(PREFIX)/share/applications
	$(INSTALL_DATA) misc/shotwell-viewer.desktop $(DESTDIR)$(PREFIX)/share/applications
ifndef DISABLE_DESKTOP_UPDATE
	-update-desktop-database || :
endif
ifndef DISABLE_SCHEMAS_INSTALL
	GCONF_CONFIG_SOURCE=`gconftool-2 --get-default-source` gconftool-2 --makefile-install-rule misc/shotwell.schemas
else
	mkdir -p $(DESTDIR)$(SCHEMA_FILE_DIR)
	$(INSTALL_DATA) misc/shotwell.schemas $(DESTDIR)$(SCHEMA_FILE_DIR)
endif
ifdef ENABLE_APPORT_HOOK_INSTALL
	mkdir -p $(DESTDIR)$(PREFIX)/share/apport/package-hooks
	$(INSTALL_DATA) apport/shotwell.py $(DESTDIR)$(PREFIX)/share/apport/package-hooks
endif
ifndef DISABLE_HELP_INSTALL
	mkdir -p $(DESTDIR)$(PREFIX)/share/gnome/help/shotwell/C
	$(INSTALL_DATA) $(EXPANDED_HELP_FILES) $(DESTDIR)$(PREFIX)/share/gnome/help/shotwell/C
	mkdir -p $(DESTDIR)$(PREFIX)/share/gnome/help/shotwell/C/figures
	$(INSTALL_DATA) $(EXPANDED_HELP_IMAGES) $(DESTDIR)$(PREFIX)/share/gnome/help/shotwell/C/figures
endif
	-$(foreach lang,$(CORE_SUPPORTED_LANGUAGES),`mkdir -p $(SYSTEM_LANG_DIR)/$(lang)/LC_MESSAGES ; \
		$(INSTALL_DATA) $(LOCAL_LANG_DIR)/$(lang)/LC_MESSAGES/shotwell.mo \
		$(SYSTEM_LANG_DIR)/$(lang)/LC_MESSAGES/shotwell.mo`)
	-$(foreach lang,$(EXTRAS_SUPPORTED_LANGUAGES),`mkdir -p $(SYSTEM_LANG_DIR)/$(lang)/LC_MESSAGES ; \
		$(INSTALL_DATA) $(LOCAL_LANG_DIR)/$(lang)/LC_MESSAGES/shotwell-extras.mo \
		$(SYSTEM_LANG_DIR)/$(lang)/LC_MESSAGES/shotwell-extras.mo`)
	mkdir -p $(DESTDIR)$(PREFIX)/$(LIB)/shotwell/plugins/builtin
	$(INSTALL_PROGRAM) $(PLUGINS_SO) $(DESTDIR)$(PREFIX)/$(LIB)/shotwell/plugins/builtin
ifdef PLUGINS_RC
	$(INSTALL_DATA) $(PLUGINS_RC) $(DESTDIR)$(PREFIX)/$(LIB)/shotwell/plugins/builtin
endif
ifndef DISABLE_EXTRA_PLUGINS_INSTALL
	$(INSTALL_PROGRAM) $(EXTRA_PLUGINS_SO) $(DESTDIR)$(PREFIX)/$(LIB)/shotwell/plugins/builtin
ifdef EXTRA_PLUGINS_RC
	$(INSTALL_DATA) $(EXTRA_PLUGINS_RC) $(DESTDIR)$(PREFIX)/$(LIB)/shotwell/plugins/builtin
endif
endif
ifdef INSTALL_HEADERS
	mkdir -p $(DESTDIR)$(PREFIX)/include/shotwell/plugins
	$(INSTALL_DATA) $(PLUGIN_HEADER) $(DESTDIR)$(PREFIX)/include/shotwell/plugins
	mkdir -p $(DESTDIR)$(PREFIX)/share/vala/vapi
	$(INSTALL_DATA) $(PLUGIN_VAPI) $(DESTDIR)$(PREFIX)/share/vala/vapi
	$(INSTALL_DATA) $(PLUGIN_DEPS) $(DESTDIR)$(PREFIX)/share/vala/vapi
	$(INSTALL_DATA) $(PC_FILE) $(DESTDIR)$(PREFIX)/$(LIB)/pkgconfig
endif

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/$(PROGRAM)
	rm -f $(DESTDIR)$(PREFIX)/bin/$(PROGRAM_THUMBNAILER)
	rm -fr $(DESTDIR)$(PREFIX)/share/shotwell
	rm -f $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/shotwell.svg
	rm -f $(DESTDIR)$(PREFIX)/share/icons/hicolor/16x16/apps/shotwell.svg
	rm -f $(DESTDIR)$(PREFIX)/share/icons/hicolor/24x24/apps/shotwell.svg
	rm -f $(DESTDIR)$(PREFIX)/share/applications/shotwell.desktop
	rm -f $(DESTDIR)$(PREFIX)/share/applications/shotwell-viewer.desktop
ifndef DISABLE_DESKTOP_UPDATE
	-update-desktop-database || :
endif
ifndef DISABLE_HELP_INSTALL
	rm -rf $(DESTDIR)$(PREFIX)/share/gnome/help/shotwell
endif
ifndef DISABLE_SCHEMAS_INSTALL
	GCONF_CONFIG_SOURCE=`gconftool-2 --get-default-source` gconftool-2 --makefile-uninstall-rule misc/shotwell.schemas
else
	rm -f $(DESTDIR)$(SCHEMA_FILE_DIR)/shotwell.schemas
endif
ifdef ENABLE_APPORT_HOOK_INSTALL
	rm -f $(DESTDIR)$(PREFIX)/share/apport/package-hooks/shotwell.py
endif
	$(foreach lang,$(CORE_SUPPORTED_LANGUAGES),`rm -f $(SYSTEM_LANG_DIR)/$(lang)/LC_MESSAGES/shotwell.mo`)
	$(foreach lang,$(EXTRAS_SUPPORTED_LANGUAGES),`rm -f $(SYSTEM_LANG_DIR)/$(lang)/LC_MESSAGES/shotwell-extras.mo`)
	rm -rf $(DESTDIR)$(PREFIX)/$(LIB)/shotwell/plugins/builtin
ifdef INSTALL_HEADERS
	rm -rf $(DESTDIR)$(PREFIX)/include/shotwell
	rm -f $(foreach vapi,$(PLUGIN_VAPI),$(DESTDIR)$(PREFIX)/share/vala/vapi/$(notdir $(vapi)))
	rm -f $(foreach dep,$(PLUGIN_DEPS),$(DESTDIR)$(PREFIX)/share/vala/vapi/$(notdir $(dep)))
	rm -f $(DESTDIR)$(PREFIX)/$(LIB)/pkgconfig/$(PC_FILE)
endif

$(PC_FILE): $(PC_INPUT) $(MAKE_FILES)
	m4 '-D_VERSION_=$(VERSION)' '-D_PREFIX_=$(PREFIX)' '-D_REQUIREMENTS_=$(PLUGIN_PKG_REQS)' \
		'-D_LIB_=$(LIB)' $< > $@

$(UNITIZE_STAMP): $(MAKE_FILES) src/unit/rc/UnitInternals.m4 src/unit/rc/unitize_entry.m4
	@mkdir -p $(UNITIZE_DIR)
	@$(foreach unit,$(APP_UNITS),\
		`m4 '-D_APP_UNIT_=$(unit)' src/unit/rc/unitize_entry.m4 > $(UNITIZE_DIR)/_$(unit)_unitize_entry.vala`)
	@$(foreach nm,$(UNIT_NAMESPACES),\
		`m4 '-D_UNIT_NAME_=$(nm)' '-D_UNIT_USES_INITS_=$($(nm)_USES_INITS)' '-D_UNIT_USES_TERMINATORS_=$($(nm)_USES_TERMINATORS)' src/unit/rc/UnitInternals.m4 > $(UNITIZE_DIR)/_$(nm)Internals.vala`)
	@touch $@

$(UNITIZE_INITS) $(UNITIZE_ENTRIES): $(UNITIZE_STAMP)
	@

# EXPANDED_SRC_FILES includes UNITIZE_INITS and UNITIZE_ENTRY
$(VALA_STAMP): $(EXPANDED_SRC_FILES) $(EXPANDED_VAPI_FILES) $(EXPANDED_SRC_HEADER_FILES)
	$(call check_valac_version)
	@echo Compiling Vala code...
	@mkdir -p $(BUILD_DIR)
	@$(VALAC) --ccode --directory=$(BUILD_DIR) --basedir=src \
		$(foreach pkg,$(VALA_PKGS),--pkg=$(pkg)) \
		$(foreach vapidir,$(VAPI_DIRS),--vapidir=$(vapidir)) \
		$(foreach def,$(DEFINES),-X -D$(def)) \
		$(foreach hdir,$(HEADER_DIRS),-X -I$(hdir)) \
		$(VALAFLAGS) \
		$(EXPANDED_SRC_FILES)
	@touch $@

# Do not remove hard tab or at symbol; necessary for dependencies to complete.
$(EXPANDED_C_FILES): $(VALA_STAMP)
	@

$(EXPANDED_OBJ_FILES): %.o: %.c $(CONFIG_IN) Makefile
	$(CC) -c $(VALA_CFLAGS) `$(LIBRAW_CONFIG) --cflags` $(CFLAGS) -o $@ $<

$(PROGRAM): $(EXPANDED_OBJ_FILES) $(RESOURCES) $(LANG_STAMP) $(THUMBNAILER_BIN)
	$(CC) $(EXPANDED_OBJ_FILES) $(CFLAGS) $(RESOURCES) $(VALA_LDFLAGS) `$(LIBRAW_CONFIG) --libs` $(EXPORT_FLAGS) -o $@

$(THUMBNAILER_BIN): $(EXPANDED_THUMBNAILER_SRC_FILES)
	$(VALAC) $(EXPANDED_THUMBNAILER_SRC_FILES) $(VALAFLAGS) -o $@ $(foreach pkg,$(THUMBNAILER_PKGS),--pkg=$(pkg))

$(PLUGINS_SO) $(EXTRA_PLUGINS_SO): $(PLUGINS_DIR)
	@

.PHONY: $(PLUGINS_DIR)
$(PLUGINS_DIR): $(PLUGIN_VAPI) $(PLUGIN_HEADER) $(PLUGIN_DEPS)
	$(call check_valac_version)
	@$(MAKE) --directory=$@ PLUGINS_VERSION="$(VERSION)" USER_VALAFLAGS="$(USER_VALAFLAGS)" \
		PLUGIN_CFLAGS="$(PLUGIN_CFLAGS)"

.PHONY: docs
docs:
# valadoc complains if the directory already exists
	@rm -rf docs
	valadoc --directory=docs --package-name=shotwell-plugin-dev --package-version=$(VERSION) --verbose \
		--no-protected \
		$(foreach def,$(DEFINES),--define=$(def)) \
		$(foreach pkg,$(VALA_PKGS),--pkg=$(pkg)) \
		$(foreach vapidir,$(VAPI_DIRS),--vapidir=$(vapidir)) \
		$(PLUGIN_INTERFACES)

glade: lib$(PROGRAM).so

lib$(PROGRAM).so: $(EXPANDED_OBJ_FILES) $(RESOURCES) $(LANG_STAMP)
	$(CC) $(EXPANDED_OBJ_FILES) $(CFLAGS) $(RESOURCES) $(VALA_LDFLAGS) `$(LIBRAW_CONFIG) --libs` $(EXPORT_FLAGS) -shared -o $@

.PHONY: pkgcheck
pkgcheck:
ifndef ASSUME_PKGS
ifdef EXT_PKG_VERSIONS
	@pkg-config --print-errors --exists '$(EXT_PKG_VERSIONS) $(DIRECT_LIBS_VERSIONS)'
else ifdef EXT_PKGS
	@pkg-config --print-errors --exists $(EXT_PKGS) $(DIRECT_LIBS_VERSIONS)
endif
# Check for libraw manually
	@$(LIBRAW_CONFIG) --exists=$(LIBRAW_VERSION)
endif
	@ type msgfmt > /dev/null || ( echo 'msgfmt (usually found in the gettext package) is missing and is required to build Shotwell. ' ; exit 1 )
