/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Plugins {

// GModule doesn't have a truly generic way to determine if a file is a shared library by extension,
// so these are hard-coded
private const string[] SHARED_LIB_EXTS = { "so", "la" };

// Although not expecting this system to last very long, these ranges declare what versions of this
// interface are supported by the current implementation.
private const int MIN_SPIT_INTERFACE = 0;
private const int MAX_SPIT_INTERFACE = 0;

public class ExtensionPoint {
    public GLib.Type pluggable_type { get; private set; }
    // name is user-visible
    public string name { get; private set; }
    public string? icon_name { get; private set; }
    public string[]? core_ids { get; private set; }
    
    public ExtensionPoint(Type pluggable_type, string name, string? icon_name, string[]? core_ids) {
        this.pluggable_type = pluggable_type;
        this.name = name;
        this.icon_name = icon_name;
        this.core_ids = core_ids;
    }
}

private class ModuleRep {
    public File file;
    public Module? module;
    public Spit.Module? spit_module = null;
    public int spit_interface = Spit.UNSUPPORTED_INTERFACE;
    public string? id = null;
    
    private ModuleRep(File file) {
        this.file = file;
        
        module = Module.open(file.get_path(), ModuleFlags.BIND_LAZY);
    }
    
    ~ModuleRep() {
        // ensure that the Spit.Module is destroyed before the GLib.Module
        spit_module = null;
    }
    
    // Have to use this funky static factory because GModule is a compact class and has no copy
    // constructor.  The handle must be kept open for the lifetime of the application (or until
    // the module is ready to be discarded), as dropping the reference will unload the binary.
    public static ModuleRep? open(File file) {
        ModuleRep module_rep = new ModuleRep(file);
        
        return (module_rep.module != null) ? module_rep : null;
    }
}

private class PluggableRep {
    public Spit.Pluggable pluggable { get; private set; }
    public string id { get; private set; }
    public bool is_core { get; private set; default = false; }
    public bool activated { get; private set; default = false; }
    
    private bool enabled = false;
    
    // Note that creating a PluggableRep does not activate it.
    public PluggableRep(Spit.Pluggable pluggable) {
        this.pluggable = pluggable;
        id = pluggable.get_id();
    }
    
    public void activate() {
        // determine if a core pluggable (which is only known after all the extension points
        // register themselves)
        is_core = is_core_pluggable(pluggable);
        
       FuzzyPropertyState saved_state = Config.Facade.get_instance().is_plugin_enabled(id);
        enabled = ((is_core && (saved_state != FuzzyPropertyState.DISABLED)) ||
            (!is_core && (saved_state == FuzzyPropertyState.ENABLED)));
        
        // inform the plugin of its activation state
        pluggable.activation(enabled);
        
        activated = true;
    }
    
    public bool is_enabled() {
        return enabled;
    }
    
    // Returns true if value changed, false otherwise
    public bool set_enabled(bool enabled) {
        if (enabled == this.enabled)
            return false;
        
        this.enabled = enabled;
        Config.Facade.get_instance().set_plugin_enabled(id, enabled);
        pluggable.activation(enabled);
        
        return true;
    }
}

private File[] search_dirs;
private Gee.HashMap<string, ModuleRep> module_table;
private Gee.HashMap<string, PluggableRep> pluggable_table;
private Gee.HashMap<Type, ExtensionPoint> extension_points;
private Gee.HashSet<string> core_ids;

public void init() throws Error {
    search_dirs = new File[0];
    unowned string plugin_dir = Environment.get_variable("SHOTWELL_PLUGIN_PATH");
    if (plugin_dir != null && plugin_dir != "") {
        search_dirs += File.new_for_commandline_arg(plugin_dir);
    }
    search_dirs += AppDirs.get_user_plugins_dir();
    search_dirs += AppDirs.get_system_plugins_dir();
    
    module_table = new Gee.HashMap<string, ModuleRep>();
    pluggable_table = new Gee.HashMap<string, PluggableRep>();
    extension_points = new Gee.HashMap<Type, ExtensionPoint>();
    core_ids = new Gee.HashSet<string>();
    
    // do this after constructing member variables so accessors don't blow up if GModule isn't
    // supported
    if (!Module.supported()) {
        warning("Plugins not support: GModule not supported on this platform.");
        
        return;
    }
    
    foreach (File dir in search_dirs) {
        try {
            search_for_plugins(dir);
        } catch (Error err) {
            debug("Unable to search directory %s for plugins: %s", dir.get_path(), err.message);
        }
    }
}

public void terminate() {
    search_dirs = null;
    pluggable_table = null;
    module_table = null;
    extension_points = null;
    core_ids = null;
}

public class Notifier {
    private static Notifier? instance = null;
    
    public signal void pluggable_activation(Spit.Pluggable pluggable, bool enabled);
    
    private Notifier() {
    }
    
    public static Notifier get_instance() {
        if (instance == null)
            instance = new Notifier();
        
        return instance;
    }
}

public void register_extension_point(Type type, string name, string? icon_name, string[]? core_ids) {
    // if this assertion triggers, it means this extension point has already registered
    assert(!extension_points.has_key(type));
    
    extension_points.set(type, new ExtensionPoint(type, name, icon_name, core_ids));
    
    // add core IDs to master list
    if (core_ids != null) {
        foreach (string core_id in core_ids)
            Plugins.core_ids.add(core_id);
    }
    
    // activate all the pluggables for this extension point
    foreach (PluggableRep pluggable_rep in pluggable_table.values) {
        if (!pluggable_rep.pluggable.get_type().is_a(type))
            continue;
        
        pluggable_rep.activate();
        Notifier.get_instance().pluggable_activation(pluggable_rep.pluggable, pluggable_rep.is_enabled());
    }
}

public Gee.Collection<Spit.Pluggable> get_pluggables(bool include_disabled = false) {
    Gee.Collection<Spit.Pluggable> all = new Gee.HashSet<Spit.Pluggable>();
    foreach (PluggableRep pluggable_rep in pluggable_table.values) {
        if (pluggable_rep.activated && (include_disabled || pluggable_rep.is_enabled()))
            all.add(pluggable_rep.pluggable);
    }
    
    return all;
}

public bool is_core_pluggable(Spit.Pluggable pluggable) {
    return core_ids.contains(pluggable.get_id());
}

private ModuleRep? get_module_for_pluggable(Spit.Pluggable needle) {
    foreach (ModuleRep module_rep in module_table.values) {
        Spit.Pluggable[]? pluggables = module_rep.spit_module.get_pluggables();
        if (pluggables != null) {
            foreach (Spit.Pluggable pluggable in pluggables) {
                if (pluggable == needle)
                    return module_rep;
            }
        }
    }
    
    return null;
}

public string? get_pluggable_module_id(Spit.Pluggable needle) {
    ModuleRep? module_rep = get_module_for_pluggable(needle);
    
    return (module_rep != null) ? module_rep.spit_module.get_id() : null;
}

public Gee.Collection<ExtensionPoint> get_extension_points(owned CompareDataFunc? compare_func = null) {
    Gee.Collection<ExtensionPoint> sorted = new Gee.TreeSet<ExtensionPoint>((owned) compare_func);
    sorted.add_all(extension_points.values);
    
    return sorted;
}

public Gee.Collection<Spit.Pluggable> get_pluggables_for_type(Type type,
    owned CompareDataFunc? compare_func = null, bool include_disabled = false) {
    // if this triggers it means the extension point didn't register itself at init() time
    assert(extension_points.has_key(type));
    
    Gee.Collection<Spit.Pluggable> for_type = new Gee.TreeSet<Spit.Pluggable>((owned) compare_func);
    foreach (PluggableRep pluggable_rep in pluggable_table.values) {
        if (pluggable_rep.activated 
            && pluggable_rep.pluggable.get_type().is_a(type) 
            && (include_disabled || pluggable_rep.is_enabled())) {
            for_type.add(pluggable_rep.pluggable);
        }
    }
    
    return for_type;
}

public string? get_pluggable_name(string id) {
    PluggableRep? pluggable_rep = pluggable_table.get(id);
    
    return (pluggable_rep != null && pluggable_rep.activated) 
        ? pluggable_rep.pluggable.get_pluggable_name() : null;
}

public bool get_pluggable_info(string id, ref Spit.PluggableInfo info) {
    PluggableRep? pluggable_rep = pluggable_table.get(id);
    if (pluggable_rep == null || !pluggable_rep.activated)
        return false;
    
    pluggable_rep.pluggable.get_info(ref info);
    
    return true;
}

public bool get_pluggable_enabled(string id, out bool enabled) {
    PluggableRep? pluggable_rep = pluggable_table.get(id);
    if (pluggable_rep == null || !pluggable_rep.activated) {
        enabled = false;
        
        return false;
    }
    
    enabled = pluggable_rep.is_enabled();
    
    return true;
}

public void set_pluggable_enabled(string id, bool enabled) {
    PluggableRep? pluggable_rep = pluggable_table.get(id);
    if (pluggable_rep == null || !pluggable_rep.activated)
        return;
    
    if (pluggable_rep.set_enabled(enabled))
        Notifier.get_instance().pluggable_activation(pluggable_rep.pluggable, enabled);
}

public File get_pluggable_module_file(Spit.Pluggable pluggable) {
    ModuleRep? module_rep = get_module_for_pluggable(pluggable);
    
    return (module_rep != null) ? module_rep.file : null;
}

public int compare_pluggable_names(void *a, void *b) {
    Spit.Pluggable *apluggable = (Spit.Pluggable *) a;
    Spit.Pluggable *bpluggable = (Spit.Pluggable *) b;
    
    return apluggable->get_pluggable_name().collate(bpluggable->get_pluggable_name());
}

public int compare_extension_point_names(void *a, void *b) {
    ExtensionPoint *apoint = (ExtensionPoint *) a;
    ExtensionPoint *bpoint = (ExtensionPoint *) b;
    
    return apoint->name.collate(bpoint->name);
}

private bool is_shared_library(File file) {
    string name, ext;
    disassemble_filename(file.get_basename(), out name, out ext);
    
    foreach (string shared_ext in SHARED_LIB_EXTS) {
        if (ext == shared_ext)
            return true;
    }
    
    return false;
}

private void search_for_plugins(File dir) throws Error {
    debug("Searching %s for plugins…", dir.get_path());
    
    // build a set of module names sans file extension ... this is to deal with the question of
    // .so vs. .la existing in the same directory (and letting GModule deal with the problem)
    FileEnumerator enumerator = dir.enumerate_children(Util.FILE_ATTRIBUTES,
        FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
    for (;;) {
        FileInfo? info = enumerator.next_file(null);
        if (info == null)
            break;
        
        if (info.get_is_hidden())
            continue;
        
        File file = dir.get_child(info.get_name());
        
        switch (info.get_file_type()) {
            case FileType.DIRECTORY:
                try {
                    search_for_plugins(file);
                } catch (Error err) {
                    warning("Unable to search directory %s for plugins: %s", file.get_path(), err.message);
                }
            break;
            
            case FileType.REGULAR:
                if (is_shared_library(file))
                    load_module(file);
            break;
            
            default:
                // ignored
            break;
        }
    }
}

private void load_module(File file) {
    ModuleRep? module_rep = ModuleRep.open(file);
    if (module_rep == null) {
        critical("Unable to load module %s: %s", file.get_path(), Module.error());
        
        return;
    }
    
    // look for the well-known entry point
    void *entry;
    if (!module_rep.module.symbol(Spit.ENTRY_POINT_NAME, out entry)) {
        critical("Unable to load module %s: well-known entry point %s not found", file.get_path(),
            Spit.ENTRY_POINT_NAME);
        
        return;
    }
    
    Spit.EntryPoint spit_entry_point = (Spit.EntryPoint) entry;
    
    assert(MIN_SPIT_INTERFACE <= Spit.CURRENT_INTERFACE && Spit.CURRENT_INTERFACE <= MAX_SPIT_INTERFACE);
    Spit.EntryPointParams params = Spit.EntryPointParams();
    params.host_min_spit_interface = MIN_SPIT_INTERFACE;
    params.host_max_spit_interface = MAX_SPIT_INTERFACE;
    params.module_spit_interface = Spit.UNSUPPORTED_INTERFACE;
    params.module_file = file;
    
    module_rep.spit_module = spit_entry_point(&params);
    if (params.module_spit_interface == Spit.UNSUPPORTED_INTERFACE) {
        critical("Unable to load module %s: module reports no support for SPIT interfaces %d to %d",
            file.get_path(), MIN_SPIT_INTERFACE, MAX_SPIT_INTERFACE);
        
        return;
    }
    
    if (params.module_spit_interface < MIN_SPIT_INTERFACE || params.module_spit_interface > MAX_SPIT_INTERFACE) {
        critical("Unable to load module %s: module reports unsupported SPIT version %d (out of range %d to %d)",
            file.get_path(), module_rep.spit_interface, MIN_SPIT_INTERFACE, MAX_SPIT_INTERFACE);
        
        return;
    }
    
    module_rep.spit_interface = params.module_spit_interface;
    
    // verify type (as best as possible; still potential to segfault inside GType here)
    if (!(module_rep.spit_module is Spit.Module))
        module_rep.spit_module = null;
    
    if (module_rep.spit_module == null) {
        critical("Unable to load module %s (SPIT %d): no spit module returned", file.get_path(),
            module_rep.spit_interface);
        
        return;
    }
    
    // if module has already been loaded, drop this one (search path is set up to load user-installed
    // binaries prior to system binaries)
    module_rep.id = prepare_input_text(module_rep.spit_module.get_id(), PrepareInputTextOptions.DEFAULT, -1);
    if (module_rep.id == null) {
        critical("Unable to load module %s (SPIT %d): invalid or empty module name",
            file.get_path(), module_rep.spit_interface);
        
        return;
    }
    
    if (module_table.has_key(module_rep.id)) {
        critical("Not loading module %s (SPIT %d): module with name \"%s\" already loaded",
            file.get_path(), module_rep.spit_interface, module_rep.id);
        
        return;
    }
    
    debug("Loaded SPIT module \"%s %s\" (%s) [%s]", module_rep.spit_module.get_module_name(),
        module_rep.spit_module.get_version(), module_rep.id, file.get_path());
    
    // stash in module table by their ID
    module_table.set(module_rep.id, module_rep);
    
    // stash pluggables in pluggable table by their ID
    foreach (Spit.Pluggable pluggable in module_rep.spit_module.get_pluggables())
        pluggable_table.set(pluggable.get_id(), new PluggableRep(pluggable));
}

}

