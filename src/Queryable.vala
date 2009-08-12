/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public interface Queryable : Object {
    public abstract string get_name();
}

public interface PhotoSource : Queryable {
    public abstract time_t get_exposure_time();

    public abstract Dimensions get_dimensions();

    public abstract uint64 get_filesize();

    public abstract Exif.Data get_exif();
}

public interface EventSource : Queryable {
    public abstract time_t get_start_time();

    public abstract time_t get_end_time();

    public uint64 get_total_filesize() {
        uint64 total_filesize = 0;
        foreach (PhotoSource photo in get_photos()) {
            total_filesize += photo.get_filesize();
        }
        return total_filesize;
    }

    public abstract int get_photo_count();

    public abstract Gee.Iterable<PhotoSource> get_photos();
}
