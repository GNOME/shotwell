// SPDX-License-Identifier:LGPL-2.1-or-later

public abstract class EditingTools.EditingToolWindow : Gtk.Window {
    private const int FRAME_BORDER = 6;

    private Gtk.Frame layout_frame = new Gtk.Frame(null);
    private bool user_moved = false;

    protected EditingToolWindow(Gtk.Window container) {
        set_transient_for(container);

        Gtk.Frame outer_frame = new Gtk.Frame(null);
        outer_frame.set_child(layout_frame);
        base.set_child(outer_frame);

        focusable = true;
        set_can_focus(true);
        ((Gtk.Widget) this).set_opacity(Resources.TRANSIENT_WINDOW_OPACITY);

        var key = new Gtk.EventControllerKey();
        key.key_pressed.connect(key_press_event);
        ((Gtk.Widget)this).add_controller(key);
    }

    ~EditingToolWindow() {
    }

    public void add(Gtk.Widget widget) {
        layout_frame.set_child(widget);
    }

    public bool has_user_moved() {
        return user_moved;
    }

    public bool key_press_event(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        return event.forward(AppWindow.get_instance());
    }
}
