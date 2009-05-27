
public class BatchImport {
    private class DateComparator : Comparator<int64?> {
        private PhotoTable photo_table;
        
        public DateComparator(PhotoTable photo_table) {
            this.photo_table = photo_table;
        }
        
        public override int64 compare(int64? ida, int64? idb) {
            time_t timea = photo_table.get_exposure_time(PhotoID(ida));
            time_t timeb = photo_table.get_exposure_time(PhotoID(idb));
            
            return timea - timeb;
        }
    }
    
    private string[] uris;
    private BatchImport ref_holder = null;
    private PhotoTable photo_table = new PhotoTable();
    private SortedList<int64?> imported_photos = null;
    private Gee.ArrayList<string> import_failed = null;
    private ImportID import_id = ImportID();
    
    public static File? create_library_path(string filename, Exif.Data? exif, time_t ts, out bool collision) {
        File dir = AppWindow.get_photos_dir();
        time_t timestamp = ts;
        
        // use EXIF exposure timestamp over the supplied one (which probably comes from the file's
        // modified time, or is simply now())
        if (exif != null) {
            Exif.Entry entry = Exif.find_first_entry(exif, Exif.Tag.DATE_TIME_ORIGINAL, Exif.Format.ASCII);
            if (entry != null) {
                string datetime = entry.get_value();
                if (datetime != null) {
                    time_t stamp;
                    if (Exif.convert_datetime(datetime, out stamp)) {
                        timestamp = stamp;
                    }
                }
            }
        }
        
        // if no timestamp, use now()
        if (timestamp == 0)
            timestamp = time_t();
        
        Time tm = Time.local(timestamp);
        
        // build a directory tree inside the library:
        // yyyy/mm/dd
        dir = dir.get_child("%04u".printf(tm.year + 1900));
        dir = dir.get_child("%02u".printf(tm.month + 1));
        dir = dir.get_child("%02u".printf(tm.day));
        
        try {
            if (dir.query_exists(null) == false)
                dir.make_directory_with_parents(null);
        } catch (Error err) {
            error("Unable to create photo library directory %s", dir.get_path());
        }
        
        // if file doesn't exist, use that and done
        File file = dir.get_child(filename);
        if (!file.query_exists(null)) {
            collision = false;

            return file;
        }

        collision = true;

        string name, ext;
        disassemble_filename(file.get_basename(), out name, out ext);

        // generate a unique filename
        for (int ctr = 1; ctr < int.MAX; ctr++) {
            string new_name = (ext != null) ? "%s_%d.%s".printf(name, ctr, ext) : "%s_%d".printf(name, ctr);

            file = dir.get_child(new_name);
            
            if (!file.query_exists(null))
                return file;
        }
        
        return null;
    }

    public BatchImport(string[] uris) {
        this.uris = uris;
    }
    
    public void schedule() {
        // XXX: This is necessary because Idle.add doesn't ref SourceFunc:
        // http://bugzilla.gnome.org/show_bug.cgi?id=548427
        this.ref_holder = this;

        Idle.add(on_import_uris);
    }

    private bool on_import_uris() {
        imported_photos = new SortedList<int64?>(new Gee.ArrayList<int64?>(), new DateComparator(photo_table));
        import_failed = new Gee.ArrayList<string>();
        import_id = photo_table.generate_import_id();

        // import one at a time
        foreach (string uri in uris)
            import(File.new_for_uri(uri));
        
        // report errors, if any
        // TODO: More informative dialog box
        if (import_failed.size > 0)
            AppWindow.error_message("Unable to import %d photos".printf(import_failed.size));

        // report all new photos to AppWindow
        AppWindow.get_instance().batch_import_complete(imported_photos);

        // XXX: unref "this" ... vital that the self pointer is not touched from here on out
        ref_holder = null;
        
        return false;
    }

    private void import(File file) {
        FileType type = file.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        
        bool imported = false;
        switch (type) {
            case FileType.DIRECTORY:
                imported = import_dir(file);
            break;
            
            case FileType.REGULAR:
                imported = import_file(file);
            break;
            
            default:
                debug("Skipping file %s (neither a directory nor a file)", file.get_path());
            break;
        }
        
        if (!imported)
            import_failed.add(file.get_path());
    }
    
    private bool import_dir(File dir) {
        try {
            FileEnumerator enumerator = dir.enumerate_children("*",
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
            if (enumerator == null)
                return false;
            
            if (!spin_event_loop())
                return false;

            FileInfo info = null;
            while ((info = enumerator.next_file(null)) != null) {
                import(dir.get_child(info.get_name()));
            }
        } catch (Error err) {
            debug("Unable to import from %s: %s", dir.get_path(), err.message);
            
            return false;
        }
        
        return true;
    }
    
    private bool import_file(File file) {
        Photo photo = Photo.import(file, import_id);
        if (photo == null)
            return false;

        if (!spin_event_loop())
            return false;

        // add to imported list for splitting into events
        PhotoID photo_id = photo.get_photo_id();
        imported_photos.add(photo_id.id);
        
        // report to AppWindow for it to disseminate
        AppWindow.get_instance().photo_imported(photo);
        
        return true;
    }
}

