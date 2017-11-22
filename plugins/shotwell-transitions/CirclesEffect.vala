/* Copyright 2013 Jens Bav
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Spit;

private class CirclesEffectDescriptor : ShotwellTransitionDescriptor {
    public CirclesEffectDescriptor(GLib.File resource_directory) {
        base(resource_directory);
    }

    public override unowned string get_id() {
        return "org.yorba.shotwell.transitions.circles";
    }

    public override unowned string get_pluggable_name() {
        return _("Circles");
    }

    public override Transitions.Effect create(HostInterface host) {
        return new CirclesEffect();
    }
}

private class CirclesEffect : Object, Transitions.Effect {
    private const int DESIRED_FPS = 25;
    private const int MIN_FPS = 15;
    private const double SPEED = 2.5;

    public CirclesEffect() {
    }

    public void get_fps(out int desired_fps, out int min_fps) {
        desired_fps = CirclesEffect.DESIRED_FPS;
        min_fps = CirclesEffect.MIN_FPS;
    }

    public void start(Transitions.Visuals visuals, Transitions.Motion motion) {
    }

    public bool needs_clear_background() {
        return true;
    }

    public void paint(Transitions.Visuals visuals, Transitions.Motion motion, Cairo.Context ctx,
        int width, int height, int frame_number) {
        double alpha = motion.get_alpha(frame_number);
        int distance = 60, radius;
        int circleCountX = width / (2 * distance);
        int circleCountY = height / distance;
        double maxRadius = SPEED * distance;
        
        if (visuals.from_pixbuf != null) {
            Gdk.cairo_set_source_pixbuf(ctx, visuals.from_pixbuf, visuals.from_pos.x,
                visuals.from_pos.y);
            ctx.paint_with_alpha(1 - alpha);
        }
        
        if (visuals.to_pixbuf != null) {
            Gdk.cairo_set_source_pixbuf(ctx, visuals.to_pixbuf,visuals.to_pos.x, visuals.to_pos.y);
            
            for(int y = 0; y <= circleCountY; y++){
                for(int x = 0; x <= circleCountX; x++){
                    radius = (int) (Math.fmax(0,Math.fmin(1, alpha-((double) (x + y)/(double)
                        ((circleCountY + circleCountX) * SPEED)))) * maxRadius);
                    ctx.arc(2 * distance * x, 2 * distance * y, radius, 0, 2 * Math.PI);
                    ctx.fill();
                }
            }
            
            ctx.clip();
            ctx.paint_with_alpha(alpha);
        }


    }

    public void advance(Transitions.Visuals visuals, Transitions.Motion motion, int frame_number) {
    }

    public void cancel() {
    }
}
