/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Utils {

/**
 * A class that represents a version number in the form x.y.z and is able to compare
 * different versions.
 */
public class VersionNumber : Object, Gee.Comparable<VersionNumber> {
    private int[] version;
    
    public VersionNumber(int[] version) {
        this.version = version;
    }
    
    public VersionNumber.from_string(string str_version, string separator = ".") {
        string[] version_items = str_version.split(separator);
        this.version = new int[version_items.length];
        for (int i = 0; i < version_items.length; i++)
            this.version[i] = int.parse(version_items[i]);
    }
    
    public string to_string() {
        string[] version_items = new string[this.version.length];
        for (int i = 0; i < this.version.length; i++)
            version_items[i] = this.version[i].to_string();
        return string.joinv(".", version_items);
    }
    
    public int compare_to(VersionNumber other) {
        int max_len = ((this.version.length > other.version.length) ?
                       this.version.length : other.version.length);
        int res = 0;
        for(int i = 0; i < max_len; i++) {
            int this_v = (i < this.version.length ? this.version[i] : 0);
            int other_v = (i < other.version.length ? other.version[i] : 0);
            res = this_v - other_v;
            if (res != 0)
                break;
        }
        return res;
    }
}

}

