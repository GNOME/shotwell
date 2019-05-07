libvideometadata_handling = static_library(
    'video_metadata_handling',
    [
        'AVIChunk.vala',
        'AVIMetadataLoader.vala',
        'QuickTimeAtom.vala',
        'QuicktimeMetdataLoader.vala',
        'util.vala'
    ],
    vala_header : 'shotwell-internal-video-metadata-handling.h',
    vala_vapi : 'shotwell-internal-video-metadata-handling.vapi',
    include_directories : config_incdir,
    dependencies : [
        gio,
        metadata
    ]
)

metadata_handling = declare_dependency(
    include_directories : include_directories('.'),
    link_with : libvideometadata_handling
)
