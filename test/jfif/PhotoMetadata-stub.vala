// SPDX-FileCopyrightText: Software Freedom Conservancy Inc.
// SPDX-License-Identifier: LGPL-2.1-or-later
// stub class for photo metadata needed by the JFIF Support test
public class PhotoMetadata {
    // Counts read_from_file() calls, so tests can check when a sniffer parses metadata
    public static int read_count = 0;
    public PhotoMetadata() { }
    public void read_from_file(File file) throws Error { read_count++; }
    public void write_to_file(File file) throws Error { }
    public string? thumbnail_hash() { return null; }
}
