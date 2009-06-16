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
        
        public virtual void error(string format, void *va_list) {
        }
        
        public virtual void status(string format, void *va_list) {
        }
        
        public virtual void message(string format, void *va_list) {
        }
        
        public virtual void progress_start(float target, string format, void *va_list) {
        }
        
        public virtual void progress_update(float current) {
        }
        
        public virtual void progress_stop() {
        }
        
        private void on_idle(Context context) {
            idle();
            spin_event_loop();
        }

        private void on_error(Context context, string format, void *va_list) {
            error(format, va_list);
        }
        
        private void on_status(Context context, string format, void *va_list) {
            status(format, va_list);
        }
        
        private void on_message(Context context, string format, void *va_list) {
            message(format, va_list);
        }
        
        private uint on_progress_start(Context context, float target, string format, void *va_list) {
            progress_start(target, format, va_list);
            
            return 0;
        }
        
        private void on_progress_update(Context context, uint id, float current) {
            progress_update(current);
            spin_event_loop();
        }
        
        private void on_progress_stop(Context context, uint id) {
            progress_stop();
        }
    }
    
    public void get_info(Context context, Camera camera, string folder, string filename,
        out CameraFileInfo info) throws Error {
        Result res = camera.get_file_info(folder, filename, out info, context);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file information for %s/%s: %s",
                (int) res, folder, filename, res.as_string());
    }
    
    public Gdk.Pixbuf? load_preview(Context context, Camera camera, string folder, string filename, 
        uint8[] buffer) throws Error {
        int bytes_read = load_file(context, camera, folder, filename, GPhoto.CameraFileType.PREVIEW, buffer);
        if (bytes_read == 0)
            return null;
        
        assert(bytes_read > 0);

        MemoryInputStream mins = new MemoryInputStream.from_data(buffer, bytes_read, null);
            
        return new Gdk.Pixbuf.from_stream(mins, null);
    }
    
    public Gdk.Pixbuf? load_image(Context context, Camera camera, string folder, string filename) throws Error {
        GPhoto.CameraFile camera_file;
        GPhoto.Result res = GPhoto.CameraFile.create(out camera_file);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error allocating camera file: %s", (int) res, res.as_string());
        
        res = camera.get_file(folder, filename, GPhoto.CameraFileType.NORMAL, camera_file, context);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file object for %s/%s: %s", 
                (int) res, folder, filename, res.as_string());

        // TODO: I know, I know.
        res = camera_file.save("shotwell.tmp");
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error copying file %s/%s to %s: %s", (int) res, 
                folder, filename, "shotwell.tmp", res.as_string());
        
        return new Gdk.Pixbuf.from_file("shotwell.tmp");
    }

    public void save_image(Context context, Camera camera, string folder, string filename, File dest_file) throws Error {
        GPhoto.CameraFile camera_file;
        GPhoto.Result res = GPhoto.CameraFile.create(out camera_file);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error allocating camera file: %s", (int) res, res.as_string());
        
        res = camera.get_file(folder, filename, GPhoto.CameraFileType.NORMAL, camera_file, context);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file object for %s/%s: %s", 
                (int) res, folder, filename, res.as_string());

        res = camera_file.save(dest_file.get_path());
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error copying file %s/%s to %s: %s", (int) res, 
                folder, filename, dest_file.get_path(), res.as_string());
    }
    
    public Exif.Data? load_exif(Context context, Camera camera, string folder, string filename,
        uint8[] buffer) throws Error {
        int bytes_read = load_file(context, camera, folder, filename, GPhoto.CameraFileType.EXIF, buffer);
        if (bytes_read == 0)
            return null;
        
        assert(bytes_read > 0);
        
        Exif.Data data = Exif.Data.new_from_data(buffer, bytes_read);
        data.fix();
        
        return data;
    }
    
    public int load_file(Context context, Camera camera, string folder, string filename, 
        GPhoto.CameraFileType filetype, uint8[] buffer) throws Error{
        GPhoto.CameraFile camera_file;
        GPhoto.Result res = GPhoto.CameraFile.create(out camera_file);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error allocating camera file: %s", (int) res, res.as_string());
        
        res = camera.get_file(folder, filename, filetype, camera_file, context);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file object for %s/%s: %s", 
                (int) res, folder, filename, res.as_string());
        
        unowned uint8[] data;
        res = camera_file.get_data_and_size(out data);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file %s/%s: %s", (int) res, 
                folder, filename, res.as_string());
        
        int bytes = int.min(data.length, buffer.length);
        Memory.copy(buffer, data, bytes);
        
        return bytes;
    }
}

