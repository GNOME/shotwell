/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

[CCode (
    cprefix = "Exif",
    lower_case_cprefix="exif_"
)]
namespace Exif {
    [CCode (
        cname="ExifByteOrder",
        cheader_filename="libexif/exif-byte-order.h",
        cprefix="EXIF_BYTE_ORDER_"
    )]
    public enum ByteOrder {
        INTEL,
        MOTOROLA;

        public weak string get_name();
    }

    [Compact]
    [CCode (
        cname="ExifContent",
        cheader_filename="libexif/exif-content.h",
        ref_function="exif_content_ref",
        ref_function_void=true,
        unref_function="exif_content_unref",
        free_function="exif_content_free"
    )]
    public class Content {
        [CCode (cname="exif_content_new")]
        public Content();
        public void add_entry(Entry entry);
        public void remove_entry(Entry entry);
        public void dump(uint indent = 4);
        public void foreach_entry(ForeachEntryFunc cb, void *user);
        public weak Entry get_entry(Tag tag);
        public void fix();
        public Ifd get_ifd();

        public Entry **entries;
        public int count;
        public Data parent;
    }

    [CCode (
        cheader_filename="libexif/exif-utils.h",
        cprefix="exif_",
        lower_case_cprefix="exif_"
    )]
    namespace Convert {
        public static uint16 get_short(uchar *buffer, ByteOrder byteOrder);
        public static int16 get_sshort(uchar *buffer, ByteOrder byteOrder);
        public static uint32 get_long(uchar *buffer, ByteOrder byteOrder);
        public static int32 get_slong(uchar *buffer, ByteOrder byteOrder);
        public static void set_short(uchar *buffer, ByteOrder byteOrder, uint16 val);
        public static void set_sshort(uchar *buffer, ByteOrder byteOrder, int16 val);
        public static void set_long(uchar *buffer, ByteOrder byteOrder, uint32 val);
        public static void set_slong(uchar *buffer, ByteOrder byteOrder, int32 val);
    }

    [CCode (cheader_filename="libexif/exif-content.h")]
    public static delegate void ForeachEntryFunc(Entry e, void *user);

    [Compact]
    [CCode (
        cname="ExifData",
        cheader_filename="libexif/exif-data.h",
        ref_function="exif_data_ref",
        ref_function_void=true,
        unref_function="exif_data_unref",
        free_function="exif_data_free"
    )]
    public class Data {
        [CCode (cname="exif_data_new")]
        public Data();
        public static Data new_from_file(string path);
        public static Data new_from_data(uint8 *data, size_t count);
        public void dump();
        public void fix();
        public void foreach_content(ForeachContentFunc cb, void *user = null);
        public ByteOrder get_byte_order();
        public void set_option(DataOption option);
        public void unset_option(DataOption option);
        public void save_data(uchar **buffer, uint *size);

        // length is Exif.IFD_COUNT
        public Content[] ifd;
        public uchar *data;
        public uint size;
    }

    [CCode (cheader_filename="libexif/exif-data.h")]
    public static delegate void ForeachContentFunc(Content c, void *user);

    [CCode (
        cname="ExifDataOption",
        cheader_filename="libexif/exif-data.h",
        cprefix="EXIF_DATA_OPTION_"
    )]
    public enum DataOption {
        IGNORE_UNKNOWN_TAGS,
        FOLLOW_SPECIFICATION,
        DONT_CHANGE_MAKER_NOTE;

        public weak string get_name();
        public weak string get_description();
    }

    [Compact]
    [CCode (
        cname="ExifEntry",
        cheader_filename="libexif/exif-entry.h",
        ref_function="exif_entry_ref",
        ref_function_void=true,
        unref_function="exif_entry_unref"
    )]
    public class Entry {
        [CCode (cname="exif_entry_new")]
        public Entry();
        public void dump(uint indent = 4);
        public void initialize(Tag tag);
        public void fix();
        public weak string get_value(char *val = new char[256], uint maxlen = 256);

        public Tag tag;
        public Format format;
        public ulong components;
        public uchar *data;
        public uint size;
        public Content *parent;
    }

    [CCode (
        cname="ExifFormat",
        cheader_filename="libexif/exif-format.h",
        cprefix="EXIF_FORMAT_"
    )]
    public enum Format {
        BYTE,
        ASCII,
        SHORT,
        LONG,
        RATIONAL,
        SBYTE,
        UNDEFINED,
        SSHORT,
        SLONG,
        SRATIONAL,
        FLOAT,
        DOUBLE;

        public weak string get_name();
        public weak uchar get_size();
    }

    [CCode (
        cname="ExifIfd",
        cheader_filename="libexif/exif-ifd.h",
        cprefix="EXIF_IFD_"
    )]
    public enum Ifd {
        [CCode (cname="EXIF_IFD_0")]
        ZERO,
        [CCode (cname="EXIF_IFD_1")]
        ONE,
        EXIF,
        GPS,
        INTEROPERABILITY;

        public weak string get_name();
    }
    
    [CCode (cname="EXIF_IFD_COUNT")]
    public const int IFD_COUNT;

    [Compact]
    [CCode (
        cname="ExifLoader",
        cheader_filename="libexif/exif-loader.h",
        ref_function="exif_loader_ref",
        ref_function_void=true,
        unref_function="exif_loader_unref",
        free_function="exif_loader_free"
    )]
    public class Loader {
        [CCode (cname="exif_loader_new")]
        public Loader();
        public void write_file(string fname);
        public void reset();
        public Data get_data();
    }

    // TODO: Flesh out Log functionality
    [Compact]
    [CCode (
        cname="ExifLog",
        cheader_filename="libexif/exif-loader.h",
        ref_function="exif_log_ref",
        ref_function_void=true,
        unref_function="exif_log_unref",
        free_function="exif_log_free"
    )]
    public class Log {
        [CCode (cname="exif_log_new")]
        public Log();
    }

    [CCode (
        cname="ExifLogCode",
        cheader_filename="libexif/exif-log.h",
        cprefix="EXIF_LOG_CODE_"
    )]
    public enum LogCode {
        NONE,
        DEBUG,
        NO_MEMORY,
        CORRUPT_DATA;

        public weak string get_title();
        public weak string get_message();
    }

    [CCode (
        cname="ExifTag",
        cheader_filename="libexif/exif-tag.h",
        cprefix="EXIF_TAG_"
    )]
    public enum Tag {
        PIXEL_X_DIMENSION,
        PIXEL_Y_DIMENSION,
        BITS_PER_SAMPLE,
        DATE_TIME_ORIGINAL,
        ORIENTATION,
        RELATED_IMAGE_WIDTH,
        RELATED_IMAGE_LENGTH;

        public weak string get_name_in_ifd(Ifd ifd);
        public weak string get_title_in_ifd(Ifd ifd);
        public weak string get_description_in_ifd(Ifd ifd);
    }
}
