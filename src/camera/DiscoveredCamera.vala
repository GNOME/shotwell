/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

internal class CameraImportJob : BatchImportJob {
    private GPhoto.Context context;
    private ImportSource import_file;
    private GPhoto.Camera camera;
    private string fulldir;
    private string filename;
    private uint64 filesize;
    private PhotoMetadata metadata;
    private DateTime exposure_time;
    private CameraImportJob? associated = null;
    private BackingPhotoRow? associated_file = null;
    private DuplicatedFile? duplicated_file;
    
    public CameraImportJob(GPhoto.Context context, ImportSource import_file,
        DuplicatedFile? duplicated_file = null) {
        this.context = context;
        this.import_file = import_file;
        this.duplicated_file = duplicated_file;
        
        // stash everything called in prepare(), as it may/will be called from a separate thread
        camera = import_file.get_camera();
        fulldir = import_file.get_fulldir();
        // this should've been caught long ago when the files were first enumerated
        assert(fulldir != null);
        filename = import_file.get_filename();
        filesize = import_file.get_filesize();
        var photo_import_source = import_file as PhotoImportSource;
        metadata = (photo_import_source != null) ?
            photo_import_source.get_metadata() : null;
        exposure_time = import_file.get_exposure_time();
    }
    
    public DateTime get_exposure_time() {
        return exposure_time;
    }
    
    public override DuplicatedFile? get_duplicated_file() {
        return duplicated_file;
    }

    public override DateTime? get_exposure_time_override() {
        return (import_file is VideoImportSource) ? get_exposure_time() : null;
    }
    
    public override string get_dest_identifier() {
        return filename;
    }
    
    public override string get_source_identifier() {
        return import_file.get_filename();
    }
    
    public override string get_basename() {
        return filename;
    }

    public override string get_path() {
        return fulldir;
    }
    
    public override void set_associated(BatchImportJob associated) {
        this.associated = associated as CameraImportJob;
    }
    
    public ImportSource get_source() {
        return import_file;
    }
    
    public override bool is_directory() {
        return false;
    }
    
    public override bool determine_file_size(out uint64 filesize, out File file) {
        file = null;
        filesize = this.filesize;
        
        return true;
    }
    
    public override bool prepare(out File file_to_import, out bool copy_to_library,
        Cancellable? cancellable = null) throws Error {
        file_to_import = null;
        copy_to_library = false;
        
        File dest_file = null;
        try {
            bool collision;
            dest_file = LibraryFiles.generate_unique_file(filename, metadata, exposure_time,
                out collision);
        } catch (Error err) {
            warning("Unable to generate local file for %s: %s", import_file.get_filename(),
                err.message);
        }
        
        if (dest_file == null) {
            message("Unable to generate local file for %s", import_file.get_filename());
            
            return false;
        }
        
        // always blacklist the copied images from the LibraryMonitor, otherwise it'll think
        // they should be auto-imported
        LibraryMonitor.blacklist_file(dest_file, "CameraImportJob.prepare");
        try {
            save_image(fulldir, filename, dest_file, cancellable);
        } catch (Error err) {
            // Remove the (possibly partial) download before propagating a cancellation or failure.
            try_delete_file(dest_file);
            throw err;
        } finally {
            LibraryMonitor.unblacklist_file(dest_file);
        }
        
        // Copy over associated file, if it exists.
        if (associated != null) {
            try {
                associated_file = 
                    RawDeveloper.CAMERA.create_backing_row_for_development(dest_file.get_path(),
                        associated.get_basename());
            } catch (Error err) {
                warning("Unable to generate backing associated file for %s: %s", associated.filename,
                    err.message);
            }
            
            if (associated_file == null) {
                message("Unable to generate backing associated file for %s", associated.filename);
                return false;
            }
            
            File assoc_dest = File.new_for_path(associated_file.filepath);
            LibraryMonitor.blacklist_file(assoc_dest, "CameraImportJob.prepare");
            try {
                save_image(associated.fulldir, associated.filename, assoc_dest, cancellable);
            } catch (Error err) {
                try_delete_file(assoc_dest);
                throw err;
            } finally {
                LibraryMonitor.unblacklist_file(assoc_dest);
            }
        }
        
        file_to_import = dest_file;
        copy_to_library = false;
        
        return true;
    }

    private static void try_delete_file(File file) {
        try {
            file.delete(null);
        } catch (Error err) {
            warning("Unable to delete partial camera download %s: %s", file.get_path(), err.message);
        }
    }

