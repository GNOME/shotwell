PROGRAM = shotwell

VERSION = 0.8.1+trunk
GETTEXT_PACKAGE = $(PROGRAM)
BUILD_ROOT = 1

VALAC := valac
VALAC_VERSION := `$(VALAC) --version | awk '{print $$2}'`
MIN_VALAC_VERSION := 0.9.8
MAX_VALAC_VERSION := 0.11.0
INSTALL_PROGRAM := install
INSTALL_DATA := install -m 644

# defaults that may be overridden by configure.mk
PREFIX=/usr/local
SCHEMA_FILE_DIR=/etc/gconf/schemas
BUILD_RELEASE=1

-include configure.mk

VALAFLAGS = -g --enable-checking --thread $(USER_VALAFLAGS)
DEFINES=_PREFIX='"$(PREFIX)"' _VERSION='"$(VERSION)"' GETTEXT_PACKAGE='"$(GETTEXT_PACKAGE)"' \
     _LANG_SUPPORT_DIR='"$(SYSTEM_LANG_DIR)"'

EXPORT_FLAGS = -export-dynamic

SUPPORTED_LANGUAGES=fr de it es pl et sv sk lv pt bg bn nl da zh_CN el ru pa hu en_GB uk ja fi zh_TW cs nb id th sl hr ar ast ro sr lt gl tr ca ko kk pt_BR eu he mk
LOCAL_LANG_DIR=locale-langpack
SYSTEM_LANG_DIR=$(DESTDIR)$(PREFIX)/share/locale

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
	ImportPage.vala \
	GPhoto.vala \
	SortedList.vala \
	EventsDirectoryPage.vala \
	Dimensions.vala \
	Box.vala \
	Photo.vala \
	Orientation.vala \
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
	AppDirs.vala \
	PixbufCache.vala \
	WebConnectors.vala \
	FacebookConnector.vala \
	CommandManager.vala \
	Commands.vala \
	SlideshowPage.vala \
	LibraryFiles.vala \
	FlickrConnector.vala \
	YandexConnector.vala \
	Printing.vala \
	Tag.vala \
	TagPage.vala \
	PicasaConnector.vala \
	PiwigoConnector.vala \
	YouTubeConnector.vala \
	Screensaver.vala \
	PhotoFileAdapter.vala \
	PhotoFileFormat.vala \
	PhotoFileSniffer.vala \
	PhotoMetadata.vala \
	GRaw.vala \
	GdkSupport.vala \
	JfifSupport.vala \
	RawSupport.vala \
	MimicManager.vala \
	TrashPage.vala \
	PngSupport.vala \
	Exporter.vala \
	DirectoryMonitor.vala \
	LibraryMonitor.vala \
	OfflinePage.vala \
	LastImportPage.vala \
	VideoSupport.vala \
	VideosPage.vala \
	Tombstone.vala \
	MetadataWriter.vala \
	Application.vala \
	TimedQueue.vala \
	MediaPage.vala \
	MediaDataRepresentation.vala \
	DesktopIntegration.vala \
	FlaggedPage.vala \
	MediaInterfaces.vala \
	MediaMetadata.vala \
	VideoMetadata.vala \
	MediaMonitor.vala \
	PhotoMonitor.vala \
	VideoMonitor.vala

VAPI_FILES = \
	libexif.vapi \
	libgphoto2.vapi \
	ExtendedPosix.vapi \
	LConv.vapi \
	libraw.vapi

RESOURCE_FILES = \
	photo.ui \
	collection.ui \
	import.ui \
	fullscreen.ui \
	import_queue.ui \
	events_directory.ui \
	event.ui \
	direct.ui \
	tags.ui \
	trash.ui \
	offline.ui \
	media.ui \
	yandex_publish_model.glade \
	shotwell.glade \
	set_background_dialog.glade \
	video.ui

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
	zoom-out.png

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
	gnome-vfs-2.0 \
	gstreamer-0.10 \
	gstreamer-base-0.10 \
	gtk+-2.0 \
	glib-2.0 \
	gudev-1.0 \
	json-glib-1.0 \
	libexif \
	libgphoto2 \
	libsoup-2.4 \
	libxml-2.0 \
	sqlite3 \
	unique-1.0 \
	webkit-1.0 \
	gmodule-2.0

