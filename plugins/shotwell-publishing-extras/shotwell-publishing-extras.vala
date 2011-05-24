/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

extern const string _VERSION;

namespace Publishing.Extras {

internal const string DOMAIN_NAME = "shotwell-extras";
internal const string[] LANGUAGE_SUPPORT_DIRECTORIES = {
    "./locale-langpack",
    "/usr/local/share/locale-langpack",
    "/usr/share/locale-langpack",
    "/usr/local/share/locale",
    "/usr/local/share/locale-langpack"
};

internal bool is_domain_configured = false;

public void configure_translation_domain() {
    if (is_domain_configured)
        return;

    string target = DOMAIN_NAME + ".mo";

    // support installation of the shotwell-extras translations separately from the shotwell core
    // translations; look for shotwell-extras translations in all 5 common locations.
    string? lang_support_dir = null;
    foreach (string dirpath in LANGUAGE_SUPPORT_DIRECTORIES) {
        File base_dirfile = File.new_for_path(dirpath);
        if (!base_dirfile.query_exists(null))
            continue;

        FileType base_filetype =
            base_dirfile.query_file_type(FileQueryInfoFlags.NONE, null);
        if (base_filetype != FileType.DIRECTORY)
            continue;
        
        try {
            FileEnumerator lang_enumerator =
                base_dirfile.enumerate_children("standard::name,standard::type",
                FileQueryInfoFlags.NONE, null);
            FileInfo info = null;
            while ((info = lang_enumerator.next_file(null)) != null) {
                if (info.get_file_type() == FileType.DIRECTORY) {
                    File message_domain_file = base_dirfile.get_child(info.get_name()).get_child(
                        "LC_MESSAGES").get_child(target);

                    if (message_domain_file.query_exists(null)) {
                        lang_support_dir = base_dirfile.get_path();
                        break;
                    }
                }
            }
        } catch (Error e) {
            critical("can't get location of translation file for extra plugins: " + e.message);
        }
        
        if (lang_support_dir != null)
            break;
     }

    if (lang_support_dir != null) {
        string? bound = Intl.bindtextdomain(DOMAIN_NAME, lang_support_dir);
        
        if (bound != null)
            debug("bound shotwell-extras language support directory '%s'.\n", lang_support_dir);
    }

    is_domain_configured = true;
}

public unowned string? _t(string msgid) {
    if (!is_domain_configured)
        configure_translation_domain();

    return dgettext(DOMAIN_NAME, msgid);
}

public unowned string? _tn(string msgid, string msgid_plural, ulong n) {
    if (!is_domain_configured)
        configure_translation_domain();
    
    return dngettext(DOMAIN_NAME, msgid, msgid_plural, n);
}
}

private class ShotwellPublishingExtraServices : Object, Spit.Module {
    private Spit.Pluggable[] pluggables = new Spit.Pluggable[0];

    public ShotwellPublishingExtraServices(GLib.File module_file) {
        GLib.File resource_directory = module_file.get_parent();
        
        pluggables += new YandexService();
        pluggables += new PiwigoService(resource_directory);
    }
    
    public unowned string get_module_name() {
        return _("Shotwell Extra Publishing Services");
    }
    
    public unowned string get_version() {
        return _VERSION;
    }
    
    public unowned string get_id() {
        return "org.yorba.shotwell.publishing.extras";
    }
    
    public unowned Spit.Pluggable[]? get_pluggables() {
        return pluggables;
    }
}

// This entry point is required for all SPIT modules.
public Spit.Module? spit_entry_point(Spit.EntryPointParams *params) {
    params->module_spit_interface = Spit.negotiate_interfaces(params->host_min_spit_interface,
        params->host_max_spit_interface, Spit.CURRENT_INTERFACE);
    
    Publishing.Extras.configure_translation_domain();
    
    return (params->module_spit_interface != Spit.UNSUPPORTED_INTERFACE)
        ? new ShotwellPublishingExtraServices(params->module_file) : null;
}

