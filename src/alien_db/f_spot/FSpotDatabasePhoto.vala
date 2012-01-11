/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace AlienDb.FSpot {

/**
 * The object that implements an F-Spot photo and provides access to all the
 * elements necessary to read data from the photographic source.
 */
public class FSpotDatabasePhoto : Object, AlienDatabasePhoto {
    private FSpotPhotoRow photo_row;
    private FSpotPhotoVersionRow? photo_version_row;
    private FSpotRollRow? roll_row;
    private Gee.Collection<AlienDatabaseTag> tags;
    private AlienDatabaseEvent? event;
    private Rating rating;
    
    public FSpotDatabasePhoto(
        FSpotPhotoRow photo_row,
        FSpotPhotoVersionRow? photo_version_row,
        FSpotRollRow? roll_row,
        Gee.Collection<AlienDatabaseTag> tags,
        AlienDatabaseEvent? event,
        bool is_hidden,
        bool is_favorite
    ) {
        this.photo_row = photo_row;
        this.photo_version_row = photo_version_row;
        this.roll_row = roll_row;
        this.tags = tags;
        this.event = event;
        if (photo_row.rating > 0)
            this.rating = Rating.unserialize(photo_row.rating);
        else if (is_hidden)
            this.rating = Rating.REJECTED;
        else if (is_favorite)
            this.rating = Rating.FIVE;
        else
            this.rating = Rating.UNRATED;
    }
    
    public string get_folder_path() {
        return (photo_version_row != null) ?
            photo_version_row.base_path.get_path() :
            photo_row.base_path.get_path();
    }
    
    public string get_filename() {
        return (photo_version_row != null) ?
            photo_version_row.filename :
            photo_row.filename;
    }
    
    public Gee.Collection<AlienDatabaseTag> get_tags() {
        return tags;
    }
    
    public AlienDatabaseEvent? get_event() {
        return event;
    }
    
    public Rating get_rating() {
        return rating;
    }
    
    public string? get_title() {
        return is_string_empty(photo_row.description) ? null : photo_row.description;
    }
    
    public ImportID? get_import_id() {
        if (roll_row != null)
            return ImportID((int64)roll_row.time);
        else
            return null;
    }
}

}

