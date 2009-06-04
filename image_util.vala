
Gdk.Color parse_color(string spec) {
    return fetch_color(spec);
}

Gdk.Color fetch_color(string spec, Gdk.Drawable? drawable = null) {
    Gdk.Color color;
    if (!Gdk.Color.parse(spec, out color))
        error("Can't parse color %s", spec);
    
    if (drawable == null) {
        Gtk.Window app = AppWindow.get_instance();
        if (app != null)
            drawable = app.window;
    }
    
    if (drawable != null) {
        Gdk.Colormap colormap = drawable.get_colormap();
        if (colormap == null)
            error("Can't get colormap for drawable");
        
        if (!colormap.alloc_color(color, false, true))
            error("Can't allocate color %s", spec);
    }
    
    return color;
}

public enum Rotation {
    CLOCKWISE,
    COUNTERCLOCKWISE,
    MIRROR,
    UPSIDE_DOWN;
    
    public Gdk.Pixbuf perform(Gdk.Pixbuf pixbuf) {
        switch (this) {
            case CLOCKWISE:
                return pixbuf.rotate_simple(Gdk.PixbufRotation.CLOCKWISE);
            
            case COUNTERCLOCKWISE:
                return pixbuf.rotate_simple(Gdk.PixbufRotation.COUNTERCLOCKWISE);
            
            case MIRROR:
                return pixbuf.flip(true);
            
            case UPSIDE_DOWN:
                return pixbuf.flip(false);
            
            default:
                error("Unknown rotation: %d", (int) this);
                
                return pixbuf;
        }
    }
}
    
Gdk.Pixbuf scale_pixbuf(Gdk.Pixbuf pixbuf, int scale, Gdk.InterpType interp) {
    Dimensions original = Dimensions(pixbuf.get_width(), pixbuf.get_height());
    Dimensions scaled = original.get_scaled(scale);
    if ((original.width == scaled.width) && (original.height == scaled.height))
        return pixbuf;

    return pixbuf.scale_simple(scaled.width, scaled.height, interp);
}

bool coord_in_rectangle(int x, int y, Gdk.Rectangle rect) {
    return (x >= rect.x && x < (rect.x + rect.width) && y >= rect.y && y <= (rect.y + rect.height));
}

namespace Jpeg {
    public static const uint8 MARKER_PREFIX = 0xFF;
    
    public enum Marker {
        SOI = 0xD8,
        EOI = 0xD9,
        
        APP0 = 0xE0,
        APP1 = 0xE1;
        
        public uint8 get_byte() {
            return (uint8) this;
        }
    }
    
    public enum Quality {
        LOW = 50,
        MEDIUM = 75,
        HIGH = 90,
        MAXIMUM = 100;
        
        public int get_pct() {
            return (int) this;
        }
        
        public string get_pct_text() {
            return "%d".printf((int) this);
        }
        
        public string? to_string() {
            switch (this) {
                case LOW:
                    return "Low (%d%%)".printf((int) this);
                
                case MEDIUM:
                    return "Medium (%d%%)".printf((int) this);
                
                case HIGH:
                    return "High (%d%%)".printf((int) this);
                    
                case MAXIMUM:
                    return "Maximum (%d%%)".printf((int) this);
            }
            
            warn_if_reached();
            
            return null;
        }
    }
    
    public bool is_jpeg(File file) throws Error {
        FileInputStream fins = file.read(null);
        
        Marker marker;
        int segment_length = read_marker(fins, out marker);
        
        // for now, merely checking for SOI
        return (marker == Marker.SOI) && (segment_length == 0);
    }

    private int read_marker(FileInputStream fins, out Jpeg.Marker marker) throws Error {
        uint8 byte = 0;
        uint16 length = 0;
        size_t bytes_read;

        fins.read_all(&byte, 1, out bytes_read, null);
        if (byte != Jpeg.MARKER_PREFIX)
            return -1;
        
        fins.read_all(&byte, 1, out bytes_read, null);
        marker = (Jpeg.Marker) byte;
        if ((marker == Jpeg.Marker.SOI) || (marker == Jpeg.Marker.EOI)) {
            // no length
            return 0;
        }
        
        fins.read_all(&length, 2, out bytes_read, null);
        length = uint16.from_big_endian(length);
        if (length < 2) {
            debug("Invalid length %Xh at ofs %llXh", length, fins.tell() - 2);
            
            return -1;
        }
        
        // account for two length bytes already read
        return length - 2;
    }
    
    // this writes the marker and a length (if positive)
    private void write_marker(FileOutputStream fouts, Jpeg.Marker marker, int length) throws Error {
        // this is required to compile
        uint8 prefix = Jpeg.MARKER_PREFIX;
        uint8 byte = marker.get_byte();
        
        size_t written;
        fouts.write_all(&prefix, 1, out written, null);
        fouts.write_all(&byte, 1, out written, null);

        if (length <= 0)
            return;

        // +2 to account for length bytes
        length += 2;
        
        uint16 host = (uint16) length;
        uint16 motorola = (uint16) host.to_big_endian();

        fouts.write_all(&motorola, 2, out written, null);
    }
}

