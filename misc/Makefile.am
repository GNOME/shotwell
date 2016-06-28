gsettings_SCHEMAS = \
	org.yorba.shotwell.gschema.xml \
	org.yorba.shotwell-extras.gschema.xml

appdata_XML = \
	shotwell.appdata.xml

desktopdir = $(datadir)/applications
desktop_in_files = $(srcdir)/shotwell.desktop.in $(srcdir)/shotwell-viewer.desktop.in
desktop_DATA = shotwell.desktop shotwell-viewer.desktop

$(desktop_in_files): $(srcdir)/shotwell.desktop.in.in $(srcdir)/shotwell-viewer.desktop.in.in
	$(AM_V_GEN) $(MSGFMT) --desktop --template $< -d $(top_srcdir)/po -o $@

# Substitute variables in a Desktop Entry file.
$(desktop_DATA): $(desktop_in_files)
	$(AM_V_GEN) sed -e 's|@VERSION[@]|$(VERSION)|g' $< > $@

@GSETTINGS_RULES@
@APPDATA_XML_RULES@
