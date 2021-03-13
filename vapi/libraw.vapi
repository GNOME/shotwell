/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

[CCode (cprefix="libraw_", cheader_filename="libraw/libraw.h")]
namespace LibRaw {

[CCode (cname="LIBRAW_CHECK_VERSION")]
public bool check_version(int major, int minor, int patch);

public unowned string version();

public unowned string versionNumber();

[SimpleType]
[CCode (cname="libraw_imgother_t")]
public struct ImageOther {
    public float iso_speed;
    public float shutter;
    public float aperture;
    public float focal_len;
    public time_t timestamp;
    public uint shot_order;
    public uint gpsdata[32];
    public char desc[512];
    public char artist[64];
}

[SimpleType]
[CCode (cname="libraw_iparams_t")]
public struct ImageParams {
    public uint raw_count;
    public uint dng_version;
    public bool is_foveon;
    public int colors;
    public uint filters;
    
    public char *make;
    public char *model;
    public char *cdesc;
    
    public string get_make() {
        return build_string(make, 64);
    }
    
    public string get_model() {
        return build_string(model, 64);
    }
    
    public string get_cdesc() {
        return build_string(cdesc, 5);
    }
    
    private static string build_string(char *array, int len) {
        GLib.StringBuilder builder = new GLib.StringBuilder();
        for (int ctr = 0; ctr < len; ctr++) {
            if (array[ctr] != '\0')
                builder.append_c(array[ctr]);
            else
                break;
        }
        
        return builder.str;
    }
}

[SimpleType]
[CCode (cname="libraw_image_sizes_t")]
public struct ImageSizes {
    public ushort raw_height;
    public ushort raw_width;
    public ushort height;
    public ushort width;
    public ushort top_margin;
    public ushort left_margin;
    public ushort iheight;
    public ushort iwidth;
    public double pixel_aspect;
    public int flip;
    public ushort right_margin;
    public ushort bottom_margin;
}

[CCode (cname="enum LibRaw_constructor_flags", cprefix="LIBRAW_OPIONS_")]
public enum Options {
    [CCode (cname="LIBRAW_OPTIONS_NONE")]
    NONE,
    NO_MEMERR_CALLBACK,
    NO_DATAERR_CALLBACK
}

[SimpleType]
[CCode (cname="libraw_output_params_t")]
public struct OutputParams {
    public uint greybox[4];
    public double aber[4];
    public double gamm[6];
    public float user_mul[4];
    public uint shot_select;
    public uint multi_out;
    public float bright;
    public float threshold;
    public bool half_size;
    public bool four_color_rgb;
    public int highlight;
    public bool use_auto_wb;
    public bool use_camera_wb;
    public int use_camera_matrix;
    public int output_color;
    public int output_bps;
    public bool output_tiff;
    public int user_flip;
    public int user_qual;
    public int user_black;
    public int user_sat;
    public int med_passes;
    public bool no_auto_bright;
    public float auto_bright_thr;
    public int use_fuji_rotate;
    public int green_matching;

    /* DCB parameters */
    public int dcb_iterations;
    public int dcb_enhance_fl;
    public int fbdd_noiserd;

    /* VCD parameters */
    public int eeci_refine;
    public int es_med_passes;
    /* AMaZE*/
    public int ca_correc;
    public float cared;
    public float cablue;
    public int cfaline;
    public float linenoise;
    public int cfa_clean;
    public float lclean;
    public float cclean;
    public int cfa_green;
    public float green_thresh;
    public int exp_correc;
    public float exp_shift;
    public float exp_preser;
    
    public static void set_chromatic_aberrations(OutputParams* params, double red_multiplier, double green_multiplier) {
        params->aber[0] = red_multiplier;
        params->aber[2] = green_multiplier;
    }
    
    public static void set_gamma_curve(OutputParams* params, double power, double slope) {
        params->gamm[0] = 1.0 / power;
        params->gamm[1] = slope;
    }
}

[Compact]
[CCode (cname="libraw_processed_image_t", free_function="free")]
public class ProcessedImage {
    public ushort height;
    public ushort width;
    public ushort colors;
    public ushort bits;
    public uint data_size;
    [CCode (array_length_cname="data_size")]
    public uint8[] data;
}

[Compact]
[CCode (cname="libraw_data_t", cprefix="libraw_", free_function="libraw_close")]
public class Processor {
    public OutputParams params;
    
    private Progress progress_flags;
    private Warnings process_warnings;
    private ImageParams idata;
    private ImageSizes sizes;
    private ImageOther other;
    private Thumbnail thumbnail;
    
    [CCode (cname="libraw_init")]
    public Processor(Options flags = Options.NONE);
    
    public Result adjust_sizes_info_only();
    [CCode (cname="libraw_dcraw_document_mode_processing")]
    public Result document_mode_processing();
    public unowned ImageOther get_image_other() { return other; }
    public unowned ImageParams get_image_params() { return idata; }
    public Progress get_progress_flags() { return progress_flags; }
    public Warnings get_process_warnings() { return process_warnings; }
    public unowned ImageSizes get_sizes() { return sizes; }
    public unowned Thumbnail get_thumbnail() { return thumbnail; }
    [CCode (cname="libraw_dcraw_make_mem_image")]
    public ProcessedImage make_mem_image(ref Result result);
    [CCode (cname="libraw_dcraw_make_mem_thumb")]
    public ProcessedImage make_mem_thumb(ref Result result);
    public Result open_buffer(uint8[] buffer);
    public Result open_file(string filename);
    [CCode (cname="libraw_dcraw_process")]
    public Result process();
    [CCode (cname="libraw_dcraw_ppm_tiff_writer")]
    public Result ppm_tiff_writer(string outfile);
    public void recycle();
    public Result rotate_fuji_raw();
    [CCode (cname="libraw_dcraw_thumb_writer")]
    public Result thumb_writer(string outfile);
    public Result unpack();
    public Result unpack_thumb();
}

[CCode (cname="enum LibRaw_progress", cprefix="LIBRAW_PROGRESS_")]
public enum Progress {
   START;
   
   [CCode (cname="libraw_strprogress")]
   public unowned string to_string();
}

[CCode (cname="enum LibRaw_errors", cprefix="LIBRAW_")]
public enum Result {
    SUCCESS,
    UNSPECIFIED_ERROR,
    FILE_UNSUPPORTED,
    REQUEST_FOR_NONEXISTENT_IMAGE,
    OUT_OF_ORDER_CALL,
    NO_THUMBNAIL,
    UNSUPPORTED_THUMBNAIL,
    UNSUFFICIENT_MEMORY,
    DATA_ERROR,
    IO_ERROR,
    CANCELLED_BY_CALLBACK,
    BAD_CROP;
    
    [CCode (cname="LIBRAW_FATAL_ERROR")]
    public bool is_fatal_error();
    
    [CCode (cname="libraw_strerror")]
    public unowned string to_string();
}

[SimpleType]
[CCode (cname="libraw_thumbnail_t")]
public struct Thumbnail {
    public ThumbnailFormat tformat;
    public ushort twidth;
    public ushort theight;
    public uint tlength;
    public int tcolors;
    [CCode (array_length_cname="tlength")]
    public unowned uint8[] thumb;
}

[CCode (cname="enum LibRaw_thumbnail_formats", cprefix="LIBRAW_THUMBNAIL_")]
public enum ThumbnailFormat {
    UNKNOWN,
    JPEG,
    BITMAP,
    LAYER,
    ROLLEI;
}

[CCode (cname="enum LibRaw_warnings", cprefix="LIBRAW_WARN_")]
public enum Warnings {
   NONE
}

}

