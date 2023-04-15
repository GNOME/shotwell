/* Copyright 2016 Software Freedom Conservancy Inc.
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
        dynamic Gst.Element pipeline, sink;
        string descr;
        Gdk.Pixbuf pixbuf;
        uint8[]? pngdata;
        int64 duration, position;
        Gst.StateChangeReturn ret;
        OutputStream out;

        if (args.length != 3) {
            stdout.printf("usage: %s <filename> <output> \n Writes video thumbnail to output\n", args[0]);
            return 1;
        }

        var out_file = File.new_for_commandline_arg (args[2]);
        try {
            out = out_file.append_to(FileCreateFlags.NONE);
            debug("Writing thumbnail to %s", args[2]);
        } catch (Error err) {
            warning("Failed to append to image file %s", err.message);
            return 1;
        }

        if (Posix.nice (19) < 0) {
            debug ("Failed to reduce thumbnailer nice level. Continuing anyway");
        }

        Gst.init(ref args);

        var registry = Gst.Registry.@get ();
        var features = registry.feature_filter ((f) => {
            return f.get_name ().has_prefix ("vaapi");
        }, false);

        foreach (var feature in features) {
            debug ("Removing registry feature %s", feature.get_name ());
            registry.remove_feature (feature);
        }

        
        descr = "playbin uri=\"%s\" audio-sink=fakesink video-sink=\"gdkpixbufsink name=sink\"".printf(File.new_for_commandline_arg(args[1]).get_uri());
        
        try {
            // Create new pipeline.
            pipeline = Gst.parse_launch(descr);
            
            // Get sink.
            sink = pipeline.video_sink;
            
            // Set to PAUSED to make the first frame arrive in the sink.
            ret = pipeline.set_state(Gst.State.PAUSED);
            if (ret == Gst.StateChangeReturn.FAILURE) {
                warning("Failed to play the file: couldn't set state\n");
                return 3;
            } else if (ret == Gst.StateChangeReturn.NO_PREROLL) {
                warning("Live sources not supported yet.\n");
                return 4;
            }
            
            // This can block for up to 5 seconds. If your machine is really overloaded,
            // it might time out before the pipeline prerolled and we generate an error. A
            // better way is to run a mainloop and catch errors there.
            ret = pipeline.get_state(null, null, 5 * Gst.SECOND);
            if (ret == Gst.StateChangeReturn.FAILURE) {
                warning("Failed to play the file: couldn't get state.\n");
                return 3;
            }

            /* get the duration */
            if (!pipeline.query_duration (Gst.Format.TIME, out duration)) {
                warning("Failed to query file for duration\n");
                return 3;
            }

            position = 1 * Gst.SECOND;

            /* seek to the a position in the file. Most files have a black first frame so
             * by seeking to somewhere else we have a bigger chance of getting something
             * more interesting. An optimisation would be to detect black images and then
             * seek a little more */
            pipeline.seek_simple (Gst.Format.TIME, Gst.SeekFlags.KEY_UNIT | Gst.SeekFlags.FLUSH, position);

            ret = pipeline.get_state(null, null, 5 * Gst.SECOND);
            if (ret == Gst.StateChangeReturn.FAILURE) {
                warning("Failed to play the file: couldn't get state.\n");
                return 3;
            }

            sink.get ("last-pixbuf", out pixbuf);

            Gst.TagList tags;
            Signal.emit_by_name(pipeline, "get-video-tags", 0, out tags);
            var direction = Gdk.PixbufRotation.NONE;
            if (tags != null) {
                string orientation = null;
                if (tags.get_string_index (Gst.Tags.IMAGE_ORIENTATION, 0, out orientation)) {
                    if (orientation != null) {
                        switch (orientation) {
                            case "rotate-90":
                                direction = Gdk.PixbufRotation.CLOCKWISE;
                                break;
                            case "rotate-180":
                                direction = Gdk.PixbufRotation.UPSIDEDOWN;
                                break;
                            case "rotate-270":
                                direction = Gdk.PixbufRotation.COUNTERCLOCKWISE;
                                break;
                            default:
                                break;
                        }
                    }
                }
            }

            // Save the pixbuf.
            if (direction != Gdk.PixbufRotation.NONE) {
                pixbuf = pixbuf.rotate_simple(direction);
            }
            pixbuf.save_to_buffer(out pngdata, "png");
            out.write(pngdata);

            // cleanup and exit.
            pipeline.set_state(Gst.State.NULL);
            
        } catch (Error e) {
            warning(e.message);
            return 2;
        }
        
        return 0;
    }
}

