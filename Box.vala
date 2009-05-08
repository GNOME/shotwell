
public enum BoxLocation {
    OUTSIDE,
    INSIDE,
    TOP_SIDE,
    LEFT_SIDE,
    RIGHT_SIDE,
    BOTTOM_SIDE,
    TOP_LEFT,
    BOTTOM_LEFT,
    TOP_RIGHT,
    BOTTOM_RIGHT
}

public struct Box {
    public static const int HAND_GRENADES = 6;
    
    public int left;
    public int top;
    public int right;
    public int bottom;

    public Box(int left, int top, int right, int bottom) {
        assert(left >= 0);
        assert(top >= 0);
        assert(right >= left);
        assert(bottom >= top);
        
        this.left = left;
        this.top = top;
        this.right = right;
        this.bottom = bottom;
    }
    
    public static Box from_rectangle(Gdk.Rectangle rect) {
        return Box(rect.x, rect.y, rect.x + rect.width, rect.y + rect.height);
    }
    
    public int get_width() {
        assert(right >= left);
        
        return right - left;
    }
    
    public int get_height() {
        assert(bottom >= top);
        
        return bottom - top;
    }
    
    public bool is_valid() {
        return (left >= 0) && (top >= 0) && (right >= left) && (bottom >= top);
    }
    
    public Box get_scaled(Dimensions orig, Dimensions scaled) {
        double x_scale = (double) scaled.width / (double) orig.width;
        double y_scale = (double) scaled.height / (double) orig.height;
    
        Box box = Box((int) (left * x_scale), (int) (top * y_scale), (int) (right * x_scale),
            (int) (bottom * y_scale));
        
        return box;
    }
    
    public Box get_offset(int xofs, int yofs) {
        return Box(left + xofs, top + yofs, right + xofs, bottom + yofs);
    }
    
    public Dimensions get_dimensions() {
        return Dimensions(get_width(), get_height());
    }
    
    public Gdk.Rectangle get_rectangle() {
        Gdk.Rectangle rect = Gdk.Rectangle();
        rect.x = left;
        rect.y = top;
        rect.width = get_width();
        rect.height = get_height();
        
        return rect;
    }
    
    public string to_string() {
        return "%d,%d %d,%d".printf(left, top, right, bottom);
    }

    private static bool in_zone(double pos, int zone) {
        int top_zone = zone - HAND_GRENADES;
        int bottom_zone = zone + HAND_GRENADES;
        
        return in_between(pos, top_zone, bottom_zone);
    }
    
    private static bool in_between(double pos, int top, int bottom) {
        int ipos = (int) pos;
        
        return (ipos > top) && (ipos < bottom);
    }
    
    private static bool near_in_between(double pos, int top, int bottom) {
        int ipos = (int) pos;
        int top_zone = top - HAND_GRENADES;
        int bottom_zone = bottom + HAND_GRENADES;
        
        return (ipos > top_zone) && (ipos < bottom_zone);
    }
    
    public BoxLocation location(int x, int y) {
        bool near_width = near_in_between(x, left, right);
        bool near_height = near_in_between(y, top, bottom);
        
        if (in_zone(x, left) && near_height) {
            if (in_zone(y, top)) {
                return BoxLocation.TOP_LEFT;
            } else if (in_zone(y, bottom)) {
                return BoxLocation.BOTTOM_LEFT;
            } else {
                return BoxLocation.LEFT_SIDE;
            }
        } else if (in_zone(x, right) && near_height) {
            if (in_zone(y, top)) {
                return BoxLocation.TOP_RIGHT;
            } else if (in_zone(y, bottom)) {
                return BoxLocation.BOTTOM_RIGHT;
            } else {
                return BoxLocation.RIGHT_SIDE;
            }
        } else if (in_zone(y, top) && near_width) {
            // if left or right was in zone, already caught top left & top right
            return BoxLocation.TOP_SIDE;
        } else if (in_zone(y, bottom) && near_width) {
            // if left or right was in zone, already caught bottom left & bottom right
            return BoxLocation.BOTTOM_SIDE;
        } else if (in_between(x, left, right) && in_between(y, top, bottom)) {
            return BoxLocation.INSIDE;
        } else {
            return BoxLocation.OUTSIDE;
        }
    }
}

