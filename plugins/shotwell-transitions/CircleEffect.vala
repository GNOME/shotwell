/* Copyright 2013 Jens Bav
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Spit;

private class CircleEffectDescriptor : ShotwellTransitionDescriptor {
    public CircleEffectDescriptor(GLib.File resource_directory) {
        base(resource_directory);
    }

    public override unowned string get_id() {
        return "org.yorba.shotwell.transitions.circle";
    }

    public override unowned string get_pluggable_name() {
        return _("Circle");
    }

    public override Transitions.Effect create(HostInterface host) {
        return new CircleEffect();
    }
}

private class CircleEffect : Object, Transitions.Effect {
    private const int DESIRED_FPS = 25;
    private const int MIN_FPS = 15;

    public CircleEffect() {
    }

    public void get_fps(out int desired_fps, out int min_fps) {
        desired_fps = CircleEffect.DESIRED_FPS;
        min_fps = CircleEffect.MIN_FPS;
    }

    public void start(Transitions.Visuals visuals, Transitions.Motion motion) {
    }

    public bool needs_clear_background() {
        return true;
    }

    public void paint(Transitions.Visuals visuals, Transitions.Motion motion, Cairo.Context ctx,
        int width, int height, int frame_number) {
        double alpha = motion.get_alpha(frame_number);
        int radius = (int)(alpha * Math.fmax(width,height));
        
        if (visuals.from_pixbuf != null) {
            Gdk.cairo_set_source_pixbuf(ctx, visuals.from_pixbuf, visuals.from_pos.x,
                visuals.from_pos.y);
            ctx.paint_with_alpha(1 - alpha);
        }
        
        if (visuals.to_pixbuf != null) {
            Gdk.cairo_set_source_pixbuf(ctx, visuals.to_pixbuf,visuals.to_pos.x, visuals.to_pos.y);
            ctx.arc ((int) width / 2, (int) height / 2, radius, 0, 2 * Math.PI);
            ctx.clip();
            ctx.paint();
        }
    }

    public void advance(Transitions.Visuals visuals, Transitions.Motion motion, int frame_number) {
    }

    public void cancel() {
    }
}
