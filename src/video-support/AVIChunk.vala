private class AVIChunk {
    private GLib.File file = null;
    private string section_name = "";
    private uint64 section_size = 0;
    private uint64 section_offset = 0;
    private GLib.DataInputStream input = null;
    private AVIChunk? parent = null;
    private const int MAX_STRING_TO_SECTION_LENGTH = 1024;

    public AVIChunk(GLib.File file) {
        this.file = file;
    }

    private AVIChunk.with_input_stream(GLib.DataInputStream input, AVIChunk parent) {
        this.input = input;
        this.parent = parent;
    }

    public void open_file() throws GLib.Error {
        close_file();
        input = new GLib.DataInputStream(file.read());
        input.set_byte_order(DataStreamByteOrder.LITTLE_ENDIAN);
        section_size = 0;
        section_offset = 0;
        section_name = "";
    }

    public void close_file() throws GLib.Error {
        if (null != input) {
            input.close();
            input = null;
        }
    }

    public void nonsection_skip(uint64 skip_amount) throws GLib.Error {
        skip_uint64(input, skip_amount);
    }

    public void skip(uint64 skip_amount) throws GLib.Error {
        advance_section_offset(skip_amount);
        skip_uint64(input, skip_amount);
    }

    public AVIChunk get_first_child_chunk() {
        return new AVIChunk.with_input_stream(input, this);
    }

    private void advance_section_offset(uint64 amount) {
        if ((section_offset + amount) > section_size)
            amount = section_size - section_offset;

        section_offset += amount;
        if (null != parent) {
            parent.advance_section_offset(amount);
        }
    }

    public uchar read_byte() throws GLib.Error {
        advance_section_offset(1);
        return input.read_byte();
    }

    public uint16 read_uint16() throws GLib.Error {
       advance_section_offset(2);
       return input.read_uint16();
    }

    public void read_chunk() throws GLib.Error {
        // don't use checked reads here because they advance the section offset, which we're trying
        // to determine here
        GLib.StringBuilder sb = new GLib.StringBuilder();
        sb.append_c((char) input.read_byte());
        sb.append_c((char) input.read_byte());
        sb.append_c((char) input.read_byte());
        sb.append_c((char) input.read_byte());
        section_name = sb.str;
        section_size = input.read_uint32();
        section_offset = 0;
    }

    public string read_name() throws GLib.Error {
        GLib.StringBuilder sb = new GLib.StringBuilder();
        sb.append_c((char) read_byte());
        sb.append_c((char) read_byte());
        sb.append_c((char) read_byte());
        sb.append_c((char) read_byte());
        return sb.str;
    }

    public void next_chunk() throws GLib.Error {
        skip(section_size_remaining());
        section_size = 0;
        section_offset = 0;
    }

    public string get_current_chunk_name() {
        return section_name;
    }

    public bool is_last_chunk() {
        return section_size == 0;
    }

    public uint64 section_size_remaining() {
        assert(section_size >= section_offset);
        return section_size - section_offset;
    }

    // Reads section contents into a string.
    public string section_to_string() throws GLib.Error {
        GLib.StringBuilder sb = new GLib.StringBuilder();
        while (section_offset < section_size) {
            sb.append_c((char) read_byte());
            if (sb.len > MAX_STRING_TO_SECTION_LENGTH) {
                return sb.str;
            }
        }
        return sb.str;
    }

}
