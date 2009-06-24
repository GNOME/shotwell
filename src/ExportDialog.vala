/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

namespace ExportUI {
    private static File current_export_dir = null;
    
    public File? choose_file(File current_file) {
        if (current_export_dir == null)
            current_export_dir = File.new_for_path(Environment.get_home_dir());
            
        Gtk.FileChooserDialog chooser = new Gtk.FileChooserDialog("Export Photo",
            AppWindow.get_instance(), Gtk.FileChooserAction.SAVE, Gtk.STOCK_CANCEL, 
            Gtk.ResponseType.CANCEL, Gtk.STOCK_SAVE, Gtk.ResponseType.ACCEPT, null);
        chooser.set_do_overwrite_confirmation(true);
        chooser.set_current_folder(current_export_dir.get_path());
        chooser.set_current_name(current_file.get_basename());

        File file = null;
        if (chooser.run() == Gtk.ResponseType.ACCEPT) {
            file = File.new_for_path(chooser.get_filename());
            current_export_dir = file.get_parent();
        }
        
        chooser.destroy();
        
        return file;
    }
    
    public File? choose_dir() {
        if (current_export_dir == null)
            current_export_dir = File.new_for_path(Environment.get_home_dir());

        Gtk.FileChooserDialog chooser = new Gtk.FileChooserDialog("Export Photos to Directory",
            AppWindow.get_instance(), Gtk.FileChooserAction.SELECT_FOLDER, Gtk.STOCK_CANCEL, 
            Gtk.ResponseType.CANCEL, Gtk.STOCK_OK, Gtk.ResponseType.ACCEPT, null);
        chooser.set_current_folder(current_export_dir.get_path());
        
        File dir = null;
        if (chooser.run() == Gtk.ResponseType.ACCEPT) {
            dir = File.new_for_path(chooser.get_filename());
            current_export_dir = dir;
        }
        
        chooser.destroy();
        
        return dir;
    }
    
    public bool query_overwrite(File file) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog(AppWindow.get_instance(), Gtk.DialogFlags.MODAL, 
            Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO, "%s already exists.  Overwrite?",
            file.get_path());
        dialog.title = "Export Photos to Directory";

        bool yes = (dialog.run() == Gtk.ResponseType.YES);

        dialog.destroy();
        
        return yes;
    }
}

public class ExportDialog : Gtk.Dialog {
    public static const ScaleConstraint[] CONSTRAINT_ARRAY = { ScaleConstraint.ORIGINAL,
        ScaleConstraint.DIMENSIONS, ScaleConstraint.WIDTH, ScaleConstraint.HEIGHT };
    
    public static const Jpeg.Quality[] QUALITY_ARRAY = { Jpeg.Quality.LOW, Jpeg.Quality.MEDIUM, 
        Jpeg.Quality.HIGH, Jpeg.Quality.MAXIMUM };

    private static ScaleConstraint current_constraint = ScaleConstraint.DIMENSIONS;
    private static Jpeg.Quality current_quality = Jpeg.Quality.HIGH;
    private static int current_scale = 1200;
    
    private Gtk.Table table = new Gtk.Table(0, 0, false);
    private Gtk.ComboBox quality_combo;
    private Gtk.ComboBox constraint_combo;
    private Gtk.Entry pixels_entry;
    private Gtk.Widget ok_button;
    private bool in_insert = false;
    
