authenticator_shotwell_sources = [
        'ShotwellAuthenticatorFactory.vala',
        'FacebookPublishingAuthenticator.vala',
        'FlickrPublishingAuthenticator.vala',
        'GoogleAuthenticator.vala',
        'OAuth1Authenticator.vala',
        'TumblrAuthenticator.vala'
        ]

authenticator_shotwell_resources = gnome.compile_resources('authenticator-resource',
        'org.gnome.Shotwell.Authenticator.gresource.xml',
        source_dir : meson.source_root())

authenticator_shotwell_deps = [gee, gtk, gio, soup, json_glib, sw_plugin,
                               sw_plugin_common_dep, json_glib, xml, webkit]

authenticator = library('shotwell-authenticator',
                        authenticator_shotwell_sources + authenticator_shotwell_resources,
                        dependencies : authenticator_shotwell_deps,
                        include_directories : config_incdir,
                        version: meson.project_version(),
                        vala_args : ['--gresources',
                        'org.gnome.Shotwell.Authenticator.gresource.xml'],
                        c_args :
                        '-DPLUGIN_RESOURCE_PATH="/org/gnome/Shotwell/Authenticator"',
                        install: true)
authenticator_dep = declare_dependency(include_directories : include_directories('.'),
                                       link_with : authenticator)
