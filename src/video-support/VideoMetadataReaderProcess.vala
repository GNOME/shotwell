/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

using Gst;
using Gst.PbUtils;

int main(string[] args) {
    Intl.setlocale(GLib.LocaleCategory.NUMERIC, "C");

    var option_context = new OptionContext("- shotwell video metadata reader helper binary");
    option_context.set_help_enabled(true);
    option_context.add_group(Gst.init_get_option_group());

    double clip_duration;
    GLib.DateTime timestamp = null;

    try {
        option_context.parse(ref args);

        if (args.length < 2)
            throw new IOError.INVALID_ARGUMENT("Missing URI");

        var f = File.new_for_commandline_arg (args[1]);

        Gst.PbUtils.Discoverer d = new Gst.PbUtils.Discoverer((Gst.ClockTime) (Gst.SECOND * 5));
        Gst.PbUtils.DiscovererInfo info = d.discover_uri(f.get_uri());

        clip_duration = ((double) info.get_duration()) / 1000000000.0;

        // Get creation time.
        // TODO: Note that TAG_DATE can be changed to TAG_DATE_TIME in the future
        // (and the corresponding output struct) in order to implement #2836.
        Date? video_date = null;
        if (info.get_tags() != null && info.get_tags().get_date(Gst.Tags.DATE, out video_date)) {
            // possible for get_date() to return true and a null Date
            if (video_date != null) {
                timestamp = new GLib.DateTime.local(video_date.get_year(), video_date.get_month(),
                    video_date.get_day(), 0, 0, 0);
            }
        }

        print("%.3f\n", clip_duration);
        if (timestamp != null) {
            print("%s\n", timestamp.format_iso8601());
        } else {
            print("none\n");
        }
    } catch (Error error) {
        critical("Failed to parse options: %s", error.message);

        return 1;
    }

    return 0;
}
