/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public abstract class MediaMetadata {
    public abstract void read_from_file(File file) throws Error;

    public abstract MetadataDateTime? get_creation_date_time();

    public abstract string? get_title();

    public abstract string? get_comment();
}
