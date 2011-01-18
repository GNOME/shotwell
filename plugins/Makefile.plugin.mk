
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
HEADER_FILES := ../shotwell-plugins-1.0.vapi ../shotwell-plugins-1.0.h

include ../plugins.mk

all: $(PLUGIN).so

$(PLUGIN).so: $(SRC_FILES) $(MAKE_FILES) $(HEADER_FILES)
	$(VALAC) --save-temps --main=dummy_main --pkg=shotwell-plugins-1.0 --vapidir=../ \
		-X -I../.. -X --shared -X -fPIC -X -D_VERSION='"$(PLUGINS_VERSION)"' $(SRC_FILES) -o $@

.PHONY: cleantemps
cleantemps:
	@rm -f $(SRC_FILES:.vala=.c) $(SRC_FILES:.vala=.o)

.PHONY: clean
clean: cleantemps
	@rm -f $(PLUGIN).so

.PHONY: distclean
distclean: clean

