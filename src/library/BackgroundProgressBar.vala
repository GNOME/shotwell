/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

internal class BackgroundProgressBar : Gtk.ProgressBar {
    public enum Priority {
        NONE = 0,
        STARTUP_SCAN = 35,
        REALTIME_UPDATE = 40,
        REALTIME_IMPORT = 50,
        METADATA_WRITER = 30
    }

    public bool should_be_visible { get; private set; default = false; }

#if UNITY_SUPPORT
    // UnityProgressBar: init
    private UnityProgressBar uniprobar = UnityProgressBar.get_instance();
#endif

    private const int PULSE_MSEC = 250;

    public BackgroundProgressBar() {
        Object(show_text: true);
    }

    private Priority current_priority = Priority.NONE;
    private uint pulse_id = 0;

    public void start(string label, Priority priority) {
        if (priority < current_priority)
            return;

        stop(priority, false);

        current_priority = priority;
        set_text(label);
        pulse();
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
        set_fraction(fraction);
        set_text(_("%s (%d%%)").printf(label, (int) (fraction * 100.0)));
        should_be_visible = true;

#if UNITY_SUPPORT
        // UnityProgressBar: try to draw & set progress
        uniprobar.set_visible(true);
        uniprobar.set_progress(fraction);
#endif

        return true;
    }

    public void clear(Priority priority) {
        if (priority < current_priority)
            return;

        stop(priority, false);

        current_priority = 0;

        set_fraction(0.0);
        set_text("");
        should_be_visible = false;

#if UNITY_SUPPORT
        // UnityProgressBar: reset
        uniprobar.reset();
#endif
    }

    private bool on_pulse_timeout() {
        pulse();

        return true;
    }
}
