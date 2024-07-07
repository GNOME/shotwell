[CCode (cheader_filename = "webp/decode.h")]
namespace WebP {
    public struct BitstreamFeatures {
        int width;
        int height;
        bool has_alpha;
        bool has_animation;
        int format;
    }
    [CCode (array_length = false, cname="WebPDecodeRGBA")]
    public static uint8[] DecodeRGBA([CCode (array_length_pos=1.1)]uint8[] data, out int width, out int height);

    [CCode (cname = "WebPGetFeatures")]
    public static int GetFeatures([CCode (array_length_pos=1.1)]uint8[] data, out BitstreamFeatures featues);
}
