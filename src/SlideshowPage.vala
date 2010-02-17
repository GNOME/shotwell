/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

class SlideshowPage : SinglePhotoPage {
    private const int CHECK_ADVANCE_MSEC = 250;
    
    private ViewCollection controller;
    private Thumbnail current;
    private Gdk.Pixbuf next_pixbuf = null;
    private Thumbnail next_thumbnail = null;
    private Gtk.ToolButton play_pause_button;
    private Gtk.ToolButton settings_button;
    private Timer timer = new Timer();
    private bool playing = true;
    private bool exiting = false;
#if !WINDOWS
    private Screensaver screensaver;
#endif

    public signal void hide_toolbar();
    
    private class SettingsDialog : Gtk.Dialog {
        Gtk.Entry delay_entry;
        double delay;
        Gtk.HScale hscale;

        private bool update_entry(Gtk.ScrollType scroll, double new_value) {
            new_value = new_value.clamp(Config.SLIDESHOW_DELAY_MIN, Config.SLIDESHOW_DELAY_MAX);

            delay_entry.set_text("%.1f".printf(new_value));
            return false;
        }

        private void check_text() { //rename this function
            // parse through text, set delay
            string delay_text = delay_entry.get_text();
            delay_text.canon("0123456789.",'?');
            delay_text = delay_text.replace("?","");
         
            delay = delay_text.to_double();
            delay_entry.set_text(delay_text);

            delay = delay.clamp(Config.SLIDESHOW_DELAY_MIN, Config.SLIDESHOW_DELAY_MAX);
            hscale.set_value(delay);
        }        

        public SettingsDialog() {
            delay = Config.get_instance().get_slideshow_delay();

            set_modal(true);
            set_transient_for(AppWindow.get_fullscreen());

            add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, 
                        Gtk.STOCK_OK, Gtk.ResponseType.OK);
            set_title(_("Settings"));

            Gtk.Label delay_label = new Gtk.Label(_("Delay:"));
            Gtk.Label units_label = new Gtk.Label(_("seconds"));
            delay_entry = new Gtk.Entry();
            delay_entry.set_max_length(5);
            delay_entry.set_text("%.1f".printf(delay));
            delay_entry.set_width_chars(4);
            delay_entry.set_activates_default(true);
            delay_entry.changed += check_text;

            Gtk.Adjustment adjustment = new Gtk.Adjustment(delay, Config.SLIDESHOW_DELAY_MIN, Config.SLIDESHOW_DELAY_MAX + 1, 0.1, 1, 1);
            hscale = new Gtk.HScale(adjustment);
            hscale.set_draw_value(false);
            hscale.set_size_request(150,-1);
            hscale.change_value += update_entry;

            Gtk.HBox query = new Gtk.HBox(false, 0);
            query.pack_start(delay_label, false, false, 3);
            query.pack_start(hscale, true, true, 3);
            query.pack_start(delay_entry, false, false, 3);
            query.pack_start(units_label, false, false, 3);

            set_default_response(Gtk.ResponseType.OK);

            vbox.pack_start(query, true, false, 6);
        }

        public double get_delay() {
            return delay;
        }
    }

    public SlideshowPage(ViewCollection controller, Thumbnail start) {
        base(_("Slideshow"), true);
        
        this.controller = controller;
        current = start;
        
        // Set up toolbar
        Gtk.Toolbar toolbar = get_toolbar();
        
        // add toolbar buttons
        Gtk.ToolButton previous_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_BACK);
        previous_button.set_label(_("Back"));
        previous_button.set_tooltip_text(_("Go to the previous photo"));
        previous_button.clicked += on_previous_manual;
        
        toolbar.insert(previous_button, -1);
        
        play_pause_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_MEDIA_PAUSE);
        play_pause_button.set_label(_("Pause"));
        play_pause_button.set_tooltip_text(_("Pause the slideshow"));
        play_pause_button.clicked += on_play_pause;
        
        toolbar.insert(play_pause_button, -1);
        
        Gtk.ToolButton next_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_FORWARD);
        next_button.set_label(_("Next"));
        next_button.set_tooltip_text(_("Go to the next photo"));
        next_button.clicked += on_next_manual;
        
        toolbar.insert(next_button, -1);

        settings_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_PREFERENCES);
        settings_button.set_label(_("Settings"));
        settings_button.set_tooltip_text(_("Change slideshow settings"));
        settings_button.clicked += on_change_settings;
        settings_button.is_important = true;
        
        toolbar.insert(settings_button, -1);

#if !WINDOWS
        screensaver = new Screensaver();
