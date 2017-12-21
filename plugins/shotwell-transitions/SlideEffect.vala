/* Copyright 2010 Maxim Kartashev
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Spit;

private class SlideEffectDescriptor : ShotwellTransitionDescriptor {
    public SlideEffectDescriptor(GLib.File resource_directory) {
        base(resource_directory);
    }

    public override unowned string get_id() {
        return "org.yorba.shotwell.transitions.slide";
    }
    
    public override unowned string get_pluggable_name() {
        return _("Slide");
    }
    
    public override Transitions.Effect create(Spit.HostInterface host) {
        return new SlideEffect();
    }
}

private class SlideEffect : Object, Transitions.Effect {
    private const int DESIRED_FPS = 25;
    private const int MIN_FPS = 15;
    
    public SlideEffect() {
    }
    
    public void get_fps(out int desired_fps, out int min_fps) {
        desired_fps = SlideEffect.DESIRED_FPS;
        min_fps = SlideEffect.MIN_FPS;
    }
    
    public void start(Transitions.Visuals visuals, Transitions.Motion motion) {
    }
    
    public bool needs_clear_background() {
        return true;
    }
    
    public void paint(Transitions.Visuals visuals, Transitions.Motion motion, Cairo.Context ctx,
        int width, int height, int frame_number) {
        double alpha = motion.get_alpha(frame_number);
        
        if (visuals.from_pixbuf != null) {
            int from_target_x = (motion.direction == Transitions.Direction.FORWARD) 
                ? -visuals.from_pixbuf.width : width;
            int from_current_x = (int) (visuals.from_pos.x * (1 - alpha) + from_target_x * alpha);
            Gdk.cairo_set_source_pixbuf(ctx, visuals.from_pixbuf, from_current_x, visuals.from_pos.y);
            ctx.paint();
        }

        if (visuals.to_pixbuf != null) {
            int to_target_x = (width - visuals.to_pixbuf.width) / 2;
            int from_x = (motion.direction == Transitions.Direction.FORWARD) 
                ? width : -visuals.to_pixbuf.width;
            int to_current_x = (int) (from_x * (1 - alpha) + to_target_x * alpha);
            Gdk.cairo_set_source_pixbuf(ctx, visuals.to_pixbuf, to_current_x, visuals.to_pos.y);
            ctx.paint();
        }
    }
    
    public void advance(Transitions.Visuals visuals, Transitions.Motion motion, int frame_number) {
    }
    
    public void cancel() {
    }
}

