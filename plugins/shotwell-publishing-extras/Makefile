
PLUGIN := shotwell-publishing-extras

PLUGIN_PKGS := \
	gtk+-3.0 \
	libsoup-2.4 \
	libxml-2.0 \
	webkit2gtk-4.0 \
	gee-0.8 \
	rest-0.7 \
	json-glib-1.0

SRC_FILES := \
	GalleryConnector.vala \
	shotwell-publishing-extras.vala \
	YandexPublishing.vala \
	TumblrPublishing.vala \
	RajcePublishing.vala \
	../../src/util/string.vala \
	../common/RESTSupport.vala

# RC_FILES must also be added to ../plugins.mk to ensure they're installed properly
RC_FILES := \
	gallery3.png \
	gallery3_authentication_pane.glade \
	gallery3_publishing_options_pane.glade \
	yandex_publish_model.glade \
	tumblr.png \
	tumblr_authentication_pane.glade \
	tumblr_publishing_options_pane.glade \
	rajce.png \
	rajce_authentication_pane.glade \
	rajce_publishing_options_pane.glade

include ../Makefile.plugin.mk

