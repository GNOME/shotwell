/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

// Specifies how pixel data is fetched from the backing file on disk.  MASTER is the original
// backing photo of any supported photo file format; SOURCE is either the master or the editable
// file, that is, the appropriate reference file for user display; BASELINE is an appropriate
// file with the proviso that it may be a suitable substitute for the master and/or the editable.
// UNMODIFIED represents the photo with no edits, i.e. the head of the pipeline.
//
// In general, callers want to use the BASELINE unless requirements are specific.
public enum BackingFetchMode {
    SOURCE,
    BASELINE,
    MASTER,
    UNMODIFIED
}

public class PhotoImportParams {
    // IN:
    public File file;
    public File final_associated_file = null;
    public ImportID import_id;
    public PhotoFileSniffer.Options sniffer_options;
    public string? exif_md5;
    public string? thumbnail_md5;
    public string? full_md5;
    
    // IN/OUT:
    public Thumbnails? thumbnails;
    
    // OUT:
    public PhotoRow row = new PhotoRow();
    public Gee.Collection<string>? keywords = null;
    
    public PhotoImportParams(File file, File? final_associated_file, ImportID import_id, 
        PhotoFileSniffer.Options sniffer_options, string? exif_md5, string? thumbnail_md5, string? full_md5, 
        Thumbnails? thumbnails = null) {
        this.file = file;
        this.final_associated_file = final_associated_file;
        this.import_id = import_id;
        this.sniffer_options = sniffer_options;
        this.exif_md5 = exif_md5;
        this.thumbnail_md5 = thumbnail_md5;
        this.full_md5 = full_md5;
        this.thumbnails = thumbnails;
    }
    
    // Creates a placeholder import.
    public PhotoImportParams.create_placeholder(File file, ImportID import_id) {
        this.file = file;
        this.import_id = import_id;
        this.sniffer_options = PhotoFileSniffer.Options.NO_MD5;
        this.exif_md5 = null;
        this.thumbnail_md5 = null;
        this.full_md5 = null;
        this.thumbnails = null;
    }
}

public abstract class PhotoTransformationState : Object {
    private bool is_broke = false;
    
    // This signal is fired when the Photo object can no longer accept it and reliably return to
    // this state.
    public virtual signal void broken() {
        is_broke = true;
    }
    
    public bool is_broken() {
        return is_broke;
    }
}

public enum Rating {
    REJECTED = -1,
    UNRATED = 0,
    ONE = 1,
    TWO = 2,
    THREE = 3,
    FOUR = 4,
    FIVE = 5;

    public bool can_increase() {
        return this < FIVE;
    }

    public bool can_decrease() {
        return this > REJECTED;
    }

    public bool is_valid() {
        return this >= REJECTED && this <= FIVE;
    }

    public Rating increase() {
        return can_increase() ? this + 1 : this;
    }

    public Rating decrease() {
        return can_decrease() ? this - 1 : this;
    }
    
    public int serialize() {
        switch (this) {
            case REJECTED:
                return -1;
            case UNRATED:
                return 0;
            case ONE:
                return 1;
            case TWO:
                return 2;
            case THREE:
                return 3;
            case FOUR:
                return 4;
            case FIVE:
                return 5;
            default:
                return 0;
        }
    }

    public static Rating unserialize(int value) {
        if (value > FIVE)
            return FIVE;
        else if (value < REJECTED)
            return REJECTED;
        
        switch (value) {
            case -1:
                return REJECTED;
            case 0:
                return UNRATED;
            case 1:
                return ONE;
            case 2:
                return TWO;
            case 3:
                return THREE;
            case 4:
                return FOUR;
            case 5:
                return FIVE;
            default:
                return UNRATED;
        }
    }
}

// Photo is an abstract class that allows for applying transformations on-the-fly to a
// particular photo without modifying the backing image file.  The interface allows for
// transformations to be stored persistently elsewhere or in memory until they're committed en
// masse to an image file.
public abstract class Photo : PhotoSource, Dateable {
    // Need to use "thumb" rather than "photo" for historical reasons -- this name is used
    // directly to load thumbnails from disk by already-existing filenames
    public const string TYPENAME = "thumb";

    private const string[] IMAGE_EXTENSIONS = {
        // raster formats
        "jpg", "jpeg", "jpe",
        "tiff", "tif",
        "png",
        "gif",
        "bmp",
        "ppm", "pgm", "pbm", "pnm",
        
        // THM are JPEG thumbnails produced by some RAW cameras ... want to support the RAW
        // image but not import their thumbnails
        "thm",
        
        // less common
        "tga", "ilbm", "pcx", "ecw", "img", "sid", "cd5", "fits", "pgf",
        
        // vector
        "cgm", "svg", "odg", "eps", "pdf", "swf", "wmf", "emf", "xps",
        
        // 3D
        "pns", "jps", "mpo",
        
        // RAW extensions
        "3fr", "arw", "srf", "sr2", "bay", "crw", "cr2", "cap", "iiq", "eip", "dcs", "dcr", "drf",
        "k25", "kdc", "dng", "erf", "fff", "mef", "mos", "mrw", "nef", "nrw", "orf", "ptx", "pef",
        "pxn", "r3d", "raf", "raw", "rw2", "rwl", "rwz", "x3f", "srw"
    };
    
    // There are assertions in the photo pipeline to verify that the generated (or loaded) pixbuf
    // is scaled properly.  We have to allow for some wobble here because of rounding errors and
    // precision limitations of various subsystems.  Pixel-accuracy would be best, but barring that,
    // need to just make sure the pixbuf is in the ballpark.
    private const int SCALING_FUDGE = 64;

    // The number of seconds we should hold onto a precached copy of the original image; if
    // it hasn't been accessed in this many seconds, discard it to conserve memory.
    private const int SOURCE_PIXBUF_TIME_TO_LIVE_SEC = 10;
    
    // min and max size of source pixbuf cache LRU
    private const int SOURCE_PIXBUF_MIN_LRU_COUNT = 1;
    private const int SOURCE_PIXBUF_MAX_LRU_COUNT = 3;
    
    // Minimum raw embedded preview size we're willing to accept; any smaller than this, and 
    // it's probably intended primarily for use only as a thumbnail and won't look good on the
    // PhotoPage.
    private const int MIN_EMBEDDED_SIZE = 1024;
    
    // Here, we cache the exposure time to avoid paying to access the row every time we
    // need to know it. This is initially set in the constructor, and updated whenever
    // the exposure time is set (please see set_exposure_time() for details).
    private time_t cached_exposure_time;
    
    public enum Exception {
        NONE            = 0,
        ORIENTATION     = 1 << 0,
        CROP            = 1 << 1,
        REDEYE          = 1 << 2,
        ADJUST          = 1 << 3,
        STRAIGHTEN      = 1 << 4,
        ALL             = 0xFFFFFFFF;
        
        public bool prohibits(Exception exception) {
            return ((this & exception) != 0);
        }
        
        public bool allows(Exception exception) {
            return ((this & exception) == 0);
        }
    }
    
    // NOTE: This class should only be instantiated when row is locked.
    private class PhotoTransformationStateImpl : PhotoTransformationState {
        private Photo photo;
        private Orientation orientation;
        private Gee.HashMap<string, KeyValueMap>? transformations;
        private PixelTransformer? transformer;
        private PixelTransformationBundle? adjustments;
        
        public PhotoTransformationStateImpl(Photo photo, Orientation orientation,
            Gee.HashMap<string, KeyValueMap>? transformations, PixelTransformer? transformer,
            PixelTransformationBundle? adjustments) {
            this.photo = photo;
            this.orientation = orientation;
            this.transformations = copy_transformations(transformations);
            this.transformer = transformer;
            this.adjustments = adjustments;
            
            photo.baseline_replaced.connect(on_photo_baseline_replaced);
        }
        
        ~PhotoTransformationStateImpl() {
            photo.baseline_replaced.disconnect(on_photo_baseline_replaced);
        }
        
        public Orientation get_orientation() {
            return orientation;
        }
        
        public Gee.HashMap<string, KeyValueMap>? get_transformations() {
            return copy_transformations(transformations);
        }
        
        public PixelTransformer? get_transformer() {
            return (transformer != null) ? transformer.copy() : null;
        }
        
        public PixelTransformationBundle? get_color_adjustments() {
            return (adjustments != null) ? adjustments.copy() : null;
        }
        
        private static Gee.HashMap<string, KeyValueMap>? copy_transformations(
            Gee.HashMap<string, KeyValueMap>? original) {
            if (original == null)
                return null;
            
            Gee.HashMap<string, KeyValueMap>? clone = new Gee.HashMap<string, KeyValueMap>();
            foreach (string object in original.keys)
                clone.set(object, original.get(object).copy());
            
            return clone;
        }
        
        private void on_photo_baseline_replaced() {
            if (!is_broken())
                broken();
        }
    }
    
    private class BackingReaders {
        public PhotoFileReader master;
        public PhotoFileReader developer;
        public PhotoFileReader editable;
    }
    
    private class CachedPixbuf {
        public Photo photo;
        public Gdk.Pixbuf pixbuf;
        public Timer last_touched = new Timer();
        
        public CachedPixbuf(Photo photo, Gdk.Pixbuf pixbuf) {
            this.photo = photo;
            this.pixbuf = pixbuf;
        }
    }
    
    // The first time we have to run the pipeline on an image, we'll precache
    // a copy of the unscaled, unmodified version; this allows us to operate
    // directly on the image data quickly without re-fetching it at the top
    // of the pipeline, which can cause significant lag with larger images.
    //
    // This adds a small amount of (automatically garbage-collected) memory
    // overhead, but greatly simplifies the pipeline, since scaling can now
    // be blithely ignored, and most of the pixel operations are fast enough
    // that the app remains responsive, even with 10MP images.
    //
    // In order to make sure we discard unneeded precaches in a timely fashion,
    // we spawn a timer when the unmodified pixbuf is first precached; if the
    // timer elapses and the pixbuf hasn't been needed again since then, we'll
    // discard it and free up the memory.  The cache also has an LRU to prevent
    // runaway amounts of memory from being stored (see SOURCE_PIXBUF_LRU_COUNT)
    private static Gee.LinkedList<CachedPixbuf>? source_pixbuf_cache = null;
    private static uint discard_source_id = 0;
    
    // because fetching individual items from the database is high-overhead, store all of
    // the photo row in memory
    protected PhotoRow row;
    private BackingPhotoRow editable = new BackingPhotoRow();
    private BackingReaders readers = new BackingReaders();
    private PixelTransformer transformer = null;
    private PixelTransformationBundle adjustments = null;
    // because file_title is determined by data in row, it should only be accessed when row is locked
    private string file_title = null;
    private FileMonitor editable_monitor = null;
    private OneShotScheduler reimport_editable_scheduler = null;
    private OneShotScheduler update_editable_attributes_scheduler = null;
    private OneShotScheduler remove_editable_scheduler = null;
    
    protected bool can_rotate_now = true;
    
    // RAW only: developed backing photos.
    private Gee.HashMap<RawDeveloper, BackingPhotoRow?>? developments = null;
    
    // Set to true if we want to develop RAW photos into new files.
    public static bool develop_raw_photos_to_files { get; set; default = false; }
    
    // This pointer is used to determine which BackingPhotoRow in the PhotoRow to be using at
    // any time.  It should only be accessed -- read or write -- when row is locked.
    protected BackingPhotoRow? backing_photo_row = null;
    
    // This is fired when the photo's editable file is replaced.  The image it generates may or
    // may not be the same; the altered signal is best for that.  null is passed if the editable
    // is being added, replaced, or removed (in the appropriate places)
    public virtual signal void editable_replaced(File? old_file, File? new_file) {
    }
    
    // Fired when one or more of the photo's RAW developments has been changed.  This will only
    // be fired on RAW photos, and only when a development has been added or removed.
    public virtual signal void raw_development_modified() {
    }
    
    // This is fired when the photo's baseline file (the file that generates images at the head
    // of the pipeline) is replaced.  Photo will make every sane effort to only fire this signal
    // if the new baseline is the same image-wise (i.e. the pixbufs it generates are essentially
    // the same).
    public virtual signal void baseline_replaced() {
    }
    
    // This is fired when the photo's master is reimported in place.  It's fired after all changes
    // to the Photo's state have been incorporated into the object and the "altered" signal has
    // been fired notifying of the various details that have changed.
    public virtual signal void master_reimported(PhotoMetadata? metadata) {
    }
    
    // Like "master-reimported", but when a photo's editable has been reimported.
    public virtual signal void editable_reimported(PhotoMetadata? metadata) {
    }
    
    // Like "master-reimported" but when the baseline file has been reimported.  Note that this
    // could be the master file OR the editable file.
    //
    // See BackingFetchMode for more details.
    public virtual signal void baseline_reimported(PhotoMetadata? metadata) {
    }
    
    // Like "master-reimported" but when the source file has been reimported.  Note that this could
    // be the master file OR the editable file.
    //
    // See BackingFetchMode for more details.
    public virtual signal void source_reimported(PhotoMetadata? metadata) {
    }
    
    // The key to this implementation is that multiple instances of Photo with the
    // same PhotoID cannot exist; it is up to the subclasses to ensure this.
    protected Photo(PhotoRow row) {
        this.row = row;
        
        // normalize user text
        this.row.title = prep_title(this.row.title);
        this.row.comment = prep_comment(this.row.comment);
        
        // don't need to lock the struct in the constructor (and to do so would hurt startup
        // time)
        readers.master = row.master.file_format.create_reader(row.master.filepath);
        
        // get the file title of the Photo without using a File object, skipping the separator itself
        string? basename = String.sliced_at_last_char(row.master.filepath, Path.DIR_SEPARATOR);
        if (basename != null)
            file_title = String.sliced_at(basename, 1);
        
        if (is_string_empty(file_title))
            file_title = row.master.filepath;
        
        if (row.editable_id.id != BackingPhotoID.INVALID) {
            BackingPhotoRow? e = get_backing_row(row.editable_id);
            if (e != null) {
                editable = e;
                readers.editable = editable.file_format.create_reader(editable.filepath);
            } else {
                try {
                    PhotoTable.get_instance().detach_editable(this.row);
                } catch (DatabaseError err) {
                    // ignored
                }
                
                // need to remove all transformations as they're keyed to the editable's
                // coordinate system
                remove_all_transformations(false);
            }
        }
        
        if (row.master.file_format == PhotoFileFormat.RAW) {
            // Fetch development backing photos for RAW.
            developments = new Gee.HashMap<RawDeveloper, BackingPhotoRow?>();
            foreach (RawDeveloper d in RawDeveloper.as_array()) {
                BackingPhotoID id = row.development_ids[d];
                if (id.id != BackingPhotoID.INVALID) {
                    BackingPhotoRow? bpr = get_backing_row(id);
                    if (bpr != null)
                        developments.set(d, bpr);
                }
            }
        }
        
        // Set up reader for developer.
        if (row.master.file_format == PhotoFileFormat.RAW && developments.has_key(row.developer)) {
            BackingPhotoRow r = developments.get(row.developer);
            readers.developer = r.file_format.create_reader(r.filepath);
        }
        
        // Set the backing photo state appropriately.
        if (readers.editable != null) {
            backing_photo_row = this.editable; 
        } else if (row.master.file_format != PhotoFileFormat.RAW) {
            backing_photo_row = this.row.master;
        } else {
            // For RAW photos, the backing photo is either the editable (above) or
            // the selected raw development.
            if (developments.has_key(row.developer)) {
                backing_photo_row = developments.get(row.developer);
            } else {
                // Use row's backing photo.
                backing_photo_row = this.row.master;
            }
        }

        cached_exposure_time = this.row.exposure_time;
    }
    
    protected static void init_photo() {
        source_pixbuf_cache = new Gee.LinkedList<CachedPixbuf>();
    }
    
    protected static void terminate_photo() {
        source_pixbuf_cache = null;
        
        if (discard_source_id != 0) {
            Source.remove(discard_source_id);
            discard_source_id = 0;
        }
    }
    
    protected virtual void notify_editable_replaced(File? old_file, File? new_file) {
        editable_replaced(old_file, new_file);
    }
    
    protected virtual void notify_raw_development_modified() {
        raw_development_modified();
    }
    
    protected virtual void notify_baseline_replaced() {
        baseline_replaced();
    }
    
    protected virtual void notify_master_reimported(PhotoMetadata? metadata) {
        master_reimported(metadata);
    }
    
    protected virtual void notify_editable_reimported(PhotoMetadata? metadata) {
        editable_reimported(metadata);
    }
    
    protected virtual void notify_source_reimported(PhotoMetadata? metadata) {
        source_reimported(metadata);
    }
    
    protected virtual void notify_baseline_reimported(PhotoMetadata? metadata) {
        baseline_reimported(metadata);
    }
    
    public override bool internal_delete_backing() throws Error {
        bool ret = true;
        File file = null;
        lock (readers) {
            if (readers.editable != null)
                file = readers.editable.get_file();
        }
        
        detach_editable(true, false);
        
        if (get_master_file_format() == PhotoFileFormat.RAW) {
            foreach (RawDeveloper d in RawDeveloper.as_array()) {
                delete_raw_development(d);
            }
        }
        
        if (file != null) {
            try {
                ret = file.trash(null);
            } catch (Error err) {
                ret = false;
                message("Unable to move editable %s for %s to trash: %s", file.get_path(), 
                    to_string(), err.message);
            }
        }
        
        // Return false if parent method failed.
        return base.internal_delete_backing() && ret;
    }
    
    // Fetches the backing state.  If it can't be read, the ID is flushed from the database
    // for safety.  If the ID is invalid or any error occurs, null is returned.
    private BackingPhotoRow? get_backing_row(BackingPhotoID id) {
        if (id.id == BackingPhotoID.INVALID)
            return null;
        
        BackingPhotoRow? backing_row = null;
        try {
            backing_row = BackingPhotoTable.get_instance().fetch(id);
        } catch (DatabaseError err) {
            warning("Unable to fetch backing state for %s: %s", to_string(), err.message);
        }
        
        if (backing_row == null) {
            try {
                BackingPhotoTable.get_instance().remove(id);
            } catch (DatabaseError err) {
                // ignored
            }
            return null;
        }
        
        return backing_row;
    }
    
    // Returns true if the given raw development was already made and the developed image 
    // exists on disk.
    public bool is_raw_developer_complete(RawDeveloper d) {
        lock (developments) {
            return developments.has_key(d) &&
                FileUtils.test(developments.get(d).filepath, FileTest.EXISTS);
        }
    }
    
    // Determines whether a given RAW developer is available for this photo.
    public bool is_raw_developer_available(RawDeveloper d) {
        lock (developments) {
            if (developments.has_key(d))
                return true;
        }
        
        switch (d) {
            case RawDeveloper.SHOTWELL:
                return true;
                
            case RawDeveloper.CAMERA:
                return false;
            
            case RawDeveloper.EMBEDDED:
                try {
                    PhotoMetadata meta = get_master_metadata();
                    uint num_previews = meta.get_preview_count();
                    
                    if (num_previews > 0) {
                        PhotoPreview? prev = meta.get_preview(num_previews - 1);

                        // Embedded preview could not be fetched?
                        if (prev == null)
                            return false;
                        
                        Dimensions dims = prev.get_pixel_dimensions();
                        
                        // Largest embedded preview was an unacceptable size?
                        int preview_major_axis = (dims.width > dims.height) ? dims.width : dims.height;
                        if (preview_major_axis < MIN_EMBEDDED_SIZE)
                            return false;
                        
                        // Preview was a supported size, use it.
                        return true;
                    }
                    
                    // Image has no embedded preview at all.
                    return false;
                } catch (Error e) {
                    debug("Error accessing embedded preview. Message: %s", e.message);
                }
                return false;
            
            default:
                assert_not_reached();
        }
    }
    
    // Reads info on a backing photo and adds it.
    // Note: this function was created for importing new photos.  It will not
    // notify of changes to the developments.
    public void add_backing_photo_for_development(RawDeveloper d, BackingPhotoRow bpr, bool notify = true) throws Error {
        import_developed_backing_photo(row, d, bpr);
        lock (developments) {
            developments.set(d, bpr);
        }

        if (notify)
            notify_altered(new Alteration("image", "developer"));
    }
    
