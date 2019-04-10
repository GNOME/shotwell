/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

class SlideshowPage : SinglePhotoPage {
    private const int READAHEAD_COUNT = 5;
    private const int CHECK_ADVANCE_MSEC = 250;
    
    private SourceCollection sources;
    private ViewCollection controller;
    private Photo current;
    private Gtk.ToolButton play_pause_button;
    private Gtk.ToolButton settings_button;
    private PixbufCache cache = null;
    private Timer timer = new Timer();
    private bool playing = true;
    private bool exiting = false;
    private string[] transitions;

    private Screensaver screensaver;

    public signal void hide_toolbar();
    
    [GtkTemplate (ui = "/org/gnome/Shotwell/ui/slideshow_settings.ui")]
    private class SettingsDialog : Gtk.Dialog {
        [GtkChild]
        Gtk.Adjustment delay_adjustment;
        [GtkChild]
        Gtk.SpinButton delay_entry;
        [GtkChild]
        Gtk.ComboBoxText transition_effect_selector;
        [GtkChild]
        Gtk.Scale transition_effect_hscale;
        [GtkChild]
        Gtk.SpinButton transition_effect_entry;
        [GtkChild]
        Gtk.Adjustment transition_effect_adjustment;
        [GtkChild]
        Gtk.CheckButton show_title_button;
        
        public SettingsDialog() {
            Object (use_header_bar: Resources.use_header_bar());

            double delay = Config.Facade.get_instance().get_slideshow_delay();

            set_transient_for(AppWindow.get_fullscreen());

            delay_adjustment.value = delay;

            // get last effect id
            string effect_id = Config.Facade.get_instance().get_slideshow_transition_effect_id();

            // null effect first, always, and set active in case no other one is found
            string null_display_name = TransitionEffectsManager.get_instance().get_effect_name(
                TransitionEffectsManager.NULL_EFFECT_ID);
            transition_effect_selector.append_text(null_display_name);
            transition_effect_selector.set_active(0);
            
            int i = 1;
            foreach (string display_name in 
                TransitionEffectsManager.get_instance().get_effect_names(utf8_ci_compare)) {
                if (display_name == null_display_name)
                    continue;
                
                transition_effect_selector.append_text(display_name);
                if (effect_id == TransitionEffectsManager.get_instance().get_id_for_effect_name(display_name))
                    transition_effect_selector.set_active(i);
                
                ++i;
            }
            transition_effect_selector.changed.connect(on_transition_changed);
            
            double transition_delay = Config.Facade.get_instance().get_slideshow_transition_delay();
            transition_effect_adjustment.value = transition_delay;
            
            bool show_title = Config.Facade.get_instance().get_slideshow_show_title();
            show_title_button.active = show_title;
            
            on_transition_changed();
        }
        
        private void on_transition_changed() {
            string selected = transition_effect_selector.get_active_text();
            bool sensitive = selected != null 
               && selected != TransitionEffectsManager.NULL_EFFECT_ID;
           
            transition_effect_hscale.sensitive = sensitive;
            transition_effect_entry.sensitive = sensitive;
        }

        public double get_delay() {
            return delay_entry.get_value();
        }
        
        public double get_transition_delay() {
            return transition_effect_entry.get_value();
        }
        
        public string get_transition_effect_id() {
            string? active = transition_effect_selector.get_active_text();
            if (active == null)
                return TransitionEffectsManager.NULL_EFFECT_ID;
            
            string? id = TransitionEffectsManager.get_instance().get_id_for_effect_name(active);
            
            return (id != null) ? id : TransitionEffectsManager.NULL_EFFECT_ID;
        }
        
        public bool get_show_title() {
            return show_title_button.active;
        }
    }

    public SlideshowPage(SourceCollection sources, ViewCollection controller, Photo start) {
        base(_("Slideshow"), true);
        
        this.sources = sources;
        this.controller = controller;
        
        Gee.Collection<string> pluggables = TransitionEffectsManager.get_instance().get_effect_ids();
        Gee.ArrayList<string> a = new Gee.ArrayList<string>();
        a.add_all(pluggables);
        a.remove(NullTransitionDescriptor.EFFECT_ID);
        a.remove(RandomEffectDescriptor.EFFECT_ID);
        transitions = a.to_array();
        current = start;
        
        update_transition_effect();
        
        // Set up toolbar
        Gtk.Toolbar toolbar = get_toolbar();
        
        // add toolbar buttons
        Gtk.ToolButton previous_button = new Gtk.ToolButton(null, _("Back"));
        previous_button.set_icon_name("go-previous-symbolic");
        previous_button.set_tooltip_text(_("Go to the previous photo"));
        previous_button.clicked.connect(on_previous_photo);
        
        toolbar.insert(previous_button, -1);
        
        play_pause_button = new Gtk.ToolButton(null, _("Pause"));
        play_pause_button.set_icon_name("media-playback-pause-symbolic");
        play_pause_button.set_tooltip_text(_("Pause the slideshow"));
        play_pause_button.clicked.connect(on_play_pause);
        
        toolbar.insert(play_pause_button, -1);
        
        Gtk.ToolButton next_button = new Gtk.ToolButton(null, _("Next"));
        next_button.set_icon_name("go-next-symbolic");
        next_button.set_tooltip_text(_("Go to the next photo"));
        next_button.clicked.connect(on_next_photo);
        
        toolbar.insert(next_button, -1);

        settings_button = new Gtk.ToolButton(null, null);
        settings_button.set_icon_name("preferences-system-symbolic");
        settings_button.set_label(_("Settings"));
        settings_button.set_tooltip_text(_("Change slideshow settings"));
        settings_button.clicked.connect(on_change_settings);
        settings_button.is_important = true;
        
        toolbar.insert(settings_button, -1);

        screensaver = new Screensaver();
    }
    
