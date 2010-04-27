/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class GdkReader : PhotoFileReader {
    private Exif.DataType? exif_datatype;
    
    public GdkReader(string filepath, PhotoFileFormat file_format, Exif.DataType? exif_datatype) {
        base (filepath, file_format);
        
        this.exif_datatype = exif_datatype;
    }
    
    public override Exif.Data? read_exif() throws Error {
        if (exif_datatype == null)
            return null;

        Exif.Data? exif = Exif.Data.new_from_file(get_filepath());
        if (exif != null)
            exif.set_data_type(exif_datatype);
        
        return exif;
    }
    
    public override Gdk.Pixbuf unscaled_read() throws Error {
        return new Gdk.Pixbuf.from_file(get_filepath());
    }
    
    public override Gdk.Pixbuf scaled_read(Dimensions full, Dimensions scaled) throws Error {
        return new Gdk.Pixbuf.from_file_at_scale(get_filepath(), scaled.width, scaled.height, false);
    }
}

public abstract class GdkSniffer : PhotoFileSniffer {
    private DetectedPhotoInformation detected = null;
    private bool size_ready = false;
    private bool area_prepared = false;
    
    public GdkSniffer(File file, PhotoFileSniffer.Options options) {
        base (file, options);
    }
    
    public override DetectedPhotoInformation? sniff() throws Error {
        detected = new DetectedPhotoInformation();
        
        Gdk.PixbufLoader pixbuf_loader = new Gdk.PixbufLoader();
        pixbuf_loader.size_prepared += on_size_prepared;
        pixbuf_loader.area_prepared += on_area_prepared;
        
        // valac chokes on the ternary operator here
        Checksum? md5_checksum = null;
        if (calc_md5)
            md5_checksum = new Checksum(ChecksumType.MD5);
        
        // load EXIF
        PhotoExif photo_exif = new PhotoExif(file);
        try {
            photo_exif.load();
            detected.exif = photo_exif.get_exif();
            
            if (calc_md5) {
                detected.exif_md5 = photo_exif.get_md5();
                detected.thumbnail_md5 = photo_exif.get_thumbnail_md5();
            }
        } catch (ExifError exif_err) {
            // no EXIF to speak of
        }
        photo_exif = null;
        
        // if no MD5, don't read as much, as the info will probably be gleaned
        // in the first 8K to 16K
        uint8[] buffer = calc_md5 ? new uint8[64 * 1024] : new uint8[8 * 1024];
        size_t count = 0;
        
        // loop through until all conditions we're searching for are met
        FileInputStream fins = file.read(null);
        for (;;) {
            size_t bytes_read = fins.read(buffer, buffer.length, null);
            if (bytes_read <= 0)
                break;
            
            count += bytes_read;
            
            if (calc_md5)
                md5_checksum.update(buffer, bytes_read);
            
            // keep parsing the image until the size is discovered
            if (!size_ready || !area_prepared)
                pixbuf_loader.write(buffer, bytes_read);
            
            // if not searching for anything else, exit
            if (!calc_md5 && size_ready && area_prepared)
                break;
        }
        
        // PixbufLoader throws an error if you close it with an incomplete image, so trap this
        try {
            pixbuf_loader.close();
        } catch (Error err) {
        }
        
        if (fins != null)
            fins.close(null);
        
        if (calc_md5)
            detected.md5 = md5_checksum.get_string();
        
        return detected;
    }
    
    private void on_size_prepared(Gdk.PixbufLoader loader, int width, int height) {
        detected.image_dim = Dimensions(width, height);
        size_ready = true;
    }
    
    private void on_area_prepared(Gdk.PixbufLoader pixbuf_loader) {
        Gdk.Pixbuf? pixbuf = pixbuf_loader.get_pixbuf();
        if (pixbuf == null)
            return;
        
        detected.colorspace = pixbuf.get_colorspace();
        detected.channels = pixbuf.get_n_channels();
        detected.bits_per_channel = pixbuf.get_bits_per_sample();
        
        unowned Gdk.PixbufFormat format = pixbuf_loader.get_format();
        detected.format_name = format.get_name();
        
        switch (detected.format_name) {
            case "jpeg":
                detected.file_format = PhotoFileFormat.JFIF;
            break;

            case "png":
                detected.file_format = PhotoFileFormat.PNG;
            break;
            
            default:
                detected.file_format = PhotoFileFormat.UNKNOWN;
            break;
        }
        
        area_prepared = true;
    }
}

