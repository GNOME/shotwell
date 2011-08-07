/* Copyright 2011 Yorba Foundation
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
                return Spit.Transitions.Direction.FORWARD;
            
            default:
                error("Unknown Direction %s", this.to_string());
        }
    }
}

// Returns false if Gtk.quit() was called
public bool spin_event_loop(int max = -1) {
    if (max == 0)
        return true;
    
    while (Gtk.events_pending()) {
        if (Gtk.main_iteration())
            return false;
        
        if (max > 0) {
            if (--max <= 0)
                break;
        }
    }
    
    return true;
}

public AdjustmentRelation get_adjustment_relation(Gtk.Adjustment adjustment, int value) {
    if (value < (int) adjustment.get_value())
        return AdjustmentRelation.BELOW;
    else if (value > (int) (adjustment.get_value() + adjustment.get_page_size()))
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

// Verifies that only the mask bits are set in the modifier field, disregarding mouse and 
// key modifers that are not normally of concern (i.e. Num Lock, Caps Lock, etc.).  Mask can be
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
        | Gdk.ModifierType.MOD1_MASK
        | Gdk.ModifierType.MOD3_MASK
        | Gdk.ModifierType.MOD4_MASK
        | Gdk.ModifierType.MOD5_MASK
        | Gdk.ModifierType.SUPER_MASK
        | Gdk.ModifierType.HYPER_MASK
        | Gdk.ModifierType.META_MASK)) == mask;
}

public string get_window_manager() {
    return Gdk.X11Screen.get_window_manager_name(AppWindow.get_instance().get_screen());
}

public string build_dummy_ui_string(Gtk.ActionGroup[] groups) {
    string ui_string = "<ui>";
    foreach (Gtk.ActionGroup group in groups) {
        foreach (Gtk.Action action in group.list_actions())
            ui_string += "<accelerator name=\"%s\" action=\"%s\" />".printf(action.name, action.name);
    }
    ui_string += "</ui>";
    
    return ui_string;
}

#if ENABLE_FACES
bool is_pointer_over(Gdk.Window window) {
    Gdk.DeviceManager? devmgr = window.get_display().get_device_manager();
    if (devmgr == null) {
        debug("No device for display");
        
        return false;
    }
    
    int x, y;
    gdk_device_get_position(devmgr.get_client_pointer(), null, out x, out y);
    
    return x >= 0 && y >= 0 && x < window.get_width() && y < window.get_height();
}
#endif