    // Downloads folder/filename off the camera into dest_file.  When cancellable is cancelled,
    // gphoto2 aborts the in-flight transfer via the context's cancel func and this throws
    // IOError.CANCELLED.
    private void save_image(string folder, string filename, File dest_file,
        Cancellable? cancellable = null) throws Error {
        var fd = Posix.creat(dest_file.get_path(), 0640);
        if (fd < 0) {
            throw new IOError.FAILED("[%d] Error creating file %s: %m", GLib.errno, dest_file.get_path());
        }

        // gphoto2 invokes the context's cancel func periodically during a transfer; return
        // CANCEL to abort an in-flight download when the caller has cancelled.
        if (cancellable != null)
            context.set_cancel_func((ctx) => cancellable.is_cancelled() ? GPhoto.ContextFeedback.CANCEL : GPhoto.ContextFeedback.OK);
        else
            context.set_cancel_func(null);

        GPhoto.CameraFile camera_file;
        GPhoto.Result res = GPhoto.CameraFile.create_from_fd(out camera_file, fd);
        if (res != GPhoto.Result.OK) {
            context.set_cancel_func(null);
            throw new GPhotoError.LIBRARY("[%d] Error allocating camera file: %s", (int) res, res.as_string());
        }

        res = camera.get_file(folder, filename, GPhoto.CameraFileType.NORMAL, camera_file, context);
        // Clear the cancel func so a stale Cancellable isn't referenced by later, unrelated transfers.
        context.set_cancel_func(null);

        if (cancellable != null && cancellable.is_cancelled())
            throw new IOError.CANCELLED("Camera download cancelled by user");

        if (res != GPhoto.Result.OK) {
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file object for %s/%s: %s",
                (int) res, folder, filename, res.as_string());
        }
    }

    public override File? get_associated_file() {
        if (associated_file == null) {
            return null;
        }

        return File.new_for_path(associated_file.filepath);
    }
}
    
public class DiscoveredCamera : Object {
    public GPhoto.Camera gcamera;
    private GPhoto.Context context;

    public string uri;
    public string display_name;
    public string? icon;

    private string port;
    private string camera_name;
    private string[] mount_uris;
    private Workers? workers = null;
    private Cancellable? cancellable = null;

    public DiscoveredCamera(string name, string port, GPhoto.PortInfo port_info, GPhoto.CameraAbilities camera_abilities) throws GPhotoError {
        this.port = port;
        this.camera_name = name;
        this.uri = "gphoto2://[%s]".printf(port);

        this.mount_uris = new string[0];
        this.mount_uris += this.uri;
        this.mount_uris += "mtp://[%s]".printf(port);

        var res = GPhoto.Camera.create(out this.gcamera);

        if (res != GPhoto.Result.OK) {
            throw new GPhotoError.LIBRARY("[%d] Unable to create camera object for %s: %s",
                (int) res, name, res.as_string());
        }

        res = gcamera.set_abilities(camera_abilities);
        if (res != GPhoto.Result.OK) {
            throw new GPhotoError.LIBRARY("[%d] Unable to set camera abilities for %s: %s",
                (int) res, name, res.as_string());
        }

        res = gcamera.set_port_info(port_info);
        if (res != GPhoto.Result.OK) {
            throw new GPhotoError.LIBRARY("[%d] Unable to set port info for %s: %s",
                (int) res, name, res.as_string());
        }

        var path = get_port_path(port);
        if (path != null) {
            var monitor = VolumeMonitor.get();
            foreach (var volume in monitor.get_volumes()) {
                if (volume.get_identifier(VolumeIdentifier.UNIX_DEVICE) == path) {
                    this.display_name = volume.get_name();
                    this.icon = volume.get_symbolic_icon().to_string();
                }
            }

#if HAVE_UDEV
            var client = new GUdev.Client(null);
            var device = client.query_by_device_file(path);


            // Create alternative uris (used for unmount)
            var serial = device.get_property("ID_SERIAL");
            this.mount_uris += "gphoto2://%s".printf(serial);
            this.mount_uris += "mtp://%s".printf(serial);

            // Look-up alternative display names
            if (display_name == null) {
                display_name = device.get_sysfs_attr("product");
            }

            if (display_name == null) {
                display_name = device.get_property("ID_MODEL");
            }
#endif
        }

        if (port.has_prefix("disk:")) {
            try {
                var mount = File.new_for_path (port.substring(5)).find_enclosing_mount();
                var volume = mount.get_volume();
                if (volume != null) {
                    // Translators: First %s is the name of camera as gotten from GPhoto, second is the GVolume name, e.g. Mass storage camera (510MB volume)
                    display_name = _("%s (%s)").printf (name, volume.get_name ());
                    icon = volume.get_symbolic_icon().to_string();
                } else {
                    // Translators: First %s is the name of camera as gotten from GPhoto, second is the GMount name, e.g. Mass storage camera (510MB volume)
                    display_name = _("%s (%s)").printf (name, mount.get_name ());
                    icon = mount.get_symbolic_icon().to_string();
                }

            } catch (Error e) { }
        }

        if (display_name == null) {
            this.display_name = camera_name;
        }
    }