DIRECT_LIBS =

LIBRAW_PKG = \
	libraw

# libraw is handled separately (see note below); when libraw-config is no longer needed, the version
# should be added to this list
EXT_PKG_VERSIONS = \
	gconf-2.0 >= 2.22.0 \
	gee-1.0 >= 0.5.0 \
	gexiv2 >= 0.2.0 \
	gnome-vfs-2.0 >= 1:2.24.3 \
	gtk+-2.0 >= 2.18.0 \
	glib-2.0 >= 2.26.0 \
	gstreamer-0.10 >= 0.10.28 \
	gstreamer-base-0.10 >= 0.10.28 \
	gudev-1.0 >= 145 \
	json-glib-1.0 >= 0.7.6 \
	libexif >= 0.6.16 \
	libgphoto2 >= 2.4.2 \
	libsoup-2.4 >= 2.26.0 \
	libxml-2.0 >= 2.6.32 \
	sqlite3 >= 3.5.9 \
	unique-1.0 >= 1.0.0 \
	webkit-1.0 >= 1.1.5 \
	gmodule-2.0 >= 2.24.0

DIRECT_LIBS_VERSIONS =

LIBRAW_VERSION = \
	0.9.0

VALA_PKGS = $(EXT_PKGS) $(LOCAL_PKGS) $(LIBRAW_PKG)

ifndef BUILD_DIR
BUILD_DIR=src
endif

DESKTOP_APPLICATION_NAME="Shotwell Photo Manager"
DESKTOP_APPLICATION_COMMENT="Organize your photos"
DESKTOP_APPLICATION_CLASS="Photo Manager"
DIRECT_EDIT_DESKTOP_APPLICATION_NAME="Shotwell Photo Viewer"
DIRECT_EDIT_DESKTOP_APPLICATION_CLASS="Photo Viewer"
TEMPORARY_DESKTOP_FILES = misc/shotwell.desktop misc/shotwell-viewer.desktop

# Process the units
UNIT_MKS := $(foreach unit,$(UNITS),src/$(unit)/mk/$(notdir $(unit)).mk)
include $(UNIT_MKS)

UNITIZE_DIR := src/.unitize
UNITIZE_ENTRIES := $(foreach group,$(APP_GROUPS),$(UNITIZE_DIR)/_$(group)_unitize_entry.vala)
UNITIZE_INITS := $(foreach nm,$(UNIT_NAMESPACES),$(UNITIZE_DIR)/_$(nm)Internals.vala)
UNITIZE_STAMP := $(UNITIZE_DIR)/.unitized

PLUGINS_DIR := plugins
PLUGINS_SO := $(foreach plugin,$(PLUGINS),$(PLUGINS_DIR)/$(plugin)/$(plugin).so)

EXPANDED_PO_FILES := $(foreach po,$(SUPPORTED_LANGUAGES),po/$(po).po)
EXPANDED_SRC_FILES := $(UNITIZED_SRC_FILES) $(foreach src,$(UNUNITIZED_SRC_FILES),src/$(src)) \
	$(UNITIZE_INITS) $(UNITIZE_ENTRIES)
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

DIST_FILES = Makefile configure chkver $(EXPANDED_SRC_FILES) $(EXPANDED_VAPI_FILES) \
	$(EXPANDED_SRC_HEADER_FILES) $(EXPANDED_RESOURCE_FILES) $(TEXT_FILES) $(EXPANDED_ICON_FILES) \
	$(EXPANDED_SYS_INTEGRATION_FILES) $(EXPANDED_PO_FILES) po/shotwell.pot libraw-config \
	$(EXPANDED_HELP_FILES) $(EXPANDED_HELP_IMAGES) apport/shotwell.py $(UNIT_RESOURCES) $(UNIT_MKS) \
	unitize.mk units.mk

DIST_TAR = $(PROGRAM)-$(VERSION).tar
DIST_TAR_BZ2 = $(DIST_TAR).bz2
DIST_TAR_GZ = $(DIST_TAR).gz
PACKAGE_ORIG_GZ = $(PROGRAM)_`parsechangelog | grep Version | sed 's/.*: //'`.orig.tar.gz

VALAFLAGS := --vapidir=plugins/

