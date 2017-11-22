shotwell_publishing_extra_sources = [
    'GalleryConnector.vala',
    'RajcePublishing.vala',
    'shotwell-publishing-extras.vala',
    'YandexPublishing.vala'
    ]

shotwell_publishing_extra_resources = gnome.compile_resources('publishing-extra-resource',
        'org.gnome.Shotwell.Publishing.Extras.gresource.xml')

shared_module('shotwell-publishing-extras',
              shotwell_publishing_extra_sources + shotwell_publishing_extra_resources,
              dependencies : [gee, gtk, xml, soup, gdk_pixbuf, sw_plugin,
                              sw_plugin_common_dep, json_glib, webkit],
              vala_args : [
                  '--gresources', 'org.gnome.Shotwell.Publishing.Extras.gresource.xml'
                  ],
              c_args : ['-DPLUGIN_RESOURCE_PATH="/org/gnome/Shotwell/Publishing/Extras"',
                        '-DGCR_API_SUBJECT_TO_CHANGE'],
              install: true,
              install_dir : shotwell_plugin_dir)
