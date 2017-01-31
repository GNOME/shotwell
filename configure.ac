AC_PREREQ([2.69])


dnl ***********************************************************************
dnl Define Versioning Information
dnl ***********************************************************************
m4_define([major_version],[0])
m4_define([minor_version],[24])
m4_define([micro_version],[5])
m4_define([package_version],[major_version.minor_version.micro_version])
m4_define([bug_report_url],[https://bugzilla.gnome.org/enter_bug.cgi?product=shotwell])
m4_define([api_version],[major_version])

AX_IS_RELEASE([micro-version])

m4_define([git_version],[m4_esyscmd(git rev-parse HEAD)])

dnl ***********************************************************************
dnl Initialize autoconf
dnl ***********************************************************************
AC_INIT([shotwell],[package_version],[bug_report_url])
AC_CONFIG_HEADERS([config.h])
AC_CONFIG_SRCDIR([NEWS])
AC_CONFIG_MACRO_DIR([m4])
AC_CONFIG_AUX_DIR([build-aux])
AC_SUBST([ACLOCAL_AMFLAGS], "-I m4")
AC_CANONICAL_HOST


dnl ***********************************************************************
dnl Make version information available to autoconf files
dnl ***********************************************************************
AC_SUBST([MAJOR_VERSION],major_version)
AC_SUBST([MINOR_VERSION],minor_version)
AC_SUBST([MICRO_VERSION],micro_version)
AC_SUBST([API_VERSION],api_version)

AC_SUBST([GITVER],git_version)
AM_CONDITIONAL([IS_GITVERSION],[test "x$GITVER" != "x"])

dnl ***********************************************************************
dnl Initialize automake
dnl ***********************************************************************
AM_SILENT_RULES([yes])
AM_INIT_AUTOMAKE([1.11 foreign subdir-objects tar-ustar no-dist-gzip dist-xz -Wno-portability])
AM_MAINTAINER_MODE([enable])
AX_GENERATE_CHANGELOG


dnl ***********************************************************************
dnl Add extra debugging with --enable-debug and --enable-compile-warnings
dnl ***********************************************************************
AX_CHECK_ENABLE_DEBUG([no],[]
                      [G_DISABLE_ASSERT G_DISABLE_CHECKS G_DISABLE_CAST_CHECKS])


dnl ***********************************************************************
dnl Internationalization
dnl ***********************************************************************
GETTEXT_PACKAGE=AC_PACKAGE_TARNAME
AC_SUBST([GETTEXT_PACKAGE])
AC_DEFINE_UNQUOTED([GETTEXT_PACKAGE], ["$GETTEXT_PACKAGE"], [GETTEXT package name])

AM_GNU_GETTEXT_VERSION([0.19.7])
AM_GNU_GETTEXT([external])


dnl ***********************************************************************
dnl Check for required programs
dnl ***********************************************************************
AM_PROG_VALAC([0.28])
AC_PROG_CC
AC_PROG_INSTALL
PKG_PROG_PKG_CONFIG([0.22])
AX_REQUIRE_DEFINED([GLIB_GSETTINGS])
GLIB_GSETTINGS

# Using -g in target's _VALAFLAGS triggers a bug in Vala's automake integration
# that causes invalid makefile generation, so we put it into global VALAFLAGS
VALAFLAGS="-g"
AC_SUBST([VALAFLAGS])

dnl ***********************************************************************
dnl Check for required packages
dnl ***********************************************************************
PKG_CHECK_MODULES(SHOTWELL, [
                             gee-0.8 >= 0.8.5
                             gexiv2 >= 0.4.90
                             gio-unix-2.0 >= 2.20
                             glib-2.0 >= 2.30.0
                             gmodule-2.0 >= 2.24.0
                             gstreamer-1.0 >= 1.0.0
                             gstreamer-base-1.0 >= 1.0.0
                             gstreamer-plugins-base-1.0 >= 1.0.0
                             gstreamer-pbutils-1.0 >= 1.0.0
                             gtk+-3.0 >= 3.12.2
                             gudev-1.0 >= 145
                             libexif >= 0.6.16
                             libgphoto2 >= 2.5.0
                             libraw >= 0.13.2
                             libsoup-2.4 >= 2.26.0
                             libxml-2.0 >= 2.6.32
                             sqlite3 >= 3.5.9
                             webkit2gtk-4.0
                            ])
PKG_CHECK_MODULES(THUMBNAILER, [gee-0.8 >= 0.8.5 gtk+-3.0 >= 3.12.2
                                gstreamer-base-1.0 >= 1.0.0])

PKG_CHECK_MODULES(PLUGIN, [gobject-2.0 glib-2.0 json-glib-1.0 libxml-2.0
                           libsoup-2.4 webkit2gtk-4.0 gee-0.8])

PKG_CHECK_MODULES(IMPORT, [gee-0.8 >= 0.8.5 glib-2.0 gio-2.0 sqlite3])

PKG_CHECK_MODULES(PUBLISHING, [gobject-2.0 glib-2.0 gexiv2 json-glib-1.0
                               gee-0.8 libsoup-2.4 libxml-2.0 gtk+-3.0
                               webkit2gtk-4.0])

PKG_CHECK_MODULES(TRANSITIONS, [gobject-2.0 cairo gio-2.0 gdk-pixbuf-2.0
                                gdk-3.0])

dnl ***********************************************************************
dnl Unity support
dnl ***********************************************************************
AC_ARG_ENABLE([unity-support],
              AS_HELP_STRING([--enable-unity-support],
                             [Enable Ubuntu Unity integration]),
              [],
              [enable_unity_support=no])

AS_IF([test "x$enable_unity_support" = "xyes"],
      [
       PKG_CHECK_MODULES(UNITY, [unity],
                         [
                          HAVE_UNITY=yes
                          UNITY_VALAFLAGS="--pkg unity --define UNITY_SUPPORT"
                          AC_SUBST([UNITY_VALAFLAGS])
                         ], [HAVE_UNITY=no])
      ], [HAVE_UNITY=no])
AC_SUBST([HAVE_UNITY])
AM_CONDITIONAL([HAVE_UNITY],[test "x$HAVE_UNITY" = "xyes"])

dnl ***********************************************************************
dnl Extra publishing plugins
dnl ***********************************************************************
AC_ARG_ENABLE([extra-plugins],
              AS_HELP_STRING([--disable-extra-plugins],
                             [Enable building and installation of extra
                              publishing plugins]),
              [],[enable_extra_plugins=yes])
AS_IF([test "x$enable_extra_plugins" = "xyes"],
      [HAVE_EXTRA_PLUGINS=yes], [HAVE_EXTRA_PLUGINS=no])
AC_SUBST([HAVE_EXTRA_PLUGINS])
AM_CONDITIONAL([HAVE_EXTRA_PLUGINS], [test "x$HAVE_EXTRA_PLUGINS" = "xyes"])

dnl ***********************************************************************
dnl Initialize Libtool
dnl ***********************************************************************
LT_PREREQ([2.2])
LT_INIT

dnl ***********************************************************************
dnl Help processing
dnl ***********************************************************************
AX_REQUIRE_DEFINED([YELP_HELP_INIT])
YELP_HELP_INIT

dnl ***********************************************************************
dnl AppData support
dnl ***********************************************************************
AX_REQUIRE_DEFINED([APPDATA_XML])
APPDATA_XML

dnl ***********************************************************************
dnl GResource compiler
dnl ***********************************************************************
AC_SUBST([GLIB_COMPILE_RESOURCES], [`$PKG_CONFIG --variable glib_compile_resources gio-2.0`])

dnl ***********************************************************************
dnl Process .in Files
dnl ***********************************************************************
AC_CONFIG_FILES([
    Makefile
    misc/Makefile
    po/Makefile.in
    help/Makefile
    app-icons/Makefile
    icons/Makefile
    ui/Makefile
],[],
[API_VERSION='$API_VERSION'])
AC_OUTPUT

echo ""
echo " ${PACKAGE} - ${VERSION}"
echo ""
echo " Options"
echo ""
echo "  Prefix ............................... : ${prefix}"
echo "  Libdir ............................... : ${libdir}"
echo "  Unity support ........................ : ${HAVE_UNITY}"
echo "  Additional publishing plugins ........ : ${HAVE_EXTRA_PLUGINS}"
echo ""