    public override void switched_to() {
        base.switched_to();
        
        // create a cache for the size of this display
        cache = new PixbufCache(sources, PixbufCache.PhotoType.BASELINE, get_canvas_scaling(),
            READAHEAD_COUNT);
        
        Gdk.Pixbuf pixbuf;
        if (get_next_photo(current, Direction.FORWARD, out current, out pixbuf))
            set_pixbuf(pixbuf, current.get_dimensions(), Direction.FORWARD);
        
        // start the auto-advance timer
        Timeout.add(CHECK_ADVANCE_MSEC, auto_advance);
        timer.start();
        
        screensaver.inhibit("Playing slideshow");
    }
    
    public override void switching_from() {
        base.switching_from();

        screensaver.uninhibit();
        exiting = true;
    }
    
    private bool get_next_photo(Photo start, Direction direction, out Photo next,
        out Gdk.Pixbuf next_pixbuf) {
        next = start;
        
        for (;;) {
            try {
                // Fails if a photo source file is missing.
                next_pixbuf = cache.fetch(next);
            } catch (Error err) {
                warning("Unable to fetch pixbuf for %s: %s", next.to_string(), err.message);
                
                // Look for the next good photo
                DataView view = controller.get_view_for_source(next);
                view = (direction == Direction.FORWARD) 
                    ? controller.get_next(view) 
                    : controller.get_previous(view);
                next = (Photo) view.get_source();
                
                // An entire slideshow set might be missing, so check for a loop.
                if ((next == start && next != current) || next == current) {
                    AppWindow.error_message(_("All photo source files are missing."), get_container());
                    AppWindow.get_instance().end_fullscreen();
                    
                    next = null;
                    next_pixbuf = null;
                    
                    return false;
                }
                
                continue;
            }
            
            // prefetch this photo's extended neighbors: the next photo highest priority, the prior
            // one normal, and the extended neighbors lowest, to recognize immediate needs
            DataSource forward, back;
            controller.get_immediate_neighbors(next, out forward, out back, Photo.TYPENAME);
            cache.prefetch((Photo) forward, BackgroundJob.JobPriority.HIGHEST);
            cache.prefetch((Photo) back, BackgroundJob.JobPriority.NORMAL);
            
            Gee.Set<DataSource> neighbors = controller.get_extended_neighbors(next, Photo.TYPENAME);
            neighbors.remove(forward);
            neighbors.remove(back);
            
            cache.prefetch_many((Gee.Collection<Photo>) neighbors, BackgroundJob.JobPriority.LOWEST);
            
            return true;
        }
    }

    private void on_play_pause() {
        if (playing) {
            play_pause_button.set_icon_name("media-playback-start-symbolic");
            play_pause_button.set_label(_("Play"));
            play_pause_button.set_tooltip_text(_("Continue the slideshow"));
        } else {
            play_pause_button.set_icon_name("media-playback-pause-symbolic");
            play_pause_button.set_label(_("Pause"));
            play_pause_button.set_tooltip_text(_("Pause the slideshow"));
        }
        
        playing = !playing;
        
        // reset the timer
        timer.start();
    }
    
    protected override void on_previous_photo() {
        DataView view = controller.get_view_for_source(current);

        Photo? prev_photo = null;
        DataView? start_view = controller.get_previous(view);
        DataView? prev_view = start_view;
        
        while (prev_view != null) {
            if (prev_view.get_source() is Photo) {
                prev_photo = (Photo) prev_view.get_source();
                break;
            }

            prev_view = controller.get_previous(prev_view);

            if (prev_view == start_view) {
                warning("on_previous( ): can't advance to previous photo: collection has only videos");
                return;
            }
        }

        advance(prev_photo, Direction.BACKWARD);
    }
    
