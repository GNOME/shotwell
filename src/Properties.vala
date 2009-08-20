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
    private int event_count;
    string basic_properties_labels;
    string basic_properties_info;
    bool first_line; 

    public BasicProperties() {
        label.set_justify(Gtk.Justification.RIGHT);
        label.set_alignment(0, (float) 5e-1);
        info.set_alignment(0, (float) 5e-1);
        pack_start(label, false, false, 3);
        pack_start(info, true, true, 3);
        
        info.set_ellipsize(Pango.EllipsizeMode.END);
    }

    private void add_line(string label, string info) {
        if (!first_line) {
            basic_properties_labels += "\n";
            basic_properties_info += "\n";
        }
        basic_properties_labels += label;
        basic_properties_info += info;
        first_line = false;
    }
    
    private string get_prettyprint_time(Time time) {
        return "%d:%02d %s".printf(((time.hour + 11) % 12) + 1, time.minute, 
            time.hour < 12 ? "AM" : "PM");    
    }

    private string get_prettyprint_date(Time date) {
        string date_string = "";
        Time today = Time.local(time_t());
        if (date.day_of_year == today.day_of_year && date.year == today.year) {
            date_string = "Today";
        } else if (date.day_of_year == (today.day_of_year - 1) && date.year == today.year) {
            date_string = "Yesterday";
        } else {
            date_string = date.format("%a %b") + " %d, %d".printf(date.day, 1900 + date.year);
        }

        return date_string;   
    }

    private void set_text() {
        label.set_text(basic_properties_labels);
        info.set_text(basic_properties_info);
    }

    public void clear_properties() {
        title = "";
        start_time = 0;
        end_time = 0;
        dimensions = Dimensions(0,0);
        filesize = 0;
        photo_count = -1;
        event_count = -1;
        basic_properties_labels = "";
        basic_properties_info = "";
        first_line = true;
    }

    private void get_single_properties(Queryable queryable) {
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

            filesize = event_source.get_total_filesize();
            photo_count = event_source.get_photo_count();
        }
    }

    private void get_multiple_properties(Gee.Iterable<Queryable>? queryables) {
        photo_count = 0;
        foreach (Queryable queryable in queryables) {
            if (queryable is PhotoSource) {
                PhotoSource photo_source = queryable as PhotoSource;
                    
                time_t exposure_time = photo_source.get_exposure_time();

                if (exposure_time != 0) {
                    if (start_time == 0 || exposure_time < start_time)
                        start_time = exposure_time;

                    if (end_time == 0 || exposure_time > end_time)
                        end_time = exposure_time;
                }
                
                filesize += photo_source.get_filesize();
                photo_count += 1;

            } else if (queryable is EventSource) {
                EventSource event_source = queryable as EventSource;
          
                if (event_count == -1)
                    event_count = 0;

                if ((start_time == 0 || event_source.get_start_time() < start_time) &&
                    event_source.get_start_time() != 0 ) {
                    start_time = event_source.get_start_time();
                }
                if ((end_time == 0 || event_source.get_end_time() > end_time) &&            
                    event_source.get_end_time() != 0 ) {
                    end_time = event_source.get_end_time();
                } else if (end_time == 0 || event_source.get_start_time() > end_time) {
                    end_time = event_source.get_start_time();
                }

                filesize += event_source.get_total_filesize();
                photo_count += event_source.get_photo_count();
                event_count += 1;
            }
        }       
    }  

    private void get_properties(Page current_page) {
        int count = current_page.get_selected_queryable_count();
        Gee.Iterable<Queryable>? queryables = current_page.get_selected_queryables();

        if (count == 0) {
            count = current_page.get_queryable_count();
            queryables = current_page.get_queryables();
        }

        if (queryables == null || count == 0)
            return;

        if (count == 1) {
            foreach (Queryable queryable in queryables)
                get_single_properties(queryable);
        } else {
            get_multiple_properties(queryables);
        }

        if (end_time == 0)
            end_time = start_time;
        if (start_time == 0)
            start_time = end_time;
    }

    public void update_properties(Page current_page) {
        clear_properties();
        get_properties(current_page);   

        if (title != "")
            add_line("Title:",title);

        if (photo_count >= 0) {
            string label = "Items:";
  
            if (event_count >= 0) {
                add_line(label, "%d Event%s".printf(event_count, event_count == 1 ? "" : "s"));
                label = "";
            }

            add_line(label, "%d Photo%s".printf(photo_count, photo_count == 1 ? "" : "s"));
        }

        if (start_time != 0) {
            string start_date = get_prettyprint_date(Time.local(start_time));
            string start_time = get_prettyprint_time(Time.local(start_time));
            string end_date = get_prettyprint_date(Time.local(end_time));
            string end_time = get_prettyprint_time(Time.local(end_time));

            if (start_date == end_date) {
                // display only one date if start and end are the same
                add_line("Date:", start_date);

                if (start_time == end_time) {
                    // display only one time if start and end are the same
                    add_line("Time:", start_time);
                } else {
                    // display time range
                    add_line("From:", start_time);
                    add_line("To:", end_time);
                }
            } else {
                // display date range
                add_line("From:", start_date);
                add_line("To:", end_date);
            }
        }

        if (filesize > 0 || dimensions.has_area()) {
            string label = "Size:";

            if (dimensions.has_area()) {
                add_line(label, "%d x %d".printf(dimensions.width, dimensions.height));
                label = "";
            }

            if (filesize > 0)
                add_line(label, format_size_for_display((int64) filesize));
        }

        set_text();
    }
}
