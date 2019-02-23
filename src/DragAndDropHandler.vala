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
    private enum TargetType {
        XDS,
        MEDIA_LIST
    }

    private const Gtk.TargetEntry[] SOURCE_TARGET_ENTRIES = {
        { "XdndDirectSave0", Gtk.TargetFlags.OTHER_APP, TargetType.XDS },
        { "shotwell/media-id-atom", Gtk.TargetFlags.SAME_APP, TargetType.MEDIA_LIST }
    };

    private static Gdk.Atom? XDS_ATOM = null;
    private static Gdk.Atom? TEXT_ATOM = null;
    private static uint8[]? XDS_FAKE_TARGET = null;

    private weak Page page;
    private Gtk.Widget event_source;
    private File? drag_destination = null;
    private ExporterUI exporter = null;

    public DragAndDropHandler(Page page) {
        this.page = page;
        this.event_source = page.get_event_source();
        assert(event_source != null);
        assert(event_source.get_has_window());

        // Need to do this because static member variables are not properly handled
        if (XDS_ATOM == null)
            XDS_ATOM = Gdk.Atom.intern_static_string("XdndDirectSave0");

        if (TEXT_ATOM == null)
            TEXT_ATOM = Gdk.Atom.intern_static_string("text/plain");

        if (XDS_FAKE_TARGET == null)
            XDS_FAKE_TARGET = string_to_uchar_array("shotwell.txt");

        // register what's available on this DnD Source
        Gtk.drag_source_set(event_source, Gdk.ModifierType.BUTTON1_MASK, SOURCE_TARGET_ENTRIES,
            Gdk.DragAction.COPY);

        // attach to the event source's DnD signals, not the Page's, which is a NO_WINDOW widget
        // and does not emit them
        event_source.drag_begin.connect(on_drag_begin);
        event_source.drag_data_get.connect(on_drag_data_get);
        event_source.drag_end.connect(on_drag_end);
        event_source.drag_failed.connect(on_drag_failed);
    }

    ~DragAndDropHandler() {
        if (event_source != null) {
            event_source.drag_begin.disconnect(on_drag_begin);
            event_source.drag_data_get.disconnect(on_drag_data_get);
            event_source.drag_end.disconnect(on_drag_end);
            event_source.drag_failed.disconnect(on_drag_failed);
        }

        page = null;
        event_source = null;
    }

    private void on_drag_begin(Gdk.DragContext context) {
        debug("on_drag_begin (%s)", page.get_page_name());

        if (page == null || page.get_view().get_selected_count() == 0 || exporter != null)
            return;

        drag_destination = null;

        // use the first media item as the icon
        ThumbnailSource thumb = (ThumbnailSource) page.get_view().get_selected_at(0).get_source();

        try {
            Gdk.Pixbuf icon = thumb.get_thumbnail(AppWindow.DND_ICON_SCALE);
            Gtk.drag_source_set_icon_pixbuf(event_source, icon);
        } catch (Error err) {
            warning("Unable to fetch icon for drag-and-drop from %s: %s", thumb.to_string(),
                err.message);
        }

        // set the XDS property to indicate an XDS save is available
        Gdk.property_change(context.get_source_window(), XDS_ATOM, TEXT_ATOM, 8, Gdk.PropMode.REPLACE,
            XDS_FAKE_TARGET, 1);
    }

    private void on_drag_data_get(Gdk.DragContext context, Gtk.SelectionData selection_data,
        uint target_type, uint time) {
        debug("on_drag_data_get (%s)", page.get_page_name());

        if (page == null || page.get_view().get_selected_count() == 0)
            return;

        switch (target_type) {
            case TargetType.XDS:
                // Fetch the XDS property that has been set with the destination path
                uchar[] data = new uchar[4096];
                Gdk.Atom actual_type;
                int actual_format = 0;
                bool fetched = Gdk.property_get(context.get_source_window(), XDS_ATOM, TEXT_ATOM,
                    0, data.length, 0, out actual_type, out actual_format, out data);

                // the destination path is actually for our XDS_FAKE_TARGET, use its parent
                // to determine where the file(s) should go
                if (fetched && data != null && data.length > 0)
                    drag_destination = File.new_for_uri(uchar_array_to_string(data)).get_parent();

                debug("on_drag_data_get (%s): %s", page.get_page_name(),
                    (drag_destination != null) ? drag_destination.get_path() : "(no path)");

                // Set the property to "S" for Success or "E" for Error
                selection_data.set(XDS_ATOM, 8,
                    string_to_uchar_array((drag_destination != null) ? "S" : "E"));
            break;

            case TargetType.MEDIA_LIST:
                Gee.Collection<MediaSource> sources =
                    (Gee.Collection<MediaSource>) page.get_view().get_selected_sources();

                // convert the selected media sources to Gdk.Atom-encoded sourceID strings for
                // internal drag-and-drop
                selection_data.set(Gdk.Atom.intern_static_string("SourceIDAtom"), (int) sizeof(Gdk.Atom),
                    serialize_media_sources(sources));
            break;

            default:
                warning("on_drag_data_get (%s): unknown target type %u", page.get_page_name(),
                    target_type);
            break;
        }
    }

    private void on_drag_end() {
        debug("on_drag_end (%s)", page.get_page_name());

        if (page == null || page.get_view().get_selected_count() == 0 || drag_destination == null
            || exporter != null) {
            return;
        }

        debug("Exporting to %s", drag_destination.get_path());

        // drag-and-drop export doesn't pop up an export dialog, so use what are likely the
        // most common export settings (the current -- or "working" -- file format, with
        // all transformations applied, at the image's original size).
        if (drag_destination.get_path() != null) {
            exporter = new ExporterUI(new Exporter(
                (Gee.Collection<Photo>) page.get_view().get_selected_sources(),
                drag_destination, Scaling.for_original(), ExportFormatParameters.current()));
            exporter.export(on_export_completed);
        } else {
            AppWindow.error_message(_("Photos cannot be exported to this directory."));
        }

        drag_destination = null;
    }

    private bool on_drag_failed(Gdk.DragContext context, Gtk.DragResult drag_result) {
        debug("on_drag_failed (%s): %d", page.get_page_name(), (int) drag_result);

        if (page == null)
            return false;

        drag_destination = null;

        return false;
    }

    private void on_export_completed() {
        exporter = null;
    }

}
