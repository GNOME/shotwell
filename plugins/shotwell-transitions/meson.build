shotwell_transitions_sources = [
    'BlindsEffect.vala',
    'ChessEffect.vala',
    'CircleEffect.vala',
    'CirclesEffect.vala',
    'ClockEffect.vala',
    'CrumbleEffect.vala',
    'FadeEffect.vala',
    'shotwell-transitions.vala',
    'SlideEffect.vala',
    'SquaresEffect.vala',
    'StripesEffect.vala']

shotwell_transitions_resources = gnome.compile_resources('transitions-resource',
        'org.gnome.Shotwell.Transitions.gresource.xml')

cc = meson.get_compiler('c')
libm = cc.find_library('m', required : false)

shared_module('shotwell-transitions',
              shotwell_transitions_sources + shotwell_transitions_resources,
              dependencies : [gio, gdk_pixbuf, cairo, gtk, gdk, xml, sw_plugin,
                              sw_plugin_common_dep, gee, soup, webkit, libm],
              vala_args : [
                  '--gresources', 'org.gnome.Shotwell.Transitions.gresource.xml',
                  ],
              c_args : ['-DPLUGIN_RESOURCE_PATH="/org/gnome/Shotwell/Transitions"'],
              install: true,
              install_dir : shotwell_plugin_dir)
