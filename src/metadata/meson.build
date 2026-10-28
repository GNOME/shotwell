# SPDX-FileCopyrightText: Software Freedom Conservancy Inc.
# SPDX-License-Identifier: LGPL-2.1-or-later
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
