/* Copyright 2010 Maxim Kartashev
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Spit;

private class FadeEffectDescriptor : ShotwellTransitionDescriptor {
    public FadeEffectDescriptor(GLib.File resource_directory) {
        base(resource_directory);
    }

    public override unowned string get_id() {
        return "org.yorba.shotwell.transitions.fade";
    }
    
    public override unowned string get_pluggable_name() {
        return _("Fade");
    }
    
    public override Transitions.Effect create(Spit.HostInterface host) {
        return new FadeEffect();
    }
}

private class FadeEffect : Object, Transitions.Effect {
    private const int DESIRED_FPS = 30;
    private const int MIN_FPS = 20;
    
    public FadeEffect() {
    }
    
    public void get_fps(out int desired_fps, out int min_fps) {
        desired_fps = FadeEffect.DESIRED_FPS;
        min_fps = FadeEffect.MIN_FPS;
    }
    
    public void start(Transitions.Visuals visuals, Transitions.Motion motion) {
    }
    
    public bool needs_clear_background() {
        return true;
    }
    
    public void paint(Transitions.Visuals visuals, Transitions.Motion motion, Cairo.Context ctx,
        int width, int height, int frame_number) {
        double alpha = motion.get_alpha(frame_number);
        
        // blend the two pixbufs using an alpha of the appropriate level depending on how far
        // the cycle has progressed
        if (visuals.from_pixbuf != null) {
            Gdk.cairo_set_source_pixbuf(ctx, visuals.from_pixbuf, visuals.from_pos.x, visuals.from_pos.y);
            ctx.paint_with_alpha(1.0 - alpha);
        }

        if (visuals.to_pixbuf != null) {
            Gdk.cairo_set_source_pixbuf(ctx, visuals.to_pixbuf, visuals.to_pos.x, visuals.to_pos.y);
            ctx.paint_with_alpha(alpha);
        }
    }
    
    public void advance(Transitions.Visuals visuals, Transitions.Motion motion, int frame_number) {
    }
    
    public void cancel() {
    }
}

