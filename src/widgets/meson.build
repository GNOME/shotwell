libwidgets = static_library(
    'widgets',
    [
      'lib.vala',
      'FolderButton.vala',
      'SettingsGroup.vala',
      'ListHeader.vala'
    ] + shotwell_widget_resources,
    vala_header : 'shotwell-internal-widgets.h',
    vala_vapi : 'shotwell-internal-widgets.vapi',
    include_directories : config_incdir,
    dependencies : [
        gtk,
        gio,
    ],
    vala_args : [
        '--gresources',
        join_paths(meson.project_source_root(), 'data',
        'org.gnome.Shotwell.gresource.xml')        
    ]
)

widgets = declare_dependency(
    include_directories : include_directories('.'),
    link_with : libwidgets
)
