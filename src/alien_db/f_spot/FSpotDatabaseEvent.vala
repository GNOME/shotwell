/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace AlienDb.FSpot {

/**
 * The object that implements an F-Spot event and provides access to all the
 * elements necessary to read event information.
 * Events are a special type of tags as far as FSpot is concered so this
 * class wraps a tag row.
 */
public class FSpotDatabaseEvent: Object, AlienDatabaseEvent {
    private FSpotTagRow row;
    
    public FSpotDatabaseEvent(FSpotTagRow row) {
        this.row = row;
    }
    
    public string get_name() {
        return row.name;
    }
}

}

