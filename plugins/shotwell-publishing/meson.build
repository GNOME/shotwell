shotwell_publishing_sources = [
    'shotwell-publishing.vala',
    'FacebookPublishing.vala',
    'FlickrPublishing.vala',
    'TumblrPublishing.vala',
    'YouTubePublishing.vala',
    'PiwigoPublishing.vala',
    'PhotosPublisher.vala',
    'PhotosService.vala',
    'PhotosPublishingPane.vala',
    'PhotosUploader.vala'
]

shotwell_publishing_resources = gnome.compile_resources('publishing-resource',
        'org.gnome.Shotwell.Publishing.gresource.xml',
        source_dir : meson.source_root())

shared_module('shotwell-publishing',
              shotwell_publishing_sources + shotwell_publishing_resources,
              dependencies : [gtk, soup, gexiv2, gee, sw_plugin, json_glib,
                              webkit, sw_plugin_common_dep, xml, gdata, gcr,
                              gcr_ui, authenticator_dep],
              c_args : ['-DPLUGIN_RESOURCE_PATH="/org/gnome/Shotwell/Publishing"',
                        '-DGCR_API_SUBJECT_TO_CHANGE'],
              install: true,
              install_dir : shotwell_plugin_dir)
