/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace GRaw {

public const double HD_POWER = 2.222;
public const double HD_SLOPE = 4.5;

public const double SRGB_POWER = 2.4;
public const double SRGB_SLOPE = 12.92;

public enum Colorspace {
    RAW = 0,
    SRGB = 1,
    ADOBE = 2,
    WIDE = 3,
    PROPHOTO = 4,
    XYZ = 5
}

public errordomain Exception {
    UNSPECIFIED,
    UNSUPPORTED_FILE,
    NONEXISTANT_IMAGE,
    OUT_OF_ORDER_CALL,
    NO_THUMBNAIL,
    UNSUPPORTED_THUMBNAIL,
    OUT_OF_MEMORY,
    DATA_ERROR,
    IO_ERROR,
    CANCELLED_BY_CALLBACK,
    BAD_CROP,
    SYSTEM_ERROR
}

public enum Flip {
    FROM_SOURCE = -1,
    NONE = 0,
    UPSIDE_DOWN = 3,
    COUNTERCLOCKWISE = 5,
    CLOCKWISE = 6
}

public enum FujiRotate {
    USE = -1,
    DONT_USE = 0
}

public enum HighlightMode {
    CLIP = 0,
    UNCLIP = 1,
    BLEND = 2,
    REBUILD = 3
}

public enum InterpolationQuality {
    LINEAR = 0,
    VNG = 1,
    PPG = 2,
    AHD = 3
}

public enum UseCameraMatrix {
    IGNORE = 0,
    EMBEDDED_COLOR_PROFILE = 1,
    EMBEDDED_COLOR_DATA = 3
}

public class ProcessedImage {
    private LibRaw.ProcessedImage image;
    private Gdk.Pixbuf pixbuf = null;
    
    public ushort width {
        get {
            return image.width;
        }
    }
    
    public ushort height {
        get {
            return image.height;
        }
    }
    
    public ushort colors {
        get {
            return image.colors;
        }
    }
    
    public ushort bits {
        get {
            return image.bits;
        }
    }
    
    public uint8* data {
        get {
            return image.data;
        }
    }
    
    public uint data_size {
        get {
            return image.data_size;
        }
    }
    
    public ProcessedImage(LibRaw.Processor proc) throws Exception {
        LibRaw.Result result = LibRaw.Result.SUCCESS;
        image = proc.make_mem_image(ref result);
        throw_exception("ProcessedImage", result);
        assert(image != null);
        
        // A regular mem image comes back with raw RGB data ready for pixbuf (data buffer is shared
        // between the ProcessedImage and the Gdk.Pixbuf)
        pixbuf = new Gdk.Pixbuf.with_unowned_data(image.data, Gdk.Colorspace.RGB, false, image.bits,
            image.width, image.height, image.width * image.colors, null);
    }
    
    public ProcessedImage.from_thumb(LibRaw.Processor proc) throws Exception {
        LibRaw.Result result = LibRaw.Result.SUCCESS;
        image = proc.make_mem_thumb(ref result);
        throw_exception("ProcessedImage.from_thumb", result);
        assert(image != null);
        
        // A mem thumb comes back as the raw bytes from the data segment in the file -- this needs
        // to be decoded before being useful.  This will throw an error if the format is not
        // supported
        try {
            var bytes = new Bytes.static (image.data);
            pixbuf = new Gdk.Pixbuf.from_stream(new MemoryInputStream.from_bytes(bytes),
                null);
        } catch (Error err) {
            throw new Exception.UNSUPPORTED_THUMBNAIL(err.message);
        }
        
        // fix up the ProcessedImage fields (which are unset when decoding the thumb)
        image.width = (ushort) pixbuf.width;
        image.height = (ushort) pixbuf.height;
        image.colors = (ushort) pixbuf.n_channels;
        image.bits = (ushort) pixbuf.bits_per_sample;
    }
    
    // This method returns a copy of a pixbuf representing the ProcessedImage.
    public Gdk.Pixbuf get_pixbuf_copy() {
        return pixbuf.copy();
    }
}

public class Processor {
    public LibRaw.OutputParams* output_params {
        get {
            return &proc.params;
        }
    }
    
    private LibRaw.Processor proc;
    
    public Processor(LibRaw.Options options = LibRaw.Options.NONE) {
        proc = new LibRaw.Processor(options);
    }
    
    public void adjust_sizes_info_only() throws Exception {
        throw_exception("adjust_sizes_info_only", proc.adjust_sizes_info_only());
    }
    
    public unowned LibRaw.ImageOther get_image_other() {
        return proc.get_image_other();
    }
    
    public unowned LibRaw.ImageParams get_image_params() {
        return proc.get_image_params();
    }
    
    public unowned LibRaw.ImageSizes get_sizes() {
        return proc.get_sizes();
    }
    
    public unowned LibRaw.Thumbnail get_thumbnail() {
        return proc.get_thumbnail();
    }
    
    public ProcessedImage make_mem_image() throws Exception {
        return new ProcessedImage(proc);
    }
    
    public ProcessedImage make_thumb_image() throws Exception {
        return new ProcessedImage.from_thumb(proc);
    }
    
    public void open_buffer(uint8[] buffer) throws Exception {
        throw_exception("open_buffer", proc.open_buffer(buffer));
    }
    
    public void open_file(string filename) throws Exception {
        throw_exception("open_file", proc.open_file(filename));
    }
    
    public void process() throws Exception {
        throw_exception("process", proc.process());
    }
    
    public void ppm_tiff_writer(string filename) throws Exception {
        throw_exception("ppm_tiff_writer", proc.ppm_tiff_writer(filename));
    }
    
    public void thumb_writer(string filename) throws Exception {
        throw_exception("thumb_writer", proc.thumb_writer(filename));
    }
    
    public void recycle() {
        proc.recycle();
    }
    
    public void unpack() throws Exception {
        throw_exception("unpack", proc.unpack());
    }
    
    public void unpack_thumb() throws Exception {
        throw_exception("unpack_thumb", proc.unpack_thumb());
    }
    
    // This configures output_params for reasonable settings for turning a RAW image into an 
    // RGB ProcessedImage suitable for display.  Tweaks can occur after this call and before
    // process().
    public void configure_for_rgb_display(bool half_size) {
        // Fields in comments are left to their defaults and/or should be modified by the caller.
        // These fields are set to reasonable defaults by libraw.
        
        // greybox
        LibRaw.OutputParams.set_chromatic_aberrations(output_params, 1.0, 1.0);
        LibRaw.OutputParams.set_gamma_curve(output_params, GRaw.SRGB_POWER, GRaw.SRGB_SLOPE);
        // user_mul
        // shot_select
        // multi_out
        output_params->bright = 1.0f;
        // threshold
        output_params->half_size = half_size;
        // four_color_rgb
        output_params->highlight = GRaw.HighlightMode.CLIP;
        output_params->use_auto_wb = true;
        output_params->use_camera_wb = true;
        output_params->use_camera_matrix = GRaw.UseCameraMatrix.EMBEDDED_COLOR_PROFILE;
        output_params->output_color = GRaw.Colorspace.SRGB;
        // output_profile
        // camera_profile
        // bad_pixels
        // dark_frame
        output_params->output_bps = 8;
        // output_tiff
        output_params->user_flip = GRaw.Flip.FROM_SOURCE;
        output_params->user_qual = GRaw.InterpolationQuality.PPG;
        // user_black
        // user_sat
        // med_passes
        output_params->no_auto_bright = true;
        output_params->auto_bright_thr = 0.01f;
        output_params->use_fuji_rotate = GRaw.FujiRotate.USE;
    }
}

private void throw_exception(string caller, LibRaw.Result result) throws Exception {
    if (result == LibRaw.Result.SUCCESS)
        return;
    else if (result > 0)
        throw new Exception.SYSTEM_ERROR("%s: System error %d: %s", caller, (int) result, strerror(result));
    
    string msg = "%s: %s".printf(caller, result.to_string());
    
    switch (result) {
        case LibRaw.Result.UNSPECIFIED_ERROR:
            throw new Exception.UNSPECIFIED(msg);
        
        case LibRaw.Result.FILE_UNSUPPORTED:
            throw new Exception.UNSUPPORTED_FILE(msg);
        
        case LibRaw.Result.REQUEST_FOR_NONEXISTENT_IMAGE:
            throw new Exception.NONEXISTANT_IMAGE(msg);
        
        case LibRaw.Result.OUT_OF_ORDER_CALL:
            throw new Exception.OUT_OF_ORDER_CALL(msg);
        
        case LibRaw.Result.NO_THUMBNAIL:
            throw new Exception.NO_THUMBNAIL(msg);
        
        case LibRaw.Result.UNSUPPORTED_THUMBNAIL:
            throw new Exception.UNSUPPORTED_THUMBNAIL(msg);
        
        case LibRaw.Result.UNSUFFICIENT_MEMORY:
            throw new Exception.OUT_OF_MEMORY(msg);
        
        case LibRaw.Result.DATA_ERROR:
            throw new Exception.DATA_ERROR(msg);
        
        case LibRaw.Result.IO_ERROR:
            throw new Exception.IO_ERROR(msg);
        
        case LibRaw.Result.CANCELLED_BY_CALLBACK:
            throw new Exception.CANCELLED_BY_CALLBACK(msg);
        
        case LibRaw.Result.BAD_CROP:
            throw new Exception.BAD_CROP(msg);
        
        default:
            return;
    }
}

}

