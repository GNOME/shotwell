libasync = static_library(
  'async',
  [
        'Threads.vala',
        'Workers.vala',
        'BackgroundJob.vala',
        'Semaphore.vala',
        'SortedList.vala',
  ],
  vala_header: 'shotwell-async.h',
  vala_vapi: 'shotwell-async.vapi',
  dependencies: [gio, gee],
  include_directories: config_incdir,
  install: false
)

async = declare_dependency(
    include_directories : include_directories('.'),
    link_with : libasync
)
