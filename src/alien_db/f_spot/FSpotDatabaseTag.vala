/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace AlienDb.FSpot {

/**
 * The object that implements an F-Spot tag and provides access to all the
 * elements necessary to read tag information.
 */
public class FSpotDatabaseTag: Object, AlienDatabaseTag {
    private FSpotTagRow row;
    
    public FSpotDatabaseTag(FSpotTagRow row) {
        this.row = row;
    }
    
    public string get_name() {
        return row.name;
    }
    
    public bool is_stock() {
        return (row.stock_icon.has_prefix(FSpotTagsTable.PREFIX_STOCK_ICON));
    }
    
    public FSpotTagRow get_row() {
        return row;
    }
    
    public FSpotDatabaseEvent to_event() {
        return new FSpotDatabaseEvent(this.row);
    }
}

}

