# Plugin helper library

shotwell_common_resources = gnome.compile_resources('common-resource',
        'common/org.gnome.Shotwell.Publishing.Common.gresource.xml',
        source_dir : meson.project_source_root())

sw_plugin_common = library('shotwell-plugin-common',
                          ['common/RESTSupport.vala',
                           'common/Resources.vala',
                           'common/WebAuthenticationPane.vala',
                           'common/BuilderPane.vala',
                           'common/OAuth1Support.vala',
                           'common/SSLCertificatePane.vala'] + shotwell_common_resources,
                          c_args : ['-DPLUGIN_RESOURCE_PATH="/org/gnome/Shotwell/Publishing/Common"',
                        '-DGCR_API_SUBJECT_TO_CHANGE'],
                          version: so_version,
                          dependencies : [gtk, gee, soup, xml, sw_plugin, gcr],
                          vala_header : 'shotwell-plugin-common.h',
                          vala_vapi : 'shotwell-plugin-common.vapi',
                          include_directories : config_incdir,
                          install : true)

sw_plugin_common_dep = declare_dependency(include_directories : include_directories('.'),
                                          link_with : sw_plugin_common)

subdir('authenticator')
subdir('shotwell-publishing')
subdir('shotwell-transitions')
