/* Copyright 2018 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public errordomain FaceShapeError {
    CANT_CREATE
}

public class FacesTool : EditingTools.EditingTool {
    protected const int CONTROL_SPACING = 8;
    protected const int FACE_LABEL_MAX_CHARS = 15;

    private enum EditingPhase {
        CLICK_TO_EDIT,
        NOT_EDITING,
        CREATING_DRAGGING,
        CREATING_EDITING,
        EDITING,
        DETECTING_FACES,
        DETECTING_FACES_FINISHED
    }

    public class FaceWidget : Gtk.Box {
        private static Pango.AttrList attrs_bold;
        private static Pango.AttrList attrs_normal;

        public signal void face_hidden();

        public Gtk.Button edit_button;
        public Gtk.Button delete_button;
        public Gtk.Label label;

        public weak FaceShape face_shape;

        static construct {
            attrs_bold = new Pango.AttrList();
            attrs_bold.insert(Pango.attr_weight_new(Pango.Weight.BOLD));
            attrs_normal = new Pango.AttrList();
            attrs_normal.insert(Pango.attr_weight_new(Pango.Weight.NORMAL));
        }

        public FaceWidget (FaceShape face_shape) {
            spacing = CONTROL_SPACING;

            edit_button = new Gtk.Button.with_label(Resources.EDIT_LABEL);
            edit_button.set_use_underline(true);
            delete_button = new Gtk.Button.with_label(Resources.DELETE_LABEL);
            delete_button.set_use_underline(true);

            label = new Gtk.Label(face_shape.get_name());
            label.halign = Gtk.Align.START;
            label.valign = Gtk.Align.CENTER;
            label.ellipsize = Pango.EllipsizeMode.END;
            label.width_chars = FACE_LABEL_MAX_CHARS;

            append(label);
            append(edit_button);
            append(delete_button);

            this.face_shape = face_shape;
            face_shape.set_widget(this);
        }

        public void on_enter_notify_event() {
            activate_label();

            if (face_shape.is_editable())
                return;

            // This check is necessary to avoid painting the face twice --see
            // note in on_leave_notify_event.
            if (!face_shape.is_visible())
                face_shape.show();
        }

        public void on_leave_notify_event() {
            // This check is necessary because GTK+ will throw enter/leave_notify
            // events when the pointer passes though windows, even if one window
            // belongs to a widget that is a child of the widget that throws this
            // signal. So, this check is necessary to avoid "deactivation" of
            // the label if the pointer enters one of the buttons in this FaceWidget.
            #if 0
            if (!is_pointer_over(get_window())) {
                deactivate_label();

                if (face_shape.is_editable())
                    return;

                face_shape.hide();
                face_hidden();
            }
            #endif

            return;
        }

        public void activate_label() {
            label.set_attributes(attrs_bold);
        }

        public void deactivate_label() {
            label.set_attributes(attrs_normal);
        }
    }

    private class FacesToolWindow : EditingTools.EditingToolWindow {
        public signal void face_hidden();
        public signal void face_edit_requested(string face_name);
        public signal void face_delete_requested(string face_name);
        public signal void detection_canceled();

        public Gtk.Button detection_button = new Gtk.Button.with_label(_("Detect faces…"));
        public Gtk.Button ok_button;
        public Gtk.Button cancel_button;
        public Gtk.Button cancel_detection_button;

        private EditingPhase editing_phase = EditingPhase.NOT_EDITING;
        private Gtk.Box help_layout = null;
        private Gtk.Box response_layout = null;
        private Gtk.Separator buttons_text_separator = null;
        private Gtk.Label help_text = null;
        private Gtk.Box face_widgets_layout = null;
        private Gtk.Box layout = null;

        public FacesToolWindow(Gtk.Window container) {
            base(container);
            
            ok_button = new Gtk.Button.with_label(Resources.OK_LABEL);
            ok_button.set_use_underline(true);

            cancel_button = new Gtk.Button.with_label(Resources.CANCEL_LABEL);
            cancel_button.set_use_underline(true);

            cancel_detection_button = new Gtk.Button.with_label(Resources.CANCEL_LABEL);
            cancel_detection_button.set_use_underline(true);

            detection_button.set_tooltip_text(_("Detect faces on this photo"));

            cancel_detection_button.set_tooltip_text(_("Cancel face detection"));
            cancel_detection_button.clicked.connect(on_cancel_detection);

            cancel_button.set_tooltip_text(_("Close the Faces tool without saving changes"));

            face_widgets_layout = new Gtk.Box(Gtk.Orientation.VERTICAL, CONTROL_SPACING);

            help_text = new Gtk.Label(_("Click and drag to tag a face"));
            help_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, CONTROL_SPACING);
            help_layout.append(help_text);

            response_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, CONTROL_SPACING);
            #if ENABLE_FACE_DETECTION
            response_layout.append(detection_button);
            #endif
            response_layout.append(cancel_button);
            response_layout.append(ok_button);

            layout = new Gtk.Box(Gtk.Orientation.VERTICAL, CONTROL_SPACING);
            layout.append(face_widgets_layout);
            layout.append(help_layout);
            layout.append(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));
            layout.append(response_layout);

            set_child(layout);
        }

        public void set_editing_phase(EditingPhase phase, FaceShape? face_shape = null) {
            if (editing_phase == EditingPhase.DETECTING_FACES &&
                phase != EditingPhase.DETECTING_FACES_FINISHED)
                return;

            switch (phase) {
                case EditingPhase.CLICK_TO_EDIT:
                    assert(face_shape != null);

                    help_text.set_markup(Markup.printf_escaped(_("Click to edit face “%s”"),
                        face_shape.get_name()));

                    break;
                case EditingPhase.NOT_EDITING:
                    help_text.set_text(_("Click and drag to tag a face"));

                    break;
                case EditingPhase.CREATING_DRAGGING:
                    help_text.set_text(_("Stop dragging to add your face and name it."));

                    break;
                case EditingPhase.CREATING_EDITING:
                    help_text.set_text(_("Type a name for this face, then press Enter"));

                    break;
                case EditingPhase.EDITING:
                    help_text.set_text(_("Move or modify the face shape or name and press Enter"));

                    break;
                case EditingPhase.DETECTING_FACES:
                    help_text.set_text(_("Detecting faces"));

                    if (cancel_detection_button.get_parent() == null)
                        help_layout.append(cancel_detection_button);

                    detection_button.set_sensitive(false);
                    cancel_detection_button.set_sensitive(true);
                    cancel_detection_button.show();

                    break;
                case EditingPhase.DETECTING_FACES_FINISHED:
                    help_text.set_text(_("If you don’t set the name of unknown faces they won’t be saved."));

                    break;
                default:
                    assert_not_reached();
            }

            if (editing_phase == EditingPhase.DETECTING_FACES && editing_phase != phase) {
                cancel_detection_button.hide();
                detection_button.set_sensitive(true);
            }

            editing_phase = phase;
        }

        public EditingPhase get_editing_phase() {
            return editing_phase;
        }

        public void ok_button_set_sensitive(bool sensitive) {
            if (sensitive)
                ok_button.set_tooltip_text(_("Save changes and close the Faces tool"));
            else
                ok_button.set_tooltip_text(_("No changes to save"));

            ok_button.set_sensitive(sensitive);
        }

        public void add_face(FaceShape face_shape) {
            FaceWidget face_widget = new FaceWidget(face_shape);

            face_widget.face_hidden.connect(on_face_hidden);
            face_widget.edit_button.clicked.connect(edit_face);
            face_widget.delete_button.clicked.connect(delete_face);

            face_widgets_layout.append(face_widget);
            var focus = new Gtk.EventControllerFocus();
            focus.enter.connect(face_widget.on_enter_notify_event);
            focus.leave.connect(face_widget.on_leave_notify_event);
            face_widget.add_controller(focus);

            if (buttons_text_separator == null) {
                buttons_text_separator = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
                face_widgets_layout.append(buttons_text_separator);
            }

            face_widgets_layout.show();
        }

        private void edit_face(Gtk.Button button) {
            FaceWidget widget = (FaceWidget) button.get_parent();

            face_edit_requested(widget.label.get_text());
        }

        private void delete_face(Gtk.Button button) {
            FaceWidget widget = (FaceWidget) button.get_parent();

            face_delete_requested(widget.label.get_text());

            widget.get_parent().destroy();

            #if 0
            if (face_widgets_layout.get_children().length() == 1) {
                buttons_text_separator.destroy();
                buttons_text_separator = null;
            }
            #endif
        }

        private void on_face_hidden() {
            face_hidden();
        }

        private void on_cancel_detection() {
            detection_canceled();
        }
    }

    public class EditingFaceToolWindow : EditingTools.EditingToolWindow {
        public signal bool key_pressed(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers);

        public Gtk.Entry entry;

        private Gtk.Box layout = null;

        public EditingFaceToolWindow(Gtk.Window container) {
            base(container);

            entry = new Gtk.Entry();

            layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, CONTROL_SPACING);
            layout.append(entry);

            set_child(layout);

            var controller = new Gtk.EventControllerKey();
            ((Gtk.Widget)this).add_controller(controller);
            controller.key_pressed.connect(on_keypress);
        }

        public bool on_keypress(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
            return key_pressed(event, keyval, keycode, modifiers);
        }
    }

    private Cairo.Surface image_surface = null;
    private Gee.HashMap<string, FaceShape> face_shapes;
    private Gee.HashMap<string, string> original_face_locations;
    private Cancellable face_detection_cancellable;
    private FaceShape editing_face_shape = null;
    private FacesToolWindow faces_tool_window = null;
    private const int FACE_DETECT_MAX_WIDTH = 1200;

    private FacesTool() {
        base("FacesTool");
    }

    public static FacesTool factory() {
        return new FacesTool();
    }

    public override void activate(EditingTools.PhotoCanvas canvas) {
        face_shapes = new Gee.HashMap<string, FaceShape>();
        original_face_locations = new Gee.HashMap<string, string>();

        bind_canvas_handlers(canvas);

        if (image_surface != null)
            image_surface = null;

        Gdk.Rectangle scaled_pixbuf_position = canvas.get_scaled_pixbuf_position();
        image_surface = new Cairo.ImageSurface(Cairo.Format.ARGB32,
            scaled_pixbuf_position.width,
            scaled_pixbuf_position.height);

        faces_tool_window = new FacesToolWindow(canvas.get_container());

        Gee.Map<FaceID?, FaceLocation>? face_locations =
            FaceLocation.get_locations_by_photo(canvas.get_photo());
        if (face_locations != null)
            foreach (Gee.Map.Entry<FaceID?, FaceLocation> entry in face_locations.entries) {
                FaceShape new_face_shape;
                string serialized_geometry = entry.value.get_serialized_geometry();
                string serialized_vec = entry.value.get_serialized_vec();
                string face_shape_str = serialized_geometry + ";" + serialized_vec;
                try {
                    new_face_shape = FaceShape.from_serialized(canvas, face_shape_str);
                } catch (FaceShapeError e) {
                    if (e is FaceShapeError.CANT_CREATE)
                        continue;

                    assert_not_reached();
                }
                Face? face = Face.global.fetch(entry.key);
                assert(face != null);
                string face_name = face.get_name();
                new_face_shape.set_name(face_name);

                add_face(new_face_shape);
                original_face_locations.set(face_name, serialized_geometry);
            }

        set_ok_button_sensitivity();

        face_detection_cancellable = new Cancellable();

        bind_window_handlers();

        base.activate(canvas);
    }

    public override void deactivate() {
        if (canvas != null)
            unbind_canvas_handlers(canvas);

        if (faces_tool_window != null) {
            unbind_window_handlers();
            faces_tool_window.hide();
            faces_tool_window.destroy();
            faces_tool_window = null;
        }

        base.deactivate();
    }

    private void bind_canvas_handlers(EditingTools.PhotoCanvas canvas) {
        canvas.new_surface.connect(prepare_ctx);
        canvas.resized_scaled_pixbuf.connect(on_resized_pixbuf);
    }

    private void unbind_canvas_handlers(EditingTools.PhotoCanvas canvas) {
        canvas.new_surface.disconnect(prepare_ctx);
        canvas.resized_scaled_pixbuf.disconnect(on_resized_pixbuf);
    }

    private void bind_window_handlers() {
        faces_tool_window.ok_button.clicked.connect(on_faces_ok);
        faces_tool_window.cancel_button.clicked.connect(notify_cancel);
        faces_tool_window.detection_button.clicked.connect(detect_faces);
        faces_tool_window.face_hidden.connect(on_face_hidden);
        faces_tool_window.face_edit_requested.connect(edit_face);
        faces_tool_window.face_delete_requested.connect(delete_face);
        faces_tool_window.detection_canceled.connect(cancel_face_detection);
    }

    private void unbind_window_handlers() {
        faces_tool_window.ok_button.clicked.disconnect(on_faces_ok);
        faces_tool_window.cancel_button.clicked.disconnect(notify_cancel);
        faces_tool_window.detection_button.clicked.disconnect(detect_faces);
        faces_tool_window.face_hidden.disconnect(on_face_hidden);
        faces_tool_window.face_edit_requested.disconnect(edit_face);
        faces_tool_window.face_delete_requested.disconnect(delete_face);
        faces_tool_window.detection_canceled.disconnect(cancel_face_detection);
    }

    private void prepare_ctx(Cairo.Context ctx, Dimensions dim) {
        if (editing_face_shape != null)
            editing_face_shape.prepare_ctx(ctx, dim);
    }

    private void on_resized_pixbuf(Dimensions old_dim, Gdk.Pixbuf scaled, Gdk.Rectangle scaled_position) {
        if (image_surface != null)
            image_surface = null;

        image_surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, scaled.width, scaled.height);
        Cairo.Context ctx = new Cairo.Context(image_surface);
        ctx.set_source_rgba(255.0, 255.0, 255.0, 0.0);
        ctx.paint();

        if (editing_face_shape != null)
            editing_face_shape.on_resized_pixbuf(old_dim, scaled);

        if (face_shapes != null)
            foreach (FaceShape face_shape in face_shapes.values)
                face_shape.on_resized_pixbuf(old_dim, scaled);
    }

    public override bool on_keypress(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        string event_keyval = Gdk.keyval_name(keyval);

        if (event_keyval == "Return" || event_keyval == "KP_Enter") {
            on_faces_ok();
            return true;
        }

        return base.on_keypress(event, keyval, keycode, modifiers);
    }

    public override void on_left_click(int x, int y) {
        var scale = Application.get_scale();
        x = (int) Math.lround(x * scale);
        y = (int) Math.lround(y * scale);
        
        if (editing_face_shape != null && editing_face_shape.on_left_click(x, y))
            return;

        foreach (FaceShape face_shape in face_shapes.values) {
            if (face_shape.is_visible() && face_shape.cursor_is_over(x, y)) {
                edit_face_shape(face_shape);
                face_shape.set_editable(true);

                return;
            }
        }

        new_face_shape(x, y);
        canvas.repaint();
    }

    public override void on_left_released(int x, int y) {
        var scale = Application.get_scale();
        x = (int) Math.lround(x * scale);
        y = (int) Math.lround(y * scale);

        if (editing_face_shape != null) {
            editing_face_shape.on_left_released(x, y);

            if (faces_tool_window.get_editing_phase() == EditingPhase.CREATING_DRAGGING)
                faces_tool_window.set_editing_phase(EditingPhase.CREATING_EDITING);
        }
        canvas.repaint();
    }

    public override void on_motion(int x, int y, Gdk.ModifierType mask) {
        var scale = Application.get_scale();
        x = (int) Math.lround(x * scale);
        y = (int) Math.lround(y * scale);
        
        if (editing_face_shape == null) {
            FaceShape to_show = null;
            double distance = 0;
            double new_distance;

            foreach (FaceShape face_shape in face_shapes.values) {
                bool cursor_is_over = face_shape.cursor_is_over(x, y);

                // The FaceShape that will be shown needs to be repainted
                // even if it is already visible, since it could be erased by
                // another hiding FaceShape -and for the same
                // reason it needs to be painted after all
                // hiding faces are already erased.
                // Also, we paint the FaceShape whose center is closer
                // to the pointer.
                if (cursor_is_over) {
                    face_shape.hide();
                    face_shape.get_widget().deactivate_label();

                    if (to_show == null) {
                        to_show = face_shape;
                        distance = face_shape.get_distance(x, y);
                    } else {
                        new_distance = face_shape.get_distance(x, y);

                        if (new_distance < distance) {
                            to_show = face_shape;
                            distance = new_distance;
                        }
                    }
                } else if (!cursor_is_over && face_shape.is_visible()) {
                    face_shape.hide();
                    face_shape.get_widget().deactivate_label();
                }
            }

            if (to_show == null) {
                faces_tool_window.set_editing_phase(EditingPhase.NOT_EDITING);
            } else {
                faces_tool_window.set_editing_phase(EditingPhase.CLICK_TO_EDIT, to_show);

                to_show.show();
                to_show.get_widget().activate_label();
            }
        } else editing_face_shape.on_motion(x, y, mask);
        canvas.repaint();
    }

    public override bool on_leave_notify_event() {
        #if 0
        // This check is a workaround for bug #3896.
        if (is_pointer_over(canvas.get_drawing_window()) &&
            !is_pointer_over(faces_tool_window.get_window()))
            return false;
        #endif

        if (editing_face_shape != null)
            return base.on_leave_notify_event();

        foreach (FaceShape face_shape in face_shapes.values) {
            if (face_shape.is_editable())
                return base.on_leave_notify_event();

            if (face_shape.is_visible()) {
                face_shape.hide();
                face_shape.get_widget().deactivate_label();

                break;
            }
        }

        faces_tool_window.set_editing_phase(EditingPhase.NOT_EDITING);

        return base.on_leave_notify_event();
    }

    public override EditingTools.EditingToolWindow? get_tool_window() {
        return faces_tool_window;
    }

    public override void paint(Cairo.Context default_ctx) {
        // fill region behind the image surface with neutral color
        int w = canvas.get_drawing_window().get_width();
        int h = canvas.get_drawing_window().get_height();

        default_ctx.set_source_rgba(0.0, 0.0, 0.0, 1.0);
        default_ctx.rectangle(0, 0, w, h);
        default_ctx.fill();
        default_ctx.paint();

        Cairo.Context ctx = new Cairo.Context(image_surface);
        ctx.set_operator(Cairo.Operator.SOURCE);
        ctx.set_source_rgba(0.0, 0.0, 0.0, 0.0);
        ctx.paint();

        canvas.paint_surface(image_surface, true);

        // paint face shape last
        if (editing_face_shape != null)
            editing_face_shape.show();

        foreach (var shape in face_shapes.values) {
            if (shape.is_visible()) {
                // Trigger repaint
                shape.show();
            }
        }
    }

    private void new_face_shape(int x, int y) {
        edit_face_shape(new FaceRectangle(canvas, x, y), true);
    }

    private void edit_face_shape(FaceShape face_shape, bool creating = false) {
        hide_visible_face();

        if (editing_face_shape != null) {
            // We need to do this because it could be one of the already
            // created faces being edited, and if that is the case it
            // will not be destroyed.
            editing_face_shape.hide();
            editing_face_shape.set_editable(false);

            // This is to allow the user to edit a FaceShape's shape
            // without pressing the Enter button.
            if (face_shapes.values.contains(editing_face_shape))
                set_ok_button_sensitivity();

            editing_face_shape = null;
        }

        if (creating) {
            faces_tool_window.set_editing_phase(EditingPhase.CREATING_DRAGGING);
        } else {
            face_shape.show();

            faces_tool_window.set_editing_phase(EditingPhase.EDITING);
        }

        editing_face_shape = face_shape;
        editing_face_shape.add_me_requested.connect(add_face);
        editing_face_shape.delete_me_requested.connect(release_face_shape);
    }

    private void release_face_shape() {
        if (editing_face_shape == null)
            return;

        // We need to do this because it could be one of the already
        // created faces being edited, and if that is the case it
        // will not be destroyed.
        if (editing_face_shape in face_shapes.values) {
            editing_face_shape.hide();
            editing_face_shape.set_editable(false);

            editing_face_shape.get_widget().deactivate_label();
        }

        editing_face_shape = null;

        faces_tool_window.set_editing_phase(EditingPhase.NOT_EDITING);
        faces_tool_window.present();
    }

    private void hide_visible_face() {
        foreach (FaceShape face_shape in face_shapes.values) {
            if (face_shape.is_visible()) {
                face_shape.hide();

                break;
            }
        }
    }

    private void on_faces_ok() {
        if (face_shapes == null)
            return;

        Gee.Map<Face, FaceLocationData?> new_faces = new Gee.HashMap<Face, FaceLocationData?>();
        foreach (FaceShape face_shape in face_shapes.values) {
            if (!face_shape.get_known())
                continue;

            Face new_face = Face.for_name(face_shape.get_name());
            string[] face_string = face_shape.serialize().split(";");
            string face_vec_str, face_geometry;
            face_geometry = string.joinv(";", face_string[0:5]);
            face_vec_str = face_string[5];
            FaceLocationData face_data =
                {
                 face_geometry, face_vec_str
                };
            new_faces.set(new_face, face_data);
        }

        ModifyFacesCommand command = new ModifyFacesCommand(canvas.get_photo(), new_faces);
        applied(command, null, canvas.get_photo().get_dimensions(), false);
    }

    private void on_face_hidden() {
        if (editing_face_shape != null)
            editing_face_shape.show();
    }

    private void add_face(FaceShape face_shape) {
        string? prepared_face_name = Face.prep_face_name(face_shape.get_name());

        if (prepared_face_name != null) {
            face_shape.set_name(prepared_face_name);

            if (face_shapes.values.contains(face_shape)) {
                foreach (Gee.Map.Entry<string, FaceShape> entry in face_shapes.entries) {
                    if (entry.value == face_shape) {
                        if (entry.key == prepared_face_name)
                            break;

                        face_shapes.unset(entry.key);
                        face_shapes.set(prepared_face_name, face_shape);

                        face_shape.set_known(true);
                        face_shape.get_widget().label.set_text(face_shape.get_name());

                        break;
                    }
                }
            } else if (!face_shapes.has_key(prepared_face_name)) {
                faces_tool_window.add_face(face_shape);
                face_shapes.set(prepared_face_name, face_shape);
            } else return;

            face_shape.hide();
            face_shape.set_editable(false);

            set_ok_button_sensitivity();
            release_face_shape();
        }
    }

    private void edit_face(string face_name) {
        FaceShape face_shape = face_shapes.get(face_name);
        assert(face_shape != null);

        face_shape.set_editable(true);
        edit_face_shape(face_shape);
    }

    private void delete_face(string face_name) {
        face_shapes.unset(face_name);

        // It is possible to have two visible faces at the same time, this happens
        // if you are editing one face and you move the pointer around the
        // FaceWidgets area in FacesToolWindow. And you can delete one of that
        // faces, so the other visible face must be repainted.
        foreach (FaceShape face_shape in face_shapes.values) {
            if (face_shape.is_visible()) {
                face_shape.hide();
                face_shape.show();

                break;
            }
        }

        set_ok_button_sensitivity();
    }

    private void set_ok_button_sensitivity() {
        Gee.Map<string, FaceShape> known_face_shapes = new Gee.HashMap<string, FaceShape>();
        foreach (Gee.Map.Entry<string, FaceShape> face_shape in face_shapes.entries) {
            if (face_shape.value.get_known()) {
                known_face_shapes.set(face_shape.key, face_shape.value);
            }
        }

        if (original_face_locations.size != known_face_shapes.size) {
            faces_tool_window.ok_button_set_sensitive(true);

            return;
        }

        foreach (Gee.Map.Entry<string, FaceShape> face_shape in known_face_shapes.entries) {
            bool found = false;

            foreach (Gee.Map.Entry<string, string> face_location in original_face_locations.entries) {
                if (face_location.key == face_shape.key) {
                    if (face_location.value == face_shape.value.serialize()) {
                        found = true;

                        break;
                    } else {
                        faces_tool_window.ok_button_set_sensitive(true);

                        return;
                    }
                }
            }

            if (!found) {
                faces_tool_window.ok_button_set_sensitive(true);

                return;
            }
        }

        faces_tool_window.ok_button_set_sensitive(false);
    }

    private void detect_faces() {
        faces_tool_window.detection_button.set_sensitive(false);
        faces_tool_window.set_editing_phase(EditingPhase.DETECTING_FACES);
        //workers.enqueue(face_detection);
        run_face_detection.begin(on_face_detection_done);
    }

    private async void run_face_detection()  throws Error {
        if (!FaceDetect.connected) {
            throw new SpawnError.INVAL("Face detect process not connected");
        }
        Dimensions dimensions = canvas.get_photo().get_dimensions();
        float scale_factor = (float)dimensions.width / FACE_DETECT_MAX_WIDTH;
        var rects = yield FaceDetect.face_detect_proxy.detect_faces(canvas.get_photo().get_file().get_path(),
                    AppDirs.get_haarcascade_file().get_path(), scale_factor, true, face_detection_cancellable);

        var faces = new Gee.PriorityQueue<string>();
        for (int i = 0; i < rects.length; i++) {
            double rect_x, rect_y, rect_w, rect_h;
            string face_vec_str = "";
            rect_w = rects[i].width / 2;
            rect_h = rects[i].height / 2;
            rect_x = rects[i].x + rect_w;
            rect_y = rects[i].y + rect_h;
            if (rects[i].vec != null) {
                foreach (var d in rects[i].vec) { face_vec_str += d.to_string() + ","; }
            }
            string serialized = "%s;%f;%f;%f;%f;%s".printf(FaceRectangle.SHAPE_TYPE,
                                                                            rect_x, rect_y, rect_w, rect_h,
                                                                            face_vec_str);
            faces.add(serialized);
        }

        pick_faces_from_autodetected(faces);
    }

    private void on_face_detection_done(Object? source, GLib.AsyncResult res) {
        try {
            run_face_detection.end(res);
        } catch (Error e) {
            string spawnErrorMessage = _("Error trying to spawn face detection program:\n");
            AppWindow.error_message(spawnErrorMessage + e.message);
            faces_tool_window.set_editing_phase(EditingPhase.DETECTING_FACES_FINISHED);
        }
    }

    private void pick_faces_from_autodetected(Gee.Queue<string> list) {
        int c = 0;
        var iter = list.iterator();
        while (true) {
            if (!iter.next()) {
                faces_tool_window.set_editing_phase(EditingPhase.DETECTING_FACES_FINISHED);
                
                return;
            }
            string? serialized_geometry = iter.@get();

            FaceShape face_shape;
            try {
                face_shape = FaceShape.from_serialized(canvas, serialized_geometry);
            } catch (FaceShapeError e) {
                if (e is FaceShapeError.CANT_CREATE)
                    continue;

                assert_not_reached();
            }

            bool found = false;
            foreach (FaceShape existing_face_shape in face_shapes.values) {
                if (existing_face_shape.equals(face_shape)) {
                    found = true;

                    break;
                }
            }

            if (found)
                continue;

            c++;
            // Reference faces to match with
            Face? guess = get_face_match(face_shape, 0.7);

            if (guess == null) {
                face_shape.set_name("Unknown face #%d".printf(c));
                face_shape.set_known(false);
            } else {
                string name_str;
                name_str = "%s (%0.2f%%)".printf(guess.get_name(), face_shape.get_guess() * 100);
                face_shape.set_name(name_str);
                face_shape.set_known(true);
            }
            add_face(face_shape);
        }
    }

    private double dot_product(double[] vec1, double[] vec2) {
        if (vec1.length != vec2.length) {
            return 0;
        }

        double ret = 0;
        for (var i = 0; i < vec1.length; i++) {
            ret += vec1[i] * vec2[i];
        }
        return ret;
    }

    private Face? get_face_match(FaceShape face_shape, double threshold) {
        Gee.List<FaceLocationRow?> face_vecs;
        try {
            Gee.List<FaceRow?> face_rows = FaceTable.get_instance().get_ref_rows();
            face_vecs = FaceLocationTable.get_instance().get_face_ref_vecs(face_rows);
        } catch(DatabaseError err) {
            warning("Cannot get reference faces from DB");
            return null;
        }
        FaceID? guess_id = null;
        double max_product = threshold;
        foreach (var row in face_vecs) {
            string[] vec_str = row.vec.split(",");
            double[] vec = {};
            foreach (var d in vec_str) vec += double.parse(d);
            double product = dot_product(face_shape.get_face_vec(), vec[0:128]);
            if (product > max_product) {
                max_product = product;
                guess_id = row.face_id;
            }
        }

        Face? face = null;
        if (guess_id != null) {
            face = Face.global.fetch(guess_id);
            face_shape.set_guess(max_product);
            assert(face != null);
        }
        return face;
    }

    private void cancel_face_detection() {
        faces_tool_window.cancel_detection_button.set_sensitive(false);

        face_detection_cancellable.cancel();
    }
}
