
include plugins.mk

DIST_FILES := \
	Makefile \
	Makefile.plugin.mk \
	plugins.mk

.PHONY: all
all: $(PLUGINS)

.PHONY: $(PLUGINS)
$(PLUGINS):
	@$(MAKE) --directory=$@ PLUGINS_VERSION="$(PLUGINS_VERSION)"

.PHONY: clean
clean:
	$(foreach plugin,$(PLUGINS),$(MAKE) --directory=$(plugin) clean;)

.PHONY: cleantemps
cleantemps:
	$(foreach plugin,$(PLUGINS),$(MAKE) --directory=$(plugin) cleantemps;)

.PHONY: distclean
distclean:
	$(foreach plugin,$(PLUGINS),$(MAKE) --directory=$(plugin) distclean;)

.PHONY: listfiles
listfiles:
	@printf "$(foreach file,$(DIST_FILES), plugins/$(file)) "
	@$(foreach plugin,$(PLUGINS),$(MAKE) --directory=$(plugin) --no-print-directory listfiles;)

