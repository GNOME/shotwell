/* Copyright 2010 Maxim Kartashev
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class TransitionEffectsManager {
    public const string NULL_EFFECT_ID = NullTransitionDescriptor.EFFECT_ID;
    public const string RANDOM_EFFECT_ID = RandomEffectDescriptor.EFFECT_ID;
    private static TransitionEffectsManager? instance = null;
    
    // effects are stored by effect ID
    private Gee.Map<string, Spit.Transitions.Descriptor> effects = new Gee.HashMap<
        string, Spit.Transitions.Descriptor>();
    private Spit.Transitions.Descriptor null_descriptor = new NullTransitionDescriptor();
    private Spit.Transitions.Descriptor random_descriptor = new RandomEffectDescriptor();
    
    private TransitionEffectsManager() {
        load_transitions();
        Plugins.Notifier.get_instance().pluggable_activation.connect(load_transitions);
    }
    
    ~TransitionEffectsManager() {
        Plugins.Notifier.get_instance().pluggable_activation.disconnect(load_transitions);
    }
    
    private void load_transitions() {
        effects.clear();
        
        // add null and random effect first
        effects.set(null_descriptor.get_id(), null_descriptor);
        effects.set(random_descriptor.get_id(),random_descriptor);

        // load effects from plug-ins
        Gee.Collection<Spit.Pluggable> pluggables = Plugins.get_pluggables_for_type(
            typeof(Spit.Transitions.Descriptor));
        foreach (Spit.Pluggable pluggable in pluggables) {
            int pluggable_interface = pluggable.get_pluggable_interface(Spit.Transitions.CURRENT_INTERFACE,
                Spit.Transitions.CURRENT_INTERFACE);
            if (pluggable_interface != Spit.Transitions.CURRENT_INTERFACE) {
                warning("Unable to load transitions plug-in %s: reported interface %d",
                    Plugins.get_pluggable_module_id(pluggable), pluggable_interface);
                
                continue;
            }
            
            Spit.Transitions.Descriptor desc = (Spit.Transitions.Descriptor) pluggable;
            if (effects.has_key(desc.get_id()))
                warning("Multiple transitions loaded with same effect ID %s", desc.get_id());
            else
                effects.set(desc.get_id(), desc);
        }
    }
    
    public static void init() {
        instance = new TransitionEffectsManager();
    }
    
    public static void terminate() {
        instance = null;
    }
    
    public static TransitionEffectsManager get_instance() {
        assert(instance != null);
        
        return instance;
    }
    
    public Gee.Collection<string> get_effect_ids() {
        return effects.keys;
    }
    
    public Gee.Collection<string> get_effect_names(owned CompareDataFunc? comparator = null) {
        Gee.Collection<string> effect_names = new Gee.TreeSet<string>((owned) comparator);
        foreach (Spit.Transitions.Descriptor desc in effects.values)
            effect_names.add(desc.get_pluggable_name());
        
        return effect_names;
    }
    
    public string? get_id_for_effect_name(string effect_name) {
        foreach (Spit.Transitions.Descriptor desc in effects.values) {
            if (desc.get_pluggable_name() == effect_name)
                return desc.get_id();
        }
        
        return null;
    }
    
    public Spit.Transitions.Descriptor? get_effect_descriptor(string effect_id) {
        return effects.get(effect_id);
    }
    
    public string get_effect_name(string effect_id) {
        Spit.Transitions.Descriptor? desc = get_effect_descriptor(effect_id);
        
        return (desc != null) ? desc.get_pluggable_name() : _("(None)");
    }
    
    public Spit.Transitions.Descriptor get_null_descriptor() {
        return null_descriptor;
    }
    
    public TransitionClock? create_transition_clock(string effect_id) {
        Spit.Transitions.Descriptor? desc = get_effect_descriptor(effect_id);
        
        return (desc != null) ? new TransitionClock(desc) : null;
    }
    
    public TransitionClock create_null_transition_clock() {
        return new TransitionClock(null_descriptor);
    }
}

public class TransitionClock {
    // This method is called by TransitionClock to indicate that it's time for the transition to be
    // repainted.  The callback should call TransitionClock.paint() with the appropriate Drawable
    // either immediately or quite soon (in an expose event).
    public delegate void RepaintCallback();
    
    private Spit.Transitions.Descriptor desc;
    private Spit.Transitions.Effect effect;
    private int desired_fps;
    private int min_fps;
    private int current_fps = 0;
    private OpTimer paint_timer;
    private Spit.Transitions.Visuals? visuals = null;
    private Spit.Transitions.Motion? motion = null;
    private unowned RepaintCallback? repaint = null;
    private uint timer_id = 0;
    private ulong time_started = 0;
    private int frame_number = 0;
    private bool cancelled = false;
    
    public TransitionClock(Spit.Transitions.Descriptor desc) {
        this.desc = desc;
        
        effect = desc.create(new Plugins.StandardHostInterface(desc, "transitions"));
        effect.get_fps(out desired_fps, out min_fps);
        
        paint_timer = new OpTimer(desc.get_pluggable_name());
    }
    
    ~TransitionClock() {
        cancel_timer();
        debug("%s tick_msec=%d min/desired/current fps=%d/%d/%d", paint_timer.to_string(),
            (motion != null) ? motion.tick_msec : 0, min_fps, desired_fps, current_fps);
    }
    
    public bool is_in_progress() {
        return (!cancelled && motion != null) ? frame_number < motion.total_frames : false;
    }
    
    public void start(Spit.Transitions.Visuals visuals, Spit.Transitions.Direction direction,
        int duration_msec, RepaintCallback repaint) {
        reset();
        
        // if no desired FPS, this is a no-op transition
        if (desired_fps == 0)
            return;
        
        this.visuals = visuals;
        this.repaint = repaint;
        motion = new Spit.Transitions.Motion(direction, desired_fps, duration_msec);
        
        effect.start(visuals, motion);
        
        // start the timer
        // TODO: It may be smarter to not use Timeout naively, as it does not attempt to catch up
        // when tick() is called late.
        time_started = now_ms();
        timer_id = Timeout.add_full(Priority.HIGH, motion.tick_msec, tick);
    }
    
    // This resets all state for the clock.  No check is done if the clock is running.
    private void reset() {
        visuals = null;
        motion = null;
        repaint = null;
        cancel_timer();
        time_started = 0;
        frame_number = 1;
        current_fps = 0;
        cancelled = false;
    }
    
    private void cancel_timer() {
        if (timer_id != 0) {
            Source.remove(timer_id);
            timer_id = 0;
        }
    }
    
    // Calculate current FPS rate and returns true if it's above minimum
    private bool is_fps_ok() {
        assert(time_started > 0);
        
        if (frame_number <= 3) 
            return true; // don't bother measuring if statistical data are too small
        
        double elapsed_msec = (double) (now_ms() - time_started);
        if (elapsed_msec <= 0.0)
            return true;
        
        current_fps = (int) ((frame_number * 1000.0) / elapsed_msec);
        if (current_fps < min_fps) {
            debug("Transition rate of %dfps below minimum of %dfps (elapsed=%lf frames=%d)",
                current_fps, min_fps, elapsed_msec, frame_number);
        }
        
        return (current_fps >= min_fps);
    }
    
    // Cancels current transition.
    public void cancel() {
        cancelled = true;
        cancel_timer();
        effect.cancel();
        
        // repaint to complete the transition
        repaint();
    }
    
    // Call this whenever using a TransitionClock in the expose event.  Returns false if the
    // transition has completed, in which case the caller should paint the final result.
    public bool paint(Cairo.Context ctx, int width, int height) {
        if (!is_in_progress())
            return false;
        
        paint_timer.start();
        
        ctx.save();
        
        if (effect.needs_clear_background()) {
            ctx.set_source_rgba(visuals.bg_color.red, visuals.bg_color.green, visuals.bg_color.blue,
                visuals.bg_color.alpha);
            ctx.rectangle(0, 0, width, height);
            ctx.fill();
        }
        
        effect.paint(visuals, motion, ctx, width, height, frame_number);
        
        ctx.restore();
        
        paint_timer.stop();
        
        return true;
    }
    
    private bool tick() {
        if (!is_fps_ok()) {
            debug("Cancelling transition: below minimum fps");
            cancel();
        }
        
        // repaint always; this timer tick will go away when the frames have exhausted (and
        // guarantees the first frame is painted before advancing the counter)
        repaint();
        
        if (!is_in_progress()) {
            cancel_timer();
            
            return false;
        }
        
        // advance to the next frame
        if (frame_number < motion.total_frames)
            effect.advance(visuals, motion, ++frame_number);
        
        return true;
    }
}

public class NullTransitionDescriptor : Object, Spit.Pluggable, Spit.Transitions.Descriptor {
    public const string EFFECT_ID = "org.yorba.shotwell.transitions.null";
    
    public int get_pluggable_interface(int min_host_version, int max_host_version) {
        return Spit.Transitions.CURRENT_INTERFACE;
    }
    
    public unowned string get_id() {
        return EFFECT_ID;
    }
    
    public unowned string get_pluggable_name() {
        return _("None");
    }
    
    public void get_info(ref Spit.PluggableInfo info) {
    }
    
    public void activation(bool enabled) {
    }
    
    public Spit.Transitions.Effect create(Spit.HostInterface host) {
        return new NullEffect();
    }
}

public class NullEffect : Object, Spit.Transitions.Effect {
    public NullEffect() {
    }
    
    public void get_fps(out int desired_fps, out int min_fps) {
        desired_fps = 0;
        min_fps = 0;
    }
    
    public void start(Spit.Transitions.Visuals visuals, Spit.Transitions.Motion motion) {
    }
    
    public bool needs_clear_background() {
        return false;
    }
    
    public void paint(Spit.Transitions.Visuals visuals, Spit.Transitions.Motion motion, Cairo.Context ctx,
        int width, int height, int frame_number) {
    }
    
    public void advance(Spit.Transitions.Visuals visuals, Spit.Transitions.Motion motion, int frame_number) {
    }
    
    public void cancel() {
    }
}
public class RandomEffectDescriptor : Object, Spit.Pluggable, Spit.Transitions.Descriptor {
    public const string EFFECT_ID = "org.yorba.shotwell.transitions.random";

    public int get_pluggable_interface(int min_host_version, int max_host_version) {
        return Spit.Transitions.CURRENT_INTERFACE;
    }

    public unowned string get_id() {
        return EFFECT_ID;
    }
    
    public unowned string get_pluggable_name() {
        return _("Random");
    }

    public void get_info(ref Spit.PluggableInfo info) {
    }
    
    public void activation(bool enabled) {
    }

    public Spit.Transitions.Effect create(Spit.HostInterface host) {
        return new NullEffect();
    }
}
