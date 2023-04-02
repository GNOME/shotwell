project('shotwell-facedetect', ['c', 'cpp'], default_options : ['cpp_std=c++17'])
gnome = import('gnome')
facedetect_dep = dependency('opencv4', version : ['>= 4.0.0'], required : false)
if not facedetect_dep.found()
    facedetect_dep = dependency('opencv', version : ['>= 3.4.0'], required : true)
endif
cpp = meson.get_compiler('cpp')
has_dnn = cpp.has_header('opencv2/dnn.hpp', dependencies: facedetect_dep)
if has_dnn
  dnn_define = declare_dependency(compile_args: '-DHAS_OPENCV_DNN')
else
  dnn_define = []
endif

libexecdir = join_paths(get_option('libexecdir'), 'shotwell')

gio = dependency('gio-2.0', version: '>= 2.40')
gio_unix = dependency('gio-unix-2.0', required : true)
gdbus_src = gnome.gdbus_codegen('dbus-interface',
  sources: 'org.gnome.ShotwellFaces1.xml',
  interface_prefix : 'org.gnome.')

con = configuration_data()
con.set('libexecdir', join_paths(get_option('prefix'), libexecdir))

if meson.is_subproject()
    config_incdir = include_directories('../..')
else
    config_incdir = include_directories('.')
    configure_file(
        input: 'org.gnome.Shotwell.Faces1.desktop.in',
        output: 'org.gnome.Shotwell.Faces1.desktop',
        configuration: con,
        install: true,
        install_dir : join_paths(get_option('datadir'), 'applications')
    )
endif

executable('shotwell-facedetect',
           'shotwell-facedetect.cpp', 'facedetect-opencv.cpp', gdbus_src,
           dependencies : [facedetect_dep, gio, gio_unix, dnn_define],
           install : true,
           include_directories: config_incdir,
           install_dir : libexecdir)
install_data('haarcascade_frontalface_alt.xml',
              install_dir : join_paths(get_option('datadir'), 'shotwell', 'facedetect'))
install_data('haarcascade_profileface.xml',
              install_dir : join_paths(get_option('datadir'), 'shotwell', 'facedetect'))
install_data(
  'openface.nn4.small2.v1.t7',
  install_dir: join_paths(get_option('datadir'), 'shotwell', 'facedetect')
)

install_data('deploy.prototxt', install_dir: join_paths(get_option('datadir'), 'shotwell', 'facedetect'))

configure_file(
    input : 'org.gnome.Shotwell.Faces1.service.in',
    output : 'org.gnome.Shotwell.Faces1.service',
    configuration: con,
    install: true,
    install_dir : join_paths(get_option('datadir'), 'dbus-1', 'services')
    )
