libdatastructures = static_library(
  'datastructures',
  [
    'SortedList.vala',
    'TimedQueue.vala'
  ],
  vala_header: 'shotwell-datastructures.h',
  vala_vapi: 'shotwell-datastructures.vapi',
  dependencies: [gio, gobject, gee],
  include_directories: config_incdir,
  install: false
)

datastructures = declare_dependency(
    include_directories : include_directories('.'),
    link_with : libdatastructures
)
