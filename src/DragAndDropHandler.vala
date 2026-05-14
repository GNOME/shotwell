/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

//
// DragAndDropHandler attaches signals to a Page to properly handle drag-and-drop requests for the
// Page as a DnD Source.  (DnD Destination handling is handled by the appropriate AppWindow, i.e.
// LibraryWindow and DirectWindow). Assumes the Page's ViewCollection holds MediaSources.
//
public class DragAndDropHandler {
    public class MediaListWrapper : Object {
        private Gee.Collection<MediaSource> data;

        public MediaListWrapper(Gee.Collection<MediaSource> data) {
            Object();

            this.data = data;
        }

        public Gee.Collection<MediaSource> unwrap() {
            return data;
        }
    }

    private unowned Page page;
    private Gtk.Widget event_source;
    public DragAndDropHandler(Page page) {
        this.page = page;
        this.event_source = page.get_event_source();
        assert(event_source != null);

        var drag_source = new Gtk.DragSource();
        drag_source.set_actions(Gdk.DragAction.COPY);

        drag_source.drag_begin.connect(on_drag_begin);
        drag_source.prepare.connect(on_drag_prepare);


        // attach to the event source's DnD signals, not the Page's, which is a NO_WINDOW widget
        // and does not emit them
        event_source.add_controller(drag_source);
    }

    ~DragAndDropHandler() {
        page = null;
        event_source = null;
    }

    private void on_drag_begin(Gtk.DragSource drag_source, Gdk.Drag drag) {
        debug("on_drag_begin (%s)", page?.get_page_name());

        if (page == null || page.get_view().get_selected_count() == 0) {
            return;
        }

        var thumb = (ThumbnailSource) page.get_view().get_selected_at(0).get_source();
        try {
            var icon = thumb.get_thumbnail(AppWindow.DND_ICON_SCALE);
            var texture = Gdk.Texture.for_pixbuf (icon);
            drag_source.set_icon(texture, 0, 0);
        } catch (Error err) {
            warning("Unable to fetch icon for drag-and-drop from %s: %s", thumb.to_string(), err.message);
        }
    }

    private Gdk.ContentProvider? on_drag_prepare(Gtk.DragSource source, double x, double y) {
        var sources = (Gee.Collection<MediaSource>)page.get_view().get_selected_sources();
        Value v;
        v = new MediaListWrapper(sources);
        return new Gdk.ContentProvider.for_value(v);
    }

}
