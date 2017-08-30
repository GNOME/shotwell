namespace WebP {
    [CCode (has_type_id = false)]
    public struct Data {
        [CCode (array_length_cname = "size")]
        public unowned uint8[] bytes;

        public size_t size;

        [CCode (cname = "WebPDataClear")]
        public void clear();
    }

    [CCode (cprefix = "WEBP_DEMUX_", cname = "WebPDemuxState")]
    public enum ParsingState {
        PARSE_ERROR,
        PARSING_HEADER,
        PARSED_HEADER,
        DONE
    }

    [CCode (cprefix = "WEBP_FF_")]
    public enum FormatFeature {
        FORMAT_FLAGS,
        CANVAS_WIDTH,
        CANVAS_HEIGHT,
        LOOP_COUNT,
        BACKGROUND_COLOR,
        FRAME_COUNT
    }

    [Compact]
    [CCode (free_function = "WebPDemuxDelete", cname = "WebPDemuxer", cheader_filename = "webp/demux.h", has_type_id = false)]
    public class Demuxer {
        [CCode (cname="WebPDemux")]
        public Demuxer(Data data);

        [CCode (cname="WebPDemuxPartial")]
        public Demuxer.partial(Data data, out ParsingState state);

        [CCode (cname="WebPDemuxGetI")]
        public uint32 get(FormatFeature feature);
    }
}
