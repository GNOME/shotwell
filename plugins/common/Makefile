
PLUGIN := libshotwell-plugin-common
PLUGIN_DIR := common

PLUGIN_PKGS := \
	gee-0.8 \
	libxml-2.0 \
	libsoup-2.4 \
	json-glib-1.0 \
	webkit2gtk-4.0

SRC_FILES := Resources.vala RESTSupport.vala

PLUGIN_EXTRAFLAGS := --vapi=shotwell-plugin-common.vapi \
	--header=shotwell-plugin-common.h

PLUGIN_EXTRALINKFLAGS :=

include ../Makefile.plugin.mk

