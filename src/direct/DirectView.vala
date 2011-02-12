/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class DirectView : DataView {
    private File file;
    private string? collate_key = null;
    
    public DirectView(DirectPhotoPlaceholder placeholder) {
        base (placeholder);
        
        this.file = placeholder.get_file();
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
            return new DirectView((DirectPhotoPlaceholder) source);
        }
    }
    
    public DirectViewCollection(File initial_file) {
        base ("DirectViewCollection of %s".printf(initial_file.get_parent().get_path()));
        
        set_comparator(filename_comparator, null);
        monitor_source_collection(DirectPhotoPlaceholder.global, new DirectViewManager(), null);
    }
    
    private static int64 filename_comparator(void *a, void *b) {
        DirectView *aview = (DirectView *) a;
        DirectView *bview = (DirectView *) b;
        
        return strcmp(aview->get_collate_key(), bview->get_collate_key());
    }
}

