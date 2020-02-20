/*
 * Copyright (C) 2009,2011 Jens Georg <mail@jensge.org>.
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

namespace Rygel.Database {

    public errordomain DatabaseError {
        SQLITE_ERROR, /// Error code translated from SQLite
        OPEN,         /// Error while opening database file
        PREPARE,      /// Error while preparing a statement
        BIND,         /// Error while binding values to a statement
        STEP          /// Error while running through a result set
    }

    public enum Flavor {
        CACHE,  /// Database is a cache (will be placed in XDG_USER_CACHE
        CONFIG, /// Database is configuration (will be placed in XDG_USER_CONFIG)
        FOREIGN /// Database is at a custom location
    }

    public enum Flags {
        READ_ONLY = 1, /// Database is read-only
        WRITE_ONLY = 1 << 1, /// Database is write-only
        /// Database can be read and updated
        READ_WRITE = READ_ONLY | WRITE_ONLY,

        /// Database is shared between several processes
        SHARED = 1 << 2;
    }

    /// Prototype for UTF-8 collation function
    extern static int utf8_collate_str (uint8[] a, uint8[] b);

    /**
     * Special GValue to pass to exec or exec_cursor to bind a column to
     * NULL
     */
    public static GLib.Value @null () {
        GLib.Value v = GLib.Value (typeof (void *));
        v.set_pointer (null);

        return v;
    }
}

/**
 * This class is a thin wrapper around SQLite's database object.
 *
 * It adds statement preparation based on GValue and a cancellable exec
 * function.
 */
public class Rygel.Database.Database : Object, Initable {

    public string name { private get; construct set; }
    public Flavor flavor { private get; construct set; default = Flavor.CACHE; }
    public Flags  flags {
        private get;
        construct set;
        default = Flags.READ_WRITE;
    }

    /**
     * Function to implement the custom SQL function 'contains'
     */
    public static void utf8_contains (Sqlite.Context context,
                                      Sqlite.Value[] args)
                                      requires (args.length == 2) {
        if (args[0].to_text () == null ||
            args[1].to_text () == null) {
           context.result_int (0);

           return;
        }

        var pattern = Regex.escape_string (args[1].to_text ());
        if (Regex.match_simple (pattern,
                                args[0].to_text (),
                                RegexCompileFlags.CASELESS)) {
            context.result_int (1);
        } else {
            context.result_int (0);
        }
    }

    /**
     * Function to implement the custom SQLite collation 'CASEFOLD'.
     *
     * Uses utf8 case-fold to compare the strings.
     */
    public static int utf8_collate (int alen, void* a, int blen, void* b) {
        // unowned to prevent array copy
        unowned uint8[] _a = (uint8[]) a;
        _a.length = alen;

        unowned uint8[] _b = (uint8[]) b;
        _b.length = blen;

        return utf8_collate_str (_a, _b);
    }

    private string build_path () {
        var name_is_path = this.name == ":memory:" ||
                           Path.is_absolute (this.name) ||
                           this.flavor == Flavor.FOREIGN;

        if (!name_is_path) {
            var dirname = Path.build_filename (
                                        this.flavor == Flavor.CACHE
                                            ? Environment.get_user_cache_dir ()
                                            : Environment.get_user_config_dir (),
                                        "rygel");
            DirUtils.create_with_parents (dirname, 0750);

            return Path.build_filename (dirname, "%s.db".printf (this.name));
        } else {
            this.flavor = Flavor.FOREIGN;

            return this.name;
        }
    }

    private Sqlite.Database db;

    /**
     * Connect to a SQLite database file
     *
     * @param name Name of the database which is used to create the file-name
     * @param flavor Specifies the flavor of the database
     * @param flags How to open the database
     */
    public Database (string name,
                     Flavor flavor = Flavor.CACHE,
                     Flags  flags = Flags.READ_WRITE)
                     throws DatabaseError, Error {
        Object (name : name, flavor : flavor, flags : flags);
        init ();
    }

