[CCode (cheader_filename = "webp/decode.h")]
namespace WebP {
    [CCode (array_length = false, cname="WebPDecodeRGBA")]
    public static uint8[] DecodeRGBA([CCode (array_length_pos=1)]uint8[] data, out int width, out int height);
}
