PROGRAM = shotwell
PROGRAM_THUMBNAILER = shotwell-video-thumbnailer
PROGRAM_MIGRATOR = shotwell-settings-migrator

VERSION = 0.15.1+trunk
GITVER := $(shell git log -n 1 2>/dev/null | head -n 1 | awk '{print $$2}')
GETTEXT_PACKAGE = $(PROGRAM)
BUILD_ROOT = 1

ifndef VALAC
VALAC := $(shell which valac)
else
VALAC := $(shell which $(VALAC))
endif

VALAC_VERSION := `$(VALAC) --version | awk '{print $$2}'`
MIN_VALAC_VERSION := 0.20.1
INSTALL_PROGRAM := install
INSTALL_DATA := install -m 644

export MIN_GLIB_VERSION=2.30.0

# defaults that may be overridden by configure.mk
PREFIX=/usr/local
BUILD_RELEASE=1
LIB=lib

-include configure.mk
ifndef LIBEXECDIR
LIBEXECDIR=$(PREFIX)/libexec/shotwell
endif

CORE_SUPPORTED_LANGUAGES=$(shell cat po/LINGUAS)

LOCAL_LANG_DIR=locale-langpack
SYSTEM_LANG_DIR := $(DESTDIR)$(PREFIX)/share/locale

VALAFLAGS := -g --enable-checking --target-glib=2.32 --thread --fatal-warnings --enable-experimental --enable-deprecated $(USER_VALAFLAGS)
ifdef UNITY_SUPPORT
VALAFLAGS := $(VALAFLAGS) --define UNITY_SUPPORT
endif

ifdef WITH_GPHOTO_25
VALAFLAGS := $(VALAFLAGS) --define WITH_GPHOTO_25
endif

DEFINES := _PREFIX='"$(PREFIX)"' _VERSION='"$(VERSION)"' GETTEXT_PACKAGE='"$(GETTEXT_PACKAGE)"' \
	_LANG_SUPPORT_DIR='"$(SYSTEM_LANG_DIR)"' _LIB='"${LIB}"' _LIBEXECDIR='"$(LIBEXECDIR)"'

ifdef GITVER
DEFINES := $(DEFINES) _GIT_VERSION='"$(GITVER)"'
VALAFLAGS := $(VALAFLAGS) --define=_GITVERSION
endif

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
	Dimensions.vala \
	Box.vala \
	Photo.vala \
	Orientation.vala \
	BatchImport.vala \
	Dialogs.vala \
	Resources.vala \
	Debug.vala \
	ColorTransformation.vala \
	Properties.vala \
	CustomComponents.vala \
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
	MediaViewTracker.vala \
	UnityProgressBar.vala \
	Upgrades.vala 

THUMBNAILER_SRC_FILES = \
	shotwell-video-thumbnailer.vala

VAPI_FILES = \
	ExtendedPosix.vapi \
	LConv.vapi \
	libexif.vapi \
	libraw.vapi \
	webkitgtk-3.0.vapi \
	unique-3.0.vapi \
	unity.vapi

DEPS_FILES = \
	webkitgtk-3.0.deps \
	unique-3.0.deps \
	unity.deps

ifdef WITH_GPHOTO_25
GPHOTO_VAPI_FILE = vapi/gphoto-2.5/libgphoto2.vapi
else
GPHOTO_VAPI_FILE = vapi/gphoto-2.4/libgphoto2.vapi
endif

RESOURCE_FILES = \
	collection.ui \
	direct.ui \
	direct_context.ui \
	events_directory.ui \
	event.ui \
	fullscreen.ui \
	import_queue.ui \
	import.ui \
	media.ui \
	offline.ui \
	photo.ui \
	photo_context.ui \
	savedsearch.ui \
	search_bar.ui \
	search_sidebar_context.ui \
	set_background_dialog.glade \
	shotwell.glade \
	shotwell.xml \
	sidebar_default_context.ui \
	tag_sidebar_context.ui \
	tags.ui \
	top.ui \
	trash.ui 

SYS_INTEGRATION_FILES = \
	shotwell.appdata.xml \
	shotwell.desktop.head \
	shotwell-viewer.desktop.head \
	org.yorba.shotwell.gschema.xml \
	org.yorba.shotwell-extras.gschema.xml \
	shotwell.convert

