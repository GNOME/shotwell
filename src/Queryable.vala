/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// Value doesn't box structs, so use the following classes to box manually until the bug is fixed:
// http://bugzilla.gnome.org/show_bug.cgi?id=590987
public abstract class BoxedStruct {
}

public class BoxedTime : BoxedStruct {
    public time_t time;
    public BoxedTime(time_t time) {
        this.time = time;
    }
}

public class BoxedDimensions : BoxedStruct {
    public Dimensions dimensions;
    public BoxedDimensions(Dimensions dimensions) {
        this.dimensions = dimensions;
    }
}

public interface Queryable {
    public enum Type {
        EVENT,
        PHOTO,
        IMPORT_PREVIEW
    }

    public enum Property {
        NAME,
        START_TIME,
        END_TIME,
        TIME,
        DIMENSIONS,
        COUNT,
        SIZE,
        EXIF
    }

    public abstract Queryable.Type get_queryable_type();

    public abstract Value? query_property(Queryable.Property property);

    public abstract Gee.Iterable<Queryable>? get_queryables();
}
