/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class DirectPhoto : Photo {
    private const int PREVIEW_BEST_FIT = 360;
    
    public static DirectPhotoSourceCollection global = null;
    
    private Gdk.Pixbuf preview = null;
    
    private DirectPhoto(PhotoRow row) {
        base (row);
    }
    
    public static void init() {
        global = new DirectPhotoSourceCollection();
    }
    
    public static void terminate() {
    }
    
    // This method should only be called by DirectPhotoSourceCollection.  Use
    // DirectPhoto.global.fetch to import files into the system.
    public static ImportResult internal_import(File file, out DirectPhoto photo) {
        PhotoImportParams params = new PhotoImportParams(file, ImportID.generate(),
            PhotoFileSniffer.Options.NO_MD5, null, null, null);
        ImportResult result = Photo.prepare_for_import(params);
        if (result != ImportResult.SUCCESS) {
            // this should never happen; DirectPhotoSourceCollection guarantees it.
            assert(result != ImportResult.PHOTO_EXISTS);
            
            photo = null;
            
            return result;
        }
        
        PhotoTable.get_instance().add(ref params.row);
        
        photo = new DirectPhoto(params.row);
        global.add(photo);
        
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
    
    public override Gdk.Pixbuf? get_thumbnail(int scale) throws Error {
        return (get_metadata().get_preview_count() == 0) ? null :
            get_orientation().rotate_pixbuf(get_metadata().get_preview(0).get_pixbuf());
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

public class DummyDirectPhoto : DirectPhoto, DummyDataSource {
    private string reason;
    
    private DummyDirectPhoto(PhotoRow row, string reason) {
        base (row);
        
        this.reason = reason;
    }
    
    // This creates a DummyDirectPhoto with basic (and invalid) values, but enough to generate
    // a Photo object.  It also adds the photo to the PhotoTable but not DirectPhoto.global.
    public static DummyDirectPhoto create(File file, string reason) {
        PhotoRow row = PhotoRow();
        row.photo_id = PhotoID();
        row.master.filepath = file.get_path();
        row.master.filesize = 0;
        row.master.timestamp = 0;
        row.master.file_format = PhotoFileFormat.JFIF;
        row.master.dim = Dimensions();
        row.master.original_orientation = Orientation.TOP_LEFT;
        row.exposure_time = 0;
        row.import_id = ImportID();
        row.orientation = Orientation.TOP_LEFT;
        row.transformations = null;
        row.md5 = null;
        row.thumbnail_md5 = null;
        row.exif_md5 = null;
        row.time_created = now_time_t();
        row.flags = 0;
        row.rating = Rating.UNRATED;
        row.title = null;
        row.backlinks = null;
        row.time_reimported = 0;
        row.metadata_dirty = false;
        
        PhotoTable.get_instance().add(ref row);
        
        return new DummyDirectPhoto(row, reason);
    }
    
    public string get_reason() {
        return reason;
    }
}

public class DirectPhotoSourceCollection : DatabaseSourceCollection {
    private Gee.HashMap<File, DirectPhoto> file_map = new Gee.HashMap<File, DirectPhoto>(file_hash, 
        file_equal, direct_equal);
    
    public DirectPhotoSourceCollection() {
        base("DirectPhotoSourceCollection", get_direct_key);
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
    
    public bool has_file(File file) {
        return file_map.has_key(file);
    }
    
    // Returns an error string if unable to fetch, null otherwise
    public string? fetch(File file, out DirectPhoto photo, bool reimport) {
        // fetch from the map first, which ensures that only one DirectPhoto exists for each file
        photo = file_map.get(file);
        if (photo != null) {
            string? reason = null;
            
            if (reimport) {
                try {
                    Photo.ReimportMasterState reimport_state;
                    if (photo.prepare_for_reimport_master(out reimport_state))
                        photo.finish_reimport_master(reimport_state);
                    else
                        reason = ImportResult.FILE_ERROR.to_string();
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

