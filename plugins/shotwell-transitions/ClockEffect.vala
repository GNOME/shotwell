/* Copyright 2013 Jens Bav
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Spit;

private class ClockEffectDescriptor : ShotwellTransitionDescriptor {
    public ClockEffectDescriptor(GLib.File resource_directory) {
        base(resource_directory);
    }

    public override unowned string get_id() {
        return "org.yorba.shotwell.transitions.clock";
    }

    public override unowned string get_pluggable_name() {
        return _("Clock");
    }

    public override Transitions.Effect create(HostInterface host) {
        return new ClockEffect();
    }
}

private class ClockEffect : Object, Transitions.Effect {
    private const int DESIRED_FPS = 25;
    private const int MIN_FPS = 15;
    private const double TOP_RADIANT = 0.5 * Math.PI;

    public ClockEffect() {
    }

    public void get_fps(out int desired_fps, out int min_fps) {
        desired_fps = ClockEffect.DESIRED_FPS;
        min_fps = ClockEffect.MIN_FPS;
    }

    public void start(Transitions.Visuals visuals, Transitions.Motion motion) {
    }

    public bool needs_clear_background() {
        return true;
    }

    public void paint(Transitions.Visuals visuals, Transitions.Motion motion, Cairo.Context ctx,
        int width, int height, int frame_number) {
        double alpha = motion.get_alpha(frame_number);
        double start_angle = -TOP_RADIANT, stop_angle = -TOP_RADIANT;
        
        if (motion.direction == Transitions.Direction.FORWARD)
            stop_angle = alpha*Math.PI * 2 - TOP_RADIANT;
        else
            start_angle = (2 * (1-alpha)) * Math.PI - TOP_RADIANT;

        int radius = (int) Math.fmax(visuals.to_pos.width, visuals.to_pos.height);

        if (visuals.from_pixbuf != null) {
            Gdk.cairo_set_source_pixbuf(ctx, visuals.from_pixbuf, visuals.from_pos.x,
                visuals.from_pos.y);
            ctx.paint_with_alpha(1 - alpha);
        }
        
        if (visuals.to_pixbuf != null) {
            Gdk.cairo_set_source_pixbuf(ctx, visuals.to_pixbuf,visuals.to_pos.x, visuals.to_pos.y);

            int x = visuals.to_pos.x + (int) visuals.to_pos.width / 2;
            int y = visuals.to_pos.y + (int) visuals.to_pos.height / 2;

            ctx.move_to(x, y);
            ctx.arc (x, y, radius, start_angle, stop_angle);
            ctx.fill_preserve();
        }
    }

    public void advance(Transitions.Visuals visuals, Transitions.Motion motion, int frame_number) {
    }

    public void cancel() {
    }
}
