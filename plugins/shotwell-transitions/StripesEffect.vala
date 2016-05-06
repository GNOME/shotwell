/* Copyright 2013 Jens Bav
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Spit;

private class StripesEffectDescriptor : ShotwellTransitionDescriptor {
    public StripesEffectDescriptor(GLib.File resource_directory) {
        base(resource_directory);
    }

    public override unowned string get_id() {
        return "org.yorba.shotwell.transitions.stripes";
    }

    public override unowned string get_pluggable_name() {
        return _("Stripes");
    }

    public override Transitions.Effect create(HostInterface host) {
        return new StripesEffect();
    }
}

private class StripesEffect : Object, Transitions.Effect {
    private const int DESIRED_FPS = 25;
    private const int MIN_FPS = 10;
    private const int STRIPE_HEIGHT = 100;
    private int stripe_count;

    public StripesEffect() {
    }

    public void get_fps(out int desired_fps, out int min_fps) {
        desired_fps = StripesEffect.DESIRED_FPS;
        min_fps = StripesEffect.MIN_FPS;
    }

    public void start(Transitions.Visuals visuals, Transitions.Motion motion) {
      stripe_count = visuals.to_pos.height / STRIPE_HEIGHT + 1;
    }

    public bool needs_clear_background() {
        return true;
    }

    public void paint(Transitions.Visuals visuals, Transitions.Motion motion, Cairo.Context ctx,
        int width, int height, int frame_number) {
        double alpha = motion.get_alpha(frame_number);
        if (visuals.from_pixbuf != null) {
            Gdk.cairo_set_source_pixbuf(ctx, visuals.from_pixbuf, visuals.from_pos.x,
                visuals.from_pos.y);
            ctx.paint_with_alpha(1 - Math.fmin(1, alpha * 2));
        }
        
        if (visuals.to_pixbuf != null) {
            Gdk.cairo_set_source_pixbuf(ctx, visuals.to_pixbuf,visuals.to_pos.x, visuals.to_pos.y);
            int x = visuals.to_pos.x;
            int y = visuals.to_pos.y;
            for (int i = 0; i <= stripe_count; i++) {
                if (i % 2 == motion.direction) {
                    ctx.rectangle(x + visuals.to_pos.width - alpha * visuals.to_pos.width,
                        y + i * STRIPE_HEIGHT, x + visuals.to_pos.width, STRIPE_HEIGHT);
                } else {
                    ctx.rectangle(x, y + STRIPE_HEIGHT * i, visuals.to_pos.width * alpha,
                        STRIPE_HEIGHT);
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

