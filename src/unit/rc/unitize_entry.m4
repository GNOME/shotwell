/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 *
 * Auto-generated file.  Do not modify!
 */

namespace _APP_GROUP_ {

// Initialize all units, unwinding the inits if an error occurs.  The caller should *not* call
// _APP_GROUP_.unitize_terminate() if an error is thrown.
public void unitize_init() throws Error {
    Unit.Initializer[] entry_points = Unitize.get_entry_points();
    
    int ctr = 0;
    while (ctr < entry_points.length) {
        try {
            entry_points[ctr]();
        } catch (Error err) {
            Unit.Terminator[] terminate_points = Unitize.get_terminate_points();
            while (ctr >= 0)
                terminate_points[ctr--]();
            
            throw err;
        }
        
        ctr++;
    }
}

public void unitize_terminate() {
    Unit.Terminator[] terminate_points = Unitize.get_terminate_points();
    for (int ctr = 0; ctr < terminate_points.length; ctr++)
        terminate_points[ctr]();
}
    
    namespace Unitize {
    
    private Unit.Initializer[]? unitize_entry_points = null;
    private Unit.Terminator[]? unitize_terminate_points = null;
    
    // non-const initializers not allowed in static variables and delegates may not be used as
    // const initializers, hence the accessors
    public Unit.Initializer[] get_entry_points() {
        // dummy_init/dummy_terminate used to deal with dangling comma in macro lists
        if (unitize_entry_points == null)
            unitize_entry_points = { _UNIT_ENTRY_POINTS_ dummy_init };
        
        return unitize_entry_points;
    }
    
    public Unit.Terminator[] get_terminate_points() {
        if (unitize_terminate_points == null)
            unitize_terminate_points = { _UNIT_TERMINATE_POINTS_ dummy_terminate };
        
        return unitize_terminate_points;
    }
    
    private void dummy_init() {
    }
    
    private void dummy_terminate() throws Error {
    }
    
    }

}

