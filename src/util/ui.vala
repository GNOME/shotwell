/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public enum AdjustmentRelation {
    BELOW,
    IN_RANGE,
    ABOVE
}

public enum CompassPoint {
    NORTH,
    SOUTH,
    EAST,
    WEST
}

public enum Direction {
    FORWARD,
    BACKWARD;
    
    public Spit.Transitions.Direction to_transition_direction() {
        switch (this) {
            case FORWARD:
                return Spit.Transitions.Direction.FORWARD;
            
            case BACKWARD:
                return Spit.Transitions.Direction.BACKWARD;
            
            default:
                error("Unknown Direction %s", this.to_string());
        }
    }
}

public void spin_event_loop() {
    while (MainContext.default().pending())
        MainContext.default().iteration(true);
}

public AdjustmentRelation get_adjustment_relation(Gtk.Adjustment adjustment, double value) {
    if (value < adjustment.get_value())
        return AdjustmentRelation.BELOW;
    else if (value > (adjustment.get_value() + adjustment.get_page_size()))
        return AdjustmentRelation.ABOVE;
    else
        return AdjustmentRelation.IN_RANGE;
}

public Gdk.Rectangle get_adjustment_page(Gtk.Adjustment hadj, Gtk.Adjustment vadj) {
    Gdk.Rectangle rect = Gdk.Rectangle();
    rect.x = (int) hadj.get_value();
    rect.y = (int) vadj.get_value();
    rect.width = (int) hadj.get_page_size();
    rect.height = (int) vadj.get_page_size();
    
    return rect;
}

Gtk.PopoverMenu get_popover_menu_from_resource(string path, string id, Gtk.Widget? parent) {
    var builder = new Gtk.Builder.from_resource(path);
    return get_popover_menu_from_builder(builder, id, parent);
}

Gtk.PopoverMenu get_popover_menu_from_builder(Gtk.Builder builder, string id, Gtk.Widget? parent) {
    var model = builder.get_object (id) as GLib.MenuModel;
    var popover = new Gtk.PopoverMenu.from_model (model);
    if (parent != null) {
        popover.set_parent (parent);
    }
    popover.set_has_arrow(false);

    return popover;
}


// Verifies that only the mask bits are set in the modifier field, disregarding mouse and 
// key modifiers that are not normally of concern (i.e. Num Lock, Caps Lock, etc.).  Mask can be
// one or more bits set, but should only consist of these values:
// * Gdk.ModifierType.SHIFT_MASK
// * Gdk.ModifierType.CONTROL_MASK
// * Gdk.ModifierType.MOD1_MASK (Alt)
// * Gdk.ModifierType.MOD3_MASK
// * Gdk.ModifierType.MOD4_MASK
// * Gdk.ModifierType.MOD5_MASK
// * Gdk.ModifierType.SUPER_MASK
// * Gdk.ModifierType.HYPER_MASK
// * Gdk.ModifierType.META_MASK
//
// (Note: MOD2 seems to be Num Lock in GDK.)
public bool has_only_key_modifier(Gdk.ModifierType field, Gdk.ModifierType mask) {
    return (field 
        & (Gdk.ModifierType.SHIFT_MASK 
        | Gdk.ModifierType.CONTROL_MASK
        | Gdk.ModifierType.ALT_MASK
        | Gdk.ModifierType.SUPER_MASK
        | Gdk.ModifierType.HYPER_MASK
        | Gdk.ModifierType.META_MASK)) == mask;
}

bool is_pointer_over(Gtk.Window window) {
    #if 0
    var seat = window.get_display().get_default_seat();
    if (seat == null) {
        debug("No seat for display");
        
        return false;
    }
    
    int x, y;
    seat.get_pointer().get_position(null, out x, out y);
    
    return x >= 0 && y >= 0 && x < window.get_width() && y < window.get_height();
    #endif
    return false;
}

