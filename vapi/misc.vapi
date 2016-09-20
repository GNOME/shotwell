namespace Workaround {
[CCode (cheader_filename = "glib.h", cname = "g_markup_collect_attributes", sentinel = "G_MARKUP_COLLECT_INVALID")]
extern bool markup_collect_attributes(string element_name,
        [CCode (array_length = false, array_null_terminated = true)]
        string[] attribute_names,
        [CCode (array_length = false, array_null_terminated = true)]
        string[] attribute_values, ...) throws GLib.MarkupError;
}