    protected override void on_next_photo() {
        DataView view = controller.get_view_for_source(current);

        Photo? next_photo = null;
        DataView? start_view = controller.get_next(view);
        DataView? next_view = start_view;

        while (next_view != null) {
            if (next_view.get_source() is Photo) {
                next_photo = (Photo) next_view.get_source();
                break;
            }

            next_view = controller.get_next(next_view);
            
            if (next_view == start_view) {
                warning("on_next( ): can't advance to next photo: collection has only videos");
                return;
            }
        }

        if (Config.Facade.get_instance().get_slideshow_transition_effect_id() ==
            RandomEffectDescriptor.EFFECT_ID) {
            random_transition_effect();
        }
        
        advance(next_photo, Direction.FORWARD);
    }
    
    private void advance(Photo photo, Direction direction) {
        current = photo;
        
        // set pixbuf
        Gdk.Pixbuf next_pixbuf;
        if (get_next_photo(current, direction, out current, out next_pixbuf))
            set_pixbuf(next_pixbuf, current.get_dimensions(), direction);
        
        // reset the advance timer
        timer.start();
    }

    private bool auto_advance() {
        if (exiting)
            return false;
        
        if (!playing)
            return true;
        
        if (timer.elapsed() < Config.Facade.get_instance().get_slideshow_delay())
            return true;
        
        on_next_photo();
        
        return true;
    }
    
    public override bool key_press_event(Gdk.EventKey event) {
        bool handled = true;
        switch (Gdk.keyval_name(event.keyval)) {
            // Block activating the toolbar on key down
            // FIXME: Why is SinglePhotoPage not a PhotoPage which already does this?
            case "Down":
            case "KP_Down":
                ;
            break;
            case "space":
                on_play_pause();
            break;
            
            default:
                handled = false;
            break;
        }
        
        if (handled)
            return true;
        
        return (base.key_press_event != null) ? base.key_press_event(event) : true;
    }

    private void on_change_settings() {
        SettingsDialog settings_dialog = new SettingsDialog();
        settings_dialog.show_all();
        
        bool slideshow_playing = playing;
        playing = false;
        hide_toolbar();
        suspend_cursor_hiding();
        
        if (settings_dialog.run() == Gtk.ResponseType.OK) {
            // sync with the config setting so it will persist
            Config.Facade.get_instance().set_slideshow_delay(settings_dialog.get_delay());
            
            Config.Facade.get_instance().set_slideshow_transition_delay(settings_dialog.get_transition_delay());
            Config.Facade.get_instance().set_slideshow_transition_effect_id(settings_dialog.get_transition_effect_id());
            Config.Facade.get_instance().set_slideshow_show_title(settings_dialog.get_show_title());
            
            update_transition_effect();
        }
        
        settings_dialog.destroy();
        restore_cursor_hiding();
        playing = slideshow_playing;
        timer.start();
    }
    
    private void update_transition_effect() {
        string effect_id = Config.Facade.get_instance().get_slideshow_transition_effect_id();
        double effect_delay = Config.Facade.get_instance().get_slideshow_transition_delay();
        
        set_transition(effect_id, (int) (effect_delay * 1000.0));
    }
    
    private void random_transition_effect() {
        double effect_delay = Config.Facade.get_instance().get_slideshow_transition_delay();
        string effect_id = TransitionEffectsManager.NULL_EFFECT_ID;
        if (0 < transitions.length) {
            int random = Random.int_range(0, transitions.length);
            effect_id = transitions[random];
        }
        set_transition(effect_id, (int) (effect_delay * 1000.0));
    }
    
    // Paint the title of the photo
    private void paint_title(Cairo.Context ctx, Dimensions ctx_dim) {
        string? title = current.get_title();
        
        // If the photo doesn't have a title, don't paint anything
        if (title == null || title == "")
            return;
        
        Pango.Layout layout = create_pango_layout(title);
        Pango.AttrList list = new Pango.AttrList();
        Pango.Attribute size = Pango.attr_scale_new(3);
        list.insert(size.copy());
        layout.set_attributes(list);
        layout.set_width((int) ((ctx_dim.width * 0.9) * Pango.SCALE));
        
        // Find the right position
        int title_width, title_height;
        layout.get_pixel_size(out title_width, out title_height);
        double x = ctx_dim.width * 0.2;
        double y = ctx_dim.height * 0.90;
        
        // Move the title up if it is too high
        if (y + title_height >= ctx_dim.height * 0.95)
            y = ctx_dim.height * 0.95 - title_height;
        // Move to the left if the title is too long
        if (x + title_width >= ctx_dim.width * 0.95)
            x = ctx_dim.width / 2 - title_width / 2;
        
        set_source_color_from_string(ctx, "#fff");
        ctx.move_to(x, y);
        Pango.cairo_show_layout(ctx, layout);
        Pango.cairo_layout_path(ctx, layout);
        ctx.set_line_width(1.5);
        set_source_color_from_string(ctx, "#000");
        ctx.stroke();
    }
    
    public override void paint(Cairo.Context ctx, Dimensions ctx_dim) {
       base.paint(ctx, ctx_dim);
        
        if (Config.Facade.get_instance().get_slideshow_show_title() && !is_transition_in_progress())
            paint_title(ctx, ctx_dim);
    }
}

