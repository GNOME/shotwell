all: photo

clean:
	rm -f photo

photo: main.vala AppWindow.vala CollectionPage.vala Thumbnail.vala Makefile
	valac -g --enable-checking --pkg gtk+-2.0 main.vala AppWindow.vala CollectionPage.vala Thumbnail.vala -o photo

