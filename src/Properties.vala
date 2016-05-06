/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

private abstract class Properties : Gtk.Grid {
    uint line_count = 0;

    public Properties() {
        row_spacing = 0;
        column_spacing = 6;
    }

    protected void add_line(string label_text, string info_text, bool multi_line = false) {
        Gtk.Label label = new Gtk.Label("");
        Gtk.Widget info;

        label.set_justify(Gtk.Justification.RIGHT);
        
        label.set_markup(GLib.Markup.printf_escaped("<span font_weight=\"bold\">%s</span>", label_text));

        if (multi_line) {
            Gtk.ScrolledWindow info_scroll = new Gtk.ScrolledWindow(null, null);
            info_scroll.shadow_type = Gtk.ShadowType.ETCHED_IN;
            Gtk.TextView view = new Gtk.TextView();
            // by default TextView widgets have a white background, which
            // makes sense during editing. In this instance we only *show*
            // the content and thus want that the parent's background color
            // is inherited to the TextView
            Gtk.StyleContext context = info_scroll.get_style_context();
            view.override_background_color (Gtk.StateFlags.NORMAL,
                context.get_background_color(Gtk.StateFlags.NORMAL));
            view.set_wrap_mode(Gtk.WrapMode.WORD);
            view.set_cursor_visible(false);
            view.set_editable(false);
            view.buffer.text = is_string_empty(info_text) ? "" : info_text;
            info_scroll.add(view);
            label.set_alignment(1, 0);
            info = (Gtk.Widget) info_scroll;
        } else {
            Gtk.Label info_label = new Gtk.Label("");
            info_label.set_markup(is_string_empty(info_text) ? "" : info_text);
            info_label.set_alignment(0, (float) 5e-1);
            info_label.set_ellipsize(Pango.EllipsizeMode.END);
            info_label.set_selectable(true);
            label.set_alignment(1, (float) 5e-1);
            info = (Gtk.Widget) info_label;
        }

        attach(label, 0, (int) line_count, 1, 1);

        if (multi_line) {
            attach(info, 1, (int) line_count, 1, 2);
        } else {
            attach(info, 1, (int) line_count, 1, 1);
        }

        line_count++;
    }
    
    protected string get_prettyprint_time(Time time) {
        string timestring = time.format(Resources.get_hh_mm_format_string());
        
        if (timestring[0] == '0')
            timestring = timestring.substring(1, -1);
        
        return timestring;
    }
    
    protected string get_prettyprint_time_with_seconds(Time time) {
        string timestring = time.format(Resources.get_hh_mm_ss_format_string());
        
        if (timestring[0] == '0')
            timestring = timestring.substring(1, -1);
        
        return timestring;
    }
    
    protected string get_prettyprint_date(Time date) {
        string date_string = null;
        Time today = Time.local(time_t());
        if (date.day_of_year == today.day_of_year && date.year == today.year) {
            date_string = _("Today");
        } else if (date.day_of_year == (today.day_of_year - 1) && date.year == today.year) {
            date_string = _("Yesterday");
        } else {
            date_string = format_local_date(date);
        }

        return date_string;
    }
    
    protected virtual void get_single_properties(DataView view) {
    }

    protected virtual void get_multiple_properties(Gee.Iterable<DataView>? iter) {
    }

    protected virtual void get_properties(Page current_page) {
        ViewCollection view = current_page.get_view();
        if (view == null)
            return;

        // summarize selected items, if none selected, summarize all
        int count = view.get_selected_count();
        Gee.Iterable<DataView> iter = null;
        if (count != 0) {
            iter = view.get_selected();
        } else {
            count = view.get_count();
            iter = (Gee.Iterable<DataView>) view.get_all();
        }
        
        if (iter == null || count == 0)
            return;

        if (count == 1) {
            foreach (DataView item in iter) {
                get_single_properties(item);
                break;
            }
        } else {
            get_multiple_properties(iter);
        }
    }

    protected virtual void clear_properties() {
        foreach (Gtk.Widget child in get_children())
            remove(child);
        
        line_count = 0;
    }

