/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public abstract class CheckerboardPage : Page {
    private const int AUTOSCROLL_PIXELS = 50;
    private const int AUTOSCROLL_TICKS_MSEC = 50;

    private weak CheckerboardLayout layout;
    private Gtk.Stack stack;
    private PageMessagePane message_pane;
    private string item_context_menu_path = null;
    private string page_context_menu_path = null;
    //private Gtk.Viewport viewport = new Gtk.Viewport(null, null);
    protected CheckerboardItem anchor = null;
    protected CheckerboardItem current_cursor = null;
    private CheckerboardItem current_hovered_item = null;
    private bool autoscroll_scheduled = false;
    private CheckerboardItem activated_item = null;
    private Gee.ArrayList<CheckerboardItem> previously_selected = null;

    public enum Activator {
        KEYBOARD,
        MOUSE
    }

    public struct KeyboardModifiers {
        public KeyboardModifiers(Page page) {
            ctrl_pressed = page.get_ctrl_pressed();
            alt_pressed = page.get_alt_pressed();
            shift_pressed = page.get_shift_pressed();
            super_pressed = page.get_super_pressed();
        }

        public bool ctrl_pressed;
        public bool alt_pressed;
        public bool shift_pressed;
        public bool super_pressed;
    }

    protected CheckerboardPage(string page_name) {
        base (page_name);

        stack = new Gtk.Stack();
        message_pane = new PageMessagePane();

        var layout = new CheckerboardLayout(get_view());
        layout.set_name(page_name);
        stack.add_named (layout, "layout");
        stack.add_named (message_pane, "message");
        stack.set_visible_child(layout);
        this.layout = layout;

        set_event_source(layout);

        //viewport.set_child(stack);

        // want to set_adjustments before adding to ScrolledWindow to let our signal handlers
        // run first ... otherwise, the thumbnails draw late
        layout.set_adjustments(scrolled.get_hadjustment(), scrolled.get_vadjustment());

        scrolled.set_child(stack);

        // need to monitor items going hidden when dealing with anchor/cursor/highlighted items
        get_view().items_hidden.connect(on_items_hidden);
        get_view().contents_altered.connect(on_contents_altered);
        get_view().items_state_changed.connect(on_items_state_changed);
        get_view().items_visibility_changed.connect(on_items_visibility_changed);

        // scrollbar policy
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);

        var key_controller = new Gtk.EventControllerKey();
        key_controller.key_pressed.connect(key_press_event);
        add_controller (key_controller);
    }

    protected override bool on_configure(Gdk.Rectangle rect) {
        layout.on_viewport_resized();

        return false;
    }

    public void init_item_context_menu(string path) {
        item_context_menu_path = path;
    }

    public void init_page_context_menu(string path) {
        page_context_menu_path = path;
    }

    public Gtk.PopoverMenu? get_context_menu() {
        // show page context menu if nothing is selected
        return (get_view().get_selected_count() != 0) ? get_item_context_menu() :
            get_page_context_menu();
    }

    private Gtk.PopoverMenu item_context_menu;
    public virtual Gtk.PopoverMenu? get_item_context_menu() {
        if (item_context_menu == null) {
            item_context_menu = get_popover_menu_from_builder (this.builder, item_context_menu_path, this);
        }

        return item_context_menu;
    }

    private Gtk.PopoverMenu page_context_menu;
    public override Gtk.PopoverMenu? get_page_context_menu() {
        if (page_context_menu_path == null)
            return null;

        if (page_context_menu == null) {
            page_context_menu = get_popover_menu_from_builder (this.builder, page_context_menu_path, this);
        }

        return page_context_menu;
    }

    protected override bool on_context_keypress() {
        //return popup_context_menu(get_context_menu());
        return true;
    }

    protected virtual string get_view_empty_icon() {
        return "image-x-generic-symbolic";
    }

    protected virtual string get_view_empty_message() {
        return _("No photos/videos");
    }

    protected virtual string get_filter_no_match_message() {
        return _("No photos/videos found which match the current filter");
    }

    protected virtual void on_item_activated(CheckerboardItem item, Activator activator, 
        KeyboardModifiers modifiers) {
    }

    public weak CheckerboardLayout get_checkerboard_layout() {
        return layout;
    }

    // Gets the search view filter for this page.
    public abstract SearchViewFilter get_search_view_filter();

    public virtual Core.ViewTracker? get_view_tracker() {
        return null;
    }

    public override void switching_from() {
        layout.set_in_view(false);
        get_search_view_filter().refresh.disconnect(on_view_filter_refresh);

        // unselect everything so selection won't persist after page loses focus 
        get_view().unselect_all();

        base.switching_from();
    }

    public void scroll_to_item(CheckerboardItem item) {
        Gtk.Adjustment vadj = scrolled.get_vadjustment();
        if (!(get_adjustment_relation(vadj, item.allocation.y) == AdjustmentRelation.IN_RANGE
              && (get_adjustment_relation(vadj, item.allocation.y + item.allocation.height) == AdjustmentRelation.IN_RANGE))) {

            // scroll to see the new item
            int top = 0;
            if (item.allocation.y < vadj.get_value()) {
                top = item.allocation.y;
                top -= CheckerboardLayout.ROW_GUTTER_PADDING / 2;
            } else {
                top = item.allocation.y + item.allocation.height - (int) vadj.get_page_size();
                top += CheckerboardLayout.ROW_GUTTER_PADDING / 2;
            }

            vadj.set_value(top);

        }
    }

    public override void switched_to() {
        layout.set_in_view(true);
        get_search_view_filter().refresh.connect(on_view_filter_refresh);
        on_view_filter_refresh();

        if (get_view().get_selected_count() > 0) {
            CheckerboardItem? item = (CheckerboardItem?) get_view().get_selected_at(0);

            // if item is in any way out of view, scroll to it
            scroll_to_item(item);
        }

        base.switched_to();
    }

    private void on_view_filter_refresh() {
        update_view_filter_message();
    }

    private void on_contents_altered(Gee.Iterable<DataObject>? added,
        Gee.Iterable<DataObject>? removed) {
        update_view_filter_message();
    }

    private void on_items_state_changed(Gee.Iterable<DataView> changed) {
        update_view_filter_message();
    }

    private void on_items_visibility_changed(Gee.Collection<DataView> changed) {
        update_view_filter_message();
    }

    private void update_view_filter_message() {
        if (get_view().are_items_filtered_out() && get_view().get_count() == 0) {
            set_page_message(get_filter_no_match_message());
        } else if (get_view().get_count() == 0) {
            set_page_message(get_view_empty_message());
        } else {
            unset_page_message();
        }
    }

    public void set_page_message(string message) {
        message_pane.label.label = message;
        try {
            message_pane.icon_image.icon_name = null;
            message_pane.icon_image.gicon = Icon.new_for_string (get_view_empty_icon());
        } catch (Error error) {
            message_pane.icon_image.gicon = null;
            message_pane.icon_image.icon_name = "image-x-generic-symbolic";
        }
        stack.set_visible_child_name ("message");
    }

    public void unset_page_message() {
        stack.set_visible_child (layout);
    }

    public override void set_page_name(string name) {
        base.set_page_name(name);

        layout.set_name(name);
    }

    public CheckerboardItem? get_item_at_pixel(double x, double y) {
        return layout.get_item_at_pixel(x, y);
    }

    private void on_items_hidden(Gee.Iterable<DataView> hidden) {
        foreach (DataView view in hidden) {
            CheckerboardItem item = (CheckerboardItem) view;

            if (anchor == item)
                anchor = null;

            if (current_cursor == item)
                current_cursor = null;

            if (current_hovered_item == item)
                current_hovered_item = null;
        }
    }

    protected bool key_press_event(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        bool handled = true;

        // mask out the modifiers we're interested in
        uint state = event.get_current_event_state() & Gdk.ModifierType.SHIFT_MASK;

        switch (Gdk.keyval_name(keyval)) {
            case "Up":
            case "KP_Up":
                move_cursor(CompassPoint.NORTH);
                select_anchor_to_cursor(state);
            break;

            case "Down":
            case "KP_Down":
                move_cursor(CompassPoint.SOUTH);
                select_anchor_to_cursor(state);
            break;

            case "Left":
            case "KP_Left":
                move_cursor(CompassPoint.WEST);
                select_anchor_to_cursor(state);
            break;

            case "Right":
            case "KP_Right":
                move_cursor(CompassPoint.EAST);
                select_anchor_to_cursor(state);
            break;

            case "Home":
            case "KP_Home":
                CheckerboardItem? first = (CheckerboardItem?) get_view().get_first();
                if (first != null)
                    cursor_to_item(first);
                select_anchor_to_cursor(state);
            break;

            case "End":
            case "KP_End":
                CheckerboardItem? last = (CheckerboardItem?) get_view().get_last();
                if (last != null)
                    cursor_to_item(last);
                select_anchor_to_cursor(state);
            break;

            case "Return":
            case "KP_Enter":
                if (get_view().get_selected_count() == 1)
                    on_item_activated((CheckerboardItem) get_view().get_selected_at(0),
                        Activator.KEYBOARD, KeyboardModifiers(this));
                else
                    handled = false;
            break;

            case "space":
                Marker marker = get_view().mark(layout.get_cursor());
                get_view().toggle_marked(marker);
            break;

            default:
                handled = false;
            break;
        }

        return handled;
    }

    protected override bool on_left_click(Gtk.EventController event, int press, double x, double y) {
        // only interested in single-click and double-clicks for now
        if (press != 1 && press != 2)
            return false;

        // mask out the modifiers we're interested in
        var state = event.get_current_event_state () &
                (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK);

        // use clicks for multiple selection and activation only; single selects are handled by
        // button release, to allow for multiple items to be selected then dragged ...
        CheckerboardItem item = get_item_at_pixel(x, y);
        if (item != null) {
            // ... however, there is no dragging if the user clicks on an interactive part of the
            // CheckerboardItem (e.g. a tag)
            if (layout.handle_left_click(item, x, y, event.get_current_event_state()))
                return true;

            switch (state) {
                case Gdk.ModifierType.CONTROL_MASK:
                    // with only Ctrl pressed, multiple selections are possible ... chosen item
                    // is toggled
                    Marker marker = get_view().mark(item);
                    get_view().toggle_marked(marker);

                    if (item.is_selected()) {
                        anchor = item;
                        current_cursor = item;
                    }
                break;

                case Gdk.ModifierType.SHIFT_MASK:
                    get_view().unselect_all();

                    if (anchor == null)
                        anchor = item;

                    select_between_items(anchor, item);

                    current_cursor = item;
                break;

                case Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK:
                    // Ticket #853 - Make Ctrl + Shift + Mouse Button 1 able to start a new run
                    // of contiguous selected items without unselecting previously-selected items
                    // a la Nautilus.
                    // Same as the case for SHIFT_MASK, but don't unselect anything first.
                    if (anchor == null)
                        anchor = item;

                    select_between_items(anchor, item);

                    current_cursor = item;
                break;

                default:
                    if (press == 2) {
                        activated_item = item;
                    } else {
                        // if the user has selected one or more items and is preparing for a drag,
                        // don't want to blindly unselect: if they've clicked on an unselected item
                        // unselect all and select that one; if they've clicked on a previously
                        // selected item, do nothing
                        if (!item.is_selected()) {
                            Marker all = get_view().start_marking();
                            all.mark_many(get_view().get_selected());

                            get_view().unselect_and_select_marked(all, get_view().mark(item));
                        }
                    }

                    anchor = item;
                    current_cursor = item;
                break;
            }
            layout.set_cursor(item);
        } else {
            // user clicked on "dead" area; only unselect if control is not pressed
            // do we want similar behavior for shift as well?
            if (state != Gdk.ModifierType.CONTROL_MASK)
                get_view().unselect_all();

            // grab previously marked items
            previously_selected = new Gee.ArrayList<CheckerboardItem>();
            foreach (DataView view in get_view().get_selected())
                previously_selected.add((CheckerboardItem) view);

            layout.set_drag_select_origin((int) x, (int) y);

            return true;
        }

        // need to determine if the signal should be passed to the DnD handlers
        // Return true to block the DnD handler, false otherwise

        return get_view().get_selected_count() == 0;
    }

    protected override bool on_left_released(Gtk.EventController event, int press, double x, double y) {
        previously_selected = null;

        // if drag-selecting, stop here and do nothing else
        if (layout.is_drag_select_active()) {
            layout.clear_drag_select();
            anchor = current_cursor;

            return true;
        }

        // only interested in non-modified button releases
        if ((event.get_current_event_state() & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) != 0)
            return false;

        // if the item was activated in the double-click, report it now
        if (activated_item != null) {
            on_item_activated(activated_item, Activator.MOUSE, KeyboardModifiers(this));
            activated_item = null;

            return true;
        }

        CheckerboardItem item = get_item_at_pixel(x, y);
        if (item == null) {
            // released button on "dead" area
            return true;
        }

        if (current_cursor != item) {
            // user released mouse button after moving it off the initial item, or moved from dead
            // space onto one.  either way, unselect everything
            get_view().unselect_all();
        } else {
            // the idea is, if a user single-clicks on an item with no modifiers, then all other items
            // should be deselected, however, if they single-click in order to drag one or more items,
            // they should remain selected, hence performing this here rather than on_left_click
            // (item may not be selected if an unimplemented modifier key was used)
            if (item.is_selected())
                get_view().unselect_all_but(item);
        }

        return true;
    }

    protected override bool on_right_click(Gtk.EventController event, int press, double x, double y) {
        // only interested in single-clicks for now
        if (press != 1)
            return false;

        // get what's right-clicked upon
        CheckerboardItem item = get_item_at_pixel(x, y);
        if (item != null) {
            // mask out the modifiers we're interested in
            switch (event.get_current_event_state() & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) {
                case Gdk.ModifierType.CONTROL_MASK:
                    // chosen item is toggled
                    Marker marker = get_view().mark(item);
                    get_view().toggle_marked(marker);
                break;

                case Gdk.ModifierType.SHIFT_MASK:
                    // TODO
                break;

                case Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK:
                    // TODO
                break;

                default:
                    // if the item is already selected, proceed; if item is not selected, a bare right
                    // click unselects everything else but it
                    if (!item.is_selected()) {
                        Marker all = get_view().start_marking();
                        all.mark_many(get_view().get_selected());

                        get_view().unselect_and_select_marked(all, get_view().mark(item));
                    }
                break;
            }
        } else {
            // clicked in "dead" space, unselect everything
            get_view().unselect_all();
        }

        Gtk.PopoverMenu context_menu = get_context_menu();
        return popup_context_menu(context_menu, x, y);
    }

    protected virtual bool on_mouse_over(CheckerboardItem? item, int x, int y, Gdk.ModifierType mask) {
        if (item != null)
            layout.handle_mouse_motion(item, x, y, mask);

        // if hovering over the last hovered item, or both are null (nothing highlighted and
        // hovering over empty space), do nothing
        if (item == current_hovered_item)
            return true;

        // either something new is highlighted or now hovering over empty space, so dim old item
        if (current_hovered_item != null) {
            current_hovered_item.handle_mouse_leave();
            current_hovered_item = null;
        }

        // if over empty space, done
        if (item == null)
            return true;

        // brighten the new item
        current_hovered_item = item;
        current_hovered_item.handle_mouse_enter();

        return true;
    }

    protected override bool on_motion(Gtk.EventControllerMotion event, double x, double y, Gdk.ModifierType mask) {
        // report what item the mouse is hovering over
        if (!on_mouse_over(get_item_at_pixel(x, y), (int)x, (int)y, mask))
            return false;

        // go no further if not drag-selecting
        if (!layout.is_drag_select_active())
            return false;

        // set the new endpoint of the drag selection
        layout.set_drag_select_endpoint((int)x, (int)y);

        updated_selection_band();

        // if out of bounds, schedule a check to auto-scroll the viewport
        if (!autoscroll_scheduled 
            && get_adjustment_relation(scrolled.get_vadjustment(), (int)y) != AdjustmentRelation.IN_RANGE) {
            Timeout.add(AUTOSCROLL_TICKS_MSEC, selection_autoscroll);
            autoscroll_scheduled = true;
        }

        // return true to stop a potential drag-and-drop operation
        return true;
    }

    private void updated_selection_band() {
        assert(layout.is_drag_select_active());

        // get all items inside the selection
        Gee.List<CheckerboardItem>? intersection = layout.items_in_selection_band();
        if (intersection == null)
            return;

        Marker to_unselect = get_view().start_marking();
        Marker to_select = get_view().start_marking();

        // mark all selected items to be unselected
        to_unselect.mark_many(get_view().get_selected());

        // except for the items that were selected before the drag began
        assert(previously_selected != null);
        to_unselect.unmark_many(previously_selected);        
        to_select.mark_many(previously_selected);   

        // toggle selection on everything in the intersection and update the cursor
        current_cursor = null;

        foreach (CheckerboardItem item in intersection) {
            if (to_select.toggle(item))
                to_unselect.unmark(item);
            else
                to_unselect.mark(item);

            if (current_cursor == null)
                current_cursor = item;
        }

        get_view().select_marked(to_select);
        get_view().unselect_marked(to_unselect);
    }

    private bool selection_autoscroll() {
        if (!layout.is_drag_select_active()) { 
            autoscroll_scheduled = false;

            return false;
        }

        // as the viewport never scrolls horizontally, only interested in vertical
        Gtk.Adjustment vadj = scrolled.get_vadjustment();

        double x, y;
        Gdk.ModifierType mask;
        get_event_source_pointer(out x, out y, out mask);

        int new_value = (int) vadj.get_value();
        switch (get_adjustment_relation(vadj, y)) {
            case AdjustmentRelation.BELOW:
                // pointer above window, scroll up
                new_value -= AUTOSCROLL_PIXELS;
                layout.set_drag_select_endpoint(x, new_value);
            break;

            case AdjustmentRelation.ABOVE:
                // pointer below window, scroll down, extend selection to bottom of page
                new_value += AUTOSCROLL_PIXELS;
                layout.set_drag_select_endpoint(x, new_value + (int) vadj.get_page_size());
            break;

            case AdjustmentRelation.IN_RANGE:
                autoscroll_scheduled = false;

                return false;

            default:
                warn_if_reached();
            break;
        }

        // It appears that in GTK+ 2.18, the adjustment is not clamped the way it was in 2.16.
        // This may have to do with how adjustments are different w/ scrollbars, that they're upper
        // clamp is upper - page_size ... either way, enforce these limits here
        vadj.set_value(new_value.clamp((int) vadj.get_lower(), 
            (int) vadj.get_upper() - (int) vadj.get_page_size()));

        updated_selection_band();

        return true;
    }

    public void cursor_to_item(CheckerboardItem item) {
        assert(get_view().contains(item));

        current_cursor = item;

        if (!get_ctrl_pressed()) {
            get_view().unselect_all();
            Marker marker = get_view().mark(item);
            get_view().select_marked(marker);
        }
        layout.set_cursor(item);
        scroll_to_item(item);
    }

    public void move_cursor(CompassPoint point) {
        // if no items, nothing to do
        if (get_view().get_count() == 0)
            return;

        // if there is no better starting point, simply select the first and exit
        // The right half of the or is related to Bug #732334, the cursor might be non-null and still not contained in
        // the view, if the user dragged a full screen Photo off screen
        if (current_cursor == null && layout.get_cursor() == null || current_cursor != null && !get_view().contains(current_cursor)) {
            CheckerboardItem item = layout.get_item_at_coordinate(0, 0);
            cursor_to_item(item);
            anchor = item;

            return;
        }

        if (current_cursor == null) {
            current_cursor = layout.get_cursor() as CheckerboardItem;
        }

        // move the cursor relative to the "first" item
        CheckerboardItem? item = layout.get_item_relative_to(current_cursor, point);
        if (item != null)
            cursor_to_item(item);
   }

    public new void set_cursor(CheckerboardItem item) {
        Marker marker = get_view().mark(item);
        get_view().select_marked(marker);

        current_cursor = item;
        anchor = item;
   }

    public void select_between_items(CheckerboardItem item_start, CheckerboardItem item_end) {
        Marker marker = get_view().start_marking();

        bool passed_start = false;
        bool passed_end = false;

        foreach (DataObject object in get_view().get_all()) {
            CheckerboardItem item = (CheckerboardItem) object;

            if (item_start == item)
                passed_start = true;

            if (item_end == item)
                passed_end = true;

            if (passed_start || passed_end)
                marker.mark((DataView) object);

            if (passed_start && passed_end)
                break;
        }

        get_view().select_marked(marker);
    }

    public void select_anchor_to_cursor(uint state) {
        if (current_cursor == null || anchor == null)
            return;

        if (state == Gdk.ModifierType.SHIFT_MASK) {
            get_view().unselect_all();
            select_between_items(anchor, current_cursor);
        } else {
            anchor = current_cursor;
        }
    }

    protected virtual void set_display_titles(bool display) {
        get_view().freeze_notifications();
        get_view().set_property(CheckerboardItem.PROP_SHOW_TITLES, display);
        get_view().thaw_notifications();
    }

    protected virtual void set_display_comments(bool display) {
        get_view().freeze_notifications();
        get_view().set_property(CheckerboardItem.PROP_SHOW_COMMENTS, display);
        get_view().thaw_notifications();
    }
}


