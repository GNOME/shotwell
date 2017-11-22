/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Transitions are used in Shotwell for interstitial effects in slideshow mode. They may
 * also be used elsewhere in future releases.
 *
 * Plugin writers should start by implementing a {@link Descriptor} which in turn Shotwell uses
 * to instantiate an {@link Effect}.
 */
namespace Spit.Transitions {

/**
 * The current version of the Transitions plugin interface.
 */
public const int CURRENT_INTERFACE = 0;

/**
 * Direction indicates what direction (animated motion) the {@link Effect} should simulate the 
 * images are moving, if appropriate.
 * 
 * The direction indicates from what side or corner of the screen the new image should come in from.
 * Thus, a LEFT slide means the current image exits via the left-hand edge of the screen and the 
 * new image moves into place from the right-hand edge.
 *
 * UP, DOWN, and diagonals may be added at some point.
 */
public enum Direction {
    LEFT = 0,
    RIGHT = 1,
    
    /**
     * Convenience definition (for LTR readers).
     */
    FORWARD = LEFT,
    
    /**
     * Convenience definition (for LTR readers).
     */
    BACKWARD = RIGHT
}

/**
 * Visuals contains the pertinent drawing information for the transition that must occur.
 * 
 * A Visuals object is supplied to {@link Effect} at the start of the transition and during each 
 * call to paint to the screen.
 *
 * Note that if starting with a blank screen, from_pixbuf will be null and from_pos will be
 * zeroed. The transition should be considered to start from a blank screen of the supplied
 * background color.
 *
 * Also note that if transitioning to a blank screen, to_pixbuf will be null and to_pos will be
 * zeroed. Like the prior case, the transition should move toward a blank screen of the background
 * color.
 */
public class Visuals : Object {
    /**
     * Returns the starting pixbuf (the pixbuf currently on the display).
     *
     * If transitioning from a blank screen, this will return null.
     */
    public Gdk.Pixbuf? from_pixbuf { get; private set; }
    
    /**
     * Returns the position of the starting pixbuf on the display.
     *
     * If transitioning from a blank screen, this will be zeroed.
     */
    public Gdk.Rectangle from_pos { get; private set; }
    
    /**
     * Returns the ending pixbuf (the pixbuf that the transition should result in).
     *
     * If transitioning to a blank screen, this will return null.
     */
    public Gdk.Pixbuf? to_pixbuf { get; private set; }
    
    /**
     * Returns the position of the ending pixbuf on the display.
     *
     * If transitioning to a blank screen, this will be zeroed.
     */
    public Gdk.Rectangle to_pos { get; private set; }
    
    /**
     * Returns the background color of the viewport.
     */
    public Gdk.RGBA bg_color { get; private set; }
    
    public Visuals(Gdk.Pixbuf? from_pixbuf, Gdk.Rectangle from_pos, Gdk.Pixbuf? to_pixbuf,
        Gdk.Rectangle to_pos, Gdk.RGBA bg_color) {
        this.from_pixbuf = from_pixbuf;
        this.from_pos = from_pos;
        this.to_pixbuf = to_pixbuf;
        this.to_pos = to_pos;
        this.bg_color = bg_color;
    }
    
    //
    // For future expansion.
    //
    protected virtual void reserved0() {}
    protected virtual void reserved1() {}
    protected virtual void reserved2() {}
    protected virtual void reserved3() {}
    protected virtual void reserved4() {}
    protected virtual void reserved5() {}
    protected virtual void reserved6() {}
    protected virtual void reserved7() {}
}

/**
 * Motion contains all the pertinent information regarding the animation of the transition.
 *
 * Some of Motion's information may not apply to a transition effect (such as Direction for a 
 * fade effect).
 */
public class Motion : Object {
    /**
     * Returns the direction the transition should occur in (if pertinent to the {@link Effect}.
     */
    public Direction direction { get; private set; }
    
    /**
     * Returns the frames per second of the {@link Effect}.
     */
    public int fps { get; private set; }
    
    /**
     * Returns the amount of time the transition should take (in milliseconds).
     */
    public int duration_msec { get; private set; }
    
    /**
     * Returns the number of frames that should be required to perform the transition in the
     * expected {@link duration_msec}.
     */
    public int total_frames { 
        get {
            return (int) ((double) fps * ((double) duration_msec / 1000.0));
        }
    }
    
    /**
     * Returns the approximate time between each frame draw (in milliseconds).
     */
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
    
