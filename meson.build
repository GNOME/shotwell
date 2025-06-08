project('shotwell', ['vala', 'c'],
        version : '0.32.13',
        meson_version : '>= 0.59.0',
        default_options : ['buildtype=debugoptimized'])

gnome = import('gnome')
i18n = import('i18n')

conf = configuration_data()
conf.set_quoted('GETTEXT_PACKAGE', meson.project_name().to_lower())
conf.set_quoted('_VERSION', meson.project_version())
conf.set_quoted('_PREFIX', get_option('prefix'))
conf.set_quoted('_LANG_SUPPORT_DIR', join_paths(get_option('prefix'), get_option('localedir')))
conf.set_quoted('_LIBEXECDIR', join_paths(get_option('prefix'), get_option('libexecdir')))
conf.set_quoted('_LIB', get_option('libdir'))
conf.set_quoted('_PIXBUF_LOADER_PATH', get_option('extra_pixbuf_loaders_path'))
configure_file(output : 'config.h', configuration: conf)

config_incdir = include_directories('.')
vapi_incdir = include_directories('vapi')
shotwell_plugin_dir = join_paths(get_option('libdir'), 'shotwell', 'plugins', 'builtin')

cc = meson.get_compiler('c')
disabled_warning_flags = []
if cc.get_id() == 'gcc' or cc.get_id() == 'clang'
  disabled_warning_flags = cc.get_supported_arguments([
    '-Wno-unused-but-set-variable', 
    '-Wno-unused-variable',
    '-Wno-incompatible-pointer-types',
    '-Wno-discarded-qualifiers',
    '-Wno-unused-label',
    '-Wno-unused-function',
    '-Wno-unused-value'
  ])
endif


add_global_arguments(['-DHAVE_CONFIG_H=1'],
                     ['-include'], ['config.h'],
                     language : 'c')
add_global_arguments(disabled_warning_flags, language: 'c')
add_global_arguments(
    [
        '--target-glib=2.40',
        '--vapidir=@0@'.format(join_paths(meson.current_source_dir(), 'vapi')),
        '--enable-checking',
        '--enable-experimental',
    ],
    language : 'vala'
)

if get_option('fatal_warnings')
    add_global_arguments(
        [
            '--fatal-warnings'
        ],
        language : 'vala'
    )
endif

version_h = vcs_tag(command: ['git', 'rev-parse', 'HEAD'], input: 'version.h.in', output: 'version.h', fallback: '')
version = declare_dependency(sources : version_h, include_directories : include_directories('.'))

gtk = dependency('gtk+-3.0', version : '>= 3.22')
gio = dependency('gio-2.0', version: '>= 2.40')
gmodule = dependency('gmodule-2.0', version: '>= 2.40')
gee = dependency('gee-0.8', version: '>= 0.8.5')
soup = dependency('libsoup-3.0')
json_glib = dependency('json-glib-1.0')
xml = dependency('libxml-2.0')
gdk = dependency('gdk-3.0', version : '>= 3.22')
gdk_pixbuf = dependency('gdk-pixbuf-2.0')
sqlite = dependency('sqlite3', version : '>= 3.5.9')
gstreamer = dependency('gstreamer-1.0', version : '>= 1.20')
gstreamer_pbu = dependency('gstreamer-pbutils-1.0', version : '>= 1.20')
gphoto2 = dependency('libgphoto2', version : '>= 2.5.0')
gudev = dependency('gudev-1.0', version : '>= 145', required: false)
gexiv2 = dependency('gexiv2', version: '>= 0.12.3')
libraw = dependency('libraw', version : '>= 0.13.2')
libexif = dependency('libexif', version : '>= 0.6.16')
unity = dependency('unity', required : false)
secret = dependency('libsecret-1', required: true)
portal = [ dependency('libportal', version: '>= 0.5'), dependency('libportal-gtk3', version: '>= 0.5')]
math = meson.get_compiler('c').find_library('m', required: false)
 
webpdemux = dependency('libwebpdemux')
webp = dependency('libwebp')

if unity.found() and get_option('unity_support')
  add_global_arguments(['--define=UNITY_SUPPORT'], language : 'vala')
endif

foreach publisher : get_option('publishers')
  add_global_arguments(['--define=HAVE_@0@'.format(publisher.to_upper())],
                       language : 'vala')
endforeach

foreach trace : get_option('trace')
  add_global_arguments(['--define=TRACE_@0@'.format(trace.to_upper().underscorify())],
                       language : 'vala')
endforeach

foreach measure : get_option('measure')
  add_global_arguments(['--define=MEASURE_@0@'.format(trace.to_upper().underscorify())],
                       language : 'vala')
endforeach

if not get_option('dupe_detection')
  add_global_arguments(['--define=NO_DUPE_DETECTION'], language : 'vala')
endif

if get_option('udev') and gudev.found()
  add_global_arguments(['--define=HAVE_UDEV'], language : 'vala')
endif

if get_option('face_detection')
  add_global_arguments(['--define=ENABLE_FACE_DETECTION'], language : 'vala')

  if get_option('face_detection_helper_bus') == 'private'
      add_global_arguments(['--define=FACEDETECT_BUS_PRIVATE'], language : 'vala')
  endif

  if get_option('face_detection_helper')
      subproject('shotwell-facedetect')
  endif
endif

json_glib = dependency('json-glib-1.0')
gcr = dependency('gcr-3')
gcr_ui = dependency('gcr-ui-3')
cairo = dependency('cairo')

valac = meson.get_compiler('vala')
posix = valac.find_library('posix')

subdir('data')
subdir('src')
subdir('plugins')
subdir('po')
subdir('help')
subdir('thumbnailer')
subdir('test')
subdir('settings-migrator')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
