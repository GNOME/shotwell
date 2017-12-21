/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class DirectPhoto : Photo {
    private const int PREVIEW_BEST_FIT = 360;
    
    public static DirectPhotoSourceCollection global = null;
    
    public signal void can_rotate_changed(bool b);
    
    private Gdk.Pixbuf preview = null;
    private bool loaded = false;
    
    private DirectPhoto(PhotoRow row) {
        base (row);
    }

    /**
     * @brief Because all transformations are discarded on reimport by design, including
     * Orientation, a JFIF file that is only rotated or flipped, then saved, has the orientation
     * change the user made before saving removed (recall that fetch() remembers which images it
     * has seen before and will only add a file to the file map once; every time it sees it
     * again after this is considered a reimport). This will set the orientation to the
     * specified value, fixing up both the row and the backing row.
     *
     * @warning Only reimported JFIF files should need this; non-lossy image types have their
     * actual pixels physically rotated in the file when they're exported.
     *
     * @param dest The orientation to set the photo to; usually, this should be a value
     * obtained by calling get_orientation() prior to export()ing a DirectPhoto.
     */
    public void fixup_orientation_after_reimport(Orientation dest) {
        row.orientation = dest;
        backing_photo_row.original_orientation = dest;
    }

    public static void init(File initial_file) {
        init_photo();
        
        global = new DirectPhotoSourceCollection(initial_file);
        DirectPhoto photo;
        string? reason = global.fetch(initial_file, out photo, false);
        if (reason != null)
            warning("fetch error: %s", reason);
        global.add(photo);
    }
    
    public static void terminate() {
        terminate_photo();
    }

    // Gets the dimensions of this photo's pixbuf when scaled to original
    // size and saves them where get_raw_dimensions can find them.
    private void save_dims() {
        try {                                                                       
            backing_photo_row.dim = Dimensions.for_pixbuf(get_pixbuf_with_options(Scaling.for_original(),
                Exception.CROP | Exception.STRAIGHTEN | Exception.ORIENTATION));
        } catch (Error e) {
            warning("Dimensions for image %s could not be gotten.", to_string());
        }
    }
    
    // Loads a photo on demand.
    public ImportResult demand_load() {
        if (loaded) {
            save_dims();
            return ImportResult.SUCCESS;
        }

        Photo.ReimportMasterState reimport_state;
        try {
            prepare_for_reimport_master(out reimport_state);
            finish_reimport_master(reimport_state);
        } catch (Error err) {
            warning("Database error on re-importing image: %s", err.message);
            return ImportResult.DATABASE_ERROR;
        }

        loaded = true;
        save_dims();
        return ImportResult.SUCCESS;
    }
    
    // This method should only be called by DirectPhotoSourceCollection.  Use
    // DirectPhoto.global.fetch to import files into the system.
    public static ImportResult internal_import(File file, out DirectPhoto photo) {
        PhotoImportParams params = new PhotoImportParams.create_placeholder(file, ImportID.generate());
        Photo.create_pre_import(params);
        PhotoTable.get_instance().add(params.row);
        
        photo = new DirectPhoto(params.row);
        
        return ImportResult.SUCCESS;
    }
    
    public override Gdk.Pixbuf get_preview_pixbuf(Scaling scaling) throws Error {
        if (preview == null) {
            preview = get_thumbnail(PREVIEW_BEST_FIT);

            if (preview == null)
                preview = get_pixbuf(scaling);
        }

        return scaling.perform_on_pixbuf(preview, Gdk.InterpType.BILINEAR, true);
    }
    
    public override void rotate(Rotation rotation) {
        can_rotate_now = false;
        can_rotate_changed(false);
        base.rotate(rotation);
    }

    public override Gdk.Pixbuf get_pixbuf(Scaling scaling) throws Error {
        Gdk.Pixbuf ret = base.get_pixbuf(scaling);
        can_rotate_changed(true);
        can_rotate_now = true;
        return ret;
    }

    public override Gdk.Pixbuf? get_thumbnail(int scale) throws Error {
        var metadata = get_metadata();

        return (metadata == null || metadata.get_preview_count() == 0) ? null :
            get_orientation().rotate_pixbuf(metadata.get_preview(0).get_pixbuf());
    }

    protected override void notify_altered(Alteration alteration) {
        preview = null;
        
        base.notify_altered(alteration);
    }

    protected override bool has_user_generated_metadata() {
        // TODO: implement this method
        return false;
    }

    protected override void set_user_metadata_for_export(PhotoMetadata metadata) {
        // TODO: implement this method, see ticket
    }
    
    protected override void apply_user_metadata_for_reimport(PhotoMetadata metadata) {
    }

    public override bool is_trashed() {
        // always returns false -- direct-edit mode has no concept of the trash can
        return false;
    }
    
    public override bool is_offline() {
        // always returns false -- direct-edit mode has no concept of offline photos
        return false;
    }
    
    public override void trash() {
        // a no-op -- direct-edit mode has no concept of the trash can
    }
    
    public override void untrash() {
        // a no-op -- direct-edit mode has no concept of the trash can
    }

    public override void mark_offline() {
        // a no-op -- direct-edit mode has no concept of offline photos
    }
    
    public override void mark_online() {
        // a no-op -- direct-edit mode has no concept of offline photos
    }
}

