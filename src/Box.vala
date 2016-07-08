/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

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

public enum BoxComplements {
    NONE,
    VERTICAL,
    HORIZONTAL,
    BOTH;
    
    public static BoxComplements derive(bool horizontal_complement, bool vertical_complement) {
        if (horizontal_complement && vertical_complement)
            return BOTH;
        else if(horizontal_complement)
            return HORIZONTAL;
        else if (vertical_complement)
            return VERTICAL;

        return NONE;
    }
}

public struct Box {
    public const int HAND_GRENADES = 12;
    
    public int left;
    public int top;
    public int right;
    public int bottom;

    public Box(int left = 0, int top = 0, int right = 0, int bottom = 0) {
        // Sanity check on top left vertex.
        left = left.clamp(0, int.MAX);
        top = top.clamp(0, int.MAX);

        // Sanity check on dimensions - force
        // box to be at least 1 px by 1 px.
        if (right <= left)
            right = left + 1;

        if (bottom <= top)
            bottom = top + 1;

        this.left = left;
        this.top = top;
        this.right = right;
        this.bottom = bottom;
    }
    
    public static Box from_rectangle(Gdk.Rectangle rect) {
        return Box(rect.x, rect.y, rect.x + rect.width - 1, rect.y + rect.height - 1);
    }
    
    public static Box from_allocation(Gtk.Allocation alloc) {
        return Box(alloc.x, alloc.y, alloc.x + alloc.width - 1, alloc.y + alloc.height - 1);
    }
    
    // This ensures a proper box is built from the points supplied, no matter the relationship
    // between the two points
    public static Box from_points(Gdk.Point corner1, Gdk.Point corner2) {
        return Box(int.min(corner1.x, corner2.x), int.min(corner1.y, corner2.y),
            int.max(corner1.x, corner2.x), int.max(corner1.y, corner2.y));
    }
    
    public static Box from_center(Gdk.Point center, int width, int height) {
        return Box(center.x - (width / 2), center.y - (height / 2),
                   center.x + (width / 2), center.y + (height / 2));
    }
    
    public int get_width() {
        assert(right >= left);
        
        return right - left + 1;
    }
    
    public int get_height() {
        assert(bottom >= top);
        
        return bottom - top + 1;
    }
    
    public bool is_valid() {
        return (left >= 0) && (top >= 0) && (right >= left) && (bottom >= top);
    }
    
    public bool equals(Box box) {
        return (left == box.left && top == box.top && right == box.right && bottom == box.bottom);
    }
    
    // Adjust width, preserving the box's center.
    public void adjust_width(int width) {
        int center_x = (left + right) / 2;
        left = center_x - (width / 2);
        right = center_x + (width / 2);
    }

    // Adjust height, preserving the box's center.
    public void adjust_height(int height) {
        int center_y = (top + bottom) / 2;
        top = center_y - (height / 2);
        bottom = center_y + (height / 2);
    }
    
    public Box get_scaled(Dimensions scaled) {
        double x_scale, y_scale;
        get_dimensions().get_scale_ratios(scaled, out x_scale, out y_scale);
        
        int l = (int) Math.round((double) left * x_scale);
        int t = (int) Math.round((double) top * y_scale);
        
        // fix-up to match the scaled dimensions
        int r = l + scaled.width - 1;
        int b = t + scaled.height - 1;

        Box box = Box(l, t, r, b);
        assert(box.get_width() == scaled.width || box.get_height() == scaled.height);
        
        return box;
    }
    
    public Box get_scaled_similar(Dimensions original, Dimensions scaled) {
        double x_scale, y_scale;
        original.get_scale_ratios(scaled, out x_scale, out y_scale);
        
        int l = (int) Math.round((double) left * x_scale);
        int t = (int) Math.round((double) top * y_scale);
        int r = (int) Math.round((double) right * x_scale);
        int b = (int) Math.round((double) bottom * y_scale);

        // catch rounding errors
        if (r >= scaled.width)
            r = scaled.width - 1;
        
        if (b >= scaled.height)
            b = scaled.height - 1;
        
        return Box(l, t, r, b);
    }
    
    public Box get_offset(int xofs, int yofs) {
        return Box(left + xofs, top + yofs, right + xofs, bottom + yofs);
    }
    
    public Dimensions get_dimensions() {
        return Dimensions(get_width(), get_height());
    }
    
    public void get_points(out Gdk.Point top_left, out Gdk.Point bottom_right) {
        top_left = { left, top };
        bottom_right = { right, bottom };
    }
    
    public Gdk.Rectangle get_rectangle() {
        Gdk.Rectangle rect = Gdk.Rectangle();
        rect.x = left;
        rect.y = top;
        rect.width = get_width();
        rect.height = get_height();
        
        return rect;
    }
    
    public Gdk.Point get_center() {
        return { (left + right) / 2, (top + bottom) / 2 };
    }
    
    public Box rotate_clockwise(Dimensions space) {
        int l = space.width - bottom - 1;
        int t = left;
        int r = space.width - top - 1;
        int b = right;
        
        return Box(l, t, r, b);
    }
    
    public Box rotate_counterclockwise(Dimensions space) {
        int l = top;
        int t = space.height - right - 1;
        int r = bottom;
        int b = space.height - left - 1;
        
        return Box(l, t, r, b);
    }
    
