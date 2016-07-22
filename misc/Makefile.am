gsettings_SCHEMAS = \
	org.yorba.shotwell.gschema.xml \
	org.yorba.shotwell-extras.gschema.xml

appdata_in_files = $(srcdir)/shotwell.appdata.xml.in
appdata_XML = \
	shotwell.appdata.xml

desktopdir = $(datadir)/applications
desktop_DATA = shotwell.desktop shotwell-viewer.desktop

$(appdata_XML) : $(appdata_in_files)
	$(AM_V_GEN) $(MSGFMT) --xml --template $< -d $(top_srcdir)/po -o $@

%.desktop.in : %.desktop.in.in
	$(AM_V_GEN) sed -e 's|@VERSION[@]|$(VERSION)|g' $< > $@

%.desktop : %.desktop.in
	$(AM_V_GEN) $(MSGFMT) --desktop --template $< -d $(top_srcdir)/po -o $@

@GSETTINGS_RULES@
@APPDATA_XML_RULES@

CLEANFILES = $(appdata_XML) $(desktop_DATA) $(desktop_in_files)

dist_noinst_DATA = \
	$(srcdir)/shotwell.desktop.in.in \
	$(srcdir)/shotwell-viewer.desktop.in.in \
	$(gsettings_SCHEMAS) \
	$(appdata_in_files)

-include $(top_srcdir)/git.mk
