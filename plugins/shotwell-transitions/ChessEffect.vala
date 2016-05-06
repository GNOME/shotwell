/* Copyright 2013 Jens Bav
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Spit;

private class ChessEffectDescriptor : ShotwellTransitionDescriptor {
    public ChessEffectDescriptor(GLib.File resource_directory) {
        base(resource_directory);
    }

    public override unowned string get_id() {
        return "org.yorba.shotwell.transitions.chess";
    }

    public override unowned string get_pluggable_name() {
        return _("Chess");
    }

    public override Transitions.Effect create(HostInterface host) {
        return new ChessEffect();
    }
}

private class ChessEffect : Object, Transitions.Effect {
    private const int DESIRED_FPS = 25;
    private const int MIN_FPS = 10;
    private const int SQUARE_SIZE = 100;
    private double square_count_x;
    private double square_count_y;

    public ChessEffect() {
    }

    public void get_fps(out int desired_fps, out int min_fps) {
        desired_fps = ChessEffect.DESIRED_FPS;
        min_fps = ChessEffect.MIN_FPS;
    }

    public void start(Transitions.Visuals visuals, Transitions.Motion motion) {
      square_count_y = visuals.to_pos.height / SQUARE_SIZE + 2;
      square_count_x = visuals.to_pos.width / SQUARE_SIZE + 2;
    }

    public bool needs_clear_background() {
        return true;
    }

    public void paint(Transitions.Visuals visuals, Transitions.Motion motion, Cairo.Context ctx,
        int width, int height, int frame_number) {
        double alpha = motion.get_alpha(frame_number);
        double size = 2 * alpha * SQUARE_SIZE;
        if (visuals.from_pixbuf != null) {
            Gdk.cairo_set_source_pixbuf(ctx, visuals.from_pixbuf, visuals.from_pos.x,
                visuals.from_pos.y);
            ctx.paint_with_alpha(1 - alpha);
        }
        
        if (visuals.to_pixbuf != null) {
            Gdk.cairo_set_source_pixbuf(ctx, visuals.to_pixbuf,visuals.to_pos.x, visuals.to_pos.y);
            for (double y = 0; y <= square_count_y; y++) {
                for (double x = 0; x <= square_count_x; x++) {
                    double translation = (x+y) % 2 == 0 ? -1.5 * SQUARE_SIZE : 1.5 * SQUARE_SIZE;
                    if (motion.direction == Transitions.Direction.FORWARD) {
                        ctx.rectangle(visuals.to_pos.x + translation + x * SQUARE_SIZE,
                        visuals.to_pos.y + y * SQUARE_SIZE, size, SQUARE_SIZE);
                    } else {
                        ctx.rectangle(visuals.to_pos.x + visuals.to_pos.width + translation - x
                            * SQUARE_SIZE - size, visuals.to_pos.y + y * SQUARE_SIZE, size,
                            SQUARE_SIZE);
                    }
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
