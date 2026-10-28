/* SPDX-FileCopyrightText: 2016 Software Freedom Conservancy Inc.
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

public abstract class MediaMetadata {
    public abstract void read_from_file(File file) throws Error;

    public abstract MetadataDateTime? get_creation_date_time();

    public abstract string? get_title();

    public abstract string? get_comment();
}