    /**
     * Initialize database. Implemented for Initiable interface.
     *
     * @param cancellable a cancellable (unused)
     * @return true on success, false on error
     * @throws DatabaseError if anything goes wrong
     */
    public bool init (Cancellable? cancellable = null) throws Error {
        var path = this.build_path ();
        if (flags == Flags.READ_ONLY) {
            Sqlite.Database.open_v2 (path, out this.db, Sqlite.OPEN_READONLY);
        } else {
            Sqlite.Database.open (path, out this.db);
        }

        if (this.db.errcode () != Sqlite.OK) {
            var msg = _("Error while opening SQLite database %s: %s");
            throw new DatabaseError.OPEN (msg, path, this.db.errmsg ());
        }

        debug ("Using database file %s", path);

        if (flags != Flags.READ_ONLY) {
            this.exec ("PRAGMA synchronous = OFF");
        }

        if (Flags.SHARED in flags) {
            this.exec ("PRAGMA journal_mode = WAL");
        } else {
            this.exec ("PRAGMA temp_store = MEMORY");
        }

        this.db.create_function ("contains",
                                 2,
                                 Sqlite.UTF8,
                                 null,
                                 Database.utf8_contains,
                                 null,
                                 null);

        this.db.create_collation ("CASEFOLD",
                                  Sqlite.UTF8,
                                  Database.utf8_collate);

        unowned string? sql_debug = Environment.get_variable
                                                         ("SHOTWELL_SQL_DEBUG");

        if (sql_debug != null && sql_debug != "") {
            this.db.trace (on_trace);
        }

        return true;
    }

    private void on_trace (string message) {
        debug ("SQLITE: %s", message);
    }

    /**
     * SQL query function.
     *
     * Use for all queries that return a result set.
     *
     * @param sql The SQL query to run.
     * @param arguments Values to bind in the SQL query or null.
     * @throws DatabaseError if the underlying SQLite operation fails.
     */
    public Cursor exec_cursor (string        sql,
                               GLib.Value[]? arguments = null)
                               throws DatabaseError {
        return new Cursor (this.db, sql, arguments);
    }

    /**
     * Simple SQL query execution function.
     *
     * Use for all queries that don't return anything.
     *
     * @param sql The SQL query to run.
     * @param arguments Values to bind in the SQL query or null.
     * @throws DatabaseError if the underlying SQLite operation fails.
     */
    public void exec (string        sql,
                      GLib.Value[]? arguments = null)
                      throws DatabaseError {
        if (arguments == null) {
            this.db.exec (sql);
            if (this.db.errcode () != Sqlite.OK) {
                var msg = "Failed to run query %s: %s";
                throw new DatabaseError.SQLITE_ERROR (msg, sql, this.db.errmsg ());
            }

            return;
        }

        var cursor = this.exec_cursor (sql, arguments);
        while (cursor.has_next ()) {
            cursor.next ();
        }
    }

    /**
     * Execute a SQL query that returns a single number.
     *
     * @param sql The SQL query to run.
     * @param args Values to bind in the SQL query or null.
     * @return The contents of the first row's column as an int.
     * @throws DatabaseError if the underlying SQLite operation fails.
     */
    public int query_value (string        sql,
                             GLib.Value[]? args = null)
                             throws DatabaseError {
        var cursor = this.exec_cursor (sql, args);
        var statement = cursor.next ();
        return statement->column_int (0);
    }

    /**
     * Analyze triggers of database
     */
    public void analyze () {
        this.db.exec ("ANALYZE");
    }

    /**
     * Start a transaction
     */
    public void begin () throws DatabaseError {
        this.exec ("BEGIN");
    }

    /**
     * Commit a transaction
     */
    public void commit () throws DatabaseError {
        this.exec ("COMMIT");
    }

    /**
     * Rollback a transaction
     */
    public void rollback () {
        try {
            this.exec ("ROLLBACK");
        } catch (DatabaseError error) {
            critical (_("Failed to roll back transaction: %s"),
                      error.message);
        }
    }

    /**
     * Check for an empty SQLite database.
     * @return true if the file is an empty SQLite database, false otherwise
     * @throws DatabaseError if the SQLite meta table does not exist which
     * usually indicates that the file is not a databsae
     */
    public bool is_empty () throws DatabaseError {
        return this.query_value ("SELECT count(type) FROM " +
                                 "sqlite_master WHERE rowid = 1") == 0;
    }
}
