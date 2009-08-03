/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/*
 * This is a patch for GLib.KeyFile, which has a bad binding for get_keys() (which returns the array
 * length as a gsize, whose size is platform-dependent, while the binding generates code for an int
 * every time.)  This vapi will be necessary until the binding is fixed.  See also
 * http://bugzilla.gnome.org/show_bug.cgi?id=588104
 */

[Compact]
[CCode (cname="GKeyFile", cprefix="g_key_file_", free_function="g_key_file_free")]
public class FixedKeyFile {
    public FixedKeyFile();
    public bool load_from_data (string data, ulong length, GLib.KeyFileFlags flags) throws GLib.KeyFileError;
    public bool has_group (string group_name);
    [CCode (array_length = false)]
    public string[] get_keys(string group_name, out size_t count) throws GLib.KeyFileError;
    public string get_string (string group_name, string key) throws GLib.KeyFileError;
    public void set_string (string group_name, string key, string str);
    // g_key_file_to_data never throws an error according to the documentation
    public string to_data (out size_t length = null, out GLib.Error error = null);
    public void remove_group (string group_name) throws GLib.KeyFileError;
}

