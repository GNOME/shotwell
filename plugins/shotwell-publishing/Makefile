
PLUGIN := shotwell-publishing

PLUGIN_PKGS := \
	gtk+-3.0 \
	libsoup-2.4 \
	libxml-2.0 \
	webkitgtk-3.0 \
	gexiv2 \
	rest-0.7 \
	gee-1.0 \
	json-glib-1.0

SRC_FILES := \
	shotwell-publishing.vala \
	FacebookPublishing.vala \
	PicasaPublishing.vala \
	FlickrPublishing.vala \
	YouTubePublishing.vala \
	PiwigoPublishing.vala \
	../../src/util/string.vala \
	../common/RESTSupport.vala \
	../common/ui.vala

RC_FILES := \
	facebook.png \
	facebook_publishing_options_pane.glade \
	flickr.png \
	flickr_publishing_options_pane.glade \
	flickr_pin_entry_pane.glade \
	picasa.png \
	picasa_auth_code_entry_pane.glade \
    picasa_not_set_up_pane.glade \
	picasa_publishing_options_pane.glade \
	piwigo.png \
	piwigo_authentication_pane.glade \
	piwigo_publishing_options_pane.glade \
	youtube.png \
	youtube_publishing_options_pane.glade

include ../Makefile.plugin.mk