    public void update_properties(Page page) {
        clear_properties();
        internal_update_properties(page);
        show_all();
    }

    public virtual void internal_update_properties(Page page) {
        get_properties(page);
    }
    
    public void unselect_text() {
        foreach (Gtk.Widget child in get_children()) {
            if (child is Gtk.Label)
                ((Gtk.Label) child).select_region(0, 0);
        }
    }
}

private class BasicProperties : Properties {
    private string title;
    private time_t start_time = time_t();
    private time_t end_time = time_t();
    private Dimensions dimensions;
    private int photo_count;
    private int event_count;
    private int video_count;
    private string exposure;
    private string aperture;
    private string iso;
    private double clip_duration;
    private string raw_developer;
    private string raw_assoc;

    public BasicProperties() {
    }

    protected override void clear_properties() {
        base.clear_properties();
        title = "";
        start_time = 0;
        end_time = 0;
        dimensions = Dimensions(0,0);
        photo_count = -1;
        event_count = -1;
        video_count = -1;
        exposure = "";
        aperture = "";
        iso = "";
        clip_duration = 0.0;
        raw_developer = "";
        raw_assoc = "";
    }

    protected override void get_single_properties(DataView view) {
        base.get_single_properties(view);

        DataSource source = view.get_source();

        title = source.get_name();
        
        if (source is PhotoSource || source is PhotoImportSource) {           
            start_time = (source is PhotoSource) ? ((PhotoSource) source).get_exposure_time() :
                ((PhotoImportSource) source).get_exposure_time();
            end_time = start_time;
                        
            PhotoMetadata? metadata = (source is PhotoSource) ? ((PhotoSource) source).get_metadata() :
                ((PhotoImportSource) source).get_metadata();

            if (metadata != null) {
                exposure = metadata.get_exposure_string();
                if (exposure == null)
                    exposure = "";
                
                aperture = metadata.get_aperture_string(true);
                if (aperture == null)
                    aperture = "";
                
                iso = metadata.get_iso_string();
                if (iso == null)
                    iso = "";

                dimensions = (metadata.get_pixel_dimensions() != null) ?
                    metadata.get_orientation().rotate_dimensions(metadata.get_pixel_dimensions()) :
                    Dimensions(0, 0);
            }
            
            if (source is PhotoSource)
                dimensions = ((PhotoSource) source).get_dimensions();
            
            if (source is Photo && ((Photo) source).get_master_file_format() == PhotoFileFormat.RAW) {
                Photo photo = source as Photo;
                raw_developer = photo.get_raw_developer().get_label();
                raw_assoc = photo.is_raw_developer_available(RawDeveloper.CAMERA) ? _("RAW+JPEG") : "";
            }
        } else if (source is EventSource) {
            EventSource event_source = (EventSource) source;

            start_time = event_source.get_start_time();
            end_time = event_source.get_end_time();

            int event_photo_count;
            int event_video_count;
            MediaSourceCollection.count_media(event_source.get_media(), out event_photo_count,
                out event_video_count);
            
            photo_count = event_photo_count;
            video_count = event_video_count;
        } else if (source is VideoSource || source is VideoImportSource) {
            if (source is VideoSource) {
                Video video = (Video) source;
                clip_duration = video.get_clip_duration();

                if (video.get_is_interpretable())
                    dimensions = video.get_frame_dimensions();

                start_time = video.get_exposure_time();
            } else {
                start_time = ((VideoImportSource) source).get_exposure_time();
            }
            end_time = start_time;
        }
    }

