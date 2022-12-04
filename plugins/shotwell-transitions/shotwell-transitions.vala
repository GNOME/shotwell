/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

extern const string _VERSION;

private class ShotwellTransitions : Object, Spit.Module {
    private Spit.Pluggable[] pluggables = new Spit.Pluggable[0];

    public ShotwellTransitions() {
        pluggables += new FadeEffectDescriptor();
        pluggables += new SlideEffectDescriptor();
        pluggables += new CrumbleEffectDescriptor();
        pluggables += new BlindsEffectDescriptor();
        pluggables += new CircleEffectDescriptor();
        pluggables += new CirclesEffectDescriptor();
        pluggables += new ClockEffectDescriptor();
        pluggables += new SquaresEffectDescriptor();
        pluggables += new ChessEffectDescriptor();
        pluggables += new StripesEffectDescriptor();
    }
    
    public unowned string get_module_name() {
        return _("Core Slideshow Transitions");
    }
    
    public unowned string get_version() {
        return _VERSION;
    }
    
    public unowned string get_id() {
        return "org.gnome.shotwell.transitions";
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
        ? new ShotwellTransitions() : null;
}

// Base class for all transition descriptors in this module
public abstract class ShotwellTransitionDescriptor : Object, Spit.Pluggable, Spit.Transitions.Descriptor {
    protected ShotwellTransitionDescriptor() {}

    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
            Spit.Transitions.CURRENT_INTERFACE);
    }
    
    public abstract unowned string get_id();
    
    public abstract unowned string get_pluggable_name();
    
    public Spit.PluggableInfo get_info() {
        var info = new Spit.PluggableInfo();
        info.authors = "Maxim Kartashev";
        info.copyright = _("Copyright 2010 Maxim Kartashev\nCopyright 2016 Software Freedom Conservancy Inc.");
        info.icon_name = "slideshow-plugin";

        return info;
    }
    
    public void activation(bool enabled) {
    }
    
    public abstract Spit.Transitions.Effect create(Spit.HostInterface host);
}

