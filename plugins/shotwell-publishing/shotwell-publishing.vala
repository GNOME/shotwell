/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

extern const string _VERSION;

// "core services" are: Facebook, Flickr, Picasa Web Albums, Piwigo and YouTube
private class ShotwellPublishingCoreServices : Object, Spit.Module {
    private Spit.Pluggable[] pluggables = new Spit.Pluggable[0];

    // we need to get a module file handle because our pluggables have to load resources from the
    // module file directory
    public ShotwellPublishingCoreServices(GLib.File module_file) {
        GLib.File resource_directory = module_file.get_parent();
        
        pluggables += new FacebookService(resource_directory);
        pluggables += new PicasaService(resource_directory);
        pluggables += new FlickrService(resource_directory);
        pluggables += new YouTubeService(resource_directory);
        pluggables += new PiwigoService(resource_directory);
    }
    
    public unowned string get_module_name() {
        return _("Core Publishing Services");
    }
    
    public unowned string get_version() {
        return _VERSION;
    }
    
    public unowned string get_id() {
        return "org.yorba.shotwell.publishing.core_services";
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
        ? new ShotwellPublishingCoreServices(params->module_file) : null;
}

