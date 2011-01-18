/* Copyright 2010 Maxim Kartashev
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class TransitionEffectsManager {
    public const string NULL_TRANSITION_NAME = TransitionEffectsImpl.NullTransitionEffectDescriptor.NAME;
    
    private static TransitionEffectsManager? instance = null;
    
    // effects are stored by name
    private Gee.Map<string, TransitionEffectDescriptor> effects = new Gee.HashMap<
        string, TransitionEffectDescriptor>();
    
    private TransitionEffectsManager() {
        add_effect(new TransitionEffectsImpl.NullTransitionEffectDescriptor());
        add_effect(new TransitionEffectsImpl.ShiftTransitionEffectDescriptor());
        add_effect(new TransitionEffectsImpl.FadeTransitionEffectDescriptor());
        add_effect(new TransitionEffectsImpl.TearTransitionEffectDescriptor());
    }
    
    public static TransitionEffectsManager get_instance() {
        if (instance == null)
            instance = new TransitionEffectsManager();
        
        return instance;
    }
    
    public TransitionEffect get_null_instance() {
        return new TransitionEffectsImpl.NullTransitionEffect.empty();
    }
    
    private void add_effect(TransitionEffectDescriptor desc) {
        effects.set(desc.get_name(), desc);
    }
    
    public Gee.Collection<string> get_names() {
        return effects.keys;
    }
    
    public Gee.Collection<string> get_display_names(CompareFunc? comparator = null) {
        Gee.Collection<string> display_names = new Gee.TreeSet<string>(comparator);
        foreach (TransitionEffectDescriptor desc in effects.values)
            display_names.add(desc.get_display_name());
        
        return display_names;
    }
    
    public string? get_name_for_display_name(string display_name) {
        foreach (TransitionEffectDescriptor desc in effects.values) {
            if (desc.get_display_name() == display_name)
                return desc.get_name();
        }
        
        return null;
    }
    
    public string get_display_name(string name) {
        TransitionEffectDescriptor? desc = effects.get(name);
        
        return (desc != null) ? desc.get_display_name() : _("(no name)");
    }
    
    public TransitionEffect? create_effect(string name, TransitionEffect.RepaintCallback repaint_callback, 
        Gdk.Color bg_color) {
        TransitionEffectDescriptor? desc = effects.get(name);
        
        return (desc != null) ? desc.create(repaint_callback, bg_color) : null;
    }
}

public abstract class TransitionState {
    private Cancellable cancellable = new Cancellable();
    
    // Returns true if transition still has frames to draw
    public bool is_in_progress() {
        return !is_cancelled() && check_in_progress();
    }
    
    // Override this in order to inform that your child transition 
    // is still in progress.
    protected abstract bool check_in_progress();
    
    // Go to next state of transition between photos
    public abstract void next();
    
    public bool is_cancelled() {
        return cancellable.is_cancelled();
    }
    
    public void cancel() {
        cancellable.cancel();
    }
}

public abstract class TransitionEffect {
    public delegate void RepaintCallback();
    
    // Describes current state of transition
    public TransitionState state { get; protected set; default = null; }
    
    // Desired duration of transition in milliseconds
    public int duration { get; set; default = 300; }
    
    // Desired number of frames-per-second for this transition effects
    public int fps { get; set; default = 30; }
    
    // Hard minimum for frames-per-second; 0 if don't care
    // Transition will get cancelled if current system can't provide this
    // amount of FPS
    public int min_fps { get; protected set; default = 0; }
    
    public bool enabled { get; set; default = true; }
    
    // Color of background when drawing transition
    protected Gdk.Color bg_color;
    
    // Current transition data:
    
    // "from" image and "to" image and their respective locations
    protected Gdk.Pixbuf from_pixbuf = null;
    protected Gdk.Rectangle from_pos;
    protected Gdk.Pixbuf to_pixbuf = null;
    protected Gdk.Rectangle to_pos;
    
    // Direction of current transition
    protected Direction direction;
    
    // Bookkeeping data: time current transition has started and ...
    protected ulong time_started;
    
    // ... how many frames has been drawn so far
    protected int frames_drawn;
    
    private RepaintCallback repaint_callback;
    
    // ID of the timer that is used to initiate repaint
    protected uint timer_id;
    
    public TransitionEffect(RepaintCallback repaint_callback, Gdk.Color bg_color) {
        this.repaint_callback = repaint_callback;
        this.bg_color = bg_color;
        
        state = get_initial_state();
    }
    
    // Initiate transition from from_pixbuf to to_pixbuf by periodically
    // calling repaint_callback() (see above) and this.paint()
    public virtual void start(Gdk.Pixbuf? from_pixbuf, Gdk.Rectangle from_pos, 
        Gdk.Pixbuf? to_pixbuf, Gdk.Rectangle to_pos, Direction direction) {
        assert(enabled);
        assert(fps > 0 && fps >= min_fps);
        assert(duration > 0);
        // Both pixbufs cannot be null
        assert(from_pixbuf != null || to_pixbuf != null);
        assert(!state.is_in_progress());
        assert(timer_id == 0);
        
        this.from_pixbuf = from_pixbuf;
        this.from_pos    = from_pos;
        this.to_pixbuf   = to_pixbuf;
        this.to_pos      = to_pos;
        this.direction   = direction;
        
        state = get_initial_state();
        
        time_started = now_ms();
        frames_drawn = 0;
        image_transition_tick(); // initiate first repaint now
        timer_id = Timeout.add((uint) (1000.0 / (double) fps), image_transition_tick);
    }
    
    // Calculate current FPS rate and returns true if it's above minimum
    protected bool is_fps_ok() {
        assert(time_started > 0);
        
        if (frames_drawn <= 2) 
            return true; // don't bother measuring if statistical data are too small
        
        int elapsed = (int) (now_ms() - time_started);
        int cur_fps = (int) (frames_drawn * 1000.0 / elapsed);
        
        if (cur_fps < min_fps)
            debug("Transition rate of %dfps below minimum of %dfps", cur_fps, min_fps);
        
        return (cur_fps >= min_fps);
    }
    
    // Cancels current transition.
    public void cancel() {
        state.cancel();
        
        if (timer_id != 0) {
            Source.remove(timer_id);
            timer_id = 0;
        }
        
        repaint_callback(); // repaint without transition this time
    }
    
    public abstract TransitionState get_initial_state();
    
    public virtual void paint(Gdk.Drawable drawable)  {
        assert(state.is_in_progress());
        
        frames_drawn++;
        if (is_fps_ok()) {
            child_paint(drawable);
        } else {
            debug("TransitionEffect: Cancelling: below minimum fps");
            cancel();
            enabled = false;
        }
    }
    
    public abstract void child_paint(Gdk.Drawable drawable);
    
    private bool image_transition_tick() {
        if (!state.is_in_progress()) {
            // cancels timer
            timer_id = 0;
            
            return false;
        }
        
        repaint_callback();
        state.next();
        
        if (!state.is_in_progress()) {
            // cancels timer
            timer_id = 0;
            
            return false;
        }
        
        return true;
    }
}

public abstract class TransitionEffectDescriptor {
    public abstract string get_name();
    
    public abstract string get_display_name();
    
    public abstract TransitionEffect create(TransitionEffect.RepaintCallback repaint_callback,
        Gdk.Color bg_color);
}

namespace TransitionEffectsImpl {

private class NullTransitionState : TransitionState {
    protected override bool check_in_progress() {
        return false;
    }
    
    public override void next() {
        assert(false);
    }
}

private class NullTransitionEffectDescriptor : TransitionEffectDescriptor {
    public const string NAME = "none";
    
    public override string get_name() {
        return NAME;
    }
    
    public override string get_display_name() {
        return _("None");
    }
    
    public override TransitionEffect create(TransitionEffect.RepaintCallback repaint_callback,
        Gdk.Color bg_color) {
        return new NullTransitionEffect(repaint_callback, bg_color);
    }
}

private class NullTransitionEffect : TransitionEffect {
    public NullTransitionEffect.empty() {
        base(() => {}, Gdk.Color());
        enabled = false;
    }

    public NullTransitionEffect(TransitionEffect.RepaintCallback repaint_callback,
        Gdk.Color bg_color) {
        base(repaint_callback, bg_color);
        enabled = false;
    }
    
    public override TransitionState get_initial_state() {
        return new NullTransitionState();
    }
    
    protected override void child_paint(Gdk.Drawable drawable) {
        assert(false);
    }
}

private class FrameTransitionState : TransitionState {
    public int current_frame { get; set; default = 0; }
    public int last_frame { get; private set; default = 0; }
    
    public FrameTransitionState(int fps, int duration) {
        current_frame = 1;
        this.last_frame = (int) (fps * (duration / 1000.0));
        assert(last_frame > 1);
    }
    
    protected override bool check_in_progress() {
        return current_frame > 0 && current_frame <= last_frame;
    }
    
    public override void next() {
        if (current_frame <= last_frame)
            current_frame++;
    }
}

private class FadeTransitionEffectDescriptor : TransitionEffectDescriptor {
    public override string get_name() {
        return "fade";
    }
    
    public override string get_display_name() {
        return _("Fade");
    }
    
    public override TransitionEffect create(TransitionEffect.RepaintCallback repaint_callback,
        Gdk.Color bg_color) {
        return new FadeTransitionEffect(repaint_callback, bg_color);
    }
}

private class FadeTransitionEffect : TransitionEffect {
    public FadeTransitionEffect(TransitionEffect.RepaintCallback repaint_callback,
        Gdk.Color bg_color) {
        base(repaint_callback, bg_color);
        fps = 30;
        min_fps = 20;
    }
    
    public override TransitionState get_initial_state() {
        return new FrameTransitionState(fps, duration);
    }
    
    private FrameTransitionState my_state() {
        return (FrameTransitionState) state;
    }

    protected override void child_paint(Gdk.Drawable drawable) {
        // draw background
        int width;
        int height;
        drawable.get_size(out width, out height);
        Cairo.Context ctx = Gdk.cairo_create(drawable);
        ctx.set_source_rgb(bg_color.red / 65535.0, bg_color.green / 65535.0, bg_color.blue / 65535.0);
        ctx.rectangle(0, 0, width, height);
        ctx.fill();
        double alpha = my_state().current_frame / (double) my_state().last_frame;
        
        if (from_pixbuf != null) {
            Gdk.cairo_set_source_pixbuf(ctx, from_pixbuf, 
                from_pos.x, from_pos.y);
            ctx.paint_with_alpha(1 - alpha);
        }

        if (to_pixbuf != null) {
            Gdk.cairo_set_source_pixbuf(ctx, to_pixbuf, 
                to_pos.x, to_pos.y);
            ctx.paint_with_alpha(alpha);
        }
    }
}

private class ShiftTransitionEffectDescriptor : TransitionEffectDescriptor {
    public override string get_name() {
        return "shift";
    }
    
    public override string get_display_name() {
        return _("Shift");
    }
    
    public override TransitionEffect create(TransitionEffect.RepaintCallback repaint_callback,
        Gdk.Color bg_color) {
        return new ShiftTransitionEffect(repaint_callback, bg_color);
    }
}

private class ShiftTransitionEffect : TransitionEffect {
    public ShiftTransitionEffect(TransitionEffect.RepaintCallback repaint_callback, 
        Gdk.Color bg_color) {
        base(repaint_callback, bg_color);
        fps = 25;
        min_fps = 15;
    }
    
    public override TransitionState get_initial_state() {
        return new FrameTransitionState(fps, duration);
    }

    private FrameTransitionState my_state() {
        return (FrameTransitionState) state;
    }
    
    protected override void child_paint(Gdk.Drawable drawable)  {
        Cairo.Context ctx = Gdk.cairo_create(drawable);
        int width, height;
        drawable.get_size(out width, out height);
        ctx.rectangle(0, 0, width, height);
        ctx.set_source_rgb(bg_color.red/65535.0, bg_color.green/65535.0, bg_color.blue/65535.0);
        ctx.fill();
        double alpha = my_state().current_frame / (double)my_state().last_frame;
        
        if (from_pixbuf != null) {
            int from_target_x = (direction == Direction.FORWARD) ? -from_pixbuf.width : width;
            int from_current_x = (int) (from_pos.x * (1 - alpha) + from_target_x * alpha);
            Gdk.cairo_set_source_pixbuf(ctx, from_pixbuf, from_current_x, from_pos.y);
            ctx.paint();
        }

        if (to_pixbuf != null) {
            int to_target_x = (width - to_pixbuf.width) / 2;
            int from_x = (direction == Direction.FORWARD) ? width : -to_pixbuf.width;
            int to_current_x = (int) (from_x * (1 - alpha) + to_target_x * alpha);
            Gdk.cairo_set_source_pixbuf(ctx, to_pixbuf, to_current_x, to_pos.y);
            ctx.paint();
        }
    }
}

private class TearTransitionEffectDescriptor : TransitionEffectDescriptor {
    public override string get_name() {
        return "tear";
    }
    
    public override string get_display_name() {
        return _("Tear down");
    }
    
    public override TransitionEffect create(TransitionEffect.RepaintCallback repaint_callback,
        Gdk.Color bg_color) {
        return new TearTransitionEffect(repaint_callback, bg_color);
    }
}

private class TearTransitionEffect : TransitionEffect {
    private const int STRIPE_WIDTH = 5;
    
    private Cairo.ImageSurface[] from_stripes;
    private double[] accelerations;
    private int stripes_count;
    
    public TearTransitionEffect(TransitionEffect.RepaintCallback repaint_callback, 
        Gdk.Color bg_color) {
        base(repaint_callback, bg_color);
        fps = 25;
        min_fps = 15;
    }
    
    public override TransitionState get_initial_state() {
        return new FrameTransitionState(fps, duration);
    }

    private FrameTransitionState my_state() {
        return (FrameTransitionState) state;
    }
    
    public override void start(Gdk.Pixbuf? from_pixbuf, Gdk.Rectangle from_pos, 
        Gdk.Pixbuf? to_pixbuf,Gdk.Rectangle to_pos, Direction direction) {
        Rand rand = new Rand();
        rand.set_seed((uint32) now_ms());
        Cairo.Context ctx;
        
        // Cut original image into stripes of STRIPE_WIDTH width; also prepare
        // acceleration for each stripe.
        if (from_pixbuf != null) {
            stripes_count = from_pixbuf.width / STRIPE_WIDTH;
            from_stripes = new Cairo.ImageSurface[stripes_count];
            accelerations = new double[stripes_count];
            for (int i = 0; i < stripes_count; ++i) {
                from_stripes[i] = new Cairo.ImageSurface(Cairo.Format.RGB24, STRIPE_WIDTH,
                    from_pixbuf.height);
                ctx = new Cairo.Context(from_stripes[i]);
                Gdk.cairo_set_source_pixbuf(ctx, from_pixbuf, - i * STRIPE_WIDTH, 0);
                ctx.paint();
                accelerations[i] = rand.next_double();
            }
        }
        
        base.start(from_pixbuf, from_pos, to_pixbuf, to_pos, direction);
    }
    
    protected override void child_paint(Gdk.Drawable drawable) {
        Cairo.Context ctx = Gdk.cairo_create(drawable);
        int width, height;
        drawable.get_size(out width, out height);
        ctx.rectangle(0, 0, width, height);
        ctx.set_source_rgb(bg_color.red / 65535.0, bg_color.green / 65535.0, bg_color.blue / 65535.0);
        ctx.fill();
        double alpha = my_state().current_frame / (double) my_state().last_frame;
        
        if (alpha < 0.5) {
            // First part: draw stripes that go down with pre-calculated acceleration
            alpha = alpha * 2; // stretch alpha to [0, 1]
            // tear down from_pixbuf first 
            for (int i = 0; i < stripes_count; ++i) {
                int x = from_pos.x + i * STRIPE_WIDTH;
                double a = alpha + alpha * accelerations[i];
                int y = from_pos.y + (int) (from_pixbuf.height * a * a);
                
                ctx.set_source_surface(from_stripes[i], x, y);
                ctx.paint();
            }
        } else {
            // Second part: fade in next image ("to_pixbuf")
            alpha = (alpha - 0.5) * 2; // stretch alpha to [0, 1]
            Gdk.cairo_set_source_pixbuf(ctx, to_pixbuf, to_pos.x, to_pos.y);
            ctx.paint_with_alpha(alpha);
        }
    }
}

}

