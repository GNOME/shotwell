project('Shotwell', ['vala', 'c'],
        version : '0.28.4',
        default_options : ['buildtype=debugoptimized'])

gnome = import('gnome')
i18n = import('i18n')

conf = configuration_data()
conf.set('GETTEXT_PACKAGE', '"@0@"'.format(meson.project_name().to_lower()))
conf.set('_VERSION', '"@0@"'.format(meson.project_version()))
conf.set('_PREFIX', '"@0@"'.format(get_option('prefix')))
conf.set('_LANG_SUPPORT_DIR', '"@0@"'.format(join_paths(get_option('prefix'), get_option('localedir'))))
conf.set('_LIBEXECDIR', '"@0@"'.format(join_paths(get_option('prefix'), get_option('libexecdir'))))
conf.set('_LIB', '"@0@"'.format(join_paths(get_option('prefix'), get_option('libdir'))))
configure_file(output : 'config.h', configuration: conf)

config_incdir = include_directories('.')
vapi_incdir = include_directories('vapi')
shotwell_plugin_dir = join_paths(get_option('libdir'), 'shotwell', 'plugins', 'builtin')

add_global_arguments(['-DHAVE_CONFIG_H=1'],
                     ['-include'], ['config.h'], language : 'c')
add_global_arguments(['--target-glib=2.40',
                      '--vapidir=@0@'.format(join_paths(meson.current_source_dir(),
                        'vapi')),
                      '--enable-checking',
                      '--fatal-warnings',
                      '--enable-experimental',
                      '--enable-deprecated'], language : 'vala')

gitver = run_command(find_program('git-hash'))
if gitver.returncode() == 0
  add_global_arguments(['-D_GIT_VERSION="@0@"'.format(gitver.stdout().strip())],
    language : 'c')
  add_global_arguments(['--define=_GITVERSION'], language : 'vala')
endif

gtk = dependency('gtk+-3.0', version : '>= 3.18')
gio = dependency('gio-2.0', version: '>= 2.40')
gmodule = dependency('gmodule-2.0', version: '>= 2.40')
gio_unix = dependency('gio-unix-2.0', version: '>= 2.40')
gee = dependency('gee-0.8', version: '>= 0.8.5')
webkit = dependency('webkit2gtk-4.0', version: '>= 2.4')
soup = dependency('libsoup-2.4')
json_glib = dependency('json-glib-1.0')
xml = dependency('libxml-2.0')
gdk = dependency('gdk-3.0', version : '>= 3.18')
gdk_pixbuf = dependency('gdk-pixbuf-2.0')
sqlite = dependency('sqlite3', version : '>= 3.5.9')
gstreamer = dependency('gstreamer-1.0', version : '>= 1.0')
gstreamer_pbu = dependency('gstreamer-pbutils-1.0', version : '>= 1.0')
gphoto2 = dependency('libgphoto2', version : '>= 2.5.0')
gudev = dependency('gudev-1.0', version : '>= 145')
gexiv2 = dependency('gexiv2', version: '>= 0.10.4')
libraw = dependency('libraw', version : '>= 0.13.2')
libexif = dependency('libexif', version : '>= 0.6.16')
unity = dependency('unity', required : false)

unity_available = false
if unity.found() and get_option('enable-unity-support')
  unity_available = true
  add_global_arguments(['--define=UNITY_SUPPORT'], language : 'vala')
endif

foreach publisher : get_option('publishers').split(',')
  add_global_arguments(['--define=HAVE_@0@'.format(publisher.to_upper())],
                       language : 'vala')
endforeach

foreach trace : get_option('trace').split(',')
  add_global_arguments(['--define=TRACE_@0@'.format(trace.to_upper().underscorify())],
                       language : 'vala')
endforeach

foreach measure : get_option('measure').split(',')
  add_global_arguments(['--define=MEASURE_@0@'.format(trace.to_upper().underscorify())],
                       language : 'vala')
endforeach

if get_option('disable-dupe-detection')
  add_global_arguments(['--define=NO_DUPE_DETECTION'], language : vala)
endif

json_glib = dependency('json-glib-1.0')
gdata = dependency('libgdata')
gcr = dependency('gcr-3')
gcr_ui = dependency('gcr-ui-3')
cairo = dependency('cairo')

valac = meson.get_compiler('vala')
posix = valac.find_library('posix')

shotwell_resources = gnome.compile_resources('shotwell-resources',
        'org.gnome.Shotwell.gresource.xml')

subdir('src')
subdir('plugins')
subdir('po')
subdir('help')
subdir('misc')
subdir('thumbnailer')
subdir('settings-migrator')
subdir('app-icons')

if get_option('install-apport-hook')
  subdir('apport')
endif
