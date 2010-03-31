/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

#if !NO_RAW

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

public enum DocMode {
    STANDARD = 0,
    GRAYSCALE = 1,
    GRAYSCALE_NO_WHITE_BALANCE = 2
}

public errordomain Exception {
    UNSPECIFIED,
    UNSUPPORTED_FILE,
    NONEXISTANT_IMAGE,
    OUT_OF_ORDER_CALL,
    NO_THUMBNAIL,
    UNSUPPORTED_THUMBNAIL,
    CANNOT_ADDMASK,
    OUT_OF_MEMORY,
    DATA_ERROR,
    IO_ERROR,
    CANCELLED_BY_CALLBACK
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

public enum Quality {
    LINEAR = 0,
    VNG = 1,
    PPG = 2,
    AHD = 3
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
    
    public unowned uint8[] data {
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
        LibRaw.Result result;
        image = proc.make_mem_image(out result);
        throw_exception("ProcessedImage", result);
    }
    
    public ProcessedImage.from_thumb(LibRaw.Processor proc) throws Exception {
        LibRaw.Result result;
        image = proc.make_mem_thumb(out result);
        throw_exception("ProcessedImage.from_thumb", result);
    }
    
    // TODO: It would be, by far, more efficient to return a shared copy of the pixbuf that the
    // caller can copy if needed (or simply use get_pixbuf_copy).  That would prevent any memory
    // copying at all, as Gdk.Pixbuf.from_data will simply use the supplied pointer and call
    // Gdk.PixbufDestroyNotify when it's completed.  Through some reference counting tricks, the
    // ProcessedImage (and its image.data) would remain in memory even if all external refs are
    // dropped, thus allowing pixbufs to float around long after the ProcessedImage is discarded,
    // all without a memcpy.
    //
    // Unfortunately, the Gdk.PixbufDestroyNotify binding is severely broken in 0.7.10, and this 
    // won't work until it's been corrected:
    // https://bugzilla.gnome.org/show_bug.cgi?id=613855
    
    // This method returns a copy of a pixbuf representing the ProcessedImage.
    public Gdk.Pixbuf get_pixbuf_copy() {
        if (pixbuf == null) {
            pixbuf = new Gdk.Pixbuf.from_data(image.data, Gdk.Colorspace.RGB, false, image.bits,
                image.width, image.height, image.width * image.colors, null);
        }
        
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
    
    public void add_masked_borders_to_bitmap() {
        proc.add_masked_borders_to_bitmap();
    }
    
    public void adjust_sizes_info_only() throws Exception {
        throw_exception("adjust_sizes_info_only", proc.adjust_sizes_info_only());
    }
    
    public void document_mode_processing() throws Exception {
        throw_exception("document_mode_processing", proc.document_mode_processing());
    }
    
    public LibRaw.ImageParams get_image_params() {
        return proc.get_image_params();
    }
    
    public LibRaw.ImageSizes get_sizes() {
        return proc.get_sizes();
    }
    
    public LibRaw.Thumbnail get_thumbnail() {
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
    
    public void rotate_fuji_raw() throws Exception {
        throw_exception("rotate_fuji_raw", proc.rotate_fuji_raw());
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
}

private void throw_exception(string caller, LibRaw.Result result) throws Exception {
    if (result == LibRaw.Result.SUCCESS)
        return;
    
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
        
        case LibRaw.Result.CANNOT_ADDMASK:
            throw new Exception.CANNOT_ADDMASK(msg);
        
        case LibRaw.Result.UNSUFFICIENT_MEMORY:
            throw new Exception.OUT_OF_MEMORY(msg);
        
        case LibRaw.Result.DATA_ERROR:
            throw new Exception.DATA_ERROR(msg);
        
        case LibRaw.Result.IO_ERROR:
            throw new Exception.IO_ERROR(msg);
        
        case LibRaw.Result.CANCELLED_BY_CALLBACK:
            throw new Exception.CANCELLED_BY_CALLBACK(msg);
        
        default:
            return;
    }
}

}

#endif
