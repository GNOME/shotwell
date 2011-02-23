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

private ShotwellTransitions? module = null;

// This entry point is required for all SPIT modules.
public unowned Spit.Module? spit_entry_point(int host_min_spit_interface, int host_max_spit_interface,
    out int module_spit_interface) {
    module_spit_interface = Spit.negotiate_interfaces(host_min_spit_interface, host_max_spit_interface,
        Spit.CURRENT_INTERFACE);
    if (module_spit_interface == Spit.UNSUPPORTED_INTERFACE)
        return null;
    
    if (module == null)
        module = new ShotwellTransitions();
    
    return module;
}

public void g_module_unload() {
    if (module != null)
        debug("%s %s unloaded", module.get_module_name(), module.get_version());
    else
        debug("spitter unloaded prior to spit_entry_point being called");
    
    module = null;
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
    
    public abstract unowned string get_id();
    
    public abstract unowned string get_pluggable_name();
    
    public void get_info(out Spit.PluggableInfo info) {
        info.authors = "Maxim Kartashev, Jim Nelson";
        info.copyright = _("Copyright 2010 Maxim Kartashev, Copyright 2011 Yorba Foundation");
        info.license = null;
        info.translators = _("translator-credits");
        info.version = _VERSION;
        info.website_name = _("Visit the Yorba web site");
        info.website_url = "http://www.yorba.org";
        
        info.is_license_wordwrapped = true;
        info.license = """
Shotwell is free software; you can redistribute it and/or modify it under the 
terms of the GNU Lesser General Public License as published by the Free 
Software Foundation; either version 2.1 of the License, or (at your option) 
any later version.

Shotwell is distributed in the hope that it will be useful, but WITHOUT 
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for 
more details.

You should have received a copy of the GNU Lesser General Public License 
along with Shotwell; if not, write to the Free Software Foundation, Inc., 
51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
""";
    }
    
    public void activation(bool enabled) {
    }
    
    public abstract Spit.Transitions.Effect create(Spit.HostInterface host);
}

