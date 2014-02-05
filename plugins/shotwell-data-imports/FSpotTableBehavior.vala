/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace DataImports.FSpot.Db {

/**
 * This class defines a generic table behavior. In practice, it implements
 * the concept of a DAO (Data Access Object) in ORM terms and is responsible
 * for transforming the data extracted from a relational statement into a
 * lightweight value object.
 *
 * The type T defined in the generic is the value object type a behavior
 * implementation is designed to handle. Value object types are designed to
 * contain the data for a single database row.
 */
public interface FSpotTableBehavior<T> : Object {
    public abstract string get_table_name();
    
    public abstract string[] list_columns();
    
    public abstract void build_row(Sqlite.Statement stmt, out T row, int offset = 0);
}

}

