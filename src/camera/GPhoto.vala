/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public errordomain GPhotoError {
    LIBRARY
}

namespace GPhoto {
    // ContextWrapper assigns signals to the various GPhoto.Context callbacks, as well as spins
    // the event loop at opportune times.
    public class ContextWrapper {
        public Context context = new Context();
        
        public ContextWrapper() {
            context.set_idle_func(on_idle);
            context.set_error_func(on_error);
            context.set_status_func(on_status);
            context.set_message_func(on_message);
            context.set_progress_funcs(on_progress_start, on_progress_update, on_progress_stop);
        }
        
        public virtual void idle() {
        }

        public virtual void error(string text, void *data) {
        }

        public virtual void status(string text, void *data) {
        }

        public virtual void message(string text, void *data) {
        }
        
        public virtual void progress_start(float current, string text, void *data) {
        }
        
        public virtual void progress_update(float current, void *data) {
        }
        
        public virtual void progress_stop() {
        }
        
        private void on_idle(Context context) {
            idle();
        }

        private void on_error(Context context, string text) {
            error(text, null);
        }
        
        private void on_status(Context context, string text) {
            status(text, null);
        }
        
        private void on_message(Context context, string text) {
            message(text, null);
        }
        
        private uint on_progress_start(Context context, float target, string text) {
            progress_start(target, text, null);
            
            return 0;
        }
        
        private void on_progress_update(Context context, uint id, float current) {
            progress_update(current, null);
        }
        
        private void on_progress_stop(Context context, uint id) {
            progress_stop();
        }

    }
    
    public class SpinIdleWrapper : ContextWrapper {
        public SpinIdleWrapper() {
        }
        
        public override void idle() {
            base.idle();
            
            spin_event_loop();
        }

        public override void progress_update(float current, void *data) {
            base.progress_update(current, data);

            spin_event_loop();
        }
    }

    // For CameraFileInfoFile, CameraFileInfoPreview, and CameraStorageInformation.  See:
    // http://redmine.yorba.org/issues/1851
    // https://bugzilla.redhat.com/show_bug.cgi?id=585676
    // https://sourceforge.net/tracker/?func=detail&aid=3000198&group_id=8874&atid=108874
    public const int MAX_FILENAME_LENGTH = 63;
    public const int MAX_BASEDIR_LENGTH = 255;
    
    public bool get_info(Context context, Camera camera, string folder, string filename,
        out CameraFileInfo info) throws Error {
        if (folder.length > MAX_BASEDIR_LENGTH || filename.length > MAX_FILENAME_LENGTH) {
            info = {};
            
            return false;
        }
        
        Result res = camera.get_file_info(folder, filename, out info, context);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file information for %s/%s: %s",
                (int) res, folder, filename, res.as_string());
        