    public void attach(Workers workers) {
        this.workers = workers;
    }

    public void set_cancellable(Cancellable? cancellable) {
        this.cancellable = cancellable;
    }

    public bool is_cancelled() {
        return (this.cancellable != null) && this.cancellable.is_cancelled();
    }

    public Mount? get_mount() {
        foreach (var uri in this.mount_uris) {
            var f = File.new_for_uri(uri);
            try {
                var mount = f.find_enclosing_mount(null);
                if (mount != null)
                    return mount;
            } catch (Error error) {}
        }

        return null;
    }

    private string? get_port_path(string port) {
        // Accepted format is usb:001,005
        return port.has_prefix("usb:") ? 
            "/dev/bus/usb/%s".printf(port.substring(4).replace(",", "/")) : null;
    }
    

    private abstract class CameraJob : AsyncableBackgroundJob {
        public GPhoto.Camera camera;
        public GPhoto.Context context;

        // Strong reference to the currently-installed cancel delegate, gphoto2 uses an
        // unowned blank void* pointer, so we need to keep it alive elsewhere
        private GPhoto.ContextCancelFunc? cancel_func = null;

        protected CameraJob(Object? owner, GPhoto.Context context, GPhoto.Camera camera,
            Cancellable? cancellable) {
            base(owner, cancellable);
            this.camera = camera;
            this.context = context;
        }

        // Subclasses that produce a result override this; the default is a no-op.
        public virtual GPhoto.Result get_result() {
            return GPhoto.Result.OK;
        }

        protected void install_cancel_handler() {
            Cancellable? cancellable = get_cancellable();
            if (cancellable != null) {
                this.cancel_func = (ctx) => cancellable.is_cancelled() ?
                    GPhoto.ContextFeedback.CANCEL : GPhoto.ContextFeedback.OK;
                context.set_cancel_func(this.cancel_func);
            } else {
                context.set_cancel_func(null);
            }
        }

        protected void clear_cancel_handler() {
            context.set_cancel_func(null);
            this.cancel_func = null;
        }

        public async GPhoto.Result run(Workers camera_workers) {
            this.function_callback = run.callback;
            install_cancel_handler();
            camera_workers.enqueue(this);
            yield;
            clear_cancel_handler();

            return get_result();
        }
    }

    private abstract class ResultCameraJob : CameraJob {
        public GPhoto.Result result;

        protected ResultCameraJob(Object? owner, GPhoto.Context context, GPhoto.Camera camera,
            Cancellable? cancellable) {
            base(owner, context, camera, cancellable);
        }

        public override GPhoto.Result get_result() {
            return this.result;
        }
    }

    // Base for camera jobs that may raise a GLib.Error; run() rethrows it on the caller's behalf.
    private abstract class ThrowingCameraJob : CameraJob {
        public Error? error = null;

        protected ThrowingCameraJob(Object? owner, GPhoto.Context context, GPhoto.Camera camera,
            Cancellable? cancellable) {
            base(owner, context, camera, cancellable);
        }

        public new async void run(Workers camera_workers) throws Error {
            this.function_callback = run.callback;
            install_cancel_handler();
            camera_workers.enqueue(this);
            yield;
            clear_cancel_handler();

            if (get_cancellable() != null && get_cancellable().is_cancelled() && this.error == null)
                throw new IOError.CANCELLED("Camera operation cancelled by user");

            if (this.error != null)
                throw this.error;
        }
    }

    private class InitCameraJob : ResultCameraJob {
        public InitCameraJob(Object owner, GPhoto.Camera camera, Cancellable? cancellable = null) {
            var context = new GPhoto.Context();
            base(owner, context, camera, cancellable);
        }

        public override void execute() {
            this.result = camera.init(this.context);
        }
    }

