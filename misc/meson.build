podir = join_paths('..', 'po')

i18n.merge_file(input : 'shotwell.appdata.xml.in',
                output : 'shotwell.appdata.xml',
                po_dir : join_paths('..', 'po'),
                type : 'xml',
                install: true,
                install_dir : join_paths(get_option('datadir'), 'metainfo'))

i18n.merge_file(input : 'shotwell.desktop.in',
                output: 'shotwell.desktop',
                po_dir : podir,
                type : 'desktop',
                install : true,
                install_dir : join_paths(get_option('datadir'), 'applications'))

i18n.merge_file(input : 'shotwell-viewer.desktop.in',
                output: 'shotwell-viewer.desktop',
                po_dir : podir,
                type : 'desktop',
                install : true,
                install_dir : join_paths(get_option('datadir'), 'applications'))

install_data(['org.yorba.shotwell-extras.gschema.xml',
              'org.yorba.shotwell.gschema.xml'],
              install_dir : join_paths(get_option('datadir'), 'glib-2.0', 'schemas'))

gnome.compile_schemas()