    public Box flip_left_to_right(Dimensions space) {
        int l = space.width - right - 1;
        int r = space.width - left - 1;
        
        return Box(l, top, r, bottom);
    }
    
    public Box flip_top_to_bottom(Dimensions space) {
        int t = space.height - bottom - 1;
        int b = space.height - top - 1;
        
        return Box(left, t, right, b);
    }
    
    public bool intersects(Box compare) {
        int left_intersect = int.max(left, compare.left);
        int top_intersect = int.max(top, compare.top);
        int right_intersect = int.min(right, compare.right);
        int bottom_intersect = int.min(bottom, compare.bottom);
        
        return (right_intersect >= left_intersect && bottom_intersect >= top_intersect);
    }
    
    public Box get_reduced(int amount) {
        return Box(left + amount, top + amount, right - amount, bottom - amount);
    }
    
    public Box get_expanded(int amount) {
        return Box(left - amount, top - amount, right + amount, bottom + amount);
    }
    
    public bool contains(Gdk.Point point) {
        return point.x >= left && point.x <= right && point.y >= top && point.y <= bottom;
    }
    
    // This specialized method is only concerned with resized comparisons between two Boxes, 
    // of which one is altered in up to two dimensions: (top or bottom) and/or (left or right).
    // There may be overlap between the two returned Boxes.
    public BoxComplements resized_complements(Box resized, out Box horizontal, out bool horizontal_enlarged,
        out Box vertical, out bool vertical_enlarged) {
        
        bool horizontal_complement = true;
        if (resized.top < top) {
            // enlarged from top
            horizontal = Box(resized.left, resized.top, resized.right, top);
            horizontal_enlarged = true;
        } else if (resized.top > top) {
            // shrunk from top
            horizontal = Box(left, top, right, resized.top);
            horizontal_enlarged = false;
        } else if (resized.bottom < bottom) {
            // shrunk from bottom
            horizontal = Box(left, resized.bottom, right, bottom);
            horizontal_enlarged = false;
        } else if (resized.bottom > bottom) {
            // enlarged from bottom
            horizontal = Box(resized.left, bottom, resized.right, resized.bottom);
            horizontal_enlarged = true;
        } else {
            horizontal = Box();
            horizontal_enlarged = false;
            horizontal_complement = false;
        }
        
        bool vertical_complement = true;
        if (resized.left < left) {
            // enlarged left
            vertical = Box(resized.left, resized.top, left, resized.bottom);
            vertical_enlarged = true;
        } else if (resized.left > left) {
            // shrunk left
            vertical = Box(left, top, resized.left, bottom);
            vertical_enlarged = false;
        } else if (resized.right < right) {
            // shrunk right
            vertical = Box(resized.right, top, right, bottom);
            vertical_enlarged = false;
        } else if (resized.right > right) {
            // enlarged right
            vertical = Box(right, resized.top, resized.right, resized.bottom);
            vertical_enlarged = true;
        } else {
            vertical = Box();
            vertical_enlarged = false;
            vertical_complement = false;
        }
        
        return BoxComplements.derive(horizontal_complement, vertical_complement);
    }
    
    // This specialized method is only concerned with the complements of identical Boxes in two
    // different, spatial locations.  There may be overlap between the four returned Boxes.  However,
    // no portion of any of the four boxes will be outside the scope of the two compared boxes.
    public BoxComplements shifted_complements(Box shifted, out Box horizontal_this, 
        out Box vertical_this, out Box horizontal_shifted, out Box vertical_shifted) {
        assert(get_width() == shifted.get_width());
        assert(get_height() == shifted.get_height());
        
        bool horizontal_complement = true;
        if (shifted.top < top && shifted.bottom > top) {
            // shifted up
            horizontal_this = Box(left, shifted.bottom, right, bottom);
            horizontal_shifted = Box(shifted.left, shifted.top, shifted.right, top);
        } else if (shifted.top > top && shifted.top < bottom) {
            // shifted down
            horizontal_this = Box(left, top, right, shifted.top);
            horizontal_shifted = Box(shifted.left, bottom, shifted.right, shifted.bottom);
        } else {
            // no vertical shift
            horizontal_this = Box();
            horizontal_shifted = Box();
            horizontal_complement = false;
        }
        
        bool vertical_complement = true;
        if (shifted.left < left && shifted.right > left) {
            // shifted left
            vertical_this = Box(shifted.right, top, right, bottom);
            vertical_shifted = Box(shifted.left, shifted.top, left, shifted.bottom);
        } else if (shifted.left > left && shifted.left < right) {
            // shifted right
            vertical_this = Box(left, top, shifted.left, bottom);
            vertical_shifted = Box(right, shifted.top, shifted.right, shifted.bottom);
        } else {
            // no horizontal shift
            vertical_this = Box();
            vertical_shifted = Box();
            vertical_complement = false;
        }
        
        return BoxComplements.derive(horizontal_complement, vertical_complement);
    }
    
    public Box rubber_band(Gdk.Point point) {
        assert(point.x >= 0);
        assert(point.y >= 0);
        
        int t = int.min(top, point.y);
        int b = int.max(bottom, point.y);
        int l = int.min(left, point.x);
        int r = int.max(right, point.x);

        return Box(l, t, r, b);
    }
    
    public string to_string() {
        return "%d,%d %d,%d (%s)".printf(left, top, right, bottom, get_dimensions().to_string());
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
    
    public BoxLocation approx_location(int x, int y) {
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

