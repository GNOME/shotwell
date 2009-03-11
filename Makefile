
TARGET = photo

VALAC_OPTS = -g --enable-checking

SRC_FILES = \
	main.vala \
	AppWindow.vala \
	CollectionPage.vala \
	Thumbnail.vala \
	PhotoTable.vala

PKGS = \
	gtk+-2.0 \
	sqlite3

all: $(TARGET)

clean:
	rm -f $(TARGET)

$(TARGET): $(SRC_FILES) Makefile
	valac $(VALAC_OPTS) $(foreach pkg,$(PKGS),--pkg $(pkg)) $(SRC_FILES) -o $(TARGET)

