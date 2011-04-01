
include plugins.mk

DIST_FILES := \
	Makefile \
	Makefile.plugin.mk \
	plugins.mk

.PHONY: all
all: $(ALL_PLUGINS)

.PHONY: $(ALL_PLUGINS)
$(ALL_PLUGINS):
	@$(MAKE) --directory=$@ PLUGINS_VERSION="$(PLUGINS_VERSION)" USER_VALAFLAGS="$(USER_VALAFLAGS)" \
		PLUGIN_CFLAGS="$(PLUGIN_CFLAGS)"

.PHONY: clean
clean:
	$(foreach plugin,$(ALL_PLUGINS),$(MAKE) --directory=$(plugin) clean;)

.PHONY: cleantemps
cleantemps:
	$(foreach plugin,$(ALL_PLUGINS),$(MAKE) --directory=$(plugin) cleantemps;)

.PHONY: distclean
distclean:
	$(foreach plugin,$(ALL_PLUGINS),$(MAKE) --directory=$(plugin) distclean;)

.PHONY: listfiles
listfiles:
	@printf "$(foreach file,$(DIST_FILES), plugins/$(file)) "
	@$(foreach plugin,$(ALL_PLUGINS),$(MAKE) --directory=$(plugin) --no-print-directory listfiles;)

