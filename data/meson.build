if get_option('install_apport_hook')
    subdir('apport')
endif

subdir('gsettings')
subdir('icons')

podir = join_paths('..', 'po')

i18n.merge_file(input : 'org.gnome.Shotwell.metainfo.xml.in',
                output : 'org.gnome.Shotwell.metainfo.xml',
                po_dir : podir,
                type : 'xml',
                install: true,
                install_dir : join_paths(get_option('datadir'), 'metainfo'))

i18n.merge_file(input : 'org.gnome.Shotwell.desktop.in',
                output: 'org.gnome.Shotwell.desktop',
                po_dir : podir,
                type : 'desktop',
                install : true,
                install_dir : join_paths(get_option('datadir'), 'applications'))

i18n.merge_file(input : 'org.gnome.Shotwell-Viewer.desktop.in',
                output: 'org.gnome.Shotwell-Viewer.desktop',
                po_dir : podir,
                type : 'desktop',
                install : true,
                install_dir : join_paths(get_option('datadir'), 'applications'))

auth_conf = configuration_data()
auth_conf.set('libexecdir', join_paths(get_option('prefix'), get_option('libexecdir')))
configure_file(
    input : 'org.gnome.Shotwell.Auth.desktop.in',
    output: 'org.gnome.Shotwell.Auth.desktop',
    configuration: auth_conf,
    install: true,
    install_dir : join_paths(get_option('datadir'), 'applications')
)

shotwell_resources = gnome.compile_resources('shotwell-resources',
        'org.gnome.Shotwell.gresource.xml')
