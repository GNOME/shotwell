
PLUGINS := \
	shotwell-transitions \
	shotwell-publishing

PLUGINS_RC := \
	plugins/shotwell-publishing/facebook.png \
	plugins/shotwell-publishing/flickr.png \
	plugins/shotwell-publishing/picasa.png \
	plugins/shotwell-publishing/youtube.png \
	plugins/shotwell-transitions/slideshow-plugin.png

EXTRA_PLUGINS := \
	shotwell-publishing-extras

EXTRA_PLUGINS_RC := \
	plugins/shotwell-publishing-extras/yandex_publish_model.glade \
	plugins/shotwell-publishing-extras/piwigo.png \
	plugins/shotwell-publishing-extras/piwigo_authentication_pane.glade

ALL_PLUGINS := $(PLUGINS) $(EXTRA_PLUGINS)

