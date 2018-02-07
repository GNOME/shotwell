subproject = ('facedetect')
add_languages('cpp')
facedetect_dep = dependency('opencv', version : ['>= 2.3.0'], required : true)
executable('shotwell-facedetect',
           'shotwell-facedetect.cpp',
           dependencies : facedetect_dep,
           install : true,
           install_dir : join_paths(get_option('libexecdir'), 'shotwell'))
install_data('facedetect-haarcascade.xml',
              install_dir : join_paths(get_option('datadir'), 'shotwell'))
