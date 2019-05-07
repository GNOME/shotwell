libmetadata = static_library(
    'metadata',
    [
        'MediaMetadata.vala',
        'MetadataDateTime.vala',
        'MetadataRational.vala'
    ],
    dependencies : [
        gio
    ]
)

metadata = declare_dependency(
    include_directories : include_directories('.'),
    link_with : libmetadata
)
