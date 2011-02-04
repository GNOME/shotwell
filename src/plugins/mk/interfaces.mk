
PLUGIN_VAPIS := \
	plugins/shotwell-spit-1.0.vapi \
	plugins/shotwell-transitions-1.0.vapi

PLUGIN_HEADERS := $(PLUGIN_VAPIS:.vapi=.h)
PLUGIN_DEPS := $(PLUGIN_VAPIS:.vapi=.deps)

$(PLUGIN_HEADERS): %.h: %.vapi

plugins/shotwell-spit-1.0.deps: plugins/shotwell-spit-1.0.vapi
	@echo "" > $@

plugins/shotwell-spit-1.0.vapi: src/plugins/SpitInterfaces.vala
	$(call check_valac_version)
	$(VALAC) -c $(VALAFLAGS) -X -I. --includedir=plugins --vapi=$@ --header=$(basename $@).h $<
	rm $(notdir $<).o

plugins/shotwell-transitions-1.0.deps: plugins/shotwell-transitions-1.0.vapi
	@printf "gdk-2.0\nshotwell-spit-1.0\n" > $@

plugins/shotwell-transitions-1.0.vapi: src/plugins/TransitionsInterfaces.vala plugins/shotwell-spit-1.0.vapi
	$(call check_valac_version)
	$(VALAC) -c $(VALAFLAGS) -X -I. --pkg=gdk-2.0 --pkg=shotwell-spit-1.0 --includedir=plugins --vapi=$@ --header=$(basename $@).h $<
	rm $(notdir $<).o
