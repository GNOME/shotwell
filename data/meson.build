if get_option('install_apport_hook')
    subdir('apport')
endif

subdir('gsettings')
subdir('icons')

podir = join_paths('..', 'po')

i18n.merge_file(input : 'org.gnome.Shotwell.appdata.xml.in',
                output : 'org.gnome.Shotwell.appdata.xml',
                po_dir : join_paths('..', 'po'),
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

i18n.merge_file(input : 'org.gnome.Shotwell-Profile-Browser.desktop.in',
                output: 'org.gnome.Shotwell-Profile-Browser.desktop',
                po_dir : podir,
                type : 'desktop',
                install : true,
                install_dir : join_paths(get_option('datadir'), 'applications'))

shotwell_resources = gnome.compile_resources('shotwell-resources',
        'org.gnome.Shotwell.gresource.xml')