    protected override void get_multiple_properties(Gee.Iterable<DataView>? iter) {
        base.get_multiple_properties(iter);

        photo_count = 0;
        video_count = 0;
        foreach (DataView view in iter) {
            DataSource source = view.get_source();
            
            if (source is PhotoSource || source is PhotoImportSource) {                  
                time_t exposure_time = (source is PhotoSource) ?
                    ((PhotoSource) source).get_exposure_time() :
                    ((PhotoImportSource) source).get_exposure_time();

                if (exposure_time != 0) {
                    if (start_time == 0 || exposure_time < start_time)
                        start_time = exposure_time;

                    if (end_time == 0 || exposure_time > end_time)
                        end_time = exposure_time;
                }
                
                photo_count++;
            } else if (source is EventSource) {
                EventSource event_source = (EventSource) source;
          
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

                int event_photo_count;
                int event_video_count;
                MediaSourceCollection.count_media(event_source.get_media(), out event_photo_count,
                    out event_video_count);

                photo_count += event_photo_count;
                video_count += event_video_count;
                event_count++;
            } else if (source is VideoSource || source is VideoImportSource) {
                time_t exposure_time = (source is VideoSource) ?
                    ((VideoSource) source).get_exposure_time() :
                    ((VideoImportSource) source).get_exposure_time();

                if (exposure_time != 0) {
                    if (start_time == 0 || exposure_time < start_time)
                        start_time = exposure_time;

                    if (end_time == 0 || exposure_time > end_time)
                        end_time = exposure_time;
                }

                video_count++;
            }
        }
    }

    protected override void get_properties(Page current_page) {
        base.get_properties(current_page);

        if (end_time == 0)
            end_time = start_time;
        if (start_time == 0)
            start_time = end_time;
    }

    protected override void internal_update_properties(Page page) {
        base.internal_update_properties(page);

        // display the title if a Tag page
        if (title == "" && page is TagPage)
            title = ((TagPage) page).get_tag().get_user_visible_name();
            
        if (title != "")
            add_line(_("Title:"), guarded_markup_escape_text(title));

        if (photo_count >= 0 || video_count >= 0) {
            string label = _("Items:");
  
            if (event_count >= 0) {
                string event_num_string = (ngettext("%d Event", "%d Events", event_count)).printf(
                    event_count);

                add_line(label, event_num_string);
                label = "";
            }

            string photo_num_string = (ngettext("%d Photo", "%d Photos", photo_count)).printf(
                photo_count);
            string video_num_string = (ngettext("%d Video", "%d Videos", video_count)).printf(
                video_count);

            if (photo_count == 0 && video_count > 0) {
                add_line(label, video_num_string);
                return;
            }
            
            add_line(label, photo_num_string);
            
            if (video_count > 0)
                add_line("", video_num_string);
        }

        if (start_time != 0) {
            string start_date = get_prettyprint_date(Time.local(start_time));
            string start_time = get_prettyprint_time(Time.local(start_time));
            string end_date = get_prettyprint_date(Time.local(end_time));
            string end_time = get_prettyprint_time(Time.local(end_time));

            if (start_date == end_date) {
                // display only one date if start and end are the same
                add_line(_("Date:"), start_date);

                if (start_time == end_time) {
                    // display only one time if start and end are the same
                    add_line(_("Time:"), start_time);
                } else {
                    // display time range
                    add_line(_("From:"), start_time);
                    add_line(_("To:"), end_time);
                }
            } else {
                // display date range
                add_line(_("From:"), start_date);
                add_line(_("To:"), end_date);
            }
        }

        if (dimensions.has_area()) {
            string label = _("Size:");

            if (dimensions.has_area()) {
                add_line(label, "%d &#215; %d".printf(dimensions.width, dimensions.height));
                label = "";
            }
        }
        
        if (clip_duration > 0.0) {
            add_line(_("Duration:"), _("%.1f seconds").printf(clip_duration));
        }
        
        if (raw_developer != "") {
            add_line(_("Developer:"), raw_developer);
        }
        
        // RAW+JPEG flag.
        if (raw_assoc != "")
            add_line("", raw_assoc);

        if (exposure != "" || aperture != "" || iso != "") {
            string line = null;
            
            // attempt to put exposure and aperture on the same line
            if (exposure != "")
                line = exposure;
            
            if (aperture != "") {
                if (line != null)
                    line += ", " + aperture;
                else
                    line = aperture;
            }
            
            // if not both available but ISO is, add it to the first line
            if ((exposure == "" || aperture == "") && iso != "") {
                if (line != null)
                    line += ", " + "ISO " + iso;
                else
                    line = "ISO " + iso;
                
                add_line(_("Exposure:"), line);
            } else {
                // fit both on the top line, emit and move on
                if (line != null)
                    add_line(_("Exposure:"), line);
                
                // emit ISO on a second unadorned line
                if (iso != "") {
                    if (line != null)
                        add_line("","ISO " + iso);
                    else
                        add_line(_("Exposure:"), "ISO " + iso);
                }
            }
        }
    }
}

