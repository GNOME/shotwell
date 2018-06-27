gnome = import('gnome')
subproject = ('facedetect')
add_languages('cpp')
facedetect_dep = dependency('opencv', version : ['>= 2.3.0'], required : true)
gio_unix = dependency('gio-unix-2.0', required : true)
gdbus_src = gnome.gdbus_codegen('dbus-interface',
  sources: 'org.gnome.ShotwellFaces1.xml',
  interface_prefix : 'org.gnome.')
executable('shotwell-facedetect',
           'shotwell-facedetect.cpp', 'facedetect-opencv.cpp', gdbus_src,
           dependencies : [facedetect_dep, gio, gio_unix],
           install : true,
           include_directories: config_incdir,
           install_dir : join_paths(get_option('libexecdir'), 'shotwell'))
install_data('facedetect-haarcascade.xml',
              install_dir : join_paths(get_option('datadir'), 'shotwell'))
