[CCode (cheader_filename = "libheif/heif.h")]
namespace Heif {
    [CCode (
        cname="struct heif_error",
        free_function="(void)",
        destroy_function="(void)"
    )]
    [SimpleType]
    public struct Error {
        [CCode (cname="heif_error_Ok")]
        public const int OK;
        public int code;
        public int subcode;
        public string message;
    }

    [Compact]
    [CCode (
        cname="struct heif_context",
        free_function="heif_context_free"
    )]
    public class Context {
        [CCode (cname="heif_context_alloc")]
        public Context();
        public Error read_from_memory_without_copy (uint8[] buffer, void *param = null);
        public Error get_primary_image_handle(out unowned ImageHandle hdl);
    }

    [CCode (cname="enum heif_colorspace")]
    public enum Colorspace {
        [CCode (cname="heif_colorspace_RGB")]
        RGB
    }

    [CCode (cname="enum heif_chroma")]
    public enum Chroma {
        [CCode (cname="heif_chroma_interleaved_RGBA")]
        INTERLEAVED_RGBA
    }

    [CCode (cname="enum heif_channel")]
    public enum Channel {
        [CCode (cname="heif_channel_interleaved")]
        INTERLEAVED
    }

    [Compact]
    [CCode (
        cname="struct heif_image_context",
        free_function="heif_image_context_release"
    )]
    public class ImageHandle {
        [CCode (cname="heif_decode_image")]
        public Error decode_image(out unowned Heif.Image image, Heif.Colorspace colorspace, Heif.Chroma chroma, void *options = null);
    }

    [Compact]
    [CCode (
        cname="struct heif_image",
        free_function="heif_image_release"
    )]
    public class Image {
        public int get_width(Heif.Channel channel);
        public int get_height(Heif.Channel channel);
        [CCode (array_length = false)]
        public uint8[] get_plane_readonly(Heif.Channel channel, out int stride);
    }
}
