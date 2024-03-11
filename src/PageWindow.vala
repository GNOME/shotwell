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
    private Spit.Publishing.Publishable[] publishables = null;

    protected virtual void switched_pages(Page? old_page, Page? new_page) {}

    protected PageWindow() {
        Object(application: Application.get_instance().get_system_app());

        notify["maximized"].connect(synthesize_configure_event);
        notify["default-width"].connect(synthesize_configure_event);
        notify["default-height"].connect(synthesize_configure_event);
        notify["fullscreened"].connect(synthesize_configure_event);

        var key_controller = new Gtk.EventControllerKey();
        key_controller.key_pressed.connect(key_press_event);
        key_controller.key_released.connect(key_release_event);
        ((Gtk.Widget)this).add_controller(key_controller);

        var focus_controller = new Gtk.EventControllerFocus();
        focus_controller.enter.connect(focus_in_event);
        ((Gtk.Widget)this).add_controller(focus_controller);

        // for drag and drop START
        var drag_source = new Gtk.DragSource ();
        drag_source.prepare.connect ((source_origin, x, y) => {
            GLib.File[] filelist = new GLib.File[0];
            publishables = new Spit.Publishing.Publishable[0];
            Gee.List<MediaSource> media_sources = (Gee.List<MediaSource>) current_page.get_view().get_selected_sources();

            var content_major_axis = -1;
            var strip_metadata = false;
            GLib.File? serialized_file = null; 

            foreach (MediaSource media in media_sources) {
                Spit.Publishing.Publishable publishable =
                    new Publishing.Glue.MediaSourcePublishableWrapper(media);
                try {
                    global::Publishing.Glue.MediaSourcePublishableWrapper wrapper =
                        (global::Publishing.Glue.MediaSourcePublishableWrapper) publishable;
                    serialized_file = wrapper.serialize_for_publishing(content_major_axis, strip_metadata);
                    if (serialized_file != null){
                        publishables += publishable;
                        filelist += serialized_file;
                    } else {
                        wrapper.clean_up();
                    }
                } catch (Spit.Publishing.PublishingError err) {
                    return null;
                }
            }
            var gdk_filelist = new Gdk.FileList.from_array(filelist);
            Gdk.ContentProvider cp = new Gdk.ContentProvider.for_value(gdk_filelist);
            return cp;
        });
        drag_source.drag_begin.connect ((source_origin, drag) => {
        });
        drag_source.drag_end.connect ((source_origin, drag, delete_data) => {
            foreach (Spit.Publishing.Publishable publishable in publishables){
                ((global::Publishing.Glue.MediaSourcePublishableWrapper) publishable).clean_up();
            }
        });
        drag_source.drag_cancel.connect ((source_origin, drag, reason) => {
            return false;
        });
        ((Gtk.Widget)this).add_controller(drag_source);
        // for drag and drop END
    }

    private void synthesize_configure_event() {
        int width = 0;
        int height = 0;
        if (get_surface() != null) {
            width = get_surface().get_width();
            height = get_surface().get_height();
        } else {
            Gtk.Allocation allocation;
            get_allocation (out allocation);
            width = allocation.width;
            height = allocation.height;
        }
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

    public virtual bool key_press_event(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        if ((get_focus() is Gtk.Entry) && event.forward(get_focus())) 
            return true;

        if (current_page != null && current_page.notify_app_key_pressed(event, keyval, keycode, modifiers))
            return true;

        return false;
    }

    public void key_release_event(Gtk.EventControllerKey event, uint keyval, uint keycode, Gdk.ModifierType modifiers) {
        if ((get_focus() is Gtk.Entry) && event.forward(get_focus()))
            return;

        if (current_page != null)
            current_page.notify_app_key_released(event, keyval, keycode, modifiers);
    }

    public void focus_in_event(Gtk.EventControllerFocus event) {
        if (current_page != null)
            current_page.notify_app_focus_in();
    }

    public void set_busy_cursor() {
        if (busy_counter++ > 0)
            return;

        set_cursor_from_name("wait");
    }

    public void set_normal_cursor() {
        if (busy_counter <= 0) {
            busy_counter = 0;
            return;
        } else if (--busy_counter > 0) {
            return;
        }

        set_cursor_from_name(null);
    }
}
