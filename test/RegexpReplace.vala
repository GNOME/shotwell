// SPDX-License-Identifier: LGPL-2.1-or-later
// SPDX-FileCopyrightText: 2025 Jens Georg <mail@jensge.org>

namespace Db {
    public static unowned string IN_MEMORY_NAME = ":memory:";
}

class AppWindow {
    public static void panic(string args) {}
}

// Helper class to expose protected members
abstract class TestDb : DatabaseTable {
    public static unowned Sqlite.Database get_db() { 
        DatabaseTable.init(Db.IN_MEMORY_NAME);
        return DatabaseTable.db;
    }
}

void main(string[] args) {
    GLib.Intl.setlocale(LocaleCategory.ALL, "");
    Test.init(ref args);
    Test.add_func("/functional/regexp_replace", () => {
        unowned Sqlite.Database db = TestDb.get_db();

        {
            Sqlite.Statement s;
            assert(db.prepare_v2("SELECT regexp_replace('^charset=\\w+\\s*', 'charset=Unicode This is a comment, äöü, some encoding perhjaps', '')", -1, out s) == Sqlite.OK);
            assert(s.step() == Sqlite.ROW);
            assert(s.column_text(0) == "This is a comment, äöü, some encoding perhjaps");
        }

        {
            Sqlite.Statement s;
            assert(db.prepare_v2("SELECT regexp_replace('^charset=\\w+\\s*', 'test charset=Unicode This is a comment, äöü, some encoding perhjaps', '')", -1, out s) == Sqlite.OK);
            assert(s.step() == Sqlite.ROW);
            assert(s.column_text(0) == "test charset=Unicode This is a comment, äöü, some encoding perhjaps");
        }
    });
    Test.add_func("/functional/catch_invalid_regexp", () => {
        unowned Sqlite.Database db = TestDb.get_db();
        assert(db.exec("regexp_replace('charset=\\X*', '', '')") == Sqlite.ERROR);
        assert(db.exec("regexp_replace(NULL, '', '')") == Sqlite.ERROR);
        assert(db.exec("regexp_replace('pattern', NULL, '')") == Sqlite.ERROR);
        
        Sqlite.Statement s;

        // NULL replacement should return the original text, even if it matches
        assert(db.prepare_v2("SELECT regexp_replace('test\\s+', 'test some pattern', NULL)", -1, out s) == Sqlite.OK);
        assert(s.step() == Sqlite.ROW);
        assert(s.column_text(0) == "test some pattern");

    });
    Test.run();
}