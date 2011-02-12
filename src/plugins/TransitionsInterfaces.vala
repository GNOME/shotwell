/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Transitions are used in Shotwell for interstitial effects in slideshow mode.  They may
// also be used elsewhere in future releases.

namespace Spit.Transitions {

public const int CURRENT_INTERFACE = 0;

// Direction indicates what direction (animated motion) the Effect should simulate the images are
// moving, if appropriate.  The direction indicates from what side or corner of the screen the
// new image should come in from.  Thus, a LEFT slide means the current image exits via the
// left-hand edge of the screen and the new image moves into place from the right-hand edge.
//
// UP, DOWN, and diagonals may be added at some point.
public enum Direction {
    LEFT = 0,
    RIGHT = 1,
    
    // convenience definitions (for LTR readers)
    FORWARD = LEFT,
    BACKWARD = RIGHT
}

// Visuals contains the pertinent drawing information for the transition that must occur.  This is
// supplied to Effect at the start of the transition and during each call to paint to the screen.
//
// Note that if starting from a blank screen, from_pixbuf will be null and from_pos will be
// zeroed.  The transition should be considered to start from a blank screen of the supplied
// background color.
//
// Also note that if transitioning to a blank screen, to_pixbuf will be null and to_pos will be
// zeroes.  Like the prior case, the transition should move toward a blank screen of the background
// color.
public class Visuals : Object {
    public Gdk.Pixbuf? from_pixbuf { get; private set; }
    public Gdk.Rectangle from_pos { get; private set; }
    public Gdk.Pixbuf? to_pixbuf { get; private set; }
    public Gdk.Rectangle to_pos { get; private set; }
    public Gdk.Color bg_color { get; private set; }
    
    public Visuals(Gdk.Pixbuf? from_pixbuf, Gdk.Rectangle from_pos, Gdk.Pixbuf? to_pixbuf,
        Gdk.Rectangle to_pos, Gdk.Color bg_color) {
        this.from_pixbuf = from_pixbuf;
        this.from_pos = from_pos;
        this.to_pixbuf = to_pixbuf;
        this.to_pos = to_pos;
        this.bg_color = bg_color;
    }
    
    //
    // For future expansion.
    //
    public virtual void reserved0() {}
    public virtual void reserved1() {}
    public virtual void reserved2() {}
    public virtual void reserved3() {}
    public virtual void reserved4() {}
    public virtual void reserved5() {}
    public virtual void reserved6() {}
    public virtual void reserved7() {}
}

// Motion contains all the pertinent information regarding the animation of the transition.  Some
// of this information may not apply to a transition effect (such as Direction for a fade effect).
public class Motion : Object {
    public Direction direction { get; private set; }
    public int fps { get; private set; }
    public int duration_msec { get; private set; }
    
    public int total_frames { 
        get {
            return (int) ((double) fps * ((double) duration_msec / 1000.0));
        }
    }
    
    public int tick_msec {
        get {
            return (int) (1000.0 / (double) fps);
        }
    }
    
    public Motion(Direction direction, int fps, int duration_msec) {
        this.direction = direction;
        this.fps = fps;
        this.duration_msec = duration_msec;
    }
    
    public double get_alpha(int frame_number) {
        return (double) frame_number / (double) total_frames;
    }
    
    //
    // For future expansion.
    //
    public virtual void reserved0() {}
    public virtual void reserved1() {}
    public virtual void reserved2() {}
    public virtual void reserved3() {}
    public virtual void reserved4() {}
    public virtual void reserved5() {}
    public virtual void reserved6() {}
    public virtual void reserved7() {}
}

// A Descriptor offers information about an Effect as well as a factory method so instances may
// be created for use.
public interface Descriptor : Object, Spit.Pluggable {
    // Returns an instance of the Effect this descriptor represents.
    public abstract Effect create(Spit.HostInterface host);
    
    //
    // For future expansion.
    //
    public virtual void reserved0() {}
    public virtual void reserved1() {}
    public virtual void reserved2() {}
    public virtual void reserved3() {}
    public virtual void reserved4() {}
    public virtual void reserved5() {}
    public virtual void reserved6() {}
    public virtual void reserved7() {}
}

// An Effect represents a particular interstitial effect that may be used when switching
// the display from one image to another.  It must hold state so that it knows what it should be
// drawn at any call to paint() (which is called regularly during a transition).
//
// If the Effect uses background threads for its work, it should use the appropriate primitives
// for critical sections.  All calls to this interface will be from the context of the main UI
// thread.
//
// If the Details object needs to be held by the Effect, its reference to it should be dropped at
// the end of the cycle (or shortly thereafter).
//
// An instantiation may be reused and should be prepared for restarts.
public interface Effect : Object {
    // Returns frames per second information for this effect.  Return 0 for desired_fps if no
    // transition is to occur (instantaneous or null transition). Return 0 for min_fps if any fps
    // is acceptable.
    //
    // The Effect will be cancelled if the min_fps is not met.
    public abstract void get_fps(out int desired_fps, out int min_fps);
    
    // Called when the effect is starting.  All state should be reset.  The frame number, which is
    // not supplied, is one.
    public abstract void start(Visuals visuals, Motion motion);
    
    // Return true if the Effect needs the background cleared prior to calling paint().
    public abstract bool needs_clear_background();
    
    // Called when the effect needs to paint (i.e. an expose event has occurred).  This call
    // should *not* advance the state of the effect (i.e. it may be called more than once for the
    // same frame).  frame_number is one-based.
    public abstract void paint(Visuals visuals, Motion motion, Cairo.Context ctx, int width,
        int height, int frame_number);
    
    // Called to notify the effect that the state of the transition should advance to the specified
    // frame number.  NOTE: There is no guarantee frame numbers will be consecutive between calls
    // to next, especially if the transition clock is attempting to catch up.
    //
    // frame_number is one-based.
    public abstract void advance(Visuals visuals, Motion motion, int frame_number);
    
    // The Effect should stop the transition.  It only needs to reset state if start() is called
    // again.
    public abstract void cancel();
    
    //
    // For future expansion.
    //
    public virtual void reserved0() {}
    public virtual void reserved1() {}
    public virtual void reserved2() {}
    public virtual void reserved3() {}
    public virtual void reserved4() {}
    public virtual void reserved5() {}
    public virtual void reserved6() {}
    public virtual void reserved7() {}
}

}