private class ExtendedPropertiesWindow : Gtk.Dialog {
    private ExtendedProperties properties = null;

    private class ExtendedProperties : Properties {
        private const string NO_VALUE = "";
        // Photo stuff
        private string file_path;
        private uint64 filesize;
        private Dimensions? original_dim;
        private string camera_make;
        private string camera_model;
        private string flash;
        private string focal_length;
        private double gps_lat;
        private string gps_lat_ref;
        private double gps_long;
        private string gps_long_ref;
        private double gps_alt;
        private string artist;
        private string copyright;
        private string software;
        private string exposure_bias;
        private string exposure_date;
        private string exposure_time;
        private bool is_raw;
        private string? development_path;
        
        // Event stuff
        // nothing here which is not already shown in the BasicProperties but
        // comments, which are common, see below
        
        // common stuff
        private string comment;
            
        protected override void clear_properties() {
            base.clear_properties();

            file_path = "";
            development_path = "";
            is_raw = false;
            filesize = 0;
            original_dim = Dimensions(0, 0);
            camera_make = "";
            camera_model = "";
            flash = "";
            focal_length = "";
            gps_lat = -1;
            gps_lat_ref = "";
            gps_long = -1;
            gps_long_ref = "";
            artist = "";
            copyright = "";
            software = "";
            exposure_bias = "";
            exposure_date = "";
            exposure_time = "";
            comment = "";
        }

        protected override void get_single_properties(DataView view) {
            base.get_single_properties(view);
            
            DataSource source = view.get_source();
            if (source == null)
                return;
            
            if (source is MediaSource) {
                MediaSource media = (MediaSource) source;
                file_path = media.get_master_file().get_path();
                development_path = media.get_file().get_path();
                filesize = media.get_master_filesize();

                // as of right now, all extended properties other than filesize, filepath & comment aren't
                // applicable to non-photo media types, so if the current media source isn't a photo,
                // just do a short-circuit return
                Photo photo = media as Photo;
                if (photo == null)
                    return;
            
                PhotoMetadata? metadata;

                try {
                    // For some raw files, the developments may not contain metadata (please
                    // see the comment about cameras generating 'crazy' exif segments in
                    // Photo.develop_photo() for why), and so we'll want to display what was
                    // in the original raw file instead.
                    metadata = photo.get_master_metadata();
                } catch (Error e) {
                    metadata = photo.get_metadata();
                }
                
                if (metadata == null)
                    return;
                
                // Fix up any timestamp weirdness.
                //
                // If the exposure date wasn't properly set (the most likely cause of this
                // is a raw with a metadataless development), use the one from the photo
                // row.
                if (metadata.get_exposure_date_time() == null)
                    metadata.set_exposure_date_time(new MetadataDateTime(photo.get_timestamp()));
                
                is_raw = (photo.get_master_file_format() == PhotoFileFormat.RAW);
                original_dim = metadata.get_pixel_dimensions();
                camera_make = metadata.get_camera_make();
                camera_model = metadata.get_camera_model();
                flash = metadata.get_flash_string();
                focal_length = metadata.get_focal_length_string();
                metadata.get_gps(out gps_long, out gps_long_ref, out gps_lat, out gps_lat_ref, out gps_alt);
                artist = metadata.get_artist();
                copyright = metadata.get_copyright();
                software = metadata.get_software();
                exposure_bias = metadata.get_exposure_bias();
                time_t exposure_time_obj = metadata.get_exposure_date_time().get_timestamp();
                exposure_date = get_prettyprint_date(Time.local(exposure_time_obj));
                exposure_time = get_prettyprint_time_with_seconds(Time.local(exposure_time_obj));
                comment = media.get_comment();
            } else if (source is EventSource) {
                Event event = (Event) source;
                comment = event.get_comment();
            }
        }
        
