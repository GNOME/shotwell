iconthemedir = $(datadir)/icons/hicolor

appicon16dir = $(iconthemedir)/16x16/apps
appicon22dir = $(iconthemedir)/22x22/apps
appicon24dir = $(iconthemedir)/24x24/apps
appicon32dir = $(iconthemedir)/32x32/apps
appicon48dir = $(iconthemedir)/48x48/apps
appicon256dir = $(iconthemedir)/256x256/apps
appiconscalabledir = $(iconthemedir)/scalable/apps
appiconsymbolicdir = $(iconthemedir)/symbolic/apps

dist_appicon16_DATA = \
					  	16x16/apps/shotwell.png
dist_appicon22_DATA = \
					  	22x22/apps/shotwell.png
dist_appicon24_DATA = \
					  	24x24/apps/shotwell.png
dist_appicon32_DATA = \
					  	32x32/apps/shotwell.png
dist_appicon48_DATA = \
					  	48x48/apps/shotwell.png
dist_appicon256_DATA = \
					   	256x256/apps/shotwell.png
dist_appiconsymbolic_DATA = \
								symbolic/apps/shotwell-symbolic.svg

UPDATE_ICON_CACHE = gtk-update-icon-cache --ignore-theme-index --force

install-data-hook: install-update-icon-cache
uninstall-hook: uninstall-update-icon-cache

install-update-icon-cache:
		$(AM_V_at)$(POST_INSTALL)
			test -n "$(DESTDIR)" || $(UPDATE_ICON_CACHE) "$(iconthemedir)"

uninstall-update-icon-cache:
		$(AM_V_at)$(POST_UNINSTALL)
			test -n "$(DESTDIR)" || $(UPDATE_ICON_CACHE) "$(iconthemedir)"


-include $(top_srcdir)/git.mk