    public static void import_developed_backing_photo(PhotoRow row, RawDeveloper d, 
        BackingPhotoRow bpr) throws Error {
        File file = File.new_for_path(bpr.filepath);
        FileInfo info = file.query_info(DirectoryMonitor.SUPPLIED_ATTRIBUTES,
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        TimeVal timestamp = info.get_modification_time();
        
        PhotoFileInterrogator interrogator = new PhotoFileInterrogator(
            file, PhotoFileSniffer.Options.GET_ALL);
        interrogator.interrogate();
        
        DetectedPhotoInformation? detected = interrogator.get_detected_photo_information();
        if (detected == null || interrogator.get_is_photo_corrupted()) {
            // TODO: Probably should remove from database, but simply exiting for now (prior code
            // didn't even do this check)
            return;
        }
        
        bpr.dim = detected.image_dim;
        bpr.filesize = info.get_size();
        bpr.timestamp = timestamp.tv_sec;
        bpr.original_orientation = detected.metadata != null ? detected.metadata.get_orientation() : 
            Orientation.TOP_LEFT;
        
        // Add to DB.
        BackingPhotoTable.get_instance().add(bpr);
        PhotoTable.get_instance().update_raw_development(row, d, bpr.id);
    }
    
    // "Develops" a raw photo
    // Not thread-safe.
    private void develop_photo(RawDeveloper d, bool notify) {
        bool wrote_img_to_disk = false;
        BackingPhotoRow bps = null;
        
        switch (d) {
            case RawDeveloper.SHOTWELL:
                try {
                    // Create file and prep.
                    bps = d.create_backing_row_for_development(row.master.filepath);
                    Gdk.Pixbuf? pix = null;
                    lock (readers) {
                        // Don't rotate this pixbuf before writing it out. We don't
                        // need to because we'll display it using the orientation
                        // from the parent raw file, so rotating it here would cause
                        // portrait images to rotate _twice_...
                        pix = get_master_pixbuf(Scaling.for_original(), false);
                    }
                    
                    if (pix == null) {
                        debug("Could not get preview pixbuf");
                        return;
                    }
                    
                    // Write out the JPEG.
                    PhotoFileWriter writer = PhotoFileFormat.JFIF.create_writer(bps.filepath);
                    writer.write(pix, Jpeg.Quality.HIGH);
                    
                    // Remember that we wrote it (we'll only get here if writing
                    // the jpeg doesn't throw an exception).  We do this because
                    // some cameras' output has non-spec-compliant exif segments
                    // larger than 64k (exiv2 can't cope with this), so saving
                    // metadata to the development could fail, but we want to use
                    // it anyway since the image portion is still valid...
                    wrote_img_to_disk = true;
                    
                    // Write out metadata. An exception could get thrown here as
                    // well, hence the separate check for being able to save the
                    // image above...
                    PhotoMetadata meta = get_master_metadata();
                    PhotoFileMetadataWriter mwriter = PhotoFileFormat.JFIF.create_metadata_writer(bps.filepath);
                    mwriter.write_metadata(meta);
                } catch (Error err) {
                    debug("Error developing photo: %s", err.message);
                } finally {
                    if (wrote_img_to_disk) {
                        try {
                            // Read in backing photo info, add to DB.
                            add_backing_photo_for_development(d, bps, notify);
                            
                            notify_raw_development_modified();
                        } catch (Error e) {
                            debug("Error adding backing photo as development. Message: %s",
                                e.message);
                        }
                    }
                }
                
                break;
                
            case RawDeveloper.CAMERA:
                // No development needed.
                break;
                
            case RawDeveloper.EMBEDDED:
                try {
                    // Read in embedded JPEG.
                    PhotoMetadata meta = get_master_metadata();
                    uint c = meta.get_preview_count();
                    if (c <= 0)
                        return;
                    PhotoPreview? prev = meta.get_preview(c - 1);
                    if (prev == null) {
                        debug("Could not get preview from metadata");
                        return;
                    }
                    
                    var pix = prev.flatten();
                    if (pix == null) {
                        debug("Could not get preview pixbuf");
                        return;
                    }

                    // Write out file.
                    bps = d.create_backing_row_for_development(row.master.filepath);

                    // Peek at data. If we really have a JPEG image, just use it,
                    // otherwise do GdkPixbuf roundtrip
                    if (Jpeg.is_jpeg_bytes(pix)) {
                        var outfile = File.new_for_path(bps.filepath);
                        outfile.replace_contents(pix.get_data(), null,
                                false, FileCreateFlags.NONE, null);
                    } else {
                        var pixbuf = prev.get_pixbuf();
                        if (pixbuf == null) {
                            debug("Could not get preview pixbuf");
                            return;
                        }

                        var writer = PhotoFileFormat.JFIF.create_writer(bps.filepath);
                        writer.write(pixbuf, Jpeg.Quality.HIGH);
                    }


                    // Remember that we wrote it (see above
                    // case for why this is necessary).
                    wrote_img_to_disk = true;
                    
                    // Write out metadata
                    PhotoFileMetadataWriter mwriter = PhotoFileFormat.JFIF.create_metadata_writer(bps.filepath);
                    mwriter.write_metadata(meta);
                } catch (Error e) {
                    debug("Error accessing embedded preview. Message: %s", e.message);
                    return;
                } finally {
                    if (wrote_img_to_disk) {
                        try {
                            // Read in backing photo info, add to DB.
                            add_backing_photo_for_development(d, bps, notify);
                            
                            notify_raw_development_modified();
                        } catch (Error e) {
                            debug("Error adding backing photo as development. Message: %s",
                                e.message);
                        }
                    }
                }
                break;
            
            default:
                assert_not_reached();
        }
    }
    
    // Sets the developer internally, but does not actually develop the backing file.
    public void set_default_raw_developer(RawDeveloper d) {
        lock (row) {
            row.developer = d;
        }
    }
    
    // Sets the developer and develops the photo.
    public void set_raw_developer(RawDeveloper d, bool notify = true) {
        if (get_master_file_format() != PhotoFileFormat.RAW)
            return;
        
        // If the caller has asked for 'embedded', but there's a camera development
        // available, always prefer that instead, as it's likely to be of higher
        // quality and resolution.
        if (is_raw_developer_available(RawDeveloper.CAMERA) && (d == RawDeveloper.EMBEDDED))
            d = RawDeveloper.CAMERA;
            
        // If the embedded preview is too small to be used in the PhotoPage, don't
        // allow EMBEDDED to be chosen.
        if (!is_raw_developer_available(RawDeveloper.EMBEDDED) && d != RawDeveloper.CAMERA)
            d = RawDeveloper.SHOTWELL;
            
        lock (developments) {
            RawDeveloper stale_raw_developer = row.developer;
            
            // Perform development, bail out if it doesn't work.
            if (!is_raw_developer_complete(d)) {
                develop_photo(d, notify);
            }
            if (!developments.has_key(d))
                return; // we tried!
            
            // Disgard changes.
            revert_to_master(false);
            
            // Switch master to the new photo.
            row.developer = d;
            backing_photo_row = developments.get(d);
            readers.developer = backing_photo_row.file_format.create_reader(backing_photo_row.filepath);

            try {
                get_prefetched_copy();
            } catch (Error e) {
                // couldn't reload the freshly-developed image, nothing to display
                return;
            }

            set_orientation(backing_photo_row.original_orientation);
            
            try {
                PhotoTable.get_instance().update_raw_development(row, d, backing_photo_row.id);
            } catch (Error e) {
                warning("Error updating database: %s", e.message);
            }
            
            // Is the 'stale' development _NOT_ a camera-supplied one?
            //
            // NOTE: When a raw is first developed, both 'stale' and 'incoming' developers
            // will be the same, so the second test is required for correct operation.
            if ((stale_raw_developer != RawDeveloper.CAMERA) &&
                (stale_raw_developer != row.developer)) {
                // The 'stale' non-Shotwell development we're using was
                // created by us, not the camera, so discard it...
                delete_raw_development(stale_raw_developer);
            }
            
            // Otherwise, don't delete the paired JPEG, since it is user/camera-created
            // and is to be preserved.
        }
        
        if (notify)
            notify_altered(new Alteration("image", "developer"));
        discard_prefetched();
    }

    public RawDeveloper get_raw_developer() {
        return row.developer;
    }

    // Removes a development from the database, filesystem, etc.
    // Returns true if a development was removed, otherwise false.
    private bool delete_raw_development(RawDeveloper d) {
        bool ret = false;
        
        lock (developments) {
            if (!developments.has_key(d))
                return false;
            
            // Remove file.  If this is a camera-generated JPEG, we trash it;
            // otherwise, it was generated by us and should be deleted outright.
            debug("Delete raw development: %s %s", this.to_string(), d.to_string());
            BackingPhotoRow bpr = developments.get(d);
            if (bpr.filepath != null) {
                File f = File.new_for_path(bpr.filepath);
                try {
                    if (d == RawDeveloper.CAMERA)
                        f.trash();
                    else
                        f.delete();
                } catch (Error e) {
                    warning("Unable to delete RAW development: %s error: %s", bpr.filepath, e.message);
                }
            }
            
            // Delete references in DB.
            try {
                PhotoTable.get_instance().remove_development(row, d);
                BackingPhotoTable.get_instance().remove(bpr.id);
            } catch (Error e) {
                warning("Database error while deleting RAW development: %s", e.message);
            }
            
            ret = developments.unset(d);
        }
        
        notify_raw_development_modified();
        return ret;
    }
    
    // Re-do development for photo.
    public void redevelop_raw(RawDeveloper d) {
        lock (developments) {
            delete_raw_development(d);
            RawDeveloper dev = d;
            if (dev == RawDeveloper.CAMERA)
                dev = RawDeveloper.EMBEDDED;
            
            set_raw_developer(dev);
        }
    }
    
    public override BackingFileState[] get_backing_files_state() {
        BackingFileState[] backing = new BackingFileState[0];
        lock (row) {
            backing += new BackingFileState.from_photo_row(row.master, row.md5);
            if (has_editable())
                backing += new BackingFileState.from_photo_row(editable, null);
            
            if (is_developed()) {
                Gee.Collection<BackingPhotoRow>? dev_rows = get_raw_development_photo_rows();
                if (dev_rows != null) {
                    foreach (BackingPhotoRow r in dev_rows) {
                        debug("adding: %s", r.filepath);
                        backing += new BackingFileState.from_photo_row(r, null);
                    }
                }
            }
        }
        
        return backing;
    }
    
    private PhotoFileReader get_backing_reader(BackingFetchMode mode) {
        switch (mode) {
            case BackingFetchMode.MASTER:
                return get_master_reader();
            
            case BackingFetchMode.BASELINE:
                return get_baseline_reader();
            
            case BackingFetchMode.SOURCE:
                return get_source_reader();
            
            case BackingFetchMode.UNMODIFIED:
                if (this.get_master_file_format() == PhotoFileFormat.RAW)
                    return get_raw_developer_reader();
                else
                    return get_master_reader();
            
            default:
                error("Unknown backing fetch mode %s", mode.to_string());
        }
    }
    
    private PhotoFileReader get_master_reader() {
        lock (readers) {
            return readers.master;
        }
    }
    
    protected PhotoFileReader? get_editable_reader() {
        lock (readers) {
            return readers.editable;
        }
    }
    
    // Returns a reader for the head of the pipeline.
    private PhotoFileReader get_baseline_reader() {
        lock (readers) {
            if (readers.editable != null)
                return readers.editable;
            
            if (readers.developer != null)
                return readers.developer;
            
            return readers.master;
        }
    }
    
    // Returns a reader for the photo file that is the source of the image.
    private PhotoFileReader get_source_reader() {
        lock (readers) {
            if (readers.editable != null)
                return readers.editable;
            
            if (readers.developer != null)
                return readers.developer;
            
            return readers.master;
        }
    }
    
    // Returns the reader used for reading the RAW development.
    private PhotoFileReader get_raw_developer_reader() {
        lock (readers) {
            return readers.developer;
        }
    }
    
    public bool is_developed() {
        lock (readers) {
            return readers.developer != null;
        }
    }
    
    public bool has_editable() {
        lock (readers) {
            return readers.editable != null;
        }
    }
    
    public bool does_master_exist() {
        lock (readers) {
            return readers.master.file_exists();
        }
    }
    
    // Returns false if the backing editable does not exist OR the photo does not have an editable
    public bool does_editable_exist() {
        lock (readers) {
            return readers.editable != null ? readers.editable.file_exists() : false;
        }
    }
    
    public bool is_master_baseline() {
        lock (readers) {
            return readers.editable == null;
        }
    }
    
    public bool is_master_source() {
        return !has_editable();
    }
    
    public bool is_editable_baseline() {
        lock (readers) {
            return readers.editable != null;
        }
    }
    
    public bool is_editable_source() {
        return has_editable();
    }
    
    public BackingPhotoRow get_master_photo_row() {
        lock (row) {
            return row.master;
        }
    }
    
    public BackingPhotoRow? get_editable_photo_row() {
        lock (row) {
            // ternary doesn't work here
            if (row.editable_id.is_valid())
                return editable;
            else
                return null;
        }
    }
    
    public Gee.Collection<BackingPhotoRow>? get_raw_development_photo_rows() {
        lock (row) {
            return developments != null ? developments.values : null;
        }
    }
    
    public BackingPhotoRow? get_raw_development_photo_row(RawDeveloper d) {
        lock (row) {
            return developments != null ? developments.get(d) : null;
        }
    }
    
    public PhotoFileFormat? get_editable_file_format() {
        PhotoFileReader? reader = get_editable_reader();
        if (reader == null)
            return null;
        
        // ternary operator doesn't work here
        return reader.get_file_format();
    }
    
    public PhotoFileFormat get_export_format_for_parameters(ExportFormatParameters params) {
        PhotoFileFormat result = PhotoFileFormat.get_system_default_format();

        switch (params.mode) {
            case ExportFormatMode.UNMODIFIED:
                result = get_master_file_format();
            break;
            
            case ExportFormatMode.CURRENT:
                result = get_best_export_file_format();
            break;
            
            case ExportFormatMode.SPECIFIED:
                result = params.specified_format;
            break;
            
            default:
                error("get_export_format_for_parameters: unsupported export format mode");
        }
        
        return result;
    }
    
    public string get_export_basename_for_parameters(ExportFormatParameters params) {
        string? result = null;

        switch (params.mode) {
            case ExportFormatMode.UNMODIFIED:
                result = get_master_file().get_basename();
            break;
            
            case ExportFormatMode.CURRENT:
            case ExportFormatMode.SPECIFIED:
                return get_export_basename(get_export_format_for_parameters(params));
            
            default:
                error("get_export_basename_for_parameters: unsupported export format mode");
        }

        assert (result != null);
        return result;
    }
    
    // This method interrogates the specified file and returns a PhotoRow with all relevant
    // information about it.  It uses the PhotoFileInterrogator to do so.  The caller should create
    // a PhotoFileInterrogator with the proper options prior to calling.  prepare_for_import()
    // will determine what's been discovered and fill out in the PhotoRow or return the relevant
    // objects and information.  If Thumbnails is not null, thumbnails suitable for caching or
    // framing will be returned as well.  Note that this method will call interrogate() and
    // perform all error-handling; the caller simply needs to construct the object.
    //
    // This is the acid-test; if unable to generate a pixbuf or thumbnails, that indicates the 
    // photo itself is bogus and should be discarded.
    //
    // NOTE: This method is thread-safe.
    public static ImportResult prepare_for_import(PhotoImportParams params) {
#if MEASURE_IMPORT
        Timer total_time = new Timer();
#endif
        File file = params.file;
        
        FileInfo info = null;
        try {
            info = file.query_info(DirectoryMonitor.SUPPLIED_ATTRIBUTES,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        } catch (Error err) {
            return ImportResult.FILE_ERROR;
        }
        
        if (info.get_file_type() != FileType.REGULAR)
            return ImportResult.NOT_A_FILE;
        
        if (!is_file_image(file)) {
            message("Not importing %s: Not an image file", file.get_path());
            
            return ImportResult.NOT_AN_IMAGE;
        }

        if (!PhotoFileFormat.is_file_supported(file)) {
            message("Not importing %s: Unsupported extension", file.get_path());
            
            return ImportResult.UNSUPPORTED_FORMAT;
        }
        
        TimeVal timestamp = info.get_modification_time();
        
        // if all MD5s supplied, don't sniff for them
        if (params.exif_md5 != null && params.thumbnail_md5 != null && params.full_md5 != null)
            params.sniffer_options |= PhotoFileSniffer.Options.NO_MD5;
        
        // interrogate file for photo information
        PhotoFileInterrogator interrogator = new PhotoFileInterrogator(file, params.sniffer_options);
        try {
            interrogator.interrogate();
        } catch (Error err) {
            warning("Unable to interrogate photo file %s: %s", file.get_path(), err.message);
            
            return ImportResult.DECODE_ERROR;
        }
        
        if (interrogator.get_is_photo_corrupted())
            return ImportResult.NOT_AN_IMAGE;
        
        // if not detected photo information, unsupported
        DetectedPhotoInformation? detected = interrogator.get_detected_photo_information();
        if (detected == null || detected.file_format == PhotoFileFormat.UNKNOWN)
            return ImportResult.UNSUPPORTED_FORMAT;
        
        // copy over supplied MD5s if provided
        if ((params.sniffer_options & PhotoFileSniffer.Options.NO_MD5) != 0) {
            detected.exif_md5 = params.exif_md5;
            detected.thumbnail_md5 = params.thumbnail_md5;
            detected.md5 = params.full_md5;
        }
        
        Orientation orientation = Orientation.TOP_LEFT;
        time_t exposure_time = 0;
        string title = "";
        string comment = "";
        Rating rating = Rating.UNRATED;
        
#if TRACE_MD5
        debug("importing MD5 %s: exif=%s preview=%s full=%s", file.get_path(), detected.exif_md5,
            detected.thumbnail_md5, detected.md5);
#endif
        
        if (detected.metadata != null) {
            MetadataDateTime? date_time = detected.metadata.get_exposure_date_time();
            if (date_time != null)
                exposure_time = date_time.get_timestamp();
            
            orientation = detected.metadata.get_orientation();
            title = detected.metadata.get_title();
            comment = detected.metadata.get_comment();
            params.keywords = detected.metadata.get_keywords();
            rating = detected.metadata.get_rating();
        }
        
        // verify basic mechanics of photo: RGB 8-bit encoding
        if (detected.colorspace != Gdk.Colorspace.RGB 
            || detected.channels < 3 
            || detected.bits_per_channel != 8) {
            message("Not importing %s: Unsupported color format", file.get_path());
            
            return ImportResult.UNSUPPORTED_FORMAT;
        }
        
        // photo information is initially stored in database in raw, non-modified format ... this is
        // especially important dealing with dimensions and orientation ... Don't trust EXIF
        // dimensions, they can lie or not be present
        params.row.photo_id = PhotoID();
        params.row.master.filepath = file.get_path();
        params.row.master.dim = detected.image_dim;
        params.row.master.filesize = info.get_size();
        params.row.master.timestamp = timestamp.tv_sec;
        params.row.exposure_time = exposure_time;
        params.row.orientation = orientation;
        params.row.master.original_orientation = orientation;
        params.row.import_id = params.import_id;
        params.row.event_id = EventID();
        params.row.transformations = null;
        params.row.md5 = detected.md5;
        params.row.thumbnail_md5 = detected.thumbnail_md5;
        params.row.exif_md5 = detected.exif_md5;
        params.row.time_created = 0;
        params.row.flags = 0;
        params.row.master.file_format = detected.file_format;
        params.row.title = title;
        params.row.comment = comment;
        params.row.rating = rating;
        
        if (params.thumbnails != null) {
            PhotoFileReader reader = params.row.master.file_format.create_reader(
                params.row.master.filepath);
            reader.set_role (PhotoFileReader.Role.THUMBNAIL);
            try {
                ThumbnailCache.generate_for_photo(params.thumbnails, reader, params.row.orientation, 
                    params.row.master.dim);
            } catch (Error err) {
                return ImportResult.convert_error(err, ImportResult.FILE_ERROR);
            }
        }
        
#if MEASURE_IMPORT
        debug("IMPORT: total=%lf", total_time.elapsed());
#endif
        return ImportResult.SUCCESS;
    }
    
    public static void create_pre_import(PhotoImportParams params) {
        File file = params.file;
        params.row.photo_id = PhotoID();
        params.row.master.filepath = file.get_path();
        params.row.master.dim = Dimensions(0,0);
        params.row.master.filesize = 0;
        params.row.master.timestamp = 0;
        params.row.exposure_time = 0;
        params.row.orientation = Orientation.TOP_LEFT;
        params.row.master.original_orientation = Orientation.TOP_LEFT;
        params.row.import_id = params.import_id;
        params.row.event_id = EventID();
        params.row.transformations = null;
        params.row.md5 = null;
        params.row.thumbnail_md5 = null;
        params.row.exif_md5 = null;
        params.row.time_created = 0;
        params.row.flags = 0;
        params.row.master.file_format = PhotoFileFormat.JFIF;
        params.row.title = null;
        params.row.comment = null;
        params.row.rating = Rating.UNRATED;
        
        PhotoFileInterrogator interrogator = new PhotoFileInterrogator(params.file, params.sniffer_options);
        try {
            interrogator.interrogate();
            DetectedPhotoInformation? detected = interrogator.get_detected_photo_information();
            if (detected != null && !interrogator.get_is_photo_corrupted() && detected.file_format != PhotoFileFormat.UNKNOWN)
                params.row.master.file_format = detected.file_format;
        } catch (Error err) {
            debug("Unable to interrogate photo file %s: %s", file.get_path(), err.message);
        }
    }
    
    protected BackingPhotoRow? query_backing_photo_row(File file, PhotoFileSniffer.Options options,
        out DetectedPhotoInformation detected) throws Error {
        detected = null;
        
        BackingPhotoRow backing = new BackingPhotoRow();
        // get basic file information
        FileInfo info = null;
        try {
            info = file.query_info(DirectoryMonitor.SUPPLIED_ATTRIBUTES,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        } catch (Error err) {
            critical("Unable to read file information for %s: %s", file.get_path(), err.message);
            
            return null;
        }
        
        // sniff photo information
        PhotoFileInterrogator interrogator = new PhotoFileInterrogator(file, options);
        interrogator.interrogate();
        detected = interrogator.get_detected_photo_information();
        if (detected == null || interrogator.get_is_photo_corrupted()) {
            critical("Photo update: %s no longer a recognized image", to_string());
            
            return null;
        }
        
        TimeVal modification_time = info.get_modification_time();
        
        backing.filepath = file.get_path();
        backing.timestamp = modification_time.tv_sec;
        backing.filesize = info.get_size();
        backing.file_format = detected.file_format;
        backing.dim = detected.image_dim;
        backing.original_orientation = detected.metadata != null
            ? detected.metadata.get_orientation() : Orientation.TOP_LEFT;
        
        return backing;
    }
    
    public abstract class ReimportMasterState {
    }
    
    private class ReimportMasterStateImpl : ReimportMasterState {
        public PhotoRow row = new PhotoRow();
        public PhotoMetadata? metadata;
        public string[] alterations;
        public bool metadata_only = false;
        
        public ReimportMasterStateImpl(PhotoRow row, PhotoMetadata? metadata, string[] alterations) {
            this.row = row;
            this.metadata = metadata;
            this.alterations = alterations;
        }
    }
    
    public abstract class ReimportEditableState {
    }
    
    private class ReimportEditableStateImpl : ReimportEditableState {
        public BackingPhotoRow backing_state = new BackingPhotoRow();
        public PhotoMetadata? metadata;
        public bool metadata_only = false;
        
        public ReimportEditableStateImpl(BackingPhotoRow backing_state, PhotoMetadata? metadata) {
            this.backing_state = backing_state;
            this.metadata = metadata;
        }
    }
    
    public abstract class ReimportRawDevelopmentState {
    }
    
    private class ReimportRawDevelopmentStateImpl : ReimportRawDevelopmentState {
        public class DevToReimport {
            public BackingPhotoRow backing = new BackingPhotoRow();
            public PhotoMetadata? metadata;
            
            public DevToReimport(BackingPhotoRow backing, PhotoMetadata? metadata) {
                this.backing = backing;
                this.metadata = metadata;
            }
        }
        
        public Gee.Collection<DevToReimport> list = new Gee.ArrayList<DevToReimport>();
        public bool metadata_only = false;
        
        public ReimportRawDevelopmentStateImpl() {
        }
        
        public void add(BackingPhotoRow backing, PhotoMetadata? metadata) {
            list.add(new DevToReimport(backing, metadata));
        }
        
        public int get_size() {
            return list.size;
        }
    }
    
    // This method is thread-safe.  If returns false the photo should be marked offline (in the
    // main UI thread).
    public bool prepare_for_reimport_master(out ReimportMasterState reimport_state) throws Error {
        reimport_state = null;
        
        File file = get_master_reader().get_file();
        
        DetectedPhotoInformation detected;
        BackingPhotoRow? backing = query_backing_photo_row(file, PhotoFileSniffer.Options.GET_ALL, 
            out detected);
        if (backing == null) {
            warning("Unable to retrieve photo state from %s for reimport", file.get_path());
            return false;
        }
        
        // verify basic mechanics of photo: RGB 8-bit encoding
        if (detected.colorspace != Gdk.Colorspace.RGB 
            || detected.channels < 3 
            || detected.bits_per_channel != 8) {
            warning("Not re-importing %s: Unsupported color format", file.get_path());
            
            return false;
        }
        
        // start with existing row and update appropriate fields
        PhotoRow updated_row = new PhotoRow();
        lock (row) {
            updated_row = row;
        }
        
        // build an Alteration list for the relevant changes
        string[] list = new string[0];
        
        if (updated_row.md5 != detected.md5)
            list += "metadata:md5";
        
        if (updated_row.master.original_orientation != backing.original_orientation) {
            list += "image:orientation";
            updated_row.master.original_orientation = backing.original_orientation;
        }
        
        if (detected.metadata != null) {
            MetadataDateTime? date_time = detected.metadata.get_exposure_date_time();
            if (date_time != null && updated_row.exposure_time != date_time.get_timestamp())
                list += "metadata:exposure-time";
            
            if (updated_row.title != detected.metadata.get_title())
                list += "metadata:name";
            
            if (updated_row.comment != detected.metadata.get_comment())
                list += "metadata:comment";
            
            if (updated_row.rating != detected.metadata.get_rating())
                list += "metadata:rating";
        }
        
        updated_row.master = backing;
        updated_row.md5 = detected.md5;
        updated_row.exif_md5 = detected.exif_md5;
        updated_row.thumbnail_md5 = detected.thumbnail_md5;
        
        PhotoMetadata? metadata = null;
        if (detected.metadata != null) {
            metadata = detected.metadata;
            
            MetadataDateTime? date_time = detected.metadata.get_exposure_date_time();
            if (date_time != null)
                updated_row.exposure_time = date_time.get_timestamp();
            
            updated_row.title = detected.metadata.get_title();
            updated_row.comment = detected.metadata.get_comment();
            updated_row.rating = detected.metadata.get_rating();
        }
        
        reimport_state = new ReimportMasterStateImpl(updated_row, metadata, list);
        
        return true;
    }
    
    protected abstract void apply_user_metadata_for_reimport(PhotoMetadata metadata);
    
    // This method is not thread-safe and should be called in the main thread.
    public void finish_reimport_master(ReimportMasterState state) throws DatabaseError {
        ReimportMasterStateImpl reimport_state = (ReimportMasterStateImpl) state;
        
        PhotoTable.get_instance().reimport(reimport_state.row);
        
        lock (row) {
            // Copy row while preserving reference to master.
            BackingPhotoRow original_master = row.master;
            row = reimport_state.row;
            row.master = original_master;
            row.master.copy_from(reimport_state.row.master);
            if (!reimport_state.metadata_only)
                remove_all_transformations(false);
        }
        
        if (reimport_state.metadata != null)
            apply_user_metadata_for_reimport(reimport_state.metadata);
        
        if (!reimport_state.metadata_only) {
            reimport_state.alterations += "image:master";
            if (is_master_baseline())
                reimport_state.alterations += "image:baseline";
        }
        
        if (reimport_state.alterations.length > 0)
            notify_altered(new Alteration.from_array(reimport_state.alterations));
        
        notify_master_reimported(reimport_state.metadata);
        
        if (is_master_baseline())
            notify_baseline_reimported(reimport_state.metadata);
        
        if (is_master_source())
            notify_source_reimported(reimport_state.metadata);
    }
    
    // Verifies a file for reimport.  Returns the file's detected photo info.
    private bool verify_file_for_reimport(File file, out BackingPhotoRow backing, 
        out DetectedPhotoInformation detected) throws Error {
        backing = query_backing_photo_row(file, PhotoFileSniffer.Options.NO_MD5, 
            out detected);
        if (backing == null) {
            return false;
        }
        
        // verify basic mechanics of photo: RGB 8-bit encoding
        if (detected.colorspace != Gdk.Colorspace.RGB 
            || detected.channels < 3 
            || detected.bits_per_channel != 8) {
            warning("Not re-importing %s: Unsupported color format", file.get_path());
            
            return false;
        }
        
        return true;
    }
    
    // This method is thread-safe.  Returns false if the photo has no associated editable.
    public bool prepare_for_reimport_editable(out ReimportEditableState state) throws Error {
        state = null;
        
        File? file = get_editable_file();
        if (file == null)
            return false;
        
        DetectedPhotoInformation detected;
        BackingPhotoRow backing;
        if (!verify_file_for_reimport(file, out backing, out detected))
            return false;
        
        state = new ReimportEditableStateImpl(backing, detected.metadata);
        
        return true;
    }
    
    // This method is not thread-safe.  It should be called by the main thread.
    public void finish_reimport_editable(ReimportEditableState state) throws DatabaseError {
        BackingPhotoID editable_id = get_editable_id();
        if (editable_id.is_invalid())
            return;
        
        ReimportEditableStateImpl reimport_state = (ReimportEditableStateImpl) state;
        
        if (!reimport_state.metadata_only) {
            BackingPhotoTable.get_instance().update(reimport_state.backing_state);
            
            lock (row) {
                editable = reimport_state.backing_state;
                set_orientation(reimport_state.backing_state.original_orientation);
                remove_all_transformations(false);
            }
        } else {
            set_orientation(reimport_state.backing_state.original_orientation);
        }
        
        if (reimport_state.metadata != null) {
            set_title(reimport_state.metadata.get_title());
            set_comment(reimport_state.metadata.get_comment());
            set_rating(reimport_state.metadata.get_rating());
            apply_user_metadata_for_reimport(reimport_state.metadata);
        }
        
        string list = "metadata:name,image:orientation,metadata:rating,metadata:exposure-time";
        if (!reimport_state.metadata_only)
            list += "image:editable,image:baseline";
        
        notify_altered(new Alteration.from_list(list));
        
        notify_editable_reimported(reimport_state.metadata);
        
        if (is_editable_baseline())
            notify_baseline_reimported(reimport_state.metadata);
        
        if (is_editable_source())
            notify_source_reimported(reimport_state.metadata);
    }
    
    // This method is thread-safe.  Returns false if the photo has no associated RAW developments.
    public bool prepare_for_reimport_raw_development(out ReimportRawDevelopmentState state) throws Error {
        state = null;
        
        Gee.Collection<File>? files = get_raw_developer_files();
        if (files == null)
            return false;
        
        ReimportRawDevelopmentStateImpl reimport_state = new ReimportRawDevelopmentStateImpl();
        
        foreach (File file in files) {
            DetectedPhotoInformation detected;
            BackingPhotoRow backing;
            if (!verify_file_for_reimport(file, out backing, out detected))
                continue;
            
            reimport_state.add(backing, detected.metadata);
        }
        
        state = reimport_state;
        return reimport_state.get_size() > 0;
    }
    
    // This method is not thread-safe.  It should be called by the main thread.
    public void finish_reimport_raw_development(ReimportRawDevelopmentState state) throws DatabaseError {
        if (this.get_master_file_format() != PhotoFileFormat.RAW)
            return;
        
        ReimportRawDevelopmentStateImpl reimport_state = (ReimportRawDevelopmentStateImpl) state;
        
        foreach (ReimportRawDevelopmentStateImpl.DevToReimport dev in reimport_state.list) {
            if (!reimport_state.metadata_only) {
                BackingPhotoTable.get_instance().update(dev.backing);
                
                lock (row) {
                    // Refresh raw developments.
                    foreach (RawDeveloper d in RawDeveloper.as_array()) {
                        BackingPhotoID id = row.development_ids[d];
                        if (id.id != BackingPhotoID.INVALID) {
                            BackingPhotoRow? bpr = get_backing_row(id);
                            if (bpr != null)
                                developments.set(d, bpr);
                        }
                    }
                }
            }
        }
        
        string list = "metadata:name,image:orientation,metadata:rating,metadata:exposure-time";
        if (!reimport_state.metadata_only)
            list += "image:editable,image:baseline";
        
        notify_altered(new Alteration.from_list(list));
        
        notify_raw_development_modified();
    }
    
    public override string get_typename() {
        return TYPENAME;
    }
    
    public override int64 get_instance_id() {
        return get_photo_id().id;
    }
    
    public override string get_source_id() {
        // Because of historical reasons, need to format Photo's source ID without a dash for
        // ThumbnailCache.  Note that any future routine designed to tear a source ID apart and
        // locate by typename will need to account for this exception.
        return ("%s%016" + int64.FORMAT_MODIFIER + "x").printf(get_typename(), get_instance_id());
    }
    
    // Use this only if the master file's modification time has been changed (i.e. touched)
    public void set_master_timestamp(FileInfo info) {
        TimeVal modification = info.get_modification_time();
        
        try {
            lock (row) {
                if (row.master.timestamp == modification.tv_sec)
                    return;

                PhotoTable.get_instance().update_timestamp(row.photo_id, modification.tv_sec);
                row.master.timestamp = modification.tv_sec;
            }
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
            
            return;
        }
        
        if (is_master_baseline())
            notify_altered(new Alteration.from_list("metadata:master-timestamp,metadata:baseline-timestamp"));
        else
            notify_altered(new Alteration("metadata", "master-timestamp"));
    }
    
    // Use this only if the editable file's modification time has been changed (i.e. touched)
    public void update_editable_modification_time(FileInfo info) throws DatabaseError {
        TimeVal modification = info.get_modification_time();
        
        bool altered = false;
        lock (row) {
            if (row.editable_id.is_valid() && editable.timestamp != modification.tv_sec) {
                BackingPhotoTable.get_instance().update_timestamp(row.editable_id,
                    modification.tv_sec);
                editable.timestamp = modification.tv_sec;
                altered = true;
            }
        }
        
        if (altered)
            notify_altered(new Alteration.from_list("metadata:editable-timestamp,metadata:baseline-timestamp"));
    }
    
    // Most useful if the appropriate SourceCollection is frozen while calling this.
    public static void update_many_editable_timestamps(Gee.Map<Photo, FileInfo> map)
        throws DatabaseError {
        DatabaseTable.begin_transaction();
        foreach (Photo photo in map.keys)
            photo.update_editable_modification_time(map.get(photo));
        DatabaseTable.commit_transaction();
    }
    
    public override PhotoFileFormat get_preferred_thumbnail_format() {
        return (get_file_format().can_write_image()) ? get_file_format() :
            PhotoFileFormat.get_system_default_format();
    }

    public override Gdk.Pixbuf? create_thumbnail(int scale) throws Error {
        return get_pixbuf(Scaling.for_best_fit(scale, true));
    }
    
    public static bool is_file_image(File file) {
        // if it's a supported image file, by definition it's an image file, otherwise check the
        // master list of common image extensions (checking this way allows for extensions to be
        // added to various PhotoFileFormats without having to also add them to IMAGE_EXTENSIONS)
        return PhotoFileFormat.is_file_supported(file)
            ? true : is_extension_found(file.get_basename(), IMAGE_EXTENSIONS);
    }
    
    private static bool is_extension_found(string basename, string[] extensions) {
        string name, ext;
        disassemble_filename(basename, out name, out ext);
        if (ext == null)
            return false;
        
        // treat extensions as case-insensitive
        ext = ext.down();
        
        // search supported list
        foreach (string extension in extensions) {
            if (ext == extension)
                return true;
        }
        
        return false;
    }
    
    // This is not thread-safe.  Obviously, at least one field must be non-null for this to be
    // effective, although there is no guarantee that any one will be sufficient.  file_format
    // should be UNKNOWN if not to require matching file formats.
    public static bool is_duplicate(File? file, string? thumbnail_md5, string? full_md5,
        PhotoFileFormat file_format) {
#if !NO_DUPE_DETECTION
        return PhotoTable.get_instance().has_duplicate(file, thumbnail_md5, full_md5, file_format);
#else
        return false;
#endif
    }
    
    protected static PhotoID[]? get_duplicate_ids(File? file, string? thumbnail_md5, string? full_md5,
        PhotoFileFormat file_format) {
#if !NO_DUPE_DETECTION
        return PhotoTable.get_instance().get_duplicate_ids(file, thumbnail_md5, full_md5, file_format);
#else
        return null;
#endif
    }
    
    // Conforms to GetDatabaseSourceKey
    public static int64 get_photo_key(DataSource source) {
        return ((LibraryPhoto) source).get_photo_id().id;
    }
    
    // Data element accessors ... by making these thread-safe, and by the remainder of this class
    // (and subclasses) accessing row *only* through these, helps ensure this object is suitable
    // for threads.  This implementation is specifically for PixbufCache to work properly.
    //
    // Much of the setter's thread-safety (especially in regard to writing to the database) is
    // that there is a single Photo object per row of the database.  The PhotoTable is accessed
    // elsewhere in the system (usually for aggregate and search functions).  Those would need to
    // be factored and locked in order to guarantee full thread safety.
    //
    // Also note there is a certain amount of paranoia here.  Many of PhotoRow's elements are
    // currently static, with no setters to change them.  However, since some of these may become
    // mutable in the future, the entire structure is locked.  If performance becomes an issue,
    // more fine-tuned locking may be implemented -- another reason to *only* use these getters
    // and setters inside this class.
    
    public override File get_file() {
        return get_source_reader().get_file();
    }
    
    // This should only be used when the photo's master backing file has been renamed; if it's been
    // altered, use update().
    public void set_master_file(File file) {
        string filepath = file.get_path();
        
        bool altered = false;
        bool is_baseline = false;
        bool is_source = false;
        bool name_changed = false;
        File? old_file = null;
        try {
            lock (row) {
                lock (readers) {
                    old_file = readers.master.get_file();
                    if (!file.equal(old_file)) {
                        PhotoTable.get_instance().set_filepath(get_photo_id(), filepath);
                        
                        row.master.filepath = filepath;
                        file_title = file.get_basename();
                        readers.master = row.master.file_format.create_reader(filepath);
                        
                        altered = true;
                        is_baseline = is_master_baseline();
                        is_source = is_master_source();
                        name_changed = is_string_empty(row.title)
                            && old_file.get_basename() != file.get_basename();
                    }
                }
            }
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        if (altered) {
            notify_master_replaced(old_file, file);
            
            if (is_baseline)
                notify_baseline_replaced();
            
            string[] alteration_list = new string[0];
            alteration_list += "backing:master";
            
            // because the name of the photo is determined by its file title if no user title is present,
            // signal metadata has altered
            if (name_changed)
                alteration_list += "metadata:name";
            
            if (is_source)
                alteration_list += "backing:source";
            
            if (is_baseline)
                alteration_list += "backing:baseline";
            
            notify_altered(new Alteration.from_array(alteration_list));
        }
    }
    
    // This should only be used when the photo's editable file has been renamed.  If it's been
    // altered, use update().  DO NOT USE THIS TO ATTACH A NEW EDITABLE FILE TO THE PHOTO.
    public void set_editable_file(File file) {
        string filepath = file.get_path();
        
        bool altered = false;
        bool is_baseline = false;
        bool is_source = false;
        File? old_file = null;
        try {
            lock (row) {
                lock (readers) {
                    old_file = (readers.editable != null) ? readers.editable.get_file() : null;
                    if (old_file != null && !old_file.equal(file)) {
                        BackingPhotoTable.get_instance().set_filepath(row.editable_id, filepath);
                        
                        editable.filepath = filepath;
                        readers.editable = editable.file_format.create_reader(filepath);
                        
                        altered = true;
                        is_baseline = is_editable_baseline();
                        is_source = is_editable_source();
                    }
                }
            }
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        if (altered) {
            notify_editable_replaced(old_file, file);
            
            if (is_baseline)
                notify_baseline_replaced();
            
            string[] alteration_list = new string[0];
            alteration_list += "backing:editable";
            
            if (is_baseline)
                alteration_list += "backing:baseline";
            
            if (is_source)
                alteration_list += "backing:source";
            
            notify_altered(new Alteration.from_array(alteration_list));
        }
    }
    
    // Also makes sense to freeze the SourceCollection during this operation.
    public static void set_many_editable_file(Gee.Map<Photo, File> map) throws DatabaseError {
        DatabaseTable.begin_transaction();
        
        Gee.MapIterator<Photo, File> map_iter = map.map_iterator();
        while (map_iter.next())
            map_iter.get_key().set_editable_file(map_iter.get_value());
        
        DatabaseTable.commit_transaction();
    }
    
    // Returns the file generating pixbufs, that is, the baseline if present, the backing
    // file if not.
    public File get_actual_file() {
        return get_baseline_reader().get_file();
    }
    
    public override File get_master_file() {
        return get_master_reader().get_file();
    }
    
    public File? get_editable_file() {
        PhotoFileReader? reader = get_editable_reader();
        
        return reader != null ? reader.get_file() : null;
    }
    
    public Gee.Collection<File>? get_raw_developer_files() {
        if (get_master_file_format() != PhotoFileFormat.RAW)
            return null;
        
        Gee.ArrayList<File> ret = new Gee.ArrayList<File>();
        lock (row) {
            foreach (BackingPhotoRow row in developments.values)
                ret.add(File.new_for_path(row.filepath));
        }
        
        return ret;
    }
    
    public File get_source_file() {
        return get_source_reader().get_file();
    }
    
    public PhotoFileFormat get_file_format() {
        lock (row) {
            return backing_photo_row.file_format;
        }
    }
    
    public PhotoFileFormat get_best_export_file_format() {
        PhotoFileFormat file_format = get_file_format();
        if (!file_format.can_write())
            file_format = PhotoFileFormat.get_system_default_format();
        
        return file_format;
    }
    
    public PhotoFileFormat get_master_file_format() {
        lock (row) {
            return readers.master.get_file_format();
        }
    }
    
    public override time_t get_timestamp() {
        lock (row) {
            return backing_photo_row.timestamp;
        }
    }

    public PhotoID get_photo_id() {
        lock (row) {
            return row.photo_id;
        }
    }
    
    // This is NOT thread-safe.
    public override inline EventID get_event_id() {
        return row.event_id;
    }
    
    // This is NOT thread-safe.
    public inline int64 get_raw_event_id() {
        return row.event_id.id;
    }
    
    public override ImportID get_import_id() {
        lock (row) {
            return row.import_id;
        }
    }
    
    protected BackingPhotoID get_editable_id() {
        lock (row) {
            return row.editable_id;
        }
    }
    
    public override string get_master_md5() {
        lock (row) {
            return row.md5;
        }
    }
    
    // Flags' meanings are determined by subclasses.  Top 16 flags (0xFFFF000000000000) reserved
    // for Photo.
    public uint64 get_flags() {
        lock (row) {
            return row.flags;
        }
    }
    
    private void notify_flags_altered(Alteration? additional_alteration) {
        Alteration alteration = new Alteration("metadata", "flags");
        if (additional_alteration != null)
            alteration = alteration.compress(additional_alteration);
        
        notify_altered(alteration);
    }
    
    public uint64 replace_flags(uint64 flags, Alteration? additional_alteration = null) {
        bool committed;
        lock (row) {
            committed = PhotoTable.get_instance().replace_flags(get_photo_id(), flags);
            if (committed)
                row.flags = flags;
        }
        
        if (committed)
            notify_flags_altered(additional_alteration);
        
        return flags;
    }
    
    public bool is_flag_set(uint64 mask) {
        lock (row) {
            return internal_is_flag_set(row.flags, mask);
        }
    }
    
    public uint64 add_flags(uint64 mask, Alteration? additional_alteration = null) {
        uint64 flags = 0;
        
        bool committed = false;
        lock (row) {
            flags = internal_add_flags(row.flags, mask);
            if (row.flags != flags) {
                committed = PhotoTable.get_instance().replace_flags(get_photo_id(), flags);
                if (committed)
                    row.flags = flags;
            }
        }
        
        if (committed)
            notify_flags_altered(additional_alteration);
        
        return flags;
    }
    
    public uint64 remove_flags(uint64 mask, Alteration? additional_alteration = null) {
        uint64 flags = 0;
        
        bool committed = false;
        lock (row) {
            flags = internal_remove_flags(row.flags, mask);
            if (row.flags != flags) {
                committed = PhotoTable.get_instance().replace_flags(get_photo_id(), flags);
                if (committed)
                    row.flags = flags;
            }
        }
        
        if (committed)
            notify_flags_altered(additional_alteration);
        
        return flags;
    }
    
    public uint64 add_remove_flags(uint64 add, uint64 remove, Alteration? additional_alteration = null) {
        uint64 flags = 0;
        
        bool committed = false;
        lock (row) {
            flags = (row.flags | add) & ~remove;
            if (row.flags != flags) {
                committed = PhotoTable.get_instance().replace_flags(get_photo_id(), flags);
                if (committed)
                    row.flags = flags;
            }
        }
        
        if (committed)
            notify_flags_altered(additional_alteration);
        
        return flags;
    }
    
    public static void add_remove_many_flags(Gee.Collection<Photo>? add, uint64 add_mask,
        Alteration? additional_add_alteration, Gee.Collection<Photo>? remove, uint64 remove_mask,
        Alteration? additional_remove_alteration) throws DatabaseError {
        DatabaseTable.begin_transaction();
        
        if (add != null) {
            foreach (Photo photo in add)
                photo.add_flags(add_mask, additional_add_alteration);
        }
        
        if (remove != null) {
            foreach (Photo photo in remove)
                photo.remove_flags(remove_mask, additional_remove_alteration);
        }
        
        DatabaseTable.commit_transaction();
    }
    
    public uint64 toggle_flags(uint64 mask, Alteration? additional_alteration = null) {
        uint64 flags = 0;
        
        bool committed = false;
        lock (row) {
            flags = row.flags ^ mask;
            if (row.flags != flags) {
                committed = PhotoTable.get_instance().replace_flags(get_photo_id(), flags);
                if (committed)
                    row.flags = flags;
            }
        }
        
        if (committed)
            notify_flags_altered(additional_alteration);
        
        return flags;
    }
    
    public bool is_master_metadata_dirty() {
        lock (row) {
            return row.metadata_dirty;
        }
    }
    
    public void set_master_metadata_dirty(bool dirty) throws DatabaseError {
        bool committed = false;
        lock (row) {
            if (row.metadata_dirty != dirty) {
                PhotoTable.get_instance().set_metadata_dirty(get_photo_id(), dirty);
                row.metadata_dirty = dirty;
                committed = true;
            }
        }
        
        if (committed)
            notify_altered(new Alteration("metadata", "master-dirty"));
    }
    
    public override Rating get_rating() {
        lock (row) {
            return row.rating;
        }
    }
    
    public override void set_rating(Rating rating) {
        bool committed = false;
        
        lock (row) {
            if (rating != row.rating && rating.is_valid()) {
                committed = PhotoTable.get_instance().set_rating(get_photo_id(), rating);
                if (committed)
                    row.rating = rating;
            }
        }
        
        if (committed)
            notify_altered(new Alteration("metadata", "rating"));
    }
    
    public override void increase_rating() {
        lock (row) {
            set_rating(row.rating.increase());
        }
    }

    public override void decrease_rating() {
        lock (row) {
            set_rating(row.rating.decrease());
        }
    }
    
    protected override void commit_backlinks(SourceCollection? sources, string? backlinks) {
        // For now, only one link state may be stored in the database ... if this turns into a
        // problem, will use SourceCollection to determine where to store it.
        
        try {
            PhotoTable.get_instance().update_backlinks(get_photo_id(), backlinks);
            lock (row) {
                row.backlinks = backlinks;
            }
        } catch (DatabaseError err) {
            warning("Unable to update link state for %s: %s", to_string(), err.message);
        }
        
        // Note: *Not* firing altered or metadata_altered signal because link_state is not a
        // property that's available to users of Photo.  Persisting it as a mechanism for dealing
        // with unlink/relink properly.
    }

    protected override bool set_event_id(EventID event_id) {
        lock (row) {
            bool committed = PhotoTable.get_instance().set_event(row.photo_id, event_id);

            if (committed)
                row.event_id = event_id;

            return committed;
        }
    }

    public override string to_string() {
        return "[%s] %s%s".printf(get_photo_id().id.to_string(), get_master_reader().get_filepath(),
            !is_master_baseline() ? " (" + get_actual_file().get_path() + ")" : "");
    }

    public override bool equals(DataSource? source) {
        // Primary key is where the rubber hits the road
        Photo? photo = source as Photo;
        if (photo != null) {
            PhotoID photo_id = get_photo_id();
            PhotoID other_photo_id = photo.get_photo_id();
            
            if (this != photo && photo_id.id != PhotoID.INVALID) {
                assert(photo_id.id != other_photo_id.id);
            }
        }
        
        return base.equals(source);
    }
    
    // used to update the database after an internal metadata exif write
    private void file_exif_updated() {
        File file = get_file();
    
        FileInfo info = null;
        try {
            info = file.query_info(DirectoryMonitor.SUPPLIED_ATTRIBUTES,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        } catch (Error err) {
            error("Unable to read file information for %s: %s", to_string(), err.message);
        }
        
        TimeVal timestamp = info.get_modification_time();
        
        // interrogate file for photo information
        PhotoFileInterrogator interrogator = new PhotoFileInterrogator(file);
        try {
            interrogator.interrogate();
        } catch (Error err) {
            warning("Unable to interrogate photo file %s: %s", file.get_path(), err.message);
        }
        
        DetectedPhotoInformation? detected = interrogator.get_detected_photo_information();
        if (detected == null || interrogator.get_is_photo_corrupted()) {
            critical("file_exif_updated: %s no longer an image", to_string());
            
            return;
        }
        
        bool success;
        lock (row) {
            success = PhotoTable.get_instance().master_exif_updated(get_photo_id(), info.get_size(),
                timestamp.tv_sec, detected.md5, detected.exif_md5, detected.thumbnail_md5, row);
        }
        
        if (success)
            notify_altered(new Alteration.from_list("metadata:exif,metadata:md5"));
    }

    // PhotoSource
    
    public override uint64 get_filesize() {
        lock (row) {
            return backing_photo_row.filesize;
        }
    }
    
    public override uint64 get_master_filesize() {
        lock (row) {
            return row.master.filesize;
        }
    }
    
    public uint64 get_editable_filesize() {
        lock (row) {
            return editable.filesize;
        }
    }
    
    public override time_t get_exposure_time() {
        return cached_exposure_time;
    }
   
    public override string get_basename() {
        lock (row) {
            return file_title;
        }
    }
    
    public override string? get_title() {
        lock (row) {
            return row.title;
        }
    }

    public override string? get_comment() {
        lock (row) {
            return row.comment;
        }
    }

    public override void set_title(string? title) {
        string? new_title = prep_title(title);
        
        bool committed = false;
        lock (row) {
            if (new_title == row.title)
                return;
            
            committed = PhotoTable.get_instance().set_title(row.photo_id, new_title);
            if (committed)
                row.title = new_title;
        }
        
        if (committed)
            notify_altered(new Alteration("metadata", "name"));
    }
    
    public override bool set_comment(string? comment) {
        string? new_comment = prep_comment(comment);
        
        bool committed = false;
        lock (row) {
            if (new_comment == row.comment)
                return true;
            
            committed = PhotoTable.get_instance().set_comment(row.photo_id, new_comment);
            if (committed)
                row.comment = new_comment;
        }
        
        if (committed)
            notify_altered(new Alteration("metadata", "comment"));

        return committed;
    }
    
    public void set_import_id(ImportID import_id) {
        DatabaseError dberr = null;
        lock (row) {
            try {
                PhotoTable.get_instance().set_import_id(row.photo_id, import_id);
                row.import_id = import_id;
            } catch (DatabaseError err) {
                dberr = err;
            }
        }
        
        if (dberr == null)
            notify_altered(new Alteration("metadata", "import-id"));
        else
            warning("Unable to write import ID for %s: %s", to_string(), dberr.message);
    }

    public void set_title_persistent(string? title) throws Error {
        PhotoFileReader source = get_source_reader();
        
        // Try to write to backing file
        if (!source.get_file_format().can_write_metadata()) {
            warning("No photo file writer available for %s", source.get_filepath());
            
            set_title(title);
            
            return;
        }
        
        PhotoMetadata metadata = source.read_metadata();
        metadata.set_title(title);
        
        PhotoFileMetadataWriter writer = source.create_metadata_writer();
        LibraryMonitor.blacklist_file(source.get_file(), "Photo.set_persistent_title");
        try {
            writer.write_metadata(metadata);
        } finally {
            LibraryMonitor.unblacklist_file(source.get_file());
        }
        
        set_title(title);
        
        file_exif_updated();
    }

    public void set_comment_persistent(string? comment) throws Error {
        PhotoFileReader source = get_source_reader();
        
        // Try to write to backing file
        if (!source.get_file_format().can_write_metadata()) {
            warning("No photo file writer available for %s", source.get_filepath());
            
            set_comment(comment);
            
            return;
        }
        
        PhotoMetadata metadata = source.read_metadata();
        metadata.set_comment(comment);
        
        PhotoFileMetadataWriter writer = source.create_metadata_writer();
        LibraryMonitor.blacklist_file(source.get_file(), "Photo.set_persistent_comment");
        try {
            writer.write_metadata(metadata);
        } finally {
            LibraryMonitor.unblacklist_file(source.get_file());
        }
        
        set_comment(comment);
        
        file_exif_updated();
    }

    public void set_exposure_time(time_t time) {
        bool committed;
        lock (row) {
            committed = PhotoTable.get_instance().set_exposure_time(row.photo_id, time);
            if (committed) {
                row.exposure_time = time;
                cached_exposure_time = time;
            }
        }
        
        if (committed)
            notify_altered(new Alteration("metadata", "exposure-time"));
    }
    
    public void set_exposure_time_persistent(time_t time) throws Error {
        PhotoFileReader source = get_source_reader();
        
        // Try to write to backing file
        if (!source.get_file_format().can_write_metadata()) {
            warning("No photo file writer available for %s", source.get_filepath());
            
            set_exposure_time(time);
            
            return;
        }
        
        PhotoMetadata metadata = source.read_metadata();
        metadata.set_exposure_date_time(new MetadataDateTime(time));
        
        PhotoFileMetadataWriter writer = source.create_metadata_writer();
        LibraryMonitor.blacklist_file(source.get_file(), "Photo.set_exposure_time_persistent");
        try {
            writer.write_metadata(metadata);
        } finally {
            LibraryMonitor.unblacklist_file(source.get_file());
        }
        
        set_exposure_time(time);
        
        file_exif_updated();
    }
    
    /**
     * @brief Returns the width and height of the Photo after various
     * arbitrary stages of the pipeline have been applied in
     * the same order they're applied in get_pixbuf_with_options.
     * With no argument passed, it works exactly like the
     * previous incarnation did.
     *
     * @param disallowed_steps Which pipeline steps should NOT
     *      be taken into account when computing image dimensions
     *      (matching the convention set by get_pixbuf_with_options()).
     *      Pipeline steps that do not affect the image geometry are
     *      ignored.
     */
    public override Dimensions get_dimensions(Exception disallowed_steps = Exception.NONE) {
        // The raw dimensions of the incoming image prior to the pipeline.
        Dimensions returned_dims = get_raw_dimensions();

        // Compute how much the image would be resized by after rotating and/or mirroring.
        if (disallowed_steps.allows(Exception.ORIENTATION)) {
            Orientation ori_tmp = get_orientation();

            // Is this image rotated 90 or 270 degrees?
            switch (ori_tmp) {
                case Orientation.LEFT_TOP:
                case Orientation.RIGHT_TOP:
                case Orientation.LEFT_BOTTOM:
                case Orientation.RIGHT_BOTTOM:
                    // Yes, swap width and height of raw dimensions.
                    int width_tmp = returned_dims.width;

                    returned_dims.width = returned_dims.height;
                    returned_dims.height = width_tmp;
                break;

                default:
                    // No, only mirrored or rotated 180; do nothing.
                break;
            }
        }

        // Compute how much the image would be resized by after straightening.
        if (disallowed_steps.allows(Exception.STRAIGHTEN)) {
            double x_size, y_size;
            double angle = 0.0;

            get_straighten(out angle);

            compute_arb_rotated_size(returned_dims.width, returned_dims.height, angle, out x_size, out y_size);

            returned_dims.width = (int) (x_size);
            returned_dims.height = (int) (y_size);
        }

        // Compute how much the image would be resized by after cropping.
        if (disallowed_steps.allows(Exception.CROP)) {
            Box crop;
            if (get_crop(out crop, disallowed_steps)) {
                returned_dims = crop.get_dimensions();
            }
        }
        return returned_dims;
    }
    
    // This method *must* be called with row locked.
    private void locked_create_adjustments_from_data() {
        adjustments = new PixelTransformationBundle();
        
        KeyValueMap map = get_transformation("adjustments");
        if (map == null)
            adjustments.set_to_identity();
        else
            adjustments.load(map);
        
        transformer = adjustments.generate_transformer();
    }
    
    // Returns a copy of the color adjustments array.  Use set_color_adjustments to persist.
    public PixelTransformationBundle get_color_adjustments() {
        lock (row) {
            if (adjustments == null)
                locked_create_adjustments_from_data();
            
            return adjustments.copy();
        }
    }
    
    public PixelTransformer get_pixel_transformer() {
        lock (row) {
            if (transformer == null)
                locked_create_adjustments_from_data();
            
            return transformer.copy();
        }
    }

    public bool has_color_adjustments() {
        return has_transformation("adjustments");
    }
    
    public PixelTransformation? get_color_adjustment(PixelTransformationType type) {
        return get_color_adjustments().get_transformation(type);
    }

    public void set_color_adjustments(PixelTransformationBundle new_adjustments) {
        /* if every transformation in 'new_adjustments' is the identity, then just remove all
           adjustments from the database */
        if (new_adjustments.is_identity()) {
            bool result;
            lock (row) {
                result = remove_transformation("adjustments");
                adjustments = null;
                transformer = null;
            }
            
            if (result)
                notify_altered(new Alteration("image", "color-adjustments"));

            return;
        }
        
        // convert bundle to KeyValueMap, which can be saved in the database
        KeyValueMap map = new_adjustments.save("adjustments");
        
        bool committed;
        lock (row) {
            if (transformer == null || adjustments == null) {
                // create new 
                adjustments = new_adjustments.copy();
                transformer = new_adjustments.generate_transformer();
            } else {
                // replace existing
                foreach (PixelTransformation transformation in new_adjustments.get_transformations()) {
                    transformer.replace_transformation(
                        adjustments.get_transformation(transformation.get_transformation_type()),
                        transformation);
                }
                
                adjustments = new_adjustments.copy();
            }

            committed = set_transformation(map);
        }
        
        if (committed)
            notify_altered(new Alteration("image", "color-adjustments"));
    }
    
    // This is thread-safe.  Returns the source file's metadata.
    public override PhotoMetadata? get_metadata() {
        try {
            return get_source_reader().read_metadata();
        } catch (Error err) {
            warning("Unable to load metadata: %s", err.message);
            
            return null;
        }
    }
    
    public PhotoMetadata get_master_metadata() throws Error {
        return get_master_reader().read_metadata();
    }
    
    public PhotoMetadata? get_editable_metadata() throws Error {
        PhotoFileReader? reader = get_editable_reader();
        
        return (reader != null) ? reader.read_metadata() : null;
    }
    
    // This is thread-safe.  This must be followed by a call to finish_update_master_metadata() in
    // the main thread.  Returns false if unable to write metadata (because operation is
    // unsupported) or the file is unavailable.
    public bool persist_master_metadata(PhotoMetadata metadata, out ReimportMasterState state)
        throws Error {
        state = null;
        
        PhotoFileReader master_reader = get_master_reader();
        
        if (!master_reader.get_file_format().can_write_metadata())
            return false;
        
        master_reader.create_metadata_writer().write_metadata(metadata);
        
        if (!prepare_for_reimport_master(out state))
            return false;
        
        ((ReimportMasterStateImpl) state).metadata_only = true;
        
        return true;
    }
    
    public void finish_update_master_metadata(ReimportMasterState state) throws DatabaseError {
        finish_reimport_master(state);
    }
    
    public bool persist_editable_metadata(PhotoMetadata metadata, out ReimportEditableState state)
        throws Error {
        state = null;
        
        PhotoFileReader? editable_reader = get_editable_reader();
        if (editable_reader == null)
            return false;
        
        if (!editable_reader.get_file_format().can_write_metadata())
            return false;
        
        editable_reader.create_metadata_writer().write_metadata(metadata);
        
        if (!prepare_for_reimport_editable(out state))
            return false;
        
        ((ReimportEditableStateImpl) state).metadata_only = true;
        
        return true;
    }
    
    public void finish_update_editable_metadata(ReimportEditableState state) throws DatabaseError {
        finish_reimport_editable(state);
    }
    
    // Transformation storage and exporting

    public Dimensions get_raw_dimensions() {
        lock (row) {
            return backing_photo_row.dim;
        }
    }

    public bool has_transformations() {
        lock (row) {
            return (row.orientation != backing_photo_row.original_orientation) 
                ? true 
                : (row.transformations != null);
        }
    }
    
    public bool only_metadata_changed() {
        MetadataDateTime? date_time = null;
        
        PhotoMetadata? metadata = get_metadata();
        if (metadata != null)
            date_time = metadata.get_exposure_date_time();
        
        lock (row) {
            return row.transformations == null 
                && (row.orientation != backing_photo_row.original_orientation 
                || (date_time != null && row.exposure_time != date_time.get_timestamp()));
        }
    }
    
    public bool has_alterations() {
        MetadataDateTime? date_time = null;
        string? title = null;
        string? comment = null;

        PhotoMetadata? metadata = get_metadata();
        if (metadata != null) {
            date_time = metadata.get_exposure_date_time();
            title = metadata.get_title();
            comment = metadata.get_comment();
        } 

        // Does this photo contain any date/time info?
        if (date_time == null) {
            // No, use file timestamp as date/time.
            lock (row) {
                // Did we manually set an exposure date?
                if(backing_photo_row.timestamp != row.exposure_time) {
                    // Yes, we need to save this.
                    return true;            
                }
            }
        }

        lock (row) {
            return row.transformations != null 
                || row.orientation != backing_photo_row.original_orientation
                || (date_time != null && row.exposure_time != date_time.get_timestamp())
                || (get_comment() != comment)
                || (get_title() != title);
        }

    }
    
    public PhotoTransformationState save_transformation_state() {
        lock (row) {
            return new PhotoTransformationStateImpl(this, row.orientation,
                row.transformations,
                transformer != null ? transformer.copy() : null,
                adjustments != null ? adjustments.copy() : null);
        }
    }
    
    public bool load_transformation_state(PhotoTransformationState state) {
        PhotoTransformationStateImpl state_impl = state as PhotoTransformationStateImpl;
        if (state_impl == null)
            return false;
        
        Orientation saved_orientation = state_impl.get_orientation();
        Gee.HashMap<string, KeyValueMap>? saved_transformations = state_impl.get_transformations();
        PixelTransformer? saved_transformer = state_impl.get_transformer();
        PixelTransformationBundle? saved_adjustments = state_impl.get_color_adjustments();
        
        bool committed;
        lock (row) {
            committed = PhotoTable.get_instance().set_transformation_state(row.photo_id,
                saved_orientation, saved_transformations);
            if (committed) {
                row.orientation = saved_orientation;
                row.transformations = saved_transformations;
                transformer = saved_transformer;
                adjustments = saved_adjustments;
            }
        }
        
        if (committed)
            notify_altered(new Alteration("image", "transformation-state"));
        
        return committed;
    }
    
    public void remove_all_transformations(bool notify = true) {
        bool is_altered = false;
        lock (row) {
            is_altered = PhotoTable.get_instance().remove_all_transformations(row.photo_id);
            row.transformations = null;
            
            transformer = null;
            adjustments = null;
            
            if (row.orientation != backing_photo_row.original_orientation) {
                PhotoTable.get_instance().set_orientation(row.photo_id, 
                    backing_photo_row.original_orientation);
                row.orientation = backing_photo_row.original_orientation;
                is_altered = true;
            }
        }

        if (is_altered && notify)
            notify_altered(new Alteration("image", "revert"));
    }
    
    public Orientation get_original_orientation() {
        lock (row) {
            return backing_photo_row.original_orientation;
        }
    }
    
    public Orientation get_orientation() {
        lock (row) {
            return row.orientation;
        }
    }
    
    public bool set_orientation(Orientation orientation) {
        bool committed = false;
        lock (row) {
            if (row.orientation != orientation) {
                committed = PhotoTable.get_instance().set_orientation(row.photo_id, orientation);
                if (committed)
                    row.orientation = orientation;
            }
        }
        
        if (committed)
            notify_altered(new Alteration("image", "orientation"));
        
        return committed;
    }

    public bool check_can_rotate() {
        return can_rotate_now;
    }

    public virtual void rotate(Rotation rotation) {
        lock (row) {
            set_orientation(get_orientation().perform(rotation));
        }
    }

    private bool has_transformation(string name) {
        lock (row) {
            return (row.transformations != null) ? row.transformations.has_key(name) : false;
        }
    }
    
    // Note that obtaining the proper map is thread-safe here.  The returned map is a copy of
    // the original, so it is thread-safe as well.  However: modifying the returned map
    // does not modify the original; set_transformation() must be used.
    private KeyValueMap? get_transformation(string name) {
        KeyValueMap map = null;
        lock (row) {
            if (row.transformations != null) {
                map = row.transformations.get(name);
                if (map != null)
                    map = map.copy();
            }
        }
        
        return map;
    }
    
    private bool set_transformation(KeyValueMap trans) {
        lock (row) {
            if (row.transformations == null)
                row.transformations = new Gee.HashMap<string, KeyValueMap>();
            
            row.transformations.set(trans.get_group(), trans);
            
            return PhotoTable.get_instance().set_transformation(row.photo_id, trans);
        }
    }

    private bool remove_transformation(string name) {
        bool altered_cache, altered_persistent;
        lock (row) {
            if (row.transformations != null) {
                altered_cache = row.transformations.unset(name);
                if (row.transformations.size == 0)
                    row.transformations = null;
            } else {
                altered_cache = false;
            }
            
            altered_persistent = PhotoTable.get_instance().remove_transformation(row.photo_id, 
                name);
        }

        return (altered_cache || altered_persistent);
    }

    public bool has_crop() {
        return has_transformation("crop");
    }

    // Returns the crop in the raw photo's coordinate system
    public bool get_raw_crop(out Box crop) {
        crop = Box();
        
        KeyValueMap map = get_transformation("crop");
        if (map == null)
            return false;
        
        int left = map.get_int("left", -1);
        int top = map.get_int("top", -1);
        int right = map.get_int("right", -1);
        int bottom = map.get_int("bottom", -1);
        
        if (left == -1 || top == -1 || right == -1 || bottom == -1)
            return false;
        
        crop = Box(left, top, right, bottom);
        
        return true;
    }
    
    // Sets the crop using the raw photo's unrotated coordinate system
    private void set_raw_crop(Box crop) {
        KeyValueMap map = new KeyValueMap("crop");
        map.set_int("left", crop.left);
        map.set_int("top", crop.top);
        map.set_int("right", crop.right);
        map.set_int("bottom", crop.bottom);
        
        if (set_transformation(map))
            notify_altered(new Alteration("image", "crop"));
    }
    
    private bool get_raw_straighten(out double angle) {
        KeyValueMap map = get_transformation("straighten");
        if (map == null) {
            angle = 0.0;
            
            return false;
        }
        
        angle = map.get_double("angle", 0.0); 
        
        return true;
    }
    
    private void set_raw_straighten(double theta) {
        KeyValueMap map = new KeyValueMap("straighten");
        map.set_double("angle", theta);       
        
        if (set_transformation(map)) {
            notify_altered(new Alteration("image", "straighten"));
        }
    }    
    
    // All instances are against the coordinate system of the unscaled, unrotated photo.
    private EditingTools.RedeyeInstance[] get_raw_redeye_instances() {
        KeyValueMap map = get_transformation("redeye");
        if (map == null)
            return new EditingTools.RedeyeInstance[0];
        
        int num_points = map.get_int("num_points", -1);
        assert(num_points > 0);

        EditingTools.RedeyeInstance[] res = new EditingTools.RedeyeInstance[num_points];

        Gdk.Point default_point = {0};
        default_point.x = -1;
        default_point.y = -1;

        for (int i = 0; i < num_points; i++) {
            string center_key = "center%d".printf(i);
            string radius_key = "radius%d".printf(i);

            res[i].center = map.get_point(center_key, default_point);
            assert(res[i].center.x != default_point.x);
            assert(res[i].center.y != default_point.y);

            res[i].radius = map.get_int(radius_key, -1);
            assert(res[i].radius != -1);
        }

        return res;
    }
    
    public bool has_redeye_transformations() {
        return has_transformation("redeye");
    }

    // All instances are against the coordinate system of the unrotated photo.
    public void add_redeye_instance(EditingTools.RedeyeInstance redeye) {
        KeyValueMap map = get_transformation("redeye");
        if (map == null) {
            map = new KeyValueMap("redeye");
            map.set_int("num_points", 0);
        }
        
        int num_points = map.get_int("num_points", -1);
        assert(num_points >= 0);
        
        num_points++;
        
        string radius_key = "radius%d".printf(num_points - 1);
        string center_key = "center%d".printf(num_points - 1);
        
        map.set_int(radius_key, redeye.radius);
        map.set_point(center_key, redeye.center);
        
        map.set_int("num_points", num_points);

        if (set_transformation(map))
            notify_altered(new Alteration("image", "redeye"));
    }

    // Pixbuf generation
    
    // Returns dimensions for the pixbuf at various stages of the pipeline.
    //
    // scaled_image is the dimensions of the image after a scaled load-and-decode.
    // scaled_to_viewport is the dimensions of the image sized according to the scaling parameter.
    // scaled_image and scaled_to_viewport may be different if the photo is cropped.
    //
    // Returns true if scaling is to occur, false otherwise.  If false, scaled_image will be set to
    // the raw image dimensions and scaled_to_viewport will be the dimensions of the image scaled
    // to the Scaling viewport.
    private bool calculate_pixbuf_dimensions(Scaling scaling, Exception exceptions, 
        out Dimensions scaled_image, out Dimensions scaled_to_viewport) {
        lock (row) {
            // this function needs to access various elements of the Photo atomically
            return locked_calculate_pixbuf_dimensions(scaling, exceptions,
                out scaled_image, out scaled_to_viewport);
        }
    }
    
    // Must be called with row locked.
    private bool locked_calculate_pixbuf_dimensions(Scaling scaling, Exception exceptions,
        out Dimensions scaled_image, out Dimensions scaled_to_viewport) {
        Dimensions raw = get_raw_dimensions();
        
        if (scaling.is_unscaled()) {
            scaled_image = raw;
            scaled_to_viewport = raw;
            
            return false;
        }
        
        Orientation orientation = get_orientation();
        
        // If no crop, the scaled_image is simply raw scaled to fit into the viewport.  Otherwise,
        // the image is scaled enough so the cropped region fits the viewport.

        scaled_image = Dimensions();
        scaled_to_viewport = Dimensions();
        
        if (exceptions.allows(Exception.CROP)) {
            Box crop;
            if (get_raw_crop(out crop)) {
                // rotate the crop and raw space accordingly ... order is important here, rotate_box
                // works with the unrotated dimensions in space
                Dimensions rotated_raw = raw;
                if (exceptions.allows(Exception.ORIENTATION)) {
                    crop = orientation.rotate_box(raw, crop);
                    rotated_raw = orientation.rotate_dimensions(raw);
                }
                
                // scale the rotated crop to fit in the viewport
                Box scaled_crop = crop.get_scaled(scaling.get_scaled_dimensions(crop.get_dimensions()));
                
                // the viewport size is the size of the scaled crop
                scaled_to_viewport = scaled_crop.get_dimensions();
                    
                // only scale the image if the crop is larger than the viewport
                if (crop.get_width() <= scaled_crop.get_width() 
                    && crop.get_height() <= scaled_crop.get_height()) {
                    scaled_image = raw;
                    scaled_to_viewport = crop.get_dimensions();
                    
                    return false;
                }
                // resize the total pixbuf so the crop slices directly from the scaled pixbuf, 
                // with no need for resizing thereafter.  The decoded size is determined by the 
                // proportion of the actual size to the crop size
                scaled_image = rotated_raw.get_scaled_similar(crop.get_dimensions(), 
                    scaled_crop.get_dimensions());
                
                // derotate, as the loader knows nothing about orientation
                if (exceptions.allows(Exception.ORIENTATION))
                    scaled_image = orientation.derotate_dimensions(scaled_image);
            }
        }
        
        // if scaled_image not set, merely scale the raw pixbuf
        if (!scaled_image.has_area()) {
            // rotate for the scaler
            Dimensions rotated_raw = raw;
            if (exceptions.allows(Exception.ORIENTATION))
                rotated_raw = orientation.rotate_dimensions(raw);

            scaled_image = scaling.get_scaled_dimensions(rotated_raw);
            scaled_to_viewport = scaled_image;
        
            // derotate the scaled dimensions, as the loader knows nothing about orientation
            if (exceptions.allows(Exception.ORIENTATION))
                scaled_image = orientation.derotate_dimensions(scaled_image);
        }

        // do not scale up
        if (scaled_image.width >= raw.width && scaled_image.height >= raw.height) {
            scaled_image = raw;
            
            return false;
        }
        
        assert(scaled_image.has_area());
        assert(scaled_to_viewport.has_area());
        
        return true;
    }

    // Returns a raw, untransformed, unrotated pixbuf directly from the source.  Scaling provides
    // asked for a scaled-down image, which has certain performance benefits if the resized
    // JPEG is scaled down by a factor of a power of two (one-half, one-fourth, etc.).
    private Gdk.Pixbuf load_raw_pixbuf(Scaling scaling, Exception exceptions,
        BackingFetchMode fetch_mode = BackingFetchMode.BASELINE) throws Error {
        
        PhotoFileReader loader = get_backing_reader(fetch_mode);
        
        // no scaling, load and get out
        if (scaling.is_unscaled()) {
#if MEASURE_PIPELINE
            debug("LOAD_RAW_PIXBUF UNSCALED %s: requested", loader.get_filepath());
#endif
            
            return loader.unscaled_read();
        }
        
        // Need the dimensions of the image to load
        Dimensions scaled_image, scaled_to_viewport;
        bool is_scaled = calculate_pixbuf_dimensions(scaling, exceptions, out scaled_image, 
            out scaled_to_viewport);
        if (!is_scaled) {
#if MEASURE_PIPELINE
            debug("LOAD_RAW_PIXBUF UNSCALED %s: scaling unavailable", loader.get_filepath());
#endif
            
            return loader.unscaled_read();
        }
        
        Gdk.Pixbuf pixbuf = loader.scaled_read(get_raw_dimensions(), scaled_image);
        
#if MEASURE_PIPELINE
        debug("LOAD_RAW_PIXBUF %s %s: %s -> %s (actual: %s)", scaling.to_string(), loader.get_filepath(),
            get_raw_dimensions().to_string(), scaled_image.to_string(), 
            Dimensions.for_pixbuf(pixbuf).to_string());
#endif
        
        assert(scaled_image.approx_equals(Dimensions.for_pixbuf(pixbuf), SCALING_FUDGE));
        
        return pixbuf;
    }

    // Returns a raw, untransformed, scaled pixbuf from the master that has been optionally rotated
    // according to its original EXIF settings.
    public Gdk.Pixbuf get_master_pixbuf(Scaling scaling, bool rotate = true) throws Error {
        return get_untransformed_pixbuf(scaling, rotate, BackingFetchMode.MASTER);
    }
    
    // Returns a pixbuf that hasn't been modified (head of the pipeline.)
    public Gdk.Pixbuf get_unmodified_pixbuf(Scaling scaling, bool rotate = true) throws Error {
        return get_untransformed_pixbuf(scaling, rotate, BackingFetchMode.UNMODIFIED);
    }
    
    // Returns an untransformed pixbuf with optional scaling, rotation, and fetch mode.
    private Gdk.Pixbuf get_untransformed_pixbuf(Scaling scaling, bool rotate, BackingFetchMode fetch_mode) 
        throws Error {
#if MEASURE_PIPELINE
        Timer timer = new Timer();
        Timer total_timer = new Timer();
        double orientation_time = 0.0;
        
        total_timer.start();
#endif
        
        // get required fields all at once, to avoid holding the row lock
        Dimensions scaled_image, scaled_to_viewport;
        Orientation original_orientation;
        
        lock (row) {
            calculate_pixbuf_dimensions(scaling, Exception.NONE, out scaled_image, 
                out scaled_to_viewport);
            original_orientation = get_original_orientation();
        }

        // load-and-decode and scale
        Gdk.Pixbuf pixbuf = load_raw_pixbuf(scaling, Exception.NONE, fetch_mode);
            
        // orientation
#if MEASURE_PIPELINE
        timer.start();
#endif
        if (rotate)
            pixbuf = original_orientation.rotate_pixbuf(pixbuf);

#if MEASURE_PIPELINE
        orientation_time = timer.elapsed();

        debug("MASTER PIPELINE %s (%s): orientation=%lf total=%lf", to_string(), scaling.to_string(),
            orientation_time, total_timer.elapsed());
#endif

        return pixbuf;
    }

    public override Gdk.Pixbuf get_pixbuf(Scaling scaling) throws Error {
        return get_pixbuf_with_options(scaling);
    }
    
    /**
     * One-stop shopping for the source pixbuf cache.
     *
     * The source pixbuf cache holds untransformed, unscaled (full-sized) pixbufs of Photo objects.
     * These can be rather large and shouldn't be held in memory for too long, nor should many be
     * allowed to stack up.
     *
     * If locate is non-null, a source pixbuf is returned for the Photo.  If keep is true, the
     * pixbuf is stored in the cache.  (Thus, passing a Photo w/ keep == false will drop the cached
     * pixbuf.)  If Photo is non-null but keep is false, null is returned.
     *
     * Whether locate is null or not, the cache is walked in its entirety, dropping expired pixbufs
     * and dropping excessive pixbufs from the LRU.  Locating a Photo "touches" the pixbuf, i.e.
     * it moves to the head of the LRU.
     */
    private static Gdk.Pixbuf? run_source_pixbuf_cache(Photo? locate, bool keep) throws Error {
        lock (source_pixbuf_cache) {
            CachedPixbuf? found = null;
            
            // walk list looking for photo to locate (if specified), dropping expired and LRU'd
            // pixbufs along the way
            double min_elapsed = double.MAX;
            int count = 0;
            Gee.Iterator<CachedPixbuf> iter = source_pixbuf_cache.iterator();
            while (iter.next()) {
                CachedPixbuf cached_pixbuf = iter.get();
                
                double elapsed = Math.trunc(cached_pixbuf.last_touched.elapsed()) + 1;
                
                if (locate != null && cached_pixbuf.photo.equals(locate)) {
                    // found it, remove and reinsert at head of LRU (below)...
                    iter.remove();
                    found = cached_pixbuf;
                    
                    // ...that's why the counter is incremented
                    count++;
                } else if (elapsed >= SOURCE_PIXBUF_TIME_TO_LIVE_SEC) {
                    iter.remove();
                } else if (count >= SOURCE_PIXBUF_MAX_LRU_COUNT) {
                    iter.remove();
                } else {
                    // find the item with the least elapsed time to reschedule a cache trim (to
                    // prevent onesy-twosy reschedules)
                    min_elapsed = double.min(elapsed, min_elapsed);
                    count++;
                }
            }
            
            // if not found and trying to locate one and keep it, generate now
            if (found == null && locate != null && keep) {
                found = new CachedPixbuf(locate,
                    locate.load_raw_pixbuf(Scaling.for_original(), Exception.ALL, BackingFetchMode.SOURCE));
            } else if (found != null) {
                // since it was located, touch it so it doesn't expire
                found.last_touched.start();
            }
            
            // if keeping it, insert at head of LRU
            if (found != null && keep) {
                source_pixbuf_cache.insert(0, found);
                
                // since this is (re-)inserted, count its elapsed time too ... w/ min_elapsed, this
                // is almost guaranteed to be the min, since it was was touched mere clock cycles
                // ago...
                min_elapsed = double.min(found.last_touched.elapsed(), min_elapsed);
                
                // ...which means don't need to readjust the min_elapsed when trimming off excess
                // due to adding back an element
                while(source_pixbuf_cache.size > SOURCE_PIXBUF_MAX_LRU_COUNT)
                    source_pixbuf_cache.poll_tail();
            }
            
            // drop expiration timer...
            if (discard_source_id != 0) {
                Source.remove(discard_source_id);
                discard_source_id = 0;
            }
            
            // ...only reschedule if there's something to expire
            if (source_pixbuf_cache.size > SOURCE_PIXBUF_MIN_LRU_COUNT) {
                assert(min_elapsed >= 0.0);
                
                // round-up to avoid a bunch of zero-second timeouts
                uint retry_sec = SOURCE_PIXBUF_TIME_TO_LIVE_SEC - ((uint) Math.trunc(min_elapsed));
                discard_source_id = Timeout.add_seconds(retry_sec, trim_source_pixbuf_cache, Priority.LOW);
            }
            
            return found != null ? found.pixbuf : null;
        }
    }
    
    private static bool trim_source_pixbuf_cache() {
        try {
            run_source_pixbuf_cache(null, false);
        } catch (Error err) {
        }
        
        return false;
    }
    
    /**
     * @brief Get a copy of what's in the cache.
     *
     * @return A copy of the Pixbuf with the image data from unmodified_precached.
     */
    public Gdk.Pixbuf get_prefetched_copy() throws Error {
        return run_source_pixbuf_cache(this, true).copy();
    }

    /**
     * @brief Discards the cached version of the unmodified image.
     */
    public void discard_prefetched() {
        try {
            run_source_pixbuf_cache(this, false);
        } catch (Error err) {
        }
    }
    
    /**
     * @brief Returns a fully transformed and scaled pixbuf.  Transformations may be excluded via
     * the mask. If the image is smaller than the scaling, it will be returned in its actual size.
     * The caller is responsible for scaling thereafter.
     *
     * @param scaling A scaling object that describes the size the output pixbuf should be.
     * @param exceptions The parts of the pipeline that should be skipped; defaults to NONE if
     *      left unset.
     * @param fetch_mode The fetch mode; if left unset, defaults to BASELINE so that
     *      we get the image exactly as it is in the file.
     */ 
    public Gdk.Pixbuf get_pixbuf_with_options(Scaling scaling, Exception exceptions =
        Exception.NONE, BackingFetchMode fetch_mode = BackingFetchMode.BASELINE) throws Error {

#if MEASURE_PIPELINE
        Timer timer = new Timer();
        Timer total_timer = new Timer();
        double redeye_time = 0.0, crop_time = 0.0, adjustment_time = 0.0, orientation_time = 0.0,
            straighten_time = 0.0, scale_time = 0.0;

        total_timer.start();
#endif

        // If this is a RAW photo, ensure the development is ready.
        if (Photo.develop_raw_photos_to_files &&
            get_master_file_format() == PhotoFileFormat.RAW && 
            (fetch_mode == BackingFetchMode.BASELINE || fetch_mode == BackingFetchMode.UNMODIFIED
            || fetch_mode == BackingFetchMode.SOURCE) &&
            !is_raw_developer_complete(get_raw_developer()))
                set_raw_developer(get_raw_developer());

        // to minimize holding the row lock, fetch everything needed for the pipeline up-front
        bool is_scaled, is_cropped, is_straightened;
        Dimensions scaled_to_viewport;
        Dimensions original = Dimensions();
        Dimensions scaled = Dimensions();
        EditingTools.RedeyeInstance[] redeye_instances = null;
        Box crop;
        double straightening_angle;
        PixelTransformer transformer = null;
        Orientation orientation;

        lock (row) {
            original = get_dimensions(Exception.ALL);
            scaled = scaling.get_scaled_dimensions(get_dimensions(exceptions));
            scaled_to_viewport = scaled;
            
            is_scaled = !(get_dimensions().equals(scaled));
                        
            redeye_instances = get_raw_redeye_instances();
            
            is_cropped = get_raw_crop(out crop);

            is_straightened = get_raw_straighten(out straightening_angle);
            
            if (has_color_adjustments())
                transformer = get_pixel_transformer();

            orientation = get_orientation();
        }
        
        //
        // Image load-and-decode
        //
        
        Gdk.Pixbuf pixbuf = get_prefetched_copy();
        
        //
        // Image transformation pipeline
        //
        
        // redeye reduction
        if (exceptions.allows(Exception.REDEYE)) {
            
#if MEASURE_PIPELINE
            timer.start();
#endif
            foreach (EditingTools.RedeyeInstance instance in redeye_instances) {
                pixbuf = do_redeye(pixbuf, instance);
            }
#if MEASURE_PIPELINE
            redeye_time = timer.elapsed();
#endif
        }

        // angle photograph so in-image horizon is aligned with horizontal
        if (exceptions.allows(Exception.STRAIGHTEN)) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            if (is_straightened) {
                pixbuf = rotate_arb(pixbuf, straightening_angle);
            }
            
#if MEASURE_PIPELINE
            straighten_time = timer.elapsed();
#endif
        }

        // crop
        if (exceptions.allows(Exception.CROP)) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            if (is_cropped) {

                // ensure the crop region stays inside the scaled image boundaries and is
                // at least 1 px by 1 px; this is needed as a work-around for inaccuracies
                // which can occur when zooming.
                crop.left = crop.left.clamp(0, pixbuf.width - 2);
                crop.top = crop.top.clamp(0, pixbuf.height - 2);

                crop.right = crop.right.clamp(crop.left + 1, pixbuf.width - 1);
                crop.bottom = crop.bottom.clamp(crop.top + 1, pixbuf.height - 1);

                pixbuf = new Gdk.Pixbuf.subpixbuf(pixbuf, crop.left, crop.top, crop.get_width(),
                     crop.get_height());
            }

#if MEASURE_PIPELINE
            crop_time = timer.elapsed();
#endif
        }
    
        // orientation (all modifications are stored in unrotated coordinate system)
        if (exceptions.allows(Exception.ORIENTATION)) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = orientation.rotate_pixbuf(pixbuf);
#if MEASURE_PIPELINE
            orientation_time = timer.elapsed();
#endif
        }
        
        // scale the scratch image, as needed.
        if (is_scaled) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            pixbuf = pixbuf.scale_simple(scaled_to_viewport.width, scaled_to_viewport.height, Gdk.InterpType.BILINEAR);
#if MEASURE_PIPELINE
            scale_time = timer.elapsed();
#endif
        }

        // color adjustment; we do this dead last, since, if an image has been scaled down,
        // it may allow us to reduce the amount of pixel arithmetic, increasing responsiveness.
        if (exceptions.allows(Exception.ADJUST)) {
#if MEASURE_PIPELINE
            timer.start();
#endif
            if (transformer != null)
                transformer.transform_pixbuf(pixbuf);
#if MEASURE_PIPELINE
            adjustment_time = timer.elapsed();
#endif
        }        

        // This is to verify the generated pixbuf matches the scale requirements; crop, straighten 
        // and orientation are all transformations that change the dimensions or aspect ratio of 
        // the pixbuf, and must be accounted for the test to be valid.
        if ((is_scaled) && (!is_straightened))
            assert(scaled_to_viewport.approx_equals(Dimensions.for_pixbuf(pixbuf), SCALING_FUDGE));
        
#if MEASURE_PIPELINE
        debug("PIPELINE %s (%s): redeye=%lf crop=%lf adjustment=%lf orientation=%lf straighten=%lf scale=%lf total=%lf",
            to_string(), scaling.to_string(), redeye_time, crop_time, adjustment_time,
            orientation_time, straighten_time, scale_time, total_timer.elapsed());
#endif
        
        return pixbuf;
    }

    
    //
    // File export
    //
    
    protected abstract bool has_user_generated_metadata();
    
    // Sets the metadata values for any user generated metadata, only called if
    // has_user_generated_metadata returns true
    protected abstract void set_user_metadata_for_export(PhotoMetadata metadata);
    
    // Returns the basename of the file if it were to be exported in format 'file_format'; if
    // 'file_format' is null, then return the basename of the file if it were to be exported in the
    // native backing format of the photo (i.e. no conversion is performed). If 'file_format' is
    // null and the native backing format is not writeable (i.e. RAW), then use the system
    // default file format, as defined in PhotoFileFormat
    public string get_export_basename(PhotoFileFormat? file_format = null) {
        if (file_format != null) {
            return file_format.get_properties().convert_file_extension(get_master_file()).get_basename();
        } else {
            if (get_file_format().can_write()) {
                return get_file_format().get_properties().convert_file_extension(
                    get_master_file()).get_basename();
            } else {
                return PhotoFileFormat.get_system_default_format().get_properties().convert_file_extension(
                    get_master_file()).get_basename();
            }
        }
    }
    
    private bool export_fullsized_backing(File file, bool export_metadata = true) throws Error {
        // See if the native reader supports writing ... if no matches, need to fall back
        // on a "regular" export, which requires decoding then encoding
        PhotoFileReader export_reader = null;
        bool is_master = true;
        lock (readers) {
            if (readers.editable != null && readers.editable.get_file_format().can_write_metadata()) {
                export_reader = readers.editable;
                is_master = false;
            } else if (readers.developer != null && readers.developer.get_file_format().can_write_metadata()) {
                export_reader = readers.developer;
                is_master = false;
            } else if (readers.master.get_file_format().can_write_metadata()) {
                export_reader = readers.master;
            }
        }
        
        if (export_reader == null)
            return false;
        
        PhotoFileFormatProperties format_properties = export_reader.get_file_format().get_properties();
        
        // Build a destination file with the caller's name but the appropriate extension
        File dest_file = format_properties.convert_file_extension(file);
        
        // Create a PhotoFileMetadataWriter that matches the PhotoFileReader's file format
        PhotoFileMetadataWriter writer = export_reader.get_file_format().create_metadata_writer(
            dest_file.get_path());
        
        debug("Exporting full-sized copy of %s to %s", to_string(), writer.get_filepath());
        
        export_reader.get_file().copy(dest_file, 
            FileCopyFlags.OVERWRITE | FileCopyFlags.TARGET_DEFAULT_PERMS, null, null);

        // If asking for an full-sized file and there are no alterations (transformations or EXIF)
        // *and* this is a copy of the original backing *and* there's no user metadata or title *and* metadata should be exported, then done
        if (!has_alterations() && is_master && !has_user_generated_metadata() &&
            (get_title() == null) && (get_comment() == null) && export_metadata)
            return true;
        
        // copy over relevant metadata if possible, otherwise generate new metadata
        PhotoMetadata? metadata = export_reader.read_metadata();
        if (metadata == null)
            metadata = export_reader.get_file_format().create_metadata();
        
        debug("Updating metadata of %s", writer.get_filepath());
        
        if (get_exposure_time() != 0)
            metadata.set_exposure_date_time(new MetadataDateTime(get_exposure_time()));
        else
            metadata.set_exposure_date_time(null);
        
        if(export_metadata) {
            //set metadata
            metadata.set_title(get_title());
            metadata.set_comment(get_comment());
            metadata.set_pixel_dimensions(get_dimensions()); // created by sniffing pixbuf not metadata
            metadata.set_orientation(get_orientation());
            metadata.set_software(Resources.APP_TITLE, Resources.APP_VERSION);
        
            if (get_orientation() != get_original_orientation())
                metadata.remove_exif_thumbnail();

            set_user_metadata_for_export(metadata);
        }
        else
            //delete metadata
            metadata.clear();

        writer.write_metadata(metadata);
        
        return true;
    }
    
    // Returns true if there's any reason that an export is required to fully represent the photo
    // on disk.  False essentially means that the source file (NOT NECESSARILY the master file)
    // *is* the full representation of the photo and its metadata.
    public bool is_export_required(Scaling scaling, PhotoFileFormat export_format) {
        return (!scaling.is_unscaled() || has_alterations() || has_user_generated_metadata()
            || export_format != get_file_format());
    }
    
    // TODO: Lossless transformations, especially for mere rotations of JFIF files.
    //
    // This method is thread-safe.
    public void export(File dest_file, Scaling scaling, Jpeg.Quality quality,
        PhotoFileFormat export_format, bool direct_copy_unmodified = false, bool export_metadata = true) throws Error {
        if (direct_copy_unmodified) {
            get_master_file().copy(dest_file, FileCopyFlags.OVERWRITE |
                FileCopyFlags.TARGET_DEFAULT_PERMS, null, null);
            return;
        }

        // Attempt to avoid decode/encoding cycle when exporting original-sized photos for lossy
        // formats, as that degrades image quality. If alterations exist, but only EXIF has
        // changed and the user hasn't requested conversion between image formats, then just copy
        // the original file and update relevant EXIF.
        if (scaling.is_unscaled() && (!has_alterations() || only_metadata_changed()) &&
            (export_format == get_file_format()) && (get_file_format() == PhotoFileFormat.JFIF)) {
            if (export_fullsized_backing(dest_file, export_metadata))
                return;
        }

        // Copy over existing metadata from source if available, or create new metadata and 
        // save it for later export below.  This has to happen before the format writer writes
        // out the modified image, as that write will strip the existing exif data.
        PhotoMetadata? metadata = get_metadata();
        if (metadata == null)
            metadata = export_format.create_metadata();       

        if (!export_format.can_write())
            export_format = PhotoFileFormat.get_system_default_format();

        PhotoFileWriter writer = export_format.create_writer(dest_file.get_path());

        debug("Saving transformed version of %s to %s in file format %s", to_string(),
            writer.get_filepath(), export_format.to_string());
        
        Gdk.Pixbuf pixbuf;
        
        // Since JPEGs can store their own orientation, we save the pixels
        // directly and let the orientation field do the rotation...
        if ((get_file_format() == PhotoFileFormat.JFIF) || 
            (get_file_format() == PhotoFileFormat.RAW)) {
            pixbuf = get_pixbuf_with_options(scaling, Exception.ORIENTATION,
                BackingFetchMode.SOURCE);
        } else {
            // Non-JPEG image - we'll need to save the rotated pixels.
            pixbuf = get_pixbuf_with_options(scaling, Exception.NONE,
                BackingFetchMode.SOURCE);
        }
        
        writer.write(pixbuf, quality);
        
        debug("Setting EXIF for %s", writer.get_filepath());
        
        // Do we need to save metadata to this file?
        if (export_metadata) {
            //Yes, set metadata obtained above.
            metadata.set_title(get_title());
            metadata.set_comment(get_comment());
            metadata.set_software(Resources.APP_TITLE, Resources.APP_VERSION);
            
            if (get_exposure_time() != 0)
                metadata.set_exposure_date_time(new MetadataDateTime(get_exposure_time()));
            else
                metadata.set_exposure_date_time(null);
            
            metadata.remove_tag("Exif.Iop.RelatedImageWidth");
            metadata.remove_tag("Exif.Iop.RelatedImageHeight");
            metadata.remove_exif_thumbnail();
            
            if (has_user_generated_metadata())
                set_user_metadata_for_export(metadata);
        }
        else {
            //No, delete metadata.
            metadata.clear();
        }
        
        // Even if we were told to trash camera-identifying data, we need
        // to make sure the orientation propagates. Also, because JPEGs
        // can store their own orientation, we'll save the original dimensions
        // directly and let the orientation field do the rotation there.
        if ((get_file_format() == PhotoFileFormat.JFIF) || 
            (get_file_format() == PhotoFileFormat.RAW)) {
            metadata.set_pixel_dimensions(get_dimensions(Exception.ORIENTATION));
            metadata.set_orientation(get_orientation());
        } else {
            // Non-JPEG image - we'll need to save the rotated dimensions.
            metadata.set_pixel_dimensions(Dimensions.for_pixbuf(pixbuf));
            metadata.set_orientation(Orientation.TOP_LEFT);
        }
        
        export_format.create_metadata_writer(dest_file.get_path()).write_metadata(metadata);
    }
    
    private File generate_new_editable_file(out PhotoFileFormat file_format) throws Error {
        File backing;
        lock (row) {
            file_format = get_file_format();
            backing = get_file();
        }
        
        if (!file_format.can_write())
            file_format = PhotoFileFormat.get_system_default_format();
        
        string name, ext;
        disassemble_filename(backing.get_basename(), out name, out ext);
        
        if (ext == null || !file_format.get_properties().is_recognized_extension(ext))
            ext = file_format.get_properties().get_default_extension();
        
        string editable_basename = "%s_%s.%s".printf(name, _("modified"), ext);
        
        bool collision;
        return generate_unique_file(backing.get_parent(), editable_basename, out collision);
    }
    
    private static bool launch_editor(File file, PhotoFileFormat file_format) throws Error {
        string commandline = file_format == PhotoFileFormat.RAW ? Config.Facade.get_instance().get_external_raw_app() : 
            Config.Facade.get_instance().get_external_photo_app();

        if (is_string_empty(commandline))
            return false;
        
        AppInfo? app;
        try {
            app = AppInfo.create_from_commandline(commandline, "", 
                AppInfoCreateFlags.NONE);
        } catch (Error er) {
            app = null;
        }

        List<File> files = new List<File>();
        files.insert(file, -1);

        if (app != null)
            return app.launch(files, null);
        
        string[] argv = new string[2];
        argv[0] = commandline;
        argv[1] = file.get_path();

        Pid child_pid;

        return Process.spawn_async(
            "/",
            argv,
            null, // environment
            SpawnFlags.SEARCH_PATH,
            null, // child setup
            out child_pid);
    }
    
    // Opens with Ufraw, etc.
    public void open_with_raw_external_editor() throws Error {
        launch_editor(get_master_file(), get_master_file_format());
    }
    
    // Opens with GIMP, etc.
    public void open_with_external_editor() throws Error {
        File current_editable_file = null;
        File create_editable_file = null;
        PhotoFileFormat editable_file_format;
        lock (readers) {
            if (readers.editable != null)
                current_editable_file = readers.editable.get_file();
            
            if (current_editable_file == null)
                create_editable_file = generate_new_editable_file(out editable_file_format);
            else
                editable_file_format = readers.editable.get_file_format();
        }
        
        // if this isn't the first time but the file does not exist OR there are transformations
        // that need to be represented there, create a new one
        if (create_editable_file == null && current_editable_file != null && 
            (!current_editable_file.query_exists(null) || has_transformations()))
            create_editable_file = current_editable_file;
        
        // if creating a new edited file and can write to it, stop watching the old one
        if (create_editable_file != null && editable_file_format.can_write()) {
            halt_monitoring_editable();
            
            try {
                export(create_editable_file, Scaling.for_original(), Jpeg.Quality.MAXIMUM, 
                    editable_file_format);
            } catch (Error err) {
                // if an error is thrown creating the file, clean it up
                try {
                    create_editable_file.delete(null);
                } catch (Error delete_err) {
                    // ignored
                    warning("Unable to delete editable file %s after export error: %s", 
                        create_editable_file.get_path(), delete_err.message);
                }
                
                throw err;
            }
            
            // attach the editable file to the photo
            attach_editable(editable_file_format, create_editable_file);
            
            current_editable_file = create_editable_file;
        }
        
        assert(current_editable_file != null);
        
        // if not already monitoring, monitor now
        if (editable_monitor == null)
            start_monitoring_editable(current_editable_file);
        
        launch_editor(current_editable_file, get_file_format());
    }
    
    public void revert_to_master(bool notify = true) {
        detach_editable(true, true, notify);
    }
    
    private void start_monitoring_editable(File file) throws Error {
        halt_monitoring_editable();
        
        // tell the LibraryMonitor not to monitor this file
        LibraryMonitor.blacklist_file(file, "Photo.start_monitoring_editable");
        
        editable_monitor = file.monitor(FileMonitorFlags.NONE, null);
        editable_monitor.changed.connect(on_editable_file_changed);
    }
    
    private void halt_monitoring_editable() {
        if (editable_monitor == null)
            return;
        
        // tell the LibraryMonitor a-ok to watch this file again
        File? file = get_editable_file();
        if (file != null)
            LibraryMonitor.unblacklist_file(file);
        
        editable_monitor.changed.disconnect(on_editable_file_changed);
        editable_monitor.cancel();
        editable_monitor = null;
    }
    
    private void attach_editable(PhotoFileFormat file_format, File file) throws Error { 
        // remove the transformations ... this must be done before attaching the editable, as these 
        // transformations are in the master's coordinate system, not the editable's ... don't 
        // notify photo is altered *yet* because update_editable will notify, and want to avoid 
        // stacking them up
        remove_all_transformations(false);
        update_editable(false, file_format.create_reader(file.get_path()));
    }
    
    private void update_editable_attributes() throws Error {
        update_editable(true, null);
    }
    
    public void reimport_editable() throws Error {
        update_editable(false, null);
    }
    
    // In general, because of the fragility of the order of operations and what's required where,
    // use one of the above wrapper functions to call this rather than call this directly.
    private void update_editable(bool only_attributes, PhotoFileReader? new_reader = null) throws Error {
        // only_attributes only available for updating existing editable
        assert((only_attributes && new_reader == null) || (!only_attributes));
        
        PhotoFileReader? old_reader = get_editable_reader();
        
        PhotoFileReader reader = new_reader ?? old_reader;
        if (reader == null) {
            detach_editable(false, true);
            
            return;
        }
        
        bool timestamp_changed = false;
        bool filesize_changed = false;
        bool is_new_editable = false;

        BackingPhotoID editable_id = get_editable_id();
        File file = reader.get_file();
        
        DetectedPhotoInformation detected;
        BackingPhotoRow? backing = query_backing_photo_row(file, PhotoFileSniffer.Options.NO_MD5, 
            out detected);        
            
        // Have we _not_ got an editable attached yet?    
        if (editable_id.is_invalid()) {
            // Yes, try to create and attach one.
            if (backing != null) {
                BackingPhotoTable.get_instance().add(backing);
                lock (row) {
                    timestamp_changed = true;
                    filesize_changed = true;
                         
                    PhotoTable.get_instance().attach_editable(row, backing.id);
                    editable = backing;
                    backing_photo_row = editable;
                    set_orientation(backing_photo_row.original_orientation);
                }
            }
            is_new_editable = true;            
        } 
               
        if (only_attributes) {  
            // This should only be possible if the editable exists already.
            assert(editable_id.is_valid());
            
            FileInfo info;
            try {
                info = file.query_filesystem_info(DirectoryMonitor.SUPPLIED_ATTRIBUTES, null);
            } catch (Error err) {
                warning("Unable to read editable filesystem info for %s: %s", to_string(), err.message);
                detach_editable(false, true);
                
                return;
            }
            
            TimeVal timestamp = info.get_modification_time();
        
            BackingPhotoTable.get_instance().update_attributes(editable_id, timestamp.tv_sec,
                info.get_size());
            lock (row) {
                timestamp_changed = editable.timestamp != timestamp.tv_sec;
                filesize_changed = editable.filesize != info.get_size();
                
                editable.timestamp = timestamp.tv_sec;
                editable.filesize = info.get_size();
            }
        } else {
            // Not just a file-attribute-only change.
            if (editable_id.is_valid() && !is_new_editable) {
                // Only check these if we didn't just have to create
                // this editable, since, with a newly-created editable,
                // the file size and modification time are by definition
                // freshly-changed.
                backing.id = editable_id;
                BackingPhotoTable.get_instance().update(backing);
                lock (row) {
                    timestamp_changed = editable.timestamp != backing.timestamp;
                    filesize_changed = editable.filesize != backing.filesize;
                    
                    editable = backing;
                    backing_photo_row = editable;
                    set_orientation(backing_photo_row.original_orientation);
                }
            }
        }           
        
        // if a new reader was specified, install that and begin using it
        if (new_reader != null) {
            lock (readers) {
                readers.editable = new_reader;
            }
        }
        
        if (!only_attributes && reader != old_reader) {
            notify_baseline_replaced();
            notify_editable_replaced(old_reader != null ? old_reader.get_file() : null,
                new_reader != null ? new_reader.get_file() : null);
        }
        
        string[] alteration_list = new string[0];
        if (timestamp_changed) {
            alteration_list += "metadata:editable-timestamp";
            alteration_list += "metadata:baseline-timestamp";
            
            if (is_editable_source())
                alteration_list += "metadata:source-timestamp";
        }
        
        if (filesize_changed || new_reader != null) {
            alteration_list += "image:editable";
            alteration_list += "image:baseline";
            
            if (is_editable_source())
                alteration_list += "image:source";
        }
        
        if (alteration_list.length > 0)
            notify_altered(new Alteration.from_array(alteration_list));
    }
    
    private void detach_editable(bool delete_editable, bool remove_transformations, bool notify = true) {
        halt_monitoring_editable();
        
        bool has_editable = false;
        File? editable_file = null;
        lock (readers) {
            if (readers.editable != null) {
                editable_file = readers.editable.get_file();
                readers.editable = null;
                has_editable = true;
            }
        }
        
        if (has_editable) {
            BackingPhotoID editable_id = BackingPhotoID();
            try {
                lock (row) {
                    editable_id = row.editable_id;
                    if (editable_id.is_valid())
                        PhotoTable.get_instance().detach_editable(row);
                    backing_photo_row = row.master;
                }
            } catch (DatabaseError err) {
                warning("Unable to remove editable from PhotoTable: %s", err.message);
            }
            
            try {
                if (editable_id.is_valid())
                    BackingPhotoTable.get_instance().remove(editable_id);
            } catch (DatabaseError err) {
                warning("Unable to remove editable from BackingPhotoTable: %s", err.message);
            }
        }
        
        if (remove_transformations)
            remove_all_transformations(false);
        
        if (has_editable) {
            notify_baseline_replaced();
            notify_editable_replaced(editable_file, null);
        }
        
        if (delete_editable && editable_file != null) {
            try {
                editable_file.trash(null);
            } catch (Error err) {
                warning("Unable to trash editable %s for %s: %s", editable_file.get_path(), to_string(),
                    err.message);
            }
        }
        
        if ((has_editable || remove_transformations) && notify)
            notify_altered(new Alteration("image", "revert"));
    }
    
    private void on_editable_file_changed(File file, File? other_file, FileMonitorEvent event) {
        // This has some expense, but this assertion is important for a lot of sanity reasons.
        lock (readers) {
            assert(readers.editable != null);

            if (!file.equal(readers.editable.get_file())) {
                // Ignore. When the export file is created, we receive a
                // DELETE event for renaming temporary file created by exiv2 when
                // writing meta-data.
                return;
            }
        }
        
        debug("EDITABLE %s: %s", event.to_string(), file.get_path());
        
        switch (event) {
            case FileMonitorEvent.CHANGED:
            case FileMonitorEvent.CREATED:
                if (reimport_editable_scheduler == null) {
                    reimport_editable_scheduler = new OneShotScheduler("Photo.reimport_editable", 
                        on_reimport_editable);
                }
                
                reimport_editable_scheduler.after_timeout(1000, true);
            break;
            
            case FileMonitorEvent.ATTRIBUTE_CHANGED:
                if (update_editable_attributes_scheduler == null) {
                    update_editable_attributes_scheduler = new OneShotScheduler(
                        "Photo.update_editable_attributes", on_update_editable_attributes);
                }
                
                update_editable_attributes_scheduler.after_timeout(1000, true);
            break;
            
            case FileMonitorEvent.DELETED:
                if (remove_editable_scheduler == null) {
                    remove_editable_scheduler = new OneShotScheduler("Photo.remove_editable",
                        on_remove_editable);
                }
                
                remove_editable_scheduler.after_timeout(3000, true);
            break;
            
            case FileMonitorEvent.CHANGES_DONE_HINT:
            default:
                // ignored
            break;
        }

        // at this point, any image date we have cached is stale,
        // so delete it and force the pipeline to re-fetch it
        discard_prefetched();
    }
    
    private void on_reimport_editable() {
        // delete old image data and force the pipeline to load new from file.
        discard_prefetched();
        
        debug("Reimporting editable for %s", to_string());
        try {
            reimport_editable();
        } catch (Error err) {
            warning("Unable to reimport photo %s changed by external editor: %s",
                to_string(), err.message);
        }
    }
    
    private void on_update_editable_attributes() {
        debug("Updating editable attributes for %s", to_string());
        try {
            update_editable_attributes();
        } catch (Error err) {
            warning("Unable to update editable attributes: %s", err.message);
        }
    }
    
    private void on_remove_editable() {
        PhotoFileReader? reader = get_editable_reader();
        if (reader == null)
            return;
        
        File file = reader.get_file();
        if (file.query_exists(null)) {
            debug("Not removing editable for %s: file exists", to_string());
            
            return;
        }
        
        debug("Removing editable for %s: file no longer exists", to_string());
        detach_editable(false, true);
    }
    
    //
    // Aggregate/helper/translation functions
    //
    
    // Returns uncropped (but rotated) dimensions
    public Dimensions get_original_dimensions() {
        Dimensions dim = get_raw_dimensions();
        Orientation orientation = get_orientation();
        
        return orientation.rotate_dimensions(dim);
    }
    
    // Returns uncropped dimensions rotated only to reflect the original orientation
    public Dimensions get_master_dimensions() {
        return get_original_orientation().rotate_dimensions(get_raw_dimensions());
    }
    
    // Returns the crop against the coordinate system of the rotated photo
    public bool get_crop(out Box crop, Exception exceptions = Exception.NONE) {
        Box raw;
        if (!get_raw_crop(out raw)) {
            crop = Box();
            
            return false;
        }
        
        Dimensions dim = get_dimensions(Exception.CROP | Exception.ORIENTATION);
        Orientation orientation = get_orientation();
        
        if(exceptions.allows(Exception.ORIENTATION))
            crop = orientation.rotate_box(dim, raw);
        else
            crop = raw;
        
        return true;
    }
    
    // Sets the crop against the coordinate system of the rotated photo
    public void set_crop(Box crop) {                                                                
        Dimensions dim = get_dimensions(Exception.CROP | Exception.ORIENTATION);
        Orientation orientation = get_orientation();

        Box derotated = orientation.derotate_box(dim, crop);

        derotated.left = derotated.left.clamp(0, dim.width - 2);
        derotated.right = derotated.right.clamp(derotated.left, dim.width - 1);

        derotated.top = derotated.top.clamp(0, dim.height - 2);
        derotated.bottom = derotated.bottom.clamp(derotated.top, dim.height - 1);
        
        set_raw_crop(derotated);
    }
    
    public bool get_straighten(out double theta) {
        if (!get_raw_straighten(out theta))
            return false;
             
        return true;
    }
    
    public void set_straighten(double theta) {            
        set_raw_straighten(theta);
    }
    
    private Gdk.Pixbuf do_redeye(Gdk.Pixbuf pixbuf, EditingTools.RedeyeInstance inst) {
        /* we remove redeye within a circular region called the "effect
           extent." the effect extent is inscribed within its "bounding
           rectangle." */

        /* for each scanline in the top half-circle of the effect extent,
           compute the number of pixels by which the effect extent is inset
           from the edges of its bounding rectangle. note that we only have
           to do this for the first quadrant because the second quadrant's
           insets can be derived by symmetry */
        double r = (double) inst.radius;
        int[] x_insets_first_quadrant = new int[inst.radius + 1];
        
        int i = 0;
        for (double y = r; y >= 0.0; y -= 1.0) {
            double theta = Math.asin(y / r);
            int x = (int)((r * Math.cos(theta)) + 0.5);
            x_insets_first_quadrant[i] = inst.radius - x;
            
            i++;
        }

        int x_bounds_min = inst.center.x - inst.radius;
        int x_bounds_max = inst.center.x + inst.radius;
        int ymin = inst.center.y - inst.radius;
        ymin = (ymin < 0) ? 0 : ymin;
        int ymax = inst.center.y;
        ymax = (ymax > (pixbuf.height - 1)) ? (pixbuf.height - 1) : ymax;

        /* iterate over all the pixels in the top half-circle of the effect
           extent from top to bottom */
        int inset_index = 0;
        for (int y_it = ymin; y_it <= ymax; y_it++) {
            int xmin = x_bounds_min + x_insets_first_quadrant[inset_index];
            xmin = (xmin < 0) ? 0 : xmin;
            int xmax = x_bounds_max - x_insets_first_quadrant[inset_index];
            xmax = (xmax > (pixbuf.width - 1)) ? (pixbuf.width - 1) : xmax;

            for (int x_it = xmin; x_it <= xmax; x_it++) {
                red_reduce_pixel(pixbuf, x_it, y_it);
            }
            inset_index++;
        }

        /* iterate over all the pixels in the top half-circle of the effect
           extent from top to bottom */
        ymin = inst.center.y;
        ymax = inst.center.y + inst.radius;
        inset_index = x_insets_first_quadrant.length - 1;
        for (int y_it = ymin; y_it <= ymax; y_it++) {  
            int xmin = x_bounds_min + x_insets_first_quadrant[inset_index];
            xmin = (xmin < 0) ? 0 : xmin;
            int xmax = x_bounds_max - x_insets_first_quadrant[inset_index];
            xmax = (xmax > (pixbuf.width - 1)) ? (pixbuf.width - 1) : xmax;

            for (int x_it = xmin; x_it <= xmax; x_it++) {
                red_reduce_pixel(pixbuf, x_it, y_it);
            }
            inset_index--;
        }
        
        return pixbuf;
    }

    private Gdk.Pixbuf red_reduce_pixel(Gdk.Pixbuf pixbuf, int x, int y) {
        int px_start_byte_offset = (y * pixbuf.get_rowstride()) +
            (x * pixbuf.get_n_channels());
            
        /* Due to inaccuracies in the scaler, we can occasionally 
         * get passed a coordinate pair outside the image, causing
         * us to walk off the array and into segfault territory.
         * Check coords prior to drawing to prevent this...  */    
        if ((x >= 0) && (y >= 0) && (x < pixbuf.width) && (y < pixbuf.height)) {
            unowned uchar[] pixel_data = pixbuf.get_pixels();
        
            /* The pupil of the human eye has no pigment, so we expect all
               color channels to be of about equal intensity. This means that at
               any point within the effects region, the value of the red channel
               should be about the same as the values of the green and blue
               channels. So set the value of the red channel to be the mean of the
               values of the red and blue channels. This preserves achromatic
               intensity across all channels while eliminating any extraneous flare
               affecting the red channel only (i.e. the red-eye effect). */
            uchar g = pixel_data[px_start_byte_offset + 1];
            uchar b = pixel_data[px_start_byte_offset + 2];
            
            uchar r = (g + b) / 2;
            
            pixel_data[px_start_byte_offset] = r;
        }

        return pixbuf;
    }

    public Gdk.Point unscaled_to_raw_point(Gdk.Point unscaled_point) {
        Orientation unscaled_orientation = get_orientation();
    
        Dimensions unscaled_dims =
            unscaled_orientation.rotate_dimensions(get_dimensions());

        int unscaled_x_offset_raw = 0;
        int unscaled_y_offset_raw = 0;

        Box crop_box;
        if (get_raw_crop(out crop_box)) {
            unscaled_x_offset_raw = crop_box.left;
            unscaled_y_offset_raw = crop_box.top;
        }
        
        Gdk.Point derotated_point =
            unscaled_orientation.derotate_point(unscaled_dims,
            unscaled_point);

        derotated_point.x += unscaled_x_offset_raw;
        derotated_point.y += unscaled_y_offset_raw;

        return derotated_point;
    }
    
    public Gdk.Rectangle unscaled_to_raw_rect(Gdk.Rectangle unscaled_rect) {
        Gdk.Point upper_left = {0};
        Gdk.Point lower_right = {0};
        upper_left.x = unscaled_rect.x;
        upper_left.y = unscaled_rect.y;
        lower_right.x = upper_left.x + unscaled_rect.width;
        lower_right.y = upper_left.y + unscaled_rect.height;
        
        upper_left = unscaled_to_raw_point(upper_left);
        lower_right = unscaled_to_raw_point(lower_right);
        
        if (upper_left.x > lower_right.x) {
            int temp = upper_left.x;
            upper_left.x = lower_right.x;
            lower_right.x = temp;
        }
        if (upper_left.y > lower_right.y) {
            int temp = upper_left.y;
            upper_left.y = lower_right.y;
            lower_right.y = temp;
        }
        
        Gdk.Rectangle raw_rect = Gdk.Rectangle();
        raw_rect.x = upper_left.x;
        raw_rect.y = upper_left.y;
        raw_rect.width = lower_right.x - upper_left.x;
        raw_rect.height = lower_right.y - upper_left.y;
        
        return raw_rect;
    }

    public PixelTransformationBundle? get_enhance_transformations() {
        Gdk.Pixbuf pixbuf = null;

#if MEASURE_ENHANCE
        Timer fetch_timer = new Timer();
#endif

        try {
            pixbuf = get_pixbuf_with_options(Scaling.for_best_fit(360, false), 
                Photo.Exception.ALL);

#if MEASURE_ENHANCE
            fetch_timer.stop();
#endif
        } catch (Error e) {
            warning("Photo: get_enhance_transformations: couldn't obtain pixbuf to build " + 
                "transform histogram");
            return null;
        }

#if MEASURE_ENHANCE
        Timer analyze_timer = new Timer();
#endif

        PixelTransformationBundle transformations = AutoEnhance.create_auto_enhance_adjustments(pixbuf);

#if MEASURE_ENHANCE
        analyze_timer.stop();
        debug("Auto-Enhance fetch time: %f sec; analyze time: %f sec", fetch_timer.elapsed(),
            analyze_timer.elapsed());
#endif

        return transformations;
    }

    public bool enhance() {
        PixelTransformationBundle transformations = get_enhance_transformations();

        if (transformations == null)
            return false;

#if MEASURE_ENHANCE
        Timer apply_timer = new Timer();
#endif
        lock (row) {
            set_color_adjustments(transformations);
        }
        
#if MEASURE_ENHANCE
        apply_timer.stop();
        debug("Auto-Enhance apply time: %f sec", apply_timer.elapsed());
#endif
        return true;
    }
}

public class LibraryPhotoSourceCollection : MediaSourceCollection {
    public enum State {
        UNKNOWN,
        ONLINE,
        OFFLINE,
        TRASH,
        EDITABLE,
        DEVELOPER
    }
    
    public override TransactionController transaction_controller {
        get {
            if (_transaction_controller == null)
                _transaction_controller = new MediaSourceTransactionController(this);
            
            return _transaction_controller;
        }
    }
    
    private TransactionController? _transaction_controller = null;
    private Gee.HashMap<File, LibraryPhoto> by_editable_file = new Gee.HashMap<File, LibraryPhoto>(
        file_hash, file_equal);
    private Gee.HashMap<File, LibraryPhoto> by_raw_development_file = new Gee.HashMap<File, LibraryPhoto>(
        file_hash, file_equal);
    private Gee.MultiMap<int64?, LibraryPhoto> filesize_to_photo =
        new Gee.TreeMultiMap<int64?, LibraryPhoto>(int64_compare);
    private Gee.HashMap<LibraryPhoto, int64?> photo_to_master_filesize =
        new Gee.HashMap<LibraryPhoto, int64?>(null, null, int64_equal);
    private Gee.HashMap<LibraryPhoto, int64?> photo_to_editable_filesize =
        new Gee.HashMap<LibraryPhoto, int64?>(null, null, int64_equal);
    private Gee.MultiMap<LibraryPhoto, int64?> photo_to_raw_development_filesize =
        new Gee.TreeMultiMap<LibraryPhoto, int64?>();
    
    public virtual signal void master_reimported(LibraryPhoto photo, PhotoMetadata? metadata) {
    }
    
    public virtual signal void editable_reimported(LibraryPhoto photo, PhotoMetadata? metadata) {
    }
    
    public virtual signal void baseline_reimported(LibraryPhoto photo, PhotoMetadata? metadata) {
    }
    
    public virtual signal void source_reimported(LibraryPhoto photo, PhotoMetadata? metadata) {
    }
    
    public LibraryPhotoSourceCollection() {
        base ("LibraryPhotoSourceCollection", Photo.get_photo_key);
        
        get_trashcan().contents_altered.connect(on_trashcan_contents_altered);
        get_offline_bin().contents_altered.connect(on_offline_contents_altered);
    }
    
    protected override MediaSourceHoldingTank create_trashcan() {
        return new LibraryPhotoSourceHoldingTank(this, check_if_trashed_photo, Photo.get_photo_key);
    }

    protected override MediaSourceHoldingTank create_offline_bin() {
        return new LibraryPhotoSourceHoldingTank(this, check_if_offline_photo, Photo.get_photo_key);
    }
    
    public override MediaMonitor create_media_monitor(Workers workers, Cancellable cancellable) {
        return new PhotoMonitor(workers, cancellable);
    }
    
    public override bool holds_type_of_source(DataSource source) {
        return source is LibraryPhoto;
    }
    
    public override string get_typename() {
        return Photo.TYPENAME;
    }
    
    public override bool is_file_recognized(File file) {
        return PhotoFileFormat.is_file_supported(file);
    }
    
    protected override void notify_contents_altered(Gee.Iterable<DataObject>? added,
        Gee.Iterable<DataObject>? removed) {
        if (added != null) {
            foreach (DataObject object in added) {
                LibraryPhoto photo = (LibraryPhoto) object;
                
                File? editable = photo.get_editable_file();
                if (editable != null)
                    by_editable_file.set(editable, photo);
                photo.editable_replaced.connect(on_editable_replaced);
                
                Gee.Collection<File> raw_list = photo.get_raw_developer_files();
                if (raw_list != null)
                    foreach (File f in raw_list)
                        by_raw_development_file.set(f, photo);
                photo.raw_development_modified.connect(on_raw_development_modified);
                
                int64 master_filesize = photo.get_master_photo_row().filesize;
                int64 editable_filesize = photo.get_editable_photo_row() != null
                    ? photo.get_editable_photo_row().filesize
                    : -1;
                filesize_to_photo.set(master_filesize, photo);
                photo_to_master_filesize.set(photo, master_filesize);
                if (editable_filesize >= 0) {
                    filesize_to_photo.set(editable_filesize, photo);
                    photo_to_editable_filesize.set(photo, editable_filesize);
                }
                
                Gee.Collection<BackingPhotoRow>? raw_rows = photo.get_raw_development_photo_rows();
                if (raw_rows != null) {
                    foreach (BackingPhotoRow row in raw_rows) {
                        if (row.filesize >= 0) {
                            filesize_to_photo.set(row.filesize, photo);
                            photo_to_raw_development_filesize.set(photo, row.filesize);
                        }
                     }
                }
            }
        }
        
        if (removed != null) {
            foreach (DataObject object in removed) {
                LibraryPhoto photo = (LibraryPhoto) object;
                
                File? editable = photo.get_editable_file();
                if (editable != null) {
                    bool is_removed = by_editable_file.unset(photo.get_editable_file());
                    assert(is_removed);
                }
                photo.editable_replaced.disconnect(on_editable_replaced);
                
                Gee.Collection<File> raw_list = photo.get_raw_developer_files();
                if (raw_list != null)
                    foreach (File f in raw_list)
                        by_raw_development_file.unset(f);
                photo.raw_development_modified.disconnect(on_raw_development_modified);
                
                int64 master_filesize = photo.get_master_photo_row().filesize;
                int64 editable_filesize = photo.get_editable_photo_row() != null
                    ? photo.get_editable_photo_row().filesize
                    : -1;
                filesize_to_photo.remove(master_filesize, photo);
                photo_to_master_filesize.unset(photo);
                if (editable_filesize >= 0) {
                    filesize_to_photo.remove(editable_filesize, photo);
                    photo_to_editable_filesize.unset(photo);
                }
                
                Gee.Collection<BackingPhotoRow>? raw_rows = photo.get_raw_development_photo_rows();
                if (raw_rows != null) {
                    foreach (BackingPhotoRow row in raw_rows) {
                        if (row.filesize >= 0) {
                            filesize_to_photo.remove(row.filesize, photo);
                            photo_to_raw_development_filesize.remove(photo, row.filesize);
                        }
                     }
                }
            }
        }
        
        base.notify_contents_altered(added, removed);
    }
    
    private void on_editable_replaced(Photo photo, File? old_file, File? new_file) {
        if (old_file != null) {
            bool is_removed = by_editable_file.unset(old_file);
            assert(is_removed);
        }
        
        if (new_file != null)
            by_editable_file.set(new_file, (LibraryPhoto) photo);
    }
    
    private void on_raw_development_modified(Photo _photo) {
        LibraryPhoto? photo = _photo as LibraryPhoto;
        if (photo == null)
            return;
        
        // Unset existing files.
        if (photo_to_raw_development_filesize.contains(photo)) {
            foreach (int64 s in photo_to_raw_development_filesize.get(photo))
                filesize_to_photo.remove(s, photo);
            photo_to_raw_development_filesize.remove_all(photo);
        }
        
        // Add new ones.
        Gee.Collection<File> raw_list = photo.get_raw_developer_files();
        if (raw_list != null)
            foreach (File f in raw_list)
                by_raw_development_file.set(f, photo);
        
        Gee.Collection<BackingPhotoRow>? raw_rows = photo.get_raw_development_photo_rows();
        if (raw_rows != null) {
            foreach (BackingPhotoRow row in raw_rows) {
                if (row.filesize > 0) {
                    filesize_to_photo.set(row.filesize, photo);
                    photo_to_raw_development_filesize.set(photo, row.filesize);
                }
            }
        }
    }
    
    protected override void items_altered(Gee.Map<DataObject, Alteration> items) {
        foreach (DataObject object in items.keys) {
            Alteration alteration = items.get(object);
            
            LibraryPhoto photo = (LibraryPhoto) object;
            
            if (alteration.has_detail("image", "master") || alteration.has_detail("image", "editable")) {
                int64 old_master_filesize = photo_to_master_filesize.get(photo);
                int64 old_editable_filesize = photo_to_editable_filesize.has_key(photo)
                    ? photo_to_editable_filesize.get(photo)
                    : -1;
                
                photo_to_master_filesize.unset(photo);
                filesize_to_photo.remove(old_master_filesize, photo);
                if (old_editable_filesize >= 0) {
                    photo_to_editable_filesize.unset(photo);
                    filesize_to_photo.remove(old_editable_filesize, photo);
                }
                
                int64 master_filesize = photo.get_master_photo_row().filesize;
                int64 editable_filesize = photo.get_editable_photo_row() != null
                    ? photo.get_editable_photo_row().filesize
                    : -1;
                photo_to_master_filesize.set(photo, master_filesize);
                filesize_to_photo.set(master_filesize, photo);
                if (editable_filesize >= 0) {
                    photo_to_editable_filesize.set(photo, editable_filesize);
                    filesize_to_photo.set(editable_filesize, photo);
                }
            }
        }
        
        base.items_altered(items);
    }
    
    // This method adds the photos to the Tags (keywords) that were discovered during import.
    public override void postprocess_imported_media(Gee.Collection<MediaSource> media_sources) {
        Gee.HashMultiMap<Tag, LibraryPhoto> map = new Gee.HashMultiMap<Tag, LibraryPhoto>();
        foreach (MediaSource media in media_sources) {
            LibraryPhoto photo = (LibraryPhoto) media;
            PhotoMetadata? metadata = photo.get_metadata();
            
            // get an index of all the htags in the application
            HierarchicalTagIndex global_index = HierarchicalTagIndex.get_global_index();
            
            // if any hierarchical tag information is available, process it first. hierarchical tag
            // information must be processed first to avoid tag duplication, since most photo
            // management applications that support hierarchical tags also "flatten" the
            // hierarchical tag information as plain old tags. If a tag name appears as part of
            // a hierarchical path, it needs to be excluded from being processed as a flat tag
            HierarchicalTagIndex? htag_index = null;
            if (metadata != null && metadata.has_hierarchical_keywords()) {
                htag_index = HierarchicalTagUtilities.process_hierarchical_import_keywords(
                    metadata.get_hierarchical_keywords());
            }
            
            if (photo.get_import_keywords() != null) {
                foreach (string keyword in photo.get_import_keywords()) {
                    if (htag_index != null && htag_index.is_tag_in_index(keyword))
                        continue;

                    string? name = Tag.prep_tag_name(keyword);

                    if (global_index.is_tag_in_index(name)) {
                        string most_derived_path = global_index.get_path_for_name(name);
                        map.set(Tag.for_path(most_derived_path), photo);
                        continue;
                    }

                    if (name != null)
                        map.set(Tag.for_path(name), photo);
                }
            }
            
            if (metadata != null && metadata.has_hierarchical_keywords()) {
                foreach (string path in htag_index.get_all_paths()) {
                    string? name = Tag.prep_tag_name(path);
                    if (name != null)
                        map.set(Tag.for_path(name), photo);
                }
            }
        }
        
        foreach (MediaSource media in media_sources) {
            LibraryPhoto photo = (LibraryPhoto) media;
            photo.clear_import_keywords();
        }
        
        foreach (Tag tag in map.get_keys())
            tag.attach_many(map.get(tag));
        
        base.postprocess_imported_media(media_sources);
    }
    
    // This is only called by LibraryPhoto.
    public virtual void notify_master_reimported(LibraryPhoto photo, PhotoMetadata? metadata) {
        master_reimported(photo, metadata);
    }
    
    // This is only called by LibraryPhoto.
    public virtual void notify_editable_reimported(LibraryPhoto photo, PhotoMetadata? metadata) {
        editable_reimported(photo, metadata);
    }
    
    // This is only called by LibraryPhoto.
    public virtual void notify_source_reimported(LibraryPhoto photo, PhotoMetadata? metadata) {
        source_reimported(photo, metadata);
    }
    
    // This is only called by LibraryPhoto.
    public virtual void notify_baseline_reimported(LibraryPhoto photo, PhotoMetadata? metadata) {
        baseline_reimported(photo, metadata);
    }
    
    protected override MediaSource? fetch_by_numeric_id(int64 numeric_id) {
        return fetch(PhotoID(numeric_id));
    }

    private void on_trashcan_contents_altered(Gee.Collection<DataSource>? added,
        Gee.Collection<DataSource>? removed) {
        trashcan_contents_altered((Gee.Collection<LibraryPhoto>?) added,
            (Gee.Collection<LibraryPhoto>?) removed);
    }
    
    private bool check_if_trashed_photo(DataSource source, Alteration alteration) {
        return ((LibraryPhoto) source).is_trashed();
    }
    
    private void on_offline_contents_altered(Gee.Collection<DataSource>? added,
        Gee.Collection<DataSource>? removed) {
        offline_contents_altered((Gee.Collection<LibraryPhoto>?) added,
            (Gee.Collection<LibraryPhoto>?) removed);
    }
    
    private bool check_if_offline_photo(DataSource source, Alteration alteration) {
        return ((LibraryPhoto) source).is_offline();
    }

    public override MediaSource? fetch_by_source_id(string source_id) {
        assert(source_id.has_prefix(Photo.TYPENAME));
        string numeric_only = source_id.substring(Photo.TYPENAME.length, -1);
        
        return fetch_by_numeric_id(parse_int64(numeric_only, 16));
    }

    public override Gee.Collection<string> get_event_source_ids(EventID event_id){
        return PhotoTable.get_instance().get_event_source_ids(event_id);
    }

    public LibraryPhoto fetch(PhotoID photo_id) {
        return (LibraryPhoto) fetch_by_key(photo_id.id);
    }
    
    public LibraryPhoto? fetch_by_editable_file(File file) {
        return by_editable_file.get(file);
    }
    
    public LibraryPhoto? fetch_by_raw_development_file(File file) {
        return by_raw_development_file.get(file);
    }
    
    private void compare_backing(LibraryPhoto photo, FileInfo info,
        Gee.Collection<LibraryPhoto> matches_master, Gee.Collection<LibraryPhoto> matches_editable,
        Gee.Collection<LibraryPhoto> matches_development) {
        if (photo.get_master_photo_row().matches_file_info(info))
            matches_master.add(photo);
        
        BackingPhotoRow? editable = photo.get_editable_photo_row();
        if (editable != null && editable.matches_file_info(info))
            matches_editable.add(photo);
        
        Gee.Collection<BackingPhotoRow>? development = photo.get_raw_development_photo_rows();
        if (development != null) {
            foreach (BackingPhotoRow row in development) {
                if (row.matches_file_info(info)) {
                    matches_development.add(photo);
                    
                    break;
                }
            }
        }
    }
    
    // Adds photos to both collections if their filesize and timestamp match.  Note that it's possible
    // for a single photo to be added to both collections.
    public void fetch_by_matching_backing(FileInfo info, Gee.Collection<LibraryPhoto> matches_master,
        Gee.Collection<LibraryPhoto> matches_editable, Gee.Collection<LibraryPhoto> matched_development) {
        foreach (LibraryPhoto photo in filesize_to_photo.get(info.get_size()))
            compare_backing(photo, info, matches_master, matches_editable, matched_development);
        
        foreach (MediaSource media in get_offline_bin_contents())
            compare_backing((LibraryPhoto) media, info, matches_master, matches_editable, matched_development);
    }
    
    public PhotoID get_basename_filesize_duplicate(string basename, int64 filesize) {
        foreach (LibraryPhoto photo in filesize_to_photo.get(filesize)) {
            if (utf8_ci_compare(photo.get_master_file().get_basename(), basename) == 0)
                return photo.get_photo_id();
        }
        
        return PhotoID(); // default constructor for PhotoIDs will create an invalid ID --
                          // this is just the behavior that we want
    }
    
    public bool has_basename_filesize_duplicate(string basename, int64 filesize) {
        return get_basename_filesize_duplicate(basename, filesize).is_valid();
    }
    
    public LibraryPhoto? get_trashed_by_file(File file) {
        LibraryPhoto? photo = (LibraryPhoto?) get_trashcan().fetch_by_master_file(file);
        if (photo == null)
            photo = (LibraryPhoto?) ((LibraryPhotoSourceHoldingTank) get_trashcan()).
                fetch_by_backing_file(file);
        
        return photo;
    }
    
    public LibraryPhoto? get_trashed_by_md5(string md5) {
        return (LibraryPhoto?) get_trashcan().fetch_by_md5(md5);
    }
    
    public LibraryPhoto? get_offline_by_file(File file) {
        LibraryPhoto? photo = (LibraryPhoto?) get_offline_bin().fetch_by_master_file(file);
        if (photo == null)
            photo = (LibraryPhoto?) ((LibraryPhotoSourceHoldingTank) get_offline_bin()).
                fetch_by_backing_file(file);
        
        return photo;
    }
    
    public LibraryPhoto? get_offline_by_md5(string md5) {
        return (LibraryPhoto?) get_offline_bin().fetch_by_md5(md5);
    }
    
    public int get_offline_count() {
        return get_offline_bin().get_count();
    }
    
    public LibraryPhoto? get_state_by_file(File file, out State state) {
        LibraryPhoto? photo = (LibraryPhoto?) fetch_by_master_file(file);
        if (photo != null) {
            state = State.ONLINE;
            
            return photo;
        }
        
        photo = fetch_by_editable_file(file);
        if (photo != null) {
            state = State.EDITABLE;
            
            return photo;
        }
        
        photo = fetch_by_raw_development_file(file);
        if (photo != null) {
            state = State.DEVELOPER;
            
            return photo;
        }
        
        photo = get_trashed_by_file(file) as LibraryPhoto;
        if (photo != null) {
            state = State.TRASH;
            
            return photo;
        }
        
        photo = get_offline_by_file(file) as LibraryPhoto;
        if (photo != null) {
            state = State.OFFLINE;
            
            return photo;
        }
        
        state = State.UNKNOWN;
        
        return null;
    }

    public override bool has_backlink(SourceBacklink backlink) {
        if (base.has_backlink(backlink))
            return true;
        
        if (get_trashcan().has_backlink(backlink))
            return true;
        
        if (get_offline_bin().has_backlink(backlink))
            return true;
        
        return false;
    }
    
    public override void remove_backlink(SourceBacklink backlink) {
        get_trashcan().remove_backlink(backlink);
        get_offline_bin().remove_backlink(backlink);
        
        base.remove_backlink(backlink);
    }
}

//
// LibraryPhoto
//

public class LibraryPhoto : Photo, Flaggable, Monitorable {
    // Top 16 bits are reserved for Photo
    // Warning: FLAG_HIDDEN and FLAG_FAVORITE have been deprecated for ratings and rating filters.
    private const uint64 FLAG_HIDDEN =      0x0000000000000001;
    private const uint64 FLAG_FAVORITE =    0x0000000000000002;
    private const uint64 FLAG_TRASH =       0x0000000000000004;
    private const uint64 FLAG_OFFLINE =     0x0000000000000008;
    private const uint64 FLAG_FLAGGED =     0x0000000000000010;
    
    public static LibraryPhotoSourceCollection global = null;
    
    private bool block_thumbnail_generation = false;
    private OneShotScheduler thumbnail_scheduler = null;
    private Gee.Collection<string>? import_keywords;

    private LibraryPhoto(PhotoRow row) {
        base (row);
        
        this.import_keywords = null;
        
        thumbnail_scheduler = new OneShotScheduler("LibraryPhoto", generate_thumbnails);
        
        // if marked in a state where they're held in an orphanage, rehydrate their backlinks
        if ((row.flags & (FLAG_TRASH | FLAG_OFFLINE)) != 0)
            rehydrate_backlinks(global, row.backlinks);
        
        if ((row.flags & (FLAG_HIDDEN | FLAG_FAVORITE)) != 0)
            upgrade_rating_flags(row.flags);
    }

    private LibraryPhoto.from_import_params(PhotoImportParams import_params) {
        base (import_params.row);
        
        this.import_keywords = import_params.keywords;       
        thumbnail_scheduler = new OneShotScheduler("LibraryPhoto", generate_thumbnails);
        
        // if marked in a state where they're held in an orphanage, rehydrate their backlinks
        if ((import_params.row.flags & (FLAG_TRASH | FLAG_OFFLINE)) != 0)
            rehydrate_backlinks(global, import_params.row.backlinks);
        
        if ((import_params.row.flags & (FLAG_HIDDEN | FLAG_FAVORITE)) != 0)
            upgrade_rating_flags(import_params.row.flags);
    }
    
    public static void init(ProgressMonitor? monitor = null) {
        init_photo();
        
        global = new LibraryPhotoSourceCollection();
        
        // prefetch all the photos from the database and add them to the global collection ...
        // do in batches to take advantage of add_many()
        Gee.ArrayList<PhotoRow?> all = PhotoTable.get_instance().get_all();
        Gee.ArrayList<LibraryPhoto> all_photos = new Gee.ArrayList<LibraryPhoto>();
        Gee.ArrayList<LibraryPhoto> trashed_photos = new Gee.ArrayList<LibraryPhoto>();
        Gee.ArrayList<LibraryPhoto> offline_photos = new Gee.ArrayList<LibraryPhoto>();
        int count = all.size;
        for (int ctr = 0; ctr < count; ctr++) {
            PhotoRow row = all.get(ctr);
            LibraryPhoto photo = new LibraryPhoto(row);
            uint64 flags = row.flags;
            
            if ((flags & FLAG_TRASH) != 0)
                trashed_photos.add(photo);
            else if ((flags & FLAG_OFFLINE) != 0)
                offline_photos.add(photo);
            else
                all_photos.add(photo);
            
            if (monitor != null)
                monitor(ctr, count);
        }
        
        global.add_many(all_photos);
        global.add_many_to_trash(trashed_photos);
        global.add_many_to_offline(offline_photos);
    }
    
    public static void terminate() {
        terminate_photo();
    }
    
    // This accepts a PhotoRow that was prepared with Photo.prepare_for_import and
    // has not already been inserted in the database.  See PhotoTable.add() for which fields are
    // used and which are ignored.  The PhotoRow itself will be modified with the remaining values
    // as they are stored in the database.
    public static ImportResult import_create(PhotoImportParams params, out LibraryPhoto photo) {
        // add to the database
        PhotoID photo_id = PhotoTable.get_instance().add(params.row);
        if (photo_id.is_invalid()) {
            photo = null;
            
            return ImportResult.DATABASE_ERROR;
        }
        
        // create local object but don't add to global until thumbnails generated
        photo = new LibraryPhoto.from_import_params(params);
        
        return ImportResult.SUCCESS;
    }
    
    public static void import_failed(LibraryPhoto photo) {
        try {
            PhotoTable.get_instance().remove(photo.get_photo_id());
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
    }
    
    protected override void notify_master_reimported(PhotoMetadata? metadata) {
        base.notify_master_reimported(metadata);
        
        global.notify_master_reimported(this, metadata);
    }
    
    protected override void notify_editable_reimported(PhotoMetadata? metadata) {
        base.notify_editable_reimported(metadata);
        
        global.notify_editable_reimported(this, metadata);
    }
    
    protected override void notify_source_reimported(PhotoMetadata? metadata) {
        base.notify_source_reimported(metadata);
        
        global.notify_source_reimported(this, metadata);
    }
    
    protected override void notify_baseline_reimported(PhotoMetadata? metadata) {
        base.notify_baseline_reimported(metadata);
        
        global.notify_baseline_reimported(this, metadata);
    }
    
    private void generate_thumbnails() {
        try {
            ThumbnailCache.import_from_source(this, true);
        } catch (Error err) {
            warning("Unable to generate thumbnails for %s: %s", to_string(), err.message);
        }
        
        // fire signal that thumbnails have changed
        notify_thumbnail_altered();
    }
    
    // These keywords are only used during import and should not be relied upon elsewhere.
    public Gee.Collection<string>? get_import_keywords() {
        return import_keywords;
    }
    
    public void clear_import_keywords() {
        import_keywords = null;
    }
    
    public override void notify_altered(Alteration alteration) {
        // generate new thumbnails in the background
        if (!block_thumbnail_generation && alteration.has_subject("image"))
            thumbnail_scheduler.at_priority_idle(Priority.LOW);
        
        base.notify_altered(alteration);
    }
    
    public override Gdk.Pixbuf get_preview_pixbuf(Scaling scaling) throws Error {
        Gdk.Pixbuf pixbuf = get_thumbnail(ThumbnailCache.Size.BIG);
        
        return scaling.perform_on_pixbuf(pixbuf, Gdk.InterpType.BILINEAR, true);
    }
    
    public override void rotate(Rotation rotation) {
        // block thumbnail generation for this operation; taken care of below
        block_thumbnail_generation = true;
        base.rotate(rotation);
        block_thumbnail_generation = false;

        // because rotations are (a) common and available everywhere in the app, (b) the user expects
        // a level of responsiveness not necessarily required by other modifications, (c) can be
        // performed on multiple images simultaneously, and (d) can't cache a lot of full-sized
        // pixbufs for rotate-and-scale ops, perform the rotation directly on the already-modified 
        // thumbnails.
        try {
            ThumbnailCache.rotate(this, rotation);
        } catch (Error err) {
            // TODO: Mark thumbnails as dirty in database
            warning("Unable to update thumbnails for %s: %s", to_string(), err.message);
        }
        
        notify_thumbnail_altered();
    }
    
    // Returns unscaled thumbnail with all modifications applied applicable to the scale
    public override Gdk.Pixbuf? get_thumbnail(int scale) throws Error {
        return ThumbnailCache.fetch(this, scale);
    }
    
    // Duplicates a backing photo row, returning the ID.
    // An invalid ID will be returned if the backing photo row is not set or is invalid.
    private BackingPhotoID duplicate_backing_photo(BackingPhotoRow? backing) throws Error {
        BackingPhotoID backing_id = BackingPhotoID();
        if (backing == null || backing.filepath == null)
            return backing_id; // empty, invalid ID
        
        File file = File.new_for_path(backing.filepath);
        if (file.query_exists()) {
            File dupe_file = LibraryFiles.duplicate(file, on_duplicate_progress, true);
            
            DetectedPhotoInformation detected;
            BackingPhotoRow? state = query_backing_photo_row(dupe_file, PhotoFileSniffer.Options.NO_MD5,
                out detected);
            if (state != null) {
                BackingPhotoTable.get_instance().add(state);
                backing_id = state.id;
            }
        }
        
        return backing_id;
    }
    
    public LibraryPhoto duplicate() throws Error {
        // clone the master file
        File dupe_file = LibraryFiles.duplicate(get_master_file(), on_duplicate_progress, true);
        
        // Duplicate editable and raw developments (if they exist)
        BackingPhotoID dupe_editable_id = duplicate_backing_photo(get_editable_photo_row());
        BackingPhotoID dupe_raw_shotwell_id = duplicate_backing_photo(
            get_raw_development_photo_row(RawDeveloper.SHOTWELL));
        BackingPhotoID dupe_raw_camera_id = duplicate_backing_photo(
            get_raw_development_photo_row(RawDeveloper.CAMERA));
        BackingPhotoID dupe_raw_embedded_id = duplicate_backing_photo(
            get_raw_development_photo_row(RawDeveloper.EMBEDDED));
        
        // clone the row in the database for these new backing files
        PhotoID dupe_id = PhotoTable.get_instance().duplicate(get_photo_id(), dupe_file.get_path(),
            dupe_editable_id, dupe_raw_shotwell_id, dupe_raw_camera_id, dupe_raw_embedded_id);
        PhotoRow dupe_row = PhotoTable.get_instance().get_row(dupe_id);
        
        // build the DataSource for the duplicate
        LibraryPhoto dupe = new LibraryPhoto(dupe_row);

        // clone thumbnails
        ThumbnailCache.duplicate(this, dupe);
        
        // add it to the SourceCollection; this notifies everyone interested of its presence
        global.add(dupe);
        
        // if it is not in "No Event" attach to event
        if (dupe.get_event() != null)
            dupe.get_event().attach(dupe);

        // attach tags
        Gee.Collection<Tag>? tags = Tag.global.fetch_for_source(this);
        if (tags != null) {
            foreach (Tag tag in tags) {
                tag.attach(dupe);
            }
        }
        
#if ENABLE_FACES
        // Attach faces.
        Gee.Collection<Face>? faces = Face.global.fetch_for_source(this);
        if (faces != null) {
            foreach (Face face in faces) {
                FaceLocation? location = FaceLocation.get_face_location(face.get_face_id(), 
                    this.get_photo_id());
                if (location != null) {
                    face.attach(dupe);
                    FaceLocation.create(face.get_face_id(), dupe.get_photo_id(), 
                        location.get_serialized_geometry());
                }
             }
        }
#endif
        
        return dupe;
    }
    
    private void on_duplicate_progress(int64 current, int64 total) {
        spin_event_loop();
    }
    
    private void upgrade_rating_flags(uint64 flags) {
        if ((flags & FLAG_HIDDEN) != 0) {
            set_rating(Rating.REJECTED);
            remove_flags(FLAG_HIDDEN);
        }
        
        if ((flags & FLAG_FAVORITE) != 0) {
            set_rating(Rating.FIVE);
            remove_flags(FLAG_FAVORITE);
        }
    }
    
    // Blotto even!
    public override bool is_trashed() {
        return is_flag_set(FLAG_TRASH);
    }
    
    public override void trash() {
        add_flags(FLAG_TRASH);
    }
    
    public override void untrash() {
        remove_flags(FLAG_TRASH);
    }
    
    public override bool is_offline() {
        return is_flag_set(FLAG_OFFLINE);
    }
    
    public override void mark_offline() {
        add_flags(FLAG_OFFLINE);
    }
    
    public override void mark_online() {
        remove_flags(FLAG_OFFLINE);
    }
    
    public  bool is_flagged() {
        return is_flag_set(FLAG_FLAGGED);
    }
    
    public void mark_flagged() {
        add_flags(FLAG_FLAGGED, new Alteration("metadata", "flagged"));
    }
    
    public void mark_unflagged() {
        remove_flags(FLAG_FLAGGED, new Alteration("metadata", "flagged"));
    }
    
    public override bool internal_delete_backing() throws Error {
        // allow the base classes to work first because delete_original_file() will attempt to
        // remove empty directories as well
        if (!base.internal_delete_backing())
            return false;
        
        return delete_original_file();
    }
    
    public override void destroy() {
        PhotoID photo_id = get_photo_id();

        // remove all cached thumbnails
        ThumbnailCache.remove(this);
        
        // remove from photo table -- should be wiped from storage now (other classes may have added
        // photo_id to other parts of the database ... it's their responsibility to remove them
        // when removed() is called)
        try {
            PhotoTable.get_instance().remove(photo_id);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        base.destroy();
    }
    
    public static bool has_nontrash_duplicate(File? file, string? thumbnail_md5, string? full_md5,
        PhotoFileFormat file_format) {
        return get_nontrash_duplicate(file, thumbnail_md5, full_md5, file_format).is_valid();
    }
    
    public static PhotoID get_nontrash_duplicate(File? file, string? thumbnail_md5,
        string? full_md5, PhotoFileFormat file_format) {
        PhotoID[]? ids = get_duplicate_ids(file, thumbnail_md5, full_md5, file_format);
        
        if (ids == null || ids.length == 0)
            return PhotoID(); // return an invalid PhotoID
        
        foreach (PhotoID id in ids) {
            LibraryPhoto photo = LibraryPhoto.global.fetch(id);
            if (photo != null && !photo.is_trashed())
                return id;
        }
        
        return PhotoID();
    }

    protected override bool has_user_generated_metadata() {
        Gee.List<Tag>? tags = Tag.global.fetch_for_source(this);
        
        PhotoMetadata? metadata = get_metadata();
        if (metadata == null)
            return tags != null || tags.size > 0 || get_rating() != Rating.UNRATED;
        
        if (get_rating() != metadata.get_rating())
            return true;
        
        Gee.Set<string>? keywords = metadata.get_keywords();
        int tags_count = (tags != null) ? tags.size : 0;
        int keywords_count = (keywords != null) ? keywords.size : 0;
        
        if (tags_count != keywords_count)
            return true;
        
        if (tags != null && keywords != null) {
            foreach (Tag tag in tags) {
                if (!keywords.contains(tag.get_name().normalize()))
                    return true;
            }
        }
        
        return false;
    }

    protected override void set_user_metadata_for_export(PhotoMetadata metadata) {
        Gee.List<Tag>? photo_tags = Tag.global.fetch_for_source(this);
        if(photo_tags != null) {
            Gee.Collection<string> string_tags = new Gee.ArrayList<string>();
            foreach (Tag tag in photo_tags) {
                string_tags.add(tag.get_name());
            }
            metadata.set_keywords(string_tags);
        } else
            metadata.set_keywords(null);
        
        metadata.set_rating(get_rating());
    }
    
    protected override void apply_user_metadata_for_reimport(PhotoMetadata metadata) {
        HierarchicalTagIndex? new_htag_index = null;
        
        if (metadata.has_hierarchical_keywords()) {
            new_htag_index = HierarchicalTagUtilities.process_hierarchical_import_keywords(
                metadata.get_hierarchical_keywords());
        }
        
        Gee.Collection<string>? keywords = metadata.get_keywords();
        if (keywords != null) {
            foreach (string keyword in keywords) {           
                if (new_htag_index != null && new_htag_index.is_tag_in_index(keyword))
                    continue;

                string safe_keyword = HierarchicalTagUtilities.make_flat_tag_safe(keyword);
                string promoted_keyword = HierarchicalTagUtilities.flat_to_hierarchical(
                    safe_keyword);
                
                if (Tag.global.exists(safe_keyword)) {
                    Tag.for_path(safe_keyword).attach(this);
                    continue;
                }
                
                if (Tag.global.exists(promoted_keyword)) {
                    Tag.for_path(promoted_keyword).attach(this);
                    continue;
                }
                
                Tag.for_path(keyword).attach(this);
            }
        }
        
        if (new_htag_index != null) {
            foreach (string path in new_htag_index.get_all_paths())
                Tag.for_path(path).attach(this);
        }
    }
}

// Used for trash and offline bin of LibraryPhotoSourceCollection
public class LibraryPhotoSourceHoldingTank : MediaSourceHoldingTank {
    private Gee.HashMap<File, LibraryPhoto> editable_file_map = new Gee.HashMap<File, LibraryPhoto>(
        file_hash, file_equal);
    private Gee.HashMap<File, LibraryPhoto> development_file_map = new Gee.HashMap<File, LibraryPhoto>(
        file_hash, file_equal);
    private Gee.MultiMap<LibraryPhoto, File> reverse_editable_file_map 
        = new Gee.HashMultiMap<LibraryPhoto, File>(null, null, file_hash, file_equal);
    private Gee.MultiMap<LibraryPhoto, File> reverse_development_file_map 
        = new Gee.HashMultiMap<LibraryPhoto, File>(null, null, file_hash, file_equal);
    
    public LibraryPhotoSourceHoldingTank(LibraryPhotoSourceCollection sources,
        SourceHoldingTank.CheckToKeep check_to_keep, GetSourceDatabaseKey get_key) {
        base (sources, check_to_keep, get_key);
    }
    
    public LibraryPhoto? fetch_by_backing_file(File file) {
        LibraryPhoto? ret = null;
        ret = editable_file_map.get(file);
        if (ret != null)
            return ret;
        
        return development_file_map.get(file);
    }
    
    protected override void notify_contents_altered(Gee.Collection<DataSource>? added,
        Gee.Collection<DataSource>? removed) {
        if (added != null) {
            foreach (DataSource source in added) {
                LibraryPhoto photo = (LibraryPhoto) source;
                
                // Editable files.
                if (photo.get_editable_file() != null) {
                    editable_file_map.set(photo.get_editable_file(), photo);
                    reverse_editable_file_map.set(photo, photo.get_editable_file());
                }
                
                // RAW developments.
                Gee.Collection<File>? raw_files = photo.get_raw_developer_files();
                if (raw_files != null) {
                    foreach (File f in raw_files) {
                        development_file_map.set(f, photo);
                        reverse_development_file_map.set(photo, f);
                    }
                }
                
                photo.editable_replaced.connect(on_editable_replaced);
                photo.raw_development_modified.connect(on_raw_development_modified);
            }
        }
        
        if (removed != null) {
            foreach (DataSource source in removed) {
                LibraryPhoto photo = (LibraryPhoto) source;
                foreach (File f in reverse_editable_file_map.get(photo))
                    editable_file_map.unset(f);
                
                foreach (File f in reverse_development_file_map.get(photo))
                    development_file_map.unset(f);
                
                reverse_editable_file_map.remove_all(photo);
                reverse_development_file_map.remove_all(photo);
                
                photo.editable_replaced.disconnect(on_editable_replaced);
                photo.raw_development_modified.disconnect(on_raw_development_modified);
            }
        }
        
        base.notify_contents_altered(added, removed);
    }
    
    private void on_editable_replaced(Photo _photo, File? old_file, File? new_file) {
        LibraryPhoto? photo = _photo as LibraryPhoto;
        assert(photo != null);
        
        if (old_file != null) {
            editable_file_map.unset(old_file);
            reverse_editable_file_map.remove(photo, old_file);
        }
        
        if (new_file != null)
            editable_file_map.set(new_file, photo);
            reverse_editable_file_map.set(photo, new_file);
    }
    
    private void on_raw_development_modified(Photo _photo) {
        LibraryPhoto? photo = _photo as LibraryPhoto;
        assert(photo != null);
        
        // Unset existing files.
        if (reverse_development_file_map.contains(photo)) {
            foreach (File f in reverse_development_file_map.get(photo))
                development_file_map.unset(f);
            reverse_development_file_map.remove_all(photo);
        }
        
        // Add new ones.
        Gee.Collection<File> raw_list = photo.get_raw_developer_files();
        if (raw_list != null) {
            foreach (File f in raw_list) {
                development_file_map.set(f, photo);
                reverse_development_file_map.set(photo, f);
            }
        }
    }
}

