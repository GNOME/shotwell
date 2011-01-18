/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Shotwell.Plugins;

namespace Plugins {

// GModule doesn't have a truly generic way to determine if a file is a shared library by extension,
// so these are hard-coded
private const string[] SHARED_LIB_EXTS = { "so", "la" };

// Although not expecting this system to last very long, these ranges declare what versions of this
// interface are supported by the current implementation.
private const int MIN_SPIT_VERSION = 1;
private const int MAX_SPIT_VERSION = 1;

private class SpitModule {
    public Module? module;
    public SpitWad? spitwad = null;
    public int spit_version = UNSUPPORTED_SPIT_VERSION;
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
    if (!spit_module.module.symbol(SPIT_ENTRY_POINT, out entry)) {
        critical("Unable to load module %s: well-known entry point %s not found", file.get_path(),
            SPIT_ENTRY_POINT);
        
        return;
    }
    
    SpitEntryPoint spit_entry_point = (SpitEntryPoint) entry;
    
    assert(MIN_SPIT_VERSION <= SPIT_VERSION && SPIT_VERSION <= MAX_SPIT_VERSION);
    spit_module.spit_version = UNSUPPORTED_SPIT_VERSION;
    spit_module.spitwad = spit_entry_point(SPIT_VERSION, out spit_module.spit_version);
    if (spit_module.spit_version == UNSUPPORTED_SPIT_VERSION) {
        critical("Unable to load module %s: module reports unsupported SPIT version %d", file.get_path(),
            SPIT_VERSION);
        
        return;
    }
    
    if (spit_module.spit_version < MIN_SPIT_VERSION || spit_module.spit_version > MAX_SPIT_VERSION) {
        critical("Unable to load module %s: module reports unsupported SPIT version %d (out of range %d - %d)",
            file.get_path(), spit_module.spit_version, MIN_SPIT_VERSION, MAX_SPIT_VERSION);
        
        return;
    }
    
    // verify type (as best as possible; still potential to segfault inside GType here)
    if (!(spit_module.spitwad is SpitWad))
        spit_module.spitwad = null;
    
    if (spit_module.spitwad == null) {
        critical("Unable to load module %s (SPIT %d): no SpitWad returned", file.get_path(),
            spit_module.spit_version);
        
        return;
    }
    
    // if module has already been loaded, drop this one (search path is set up to load user-installed
    // binaries prior to system binaries)
    spit_module.wad_name = prepare_input_text(spit_module.spitwad.get_wad_name(), 
        PrepareInputTextOptions.DEFAULT);
    if (spit_module.wad_name == null) {
        critical("Unable to load module %s (SPIT %d): invalid or empty wad name",
            file.get_path(), spit_module.spit_version);
        
        return;
    }
    
    if (module_table.has_key(spit_module.wad_name)) {
        critical("Not loading module %s (SPIT %d): wad with name \"%s\" already loaded",
            file.get_path(), spit_module.spit_version, spit_module.wad_name);
        
        return;
    }
    
    debug("Loaded SPIT module \"%s %s\" (%s) [%s]", spit_module.spitwad.get_name(),
        spit_module.spitwad.get_version(), spit_module.wad_name, file.get_path());
    
    // stash in module table
    module_table.set(spit_module.wad_name, spit_module);
}

}

