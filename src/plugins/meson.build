# Plugin helper library
sw_plugin_dev = library('shotwell-plugin-dev-1.0',
                               ['DataImportsInterfaces.vala',
                                'PublishingInterfaces.vala',
                                'SpitInterfaces.vala',
                                'TransitionsInterfaces.vala'],
                                version: meson.project_version(),
                                vala_header : 'shotwell-plugin-dev-1.0.h',
                                vala_vapi : 'shotwell-plugin-dev-1.0.vapi',
                                dependencies : [gmodule, gtk, gio, gee],
                                include_directories : config_incdir,
                                install : true)

sw_plugin = declare_dependency(include_directories : include_directories('.'),
        link_with : sw_plugin_dev)
