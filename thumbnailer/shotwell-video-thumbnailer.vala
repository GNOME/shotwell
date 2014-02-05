/* Copyright 2011-2014 Yorba Foundation
 * 
 * This is a Vala-rewrite of GStreamer snapshot example. Adapted from earlier 
 * work from Wim Taymans.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

// Shotwell Thumbnailer takes in a video file and returns a thumbnail to stdout.  This is
// a replacement for totem-video-thumbnailer
class ShotwellThumbnailer {
    const string caps_string = """video/x-raw,format=RGB,pixel-aspect-ratio=1/1""";
    
    public static int main(string[] args) {
        Gst.Element pipeline, sink;
        int width, height;
        Gst.Sample sample;
        string descr;
        Gdk.Pixbuf pixbuf;
        int64 duration, position;
        Gst.StateChangeReturn ret;
        bool res;
        
        Gst.init(ref args);
        
        if (args.length != 2) {
            stdout.printf("usage: %s [filename]\n Writes video thumbnail to stdout\n", args[0]);
            return 1;
        }
        
        descr = "filesrc location=\"%s\" ! decodebin ! videoconvert ! videoscale ! ".printf(args[1]) +
            "appsink name=sink caps=\"%s\"".printf(caps_string);
        
        try {
            // Create new pipeline.
            pipeline = Gst.parse_launch(descr);
            
            // Get sink.
            sink = ((Gst.Bin) pipeline).get_by_name("sink");
            
            // Set to PAUSED to make the first frame arrive in the sink.
            ret = pipeline.set_state(Gst.State.PAUSED);
            if (ret == Gst.StateChangeReturn.FAILURE) {
                stderr.printf("Failed to play the file: couldn't set state\n");
                return 3;
            } else if (ret == Gst.StateChangeReturn.NO_PREROLL) {
                stderr.printf("Live sources not supported yet.\n");
                return 4;
            }
            
            // This can block for up to 5 seconds. If your machine is really overloaded,
            // it might time out before the pipeline prerolled and we generate an error. A
            // better way is to run a mainloop and catch errors there.
            ret = pipeline.get_state(null, null, 5 * Gst.SECOND);
            if (ret == Gst.StateChangeReturn.FAILURE) {
                stderr.printf("Failed to play the file: couldn't get state.\n");
                return 3;
            }

            /* get the duration */
            pipeline.query_duration (Gst.Format.TIME, out duration);

            position = 1 * Gst.SECOND;

            /* seek to the a position in the file. Most files have a black first frame so
             * by seeking to somewhere else we have a bigger chance of getting something
             * more interesting. An optimisation would be to detect black images and then
             * seek a little more */
            pipeline.seek_simple (Gst.Format.TIME, Gst.SeekFlags.KEY_UNIT | Gst.SeekFlags.FLUSH, position);

            /* get the preroll buffer from appsink, this block untils appsink really
             * prerolls */
            GLib.Signal.emit_by_name (sink, "pull-preroll", out sample, null);

            // if we have a buffer now, convert it to a pixbuf. It's possible that we
            // don't have a buffer because we went EOS right away or had an error.
            if (sample != null) {
                Gst.Buffer buffer;
                Gst.Caps caps;
                unowned Gst.Structure s;
                Gst.MapInfo mapinfo;
                uint8[]? pngdata;

                // Get the snapshot buffer format now. We set the caps on the appsink so
                // that it can only be an rgb buffer. The only thing we have not specified
                // on the caps is the height, which is dependent on the pixel-aspect-ratio
                // of the source material.
                caps = sample.get_caps();
                if (caps == null) {
                    stderr.printf("could not get snapshot format\n");
                    return 5;
                }
                
                s = caps.get_structure(0);
                
                // We need to get the final caps on the buffer to get the size.
                res = s.get_int("width", out width);
                res |= s.get_int("height", out height);
                if (!res) {
                    stderr.printf("Could not get snapshot dimension\n");
                    return 6;
                }

                buffer = sample.get_buffer();
                buffer.map(out mapinfo, Gst.MapFlags.READ);

                // Create pixmap from buffer and save, gstreamer video buffers have a stride
                // that is rounded up to the nearest multiple of 4.
                pixbuf = new Gdk.Pixbuf.from_data(mapinfo.data, Gdk.Colorspace.RGB, false, 8,
                    width, height, (((width * 3)+3)&~3), null);
                
                // Save the pixbuf.
                pixbuf.save_to_buffer(out pngdata, "png");
                stdout.write(pngdata);
                buffer.unmap(mapinfo);
            } else {
                stderr.printf("Could not make snapshot\n");
                return 10;
            }
            
            // cleanup and exit.
            pipeline.set_state(Gst.State.NULL);
            
        } catch (Error e) {
            stderr.printf(e.message);
            return 2;
        }
        
        return 0;
    }
}