    public ExportDialog(int count) {
        // TODO: I18N
        title = "Export Photo%s".printf(count > 1 ? "s" : "");
        has_separator = false;
        allow_grow = false;
        
        // prepare controls
        quality_combo = new Gtk.ComboBox.text();
        int ctr = 0;
        foreach (Jpeg.Quality quality in QUALITY_ARRAY) {
            quality_combo.append_text(quality.to_string());
            if (quality == current_quality)
                quality_combo.set_active(ctr);
            ctr++;
        }
        
        constraint_combo = new Gtk.ComboBox.text();
        ctr = 0;
        foreach (ScaleConstraint constraint in CONSTRAINT_ARRAY) {
            constraint_combo.append_text(constraint.to_string());
            if (constraint == current_constraint)
                constraint_combo.set_active(ctr);
            ctr++;
        }

        pixels_entry = new Gtk.Entry();
        pixels_entry.set_max_length(6);
        pixels_entry.set_text("%d".printf(current_scale));
        
        // register after preparation to avoid signals during init
        constraint_combo.changed += on_constraint_changed;
        pixels_entry.changed += on_pixels_changed;
        pixels_entry.insert_text += on_pixels_insert_text;
        pixels_entry.activate += on_activate;

        // layout controls 
        add_label("Quality", 0, 0);
        add_control(quality_combo, 1, 0);
        
        add_label("Scaling constraint", 0, 1);
        add_control(constraint_combo, 1, 1);
        
        Gtk.HBox pixels_box = new Gtk.HBox(false, 0);
        pixels_box.pack_start(pixels_entry, true, true, 0);
        pixels_box.pack_end(new Gtk.Label(" pixels"), false, false, 0);
        add_control(pixels_box, 1, 2);
        
        ((Gtk.VBox) get_content_area()).add(table);
        
        // add buttons to action area
        add_button(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL);
        ok_button = add_button(Gtk.STOCK_OK, Gtk.ResponseType.OK);

        ok_button.set_flags(ok_button.get_flags() | Gtk.WidgetFlags.CAN_DEFAULT | Gtk.WidgetFlags.HAS_DEFAULT);
        set_default(ok_button);

        if (current_constraint == ScaleConstraint.ORIGINAL) {
            pixels_entry.sensitive = false;
            quality_combo.sensitive = false;
        }

        ok_button.grab_focus();
    }
    
    public bool execute(out int scale, out ScaleConstraint constraint, out Jpeg.Quality quality) {
        show_all();

        bool ok = (run() == Gtk.ResponseType.OK);
        if (ok) {
            int index = constraint_combo.get_active();
            assert(index >= 0);
            constraint = CONSTRAINT_ARRAY[index];
            current_constraint = constraint;
            
            scale = pixels_entry.get_text().to_int();
            if (constraint != ScaleConstraint.ORIGINAL)
                assert(scale > 0);
            current_scale = scale;
            
            index = quality_combo.get_active();
            assert(index >= 0);
            quality = QUALITY_ARRAY[index];
            current_quality = quality;
        }
        
        destroy();
        
        return ok;
    }
    
    private void add_label(string text, int x, int y) {
        Gtk.Alignment left_aligned = new Gtk.Alignment(0.0f, 0.5f, 0, 0);
        left_aligned.add(new Gtk.Label(text));
        
        table.attach(left_aligned, x, x + 1, y, y + 1, Gtk.AttachOptions.FILL, Gtk.AttachOptions.FILL, 
            10, 5);
    }
    
    private void add_control(Gtk.Widget widget, int x, int y) {
        Gtk.Alignment left_aligned = new Gtk.Alignment(0, 0.5f, 0, 0);
        left_aligned.add(widget);
        
        table.attach(left_aligned, x, x + 1, y, y + 1, Gtk.AttachOptions.FILL, Gtk.AttachOptions.FILL,
            10, 5);
    }
    
    private void on_constraint_changed() {
        bool original = (CONSTRAINT_ARRAY[constraint_combo.get_active()] == ScaleConstraint.ORIGINAL);
        pixels_entry.sensitive = !original;
        quality_combo.sensitive = !original;
        if (original)
            ok_button.sensitive = true;
        else
            on_pixels_changed();
    }
    
    private void on_activate() {
        response(Gtk.ResponseType.OK);
    }
    
    private void on_pixels_changed() {
        ok_button.sensitive = (pixels_entry.get_text_length() > 0) && (pixels_entry.get_text().to_int() > 0);
    }
    
    private void on_pixels_insert_text(string text, int length, void *position) {
        // This is necessary because SignalHandler.block_by_func() is not properly bound
        if (in_insert)
            return;
            
        in_insert = true;
        
        if (length == -1)
            length = (int) text.length;

        // only permit numeric text
        string buffer = new string();
        string new_text = new string();
        for (int ctr = 0; ctr < length; ctr++) {
            if (text[ctr].isdigit()) {
                text[ctr].to_utf8(buffer);
                new_text += buffer;
            }
        }
        
        if (new_text.length > 0)
            pixels_entry.insert_text(new_text, (int) new_text.length, position);

        Signal.stop_emission_by_name(pixels_entry, "insert-text");
        
        in_insert = false;
    }
}
