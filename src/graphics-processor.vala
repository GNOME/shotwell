static string? input_file = null;
static string? output_file = null;
static string? pipeline = null;
static bool auto_enhance = false;
static string? format = null;
static int jobs = -1;

const GLib.OptionEntry[] options = {
    { "input", 'i', 0, GLib.OptionArg.FILENAME, ref input_file, "FILE to process", "FILE" },
    { "output", 'o', 0, GLib.OptionArg.FILENAME, ref output_file, "destination FILE", "FILE" },
    { "pipeline", 'p', 0, GLib.OptionArg.FILENAME, ref pipeline, "graphics PIPELINE to run", "PIPELINE" },
    { "auto-enance", 'a', 0, GLib.OptionArg.NONE, ref auto_enhance, "run auto-enhance on input file", null },
    { "format", 'f', 0, GLib.OptionArg.STRING, ref format, "Save output file in specific format [png, jpeg (default)]", null},
    { "jobs", 'j', 0, GLib.OptionArg.INT, ref jobs, "Number of parallel jobs to run on an image", null },
    { null, 0, 0, GLib.OptionArg.NONE, null, null, null }
};

Gee.HashMap<string, KeyValueMap>? marshall_all_transformations(string filename) {
    try {
        var keyfile = new KeyFile();
        if (filename.has_prefix("string:")) {
            var data = "[adjustments]\n" + filename.substring(7).replace("&", "\n");
            keyfile.load_from_data(data, data.length, KeyFileFlags.NONE);
        } else {
            keyfile.load_from_file(filename, KeyFileFlags.NONE);
        }

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

int main(string[] args) {
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

    if (input_file == null || output_file == null) {
        print("You need to provide and input and output file\n");
        print(ctx.get_help(true, null));

        return 1;
    }

    if (auto_enhance == false && pipeline == null) {
        print("No operation provided. Nothing to do.\n");

        return 0;
    }

    Gdk.Pixbuf? src = null;
    try {
        src = new Gdk.Pixbuf.from_file(input_file);
    } catch (Error err) {
        error ("%s", err.message);
    }

    var output = src.copy();
    PixelTransformationBundle? adjustments = null;

    if (pipeline != null) {
        var transformations = marshall_all_transformations(pipeline);

        adjustments = new PixelTransformationBundle();
        var map = transformations.get("adjustments");
        if (map == null) {
            adjustments.set_to_identity();
        } else {
            adjustments.load(map);
        }
    }

    if (auto_enhance) {
        adjustments = AutoEnhance.create_auto_enhance_adjustments(src);
    }

    var transformer = adjustments.generate_transformer();
    var timer = new Timer();
    transformer.transform_to_other_pixbuf(src, output, null, jobs);
    var elapsed = timer.elapsed();

    print("Transformation took %f\n", elapsed);

    // Trz to guess output format. If it's not PNG, assume JPEG.
    if (format == null) {
        var content_type = ContentType.guess(output_file, null, null);
        if (content_type == "image/png") {
            format = "png";
        }

        format = "jpeg";
    }

    try {
        output.save(output_file, format, null);
    } catch (Error err) {
        error("%s", err.message);
    }

    return 0;
}