    /**
     * Returns a value from 0.0 to 1.0 that represents the percentage of the transition's completion
     * for the specified frame.
     */
    public double get_alpha(int frame_number) {
        return (double) frame_number / (double) total_frames;
    }
    
    //
    // For future expansion.
    //
    protected virtual void reserved0() {}
    protected virtual void reserved1() {}
    protected virtual void reserved2() {}
    protected virtual void reserved3() {}
    protected virtual void reserved4() {}
    protected virtual void reserved5() {}
    protected virtual void reserved6() {}
    protected virtual void reserved7() {}
}

/**
 * A Descriptor offers a factory method for creating {@link Effect} instances.
 */
public interface Descriptor : Object, Spit.Pluggable {
    /**
     * Returns an instance of the {@link Effect} this descriptor represents.
     */
    public abstract Effect create(Spit.HostInterface host);
    
    //
    // For future expansion.
    //
    protected virtual void reserved0() {}
    protected virtual void reserved1() {}
    protected virtual void reserved2() {}
    protected virtual void reserved3() {}
    protected virtual void reserved4() {}
    protected virtual void reserved5() {}
    protected virtual void reserved6() {}
    protected virtual void reserved7() {}
}

/**
 * An Effect represents an interstitial effect that is used to transition the display from one 
 * image to another.
 * 
 * An Effect must hold state so that it knows what it should be drawn at any call to {@link paint}
 * (which is called regularly during a transition). That is, it should be able to draw any frame of
 * the transition at any time. The same frame may need to be drawn multiple times, or the host
 * may skip ahead and ask for a frame well ahead of the last requested one.
 *
 * ''Frame numbers are one-based throughout this interface''. This is because the initial state (the
 * blank viewport or the starting pixbuf) is frame zero. The Effect is never called to paint this
 * frame.  The Effect is also not called to paint the final frame (a blank viewport or the ending
 * pixbuf).
 *
 * If the Effect uses background threads for its work, it should use the appropriate primitives
 * for critical sections. All calls to this interface will be from the context of the main UI
 * thread. ''None of these calls should block.''
 *
 * If the Details object needs to be held by the Effect, its reference to it should be dropped at
 * the end of the cycle (or shortly thereafter).
 *
 * An instance may be reused and should be prepared for restarts.
 */
public interface Effect : Object {
    /**
     * Returns frames per second (FPS) information for this effect.
     *
     * If the min_fps is not met, the Effect may be cancelled or the host will skip ahead.
     *
     * @param desired_fps The desired FPS of the transition.  Return zero if no
     *        transition is to occur (instantaneous or null transition).
     * @param min_fps The minimum FPS before the effect is consider "ruined".
     *        Return zero if any FPS is acceptable.
     */
    public abstract void get_fps(out int desired_fps, out int min_fps);
    
    /**
     * Called when the effect is starting.
     * 
     * All state should be reset. The frame number, which is not supplied, is one.
     */
    public abstract void start(Visuals visuals, Motion motion);
    
    /**
     * Return true if the Effect needs the background cleared prior to calling {@link paint}.
     */
    public abstract bool needs_clear_background();
    
    /**
     * Called when the effect needs to paint (i.e. an expose or draw event has occurred).
     * 
     * This call should ''not'' advance the state of the effect (i.e. it may be called more than 
     * once for the same frame).
     *
     * @param ctx The Cairo context the Effect should use to paint the transition.
     * @param width The width (in pixels) of the Cairo surface.
     * @param height The height (in pixels) of the Cairo surface.
     * @param frame_number The ''one-based'' frame being drawn.
     */
    public abstract void paint(Visuals visuals, Motion motion, Cairo.Context ctx, int width,
        int height, int frame_number);
    
    /**
     * Called to notify the effect that the state of the transition should advance to the specified
     * frame number.
     * 
     * Note: There is no guarantee frame numbers will be consecutive between calls
     * to next, especially if the transition clock is attempting to catch up.
     *
     * @param frame_number The ''one-based'' frame being advanced to.
     */
    public abstract void advance(Visuals visuals, Motion motion, int frame_number);
    
    /**
     * Called if the Effect should halt the transition.
     * 
     * It only needs to reset state if {@link start} is called again.
     */
    public abstract void cancel();
    
    //
    // For future expansion.
    //
    protected virtual void reserved0() {}
    protected virtual void reserved1() {}
    protected virtual void reserved2() {}
    protected virtual void reserved3() {}
    protected virtual void reserved4() {}
    protected virtual void reserved5() {}
    protected virtual void reserved6() {}
    protected virtual void reserved7() {}
}

}

