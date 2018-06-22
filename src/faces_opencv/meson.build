subproject = ('faces_opencv')
add_languages('cpp')
opencv_dep = dependency('opencv', version : ['>= 2.3.0'], required : true)

faces_lib = shared_library('faces_opencv',
           'faces_opencv.cpp',
           dependencies : opencv_dep)
faces_vapi = meson.get_compiler('vala').find_library('faces', dirs: join_paths(meson.source_root(), 'vapi'))
faces_dep = declare_dependency(dependencies: [opencv_dep, faces_vapi])
