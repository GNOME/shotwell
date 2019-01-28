/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

private class CheckerboardItemText {
    private static int one_line_height = 0;
    
    private string text;
    private bool marked_up;
    private Pango.Alignment alignment;
    private Pango.Layout layout = null;
    private bool single_line = true;
    private int height = 0;
    
    public Gdk.Rectangle allocation = Gdk.Rectangle();
    
    public CheckerboardItemText(string text, Pango.Alignment alignment = Pango.Alignment.LEFT,
        bool marked_up = false) {
        this.text = text;
        this.marked_up = marked_up;
        this.alignment = alignment;
        
        single_line = is_single_line();
    }
    
    private bool is_single_line() {
        return !String.contains_char(text, '\n');
    }
    
    public bool is_marked_up() {
        return marked_up;
    }
    
    public bool is_set_to(string text, bool marked_up, Pango.Alignment alignment) {
        return (this.marked_up == marked_up && this.alignment == alignment && this.text == text);
    }
    
    public string get_text() {
        return text;
    }
    
    public int get_height() {
        if (height == 0)
            update_height();
        
        return height;
    }
    
    public Pango.Layout get_pango_layout(int max_width = 0) {
        if (layout == null)
            create_pango();
        
        if (max_width > 0)
            layout.set_width(max_width * Pango.SCALE);
        
        return layout;
    }
    
    public void clear_pango_layout() {
        layout = null;
    }
    
    private void update_height() {
        if (one_line_height != 0 && single_line)
            height = one_line_height;
        else
            create_pango();
    }
    
    private void create_pango() {
        // create layout for this string and ellipsize so it never extends past its laid-down width
        layout = AppWindow.get_instance().create_pango_layout(null);
        if (!marked_up)
            layout.set_text(text, -1);
        else
            layout.set_markup(text, -1);
        
        layout.set_ellipsize(Pango.EllipsizeMode.END);
        layout.set_alignment(alignment);
        
        // getting pixel size is expensive, and we only need the height, so use cached values
        // whenever possible
        if (one_line_height != 0 && single_line) {
            height = one_line_height;
        } else {
            int width;
            layout.get_pixel_size(out width, out height);
            
            // cache first one-line height discovered
            if (one_line_height == 0 && single_line)
                one_line_height = height;
        }
    }
}