        public override void internal_update_properties(Page page) {
            base.internal_update_properties(page);

            if (page is EventsDirectoryPage) {
                // nothing special to be done for now for Events
            } else {
                add_line(_("Location:"), (file_path != "" && file_path != null) ? 
                    file_path.replace("&", "&amp;") : NO_VALUE);

                add_line(_("File size:"), (filesize > 0) ? 
                    format_size((int64) filesize) : NO_VALUE);

                if (is_raw)
                    add_line(_("Current Development:"), development_path);

                add_line(_("Original dimensions:"), (original_dim != null && original_dim.has_area()) ?
                    "%d &#215; %d".printf(original_dim.width, original_dim.height) : NO_VALUE);

                add_line(_("Camera make:"), (camera_make != "" && camera_make != null) ?
                    camera_make : NO_VALUE);

                add_line(_("Camera model:"), (camera_model != "" && camera_model != null) ?
                    camera_model : NO_VALUE);

                add_line(_("Flash:"), (flash != "" && flash != null) ? flash : NO_VALUE);

                add_line(_("Focal length:"), (focal_length != "" && focal_length != null) ?
                    focal_length : NO_VALUE);
                
                add_line(_("Exposure date:"), (exposure_date != "" && exposure_date != null) ?
                    exposure_date : NO_VALUE);
                
                add_line(_("Exposure time:"), (exposure_time != "" && exposure_time != null) ?
                   exposure_time : NO_VALUE);
                
                add_line(_("Exposure bias:"), (exposure_bias != "" && exposure_bias != null) ? exposure_bias : NO_VALUE);
            
                add_line(_("GPS latitude:"), (gps_lat != -1 && gps_lat_ref != "" && 
                    gps_lat_ref != null) ? "%f °%s".printf(gps_lat, gps_lat_ref) : NO_VALUE);
            
                add_line(_("GPS longitude:"), (gps_long != -1 && gps_long_ref != "" && 
                    gps_long_ref != null) ? "%f °%s".printf(gps_long, gps_long_ref) : NO_VALUE);

                add_line(_("Artist:"), (artist != "" && artist != null) ? artist : NO_VALUE);

                add_line(_("Copyright:"), (copyright != "" && copyright != null) ? copyright : NO_VALUE);
    
                add_line(_("Software:"), (software != "" && software != null) ? software : NO_VALUE);
            }

            bool has_comment = (comment != "" && comment != null);
            add_line(_("Comment:"), has_comment ? comment : NO_VALUE, has_comment);
        }
    }

    public ExtendedPropertiesWindow(Gtk.Window owner) {
        bool use_header;
        Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header);
        Object(use_header_bar: use_header ? 1 : 0);
        
        add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.KEY_PRESS_MASK);
        focus_on_map = true;
        set_accept_focus(true);
        set_can_focus(true);
        set_title(_("Extended Information"));
        set_position(Gtk.WindowPosition.CENTER);
        set_transient_for(owner);
        set_type_hint(Gdk.WindowTypeHint.DIALOG);

        delete_event.connect(hide_on_delete);

        properties = new ExtendedProperties();
        Gtk.Alignment alignment = new Gtk.Alignment(0.5f,0.5f,1,1);
        alignment.add(properties);
        alignment.set_border_width(3);
        ((Gtk.Box) get_content_area()).add(alignment);
    }

    public override bool button_press_event(Gdk.EventButton event) {
        // LMB only
        if (event.button != 1)
            return (base.button_press_event != null) ? base.button_press_event(event) : true;

        begin_move_drag((int) event.button, (int) event.x_root, (int) event.y_root, event.time);

        return true;
    }

    public override bool key_press_event(Gdk.EventKey event) {
        // hide properties
        if (Gdk.keyval_name(event.keyval) == "Escape") {
            hide();
            return true;
        }
        // or send through to AppWindow
        return AppWindow.get_instance().key_press_event(event);
    }

    public void update_properties(Page page) {
        properties.update_properties(page);
    }
    
    public override void show_all() {
        base.show_all();
        properties.unselect_text();
        grab_focus();
    }
}
