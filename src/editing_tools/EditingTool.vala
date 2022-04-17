// SPDX-License-Identifier: LGPL-2.1-or-later
public abstract class EditingTools.EditingTool {
    public PhotoCanvas canvas = null;

    private EditingToolWindow tool_window = null;
    private Gtk.EventControllerKey key_controller;
    protected Cairo.Surface surface;
    public string name;

    [CCode (has_target=false)]
    public delegate EditingTool Factory();

    public signal void activated();

    public signal void deactivated();

    public signal void applied(Command? command, Gdk.Pixbuf? new_pixbuf, Dimensions new_max_dim,
        bool needs_improvement);

    public signal void cancelled();

    public signal void aborted();


    protected EditingTool(string name) {
        this.name = name;
        key_controller = new Gtk.EventControllerKey();
        key_controller.key_pressed.connect(on_keypress);
    }

    // base.activate() should always be called by an overriding member to ensure the base class
    // gets to set up and store the PhotoCanvas in the canvas member field.  More importantly,
    // the activated signal is called here, and should only be called once the tool is completely
    // initialized.
    public virtual void activate(PhotoCanvas canvas) {
        // multiple activates are not tolerated
        assert(this.canvas == null);
        assert(tool_window == null);

        this.canvas = canvas;

        tool_window = get_tool_window();
        if (tool_window != null)
            ((Gtk.Widget) tool_window).add_controller(key_controller);

        activated();
    }

    // Like activate(), this should always be called from an overriding subclass.
    public virtual void deactivate() {
        // multiple deactivates are tolerated
        if (canvas == null && tool_window == null)
            return;

        canvas = null;

        if (tool_window != null) {
            ((Gtk.Widget) tool_window).remove_controller(key_controller);
            tool_window = null;
        }

        deactivated();
    }

    public bool is_activated() {
        return canvas != null;
    }

    public virtual EditingToolWindow? get_tool_window() {
        return null;
    }

    // This allows the EditingTool to specify which pixbuf to display during the tool's
    // operation.  Returning null means the host should use the pixbuf associated with the current
    // Photo.  Note: This will be called before activate(), primarily to display the pixbuf before
    // the tool is on the screen, and before paint_full() is hooked in.  It also means the PhotoCanvas
    // will have this pixbuf rather than one from the Photo class.
    //
    // If returns non-null, should also fill max_dim with the maximum dimensions of the original
    // image, as the editing host may not always scale images up to fit the viewport.
    //
    // Note this this method doesn't need to be returning the "proper" pixbuf on-the-fly (i.e.
    // a pixbuf with unsaved tool edits in it).  That can be handled in the paint() virtual method.
    public virtual Gdk.Pixbuf? get_display_pixbuf(Scaling scaling, Photo photo,
        out Dimensions max_dim) throws Error {
        max_dim = Dimensions();

        return null;
    }

    public virtual void on_left_click(int x, int y) {
    }

    public virtual void on_left_released(int x, int y) {
    }

    public virtual void on_motion(int x, int y, Gdk.ModifierType mask) {
    }

    public virtual bool on_leave_notify_event(){
        return false;
    }

    public virtual bool on_keypress(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        // check for an escape/abort first
        if (Gdk.keyval_name(keyval) == "Escape") {
            notify_cancel();

            return true;
        }

        return false;
    }

    public virtual void paint(Cairo.Context ctx) {
    }

    // Helper function that fires the cancelled signal.  (Can be connected to other signals.)
    protected void notify_cancel() {
        cancelled();
    }
}