VALA_CFLAGS := `pkg-config --cflags $(EXT_PKGS) $(DIRECT_LIBS) gthread-2.0` \
	$(foreach hdir,$(HEADER_DIRS),-I$(hdir)) \
	$(foreach def,$(DEFINES),-D$(def))

VALA_LDFLAGS := `pkg-config --libs $(EXT_PKGS) $(DIRECT_LIBS) gthread-2.0`

# setting CFLAGS in configure.mk overrides build type
ifndef CFLAGS
ifdef BUILD_DEBUG
CFLAGS = -O0 -g -pipe -fPIC
else
CFLAGS = -O2 -g -pipe -fPIC
endif
endif

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

ifdef ENABLE_BUILD_FOR_GLADE
all: $(PLUGINS_DIR) lib$(PROGRAM).so $(PROGRAM)
else
all: $(PLUGINS_DIR) $(PROGRAM)
endif

include src/plugins/mk/interfaces.mk

$(LANG_STAMP): $(EXPANDED_PO_FILES)
	@$(foreach po,$(SUPPORTED_LANGUAGES),`mkdir -p $(LOCAL_LANG_DIR)/$(po)/LC_MESSAGES ; \
		msgfmt -o $(LOCAL_LANG_DIR)/$(po)/LC_MESSAGES/shotwell.mo po/$(po).po`)
	@touch $(LANG_STAMP)

clean:
	rm -f $(EXPANDED_C_FILES)
	rm -f $(EXPANDED_OBJ_FILES)
	rm -f $(VALA_STAMP)
	rm -rf $(PROGRAM)-$(VERSION)
	rm -f $(PROGRAM)
	rm -rf $(LOCAL_LANG_DIR)
	rm -f $(LANG_STAMP)
	rm -f $(TEMPORARY_DESKTOP_FILES)
	rm -f lib$(PROGRAM).so
	rm -rf $(UNITIZE_DIR)
	rm -f $(PLUGIN_VAPIS)
	rm -f $(PLUGIN_HEADERS)
	rm -f $(PLUGIN_DEPS)
	rm -f $(PLUGINS_SO)
	@$(MAKE) --directory=plugins clean

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

dist: $(DIST_FILES)
	mkdir -p $(PROGRAM)-$(VERSION)
	cp --parents $(DIST_FILES) $(PROGRAM)-$(VERSION)
	tar --bzip2 -cvf $(DIST_TAR_BZ2) $(PROGRAM)-$(VERSION)
	tar --gzip -cvf $(DIST_TAR_GZ) $(PROGRAM)-$(VERSION)
	rm -rf $(PROGRAM)-$(VERSION)

distclean: clean
	rm -f configure.mk
	@$(MAKE) --directory=plugins distclean

.PHONY: install
install:
	cp misc/shotwell.desktop.head misc/shotwell.desktop
	cp misc/shotwell-viewer.desktop.head misc/shotwell-viewer.desktop
	$(foreach lang,$(SUPPORTED_LANGUAGES), echo Name[$(lang)]=`TEXTDOMAINDIR=locale-langpack \
		LANGUAGE=$(lang) gettext --domain=shotwell $(DESKTOP_APPLICATION_NAME)` \
		>> misc/shotwell.desktop ; \
		echo GenericName[$(lang)]=`TEXTDOMAINDIR=locale-langpack LANGUAGE=$(lang) \
		gettext --domain=shotwell $(DESKTOP_APPLICATION_CLASS)` >> misc/shotwell.desktop ; \
		echo Comment[$(lang)]=`TEXTDOMAINDIR=locale-langpack LANGUAGE=$(lang) gettext \
		--domain=shotwell $(DESKTOP_APPLICATION_COMMENT)` >> misc/shotwell.desktop ; \
		echo Name[$(lang)]=`TEXTDOMAINDIR=locale-langpack LANGUAGE=$(lang) gettext \
		--domain=shotwell $(DIRECT_EDIT_DESKTOP_APPLICATION_NAME)` >> misc/shotwell-viewer.desktop ; \
		echo GenericName[$(lang)]=`TEXTDOMAINDIR=locale-langpack LANGUAGE=$(lang) gettext \
		--domain=shotwell $(DIRECT_EDIT_DESKTOP_APPLICATION_CLASS)` >> misc/shotwell-viewer.desktop ;)
	touch $(LANG_STAMP)
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	$(INSTALL_PROGRAM) $(PROGRAM) $(DESTDIR)$(PREFIX)/bin
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
	-$(foreach lang,$(SUPPORTED_LANGUAGES),`mkdir -p $(SYSTEM_LANG_DIR)/$(lang)/LC_MESSAGES ; \
		$(INSTALL_DATA) $(LOCAL_LANG_DIR)/$(lang)/LC_MESSAGES/shotwell.mo \
		$(SYSTEM_LANG_DIR)/$(lang)/LC_MESSAGES/shotwell.mo`)
	mkdir -p $(DESTDIR)$(PREFIX)/lib/shotwell/plugins/builtin
	$(INSTALL_PROGRAM) $(PLUGINS_SO) $(DESTDIR)$(PREFIX)/lib/shotwell/plugins/builtin

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/$(PROGRAM)
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
	$(foreach lang,$(SUPPORTED_LANGUAGES),`rm -f $(SYSTEM_LANG_DIR)/$(lang)/LC_MESSAGES/shotwell.mo`)
	rm -rf $(DESTDIR)$(PREFIX)/lib/shotwell/plugins/builtin

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(UNITIZE_DIR):
	@mkdir -p $(UNITIZE_DIR)

