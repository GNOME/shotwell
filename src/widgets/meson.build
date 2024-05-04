libwidgets = static_library(
    'widgets',
    [
      'lib.vala',
      'FolderButton.vala',
      'SettingsGroup.vala'
    ],
    vala_header : 'shotwell-internal-widgets.h',
    vala_vapi : 'shotwell-internal-widgets.vapi',
    include_directories : config_incdir,
    dependencies : [
        gtk,
        gio,
    ]
)

widgets = declare_dependency(
    include_directories : include_directories('.'),
    link_with : libwidgets
)
