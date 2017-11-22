/* Copyright 2013 Jens Bav
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Spit;

private class SquaresEffectDescriptor : ShotwellTransitionDescriptor {
    public SquaresEffectDescriptor(GLib.File resource_directory) {
        base(resource_directory);
    }

    public override unowned string get_id() {
        return "org.yorba.shotwell.transitions.squares";
    }

    public override unowned string get_pluggable_name() {
        return _("Squares");
    }

    public override Transitions.Effect create(HostInterface host) {
        return new SquaresEffect();
    }
}

private class SquaresEffect : Object, Transitions.Effect {
    private const int DESIRED_FPS = 25;
    private const int MIN_FPS = 10;
    private const int SQUARE_SIZE = 100;
    private double square_count_x;
    private double square_count_y;

    public SquaresEffect() {
    }

    public void get_fps(out int desired_fps, out int min_fps) {
        desired_fps = SquaresEffect.DESIRED_FPS;
        min_fps = SquaresEffect.MIN_FPS;
    }

    public void start(Transitions.Visuals visuals, Transitions.Motion motion) {
      square_count_x = visuals.to_pos.width/SQUARE_SIZE + 1;
      square_count_y = visuals.to_pos.height/SQUARE_SIZE + 1;
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
            ctx.paint_with_alpha(1 - alpha);
        }
        
        if (visuals.to_pixbuf != null) {
            Gdk.cairo_set_source_pixbuf(ctx, visuals.to_pixbuf,visuals.to_pos.x, visuals.to_pos.y);
            for (double y = 0; y<=square_count_y; y++) {
                for (double x = 0; x <=square_count_x; x++) {
                    double size = SQUARE_SIZE * (Math.fmin(1, alpha + ((square_count_x - x)
                        / square_count_x + (square_count_y - y)/square_count_y)/2.5));

                    ctx.rectangle(visuals.to_pos.x + x * SQUARE_SIZE, visuals.to_pos.y + y
                        * SQUARE_SIZE, size, size);

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

