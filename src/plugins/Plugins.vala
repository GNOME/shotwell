/* Copyright 2011 Yorba Foundation
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

private class SpitModule {
    public Module? module;
    public unowned Spit.Wad? spitwad = null;
    public int spit_interface = Spit.UNSUPPORTED_INTERFACE;
    public string? wad_name = null;
    
    private SpitModule() {
    }
    
    // Have to use this funky static factory because GModule is a compact class and has no copy
    // constructor.  The handle must be kept open for the lifetime of the application (or until
    // the module is ready to be discarded), as dropping the reference will unload the binary.
    public static SpitModule? open(File file) {
        SpitModule spit_module = new SpitModule();
        
        spit_module.module = Module.open(file.get_path(), ModuleFlags.BIND_LAZY);
        
        return (spit_module.module != null) ? spit_module : null;
    }
}

private File[] search_dirs;
private Gee.HashMap<string, SpitModule> module_table;

public void init() throws Error {
    if (!Module.supported()) {
        warning("Plugins not support: GModule not supported on this platform.");
        
        return;
    }
    
    search_dirs = new File[0];
    search_dirs += AppDirs.get_user_plugins_dir();
    search_dirs += AppDirs.get_system_plugins_dir();
    
    module_table = new Gee.HashMap<string, SpitModule>();
    
    foreach (File dir in search_dirs) {
        try {
            search_for_plugins(dir);
        } catch (Error err) {
            warning("Unable to search directory %s for plugins: %s", dir.get_path(), err.message);
        }
    }
}

public void terminate() {
    search_dirs = null;
    module_table = null;
}

public Gee.Collection<Spit.Pluggable> get_pluggables_for_type(Type type) {
    Gee.Collection<Spit.Pluggable> for_type = new Gee.HashSet<Spit.Pluggable>();
    foreach (SpitModule module in module_table.values) {
        Spit.Pluggable[]? pluggables = module.spitwad.get_pluggables();
        if (pluggables != null) {
            foreach (Spit.Pluggable pluggable in pluggables) {
                if (pluggable.get_type().is_a(type))
                    for_type.add(pluggable);
            }
        }
    }
    
    return for_type;
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
    debug("Searching %s for plugins ...", dir.get_path());
    
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
    SpitModule? spit_module = SpitModule.open(file);
    if (spit_module == null) {
        critical("Unable to load module %s: %s", file.get_path(), Module.error());
        
        return;
    }
    
    // look for the well-known entry point
    void *entry;
    if (!spit_module.module.symbol(Spit.ENTRY_POINT_NAME, out entry)) {
        critical("Unable to load module %s: well-known entry point %s not found", file.get_path(),
            Spit.ENTRY_POINT_NAME);
        
        return;
    }
    
    Spit.EntryPoint spit_entry_point = (Spit.EntryPoint) entry;
    
    assert(MIN_SPIT_INTERFACE <= Spit.CURRENT_INTERFACE && Spit.CURRENT_INTERFACE <= MAX_SPIT_INTERFACE);
    spit_module.spit_interface = Spit.UNSUPPORTED_INTERFACE;
    spit_module.spitwad = spit_entry_point(MIN_SPIT_INTERFACE, MAX_SPIT_INTERFACE, out spit_module.spit_interface);
    if (spit_module.spit_interface == Spit.UNSUPPORTED_INTERFACE) {
        critical("Unable to load module %s: module reports no support for SPIT interfaces %d to %d",
            file.get_path(), MIN_SPIT_INTERFACE, MAX_SPIT_INTERFACE);
        
        return;
    }
    
    if (spit_module.spit_interface < MIN_SPIT_INTERFACE || spit_module.spit_interface > MAX_SPIT_INTERFACE) {
        critical("Unable to load module %s: module reports unsupported SPIT version %d (out of range %d to %d)",
            file.get_path(), spit_module.spit_interface, MIN_SPIT_INTERFACE, MAX_SPIT_INTERFACE);
        
        return;
    }
    
    // verify type (as best as possible; still potential to segfault inside GType here)
    if (!(spit_module.spitwad is Spit.Wad))
        spit_module.spitwad = null;
    
    if (spit_module.spitwad == null) {
        critical("Unable to load module %s (SPIT %d): no spitwad returned", file.get_path(),
            spit_module.spit_interface);
        
        return;
    }
    
    // if module has already been loaded, drop this one (search path is set up to load user-installed
    // binaries prior to system binaries)
    spit_module.wad_name = prepare_input_text(spit_module.spitwad.get_wad_name(), 
        PrepareInputTextOptions.DEFAULT);
    if (spit_module.wad_name == null) {
        critical("Unable to load module %s (SPIT %d): invalid or empty wad name",
            file.get_path(), spit_module.spit_interface);
        
        return;
    }
    
    if (module_table.has_key(spit_module.wad_name)) {
        critical("Not loading module %s (SPIT %d): wad with name \"%s\" already loaded",
            file.get_path(), spit_module.spit_interface, spit_module.wad_name);
        
        return;
    }
    
    debug("Loaded SPIT module \"%s %s\" (%s) [%s]", spit_module.spitwad.get_name(),
        spit_module.spitwad.get_version(), spit_module.wad_name, file.get_path());
    
    // stash in module table
    module_table.set(spit_module.wad_name, spit_module);
}

}