    public async GPhoto.Result init() {
        var init = new InitCameraJob(this, this.gcamera, this.cancellable);
        var result = yield init.run(this.workers);

        this.context = init.context;

        return result;
    }

    public BatchImportJob create_import_job(ImportSource import_file, DuplicatedFile? duplicated_file = null) {
        return new CameraImportJob(this.context, import_file, duplicated_file);
    }

    private class GetStorageInfo : ResultCameraJob {
        public GPhoto.CameraStorageInformation[] sifs = null;

        public GetStorageInfo(Object? owner, GPhoto.Context context, GPhoto.Camera camera, Cancellable? cancellable) {
            base(owner, context, camera, cancellable);
        }

        public override void execute() {
            this.result = camera.get_storageinfo(out this.sifs, this.context);
        }
    }

    // Need to do this because some phones (iPhone, in particular) changes the name of their filesystem
    // between each mount
    public async string? get_fs_basedir(int fsid) {
        var gsi = new GetStorageInfo(null, context, gcamera, this.cancellable);
        yield gsi.run(this.workers);
        if (gsi.result != GPhoto.Result.OK) {
            return null;
        }

        if (fsid >= gsi.sifs.length) {
            return null;
        }

        if (GPhoto.CameraStorageInfoFields.BASE in gsi.sifs[fsid].fields) {
            return (string) gsi.sifs[fsid].basedir;
        }

        return "/";
    }
    
    private static string chomp_ch(string str, char ch) {
        long offset = str.length;
        while (--offset >= 0) {
            if (str[offset] != ch)
                return str.slice(0, offset);
        }
        
        return "";
    }

    public static string append_path(string basepath, string addition) {
        if (!basepath.has_suffix("/") && !addition.has_prefix("/"))
            return basepath + "/" + addition;
        else if (basepath.has_suffix("/") && addition.has_prefix("/"))
            return chomp_ch(basepath, '/') + addition;
        else
            return basepath + addition;
    }

    public async string? get_fulldir(int fsid, string folder) {
        var basedir = yield get_fs_basedir(fsid);
        if (basedir == null) {
            debug("Unable to find base directory for %s fsid %d", display_name, fsid);
            
            return folder;
        }
        
        return append_path(basedir, folder);
    }

    private class ListFiles : ResultCameraJob {
        public GPhoto.CameraList files;
        public string fulldir;

        public ListFiles(Object owner, GPhoto.Context context, GPhoto.Camera camera, string fulldir, Cancellable? cancellable) {
            base(owner, context, camera, cancellable);
            this.fulldir = fulldir;
        }

        public override void execute() {
            this.result = GPhoto.CameraList.create(out this.files);
            if (this.result != GPhoto.Result.OK) {
                warning("Unable to create file list: %s", result.to_full_string());

                return;
            }

            this.result = camera.list_files(this.fulldir, this.files, this.context);
        }
    }

    private class ListFolders : ResultCameraJob {
        public GPhoto.CameraList folders;
        public string fulldir;

        public ListFolders(Object owner, GPhoto.Context context, GPhoto.Camera camera, string fulldir, Cancellable? cancellable) {
            base(owner, context, camera, cancellable);
            this.fulldir = fulldir;
        }

        public override void execute() {
            this.result = GPhoto.CameraList.create(out this.folders);
            if (this.result != GPhoto.Result.OK) {
                warning("Unable to create file list: %s", result.to_full_string());

                return;
            }

            this.result = camera.list_folders(this.fulldir, this.folders, this.context);
        }
    }

    private class GetFileInfo : ResultCameraJob {
        public GPhoto.CameraFileInfo info;
        public string fulldir;
        public string file_name;

        public GetFileInfo(Object owner, GPhoto.Context context, GPhoto.Camera camera, string fulldir, string file_name, Cancellable? cancellable) {
            base(owner, context, camera, cancellable);
            this.fulldir = fulldir;
            this.file_name = file_name;
        }

        public override void execute() {
            this.result = this.camera.get_file_info (this.fulldir, this.file_name, out this.info, this.context);
        }
    }

