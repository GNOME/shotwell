/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

#if ENABLE_FACES

public class FaceLocation : Object {
    
    private static Gee.Map<FaceID?, Gee.Map<PhotoID?, FaceLocation>> face_photos_map;
    private static Gee.Map<PhotoID?, Gee.Map<FaceID?, FaceLocation>> photo_faces_map;
    
    private FaceLocationID face_location_id;
    private FaceID face_id;
    private PhotoID photo_id;
    private string geometry;
    
    private FaceLocation(FaceLocationID face_location_id, FaceID face_id, PhotoID photo_id,
    string geometry) {
        this.face_location_id = face_location_id;
        this.face_id = face_id;
        this.photo_id = photo_id;
        this.geometry = geometry;
    }
    
    public static FaceLocation create(FaceID face_id, PhotoID photo_id, string geometry) {
        FaceLocation face_location = null;
        
        // Test if that FaceLocation already exists (that face in that photo) ...
        Gee.Map<PhotoID?, FaceLocation> photos_map = face_photos_map.get(face_id);
        Gee.Map<FaceID?, FaceLocation> faces_map = photo_faces_map.get(photo_id);
        
        if (photos_map != null && faces_map != null && faces_map.has_key(face_id)) {
            
            face_location = faces_map.get(face_id);
            
            if (face_location.get_serialized_geometry() != geometry) {
                face_location.set_serialized_geometry(geometry);
                
                try {
                    FaceLocationTable.get_instance().update_face_location_serialized_geometry(
                        face_location);
                } catch (DatabaseError err) {
                    AppWindow.database_error(err);
                }
            }
            
            return face_location;
        }
        
        // ... or create a new FaceLocation.
        try {
            face_location =
                FaceLocation.add_from_row(
                    FaceLocationTable.get_instance().add(face_id, photo_id, geometry));
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        return face_location;
    }
    
    public static void destroy(FaceID face_id, PhotoID photo_id) {
        Gee.Map<PhotoID?, FaceLocation> photos_map = face_photos_map.get(face_id);
        Gee.Map<FaceID?, FaceLocation> faces_map = photo_faces_map.get(photo_id);
        
        assert(photos_map != null);
        assert(faces_map != null);
        
        faces_map.unset(face_id);
        if (faces_map.size == 0)
            photo_faces_map.unset(photo_id);
        
        photos_map.unset(photo_id);
        if (photos_map.size == 0)
            face_photos_map.unset(face_id);
        
        try {
            FaceLocationTable.get_instance().remove_face_from_source(face_id, photo_id);
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
    }
    
    public static FaceLocation add_from_row(FaceLocationRow row) {
        
        FaceLocation face_location =
            new FaceLocation(row.face_location_id, row.face_id, row.photo_id, row.geometry);
        
        Gee.Map<PhotoID?, FaceLocation> photos_map = face_photos_map.get(row.face_id);
        if (photos_map == null) {photos_map = new Gee.HashMap<PhotoID?, FaceLocation>
            ((Gee.HashDataFunc)FaceLocation.photo_id_hash, (Gee.EqualDataFunc)FaceLocation.photo_ids_equal);
            face_photos_map.set(row.face_id, photos_map);
        }
        photos_map.set(row.photo_id, face_location);
        
        Gee.Map<FaceID?, FaceLocation> faces_map = photo_faces_map.get(row.photo_id);
        if (faces_map == null) {faces_map = new Gee.HashMap<FaceID?, FaceLocation>
            ((Gee.HashDataFunc)FaceLocation.face_id_hash, (Gee.EqualDataFunc)FaceLocation.face_ids_equal);
            
            photo_faces_map.set(row.photo_id, faces_map);
        }
        faces_map.set(row.face_id, face_location);
        
        return face_location;
    }
    
    public static Gee.Map<FaceID?, FaceLocation>? get_locations_by_photo(Photo photo) {
        return photo_faces_map.get(photo.get_photo_id());
    }
    
    public static Gee.Map<PhotoID?, FaceLocation>? get_locations_by_face(Face face) {
        return face_photos_map.get(face.get_face_id());
    }
    
    public static Gee.Set<PhotoID?>? get_photo_ids_by_face(Face face) {
        Gee.Map<PhotoID?, FaceLocation>? photos_map = face_photos_map.get(face.get_face_id());
        if (photos_map == null)
            return null;
        
        return photos_map.keys;
    }
    
    public static FaceLocation? get_face_location(FaceID face_id, PhotoID photo_id) {
        Gee.Map<FaceID?, FaceLocation>? faces_map = photo_faces_map.get(photo_id);
        if (faces_map == null)
            return null;
        
        return faces_map.get(face_id);
    }
    
    public static bool photo_ids_equal(void *a, void *b) {
        PhotoID *aid = (PhotoID *) a;
        PhotoID *bid = (PhotoID *) b;
    
        return aid->id == bid->id;
    }
    
    public static bool face_ids_equal(void *a, void *b) {
        FaceID *aid = (FaceID *) a;
        FaceID *bid = (FaceID *) b;
    
        return aid->id == bid->id;
    }
    
    public static uint photo_id_hash(void *p) {
        // Rotating XOR hash
        uint8 u8 = (uint8) ((PhotoID *) p)->id;
        uint hash = 0;
        for (int ctr = 0; ctr < (sizeof(int64) / sizeof(uint8)); ctr++) {
            hash = (hash << 4) ^ (hash >> 28) ^ (u8++);
        }
        
        return hash;
    }
    
    public static uint face_id_hash(void *p) {
        // Rotating XOR hash
        uint8 u8 = (uint8) ((FaceID *) p)->id;
        uint hash = 0;
        for (int ctr = 0; ctr < (sizeof(int64) / sizeof(uint8)); ctr++) {
            hash = (hash << 4) ^ (hash >> 28) ^ (u8++);
        }
        
        return hash;
    }

    public static void init(ProgressMonitor? monitor) {
        face_photos_map = new Gee.HashMap<FaceID?, Gee.HashMap<PhotoID?, FaceLocation>>
            ((Gee.HashDataFunc)face_id_hash, (Gee.EqualDataFunc)face_ids_equal);
        photo_faces_map = new Gee.HashMap<PhotoID?, Gee.HashMap<FaceID?, FaceLocation>>
            ((Gee.HashDataFunc)photo_id_hash, (Gee.EqualDataFunc)photo_ids_equal);
        
        // scoop up all the rows at once
        Gee.List<FaceLocationRow?> rows = null;
        try {
            rows = FaceLocationTable.get_instance().get_all_rows();
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        }
        
        // turn them into FaceLocation objects
        int count = rows.size;
        for (int ctr = 0; ctr < count; ctr++) {
            FaceLocation.add_from_row(rows.get(ctr));
            
            if (monitor != null)
                monitor(ctr, count);
        }
    }
    
    public static void terminate() {
    }
    
    public FaceLocationID get_face_location_id() {
        return face_location_id;
    }
    
    public string get_serialized_geometry() {
        return geometry;
    }
    
    private void set_serialized_geometry(string geometry) {
        this.geometry = geometry;
    }
}

#endif
