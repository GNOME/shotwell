
TARGET = photo

VALAC_OPTS =

SRC_FILES = \
	main.vala \
	AppWindow.vala \
	CollectionPage.vala \
	Thumbnail.vala \
	PhotoTable.vala \
	ThumbnailCache.vala \
	image_util.vala \
	ThumbnailCacheTable.vala

PKGS = \
	gtk+-2.0 \
	sqlite3 \
	vala-1.0

all: $(TARGET)

clean:
	rm -f $(TARGET)

$(TARGET): $(SRC_FILES) Makefile
	valac $(VALAC_OPTS) $(foreach pkg,$(PKGS),--pkg $(pkg)) $(SRC_FILES) -o $(TARGET)

