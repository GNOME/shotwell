/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Db {

public const string IN_MEMORY_NAME = ":memory:";

private string? filename = null;

// Passing null as the db_file will create an in-memory, non-persistent database.
public void preconfigure(File? db_file) {
    filename = (db_file != null) ? db_file.get_path() : IN_MEMORY_NAME;
}

public void init() throws Error {
    assert(filename != null);
    
    DatabaseTable.init(filename);
}

public void terminate() {
    DatabaseTable.terminate();
}

public enum VerifyResult {
    OK,
    FUTURE_VERSION,
    UPGRADE_ERROR,
    NO_UPGRADE_AVAILABLE
}

public VerifyResult verify_database(out string app_version, out int schema_version) {
    VersionTable version_table = VersionTable.get_instance();
    schema_version = version_table.get_version(out app_version);
    
    if (schema_version >= 0)
        debug("Database schema version %d created by app version %s", schema_version, app_version);
    
    if (schema_version == -1) {
        // no version set, do it now (tables will be created on demand)
        debug("Creating database schema version %d for app version %s", DatabaseTable.SCHEMA_VERSION,
            Resources.APP_VERSION);
        version_table.set_version(DatabaseTable.SCHEMA_VERSION, Resources.APP_VERSION);
        app_version = Resources.APP_VERSION;
        schema_version = DatabaseTable.SCHEMA_VERSION;
    } else if (schema_version > DatabaseTable.SCHEMA_VERSION) {
        // Back to the future
        return Db.VerifyResult.FUTURE_VERSION;
    } else if (schema_version < DatabaseTable.SCHEMA_VERSION) {
        // Past is present
        VerifyResult result = upgrade_database(schema_version);
        if (result != VerifyResult.OK)
            return result;
    }
    
    return VerifyResult.OK;
}

private VerifyResult upgrade_database(int input_version) {
    assert(input_version < DatabaseTable.SCHEMA_VERSION);
    
    int version = input_version;
    
    // No upgrade available from version 1.
    if (version == 1)
        return VerifyResult.NO_UPGRADE_AVAILABLE;
    
    message("Upgrading database from schema version %d to %d", version, DatabaseTable.SCHEMA_VERSION);
    
    //
    // Version 2: For all intents and purposes, the baseline schema version.
    // * Removed start_time and end_time from EventsTable
    //
    
    //
    // Version 3:
    // * Added flags column to PhotoTable
    //
    
    if (!DatabaseTable.has_column("PhotoTable", "flags")) {
        message("upgrade_database: adding flags column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "flags", "INTEGER DEFAULT 0"))
            return VerifyResult.UPGRADE_ERROR;
    }
    
    version = 3;
    
    //
    // ThumbnailTable(s) removed.
    //
    
    //
    // Version 4:
    // * Added file_format column to PhotoTable
    //
    
    if (!DatabaseTable.has_column("PhotoTable", "file_format")) {
        message("upgrade_database: adding file_format column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "file_format", "INTEGER DEFAULT 0"))
            return VerifyResult.UPGRADE_ERROR;
    }
    
    version = 4;
    
    //
    // Version 5:
    // * Added title column to PhotoTable
    //
    
    if (!DatabaseTable.has_column("PhotoTable", "title")) {
        message("upgrade_database: adding title column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "title", "TEXT"))
            return VerifyResult.UPGRADE_ERROR;
    }
    
    version = 5;
    
    //
    // Version 6:
    // * Added backlinks column to PhotoTable
    //
    
    if (!DatabaseTable.has_column("PhotoTable", "backlinks")) {
        message("upgrade_database: adding backlinks column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "backlinks", "TEXT"))
            return VerifyResult.UPGRADE_ERROR;
    }
    
    version = 6;
    
    //
    // * Ignore the exif_md5 column from PhotoTable.  Because removing columns with SQLite is
    //   painful, simply ignoring the column for now.  Keeping it up-to-date when possible in
    //   case a future requirement is discovered.
    //
    
    //
    // Version 7:
    // * Added BackingPhotoTable (which creates itself if needed)
    // * Added time_reimported and editable_id columns to PhotoTable
    //
    
    if (!DatabaseTable.has_column("PhotoTable", "time_reimported")) {
        message("upgrade_database: adding time_reimported column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "time_reimported", "INTEGER"))
            return VerifyResult.UPGRADE_ERROR;
    }
    
    if (!DatabaseTable.has_column("PhotoTable", "editable_id")) {
        message("upgrade_database: adding editable_id column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "editable_id", "INTEGER DEFAULT -1"))
            return VerifyResult.UPGRADE_ERROR;
    }
    
    version = 7;
    
    //
    // * Ignore the orientation column in BackingPhotoTable.  (See note above about removing
    //   columns from tables.)
    //
    
    //
    // Version 8:
    // * Added rating column to PhotoTable
    //

    if (!DatabaseTable.has_column("PhotoTable", "rating")) {
        message("upgrade_database: adding rating column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "rating", "INTEGER DEFAULT 0"))
            return VerifyResult.UPGRADE_ERROR;
    }
    
    //
    // Version 9:
    // * Added metadata_dirty flag to PhotoTable.  Default to 1 rather than 0 on upgrades so
    //   changes to metadata prior to upgrade will be caught by MetadataWriter.
    //
    
    if (!DatabaseTable.has_column("PhotoTable", "metadata_dirty")) {
        message("upgrade_database: adding metadata_dirty column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "metadata_dirty", "INTEGER DEFAULT 1"))
            return VerifyResult.UPGRADE_ERROR;
    }
    
    version = 9;
    
    //
    // Version 10:
    // * Added flags column to VideoTable
    //

    if (DatabaseTable.has_table("VideoTable") && !DatabaseTable.has_column("VideoTable", "flags")) {
        message("upgrade_database: adding flags column to VideoTable");
        if (!DatabaseTable.add_column("VideoTable", "flags", "INTEGER DEFAULT 0"))
            return VerifyResult.UPGRADE_ERROR;
    }

    version = 10;

    //
    // Version 11:
    // * Added primary_source_id column to EventTable
    //

    if (!DatabaseTable.has_column("EventTable", "primary_source_id")) {
        message("upgrade_database: adding primary_source_id column to EventTable");
        if (!DatabaseTable.add_column("EventTable", "primary_source_id", "TEXT"))
            return VerifyResult.UPGRADE_ERROR;
    }
    
    version = 11;
    
    //
    // Version 12:
    // * Added reason column to TombstoneTable
    //
    
    if (!DatabaseTable.ensure_column("TombstoneTable", "reason", "INTEGER DEFAULT 0",
        "upgrade_database: adding reason column to TombstoneTable")) {
        return VerifyResult.UPGRADE_ERROR;
    }
    
    version = 12;
    
    //
    // Version 13:
    // * Added RAW development columns to Photo table.
    //
    
    if (!DatabaseTable.has_column("PhotoTable", "developer")) {
        message("upgrade_database: adding developer column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "developer", "TEXT"))
            return VerifyResult.UPGRADE_ERROR;
    }
    
    if (!DatabaseTable.has_column("PhotoTable", "develop_shotwell_id")) {
        message("upgrade_database: adding develop_shotwell_id column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "develop_shotwell_id", "INTEGER DEFAULT -1"))
            return VerifyResult.UPGRADE_ERROR;
    }
    
    if (!DatabaseTable.has_column("PhotoTable", "develop_camera_id")) {
        message("upgrade_database: adding develop_camera_id column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "develop_camera_id", "INTEGER DEFAULT -1"))
            return VerifyResult.UPGRADE_ERROR;
    }
    
    if (!DatabaseTable.has_column("PhotoTable", "develop_embedded_id")) {
        message("upgrade_database: adding develop_embedded_id column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "develop_embedded_id", "INTEGER DEFAULT -1"))
            return VerifyResult.UPGRADE_ERROR;
    }
    
    version = 13;
    
    //
    // Version 14:
    // * Upgrades tag names in the TagTable for hierarchical tag support
    //
    
    if (input_version < 14)
        TagTable.upgrade_for_htags();
    
    version = 14;
    
    //
    // Version 15:
    // * Upgrades the version number to prevent Shotwell 0.11 users from opening
    //   Shotwell 0.12 databases. While the database schema hasn't changed,
    //   straighten was only partially implemented in 0.11 but is fully
    //   implemented in 0.12, so when 0.11 users open an 0.12 database with
    //   straightening information, they see partially and/or incorrectly
    //   rotated photos.
    //
    
    version =  15;
    
    //
    // Version 16:
    // * Migration of dconf settings data from /apps/shotwell to /org/yorba/shotwell.
    //
    //   The database itself doesn't change; this is to force the path migration to
    //   occur.
    //

    if (input_version < 16) {
        // Run the settings migrator to copy settings data from /apps/shotwell to /org/yorba/shotwell.
        // Please see https://mail.gnome.org/archives/desktop-devel-list/2011-February/msg00064.html
        GSettingsConfigurationEngine.run_gsettings_migrator();
    }
    
    version = 16;
    
    //
    // Version 17:
    // * Added comment column to PhotoTable and VideoTable
    //
    
    if (!DatabaseTable.has_column("PhotoTable", "comment")) {
        message("upgrade_database: adding comment column to PhotoTable");
        if (!DatabaseTable.add_column("PhotoTable", "comment", "TEXT"))
            return VerifyResult.UPGRADE_ERROR;
    }
    if (DatabaseTable.has_table("VideoTable") & !DatabaseTable.has_column("VideoTable", "comment")) {
        message("upgrade_database: adding comment column to VideoTable");
        if (!DatabaseTable.add_column("VideoTable", "comment", "TEXT"))
            return VerifyResult.UPGRADE_ERROR;
    }
    
    version = 17;
    
    //
    // Version 18:
    // * Added comment column to EventTable
    //
    
    if (!DatabaseTable.has_column("EventTable", "comment")) {
        message("upgrade_database: adding comment column to EventTable");
        if (!DatabaseTable.add_column("EventTable", "comment", "TEXT"))
            return VerifyResult.UPGRADE_ERROR;
    }
    
    version = 18;
    
    //
    // Version 19:
    // * Deletion and regeneration of camera-raw thumbnails from previous versions,
    //   since they're likely to be incorrect.
    //
    //   The database itself doesn't change; this is to force the thumbnail fixup to
    //   occur.
    //
    
    if  (input_version < 19) {
        Application.get_instance().set_raw_thumbs_fix_required(true);
    }
    
    version = 19;
    
    // 
    // Version 20:
    // * No change to database schema but fixing issue #6541 ("Saved searches should be aware of
    //   comments") added a new enumeration value that is stored in the SavedSearchTable. The
    //   presence of this heretofore unseen enumeration value will cause prior versions of
    //   Shotwell to yarf, so we bump the version here to ensure this doesn't happen
    //
    
    version = 20;
    
    //
    // Finalize the upgrade process
    //
    
    assert(version == DatabaseTable.SCHEMA_VERSION);
    VersionTable.get_instance().update_version(version, Resources.APP_VERSION);
    
    message("Database upgrade to schema version %d successful", version);
    
    return VerifyResult.OK;
}

}

