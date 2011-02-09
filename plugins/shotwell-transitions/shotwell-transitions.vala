/* Copyright 2011 Yorba Foundation
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
    }
    
    public string get_name() {
        return "Shotwell Transitions";
    }
    
    public string get_version() {
        return _VERSION;
    }
    
    public string get_id() {
        return "org.yorba.shotwell.transitions";
    }
    
    public Spit.Pluggable[]? get_pluggables() {
        return pluggables;
    }
}

private ShotwellTransitions? spitwad = null;

// This entry point is required for all SPIT modules.
public unowned Spit.Module? spit_entry_point(int host_min_spit_interface, int host_max_spit_interface,
    out int module_spit_interface) {
    module_spit_interface = Spit.negotiate_interfaces(host_min_spit_interface, host_max_spit_interface,
        Spit.CURRENT_INTERFACE);
    if (module_spit_interface == Spit.UNSUPPORTED_INTERFACE)
        return null;
    
    if (spitwad == null)
        spitwad = new ShotwellTransitions();
    
    return spitwad;
}

public void g_module_unload() {
    if (spitwad != null)
        debug("%s %s unloaded", spitwad.get_name(), spitwad.get_version());
    else
        debug("spitter unloaded prior to spit_entry_point being called");
    
    spitwad = null;
}

// This is here to keep valac happy.
private void dummy_main() {
}

// Base class for all transition descriptors in this module
public abstract class ShotwellTransitionDescriptor : Object, Spit.Pluggable, Spit.Transitions.Descriptor {
    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
            Spit.Transitions.CURRENT_INTERFACE);
    }
    
    public abstract string get_id();
    
    public abstract string get_pluggable_name();
    
    public void get_info(out Spit.PluggableInfo info) {
        info.authors = "Maxim Kartashev, Jim Nelson";
        info.copyright = _("Copyright 2010 Maxim Kartashev, Copyright 2011 Yorba Foundation");
        // TODO: Include license here
        info.license = null;
        info.is_licensed_wordwrapped = false;
        info.translators = _("translator-credits");
        info.version = _VERSION;
        info.website_name = _("Visit the Yorba web site");
        info.website_url = "http://www.yorba.org";
    }
    
    public abstract Spit.Transitions.Effect create(Spit.HostInterface host);
}

