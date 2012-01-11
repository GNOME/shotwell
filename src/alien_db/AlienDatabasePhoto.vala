/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace AlienDb {

/**
 * The main interface for a single instance of a photo held in the database.
 * This interface assumes that the photograph can be accessed via the Vala
 * File classes.
 */
public interface AlienDatabasePhoto : Object {
    public abstract string get_folder_path();
    
    public abstract string get_filename();
    
    public abstract Gee.Collection<AlienDatabaseTag> get_tags();
    
    public abstract AlienDatabaseEvent? get_event();
    
    public abstract Rating get_rating();
    
    public abstract string? get_title();
    
    public abstract ImportID? get_import_id();
}

}

