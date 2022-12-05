/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class VideoImportParams {
    // IN:
    public File file;
    public ImportID import_id = ImportID();
    public string? md5;
    public DateTime? exposure_time_override;

    // IN/OUT:
    public Thumbnails? thumbnails;

    // OUT:
    public VideoRow row = new VideoRow();

    public VideoImportParams(File file, ImportID import_id, string? md5,
        Thumbnails? thumbnails = null, DateTime? exposure_time_override = null) {
        this.file = file;
        this.import_id = import_id;
        this.md5 = md5;
        this.thumbnails = thumbnails;
        this.exposure_time_override = exposure_time_override;
    }
}
