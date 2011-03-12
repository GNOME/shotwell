
# Generic plug-in Makefile for Shotwell standard plugins.
#
# Requires PLUGIN and SRC_FILES be set to the name of the plugin binary (minus extension) and that 
# the directory is registered in plugins.mk.
#
# To use, include this file in each plug-in directory's Makefile after setting apropriate variables.
# Also be sure that each plug-in has a dummy_main() function to satisfy valac's linkage.
#
# NOTE: This file is called from the cwd of each directory, hence the relative paths should be
# read as such.

VALAC := valac
MAKE_FILES := Makefile ../Makefile.plugin.mk ../plugins.mk
HEADER_FILES := ../shotwell-plugin-dev-1.0.vapi ../shotwell-plugin-dev-1.0.h \
	../shotwell-plugin-dev-1.0.deps

include ../plugins.mk

# automatically include the shotwell-plugin-dev-1.0 package
PKGS := shotwell-plugin-dev-1.0 $(PKGS)

# automatically include the Resources.vala common file
SRC_FILES := ../common/Resources.vala $(SRC_FILES)

all: $(PLUGIN).so

$(PLUGIN).so: $(SRC_FILES) $(MAKE_FILES) $(HEADER_FILES)
	$(VALAC) -g --enable-checking --fatal-warnings --save-temps --main=dummy_main --vapidir=../ \
		$(foreach pkg,$(PKGS),--pkg=$(pkg)) \
		-X -I../.. -X --shared -X -fPIC -X -D_VERSION='"$(PLUGINS_VERSION)"' \
		-X -DGETTEXT_PACKAGE='"shotwell"' $(SRC_FILES) -o $@

.PHONY: cleantemps
cleantemps:
	@rm -f $(notdir $(SRC_FILES:.vala=.c)) $(notdir $(SRC_FILES:.vala=.o))

.PHONY: clean
clean: cleantemps
	@rm -f $(PLUGIN).so

.PHONY: distclean
distclean: clean

.PHONY: listfiles
listfiles:
	@printf "plugins/$(PLUGIN)/Makefile $(foreach file,$(SRC_FILES),plugins/$(PLUGIN)/$(file)) "