    public async GPhoto.Result enumerate_files(int fsid, string dir, Gee.ArrayList<ImportSource> import_list) {
        string? fulldir = yield get_fulldir(fsid, dir);
        if (fulldir == null) {
            warning("Skipping enumerating %s: invalid folder name", dir);
            
            return GPhoto.Result.OK;
        }
                
        var list_files = new ListFiles(this, context, gcamera, fulldir, this.cancellable);
        var result = yield list_files.run(workers);
        if (list_files.result != GPhoto.Result.OK) {
            warning("Unable to list files in %s: %s", fulldir, result.to_full_string());
            
            // Although an error, don't abort the import because of this
            return GPhoto.Result.OK;
        }
        list_files.files.sort();

        for (int ctr = 0; ctr < list_files.files.count(); ctr++) {
            if (is_cancelled())
                return GPhoto.Result.OK;
            string filename;
            result = list_files.files.get_name(ctr, out filename);
            if (result != GPhoto.Result.OK) {
                warning("Unable to get the name of file %d in %s: %s", ctr, fulldir,
                    result.to_full_string());
                
                return result;
            }
            
            var info = new GetFileInfo(this, context, gcamera, fulldir, filename, this.cancellable);
            result = yield info.run(workers);
            if (result != GPhoto.Result.OK) {
                warning("Skipping import of %s/%s: name too long", fulldir, filename);
                continue;
            }
            
            if ((info.info.file.fields & GPhoto.CameraFileInfoFields.TYPE) == 0) {
                message("Skipping %s/%s: No file (file=%02Xh)", fulldir, filename,
                    info.info.file.fields);
                    
                continue;
            }
            
            if (VideoReader.is_supported_video_filename(filename)) {
                VideoImportSource video_source = new VideoImportSource(display_name, gcamera,
                    fsid, fulldir, dir, filename, info.info.file.size, new DateTime.from_unix_utc(info.info.file.mtime));
                import_list.add(video_source);
            } else {
                // determine file format from type, and then from file extension
                string file_type = (string)info.info.file.type;
                PhotoFileFormat file_format = PhotoFileFormat.from_gphoto_type(file_type);               
                if (file_format == PhotoFileFormat.UNKNOWN) {
                    file_format = PhotoFileFormat.get_by_basename_extension(filename);
                    if (file_format == PhotoFileFormat.UNKNOWN) {
                        message("Skipping %s/%s: Not a supported file extension (%s)", fulldir,
                            filename, file_type);
                        
                        continue;
                    }
                }
                import_list.add(new PhotoImportSource(display_name, gcamera, fsid, fulldir, dir, filename,
                    info.info.file.size, new DateTime.from_unix_utc(info.info.file.mtime), file_format));
            }
        }
        
        var list_folders = new ListFolders(this, context, gcamera, fulldir, this.cancellable);
        result = yield list_folders.run(workers);
        if (list_folders.result != GPhoto.Result.OK) {
            warning("Unable to list folders in %s: %s", fulldir, result.to_full_string());
            
            // Although an error, don't abort the import because of this
            return GPhoto.Result.OK;
        }
        
        for (int ctr = 0; ctr < list_folders.folders.count(); ctr++) {
            string subdir;
            result = list_folders.folders.get_name(ctr, out subdir);
            if (result != GPhoto.Result.OK) {
                warning("Unable to get name of folder %d: %s", ctr, result.to_full_string());
                
                return result;
            }
            
            if (subdir.has_prefix(".")) {
                debug("Skipping hidden sub-folder %s in %s", subdir, dir);
            } else {
                result = yield enumerate_files(fsid, append_path(dir, subdir), import_list);
                if (result != GPhoto.Result.OK) {
                    return result;
                }
            }
        }
        
        return GPhoto.Result.OK;
    }

    /**
     * @brief Returns whether the current device has a given directory or not.
     *
     * @param fsid The file system id of the camera or other device to search.
     * @param dir The path to start searching from.
     * @param search_target The name of the directory to look for.
     */
    public async bool check_directory_exists(int fsid, string dir, string search_target) {
        string? fulldir = yield get_fulldir(fsid, dir);

        var lf = new ListFolders(this, context, gcamera, fulldir, this.cancellable);
        var result = yield lf.run(workers);
        if (result != GPhoto.Result.OK) {
            // fetching the list failed - can't determine whether specified dir is present
            return false;
        }

        int list_len = lf.folders.count();

        for (int list_index = 0; list_index < list_len; list_index++) {
            string tmp;

            lf.folders.get_name(list_index, out tmp);
            if (tmp == search_target) {
                return true;
            }
        }
        return false;
    }

    public async GPhoto.Result get_storage_information(out GPhoto.CameraStorageInformation[] sifs) {
        var storage_information = new GetStorageInfo(this, context, gcamera, null);
        var result = yield storage_information.run(workers);
        sifs = storage_information.sifs;

        return result;
    }

