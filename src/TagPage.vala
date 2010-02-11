/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class TagPage : CollectionPage {
    private Tag tag;
    
    public TagPage(Tag tag) {
        base (tag.get_name());
        
        this.tag = tag;
        
        tag.mirror_photos(get_view(), create_thumbnail);
    }
    
    ~TagPage() {
        get_view().halt_mirroring();
    }
    
    public Tag get_tag() {
        return tag;
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.get_instance().get_library_photos_sort(out sort_order, out sort_by);
    }

    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.get_instance().set_library_photos_sort(sort_order, sort_by);
    }
}

