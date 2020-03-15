project('shotwell-facedetect', ['c', 'cpp'], default_options : ['cpp_std=c++14'])
gnome = import('gnome')
opencv = dependency('opencv4', version : ['>= 4.0.0'], required : false)
if opencv.found()
    add_global_arguments(['-DHAVE_OPENCV_4'], language: 'cpp')
else
    opencv = dependency('opencv', version: ['>= 2.3.0'], required : true)
endif

cpp = meson.get_compiler('cpp')
has_dnn = cpp.has_header('opencv2/dnn.hpp', dependencies: opencv)
if opencv.found()
    add_global_arguments(['-DHAVE_OPENCV_4'], language: 'cpp')
endif

if has_dnn
    add_global_arguments(['-DHAVE_OPENCV2_DNN_HPP'], language: 'cpp')
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
           dependencies : [opencv, gio, gio_unix],
           install : true,
           include_directories: config_incdir,
           install_dir : libexecdir)
install_data('facedetect-haarcascade.xml',
              install_dir : join_paths(get_option('datadir'), 'shotwell'))

configure_file(
    input : 'org.gnome.Shotwell.Faces1.service.in',
    output : 'org.gnome.Shotwell.Faces1.service',
    configuration: con,
    install: true,
    install_dir : join_paths(get_option('datadir'), 'dbus-1', 'services')
    )
