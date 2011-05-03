/* Copyright 2011 Yorba Foundation
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
    const string caps_string = """video/x-raw-rgb,bpp = (int) 32, depth = (int) 32,
                                      endianness = (int) BIG_ENDIAN,
                                      red_mask = (int)   0xFF000000,
                                      green_mask = (int) 0x00FF0000,
                                      blue_mask = (int)  0x0000FF00,
                                      width = (int) [ 1, max ],
                                      height = (int) [ 1, max ],
                                      framerate = (fraction) [ 0, max ]""";
    
    public static int main(string[] args) {
        Gst.Element pipeline, sink;
        int width, height;
        Gst.Buffer buffer;
        string descr;
        Gdk.Pixbuf pixbuf;
        int64 position;
        Gst.StateChangeReturn ret;
        bool res;
        
        Gst.init(ref args);
        
        if (args.length != 2) {
            stdout.printf("usage: %s [filename]\n Writes video thumbnail to stdout\n", args[0]);
            return 1;
        }
        
        descr = "filesrc location=\"%s\" ! decodebin2 ! ffmpegcolorspace ! ".printf(args[1]) + 
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
            
            // Seek to the a position in the file. Most files have a black first frame so
            // by seeking to somewhere else we have a bigger chance of getting something
            // more interesting. An optimization would be to detect black images and then
            // seek a little more.
            position = (int64) (Gst.Format.PERCENT_MAX * 0.05);
            pipeline.seek_simple(Gst.Format.PERCENT, Gst.SeekFlags.KEY_UNIT | Gst.SeekFlags.FLUSH , position);
            
            // Get the preroll buffer from appsink, this block untils appsink really
            // prerolls.
            GLib.Signal.emit_by_name(sink, "pull-preroll", out buffer, null);
            
            // if we have a buffer now, convert it to a pixbuf. It's possible that we
            // don't have a buffer because we went EOS right away or had an error.
            if (buffer != null) {
                Gst.Caps caps;
                Gst.Structure s;

                // Get the snapshot buffer format now. We set the caps on the appsink so
                // that it can only be an rgb buffer. The only thing we have not specified
                // on the caps is the height, which is dependant on the pixel-aspect-ratio
                // of the source material.
                caps = buffer.get_caps();
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
                
                // Create pixmap from buffer and save, gstreamer video buffers have a stride
                // that is rounded up to the nearest multiple of 4.
                pixbuf = new Gdk.Pixbuf.from_data(buffer.data, Gdk.Colorspace.RGB, true, 8, 
                    width, height, width * 4, null);
                
                // Save the pixbuf.
                pixbuf.save("/dev/stdout", "png");
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

