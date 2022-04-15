// SPDX-License-Identifier: LGPL-2.1-or-later
//
// PageWindow is a Gtk.Window with essential functions for hosting a Page.  There may be more than
// one PageWindow in the system, and closing one does not imply exiting the application.
//
// PageWindow offers support for hosting a single Page; multiple Pages must be handled by the
// subclass.  A subclass should set current_page to the user-visible Page for it to receive
// various notifications.  It is the responsibility of the subclass to notify Pages when they're
// switched to and from, and other aspects of the Page interface.
public abstract class PageWindow : Gtk.ApplicationWindow {
    private Page current_page = null;
    private int busy_counter = 0;
    
    protected virtual void switched_pages(Page? old_page, Page? new_page) {
    }
    
    protected PageWindow() {
        Object (application: Application.get_instance().get_system_app ());

        // the current page needs to know when modifier keys are pressed
        #if 0
        add_events(Gdk.EventMask.KEY_PRESS_MASK | Gdk.EventMask.KEY_RELEASE_MASK
            | Gdk.EventMask.STRUCTURE_MASK);
            #endif
        set_show_menubar (true);

        notify["maximized"].connect(synthesize_configure_event);
        notify["default-width"].connect(synthesize_configure_event);
        notify["default-height"].connect(synthesize_configure_event);
        notify["fullscreened"].connect(synthesize_configure_event);
    }

    private void synthesize_configure_event() {
        int width = get_surface().get_width();
        int height = get_surface().get_height();
        configure_event(width, height);
    }

    public virtual bool configure_event(int width, int height) {
        if (current_page != null) {
            if (current_page.notify_configure_event(width, height))
                return true;
        }      
        
        return false;
    }
    
    public Page? get_current_page() {
        return current_page;
    }
    
    public virtual void set_current_page(Page page) {
        if (current_page != null)
            current_page.clear_container();
        
        Page? old_page = current_page;
        current_page = page;
        current_page.set_container(this);
        
        switched_pages(old_page, page);
    }
    
    public virtual void clear_current_page() {
        if (current_page != null)
            current_page.clear_container();
        
        Page? old_page = current_page;
        current_page = null;
        
        switched_pages(old_page, null);
    }
    
    #if 0
    public override bool key_press_event(Gdk.EventKey event) {
        if (get_focus() is Gtk.Entry && get_focus().key_press_event(event))
            return true;
        
        if (current_page != null && current_page.notify_app_key_pressed(event))
            return true;
        
        return (base.key_press_event != null) ? base.key_press_event(event) : false;
    }
    
    public override bool key_release_event(Gdk.EventKey event) {
        if (get_focus() is Gtk.Entry && get_focus().key_release_event(event))
            return true;
       
        if (current_page != null && current_page.notify_app_key_released(event))
                return true;
        
        return (base.key_release_event != null) ? base.key_release_event(event) : false;
    }

    public override bool focus_in_event(Gdk.EventFocus event) {
        if (current_page != null && current_page.notify_app_focus_in(event))
                return true;
        
        return (base.focus_in_event != null) ? base.focus_in_event(event) : false;
    }

    public override bool focus_out_event(Gdk.EventFocus event) {
        if (current_page != null && current_page.notify_app_focus_out(event))
                return true;
        
        return (base.focus_out_event != null) ? base.focus_out_event(event) : false;
    }
    #endif

    public void set_busy_cursor() {
        if (busy_counter++ > 0)
            return;

        set_cursor (new Gdk.Cursor.from_name ("wait", null));
    }
    
    public void set_normal_cursor() {
        if (busy_counter <= 0) {
            busy_counter = 0;
            return;
        } else if (--busy_counter > 0) {
            return;
        }

        set_cursor (new Gdk.Cursor.from_name ("default", null));
    }
}