SCHEMA_FILES := $(shell ls misc/*.gschema.xml)

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
	no-event.png \
	noninterpretable-video.png \
	one-event.png \
	one-star-filter-plus.svg \
	one-star.svg \
	one-tag.png \
	pin-toolbar.svg \
	publish.png \
	redeye.png \
	rejected.svg \
	shotwell-16.svg \
	shotwell-24.svg \
	shotwell.ico \
	shotwell-street.jpg \
	shotwell.svg \
	sprocket.png \
	straighten.svg \
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
	edit-straighten.page \
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
	other-plugins.page \
	raw.page \
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

ifdef WITH_GPHOTO_25
VAPI_DIRS += ./vapi/gphoto-2.5
else
VAPI_DIRS += ./vapi/gphoto-2.4
endif


HEADER_DIRS = \
	./vapi

LOCAL_PKGS = \
	ExtendedPosix \
	posix \
	LConv

EXT_PKGS = \
	atk \
	gdk-3.0 \
	gee-0.8 \
	gexiv2 \
	gio-unix-2.0 \
	glib-2.0 \
	gmodule-2.0 \
	gstreamer-1.0 \
	gstreamer-base-1.0 \
	gstreamer-pbutils-1.0 \
	gtk+-3.0 \
	gudev-1.0 \
	libexif \
	libgphoto2 \
	json-glib-1.0 \
	libraw \
	libsoup-2.4 \
	libxml-2.0 \
	sqlite3 \
	webkitgtk-3.0
ifdef UNITY_SUPPORT
EXT_PKGS += unity
endif

THUMBNAILER_PKGS = \
    gtk+-3.0 \
    gee-0.8 \
    gstreamer-1.0 \
    gstreamer-base-1.0

DIRECT_LIBS =

EXT_PKG_VERSIONS = \
	gee-0.8 >= 0.8.5 \
	gexiv2 >= 0.4.90 \
	gio-unix-2.0 >= 2.20 \
	glib-2.0 >= $(MIN_GLIB_VERSION) \
	gmodule-2.0 >= 2.24.0 \
	gstreamer-1.0 >= 1.0.0 \
	gstreamer-base-1.0 >= 1.0.0 \
	gstreamer-plugins-base-1.0 >= 1.0.0 \
	gstreamer-pbutils-1.0 >= 1.0.0 \
	gtk+-3.0 >= 3.6.0 \
	gudev-1.0 >= 145 \
	libexif >= 0.6.16 \
	libgphoto2 >= 2.4.2 \
	libraw >= 0.13.2 \
	libsoup-2.4 >= 2.26.0 \
	libxml-2.0 >= 2.6.32 \
	rest-0.7 >= 0.7 \
	sqlite3 >= 3.5.9 \
	webkitgtk-3.0 >= 1.4.0 

DIRECT_LIBS_VERSIONS =

VALA_PKGS = $(EXT_PKGS) $(LOCAL_PKGS)

ifndef BUILD_DIR
BUILD_DIR=src
endif

DESKTOP_APP_SHORT_NAME="Shotwell"
DESKTOP_APP_FULL_NAME="Shotwell Photo Manager"
DESKTOP_APPLICATION_COMMENT="Organize your photos"
DESKTOP_APPLICATION_CLASS="Photo Manager"
DESKTOP_APP_KEYWORDS="album;camera;cameras;crop;edit;enhance;export;gallery;image;images;import;organize;photo;photographs;photos;picture;pictures;photography;print;publish;rotate;share;tags;video;facebook;flickr;picasa;youtube;piwigo;"
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

MIGRATOR_DIR := settings-migrator
MIGRATOR_BIN := $(MIGRATOR_DIR)/$(PROGRAM_MIGRATOR)

EXPANDED_CORE_PO_FILES := $(foreach po,$(CORE_SUPPORTED_LANGUAGES),po/$(po).po)

EXPANDED_SRC_FILES := $(UNITIZED_SRC_FILES) $(foreach src,$(UNUNITIZED_SRC_FILES),src/$(src)) \
	$(UNITIZE_INITS) $(UNITIZE_ENTRIES)
EXPANDED_DIST_SRC_FILES := $(UNITIZED_SRC_FILES) $(foreach src,$(UNUNITIZED_SRC_FILES),src/$(src))
EXPANDED_C_FILES := $(foreach file,$(subst src,$(BUILD_DIR),$(EXPANDED_SRC_FILES)),$(file:.vala=.c))
EXPANDED_OBJ_FILES := $(foreach file,$(subst src,$(BUILD_DIR),$(EXPANDED_SRC_FILES)),$(file:.vala=.o))
EXPANDED_SYS_INTEGRATION_FILES := $(foreach file,$(SYS_INTEGRATION_FILES),misc/$(file))
EXPANDED_ICON_FILES := $(foreach file,$(ICON_FILES),icons/$(file))
EXPANDED_VAPI_FILES := $(foreach vapi,$(VAPI_FILES),vapi/$(vapi))
EXPANDED_DEPS_FILES := $(foreach deps,$(DEPS_FILES),vapi/$(deps))
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
	$(EXPANDED_DEPS_FILES) $(EXPANDED_SRC_HEADER_FILES) $(EXPANDED_RESOURCE_FILES) $(TEXT_FILES) \
	$(EXPANDED_ICON_FILES) $(EXPANDED_SYS_INTEGRATION_FILES) $(EXPANDED_CORE_PO_FILES) \
	po/LINGUAS po/POTFILES.in po/POTFILES.skip \
	$(EXPANDED_HELP_FILES) $(EXPANDED_HELP_IMAGES) apport/shotwell.py $(UNIT_RESOURCES) $(UNIT_MKS) \
	unitize.mk units.mk $(PC_INPUT) $(PLUGINS_DIST_FILES) \
	vapi/gphoto-2.5/libgphoto2.vapi vapi/gphoto-2.4/libgphoto2.vapi \
	$(EXPANDED_THUMBNAILER_SRC_FILES) $(MIGRATOR_BIN)

DIST_TAR = $(PROGRAM)-$(VERSION).tar
DIST_TAR_XZ = $(DIST_TAR).xz
PACKAGE_ORIG_XZ = $(PROGRAM)_`parsechangelog | grep Version | sed 's/.*: //'`.orig.tar.xz

VALAFLAGS := $(VALAFLAGS) $(VALA_DEFINES) --vapidir=plugins/

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

CFLAGS += $(PROFILE_FLAGS) $(REQUIRED_CFLAGS)
PLUGIN_CFLAGS += $(PROFILE_FLAGS) $(REQUIRED_CFLAGS)

# Required for gudev-1.0
CFLAGS += -DG_UDEV_API_IS_SUBJECT_TO_CHANGE

all: pkgcheck valacheck desktop

ifdef ENABLE_BUILD_FOR_GLADE
all: $(PLUGINS_DIR) lib$(PROGRAM).so $(PROGRAM) $(PC_FILE)
else
all: $(PLUGINS_DIR) $(PROGRAM) $(PC_FILE)
endif


include src/plugins/mk/interfaces.mk

$(LANG_STAMP): $(EXPANDED_CORE_PO_FILES)
	@$(foreach po,$(CORE_SUPPORTED_LANGUAGES),`mkdir -p $(LOCAL_LANG_DIR)/$(po)/LC_MESSAGES ; \
		msgfmt -c -o $(LOCAL_LANG_DIR)/$(po)/LC_MESSAGES/shotwell.mo po/$(po).po`)
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
	rm -f misc/gschemas.compiled

package:
	$(MAKE) dist
	cp $(DIST_TAR_XZ) $(PACKAGE_ORIG_XZ)
	rm -f $(DIST_TAR_XZ)

misc/shotwell.desktop: misc/shotwell.desktop.head $(EXPANDED_CORE_PO_FILES)
	cp misc/shotwell.desktop.head misc/shotwell.desktop
	@ $(foreach lang,$(CORE_SUPPORTED_LANGUAGES), echo X-GNOME-FullName[$(lang)]=`TEXTDOMAINDIR=locale-langpack \
		LANGUAGE=$(lang) gettext --domain=shotwell $(DESKTOP_APP_FULL_NAME)` \
		>> misc/shotwell.desktop ; \
		echo GenericName[$(lang)]=`TEXTDOMAINDIR=locale-langpack LANGUAGE=$(lang) \
		gettext --domain=shotwell $(DESKTOP_APPLICATION_CLASS)` >> misc/shotwell.desktop ; \
		echo Comment[$(lang)]=`TEXTDOMAINDIR=locale-langpack LANGUAGE=$(lang) gettext \
		--domain=shotwell $(DESKTOP_APPLICATION_COMMENT)` >> misc/shotwell.desktop ; \
		echo Keywords[$(lang)]=`TEXTDOMAINDIR=locale-langpack LANGUAGE=$(lang) gettext \
		--domain=shotwell $(DESKTOP_APP_KEYWORDS)` >> misc/shotwell.desktop ;) 
ifndef DISABLE_DESKTOP_VALIDATE
	@ desktop-file-validate misc/shotwell.desktop 1>misc/shotwell.desktop.errors 2>&1; \
	if test -s misc/shotwell.desktop.errors; then \
		echo -e "\nThe file misc/shotwell.desktop.head or one of the .po files contains errors and may need to be edited.\nPlease see the file misc/shotwell.desktop.errors for details."; \
		exit 1; \
	else rm -f misc/shotwell.desktop.errors; \
	fi
endif
	
misc/shotwell-viewer.desktop: misc/shotwell-viewer.desktop.head $(EXPANDED_CORE_PO_FILES)
	cp misc/shotwell-viewer.desktop.head misc/shotwell-viewer.desktop
	$(foreach lang,$(CORE_SUPPORTED_LANGUAGES), echo X-GNOME-FullName[$(lang)]=`TEXTDOMAINDIR=locale-langpack \
		LANGUAGE=$(lang) gettext --domain=shotwell $(DESKTOP_APP_FULL_NAME)` \
		echo X-GNOME-FullName[$(lang)]=`TEXTDOMAINDIR=locale-langpack LANGUAGE=$(lang) gettext \
		--domain=shotwell $(DIRECT_EDIT_DESKTOP_APP_FULL_NAME)` >> misc/shotwell-viewer.desktop ; \
		echo GenericName[$(lang)]=`TEXTDOMAINDIR=locale-langpack LANGUAGE=$(lang) gettext \
		--domain=shotwell $(DIRECT_EDIT_DESKTOP_APPLICATION_CLASS)` >> misc/shotwell-viewer.desktop ;)
ifndef DISABLE_DESKTOP_VALIDATE
	@ desktop-file-validate misc/shotwell-viewer.desktop 1>misc/shotwell-viewer.desktop.errors 2>&1; \
	if test -s misc/shotwell-viewer.desktop.errors; then \
		echo -e S"\nThe file misc/shotwell-viewer.desktop.head or one of the .po files contains errors and may need to be edited.\nPlease see the file misc/shotwell-viewer.desktop.errors for details."; \
		exit 1; \
	else rm -f misc/shotwell-viewer.desktop.errors; \
	fi
endif

.PHONY: desktop
desktop: misc/shotwell.desktop misc/shotwell-viewer.desktop

.PHONY: dist
dist:
	mkdir -p $(PROGRAM)-$(VERSION)
	cp --parents --preserve $(DIST_FILES) $(PROGRAM)-$(VERSION)
	tar --xz -cvf $(DIST_TAR_XZ) $(PROGRAM)-$(VERSION)
	rm -rf $(PROGRAM)-$(VERSION)

distclean: clean
	rm -f configure.mk
	rm -f $(DIST_TAR_XZ)
	@$(MAKE) --directory=plugins distclean

.PHONY: install
install:
	touch $(LANG_STAMP)
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	$(INSTALL_PROGRAM) $(PROGRAM) $(DESTDIR)$(PREFIX)/bin
	mkdir -p $(DESTDIR)$(LIBEXECDIR)
	$(INSTALL_PROGRAM) $(THUMBNAILER_BIN) $(DESTDIR)$(LIBEXECDIR)
	$(INSTALL_PROGRAM) $(MIGRATOR_BIN) $(DESTDIR)$(LIBEXECDIR)
	mkdir -p $(DESTDIR)$(PREFIX)/share/shotwell/icons
	$(INSTALL_DATA) icons/* $(DESTDIR)$(PREFIX)/share/shotwell/icons
	mkdir -p $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps
	$(INSTALL_DATA) icons/shotwell.svg $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps
	mkdir -p $(DESTDIR)$(PREFIX)/share/icons/hicolor/16x16/apps
	$(INSTALL_DATA) icons/shotwell-16.svg $(DESTDIR)$(PREFIX)/share/icons/hicolor/16x16/apps/shotwell.svg
	mkdir -p $(DESTDIR)$(PREFIX)/share/icons/hicolor/24x24/apps
	$(INSTALL_DATA) icons/shotwell-24.svg $(DESTDIR)$(PREFIX)/share/icons/hicolor/24x24/apps/shotwell.svg
	mkdir -p $(DESTDIR)$(PREFIX)/share/glib-2.0/schemas
	$(INSTALL_DATA) misc/org.yorba.shotwell.gschema.xml $(DESTDIR)$(PREFIX)/share/glib-2.0/schemas
	$(INSTALL_DATA) misc/org.yorba.shotwell-extras.gschema.xml $(DESTDIR)$(PREFIX)/share/glib-2.0/schemas
ifndef DISABLE_SCHEMAS_COMPILE
	glib-compile-schemas $(DESTDIR)$(PREFIX)/share/glib-2.0/schemas
endif
ifndef DISABLE_GSETTINGS_CONVERT_INSTALL
	mkdir -p $(DESTDIR)/usr/share/GConf/gsettings
	$(INSTALL_DATA) misc/shotwell.convert $(DESTDIR)/usr/share/GConf/gsettings
endif
ifndef DISABLE_ICON_UPDATE
	-gtk-update-icon-cache -t -f $(DESTDIR)$(PREFIX)/share/icons/hicolor || :
endif
	mkdir -p $(DESTDIR)$(PREFIX)/share/shotwell/ui
	$(INSTALL_DATA) ui/* $(DESTDIR)$(PREFIX)/share/shotwell/ui
	mkdir -p $(DESTDIR)$(PREFIX)/share/applications
	mkdir -p $(DESTDIR)$(PREFIX)/share/appdata
	$(INSTALL_DATA) misc/shotwell.desktop $(DESTDIR)$(PREFIX)/share/applications
	$(INSTALL_DATA) misc/shotwell-viewer.desktop $(DESTDIR)$(PREFIX)/share/applications
	$(INSTALL_DATA) misc/shotwell.appdata.xml $(DESTDIR)$(PREFIX)/share/appdata
ifndef DISABLE_DESKTOP_UPDATE
	-update-desktop-database || :
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
	test -d $(DESTDIR)$(PREFIX)/$(LIB)/pkgconfig || mkdir -p $(DESTDIR)$(PREFIX)/$(LIB)/pkgconfig
	$(INSTALL_DATA) $(PC_FILE) $(DESTDIR)$(PREFIX)/$(LIB)/pkgconfig
endif

# Old versions of Makefile installed util binaries to $(PREFIX)/bin, so uninstall from there for now
uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/$(PROGRAM)
	rm -f $(DESTDIR)$(PREFIX)/bin/$(PROGRAM_THUMBNAILER)
	rm -f $(DESTDIR)$(PREFIX)/bin/$(PROGRAM_MIGRATOR)
	rm -f $(DESTDIR)$(LIBEXECDIR)/$(PROGRAM_THUMBNAILER)
	rm -f $(DESTDIR)$(LIBEXECDIR)/$(PROGRAM_MIGRATOR)
	rm -fr $(DESTDIR)$(PREFIX)/share/shotwell
	rm -f $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/shotwell.svg
	rm -f $(DESTDIR)$(PREFIX)/share/icons/hicolor/16x16/apps/shotwell.svg
	rm -f $(DESTDIR)$(PREFIX)/share/icons/hicolor/24x24/apps/shotwell.svg
	rm -f $(DESTDIR)$(PREFIX)/share/applications/shotwell.desktop
	rm -f $(DESTDIR)$(PREFIX)/share/applications/shotwell-viewer.desktop
	rm -f $(DESTDIR)$(PREFIX)/share/appdata/shotwell.appdata.xml
ifndef DISABLE_DESKTOP_UPDATE
	-update-desktop-database || :
endif
ifndef DISABLE_HELP_INSTALL
	rm -rf $(DESTDIR)$(PREFIX)/share/gnome/help/shotwell
endif
ifdef ENABLE_APPORT_HOOK_INSTALL
	rm -f $(DESTDIR)$(PREFIX)/share/apport/package-hooks/shotwell.py
endif
	$(foreach lang,$(CORE_SUPPORTED_LANGUAGES),`rm -f $(SYSTEM_LANG_DIR)/$(lang)/LC_MESSAGES/shotwell.mo`)
	rm -rf $(DESTDIR)$(PREFIX)/$(LIB)/shotwell/plugins/builtin
ifdef INSTALL_HEADERS
	rm -rf $(DESTDIR)$(PREFIX)/include/shotwell
	rm -f $(foreach vapi,$(PLUGIN_VAPI),$(DESTDIR)$(PREFIX)/share/vala/vapi/$(notdir $(vapi)))
	rm -f $(foreach dep,$(PLUGIN_DEPS),$(DESTDIR)$(PREFIX)/share/vala/vapi/$(notdir $(dep)))
	rm -f $(DESTDIR)$(PREFIX)/$(LIB)/pkgconfig/$(PC_FILE)
endif
	rm -f $(DESTDIR)$(PREFIX)/share/glib-2.0/schemas/org.yorba.shotwell.gschema.xml
	rm -f $(DESTDIR)$(PREFIX)/share/glib-2.0/schemas/org.yorba.shotwell-extras.gschema.xml
ifndef DISABLE_SCHEMAS_COMPILE
	glib-compile-schemas $(DESTDIR)$(PREFIX)/share/glib-2.0/schemas
endif
ifndef DISABLE_GSETTINGS_CONVERT_INSTALL
	rm -f $(DESTDIR)/usr/share/GConf/gsettings/shotwell.convert
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
$(VALA_STAMP): $(EXPANDED_SRC_FILES) $(EXPANDED_VAPI_FILES) $(GPHOTO_VAPI_FILE) $(EXPANDED_SRC_HEADER_FILES)
	$(call check_valac_version)
	@echo Compiling Vala code...
	@mkdir -p $(BUILD_DIR)
	$(VALAC) --ccode --directory=$(BUILD_DIR) --basedir=src \
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
	$(CC) -c $(VALA_CFLAGS) $(CFLAGS) -o $@ $<

$(PROGRAM): $(EXPANDED_OBJ_FILES) $(RESOURCES) $(LANG_STAMP) $(THUMBNAILER_BIN) misc/gschemas.compiled
	$(CC) $(EXPANDED_OBJ_FILES) $(CFLAGS) $(LDFLAGS) $(RESOURCES) $(VALA_LDFLAGS) $(EXPORT_FLAGS) -o $@

misc/gschemas.compiled: $(SCHEMA_FILES)
	rm -f misc/gschemas.compiled
	glib-compile-schemas misc

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
	$(CC) $(EXPANDED_OBJ_FILES) $(CFLAGS) $(LDFLAGS) $(RESOURCES) $(VALA_LDFLAGS) $(EXPORT_FLAGS) -shared -o $@

.PHONY: pkgcheck
pkgcheck:
	@if ! test -f configure.mk; then echo "Please run ./configure first."; exit 2; fi 

.PHONY: valacheck
valacheck:
	@ $(VALAC) --version >/dev/null 2>/dev/null || ( echo 'Shotwell requires Vala compiler $(MIN_VALAC_VERSION) or greater.  No valac found in path or $$VALAC.'; exit 1 )
	@ ./chkver min $(VALAC_VERSION) $(MIN_VALAC_VERSION) || ( echo 'Shotwell requires Vala compiler $(MIN_VALAC_VERSION) or greater.  You are running' $(VALAC_VERSION) '\b.'; exit 1 )
	$(if $(MAX_VALAC_VERSION),\
		@ ./chkver max $(VALAC_VERSION) $(MAX_VALAC_VERSION) || ( echo 'Shotwell cannot be built by Vala compiler $(MAX_VALAC_VERSION) or greater.  You are running' $(VALAC_VERSION) '\b.'; exit 1 ),)



ifndef ASSUME_PKGS
ifdef EXT_PKG_VERSIONS
	@pkg-config --print-errors --exists '$(EXT_PKG_VERSIONS) $(DIRECT_LIBS_VERSIONS)'
endif
ifdef EXT_PKGS
	@pkg-config --print-errors --exists $(EXT_PKGS) $(DIRECT_LIBS_VERSIONS)
endif
endif
	@ type msgfmt > /dev/null || ( echo 'msgfmt (usually found in the gettext package) is missing and is required to build Shotwell. ' ; exit 1 )
ifndef DISABLE_DESKTOP_VALIDATE
	@ type desktop-file-validate > /dev/null || ( echo 'desktop-file-validate (usually found in the desktop-file-utils package) is missing and is required to build Shotwell. ' ; exit 1 )
endif
