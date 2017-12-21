subproject = ('facedetect')
add_languages('cpp')
facedetect_dep = dependency('opencv', version : ['>= 2.3.0'], required : true)
exe = executable('shotwell-facedetect', 'shotwell-facedetect.cpp',
                 dependencies : facedetect_dep, install : true)
