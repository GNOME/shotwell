/* Copyright 2009-2011 Yorba Foundation
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

    private Screensaver screensaver;

    public signal void hide_toolbar();
    
    private class SettingsDialog : Gtk.Dialog {
        Gtk.SpinButton delay_entry;
        Gtk.HScale hscale;
        Gtk.ComboBox transition_effect_selector;
        Gtk.HScale transition_effect_hscale;
        Gtk.SpinButton transition_effect_entry;
        Gtk.Adjustment transition_effect_adjustment;
        
        public SettingsDialog() {
            double delay = Config.Facade.get_instance().get_slideshow_delay();
            
            set_modal(true);
            set_transient_for(AppWindow.get_fullscreen());

            add_buttons(Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL, 
                Gtk.Stock.OK, Gtk.ResponseType.OK);
            set_title(_("Settings"));

            Gtk.Label delay_label = new Gtk.Label.with_mnemonic(_("_Delay:"));
            delay_label.xalign = (float) 1.0;
            Gtk.Label units_label = new Gtk.Label(_("seconds"));
            units_label.xalign = (float) 0.0;
            Gtk.Label units_label1 = new Gtk.Label(_("seconds"));
            units_label1.xalign = (float) 0.0;

            Gtk.Adjustment adjustment = new Gtk.Adjustment(delay, Config.Facade.SLIDESHOW_DELAY_MIN, Config.Facade.SLIDESHOW_DELAY_MAX, 0.1, 1, 0);
            hscale = new Gtk.HScale(adjustment);
            hscale.set_draw_value(false);
            hscale.set_size_request(150,-1);
            delay_label.set_mnemonic_widget(hscale);
            
            delay_entry = new Gtk.SpinButton(adjustment, 0.1, 1);
            delay_entry.set_value(delay);
            delay_entry.set_numeric(true);
            delay_entry.set_activates_default(true);

            transition_effect_selector = new Gtk.ComboBox.text();
            Gtk.Label transition_effect_selector_label = new Gtk.Label.with_mnemonic(
                _("_Transition effect:"));
            transition_effect_selector_label.xalign = (float) 1.0;
            transition_effect_selector_label.set_mnemonic_widget(transition_effect_selector);
            
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
            
            Gtk.Label transition_delay_label = new Gtk.Label.with_mnemonic(_("Transition d_elay:"));
            transition_delay_label.xalign = (float) 1.0;
            
            double transition_delay = Config.Facade.get_instance().get_slideshow_transition_delay();
            transition_effect_adjustment = new Gtk.Adjustment(transition_delay,
                Config.Facade.SLIDESHOW_TRANSITION_DELAY_MIN, Config.Facade.SLIDESHOW_TRANSITION_DELAY_MAX,
                0.1, 1, 0);
            transition_effect_hscale = new Gtk.HScale(transition_effect_adjustment);
            transition_effect_hscale.set_draw_value(false);
            transition_effect_hscale.set_size_request(150, -1);
            
            transition_effect_entry = new Gtk.SpinButton(transition_effect_adjustment, 0.1, 1);
            transition_effect_entry.set_value(transition_delay);
            transition_effect_entry.set_numeric(true);
            transition_effect_entry.set_activates_default(true);
            transition_delay_label.set_mnemonic_widget(transition_effect_hscale);
            
            set_default_response(Gtk.ResponseType.OK);
            
            Gtk.Table tbl = new Gtk.Table(3, 4, false);
            tbl.attach(delay_label, 0, 1, 0, 1, 
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                3, 0);
            tbl.attach(hscale, 1, 2, 0, 1, 
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                3, 0);
            tbl.attach(delay_entry, 2, 3, 0, 1, 
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                3, 0);
            tbl.attach(units_label, 3, 4, 0, 1, 
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                3, 0);
                
            tbl.attach(transition_effect_selector_label, 0, 1, 1, 2, 
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                3, 6);
            tbl.attach(transition_effect_selector, 1, 2, 1, 2, 
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                3, 6);
                
            tbl.attach(transition_delay_label, 0, 1, 2, 3, 
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                3, 0);
            tbl.attach(transition_effect_hscale, 1, 2, 2, 3, 
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                3, 0);
            tbl.attach(transition_effect_entry, 2, 3, 2, 3, 
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                3, 0);
            tbl.attach(units_label1, 3, 4, 2, 3, 
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                3, 0);
            
            vbox.pack_start(tbl, true, false, 6);
            
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
    }

    public SlideshowPage(SourceCollection sources, ViewCollection controller, Photo start) {
        base(_("Slideshow"), true);
        
        this.sources = sources;
        this.controller = controller;
        current = start;
        
        update_transition_effect();
        
        // Set up toolbar
        Gtk.Toolbar toolbar = get_toolbar();
        
        // add toolbar buttons
        Gtk.ToolButton previous_button = new Gtk.ToolButton.from_stock(Gtk.Stock.GO_BACK);
        previous_button.set_label(_("Back"));
        previous_button.set_tooltip_text(_("Go to the previous photo"));
        previous_button.clicked.connect(on_previous);
        
        toolbar.insert(previous_button, -1);
        
        play_pause_button = new Gtk.ToolButton.from_stock(Gtk.Stock.MEDIA_PAUSE);
        play_pause_button.set_label(_("Pause"));
        play_pause_button.set_tooltip_text(_("Pause the slideshow"));
        play_pause_button.clicked.connect(on_play_pause);
        
        toolbar.insert(play_pause_button, -1);
        
        Gtk.ToolButton next_button = new Gtk.ToolButton.from_stock(Gtk.Stock.GO_FORWARD);
        next_button.set_label(_("Next"));
        next_button.set_tooltip_text(_("Go to the next photo"));
        next_button.clicked.connect(on_next);
        
        toolbar.insert(next_button, -1);

        settings_button = new Gtk.ToolButton.from_stock(Gtk.Stock.PREFERENCES);
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
            play_pause_button.set_stock_id(Gtk.Stock.MEDIA_PLAY);
            play_pause_button.set_label(_("Play"));
            play_pause_button.set_tooltip_text(_("Continue the slideshow"));
        } else {
            play_pause_button.set_stock_id(Gtk.Stock.MEDIA_PAUSE);
            play_pause_button.set_label(_("Pause"));
            play_pause_button.set_tooltip_text(_("Pause the slideshow"));
        }
        
        playing = !playing;
        
        // reset the timer
        timer.start();
    }
    
    private void on_previous() {
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
    
    private void on_next() {
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
        
        on_next();
        
        return true;
    }
    
    public override bool key_press_event(Gdk.EventKey event) {
        bool handled = true;
        switch (Gdk.keyval_name(event.keyval)) {
            case "space":
                on_play_pause();
            break;
            
            case "Left":
            case "KP_Left":
                on_previous();
            break;
            
            case "Right":
            case "KP_Right":
                on_next();
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
        
        if (settings_dialog.run() == Gtk.ResponseType.OK) {
            // sync with the config setting so it will persist
            Config.Facade.get_instance().set_slideshow_delay(settings_dialog.get_delay());
            
            Config.Facade.get_instance().set_slideshow_transition_delay(settings_dialog.get_transition_delay());
            Config.Facade.get_instance().set_slideshow_transition_effect_id(settings_dialog.get_transition_effect_id());
            
            update_transition_effect();
        }
        
        settings_dialog.destroy();
        playing = slideshow_playing;
        timer.start();
    }
    
    private void update_transition_effect() {
        string effect_id = Config.Facade.get_instance().get_slideshow_transition_effect_id();
        double effect_delay = Config.Facade.get_instance().get_slideshow_transition_delay();
        
        set_transition(effect_id, (int) (effect_delay * 1000.0));
    }
}

