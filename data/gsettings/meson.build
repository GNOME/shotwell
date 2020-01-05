schema_xml = files(
    'org.gnome.shotwell-extras.gschema.xml',
    'org.gnome.shotwell.gschema.xml'
)

install_data(schema_xml,
    install_dir : join_paths(get_option('datadir'), 'glib-2.0', 'schemas'))

gnome.compile_schemas(
    depend_files : schema_xml
)
