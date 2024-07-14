/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

internal class BackgroundProgressBar : Gtk.Box {
    public enum Priority {
        NONE = 0,
        STARTUP_SCAN = 35,
        REALTIME_UPDATE = 40,
        REALTIME_IMPORT = 50,
        METADATA_WRITER = 30
    }

    public bool should_be_visible { get; private set; default = false; }

    private Gtk.ProgressBar progress_bar;

    private const int PULSE_MSEC = 250;

    public BackgroundProgressBar() {
        Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0, margin_top: 12, margin_bottom: 12, margin_start: 12, margin_end: 12);
        progress_bar = new Gtk.ProgressBar();
        progress_bar.hexpand = true;
        progress_bar.show_text = true;
        append (progress_bar);
    }

    private Priority current_priority = Priority.NONE;
    private uint pulse_id = 0;

    public void start(string label, Priority priority) {
        if (priority < current_priority)
            return;

        stop(priority, false);

        current_priority = priority;
        progress_bar.set_text(label);
        progress_bar.pulse();
        should_be_visible = true;
        pulse_id = Timeout.add(PULSE_MSEC, on_pulse_timeout);
    }

    public void stop(Priority priority, bool clear) {
        if (priority < current_priority)
            return;

        if (pulse_id != 0) {
            Source.remove(pulse_id);
            pulse_id = 0;
        }

        if (clear)
            this.clear(priority);
    }

    public bool update(string label, Priority priority, double count, double total) {
        if (priority < current_priority)
            return false;

        stop(priority, false);

        if (count <= 0.0 || total <= 0.0 || count >= total) {
            clear(priority);

            return false;
        }

        current_priority = priority;

        double fraction = count / total;
        progress_bar.set_fraction(fraction);
        progress_bar.set_text(_("%s (%d%%)").printf(label, (int) (fraction * 100.0)));
        should_be_visible = true;

        return true;
    }

    public void clear(Priority priority) {
        if (priority < current_priority)
            return;

        stop(priority, false);

        current_priority = 0;

        progress_bar.set_fraction(0.0);
        progress_bar.set_text("");
        should_be_visible = false;

    }

    private bool on_pulse_timeout() {
        progress_bar.pulse();

        return true;
    }
}