        return true;
    }

    public Bytes? camera_file_to_bytes (Context context, CameraFile file) {
        // if buffer can be loaded into memory, return a Bytes class with
        // CameraFile being the owner of the data. This way, the CameraFile is freed
        // when the Bytes are freed
        unowned uint8[] buffer = null;
        var res = file.get_data(out buffer);
        if (res != Result.OK)
            return null;

        return Bytes.new_with_owner<GPhoto.CameraFile>(buffer, file);
    }

    // Libgphoto will in some instances refuse to get metadata from a camera, but the camera is accessible as a
    // filesystem.  In these cases shotwell can access the file directly. See:
    // http://redmine.yorba.org/issues/2959
    public PhotoMetadata? get_fallback_metadata(Camera camera, Context context, string folder, string filename) {
        // Fixme: Why do we need to query get_storageinfo here first?
        GPhoto.CameraStorageInformation[] sifs = null;
        int count = 0;
        camera.get_storageinfo(out sifs, context);
        
        GPhoto.PortInfo port_info;
        camera.get_port_info(out port_info);
        
        string path;
        port_info.get_path(out path);
        
        string prefix = "disk:";
        if(path.has_prefix(prefix))
            path = path[prefix.length:path.length];
        else
            return null;
        
        PhotoMetadata? metadata = new PhotoMetadata();
        try {
            metadata.read_from_file(File.new_for_path(path + folder + "/" + filename));
        } catch {
            metadata = null;
        }
        
        return metadata;
    }
    
    public Gdk.Pixbuf? load_preview(Context context, Camera camera, string folder, string filename,
            out string? preview_md5) throws Error {
        Bytes? raw = null;
        Bytes? out_bytes = null;
        preview_md5 = null;
        
        try {
            raw = load_file_into_buffer(context, camera, folder, filename, GPhoto.CameraFileType.PREVIEW);
        } catch {
            PhotoMetadata metadata = get_fallback_metadata(camera, context, folder, filename);
            if(null == metadata)
                return null;
            if(0 == metadata.get_preview_count())
                return null;

            // Get the smallest preview from meta-data
            var preview = metadata.get_preview (metadata.get_preview_count() - 1);
            raw = preview.flatten();
            preview_md5 = Checksum.compute_for_bytes(ChecksumType.MD5, raw);
        }
        
        out_bytes = raw;
        preview_md5 = Checksum.compute_for_bytes(ChecksumType.MD5, out_bytes);

        MemoryInputStream mins = new MemoryInputStream.from_bytes (raw);

        return new Gdk.Pixbuf.from_stream_at_scale(mins, ImportPreview.MAX_SCALE, ImportPreview.MAX_SCALE, true, null);
    }
    
    public Gdk.Pixbuf? load_image(Context context, Camera camera, string folder, string filename) 
        throws Error {
        InputStream ins = load_file_into_stream(context, camera, folder, filename, GPhoto.CameraFileType.NORMAL);
        if (ins == null)
            return null;
        
        return new Gdk.Pixbuf.from_stream(ins, null);
    }

    public void save_image(Context context, Camera camera, string folder, string filename, File dest_file) throws Error {
        var fd = Posix.creat(dest_file.get_path(), 0640);
        if (fd < 0) {
            throw new IOError.FAILED("[%d] Error creating file %s: %m", GLib.errno, dest_file.get_path());
        }

        GPhoto.CameraFile camera_file;
        GPhoto.Result res = GPhoto.CameraFile.create_from_fd(out camera_file, fd);
        if (res != Result.OK) {
            throw new GPhotoError.LIBRARY("[%d] Error allocating camera file: %s", (int) res, res.as_string());
        }
        
        res = camera.get_file(folder, filename, GPhoto.CameraFileType.NORMAL, camera_file, context);
        if (res != Result.OK) {
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file object for %s/%s: %s", 
                (int) res, folder, filename, res.as_string());
        }
    }
    
    public PhotoMetadata? load_metadata(Context context, Camera camera, string folder, string filename)
        throws Error {
        Bytes? camera_raw = null;
        try {
            camera_raw = load_file_into_buffer(context, camera, folder, filename, GPhoto.CameraFileType.EXIF);
        } catch {
            return get_fallback_metadata(camera, context, folder, filename);
        }
        
        if (camera_raw == null || camera_raw.length == 0)
            return null;
        
        PhotoMetadata metadata = new PhotoMetadata();
        metadata.read_from_app1_segment(camera_raw);
        
        return metadata;
    }
    
    // Returns an InputStream for the requested camera file.  The stream should be used
    // immediately rather than stored, as the backing is temporary in nature.
    public InputStream load_file_into_stream(Context context, Camera camera, string folder, string filename, 
        GPhoto.CameraFileType filetype) throws Error {
        GPhoto.CameraFile camera_file;
        GPhoto.Result res = GPhoto.CameraFile.create(out camera_file);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error allocating camera file: %s", (int) res, res.as_string());
        
        res = camera.get_file(folder, filename, filetype, camera_file, context);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file object for %s/%s: %s", 
                (int) res, folder, filename, res.as_string());
        
        // if entire file fits in memory, return a stream from that ...
        // The camera_file is set as data on the object to keep it alive while
        // the MemoryInputStream is alive.
        var bytes = camera_file_to_bytes (context, camera_file);
        if (bytes != null) {
            return new MemoryInputStream.from_bytes(bytes);
        }

        // if not stored in memory, try copying it to a temp file and then reading out of that
        File temp = AppDirs.get_temp_dir().get_child("import.tmp");
        res = camera_file.save(temp.get_path());
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error copying file %s/%s to %s: %s", (int) res, 
                folder, filename, temp.get_path(), res.as_string());
        
        return temp.read(null);
    }
    
    // Returns a buffer with the requested file, if within reason.  Use load_file for larger files.
    public Bytes? load_file_into_buffer(Context context, Camera camera, string folder,
        string filename, CameraFileType filetype) throws Error {
        GPhoto.CameraFile camera_file;
        GPhoto.Result res = GPhoto.CameraFile.create(out camera_file);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error allocating camera file: %s", (int) res, res.as_string());

        res = camera.get_file(folder, filename, filetype, camera_file, context);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file object for %s/%s: %s", 
                (int) res, folder, filename, res.as_string());

        return camera_file_to_bytes (context, camera_file);
    }
}

