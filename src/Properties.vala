/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

private class BasicProperties : Gtk.HBox {
    private Gtk.Label label = new Gtk.Label("");
    private Gtk.Label info = new Gtk.Label(""); 
    private string title;
    private time_t start_time = time_t();
    private time_t end_time = time_t();
    private Dimensions dimensions;
    private uint64 filesize;
    private int photo_count;      

    public BasicProperties() {
        label.set_justify(Gtk.Justification.RIGHT);
        label.set_alignment(0, (float) 5e-1);
        info.set_alignment(0, (float) 5e-1);
        pack_start(label, false, false, 3);
        pack_start(info, true, true, 3);
        
        info.set_ellipsize(Pango.EllipsizeMode.END);
    }
    
    private string get_prettyprint_time(Time time) {
        return "%d:%02d %s".printf((time.hour-1)%12+1, time.minute, 
            time.hour < 12 ? "AM" : "PM");    
    }

    private string get_prettyprint_date(Time time) {
        return time.format("%a %b") + " %d, %d".printf(time.day, 1900 + time.year);    
    }

    private void set_text(string new_label, string new_info) {
        label.set_text(new_label);
        info.set_text(new_info);
    }

    public void clear_properties() {
        title = "";
        start_time = time_t();
        end_time = time_t();
        dimensions = Dimensions(0,0);
        filesize = 0;
        photo_count = -1;
    }

    public void update_properties(Page current_page) {
        clear_properties();
        get_properties(current_page);   

        string basic_properties_labels = "";
        string basic_properties_info = "";

        if (title != "") {
            basic_properties_labels += "Title:";
            basic_properties_info += title;
        }

        if (photo_count >= 0) {
            basic_properties_labels += "\nItems:";
            basic_properties_info += "\n%d".printf(photo_count);
            basic_properties_info += photo_count == 1 ? " Photo" : " Photos";
        }

        if (start_time != time_t()) {
            string start_date = get_prettyprint_date(Time.local(start_time));
            string start_time = get_prettyprint_time(Time.local(start_time));
            string end_date = get_prettyprint_date(Time.local(end_time));
            string end_time = get_prettyprint_time(Time.local(end_time));
            if (start_date == end_date) {
                basic_properties_labels += "\nDate:";
                basic_properties_info += "\n" + start_date;
                if (start_date == end_date && start_time == end_time) {
                    basic_properties_labels += "\nTime:";
                    basic_properties_info += "\n" + start_time;
                } else {
                    basic_properties_labels += "\nTime:\n";
                    basic_properties_info += "\n" + start_time + " to\n" + end_time;
                }
            } else {
                basic_properties_labels += "\nDate:\n";
                basic_properties_info += "\n" + start_date + " to\n" + end_date;
           }
            
        }

        if (filesize > 0 || (dimensions.width != 0 && dimensions.height != 0)) {
            basic_properties_labels += "\nSize:";

            if (filesize > 0 && (dimensions.width != 0 && dimensions.height != 0)) {
                basic_properties_labels += "\n";
            }

            if (dimensions.width != 0 && dimensions.height != 0) {
                basic_properties_info += "\n%d x %d".printf(dimensions.width, dimensions.height);
            }

            if (filesize > 0) {
                basic_properties_info += "\n" + format_size_for_display((int64) filesize);
            }
        }

        set_text(basic_properties_labels, basic_properties_info);
    }
    
    private void get_properties(Page current_page) {
        int count = current_page.get_selected_queryable_count();
        Gee.Iterable<Queryable>? queryables = current_page.get_selected_queryables();

        if (queryables == null)
            return;

        if (count == 1) {
            foreach (Queryable queryable in queryables) {
                title = queryable.get_name();
                if (queryable is PhotoSource) {
                    PhotoSource photo_source = queryable as PhotoSource;
                    
                    start_time = photo_source.get_exposure_time();
                    end_time = start_time;
                    
                    dimensions = photo_source.get_dimensions();
                    
                    filesize = photo_source.get_filesize();
                } else if (queryable is EventSource) {
                    EventSource event_source = queryable as EventSource;

                    start_time = event_source.get_start_time();
                    end_time = event_source.get_end_time();
                    if (end_time == 0) {
                        end_time = start_time;
                    }

                    filesize = event_source.get_total_filesize();
                    photo_count = event_source.get_photo_count();
                }
            }
        } else if (count == 0) {
            count = current_page.get_queryable_count();
            queryables = current_page.get_queryables();
        }
    }
}
