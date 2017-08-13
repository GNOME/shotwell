gsettings_SCHEMAS = \
	org.yorba.shotwell.gschema.xml \
	org.yorba.shotwell-extras.gschema.xml

appstream_in_files = $(srcdir)/shotwell.appdata.xml.in
appstream_XML = \
	shotwell.appdata.xml

desktopdir = $(datadir)/applications
desktop_DATA = shotwell.desktop shotwell-viewer.desktop

$(appstream_XML) : $(appstream_in_files)
	$(AM_V_GEN) $(MSGFMT) --xml --template $< -d $(top_srcdir)/po -o $@

%.desktop : %.desktop.in
	$(AM_V_GEN) $(MSGFMT) --desktop --template $< -d $(top_srcdir)/po -o $@

@GSETTINGS_RULES@
@APPSTREAM_XML_RULES@

CLEANFILES = $(appstream_XML) $(desktop_DATA) $(desktop_in_files)

dist_noinst_DATA = \
	$(srcdir)/shotwell.desktop.in \
	$(srcdir)/shotwell-viewer.desktop.in \
	$(gsettings_SCHEMAS) \
	$(appstream_in_files)

-include $(top_srcdir)/git.mk
