
PLUGIN := shotwell-publishing-extras

PLUGIN_PKGS := \
	gtk+-3.0 \
	libsoup-2.4 \
	libxml-2.0 \
	webkitgtk-3.0 \
	gee-1.0 \
	rest-0.7 \
	json-glib-1.0

SRC_FILES := \
	shotwell-publishing-extras.vala \
	YandexPublishing.vala \
	TumblrPublishing.vala \
	../../src/util/string.vala \
	../common/RESTSupport.vala

RC_FILES := \
	yandex_publish_model.glade \
	tumblr.png \
	tumblr_authentication_pane.glade \
	tumblr_publishing_options_pane.glade

include ../Makefile.plugin.mk

