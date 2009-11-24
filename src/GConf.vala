/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

/* This is an alternate implementation of a small subset of GConf.  This implementation simply
 * writes keys/values to a .ini file.  We use it on Windows and Mac OS, where there is no
 * GConf server running.  On those platforms we could conceivably bundle a full-on GConf server
 * and launch it when Shotwell starts up, but this approach is much lighter-weight.
 *
 * This implementation will not be well-behaved if you try to use it from multiple processes at
 * the same time.  That's not an issue (yet) because Shotwell doesn't (yet) write to any GConf
 * keys in direct-edit mode.
 */

namespace GConf {

class Client {
    KeyFile key_file = new KeyFile();
    
    const string DATA = "data";
    
    Client() {
        try {
            key_file.load_from_file(filename(), KeyFileFlags.NONE);
        } catch (FileError e) { }
          catch (KeyFileError e) { }
    }
    
    public static Client get_default() {
        return new Client();
    }

    string filename() {
        return AppDirs.get_data_dir().get_child("shotwell.ini").get_path();
    }
    
    void write() {
        FileStream output = FileStream.open(filename(), "w");
        output.puts(key_file.to_data());
    }
    
    public bool get_bool(string key) throws Error {
        // The KeyFile.get_xxx() methods throws an error when a key is absent,
        // but the GConf.get_xxx() methods return a default value without error in this case.
        try {
            return key_file.get_boolean(DATA, key);
        } catch (KeyFileError e) { return false; }
    }
    
    public void set_bool(string key, bool val) throws Error {
        if (val != get_bool(key)) {
            key_file.set_boolean(DATA, key, val);
            write();
        }
    }
    
    public string? get_string(string key) throws Error {
        try {
            return key_file.get_string(DATA, key);
        } catch (KeyFileError e) { return null; }
    }
    
    public void set_string(string key, string val) throws Error {
        if (val != get_string(key)) {
            key_file.set_string(DATA, key, val);
            write();
        }
    }
    
    public double get_float(string key) throws Error {
        try {
            return key_file.get_double(DATA, key);
        } catch (KeyFileError e) { return 0.0; }
    }
    
    public void set_float(string key, double val) throws Error {
        if (val != get_float(key)) {
            key_file.set_double(DATA, key, val);
            write();
        }
    }
}

}

