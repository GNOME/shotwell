
PLUGIN := shotwell-data-imports

PLUGIN_PKGS := \
	gtk+-3.0 \
	gexiv2 \
	gee-1.0 \
	sqlite3

SRC_FILES := \
	shotwell-data-imports.vala \
	../common/VersionNumber.vala \
	../common/SqliteSupport.vala \
	FSpotImporter.vala \
	FSpotDatabaseBehavior.vala \
	FSpotDatabase.vala \
	FSpotDatabaseTable.vala \
	FSpotTableBehavior.vala \
	FSpotMetaTable.vala \
	FSpotPhotosTable.vala \
	FSpotPhotoTagsTable.vala \
	FSpotPhotoVersionsTable.vala \
	FSpotRollsTable.vala \
	FSpotTagsTable.vala

RC_FILES := \
	f-spot-24.png

include ../Makefile.plugin.mk

