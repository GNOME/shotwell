/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public errordomain GPhotoError {
    LIBRARY
}

namespace GPhoto {
    public Bytes? camera_file_to_bytes (CameraFile file) {
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
    // https://bugzilla.gnome.org/show_bug.cgi?id=716915
    public PhotoMetadata? get_fallback_metadata(Camera camera, Context context, string folder, string filename) {
        // Fixme: Why do we need to query get_storageinfo here first?
        GPhoto.CameraStorageInformation[] sifs = null;
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

        return camera_file_to_bytes (camera_file);
    }
}

