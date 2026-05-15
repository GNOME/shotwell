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

    private class ContentProvider : Gdk.ContentProvider {
        private Gee.Collection<MediaSource> data;
        private Gee.ArrayList<File> serialized_files = new Gee.ArrayList<File>(file_equal);

        public ContentProvider(Gee.Collection<MediaSource> sources) {
            Object();

            this.data = sources;
        }

        ~ContentProvider() {
            foreach (var file in serialized_files) {
                try {
                    file.delete(null);
                } catch (Error err) {
                    warning("Failed to remove temporary file %s: %s", file.get_path(), err.message);
                }
            }
        }

        public override Gdk.ContentFormats ref_formats() {
            return new Gdk.ContentFormats({"text/uri-list"});
        }

        public async string? serialize_for_dnd(MediaSource source, int io_priority, Cancellable? cancellable) throws Error {
            if (source is LibraryPhoto) {

                // Shortcut. If we do not have anything changed on it, just pass on the original URI
                var photo = (LibraryPhoto)source;
                if (!photo.is_export_required(Scaling.for_original(), photo.get_file_format())) {
                    return photo.get_master_file().get_uri();
                }

                string basename;
                string extension;

                disassemble_filename(source.get_basename(), out basename, out extension);
                var file = AppDirs.get_temp_dir().get_child("dnd-%s.%s".printf(GLib.Uuid.string_random(), extension));
                yield photo.export_async(file, Scaling.for_original(), Jpeg.Quality.MAXIMUM, photo.get_file_format(), io_priority, cancellable);
                this.serialized_files.add(file);

                return file.get_uri();
            } else if (source is Video) {
                string basename;
                string extension;

                disassemble_filename(source.get_basename(), out basename, out extension);
                var file = AppDirs.get_temp_dir().get_child("dnd-%s.%s".printf(GLib.Uuid.string_random(), extension));
                var video = (Video)source;
                yield video.export_async(file, io_priority, cancellable);
            } else {
                warning("Unknown MediaSource type: %s", source.get_type().name());
            }

            return null;
        }

        public override async bool write_mime_type_async(string mime_type, GLib.OutputStream ostream,
                int io_priority, GLib.Cancellable? cancellable) throws Error {
            if (mime_type != "text/uri-list") {
                throw new GLib.IOError.NOT_SUPPORTED("MIME type %s is currently not supported".printf(mime_type));
            }
            
            var builder = new StringBuilder();
            foreach (var source in data) {
                yield serialize_for_dnd(source, io_priority, cancellable);
                builder.append(source.get_master_file().get_uri());
                builder.append("\r\n");
            }
            if (builder.len > 2) {
                builder.erase(builder.len - 2, -1);
            }

            size_t bytes_written;
            return yield ostream.write_all_async(builder.data, io_priority, cancellable, out bytes_written);
        }
    }

    private unowned Page page;
    private Gtk.Widget event_source;
    public DragAndDropHandler(Page page) {
        this.page = page;
        this.event_source = page.get_event_source();
        assert(event_source != null);

        var drag_source = new Gtk.DragSource();
        drag_source.set_name("Shotwell drag source for %s".printf(page.get_name()));
        drag_source.set_actions(Gdk.DragAction.COPY);

        drag_source.drag_begin.connect(on_drag_begin);
        drag_source.prepare.connect(on_drag_prepare);
        drag_source.drag_cancel.connect(on_drag_cancel);


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

    private bool on_drag_cancel(Gtk.DragSource source, Gdk.Drag drag, Gdk.DragCancelReason reason) {
        print("Drag was cancelled : %s\n", reason.to_string());
        return false;
    }

    private Gdk.ContentProvider? on_drag_prepare(Gtk.DragSource source, double x, double y) {
        var sources = (Gee.Collection<MediaSource>)page.get_view().get_selected_sources();
        Value v;
        v = new MediaListWrapper(sources);
        return new Gdk.ContentProvider.union({new Gdk.ContentProvider.for_value(v), new ContentProvider(sources)});
    }

}
