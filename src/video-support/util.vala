// Breaks a uint64 skip amount into several smaller skips.
public void skip_uint64(InputStream input, uint64 skip_amount) throws GLib.Error {
    while (skip_amount > 0) {
        // skip() throws an error if the amount is too large, so check against ssize_t.MAX
        if (skip_amount >= ssize_t.MAX) {
            input.skip(ssize_t.MAX);
            skip_amount -= ssize_t.MAX;
        } else {
            input.skip((size_t) skip_amount);
            skip_amount = 0;
        }
    }
}
