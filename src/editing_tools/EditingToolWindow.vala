// SPDX-License-Identifier:LGPL-2.1-or-later
public abstract class EditingTools.EditingToolWindow : Gtk.Window {
    private const int FRAME_BORDER = 6;

    private Gtk.Frame layout_frame = new Gtk.Frame(null);
    private bool user_moved = false;

    protected EditingToolWindow(Gtk.Window container) {
        set_decorated(false);
        set_transient_for(container);

        Gtk.Frame outer_frame = new Gtk.Frame(null);
        outer_frame.set_child(layout_frame);
        base.set_child(outer_frame);

        // add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.KEY_PRESS_MASK);
        focusable = true;
        set_can_focus(true);
        ((Gtk.Widget) this).set_opacity(Resources.TRANSIENT_WINDOW_OPACITY);
    }

    ~EditingToolWindow() {
    }

    public void add(Gtk.Widget widget) {
        layout_frame.set_child(widget);
    }

    public bool has_user_moved() {
        return user_moved;
    }

    #if 0
    public override bool key_press_event(Gdk.EventKey event) {
        if (base.key_press_event(event)) {
            return true;
        }
        return AppWindow.get_instance().key_press_event(event);
    }

    public override bool button_press_event(Gdk.EventButton event) {
        // LMB only
        if (event.button != 1)
            return (base.button_press_event != null) ? base.button_press_event(event) : true;

        begin_move_drag((int) event.button, (int) event.x_root, (int) event.y_root, event.time);
        user_moved = true;

        return true;
    }
    #endif
}
