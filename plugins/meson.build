# Plugin helper library

sw_plugin_common = library('shotwell-plugin-common',
                          ['common/RESTSupport.vala',
                           'common/Resources.vala',
                           'common/WebAuthenticationPane.vala',
                           'common/BuilderPane.vala',
                           'common/OAuth1Support.vala'],
                          version: meson.project_version(),
                          dependencies : [gtk, gee, webkit, soup, xml, sw_plugin],
                          vala_header : 'shotwell-plugin-common.h',
                          vala_vapi : 'shotwell-plugin-common.vapi',
                          include_directories : config_incdir,
                          install : true)

sw_plugin_common_dep = declare_dependency(include_directories : include_directories('.'),
                                          link_with : sw_plugin_common)

subdir('authenticator')
subdir('shotwell-publishing')
if get_option('extra-plugins')
  subdir('shotwell-publishing-extras')
endif
subdir('shotwell-transitions')
