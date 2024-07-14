/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class ProgressDialog : Gtk.Window {
    private Gtk.ProgressBar progress_bar = new Gtk.ProgressBar();
    private Gtk.Button cancel_button = null;
    private Cancellable cancellable;
    private uint64 last_count = uint64.MAX;
    private int update_every = 1;
    private int minimum_on_screen_time_msec = 500;
    private ulong time_started;

    public ProgressDialog(Gtk.Window? owner, string text, Cancellable? cancellable = null) {
        this.cancellable = cancellable;

        set_title(text);
        set_resizable(false);
        if (owner != null)
            set_transient_for(owner);
        set_modal(true);

        progress_bar.set_size_request(300, -1);
        progress_bar.set_show_text(true);

        Gtk.Box vbox_bar = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        vbox_bar.prepend(progress_bar);

        if (cancellable != null) {
            cancel_button = new Gtk.Button.with_mnemonic(Resources.CANCEL_LABEL);
            cancel_button.clicked.connect(on_cancel);
            close_request.connect(on_window_closed);
        } else {
            set_hide_on_close(true);
        }

        Gtk.Box hbox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        hbox.prepend(vbox_bar);
        if (cancel_button != null)
            hbox.append(cancel_button);

        Gtk.Label primary_text_label = new Gtk.Label("");
        primary_text_label.set_markup("<span weight=\"bold\">%s</span>".printf(text));
        primary_text_label.xalign = 0.0f;
        primary_text_label.yalign = 0.5f;

        Gtk.Box vbox = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
        vbox.prepend(primary_text_label);
        vbox.append(hbox);
        vbox.halign = Gtk.Align.CENTER;
        vbox.valign = Gtk.Align.CENTER;
        vbox.hexpand = true;
        vbox.vexpand = true;
        vbox.margin_start = 12;
        vbox.margin_end = 12;
        vbox.margin_top = 12;
        vbox.margin_bottom = 12;

        set_child(vbox);

        time_started = now_ms();
        set_titlebar(new Gtk.HeaderBar());
        if (cancellable == null) {
            ((Gtk.HeaderBar)get_titlebar()).set_show_title_buttons(false);
        }
    }

    public void update_display_every(int update_every) {
        assert(update_every >= 1);

        this.update_every = update_every;
    }

    public void set_minimum_on_screen_time_msec(int minimum_on_screen_time_msec) {
        this.minimum_on_screen_time_msec = minimum_on_screen_time_msec;
    }

    public void set_fraction(int current, int total) {
        set_percentage((double) current / (double) total);
    }

    public void set_percentage(double pct) {
        pct = pct.clamp(0.0, 1.0);

        maybe_show_all(pct);

        progress_bar.set_fraction(pct);
        progress_bar.set_text(_("%d%%").printf((int) (pct * 100.0)));
    }

    public void set_status(string text) {
        progress_bar.set_text(text);

        show();
    }

    // This can be used as a ProgressMonitor delegate.
    public bool monitor(uint64 count, uint64 total, bool do_event_loop = true) {
        if ((last_count == uint64.MAX) || (count - last_count) >= update_every) {
            set_percentage((double) count / (double) total);
            last_count = count;
        }

        bool keep_going = (cancellable != null) ? !cancellable.is_cancelled() : true;

        // TODO: get rid of this.  non-trivial, as some progress-monitor operations are blocking
        // and need to allow the event loop to spin
        //
        // Important: Since it's possible the progress dialog might be destroyed inside this call,
        // avoid referring to "this" afterwards at all costs (in case all refs have been dropped)

        if (do_event_loop)
            spin_event_loop();

        return keep_going;
    }

    public new void close() {
        hide();
        destroy();
    }

    private bool on_window_closed() {
        on_cancel();
        return false; // return false so that the system handler will remove the window from
                      // the screen
    }

    private void on_cancel() {
        if (cancellable != null)
            cancellable.cancel();

        cancel_button.sensitive = false;
    }

    private void maybe_show_all(double pct) {
        // Appear only after a while because some jobs may take only a
        // fraction of second to complete so there's no point in showing progress.
        if (!this.visible && now_ms() - time_started > minimum_on_screen_time_msec) {
            // calculate percents completed in one ms
            double pps = pct * 100.0 / minimum_on_screen_time_msec;
            // calculate [very rough] estimate of time to complete in ms
            double ttc = 100.0 / pps;
            // If there is still more work to do for at least MINIMUM_ON_SCREEN_TIME_MSEC,
            // finally display the dialog.
            if (ttc > minimum_on_screen_time_msec) {
                show();
                spin_event_loop();
            }
        }
    }
}
