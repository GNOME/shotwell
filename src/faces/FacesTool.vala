/* Copyright 2018 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

#if ENABLE_FACES
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
        public signal void face_tool_window_default_view();

        public Gtk.Label label;
        public Gtk.Button delete_button;
        public Gtk.Entry name_entry;
        public Gtk.Button ok_button;
        public Gtk.Button cancel_button;

        public weak FaceShape face_shape;

        static construct {
            attrs_bold = new Pango.AttrList();
            attrs_bold.insert(Pango.attr_weight_new(Pango.Weight.BOLD));
            attrs_normal = new Pango.AttrList();
            attrs_normal.insert(Pango.attr_weight_new(Pango.Weight.NORMAL));
        }

        public FaceWidget (FaceShape face_shape) {
            spacing = CONTROL_SPACING;

            delete_button = new Gtk.Button.from_icon_name("user-trash", Gtk.IconSize.BUTTON);
            delete_button.set_use_underline(true);

            label = new Gtk.Label(face_shape.get_name());
            label.halign = Gtk.Align.START;
            label.valign = Gtk.Align.CENTER;
            label.ellipsize = Pango.EllipsizeMode.END;
            label.width_chars = FACE_LABEL_MAX_CHARS;

            name_entry = new Gtk.Entry();

            ok_button = new Gtk.Button.from_icon_name("emblem-default", Gtk.IconSize.BUTTON);
            ok_button.set_use_underline(true);

            cancel_button = new Gtk.Button.from_icon_name("edit-undo", Gtk.IconSize.BUTTON);
            cancel_button.set_use_underline(true);
            cancel_button.clicked.connect(set_default_view);

            pack_start(label, true);
            pack_start(delete_button, false);

            this.face_shape = face_shape;
            face_shape.set_widget(this);

        }

        public bool on_enter_notify_event() {
            // if is editing name
            if (name_entry.get_visible() == true)
                return true;

            // if is editing name in popover

            // if not edit name, just bold text and show rectangle
            activate_label();

            // [TODO] this return false can change a lot
//            if (face_shape.is_editable())
//                return false;

            // This check is necessary to avoid painting the face twice --see
            // note in on_leave_notify_event.
//            if (!face_shape.is_visible())
//                face_shape.show();

            return true;
        }

        public bool on_leave_notify_event() {
            // This check is necessary because GTK+ will throw enter/leave_notify
            // events when the pointer passes though windows, even if one window
            // belongs to a widget that is a child of the widget that throws this
            // signal. So, this check is necessary to avoid "deactivation" of
            // the label if the pointer enters one of the buttons in this FaceWidget.
            face_shape.set_view_state(FaceShape.ViewState.HIDE);
/*            if (!is_pointer_over(get_window())) {
                deactivate_label();

                if (face_shape.is_editable())
                    return false;

                face_shape.hide();
                face_hidden();
            }*/

            return true;
        }

        public bool edit_name() {
            set_default_view();
            face_tool_window_default_view();
            remove(label);
            remove(delete_button);
            pack_start(name_entry, true);
            pack_start(ok_button, false);
            pack_start(cancel_button, false);
            name_entry.set_visible(true);
            name_entry.set_text(face_shape.get_name());
            name_entry.grab_focus();
            ok_button.set_visible(true);
            cancel_button.set_visible(true);

            return true;
        }

        public void set_default_view() {
            if (name_entry.get_visible() == true) {
                remove(name_entry);
                name_entry.set_visible(false);
                remove(ok_button);
                remove(cancel_button);
                pack_start(label, true);
                pack_start(delete_button, false);
            }
            face_shape.set_view_state(FaceShape.ViewState.HIDE);
        }

        public FaceShape? update_ui_is_face_new() {
            //update user interface
            set_default_view();

            //need to update any FaceShape?
            if (name_entry.get_text() != label.get_text()) {
                string new_name = name_entry.get_text();
                label.set_text(new_name);
                face_shape.set_name(new_name);
                face_shape.add_me_requested(face_shape);
                return face_shape;
            } else {
                return null; //do not need update
            }
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
        public signal void face_shape_edit_requested(FaceShape face_shape, bool creating = false);
        public signal void face_delete_requested(string face_name);
        public signal void detection_canceled();

        public Gtk.Button detection_button = new Gtk.Button.with_label(_("Detect faces…"));
        public Gtk.Button ok_button;
        public Gtk.Button cancel_button;
        public Gtk.Button cancel_detection_button;

        private EditingPhase editing_phase = EditingPhase.NOT_EDITING;
        private Gtk.Box help_layout = null;
        private Gtk.Box response_layout = null;
        private Gtk.Label help_text = null;
        private Gtk.ListBox face_widgets_layout = null;
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
            cancel_detection_button.set_image_position(Gtk.PositionType.LEFT);
            cancel_detection_button.clicked.connect(on_cancel_detection);

            cancel_button.set_tooltip_text(_("Close the Faces tool without saving changes"));
            cancel_button.set_image_position(Gtk.PositionType.LEFT);

            ok_button.set_image_position(Gtk.PositionType.LEFT);

            face_widgets_layout = new Gtk.ListBox();
            face_widgets_layout.set_selection_mode(Gtk.SelectionMode.NONE);

            help_text = new Gtk.Label(_("Click and drag to tag a face"));
            help_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, CONTROL_SPACING);
            help_layout.pack_start(help_text, true);

            response_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, CONTROL_SPACING);
            response_layout.set_homogeneous(true);
            response_layout.add(detection_button);
            response_layout.add(cancel_button);
            response_layout.add(ok_button);

            layout = new Gtk.Box(Gtk.Orientation.VERTICAL, CONTROL_SPACING);
            layout.pack_start(face_widgets_layout, false);
            layout.pack_start(help_layout, false);
            layout.pack_start(new Gtk.HSeparator(), false);
            layout.pack_start(response_layout, false);

            add(layout);
        }

        public void set_editing_phase(EditingPhase phase, FaceShape? face_shape = null) {
            if (editing_phase == EditingPhase.DETECTING_FACES &&
                phase != EditingPhase.DETECTING_FACES_FINISHED)
                return;

            switch (phase) {
                case EditingPhase.CLICK_TO_EDIT:
                    assert(face_shape != null);

                    help_text.set_markup(Markup.printf_escaped(_("Click to edit face <i>%s</i>"),
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
                        help_layout.pack_start(cancel_detection_button, false);

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
            face_widget.delete_button.clicked.connect(delete_face);

            Gtk.EventBox event_box = new Gtk.EventBox();
            event_box.add(face_widget);
            event_box.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK);
            event_box.enter_notify_event.connect(face_widget.on_enter_notify_event);
            event_box.leave_notify_event.connect(face_widget.on_leave_notify_event);
            event_box.button_press_event.connect(face_widget.edit_name);
            face_widget.ok_button.clicked.connect(on_face_widget_ok_button_pressed);
            face_widget.face_tool_window_default_view.connect(all_face_widgets_default_view);

            face_widgets_layout.insert(event_box, -1);

            face_widgets_layout.show_all();
        }

        private void delete_face(Gtk.Button button) {
            FaceWidget widget = (FaceWidget) button.get_parent();

            face_delete_requested(widget.label.get_text());

            Gtk.EventBox event = (Gtk.EventBox) widget.get_parent();
            Gtk.ListBoxRow row = (Gtk.ListBoxRow) event.get_parent();
            face_widgets_layout.remove(row);
            row.destroy();
        }

        private void on_face_hidden() {
            face_hidden();
        }

        private void on_cancel_detection() {
            detection_canceled();
        }

        private void on_face_widget_ok_button_pressed(Gtk.Button button) {
            FaceWidget widget = (FaceWidget) button.get_parent();
            FaceShape face_shape = widget.update_ui_is_face_new();
            if (face_shape != null) {
                face_shape_edit_requested(face_shape);
                ok_button_set_sensitive(true);
            }
        }

        private void all_face_widgets_default_view() {
            set_editing_phase(EditingPhase.NOT_EDITING);
            List<unowned Gtk.ListBoxRow> rows = (List<unowned Gtk.ListBoxRow>) face_widgets_layout.get_children();
            foreach (Gtk.ListBoxRow list_row in rows) {
                Gtk.EventBox event_box = (Gtk.EventBox) list_row.get_child();
                FaceWidget face_widget = (FaceWidget) event_box.get_child();
                face_widget.set_default_view();
            }
        }
    }

    public class EditingFacePopover{
        public Gtk.Popover popover;
        public Gtk.Entry entry;
        public Gtk.Button ok_button;
        public Gtk.Button cancel_button;

        public EditingFacePopover(Page? window){
            entry = new Gtk.Entry();
            ok_button = new Gtk.Button.with_label(Resources.OK_LABEL);
            ok_button.set_use_underline(true);
            cancel_button = new Gtk.Button.with_label(Resources.CANCEL_LABEL);
            cancel_button.set_use_underline(true);

            Gtk.Box layoutH;
            Gtk.Box layoutV;
            layoutV = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            layoutV.set_border_width(5);
            layoutV.set_spacing(CONTROL_SPACING);
            layoutH = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            layoutH.set_homogeneous(true);
            layoutH.set_spacing(CONTROL_SPACING);
            layoutV.add(entry);
            layoutV.add(layoutH);
            layoutH.add(ok_button);
            layoutH.add(cancel_button);
            layoutV.set_can_default (true);
            popover = new Gtk.Popover(window);
            popover.add(layoutV);
            popover.set_position(Gtk.PositionType.BOTTOM);
            popover.show_all();
            popover.hide();
            popover.set_modal(false);
        }
    }

    private class FaceDetectionJob : BackgroundJob {
        private Gee.Queue<string> faces = null;
        private string image_path;
        private string output;
        public SpawnError? spawnError;

        public FaceDetectionJob(FacesToolWindow owner, string image_path,
            CompletionCallback completion_callback, Cancellable cancellable,
            CancellationCallback cancellation_callback) {
            base(owner, completion_callback, cancellable, cancellation_callback);

            this.image_path = image_path;
        }

        public override void execute() {
            try {
                string[] argv = {
                    AppDirs.get_facedetect_bin().get_path(),
                    "--cascade=" + AppDirs.get_haarcascade_file().get_path(),
                    "--scale=1.2",
                    image_path
                };
                Process.spawn_sync(null, argv, null, SpawnFlags.STDERR_TO_DEV_NULL, null, out output);

            } catch (SpawnError e) {
                spawnError = e;
                critical(e.message);

                return;
            }

            faces = new Gee.PriorityQueue<string>();
            string[] lines = output.split("\n");
            foreach (string line in lines) {
                if (line.length == 0)
                    continue;

                string[] type_and_serialized = line.split(";");
                if (type_and_serialized.length != 2) {
                    critical("Wrong serialized line in face detection program output.");
                    assert_not_reached();
                }

                switch (type_and_serialized[0]) {
                    case "face":
                        StringBuilder serialized_geometry = new StringBuilder();
                        serialized_geometry.append(FaceRectangle.SHAPE_TYPE);
                        serialized_geometry.append(";");
                        serialized_geometry.append(parse_serialized_geometry(type_and_serialized[1]));

                        faces.add(serialized_geometry.str);
                        break;

                    case "warning":
                        warning("%s\n", type_and_serialized[1]);
                        break;

                    case "error":
                        critical("%s\n", type_and_serialized[1]);
                        assert_not_reached();

                    default:
                        assert_not_reached();
                }
            }
        }

        private string parse_serialized_geometry(string serialized_geometry) {
            string[] serialized_geometry_pieces = serialized_geometry.split("&");
            if (serialized_geometry_pieces.length != 4) {
                critical("Wrong serialized line in face detection program output.");
                assert_not_reached();
            }

            double x = 0;
            double y = 0;
            double width = 0;
            double height = 0;
            foreach (string piece in serialized_geometry_pieces) {

                string[] name_and_value = piece.split("=");
                if (name_and_value.length != 2) {
                    critical("Wrong serialized line in face detection program output.");
                    assert_not_reached();
                }

                switch (name_and_value[0]) {
                    case "x":
                        x = name_and_value[1].to_double();
                        break;

                    case "y":
                        y = name_and_value[1].to_double();
                        break;

                    case "width":
                        width = name_and_value[1].to_double();
                        break;

                    case "height":
                        height = name_and_value[1].to_double();
                        break;

                    default:
                        critical("Wrong serialized line in face detection program output.");
                        assert_not_reached();
                }
            }

            double half_width = width / 2;
            double half_height = height / 2;

            return "%s;%s;%s;%s".printf((x + half_width).to_string(), (y + half_height).to_string(),
                half_width.to_string(), half_height.to_string());
        }

        public string? get_next() {
            if (faces == null)
                return null;

            return faces.poll();
        }

        public void reset() {
            faces = null;
        }
    }

    public Cairo.Surface image_surface = null;
    private Gee.HashMap<string, FaceShape> face_shapes;
    private Gee.HashMap<string, string> original_face_locations;
    private Cancellable face_detection_cancellable;
    private FaceDetectionJob face_detection;
    private Workers workers;
    private FaceShape editing_face_shape = null;
    private FacesToolWindow faces_tool_window = null;

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
                try {
                    new_face_shape = FaceShape.from_serialized(canvas, serialized_geometry);
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
        workers = new Workers(1, false);
        face_detection = new FaceDetectionJob(faces_tool_window,
            canvas.get_photo().get_file().get_path(), on_faces_detected,
            face_detection_cancellable, on_detection_cancelled);

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
        faces_tool_window.key_press_event.connect(on_keypress);
        faces_tool_window.ok_button.clicked.connect(on_faces_ok);
        faces_tool_window.cancel_button.clicked.connect(notify_cancel);
        faces_tool_window.detection_button.clicked.connect(detect_faces);
        faces_tool_window.face_hidden.connect(on_face_hidden);
        faces_tool_window.face_edit_requested.connect(edit_face);
        faces_tool_window.face_shape_edit_requested.connect(edit_face_shape);
        faces_tool_window.face_delete_requested.connect(delete_face);
        faces_tool_window.detection_canceled.connect(cancel_face_detection);
    }

    private void unbind_window_handlers() {
        faces_tool_window.key_press_event.disconnect(on_keypress);
        faces_tool_window.ok_button.clicked.disconnect(on_faces_ok);
        faces_tool_window.cancel_button.clicked.disconnect(notify_cancel);
        faces_tool_window.detection_button.clicked.disconnect(detect_faces);
        faces_tool_window.face_hidden.disconnect(on_face_hidden);
        faces_tool_window.face_edit_requested.disconnect(edit_face);
        faces_tool_window.face_shape_edit_requested.disconnect(edit_face_shape);
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

    public override bool on_keypress(Gdk.EventKey event) {
        string event_keyval = Gdk.keyval_name(event.keyval);

        if (event_keyval == "Return" || event_keyval == "KP_Enter") {
            on_faces_ok();
            return true;
        }

        return base.on_keypress(event);
    }

    public override void on_left_click(int x, int y) {
        // current face_shape is been manipulated?
        if (editing_face_shape != null) {
            if (!editing_face_shape.cursor_is_over(x, y)) {
                editing_face_shape.set_view_state(FaceShape.ViewState.HIDE);
            } else {
                //[TODO] editing_face_shape should "return void", single responsibility principle
                // it stores the initial draging position
                editing_face_shape.on_left_click(x, y);
                faces_tool_window.set_editing_phase(EditingPhase.EDITING);
                return;
            }
        }

        // check if clicked over other face_shape
        foreach (FaceShape face_shape in face_shapes.values) {
            if (face_shape.cursor_is_over(x, y)) {
                edit_face_shape(face_shape);
                face_shape.set_view_state(FaceShape.ViewState.CONTOUR_AND_POPOVER);
                faces_tool_window.set_editing_phase(EditingPhase.EDITING);
                return;
            }
        }

        new_face_shape(x, y);
    }

    public override void on_left_released(int x, int y) {
        if (editing_face_shape != null) {
            editing_face_shape.on_left_released(x, y);

            if (faces_tool_window.get_editing_phase() == EditingPhase.CREATING_DRAGGING) {
                faces_tool_window.set_editing_phase(EditingPhase.CREATING_EDITING);
                editing_face_shape.set_known(false);
                face_shapes.set(editing_face_shape.get_name(), editing_face_shape);
                faces_tool_window.add_face(editing_face_shape);
                editing_face_shape.set_view_state(CONTOUR_AND_POPOVER);
            }
        }
    }

    public override void on_motion(int x, int y, Gdk.ModifierType mask) {
        // is not dragging?
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
                    switch (face_shape.get_view_state()) {
                        case FaceShape.ViewState.HIDE:
                        case FaceShape.ViewState.CONTOUR:
                            face_shape.set_view_state(FaceShape.ViewState.CONTOUR_AND_LABEL);
                            break;
                        case FaceShape.ViewState.CONTOUR_AND_LABEL:
                        case FaceShape.ViewState.CONTOUR_AND_POPOVER:
                            // do nothing ? [TODO] see better
                            break;
                    }

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
                } else if (!cursor_is_over && face_shape.get_view_state() != FaceShape.ViewState.HIDE) {
                    face_shape.set_view_state(FaceShape.ViewState.HIDE);
                }
            }

            if (to_show == null)
                faces_tool_window.set_editing_phase(EditingPhase.NOT_EDITING);
            else
                faces_tool_window.set_editing_phase(EditingPhase.CLICK_TO_EDIT, to_show);
        } else editing_face_shape.on_motion(x, y, mask);
    }

    public override bool on_leave_notify_event() {
        // This check is a workaround for bug #3896.
        if (is_pointer_over(canvas.get_drawing_window()) &&
            !is_pointer_over(faces_tool_window.get_window()))
            return false;

        if (editing_face_shape != null)
            return base.on_leave_notify_event();

        foreach (FaceShape face_shape in face_shapes.values) {
            if (face_shape.get_view_state() != FaceShape.ViewState.HIDE) {
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
            //editing_face_shape.set_editable(false);

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
            editing_face_shape.set_view_state(FaceShape.ViewState.HIDE);
        }

        editing_face_shape = null;

        faces_tool_window.set_editing_phase(EditingPhase.NOT_EDITING);
        faces_tool_window.present();
    }

    private void hide_visible_face() {
        foreach (FaceShape face_shape in face_shapes.values) {
            if (face_shape.get_view_state() != FaceShape.ViewState.HIDE) {
                face_shape.hide();
                break;
            }
        }
    }

    private void on_faces_ok() {
        if (face_shapes == null)
            return;

        Gee.Map<Face, string> new_faces = new Gee.HashMap<Face, string>();
        foreach (FaceShape face_shape in face_shapes.values) {
            if (!face_shape.get_known())
                continue;

            Face new_face = Face.for_name(face_shape.get_name());

            new_faces.set(new_face, face_shape.serialize());
        }

        ModifyFacesCommand command = new ModifyFacesCommand(canvas.get_photo(), new_faces);
        applied(command, null, canvas.get_photo().get_dimensions(), false);
    }

    private void on_face_hidden() {
        if (editing_face_shape != null)
            editing_face_shape.show();
    }

    private void add_face(FaceShape face_shape) {
        face_shape.set_name(face_shape.get_entry_name());
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
//            face_shape.set_editable(false);

            set_ok_button_sensitivity();
            release_face_shape();
        }
    }

    private void edit_face(string face_name) {
        FaceShape face_shape = face_shapes.get(face_name);
        assert(face_shape != null);

        face_shape.set_view_state(FaceShape.ViewState.CONTOUR_AND_POPOVER);
        edit_face_shape(face_shape);
    }

    private void delete_face(string face_name) {
        face_shapes.unset(face_name);

        // It is posible to have two visible faces at the same time, this happens
        // if you are editing one face and you move the pointer around the
        // FaceWidgets area in FacesToolWindow. And you can delete one of that
        // faces, so the other visible face must be repainted.
        foreach (FaceShape face_shape in face_shapes.values) {
            if (face_shape.get_view_state() != FaceShape.ViewState.HIDE) {
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

        workers.enqueue(face_detection);
    }

    private void pick_faces_from_autodetected() {
        int c = 0;
        while (true) {
            string? serialized_geometry = face_detection.get_next();
            if (serialized_geometry == null) {
                faces_tool_window.set_editing_phase(EditingPhase.DETECTING_FACES_FINISHED);

                return;
            }

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

            face_shape.set_name("Unknown face #%d".printf(c));
            face_shape.set_known(false);
            add_face(face_shape);
        }
    }

    private void on_faces_detected() {
        face_detection_cancellable.reset();
        
        if (face_detection.spawnError != null){
            string spawnErrorMessage = _("Error trying to spawn face detection program:\n");
            AppWindow.error_message(spawnErrorMessage + face_detection.spawnError.message + "\n");
            faces_tool_window.set_editing_phase(EditingPhase.DETECTING_FACES_FINISHED);
        } else
            pick_faces_from_autodetected();
    }

    private void on_detection_cancelled(BackgroundJob job) {
        ((FaceDetectionJob) job).reset();
        face_detection_cancellable.reset();

        faces_tool_window.set_editing_phase(EditingPhase.DETECTING_FACES_FINISHED);
    }

    private void cancel_face_detection() {
        faces_tool_window.cancel_detection_button.set_sensitive(false);

        face_detection.cancel();
    }
}

#endif
