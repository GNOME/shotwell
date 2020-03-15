subproject = ('facedetect')
add_languages('cpp')
facedetect_dep = dependency('opencv4', version : ['>= 4.0.0'], required : false)
if not facedetect_dep.found()
    facedetect_dep = dependency('opencv', version : ['>= 3.4.0'], required : true)
endif
executable('shotwell-facedetect',
           'shotwell-facedetect.cpp',
           dependencies : facedetect_dep,
           install : true,
           install_dir : join_paths(get_option('libexecdir'), 'shotwell'))
install_data('facedetect-haarcascade.xml',
              install_dir : join_paths(get_option('datadir'), 'shotwell'))
