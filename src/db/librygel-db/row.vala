using Sqlite;

public class Rygel.Database.Row : Object {
    private Statement *statement;
    internal Row (Statement *statement) {
        this.statement = statement;
    }

    public T at<T>(int index) throws DatabaseError {
        if (index >= statement->column_count ()) {
            throw new DatabaseError.OUT_OF_RANGE ("Query result only contains %d columns",
                                                  statement->column_count ());
        }
        if (typeof (T) == typeof (int64) ||
            typeof (T) == typeof (uint64) ||
            typeof (T) == typeof (int) ||
            typeof (T) == typeof (uint) ||
            typeof (T) == typeof (long) ||
            typeof (T) == typeof (ulong)) {
            return (T) statement->column_int64 (index);
        }

        if (typeof (T) == typeof (float) ||
            typeof (T) == typeof (double)) {
            return (T) statement->column_double (index);
        }

        if (typeof (T) == typeof (string)) {
            return statement->column_text (index).dup ();
        }

        if (typeof (T) == typeof (void*)) {
            return statement->column_blob (index);
        }

        if (typeof (T) == typeof (bool)) {
            return statement->column_int (index) != 0;
        }

        assert_not_reached ();
    }
}
