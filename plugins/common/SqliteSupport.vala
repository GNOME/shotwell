/* Copyright 2009-2014 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public errordomain DatabaseError {
    ERROR,
    BACKING,
    MEMORY,
    ABORT,
    LIMITS,
    TYPESPEC
}

public abstract class ImportableDatabaseTable {
    
    protected static Sqlite.Database db;
    
    public string table_name = null;
    
    protected void set_table_name(string table_name) {
        this.table_name = table_name;
    }
    
    // This method will throw an error on an SQLite return code unless it's OK, DONE, or ROW, which
    // are considered normal results.
    protected static void throw_error(string method, int res) throws DatabaseError {
        string msg = "(%s) [%d] - %s".printf(method, res, db.errmsg());
        
        switch (res) {
            case Sqlite.OK:
            case Sqlite.DONE:
            case Sqlite.ROW:
                return;
            
            case Sqlite.PERM:
            case Sqlite.BUSY:
            case Sqlite.READONLY:
            case Sqlite.IOERR:
            case Sqlite.CORRUPT:
            case Sqlite.CANTOPEN:
            case Sqlite.NOLFS:
            case Sqlite.AUTH:
            case Sqlite.FORMAT:
            case Sqlite.NOTADB:
                throw new DatabaseError.BACKING(msg);
            
            case Sqlite.NOMEM:
                throw new DatabaseError.MEMORY(msg);
            
            case Sqlite.ABORT:
            case Sqlite.LOCKED:
            case Sqlite.INTERRUPT:
                throw new DatabaseError.ABORT(msg);
            
            case Sqlite.FULL:
            case Sqlite.EMPTY:
            case Sqlite.TOOBIG:
            case Sqlite.CONSTRAINT:
            case Sqlite.RANGE:
                throw new DatabaseError.LIMITS(msg);
            
            case Sqlite.SCHEMA:
            case Sqlite.MISMATCH:
                throw new DatabaseError.TYPESPEC(msg);
            
            case Sqlite.ERROR:
            case Sqlite.INTERNAL:
            case Sqlite.MISUSE:
            default:
                throw new DatabaseError.ERROR(msg);
        }
    }
}