public class DirectPhotoSourceCollection : DatabaseSourceCollection {
    private const int DISCOVERED_FILES_BATCH_ADD = 500;
    private Gee.Collection<DirectPhoto> prepared_photos = new Gee.ArrayList<DirectPhoto>();
    private Gee.HashMap<File, DirectPhoto> file_map = new Gee.HashMap<File, DirectPhoto>(file_hash, 
        file_equal);
    private DirectoryMonitor monitor;
    
    public DirectPhotoSourceCollection(File initial_file) {
        base("DirectPhotoSourceCollection", get_direct_key);
        
        // only use the monitor for discovery in the specified directory, not its children
        monitor = new DirectoryMonitor(initial_file.get_parent(), false, false);
        monitor.file_discovered.connect(on_file_discovered);
        monitor.discovery_completed.connect(on_discovery_completed);
        
        monitor.start_discovery();
    }
    
    public override bool holds_type_of_source(DataSource source) {
        return source is DirectPhoto;
    }
    
    private static int64 get_direct_key(DataSource source) {
        DirectPhoto photo = (DirectPhoto) source;
        PhotoID photo_id = photo.get_photo_id();
        
        return photo_id.id;
    }
    
    public override void notify_items_added(Gee.Iterable<DataObject> added) {
        foreach (DataObject object in added) {
            DirectPhoto photo = (DirectPhoto) object;
            File file = photo.get_file();
            
            assert(!file_map.has_key(file));
            
            file_map.set(file, photo);
        }
        
        base.notify_items_added(added);
    }
    
    public override void notify_items_removed(Gee.Iterable<DataObject> removed) {
        foreach (DataObject object in removed) {
            DirectPhoto photo = (DirectPhoto) object;
            File file = photo.get_file();
            
            bool is_removed = file_map.unset(file);
            assert(is_removed);
        }
        
        base.notify_items_removed(removed);
    }
    
    public bool has_source_for_file(File file) {
        return file_map.has_key(file);
    }
    
    private void on_file_discovered(File file, FileInfo info) {
        // skip already-seen files
        if (has_source_for_file(file))
            return;
        
        // only add files that look like photo files we support
        if (!PhotoFileFormat.is_file_supported(file))
            return;
        
        DirectPhoto photo;
        string? reason = fetch(file, out photo, false);
        if (reason != null)
            warning("Error fetching file: %s", reason);
        prepared_photos.add(photo);
        if (prepared_photos.size >= DISCOVERED_FILES_BATCH_ADD)
            flush_prepared_photos();
    }
    
    private void on_discovery_completed() {
        flush_prepared_photos();
    }
    
    private void flush_prepared_photos() {
        add_many(prepared_photos);
        prepared_photos.clear();
    }
    
    public bool has_file(File file) {
        return file_map.has_key(file);
    }
    
    public void reimport_photo(DirectPhoto photo) {
        photo.discard_prefetched();
        DirectPhoto reimported_photo;
        fetch(photo.get_file(), out reimported_photo, true);
    }
    
    // Returns an error string if unable to fetch, null otherwise
    public string? fetch(File file, out DirectPhoto photo, bool reimport) {
        // fetch from the map first, which ensures that only one DirectPhoto exists for each file
        photo = file_map.get(file);
        if (photo != null) {
            string? reason = null;
            
            if (reimport) {
                try {
                    Orientation ori_tmp = Orientation.TOP_LEFT;
                    bool should_restore_ori = false;

                    if ((photo.only_metadata_changed()) ||
                        (photo.get_file_format() == PhotoFileFormat.JFIF)) {
                        ori_tmp = photo.get_orientation();
                        should_restore_ori = true;
                    }

                    Photo.ReimportMasterState reimport_state;
                    if (photo.prepare_for_reimport_master(out reimport_state)) {
                        photo.finish_reimport_master(reimport_state);
                        if (should_restore_ori) {
                            photo.fixup_orientation_after_reimport(ori_tmp);
                        }
                    }
                    else {
                        reason = ImportResult.FILE_ERROR.to_string();
                    }
                } catch (Error err) {
                    reason = err.message;
                }
            }

            return reason;
        }
        
        // for DirectPhoto, a fetch on an unknown file is an implicit import into the in-memory
        // database (which automatically adds the new DirectPhoto object to DirectPhoto.global)
        ImportResult result = DirectPhoto.internal_import(file, out photo);
        
        return (result == ImportResult.SUCCESS) ? null : result.to_string();
    }
    
    public bool has_file_source(File file) {
        return file_map.has_key(file);
    }
    
    public DirectPhoto? get_file_source(File file) {
        return file_map.get(file);
    }
}