#endif
    }
    
    public override void switched_to() {
        base.switched_to();

        Gdk.Pixbuf pixbuf;
        if (!get_fullscreen_pixbuf(current, true, out current, out pixbuf))
            return;

        set_pixbuf(pixbuf, current.get_photo().get_dimensions());
        
        // start the auto-advance timer
        Timeout.add(CHECK_ADVANCE_MSEC, auto_advance);
        timer.start();
        
        // prefetch the next pixbuf so it's ready when auto-advance fires
        schedule_prefetch();

#if !WINDOWS
        screensaver.inhibit("Playing slideshow");
#endif
    }
    
    public override void switching_from() {
        base.switching_from();

#if !WINDOWS
        screensaver.uninhibit();
#endif

        exiting = true;
    }
    
    private void schedule_prefetch() {
        next_pixbuf = null;
        Idle.add(prefetch_next_pixbuf);
    }

    private bool get_fullscreen_pixbuf(Thumbnail start, bool forward, out Thumbnail next, out Gdk.Pixbuf next_pixbuf) {
        next = start;

        for (;;) {
            try {
                // Fails if a photo source file is missing.
                next_pixbuf = next.get_photo().get_pixbuf(Scaling.for_screen(get_container(), true));
            } catch (Error err) {
                warning("%s", err.message);

                // Look for the next good photo.
                next = (Thumbnail) ((forward) ? controller.get_next(next) : controller.get_previous(next));

                // An entire slideshow set might be missing, so check for a loop.
                if ((next == start && next != current) || next == current) {
                    Gtk.MessageDialog dialog = new Gtk.MessageDialog(AppWindow.get_fullscreen(),
                        Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "%s",
                        _("All photo source files are missing."));
                    dialog.title = Resources.APP_TITLE;
                    dialog.run();
                    dialog.destroy();

                    AppWindow.get_instance().end_fullscreen();

                    next = null;
                    next_pixbuf = null;

                    return false;
                }

                continue;
            }
            return true;
        }
    }

    private bool prefetch_next_pixbuf() {
        // if multiple prefetches get lined up in the queue, this stops them from doing multiple
        // pipelines
        if (next_pixbuf != null)
            return false;
        
        get_fullscreen_pixbuf((Thumbnail) controller.get_next(current), true, out next_thumbnail, out next_pixbuf);
        
        return false;
    }
    
    private void on_play_pause() {
        if (playing) {
            play_pause_button.set_stock_id(Gtk.STOCK_MEDIA_PLAY);
            play_pause_button.set_label(_("Play"));
            play_pause_button.set_tooltip_text(_("Continue the slideshow"));
        } else {
            play_pause_button.set_stock_id(Gtk.STOCK_MEDIA_PAUSE);
            play_pause_button.set_label(_("Pause"));
            play_pause_button.set_tooltip_text(_("Pause the slideshow"));
        }
        
        playing = !playing;
        
        // reset the timer
        timer.start();
    }
    
    private void on_previous_manual() {
        manual_advance((Thumbnail) controller.get_previous(current), false);
    }
    
    private void on_next_automatic() {
        current = ((current == next_thumbnail) ? (Thumbnail) controller.get_next(current) : next_thumbnail);
        
        // if prefetch didn't happen in time, get pixbuf now
        Gdk.Pixbuf pixbuf = next_pixbuf;
        if (pixbuf == null) {
            warning("Slideshow prefetch was not ready");

            get_fullscreen_pixbuf(current, true, out current, out pixbuf);
        }
        
        if (pixbuf != null)
            set_pixbuf(pixbuf, current.get_photo().get_dimensions());
        
        // reset the timer
        timer.start();
        
        // prefetch the next pixbuf
        schedule_prefetch();
    }
    
    private void on_next_manual() {
        manual_advance((Thumbnail) controller.get_next(current), true);
    }
    
    private void manual_advance(Thumbnail thumbnail, bool forward) {
        current = thumbnail;
        
        // set pixbuf
        Gdk.Pixbuf next_pixbuf;
        get_fullscreen_pixbuf(current, forward, out current, out next_pixbuf);
        set_pixbuf(next_pixbuf, current.get_photo().get_dimensions());
        
        // reset the advance timer
        timer.start();
        
        // prefetch the next pixbuf
        schedule_prefetch();
    }

    private bool auto_advance() {
        if (exiting)
            return false;
        
        if (!playing)
            return true;
        
        if (timer.elapsed() < Config.get_instance().get_slideshow_delay())
            return true;
        
        on_next_automatic();
        
        return true;
    }
    
    private override bool key_press_event(Gdk.EventKey event) {
        bool handled = true;
        switch (Gdk.keyval_name(event.keyval)) {
            case "space":
                on_play_pause();
            break;
            
            case "Left":
            case "KP_Left":
                on_previous_manual();
            break;
            
            case "Right":
            case "KP_Right":
                on_next_manual();
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

        int response = settings_dialog.run();
        if (response == Gtk.ResponseType.OK) {
            // sync with the config setting so it will persist
            Config.get_instance().set_slideshow_delay(settings_dialog.get_delay());
        }

        settings_dialog.destroy();
        playing = slideshow_playing;
        timer.start();
    }
}

