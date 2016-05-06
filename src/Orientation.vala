/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public enum Orientation {
    MIN = 1,
    TOP_LEFT = 1,
    TOP_RIGHT = 2,
    BOTTOM_RIGHT = 3,
    BOTTOM_LEFT = 4,
    LEFT_TOP = 5,
    RIGHT_TOP = 6,
    RIGHT_BOTTOM = 7,
    LEFT_BOTTOM = 8,
    MAX = 8;

    public string to_string() {
        switch (this) {
            case TOP_LEFT:
                return "top-left";
                
            case TOP_RIGHT:
                return "top-right";
                
            case BOTTOM_RIGHT:
                return "bottom-right";
                
            case BOTTOM_LEFT:
                return "bottom-left";
                
            case LEFT_TOP:
                return "left-top";
                
            case RIGHT_TOP:
                return "right-top";
                
            case RIGHT_BOTTOM:
                return "right-bottom";
                
            case LEFT_BOTTOM:
                return "left-bottom";
                
            default:
                return "unknown orientation %d".printf((int) this);
        }
    }
    
    public Orientation rotate_clockwise() {
        switch (this) {
            case TOP_LEFT:
                return RIGHT_TOP;
                
            case TOP_RIGHT:
                return RIGHT_BOTTOM;
                
            case BOTTOM_RIGHT:
                return LEFT_BOTTOM;
                
            case BOTTOM_LEFT:
                return LEFT_TOP;
                
            case LEFT_TOP:
                return TOP_RIGHT;
                
            case RIGHT_TOP:
                return BOTTOM_RIGHT;
                
            case RIGHT_BOTTOM:
                return BOTTOM_LEFT;
                
            case LEFT_BOTTOM:
                return TOP_LEFT;
                
            default:
                error("rotate_clockwise: %d", this);
        }
    }
    
    public Orientation rotate_counterclockwise() {
        switch (this) {
            case TOP_LEFT:
                return LEFT_BOTTOM;
                
            case TOP_RIGHT:
                return LEFT_TOP;
                
            case BOTTOM_RIGHT:
                return RIGHT_TOP;
                
            case BOTTOM_LEFT:
                return RIGHT_BOTTOM;
                
            case LEFT_TOP:
                return BOTTOM_LEFT;
                
            case RIGHT_TOP:
                return TOP_LEFT;
                
            case RIGHT_BOTTOM:
                return TOP_RIGHT;
                
            case LEFT_BOTTOM:
                return BOTTOM_RIGHT;
                
            default:
                error("rotate_counterclockwise: %d", this);
        }
    }
    
    public Orientation flip_top_to_bottom() {
        switch (this) {
            case TOP_LEFT:
                return BOTTOM_LEFT;
                
            case TOP_RIGHT:
                return BOTTOM_RIGHT;
                
            case BOTTOM_RIGHT:
                return TOP_RIGHT;
                
            case BOTTOM_LEFT:
                return TOP_LEFT;
                
            case LEFT_TOP:
                return LEFT_BOTTOM;
                
            case RIGHT_TOP:
                return RIGHT_BOTTOM;
                
            case RIGHT_BOTTOM:
                return RIGHT_TOP;
                
            case LEFT_BOTTOM:
                return LEFT_TOP;
                
            default:
                error("flip_top_to_bottom: %d", this);
        }
    }
    
    public Orientation flip_left_to_right() {
        switch (this) {
            case TOP_LEFT:
                return TOP_RIGHT;
                
            case TOP_RIGHT:
                return TOP_LEFT;
                
            case BOTTOM_RIGHT:
                return BOTTOM_LEFT;
                
            case BOTTOM_LEFT:
                return BOTTOM_RIGHT;
                
            case LEFT_TOP:
                return RIGHT_TOP;
                
            case RIGHT_TOP:
                return LEFT_TOP;
                
            case RIGHT_BOTTOM:
                return LEFT_BOTTOM;
                
            case LEFT_BOTTOM:
                return RIGHT_BOTTOM;
                
            default:
                error("flip_left_to_right: %d", this);
        }
    }
    
    public Orientation perform(Rotation rotation) {
        switch (rotation) {
            case Rotation.CLOCKWISE:
                return rotate_clockwise();
            
            case Rotation.COUNTERCLOCKWISE:
                return rotate_counterclockwise();
            
            case Rotation.MIRROR:
                return flip_left_to_right();
            
            case Rotation.UPSIDE_DOWN:
                return flip_top_to_bottom();
            
            default:
                error("perform: %d", (int) rotation);
        }
    }
    
    public Rotation[] to_rotations() {
        switch (this) {
            case TOP_LEFT:
                // identity orientation
                return { };
            
            case TOP_RIGHT:
                return { Rotation.MIRROR };
            
            case BOTTOM_RIGHT:
                return { Rotation.UPSIDE_DOWN };
            
            case BOTTOM_LEFT:
                // flip top-to-bottom
                return { Rotation.MIRROR, Rotation.UPSIDE_DOWN };
            
            case LEFT_TOP:
                return { Rotation.COUNTERCLOCKWISE, Rotation.UPSIDE_DOWN };
            
            case RIGHT_TOP:
                return { Rotation.CLOCKWISE };
            
            case RIGHT_BOTTOM:
                return { Rotation.CLOCKWISE, Rotation.UPSIDE_DOWN };
            
            case LEFT_BOTTOM:
                return { Rotation.COUNTERCLOCKWISE };
            
            default:
                error("to_rotations: %d", this);
        }
    }
    
    public Dimensions rotate_dimensions(Dimensions dim) {
        switch (this) {
            case Orientation.TOP_LEFT:
            case Orientation.TOP_RIGHT:
            case Orientation.BOTTOM_RIGHT:
            case Orientation.BOTTOM_LEFT:
                // fine just as it is
                return dim;

            case Orientation.LEFT_TOP:
            case Orientation.RIGHT_TOP:
            case Orientation.RIGHT_BOTTOM:
            case Orientation.LEFT_BOTTOM:
                // swap
                return Dimensions(dim.height, dim.width);

            default:
                error("rotate_dimensions: %d", this);
        }
    }
    
    public Dimensions derotate_dimensions(Dimensions dim) {
        return rotate_dimensions(dim);
    }

    public Gdk.Pixbuf rotate_pixbuf(Gdk.Pixbuf pixbuf) {
        Gdk.Pixbuf rotated;
        switch (this) {
            case TOP_LEFT:
                // fine just as it is
                rotated = pixbuf;
            break;
            
            case TOP_RIGHT:
                // mirror
                rotated = pixbuf.flip(true);
            break;
            
            case BOTTOM_RIGHT:
                rotated = pixbuf.rotate_simple(Gdk.PixbufRotation.UPSIDEDOWN);
            break;
            
            case BOTTOM_LEFT:
                // flip top-to-bottom
                rotated = pixbuf.flip(false);
            break;
            
            case LEFT_TOP:
                rotated = pixbuf.rotate_simple(Gdk.PixbufRotation.COUNTERCLOCKWISE).flip(false);
            break;
            
            case RIGHT_TOP:
                rotated = pixbuf.rotate_simple(Gdk.PixbufRotation.CLOCKWISE);
            break;
            
            case RIGHT_BOTTOM:
                rotated = pixbuf.rotate_simple(Gdk.PixbufRotation.CLOCKWISE).flip(false);
            break;
            
            case LEFT_BOTTOM:
                rotated = pixbuf.rotate_simple(Gdk.PixbufRotation.COUNTERCLOCKWISE);
            break;
            
            default:
                error("rotate_pixbuf: %d", this);
        }
        
        return rotated;
    }
    
    // space is the unrotated dimensions the point is rotating with
    public Gdk.Point rotate_point(Dimensions space, Gdk.Point point) {
        assert(space.has_area());
        assert(point.x >= 0);
        assert(point.x < space.width);
        assert(point.y >= 0);
        assert(point.y < space.height);
        
        Gdk.Point rotated = Gdk.Point();
        
        switch (this) {
            case TOP_LEFT:
                // fine as-is
                rotated = point;
            break;
                
            case TOP_RIGHT:
                // mirror
                rotated.x = space.width - point.x - 1;
                rotated.y = point.y;
            break;
                
            case BOTTOM_RIGHT:
                // rotate 180
                rotated.x = space.width - point.x - 1;
                rotated.y = space.height - point.y - 1;
            break;
                
            case BOTTOM_LEFT:
                // flip top-to-bottom
                rotated.x = point.x;
                rotated.y = space.height - point.y - 1;
            break;
                
            case LEFT_TOP:
                // rotate 90, flip top-to-bottom
                rotated.x = point.y;
                rotated.y = point.x;
            break;
                
            case RIGHT_TOP:
                // rotate 270
                rotated.x = space.height - point.y - 1;
                rotated.y = point.x;
            break;
                
            case RIGHT_BOTTOM:
                // rotate 270, flip top-to-bottom
                rotated.x = space.height - point.y - 1;
                rotated.y = space.width - point.x - 1;
            break;
                
            case LEFT_BOTTOM:
                // rotate 90
                rotated.x = point.y;
                rotated.y = space.width - point.x - 1;
            break;
                
            default:
                error("rotate_point: %d", this);
        }
        
        return rotated;
    }
    
    // space is the unrotated dimensions the point is return to
    public Gdk.Point derotate_point(Dimensions space, Gdk.Point point) {
        assert(space.has_area());
        
        Gdk.Point derotated = Gdk.Point();
        
        switch (this) {
            case TOP_LEFT:
                // fine as-is
                derotated = point;
            break;
                
            case TOP_RIGHT:
                // mirror
                derotated.x = space.width - point.x - 1;
                derotated.y = point.y;
            break;
                
            case BOTTOM_RIGHT:
                // rotate 180
                derotated.x = space.width - point.x - 1;
                derotated.y = space.height - point.y - 1;
            break;
                
            case BOTTOM_LEFT:
                // flip top-to-bottom
                derotated.x = point.x;
                derotated.y = space.height - point.y - 1;
            break;
                
            case LEFT_TOP:
                // rotate 90, flip top-to-bottom
                derotated.x = point.y;
                derotated.y = point.x;
            break;
                
            case RIGHT_TOP:
                // rotate 270
                derotated.x = point.y;
                derotated.y = space.height - point.x - 1;
            break;
                
            case RIGHT_BOTTOM:
                // rotate 270, flip top-to-bottom
                derotated.x = space.width - point.y - 1;
                derotated.y = space.height - point.x - 1;
            break;
                
            case LEFT_BOTTOM:
                // rotate 90
                derotated.x = space.width - point.y - 1;
                derotated.y = point.x;
            break;
                
            default:
                error("rotate_point: %d", this);
        }
        
        return derotated;
    }
    
    // space is the unrotated dimensions the point is rotating with
    public Box rotate_box(Dimensions space, Box box) {
        Gdk.Point top_left, bottom_right;
        box.get_points(out top_left, out bottom_right);
        
        top_left.x = top_left.x.clamp(0, space.width - 1);
        top_left.y = top_left.y.clamp(0, space.height - 1);

        bottom_right.x = bottom_right.x.clamp(0, space.width - 1);
        bottom_right.y = bottom_right.y.clamp(0, space.height - 1);
        
        top_left = rotate_point(space, top_left);
        bottom_right = rotate_point(space, bottom_right);
        
        return Box.from_points(top_left, bottom_right);
    }
    
    // space is the unrotated dimensions the point is return to
    public Box derotate_box(Dimensions space, Box box) {
        Gdk.Point top_left, bottom_right;
        box.get_points(out top_left, out bottom_right);
        
        top_left = derotate_point(space, top_left);
        bottom_right = derotate_point(space, bottom_right);
        
        return Box.from_points(top_left, bottom_right);
    }
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
        }
    }
    
    public Rotation opposite() {
        switch (this) {
            case CLOCKWISE:
                return COUNTERCLOCKWISE;
            
            case COUNTERCLOCKWISE:
                return CLOCKWISE;
            
            case MIRROR:
            case UPSIDE_DOWN:
                return this;
            
            default:
                error("Unknown rotation: %d", (int) this);
        }
    }
}