    private class LoadMetadata : ThrowingCameraJob {
        public PhotoMetadata metadata;
        public string folder;
        public string file_name;

        public LoadMetadata(Object owner, GPhoto.Context context, GPhoto.Camera camera, string folder, string file_name, Cancellable? cancellable) {
            base(owner, context, camera, cancellable);
            this.folder = folder;
            this.file_name = file_name;
        }

        public override void execute() {
            try {
                Bytes? camera_raw = null;
                try {
                    camera_raw = GPhoto.load_file_into_buffer(this.context, this.camera, this.folder,
                        this.file_name, GPhoto.CameraFileType.EXIF);
                } catch (Error e) {
                    this.metadata = GPhoto.get_fallback_metadata(this.camera, this.context, this.folder,
                        this.file_name);
                    return;
                }

                if (camera_raw == null || camera_raw.length == 0) {
                    this.metadata = null;
                    return;
                }

                PhotoMetadata metadata = new PhotoMetadata();
                metadata.read_from_app1_segment(camera_raw);
                this.metadata = metadata;
            } catch (Error e) {
                this.error = e;
            }
        }
    }
    
    public async PhotoMetadata load_metadata(string fulldir, string filename) throws Error {
        var lmd = new LoadMetadata(this, context, gcamera, fulldir, filename, this.cancellable);
        yield lmd.run(workers);

        return lmd.metadata;
    }

    private class LoadPreview : ThrowingCameraJob {
        public string folder;
        public string file_name;
        public Gdk.Pixbuf preview;
        public string md5;

        public LoadPreview(Object owner, GPhoto.Context context, GPhoto.Camera camera, string folder, string file_name, Cancellable? cancellable) {
            base(owner, context, camera, cancellable);
            this.folder = folder;
            this.file_name = file_name;
        }

        public override void execute() {
            try {
                Bytes? raw = null;
                this.md5 = null;

                try {
                    raw = GPhoto.load_file_into_buffer(this.context, this.camera, this.folder,
                        this.file_name, GPhoto.CameraFileType.PREVIEW);
                } catch (Error e) {
                    PhotoMetadata metadata = GPhoto.get_fallback_metadata(this.camera, this.context,
                        this.folder, this.file_name);
                    if (metadata == null)
                        return;
                    if (metadata.get_preview_count() == 0)
                        return;

                    // Get the smallest preview from meta-data
                    var preview = metadata.get_preview(metadata.get_preview_count() - 1);
                    raw = preview.flatten();
                    this.md5 = Checksum.compute_for_bytes(ChecksumType.MD5, raw);
                }

                this.md5 = Checksum.compute_for_bytes(ChecksumType.MD5, raw);

                MemoryInputStream mins = new MemoryInputStream.from_bytes(raw);

                this.preview = new Gdk.Pixbuf.from_stream_at_scale(mins, ImportPreview.MAX_SCALE,
                    ImportPreview.MAX_SCALE, true, null);
            } catch (Error e) {
                this.error = e;
            }
        }
    }

    public async Gdk.Pixbuf load_preview(string fulldir, string filename, out string md5) throws Error {
        var lmd = new LoadPreview(this, context, gcamera, fulldir, filename, this.cancellable);
        yield lmd.run(workers);
        md5 = lmd.md5;

        return lmd.preview;
    }

    private class ExitCamera : ResultCameraJob {
        public ExitCamera(Object owner, GPhoto.Context context, GPhoto.Camera camera, Cancellable? cancellable = null) {
            base(owner, context, camera, cancellable);
        }

        public override void execute() {
            this.result = camera.exit(this.context);
        }
    }

    public async GPhoto.Result shutdown() {
        var exit = new ExitCamera(this, context, gcamera, null);
        return yield exit.run(workers);
    }

    private class DeleteFile : ResultCameraJob {
        public string fulldir;
        public string file_name;

        public DeleteFile(Object owner, GPhoto.Context context, GPhoto.Camera camera, string fulldir, string file_name, Cancellable? cancellable) {
            base(owner, context, camera, cancellable);
            this.fulldir = fulldir;
            this.file_name = file_name;
        }

        public override void execute() {
            this.result = this.camera.delete_file(this.fulldir, this.file_name, this.context);
        }
    }

    public async GPhoto.Result delete_file(string fulldir, string filename) {
        var del = new DeleteFile(this, context, gcamera, fulldir, filename, this.cancellable);
        return yield del.run(workers);
    }
}


