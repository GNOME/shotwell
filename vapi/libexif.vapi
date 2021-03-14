/* Copyright 2016 Software Freedom Conservancy Inc.
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

        public unowned string get_name();
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
        public unowned Entry get_entry(Tag tag);
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
        public static Rational get_rational(uchar *buffer, ByteOrder byteOrder);
        public static void set_short(uchar *buffer, ByteOrder byteOrder, uint16 val);
        public static void set_sshort(uchar *buffer, ByteOrder byteOrder, int16 val);
        public static void set_long(uchar *buffer, ByteOrder byteOrder, uint32 val);
        public static void set_slong(uchar *buffer, ByteOrder byteOrder, int32 val);
    }

    [CCode (cheader_filename="libexif/exif-content.h", has_target=false)]
    public delegate void ForeachEntryFunc(Entry e, void *user);

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
        public static Data? new_from_file(string path);
        public static Data? new_from_data([CCode (array_length_pos=1.1)]uint8[] data);
        public void dump();
        public void fix();
        public void foreach_content(ForeachContentFunc cb, void *user = null);
        public ByteOrder get_byte_order();
        public DataType get_data_type();
        public void load_data(uchar *buffer, uint size);
        public void set_option(DataOption option);
        public void unset_option(DataOption option);
        public void save_data(uchar **buffer, uint *size);
        public void set_data_type(DataType data_type);
        
        // length is Exif.IFD_COUNT
        public Content[] ifd;
        public uchar *data;
        public uint size;
    }

    [CCode (cheader_filename="libexif/exif-data.h", has_target=false)]
    public delegate void ForeachContentFunc(Content c, void *user);

    [CCode (
        cname="ExifDataOption",
        cheader_filename="libexif/exif-data.h",
        cprefix="EXIF_DATA_OPTION_"
    )]
    public enum DataOption {
        IGNORE_UNKNOWN_TAGS,
        FOLLOW_SPECIFICATION,
        DONT_CHANGE_MAKER_NOTE;

        public unowned string get_name();
        public unowned string get_description();
    }
    
    [CCode (
        cname="ExifDataType",
        cheader_filename="libexif/exif-data-type.h",
        cprefix="EXIF_DATA_TYPE_"
    )]
    public enum DataType {
        UNCOMPRESSED_CHUNKY,
        UNCOMPRESSED_PLANAR,
        UNCOMPRESSED_YCC,
        COMPRESSED;
        
        public bool is_valid() {
            switch (this) {
                case UNCOMPRESSED_CHUNKY:
                case UNCOMPRESSED_PLANAR:
                case UNCOMPRESSED_YCC:
                case COMPRESSED:
                    return true;
                
                default:
                    return false;
            }
        }
    }
    
    [CCode (cname="EXIF_DATA_TYPE_COUNT")]
    public const int DATA_TYPE_COUNT;
    
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
        public unowned char* get_value(char *val, uint maxlen);
        public string get_string() {
            char[] buffer = new char[256];
            get_value(buffer, 256);
            
            GLib.StringBuilder builder = new GLib.StringBuilder();
            foreach (char c in buffer)
                builder.append_c(c);
            
            return builder.str;
        }
        
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

        public unowned string get_name();
        public unowned uchar get_size();
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

        public unowned string get_name();
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

        public unowned string get_title();
        public unowned string get_message();
    }
    
    [Compact]
    [CCode (
        cname="ExifMem",
        cheader_filename="libexif/exif-mem.h",
        ref_function="exif_mem_ref",
        ref_function_void=true,
        unref_function="exif_mem_unref"
    )]
    public class Mem {
        public void *alloc(uint32 size);
        public void *realloc(void *ptr, uint32 size);
        public void free(void *ptr);
        public static Mem new_default();
    }
    
    [SimpleType]
    [CCode (
        cname="ExifRational",
        cheader_filename="libexif/exif-utils.h"
    )]
    public struct Rational {
        uint32 numerator;
        uint32 denominator;
    }
    
    [CCode (
        cname="ExifSupportLevel",
        cheader_filename="libexif/exif-tag.h",
        cprefix="EXIF_SUPPORT_LEVEL_"
    )]
    public enum SupportLevel {
        UNKNOWN,
        NOT_RECORDED,
        MANDATORY,
        OPTIONAL
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
        RELATED_IMAGE_LENGTH,
        EXPOSURE_TIME,
        FNUMBER,
        ISO_SPEED_RATINGS,
        MAKE,
        MODEL,
        FLASH,
        FOCAL_LENGTH,
        GPS_LATITUDE,
        GPS_LATITUDE_REF,
        GPS_LONGITUDE,
        GPS_LONGITUDE_REF,
        ARTIST,
        COPYRIGHT,
        SOFTWARE,
        IMAGE_DESCRIPTION;

        public unowned string get_name_in_ifd(Ifd ifd);
        public unowned string get_title_in_ifd(Ifd ifd);
        public unowned string get_description_in_ifd(Ifd ifd);
        public SupportLevel get_support_level_in_ifd(Ifd ifd, DataType data_type);
    }
}
