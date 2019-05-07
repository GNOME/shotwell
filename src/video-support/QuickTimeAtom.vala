private class QuickTimeAtom {
    private GLib.File file = null;
    private string section_name = "";
    private uint64 section_size = 0;
    private uint64 section_offset = 0;
    private GLib.DataInputStream input = null;
    private QuickTimeAtom? parent = null;

    public QuickTimeAtom(GLib.File file) {
        this.file = file;
    }

    private QuickTimeAtom.with_input_stream(GLib.DataInputStream input, QuickTimeAtom parent) {
        this.input = input;
        this.parent = parent;
    }

    public void open_file() throws GLib.Error {
        close_file();
        input = new GLib.DataInputStream(file.read());
        input.set_byte_order(DataStreamByteOrder.BIG_ENDIAN);
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

    private void advance_section_offset(uint64 amount) {
        section_offset += amount;
        if (null != parent) {
            parent.advance_section_offset(amount);
        }
    }

    public QuickTimeAtom get_first_child_atom() {
        // Child will simply have the input stream
        // but not the size/offset.  This works because
        // child atoms follow immediately after a header,
        // so no skipping is required to access the child
        // from the current position.
        return new QuickTimeAtom.with_input_stream(input, this);
    }

    public uchar read_byte() throws GLib.Error {
        advance_section_offset(1);
        return input.read_byte();
    }

    public uint32 read_uint32() throws GLib.Error {
        advance_section_offset(4);
        return input.read_uint32();
    }

    public uint64 read_uint64() throws GLib.Error {
        advance_section_offset(8);
        return input.read_uint64();
    }

    public void read_atom() throws GLib.Error {
        // Read atom size.
        section_size = read_uint32();

        // Read atom name.
        GLib.StringBuilder sb = new GLib.StringBuilder();
        sb.append_c((char) read_byte());
        sb.append_c((char) read_byte());
        sb.append_c((char) read_byte());
        sb.append_c((char) read_byte());
        section_name = sb.str;

        // Check string.
        if (section_name.length != 4) {
            throw new IOError.NOT_SUPPORTED("QuickTime atom name length is invalid for %s",
                file.get_path());
        }
        for (int i = 0; i < section_name.length; i++) {
            if (!section_name[i].isprint()) {
                throw new IOError.NOT_SUPPORTED("Bad QuickTime atom in file %s", file.get_path());
            }
        }

        if (1 == section_size) {
            // This indicates the section size is a 64-bit
            // value, specified below the atom name.
            section_size = read_uint64();
        }
    }

    private void skip(uint64 skip_amount) throws GLib.Error {
        skip_uint64(input, skip_amount);
    }

    public uint64 section_size_remaining() {
        assert(section_size >= section_offset);
        return section_size - section_offset;
    }

    public void next_atom() throws GLib.Error {
        skip(section_size_remaining());
        section_size = 0;
        section_offset = 0;
    }

    public string get_current_atom_name() {
        return section_name;
    }

    public bool is_last_atom() {
        return 0 == section_size;
    }

}
