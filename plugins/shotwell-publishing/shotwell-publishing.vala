/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

extern const string _VERSION;

// "core services" are: Flickr, Google Photos, Piwigo, Tumblr and YouTube
private class ShotwellPublishingCoreServices : Object, Spit.Module {
    private Spit.Pluggable[] pluggables = new Spit.Pluggable[0];

    // we need to get a module file handle because our pluggables have to load resources from the
    // module file directory
    public ShotwellPublishingCoreServices(GLib.File module_file) {
        GLib.File resource_directory = module_file.get_parent();
        var factory = Publishing.Authenticator.Factory.get_instance();
        var authenicators = factory.get_available_authenticators();

        // Prevent vala complaining when all authenticators from this plugin
        // are disabled
        debug("Looking for resources in %s", resource_directory.get_path());
        debug("Found %d authenicators", authenicators.size);

#if HAVE_FACEBOOK
        if (authenicators.contains("facebook")) {
            pluggables += new FacebookService(resource_directory);
        }
#endif

#if HAVE_GOOGLEPHOTOS
        if (authenicators.contains("google-photos")) {
            pluggables += new Publishing.GooglePhotos.Service(resource_directory);
        }
#endif

#if HAVE_FLICKR
        if (authenicators.contains("flickr")) {
            pluggables += new FlickrService(resource_directory);
        }
#endif

#if HAVE_YOUTUBE
        if (authenicators.contains("youtube")) {
            pluggables += new YouTubeService(resource_directory);
        }
#endif

#if HAVE_PIWIGO
        pluggables += new PiwigoService(resource_directory);
#endif

#if HAVE_TUMBLR
        pluggables += new TumblrService(module_file.get_parent());
#endif
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