$(UNITIZE_STAMP): $(UNITIZE_DIR) $(MAKE_FILES) src/unit/rc/UnitInternals.m4 src/unit/rc/unitize_entry.m4
	@$(foreach group,$(APP_GROUPS),\
		`m4 '--define=_APP_GROUP_=$(group)' '--define=_UNIT_ENTRY_POINTS_=$(foreach nm,$(UNIT_NAMESPACES),$(nm).init_entry,)' '--define=_UNIT_TERMINATE_POINTS_=$(foreach nm,$(UNIT_NAMESPACES),$(nm).terminate_entry,)' src/unit/rc/unitize_entry.m4 > $(UNITIZE_DIR)/_$(group)_unitize_entry.vala`)
	@$(foreach nm,$(UNIT_NAMESPACES),\
		`m4 '--define=_UNIT_NAME_=$(nm)' '--define=_UNIT_USES_INITS_=$($(nm)_USES_INITS)' '--define=_UNIT_USES_TERMINATORS_=$($(nm)_USES_TERMINATORS)' src/unit/rc/UnitInternals.m4 > $(UNITIZE_DIR)/_$(nm)Internals.vala`)
	@touch $@

$(UNITIZE_INITS) $(UNITIZE_ENTRIES): $(UNITIZE_STAMP)
	@

# EXPANDED_SRC_FILES includes UNITIZE_INITS and UNITIZE_ENTRY
$(VALA_STAMP): $(EXPANDED_SRC_FILES) $(EXPANDED_VAPI_FILES) $(EXPANDED_SRC_HEADER_FILES)
	$(call check_valac_version)
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
	@echo Compiling Vala code...
	@$(VALAC) --ccode --directory=$(BUILD_DIR) --basedir=src $(VALAFLAGS) \
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

$(PROGRAM): $(EXPANDED_OBJ_FILES) $(RESOURCES) $(LANG_STAMP)
	$(CC) $(EXPANDED_OBJ_FILES) $(CFLAGS) $(RESOURCES) $(VALA_LDFLAGS) `$(LIBRAW_CONFIG) --libs` $(EXPORT_FLAGS) -o $@

$(PLUGINS_SO): $(PLUGINS_DIR)
	@

.PHONY: $(PLUGINS_DIR)
$(PLUGINS_DIR): $(PLUGIN_VAPIS) $(PLUGIN_HEADERS) $(PLUGIN_DEPS)
	$(call check_valac_version)
	@$(MAKE) --directory=$@ PLUGINS_VERSION="$(VERSION)"

glade: lib$(PROGRAM).so

lib$(PROGRAM).so: $(EXPANDED_OBJ_FILES) $(RESOURCES) $(LANG_STAMP)
	$(CC) $(EXPANDED_OBJ_FILES) $(CFLAGS) $(RESOURCES) $(VALA_LDFLAGS) `$(LIBRAW_CONFIG) --libs` $(EXPORT_FLAGS) -shared -o $@

