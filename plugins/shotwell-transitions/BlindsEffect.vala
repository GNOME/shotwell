/* Copyright 2013 Jens Bav
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Spit;

private class BlindsEffectDescriptor : ShotwellTransitionDescriptor {
    public BlindsEffectDescriptor(GLib.File resource_directory) {
        base(resource_directory);
    }

    public override unowned string get_id() {
        return "org.yorba.shotwell.transitions.blinds";
    }

    public override unowned string get_pluggable_name() {
        return _("Blinds");
    }

    public override Transitions.Effect create(HostInterface host) {
        return new BlindsEffect();
    }
}

private class BlindsEffect : Object, Transitions.Effect {
    private const int DESIRED_FPS = 30;
    private const int MIN_FPS = 15;

    private const int BLIND_WIDTH = 50;
    private int current_blind_width;
   
    private Cairo.ImageSurface[] to_blinds;
    private int blind_count;

    public BlindsEffect() {
    }

    public void get_fps(out int desired_fps, out int min_fps) {
        desired_fps = BlindsEffect.DESIRED_FPS;
        min_fps = BlindsEffect.MIN_FPS;
    }

    public bool needs_clear_background() {
        return true;
    }

    public void start(Transitions.Visuals visuals, Transitions.Motion motion) {
        if (visuals.from_pixbuf != null) {
            blind_count = visuals.to_pixbuf.width / BLIND_WIDTH;
            current_blind_width =
                (int) Math.ceil((double) visuals.to_pixbuf.width / (double) blind_count);
              
            to_blinds = new Cairo.ImageSurface[blind_count];
            
            for (int i = 0; i < blind_count; ++i) {
                to_blinds[i] = new Cairo.ImageSurface(Cairo.Format.RGB24, current_blind_width,
                    visuals.to_pixbuf.height);
                Cairo.Context ctx = new Cairo.Context(to_blinds[i]);
                Gdk.cairo_set_source_pixbuf(ctx, visuals.to_pixbuf, -i * current_blind_width, 0);
                ctx.paint();
            }
        }
    }

    public void paint(Transitions.Visuals visuals, Transitions.Motion motion, Cairo.Context ctx,
        int width, int height, int frame_number) {
        double alpha = motion.get_alpha(frame_number);
        int y = visuals.to_pos.y;
        int x = visuals.to_pos.x;

        if (visuals.from_pixbuf != null){
            Gdk.cairo_set_source_pixbuf(ctx, visuals.from_pixbuf, visuals.from_pos.x,
                visuals.from_pos.y);
            ctx.paint_with_alpha(1 - alpha * 2);
        }
        
        for (int i = 0; i < blind_count; ++i) {
            ctx.set_source_surface(to_blinds[i], x + i * current_blind_width, y);
            ctx.rectangle(x + i * current_blind_width, y, current_blind_width * (alpha + 0.5),
                visuals.to_pixbuf.height);
            ctx.fill();
        }
        
        ctx.clip();
        ctx.paint();
    }

    public void advance(Transitions.Visuals visuals, Transitions.Motion motion, int frame_number) {
    }

    public void cancel() {
    }
}
