libsw_publishing_gui = static_library(
    'publishing_gui',
    [
        'StaticMessagePaneWidget.vala',
        'ProgressPaneWidget.vala',
        'SuccessPaneWidget.vala',
        'LoginWelcomePaneWidget.vala',
    ],
    vala_header : 'shotwell-internal-publishing-gui.h',
    vala_vapi : 'shotwell-internal-publishing-gui.vapi',
    include_directories : config_incdir,
    dependencies: [
        gtk,
        gee,
        sw_plugin
    ],
    vala_args : [
        '--gresources',
        join_paths(meson.project_source_root(), 'data',
        'org.gnome.Shotwell.gresource.xml')
    ]
)

sw_publishing_gui = declare_dependency(
    include_directories : include_directories('.'),
    link_with : libsw_publishing_gui
)
