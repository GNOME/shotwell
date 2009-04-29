
namespace GPhoto {
    public void get_info(Context context, Camera camera, string folder, string filename,
        out CameraFileInfo info) throws Error {
        Result res = camera.get_file_info(folder, filename, out info, context);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file information for %s/%s: %s",
                (int) res, folder, filename, res.as_string());
    }
    
    public Gdk.Pixbuf? load_preview(Context context, Camera camera, string folder, string filename, 
        uint8[] buffer) throws Error {
        int bytesRead = load_file(context, camera, folder, filename, GPhoto.CameraFileType.PREVIEW, buffer);
        if (bytesRead == 0)
            return null;
        
        assert(bytesRead > 0);

        MemoryInputStream mins = new MemoryInputStream.from_data(buffer, bytesRead, null);
            
        return new Gdk.Pixbuf.from_stream(mins, null);
    }
    
    public Gdk.Pixbuf? load_image(Context context, Camera camera, string folder, string filename) throws Error {
        GPhoto.CameraFile cameraFile;
        GPhoto.Result res = GPhoto.CameraFile.create(out cameraFile);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error allocating camera file: %s", (int) res, res.as_string());
        
        res = camera.get_file(folder, filename, GPhoto.CameraFileType.NORMAL, cameraFile, context);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file object for %s/%s: %s", 
                (int) res, folder, filename, res.as_string());

        // TODO: I know, I know.
        res = cameraFile.save("shotwell.tmp");
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
        
        debug("folder=%s filename=%s", folder, filename);
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
        int bytesRead = load_file(context, camera, folder, filename, GPhoto.CameraFileType.EXIF, buffer);
        if (bytesRead == 0)
            return null;
        
        assert(bytesRead > 0);
        
        Exif.Data data = Exif.Data.new_from_data(buffer, bytesRead);
        
        return data;
    }
    
    public int load_file(Context context, Camera camera, string folder, string filename, GPhoto.CameraFileType filetype,
        uint8[] buffer) throws Error{
        GPhoto.CameraFile cameraFile;
        GPhoto.Result res = GPhoto.CameraFile.create(out cameraFile);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error allocating camera file: %s", (int) res, res.as_string());
        
        res = camera.get_file(folder, filename, filetype, cameraFile, context);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file object for %s/%s: %s", 
                (int) res, folder, filename, res.as_string());
        
        int bytesRead = 0;
        res = cameraFile.slurp(buffer, out bytesRead);
        if (res != Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Error retrieving file %s/%s: %s", (int) res, 
                folder, filename, res.as_string());
        
        return bytesRead;
    }
}

public errordomain GPhotoError {
    LIBRARY
}
