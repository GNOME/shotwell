static string input_file;
static string output_file;
static string pipeline;
static bool auto_enhance;

const GLib.OptionEntry[] options = {
    { "input", 'i', 0, GLib.OptionArg.FILENAME, ref input_file, "FILE to process", "FILE" },
    { "output", 'o', 0, GLib.OptionArg.FILENAME, ref output_file, "destination FILE", "FILE" },
    { "pipeline", 'p', 0, GLib.OptionArg.FILENAME, ref pipeline, "graphics PIPELINE to run", "PIPELINE" },
    { "auto-enance", 'a', 0, GLib.OptionArg.NONE, ref auto_enhance, "run auto-enhance on input file", null },
    { null, 0, 0, GLib.OptionArg.NONE, null, null, null }
};

Gee.HashMap<string, KeyValueMap>? marshall_all_transformations(string filename) {
    try {
        var keyfile = new KeyFile();
        keyfile.load_from_file(filename, KeyFileFlags.NONE);
        var map = new Gee.HashMap<string, KeyValueMap>();

        var objects = keyfile.get_groups();
        foreach (var object in objects) {
            var keys = keyfile.get_keys(object);
            if (keys == null || keys.length == 0) {
                continue;
            }

            var key_map = new KeyValueMap(object);
            foreach (var key in keys) {
                key_map.set_string(key, keyfile.get_string(object, key));
            }
            map.set(object, key_map);
        }

        return map;
    } catch (Error err) {
        error("%s", err.message);
    }
}

int main(string[] args)
{
    var ctx = new OptionContext("- Apply shotwell transformations on commandline");
    ctx.set_help_enabled(true);
    ctx.set_ignore_unknown_options(true);
    ctx.add_main_entries(options, null);

    try {
        ctx.parse(ref args);
    } catch (Error error) {
        print(ctx.get_help(true, null));

        return 1;
    }

    Gdk.Pixbuf? src = null;
    try {
        src = new Gdk.Pixbuf.from_file(input_file);
    } catch (Error err) {
        error ("%s", err.message);
    }

    var output = src.copy();

    var transformations = marshall_all_transformations(pipeline);

    var adjustments = new PixelTransformationBundle();
    var map = transformations.get("adjustments");
    if (map == null) {
        adjustments.set_to_identity();
    } else {
        adjustments.load(map);
    }

    var transformer = adjustments.generate_transformer();
    var timer = new Timer();
    transformer.transform_to_other_pixbuf(src, output, null);
    var elapsed = timer.elapsed();

    print("Transformation took %f\n", elapsed);

    try {
        output.save(output_file, "jpeg", "quality", "100", null);
    } catch (Error err) {
        error("%s", err.message);
    }

    return 0;
}
