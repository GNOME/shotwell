/*
 * Copyright (C) 2011 Jens Georg <mail@jensge.org>.
 *
 * Author: Jens Georg <mail@jensge.org>
 *
 * This file is part of Rygel.
 *
 * Rygel is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * Rygel is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

using Sqlite;

public class Rygel.Database.Cursor : Object {
    private Statement statement;
    private int current_state = -1;
    private bool dirty = true;
    private unowned Sqlite.Database db;

    /**
     * Prepare a SQLite statement from a SQL string
     *
     * If @arguments is non-null, it will call bind()
     *
     * @param db SQLite database this cursor belongs to
     * @param sql statement to execute
     * @param arguments array of values to bind to the SQL statement or null if
     * none
     */
    public Cursor (Sqlite.Database   db,
                   string            sql,
                   GLib.Value[]?     arguments) throws DatabaseError {
        this.db = db;

        this.throw_if_code_is_error (db.prepare_v2 (sql,
                                                    -1,
                                                    out this.statement,
                                                    null));
        if (arguments == null) {
            return;
        }

        this.bind (arguments);
    }

    /**
     * Bind new values to a cursor.
     *
     * The cursor will be reset.
     *
     * This function uses the type of the GValue passed in values to determine
     * which _bind function to use.
     *
     * Supported types are: int, long, int64, uint64, string and pointer.
     * Note: The only pointer supported is the null pointer as provided by
     * Database.@null. This is a special value to bind a column to NULL
     * @param arguments array of values to bind to the SQL statement or null if
     * none
     */
    public void bind (GLib.Value[]? arguments) throws DatabaseError {
        this.statement.reset ();
        this.dirty = true;
        this.current_state = -1;

        for (var i = 1; i <= arguments.length; ++i) {
            unowned GLib.Value current_value = arguments[i - 1];

            if (current_value.holds (typeof (int))) {
                statement.bind_int (i, current_value.get_int ());
            } else if (current_value.holds (typeof (int64))) {
                statement.bind_int64 (i, current_value.get_int64 ());
            } else if (current_value.holds (typeof (uint64))) {
                statement.bind_int64 (i, (int64) current_value.get_uint64 ());
            } else if (current_value.holds (typeof (long))) {
                statement.bind_int64 (i, current_value.get_long ());
            } else if (current_value.holds (typeof (uint))) {
                statement.bind_int64 (i, current_value.get_uint ());
            } else if (current_value.holds (typeof (string))) {
                statement.bind_text (i, current_value.get_string ());
            } else if (current_value.holds (typeof (void *))) {
                if (current_value.peek_pointer () == null) {
                    statement.bind_null (i);
                } else {
                    assert_not_reached ();
                }
            } else {
                var type = current_value.type ();
                warning (_("Unsupported type %s"), type.name ());
                assert_not_reached ();
            }

            if (this.db.errcode () != Sqlite.OK) {
                throw new DatabaseError.BIND ("Failed to bind value %d in %s: %s",
                                              i,
                                              this.statement.sql (),
                                              this.db.errmsg ());
            }
        }
    }

    /**
     * Check if the cursor has more rows left
     *
     * @return true if more rows left, false otherwise
     */
    public bool has_next () throws DatabaseError {
        if (this.dirty) {
            this.current_state = this.statement.step ();
            this.dirty = false;
        }

        this.throw_if_code_is_error (this.current_state);

        return this.current_state == Sqlite.ROW || this.current_state == -1;
    }

    /**
     * Get the next row of this cursor.
     *
     * This function uses pointers instead of unowned because var doesn't work
     * with unowned.
     *
     * @return a pointer to the current row
     */
    public Statement* next () throws DatabaseError {
        this.has_next ();
        this.throw_if_code_is_error (this.current_state);
        this.dirty = true;

        return this.statement;
    }

    // convenience functions for "foreach"

    /**
     * Return an iterator to the cursor to use with foreach
     *
     * @return an iterator wrapping the cursor
     */
    public Iterator iterator () {
        return new Iterator (this);
    }

    public class Iterator {
        public Cursor cursor;

        public Iterator (Cursor cursor) {
            this.cursor = cursor;
        }

        public bool next () throws DatabaseError {
            return this.cursor.has_next ();
        }

        public unowned Statement @get () throws DatabaseError {
            return this.cursor.next ();
        }
    }

    /**
     * Convert a SQLite return code to a DatabaseError
     */
    protected void throw_if_code_is_error (int sqlite_error)
                                           throws DatabaseError {
        switch (sqlite_error) {
            case Sqlite.OK:
            case Sqlite.DONE:
            case Sqlite.ROW:
                return;
            default:
                throw new DatabaseError.SQLITE_ERROR
                                        ("SQLite error %d: %s",
                                         sqlite_error,
                                         this.db.errmsg ());
        }
    }

    /**
     * Check if the last operation on the database was an error
     */
    protected void throw_if_db_has_error () throws DatabaseError {
        this.throw_if_code_is_error (this.db.errcode ());
    }
}
