/* Copyright 2010 Maxim Kartashev
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Spit;

private class CrumbleEffectDescriptor : ShotwellTransitionDescriptor {
    public CrumbleEffectDescriptor(GLib.File resource_directory) {
        base(resource_directory);
    }

    public override unowned string get_id() {
        return "org.yorba.shotwell.transitions.crumble";
    }
    
    public override unowned string get_pluggable_name() {
        return _("Crumble");
    }
    
    public override Transitions.Effect create(Spit.HostInterface host) {
        return new CrumbleEffect();
    }
}

private class CrumbleEffect : Object, Transitions.Effect {
    private const int DESIRED_FPS = 25;
    private const int MIN_FPS = 15;
    
    private const int STRIPE_WIDTH = 10;
    
    private Cairo.ImageSurface[] from_stripes;
    private double[] accelerations;
    private int stripes_count;
    
    public CrumbleEffect() {
    }
    
    public void get_fps(out int desired_fps, out int min_fps) {
        desired_fps = CrumbleEffect.DESIRED_FPS;
        min_fps = CrumbleEffect.MIN_FPS;
    }
    
    public bool needs_clear_background() {
        return true;
    }
    
    public void start(Transitions.Visuals visuals, Transitions.Motion motion) {
        Rand rand = new Rand();
        
        // Cut original image into stripes of STRIPE_WIDTH width; also prepare
        // acceleration for each stripe.
        if (visuals.from_pixbuf != null) {
            stripes_count = visuals.from_pixbuf.width / STRIPE_WIDTH;
            from_stripes = new Cairo.ImageSurface[stripes_count];
            accelerations = new double[stripes_count];
            for (int i = 0; i < stripes_count; ++i) {
                from_stripes[i] = new Cairo.ImageSurface(Cairo.Format.RGB24, STRIPE_WIDTH,
                    visuals.from_pixbuf.height);
                Cairo.Context ctx = new Cairo.Context(from_stripes[i]);
                Gdk.cairo_set_source_pixbuf(ctx, visuals.from_pixbuf, - i * STRIPE_WIDTH, 0);
                ctx.paint();
                accelerations[i] = rand.next_double();
            }
        }
    }
    
    public void paint(Transitions.Visuals visuals, Transitions.Motion motion, Cairo.Context ctx,
        int width, int height, int frame_number) {
        double alpha = motion.get_alpha(frame_number);
        
        if (alpha < 0.5) {
            // First part: draw stripes that go down with pre-calculated acceleration
            alpha = alpha * 2; // stretch alpha to [0, 1]
            
            // tear down from_pixbuf first 
            for (int i = 0; i < stripes_count; ++i) {
                int x = visuals.from_pos.x + i * STRIPE_WIDTH;
                double a = alpha + alpha * accelerations[i];
                int y = visuals.from_pos.y + (int) (visuals.from_pixbuf.height * a * a);
                
                ctx.set_source_surface(from_stripes[i], x, y);
                ctx.paint();
            }
        } else if (visuals.to_pixbuf != null) {
            // Second part: fade in next image ("to_pixbuf")
            alpha = (alpha - 0.5) * 2; // stretch alpha to [0, 1]
            Gdk.cairo_set_source_pixbuf(ctx, visuals.to_pixbuf, visuals.to_pos.x, visuals.to_pos.y);
            ctx.paint_with_alpha(alpha);
        } else {
            // TODO: fade in background color
        }
    }
    
    public void advance(Transitions.Visuals visuals, Transitions.Motion motion, int frame_number) {
    }
    
    public void cancel() {
    }
}

