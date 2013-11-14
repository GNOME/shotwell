
PLUGINS := \
	shotwell-transitions \
	shotwell-publishing \
	shotwell-data-imports

PLUGINS_RC := \
	plugins/shotwell-publishing/facebook.png \
	plugins/shotwell-publishing/facebook_publishing_options_pane.glade \
	plugins/shotwell-publishing/flickr.png \
	plugins/shotwell-publishing/flickr_publishing_options_pane.glade \
	plugins/shotwell-publishing/flickr_pin_entry_pane.glade \
	plugins/shotwell-publishing/picasa.png \
	plugins/shotwell-publishing/picasa_publishing_options_pane.glade \
	plugins/shotwell-publishing/youtube.png \
	plugins/shotwell-publishing/youtube_publishing_options_pane.glade \
	plugins/shotwell-publishing/piwigo.png \
	plugins/shotwell-publishing/piwigo_authentication_pane.glade \
	plugins/shotwell-publishing/piwigo_publishing_options_pane.glade \
	plugins/shotwell-transitions/slideshow-plugin.png

EXTRA_PLUGINS := \
	shotwell-publishing-extras

EXTRA_PLUGINS_RC := \
	plugins/shotwell-publishing-extras/yandex_publish_model.glade \
	plugins/shotwell-data-imports/f-spot-24.png \
	plugins/shotwell-publishing-extras/tumblr.png \
	plugins/shotwell-publishing-extras/tumblr_authentication_pane.glade \
	plugins/shotwell-publishing-extras/tumblr_publishing_options_pane.glade

ALL_PLUGINS := $(PLUGINS) $(EXTRA_PLUGINS)

