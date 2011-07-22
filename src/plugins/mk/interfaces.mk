
PLUGIN_INTERFACES := \
	src/plugins/SpitInterfaces.vala \
	src/plugins/TransitionsInterfaces.vala \
	src/plugins/PublishingInterfaces.vala

PLUGIN_PKG_REQS := \
	gobject-2.0 \
	glib-2.0 \
	gdk-3.0 \
	gtk+-3.0

PLUGIN_VAPI := plugins/shotwell-plugin-dev-1.0.vapi
PLUGIN_HEADER := $(PLUGIN_VAPI:.vapi=.h)
PLUGIN_DEPS := $(PLUGIN_VAPI:.vapi=.deps)

$(PLUGIN_DEPS): src/plugins/mk/interfaces.mk
	rm -f $@
	$(foreach pkg,$(PLUGIN_PKG_REQS),`echo $(pkg) >> $@`)

$(PLUGIN_HEADER): $(PLUGIN_VAPI)

$(PLUGIN_VAPI): $(PLUGIN_INTERFACES) src/plugins/mk/interfaces.mk
	$(call check_valac_version)
	$(VALAC) -c $(VALAFLAGS) -X -DGETTEXT_PACKAGE='"shotwell"' -X -I. $(foreach pkg,$(PLUGIN_PKG_REQS),--pkg=$(pkg)) --includedir=plugins --vapi=$@ --header=$(basename $@).h $(PLUGIN_INTERFACES)
	$(foreach src,$(PLUGIN_INTERFACES),`rm $(notdir $(src)).o`)

