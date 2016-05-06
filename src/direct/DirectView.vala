/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class DirectView : DataView {
    private File file;
    private string? collate_key = null;
    
    public DirectView(DirectPhoto source) {
        base ((DataSource) source);
        
        this.file = ((Photo) source).get_file();
    }
    
    public File get_file() {
        return file;
    }
    
    public string get_collate_key() {
        if (collate_key == null)
            collate_key = file.get_basename().collate_key_for_filename();
        
        return collate_key;
    }
}

private class DirectViewCollection : ViewCollection {
    private class DirectViewManager : ViewManager {
        public override DataView create_view(DataSource source) {
            return new DirectView((DirectPhoto) source);
        }
    }
    
    public DirectViewCollection() {
        base ("DirectViewCollection");
        
        set_comparator(filename_comparator, null);
        monitor_source_collection(DirectPhoto.global, new DirectViewManager(), null);
    }
    
    private static int64 filename_comparator(void *a, void *b) {
        DirectView *aview = (DirectView *) a;
        DirectView *bview = (DirectView *) b;
        
        return strcmp(aview->get_collate_key(), bview->get_collate_key());
    }
}

