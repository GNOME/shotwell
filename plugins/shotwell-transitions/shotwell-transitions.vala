/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

extern const string _VERSION;

private class ShotwellTransitions : Object, Spit.Module {
    private Spit.Pluggable[] pluggables = new Spit.Pluggable[0];

    public ShotwellTransitions(GLib.File module_file) {
        GLib.File resource_directory = module_file.get_parent();

        pluggables += new FadeEffectDescriptor(resource_directory);
        pluggables += new SlideEffectDescriptor(resource_directory);
        pluggables += new CrumbleEffectDescriptor(resource_directory);
        pluggables += new BlindsEffectDescriptor(resource_directory);
        pluggables += new CircleEffectDescriptor(resource_directory);
        pluggables += new CirclesEffectDescriptor(resource_directory);
        pluggables += new ClockEffectDescriptor(resource_directory);
        pluggables += new SquaresEffectDescriptor(resource_directory);
        pluggables += new ChessEffectDescriptor(resource_directory);
        pluggables += new StripesEffectDescriptor(resource_directory);
    }
    
    public unowned string get_module_name() {
        return _("Core Slideshow Transitions");
    }
    
    public unowned string get_version() {
        return _VERSION;
    }
    
    public unowned string get_id() {
        return "org.yorba.shotwell.transitions";
    }
    
    public unowned Spit.Pluggable[]? get_pluggables() {
        return pluggables;
    }
}

// This entry point is required for all SPIT modules.
public Spit.Module? spit_entry_point(Spit.EntryPointParams *params) {
    params->module_spit_interface = Spit.negotiate_interfaces(params->host_min_spit_interface,
        params->host_max_spit_interface, Spit.CURRENT_INTERFACE);
    
    return (params->module_spit_interface != Spit.UNSUPPORTED_INTERFACE)
        ? new ShotwellTransitions(params->module_file) : null;
}

// Base class for all transition descriptors in this module
public abstract class ShotwellTransitionDescriptor : Object, Spit.Pluggable, Spit.Transitions.Descriptor {
    private const string ICON_FILENAME = "slideshow-plugin.png";

    private static Gdk.Pixbuf[] icon_pixbuf_set = null;
    
    protected ShotwellTransitionDescriptor(GLib.File resource_directory) {
        if (icon_pixbuf_set == null)
            icon_pixbuf_set =
                Resources.load_from_resource(Resources.RESOURCE_PATH + "/" + ICON_FILENAME);
    }

    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
            Spit.Transitions.CURRENT_INTERFACE);
    }
    
    public abstract unowned string get_id();
    
    public abstract unowned string get_pluggable_name();
    
    public void get_info(ref Spit.PluggableInfo info) {
        info.authors = "Maxim Kartashev";
        info.copyright = _("Copyright 2010 Maxim Kartashev, Copyright 2016 Software Freedom Conservancy Inc.");
        info.translators = Resources.TRANSLATORS;
        info.version = _VERSION;
        info.website_name = Resources.WEBSITE_NAME;
        info.website_url = Resources.WEBSITE_URL;
        info.is_license_wordwrapped = false;
        info.license = Resources.LICENSE;
        info.icons = icon_pixbuf_set;
    }
    
    public void activation(bool enabled) {
    }
    
    public abstract Spit.Transitions.Effect create(Spit.HostInterface host);
}

