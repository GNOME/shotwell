// SPDX-License-Identifier: LGPL-2.1-or-later
// SPDX-FileCopyrightText: Jens Georg <mail@jensge.org>

public abstract class GlycinReader : PhotoFileReader {
    protected GlycinReader(string filepath, PhotoFileFormat file_format) {
        base (filepath, file_format);
    }
    
    public override PhotoMetadata read_metadata() throws Error {
        PhotoMetadata metadata = new PhotoMetadata();
        metadata.read_from_file(get_file());
        
        return metadata;
    }
    
    public override Gdk.Pixbuf unscaled_read() throws Error {
        var loader = new Gly.Loader(get_file());
        loader.set_accepted_memory_formats(Gly.MemoryFormatSelection.R8G8B8A8 | Gly.MemoryFormatSelection.R8G8B8);
        loader.set_apply_transformations(false);
        var image = loader.load();
        var width = image.get_width();
        var height = image.get_height();
        var request = new Gly.FrameRequest();
        request.set_scale (width, height);
        var frame = image.get_specific_frame(request);
        var memory_format = frame.get_memory_format();

        var pixbuf = new Gdk.Pixbuf.from_bytes(frame.get_buf_bytes(), Gdk.Colorspace.RGB, 
                            memory_format.has_alpha(), 8, (int)frame.get_width(), 
                            (int)frame.get_height(), (int)frame.get_stride());

        pixbuf.set_option("orientation", image.get_transformation_orientation().to_string());

        return pixbuf;
    }
    
    public override Gdk.Pixbuf scaled_read(Dimensions full, Dimensions scaled) throws Error {
        var result = unscaled_read();

        return result.scale_simple(scaled.width, scaled.height, Gdk.InterpType.HYPER);
    }
}

public abstract class GlycinSniffer : PhotoFileSniffer {
    private DetectedPhotoInformation detected = null;
    
    protected GlycinSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }

    public static string? format_name_from_mime(string mime_type) {
        switch (mime_type) {
            case "image/png":
                return "png";
            case "image/avif":
                return "avif";
            case "image/bmp":
                return "bmp";
            case "image/gif":
                return "gif";
            case "image/heif":
                return "heif";
            case "image/jxl":
                return "jxl";
            case "image/tiff":
                return "tiff";
            case "image/jpeg":
                return "jpeg";
            default:
                break;
        }

        return null;
    }
    
    public override DetectedPhotoInformation? sniff(out bool is_corrupted) throws Error {
        detected = new DetectedPhotoInformation();
        is_corrupted = false;
        
        var loader = new Gly.Loader(file);
        loader.set_accepted_memory_formats(Gly.MemoryFormatSelection.R8G8B8A8 | Gly.MemoryFormatSelection.R8G8B8);
        loader.set_apply_transformations(false);
        var image = loader.load();
        var width = image.get_width();
        var height = image.get_height();
        var request = new Gly.FrameRequest();
        request.set_scale (width, height);
        var frame = image.get_specific_frame(request);
        var memory_format = frame.get_memory_format();
        
        detected.colorspace = Gdk.Colorspace.RGB;
        detected.channels = memory_format.has_alpha() ? 4 : 3;
        detected.bits_per_channel = 8;
        detected.format_name = GlycinSniffer.format_name_from_mime(image.get_mime_type());
        detected.file_format = PhotoFileFormat.from_pixbuf_name(detected.format_name);
        detected.image_dim = Dimensions((int)frame.get_width(), (int)frame.get_height());
            
        Checksum? md5_checksum = null;
        if (calc_md5)
            md5_checksum = new Checksum(ChecksumType.MD5);
        
        detected.metadata = new PhotoMetadata();
        try {
            detected.metadata.read_from_file(file);
        } catch (Error err) {
            // no metadata detected
            detected.metadata = null;
        }
        
        if (calc_md5 && detected.metadata != null) {
            detected.exif_md5 = detected.metadata.exif_hash();
            detected.thumbnail_md5 = detected.metadata.thumbnail_hash();
        }
    
        if (calc_md5) {
            // if no MD5, don't read as much, as the needed info will probably be gleaned
            // in the first 8K to 16K
            uint8[] buffer = new uint8[64 * 1024];
            size_t count = 0;
            
            // loop through until all conditions we're searching for are met
            FileInputStream fins = file.read(null);
            for (;;) {
                size_t bytes_read = fins.read(buffer, null);
                if (bytes_read <= 0)
                    break;
                
                count += bytes_read;
                
                md5_checksum.update(buffer, bytes_read);                            
            }
                    
            if (fins != null)
                fins.close(null);
            
            detected.md5 = md5_checksum.get_string();
        }
                
        return detected;
    }
}

