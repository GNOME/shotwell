/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Shotwell/ui/set_background_slideshow_dialog.ui")]
public class SetBackgroundSlideshowDialog : Gtk.Dialog {
    [GtkChild]
    private Gtk.CheckButton desktop_background_checkbox;
    [GtkChild]
    private Gtk.CheckButton screensaver_checkbox;
    [GtkChild]
    private Gtk.Scale delay_scale;
    [GtkChild]
    private Gtk.Label delay_value_label;

    private int delay_value = 0;

    public SetBackgroundSlideshowDialog() {
        Object(use_header_bar: Resources.use_header_bar());
        this.set_transient_for (AppWindow.get_instance());
    }

    public override void constructed () {
        on_delay_scale_value_changed ();
    }

    [GtkCallback]
    private void on_checkbox_clicked() {
        set_response_sensitive (Gtk.ResponseType.OK,
                                desktop_background_checkbox.active ||
                                screensaver_checkbox.active);
    }

    [GtkCallback]
    private void on_delay_scale_value_changed() {
        double value = delay_scale.adjustment.value;

        // f(x)=x^5 allows to have fine-grained values (seconds) to the left
        // and very coarse-grained values (hours) to the right of the slider.
        // We limit maximum value to 1 day and minimum to 5 seconds.
        delay_value = (int) (Math.pow(value, 5) / Math.pow(90, 5) * 60 * 60 * 24 + 5);

        // convert to text and remove fractions from values > 1 minute
        string text;
        if (delay_value < 60) {
            text = ngettext("%d second", "%d seconds", delay_value).printf(delay_value);
        } else if (delay_value < 60 * 60) {
            int minutes = delay_value / 60;
            text = ngettext("%d minute", "%d minutes", minutes).printf(minutes);
            delay_value = minutes * 60;
        } else if (delay_value < 60 * 60 * 24) {
            int hours = delay_value / (60 * 60);
            text = ngettext("%d hour", "%d hours", hours).printf(hours);
            delay_value = hours * (60 * 60);
        } else {
            text = _("1 day");
            delay_value = 60 * 60 * 24;
        }

        delay_value_label.label = text;
    }

    public bool execute(out int delay_value, out bool desktop_background, out bool screensaver) {
        this.show_all();
        var result = this.run() == Gtk.ResponseType.OK;
        this.hide ();

        delay_value = this.delay_value;
        desktop_background = desktop_background_checkbox.active;
        screensaver = screensaver_checkbox.active;

        this.destroy();
        return result;
    }
}
