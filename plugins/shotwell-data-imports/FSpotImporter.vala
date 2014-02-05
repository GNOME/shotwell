/* Copyright 2009-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class FSpotService : Object, Spit.Pluggable, Spit.DataImports.Service {
    private const string ICON_FILENAME = "f-spot-24.png";

    private static Gdk.Pixbuf[] icon_pixbuf_set = null;

    public FSpotService(GLib.File resource_directory) {
        // initialize the database layer
        DataImports.FSpot.Db.init();
        if (icon_pixbuf_set == null)
            icon_pixbuf_set = Resources.load_icon_set(resource_directory.get_child(ICON_FILENAME));
    }
    
    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
            Spit.DataImports.CURRENT_INTERFACE);
    }

    public unowned string get_id() {
        return "org.yorba.shotwell.dataimports.fspot";
    }

    public unowned string get_pluggable_name() {
        return "F-Spot";
    }

    public void get_info(ref Spit.PluggableInfo info) {
        info.authors = "Bruno Girin";
        info.copyright = _("Copyright 2009-2014 Yorba Foundation");
        info.translators = Resources.TRANSLATORS;
        info.version = _VERSION;
        info.website_name = Resources.WEBSITE_NAME;
        info.website_url = Resources.WEBSITE_URL;
        info.is_license_wordwrapped = false;
        info.license = Resources.LICENSE;
        info.icons = icon_pixbuf_set;
    }

    public void activation(bool enabled) {
    }
    
    public Spit.DataImports.DataImporter create_data_importer(Spit.DataImports.PluginHost host) {
        return new DataImports.FSpot.FSpotDataImporter(this, host);
    }
}

namespace DataImports.FSpot {

internal const string SERVICE_NAME = "F-Spot";
internal const string SERVICE_WELCOME_MESSAGE =
    _("Welcome to the F-Spot library import service.\n\nPlease select a library to import, either by selecting one of the existing libraries found by Shotwell or by selecting an alternative F-Spot database file.");
internal const string SERVICE_WELCOME_MESSAGE_FILE_ONLY =
    _("Welcome to the F-Spot library import service.\n\nPlease select an F-Spot database file.");
internal const string FILE_IMPORT_LABEL =
    _("Manually select an F-Spot database file to import:");
internal const string ERROR_CANT_OPEN_DB_FILE =
    _("Cannot open the selected F-Spot database file: the file does not exist or is not an F-Spot database");
internal const string ERROR_UNSUPPORTED_DB_VERSION =
    _("Cannot open the selected F-Spot database file: this version of the F-Spot database is not supported by Shotwell");
internal const string ERROR_CANT_READ_TAGS_TABLE =
    _("Cannot read the selected F-Spot database file: error while reading tags table");
internal const string ERROR_CANT_READ_PHOTOS_TABLE =
    _("Cannot read the selected F-Spot database file: error while reading photos table");
internal const string MESSAGE_FINAL_SCREEN =
    _("Shotwell has found %d photos in the F-Spot library and is currently importing them. Duplicates will be automatically detected and removed.\n\nYou can close this dialog and start using Shotwell while the import is taking place in the background.");

public class FSpotImportableLibrary : Spit.DataImports.ImportableLibrary, GLib.Object {
    private File db_file;
    
    public FSpotImportableLibrary(File db_file) {
        this.db_file = db_file;
    }
    
    public File get_db_file() {
        return db_file;
    }
    
    public string get_display_name() {
        return _("F-Spot library: %s").printf(db_file.get_path());
    }
}

public class FSpotImportableItem : Spit.DataImports.ImportableMediaItem, GLib.Object {
    private DataImports.FSpot.Db.FSpotPhotoRow photo_row;
    private DataImports.FSpot.Db.FSpotPhotoVersionRow? photo_version_row;
    private DataImports.FSpot.Db.FSpotRollRow? roll_row;
    private FSpotImportableTag[] tags;
    private FSpotImportableEvent? event;
    private FSpotImportableRating rating;
    private string folder_path;
    private string filename;
    
    public FSpotImportableItem(
        DataImports.FSpot.Db.FSpotPhotoRow photo_row,
        DataImports.FSpot.Db.FSpotPhotoVersionRow? photo_version_row,
        DataImports.FSpot.Db.FSpotRollRow? roll_row,
        FSpotImportableTag[] tags,
        FSpotImportableEvent? event,
        bool is_hidden,
        bool is_favorite
    ) {
        this.photo_row = photo_row;
        this.photo_version_row = photo_version_row;
        this.roll_row = roll_row;
        this.tags = tags;
        this.event = event;
        if (photo_row.rating > 0)
            this.rating = new FSpotImportableRating(photo_row.rating);
        else if (is_hidden)
            this.rating = new FSpotImportableRating(FSpotImportableRating.REJECTED);
        else if (is_favorite)
            this.rating = new FSpotImportableRating(5);
        else
            this.rating = new FSpotImportableRating(FSpotImportableRating.UNRATED);
            
        // store path and filename
        folder_path = (photo_version_row != null) ?
            photo_version_row.base_path.get_path() :
            photo_row.base_path.get_path();
        filename = (photo_version_row != null) ?
            photo_version_row.filename :
            photo_row.filename;
        
        // In theory, neither field should be null at that point but belts
        // and braces don't hurt
        if (folder_path != null && filename != null) {
            // check if file exist and if not decode as URL
            File photo = File.new_for_path(folder_path).get_child(filename);
                
            // If file not found, parse as URI and store back
            if (!photo.query_exists()) {
                folder_path = decode_url(folder_path);
                filename = decode_url(filename);
            }
        }
    }
    
    public Spit.DataImports.ImportableTag[] get_tags() {
        Spit.DataImports.ImportableTag[] importable_tags = new Spit.DataImports.ImportableTag[0];
        foreach (FSpotImportableTag tag in tags)
            importable_tags += tag;
        return importable_tags;
    }
    
    public Spit.DataImports.ImportableEvent? get_event() {
        return event;
    }
    
    public string get_folder_path() {
        return folder_path;
    }
    
    public string get_filename() {
        return filename;
    }
    
    public string? get_title() {
        return (photo_row.description == null || photo_row.description == "") ? null : photo_row.description;
    }
    
    public Spit.DataImports.ImportableRating get_rating() {
        return rating;
    }
    
    private string decode_url(string url) {
        StringBuilder builder = new StringBuilder();
        for (int idx = 0; idx < url.length; ) {
            int cidx = url.index_of_char('%', idx);
            if (cidx > idx) {
                builder.append(url.slice(idx, cidx));
            }
            if (cidx >= 0) {
                if (cidx < url.length - 2) {
                    char c1 = url.get(cidx + 1);
                    char c2 = url.get(cidx + 2);
                    if (c1.isxdigit() && c1.isxdigit()) {
                        int ccode = 0x10 * c1.xdigit_value() + c2.xdigit_value();
                        builder.append_c((char)ccode);
                    }
                    idx = cidx + 3;
                } else {
                    idx = cidx + 1;
                }
            } else {
                builder.append(url.substring(idx));
                idx = url.length;
            }
        }
        return builder.str;
    }
}

public class FSpotImportableTag : Spit.DataImports.ImportableTag, GLib.Object {
    private DataImports.FSpot.Db.FSpotTagRow row;
    private FSpotImportableTag? parent;
    
    public FSpotImportableTag(DataImports.FSpot.Db.FSpotTagRow row, FSpotImportableTag? parent) {
        this.row = row;
        this.parent = parent;
    }
    
    public int64 get_id() {
        return row.tag_id;
    }
    
    public string get_name() {
        return row.name;
    }
    
    public Spit.DataImports.ImportableTag? get_parent() {
        return parent;
    }
    
    public FSpotImportableTag? get_fspot_parent() {
        return parent;
    }
    
    public string get_stock_icon() {
        return row.stock_icon;
    }
    
    public bool is_stock() {
        return (row.stock_icon.has_prefix(DataImports.FSpot.Db.FSpotTagsTable.PREFIX_STOCK_ICON));
    }
    
    public FSpotImportableEvent to_event() {
        return new FSpotImportableEvent(this.row);
    }
}

public class FSpotImportableEvent : Spit.DataImports.ImportableEvent, GLib.Object {
    private DataImports.FSpot.Db.FSpotTagRow row;
    
    public FSpotImportableEvent(DataImports.FSpot.Db.FSpotTagRow row) {
        this.row = row;
    }
    
    public string get_name() {
        return row.name;
    }
}

public class FSpotImportableRating : Spit.DataImports.ImportableRating, GLib.Object {
    public static const int REJECTED = -1;
    public static const int UNRATED = 0;
    
    private int rating_value;
    
    public FSpotImportableRating(int rating_value) {
        if (rating_value < -1)
            rating_value = -1;
        else if (rating_value > 5)
            rating_value = 5;
        this.rating_value = rating_value;
    }
    
    public bool is_rejected() {
        return (rating_value == REJECTED);
    }
    
    public bool is_unrated() {
        return (rating_value == UNRATED);
    }
    
    public int get_value() {
        return rating_value;
    }
}

internal class FSpotTagsCache : Object {
    private DataImports.FSpot.Db.FSpotTagsTable tags_table;
    private Gee.HashMap<int64?, FSpotImportableTag> tags_map;
    
    public FSpotTagsCache(DataImports.FSpot.Db.FSpotTagsTable tags_table) throws DatabaseError {
        this.tags_table = tags_table;
        tags_map = new Gee.HashMap<int64?, FSpotImportableTag> ();
    }
    
    public FSpotImportableTag get_tag(DataImports.FSpot.Db.FSpotTagRow tag_row) throws DatabaseError {
        FSpotImportableTag? tag = tags_map.get(tag_row.tag_id);
        if (tag != null) {
            return tag;
        } else {
            FSpotImportableTag? parent_tag = get_tag_from_id(tag_row.category_id);
            FSpotImportableTag new_tag = new FSpotImportableTag(tag_row, parent_tag);
            tags_map[tag_row.tag_id] = new_tag;
            return new_tag;
        }
    }
    
    private FSpotImportableTag? get_tag_from_id(int64 tag_id) throws DatabaseError {
        // check whether the tag ID is valid first, otherwise return null
        if (tag_id < 1)
            return null;
        FSpotImportableTag? tag = tags_map.get(tag_id);
        if (tag != null)
            return tag;
        DataImports.FSpot.Db.FSpotTagRow? tag_row = tags_table.get_by_id(tag_id);
        if (tag_row != null) {
            FSpotImportableTag? parent_tag = get_tag_from_id(tag_row.category_id);
            FSpotImportableTag new_tag = new FSpotImportableTag(tag_row, parent_tag);
            tags_map[tag_id] = new_tag;
            return new_tag;
        }
        return null;
    }
}

public class FSpotDataImporter : Spit.DataImports.DataImporter, GLib.Object {

    private weak Spit.DataImports.PluginHost host = null;
    private weak Spit.DataImports.Service service = null;
    private bool running = false;

    public FSpotDataImporter(Spit.DataImports.Service service,
        Spit.DataImports.PluginHost host) {
        debug("FSpotDataImporter instantiated.");
        this.service = service;
        this.host = host;
    }
    
    private bool is_running() {
        return running;
    }
    
    public Spit.DataImports.Service get_service() {
        return service;
    }

    public void start() {
        if (is_running())
            return;
        
        debug("FSpotDataImporter: starting interaction.");
        
        running = true;
        
        do_discover_importable_libraries();
    }

    public void stop() {
        debug("FSpotDataImporter: stopping interaction.");
        
        running = false;
    }
    
    // Actions and event implementation
    
    /**
     * Action that discovers importable libraries based on standard locations.
     */
    private void do_discover_importable_libraries() {
        Spit.DataImports.ImportableLibrary[] discovered_libraries =
            new Spit.DataImports.ImportableLibrary[0];
        
        File[] db_files = {
            // where the DB is in Ubuntu Lucid
            File.new_for_path(Environment.get_user_config_dir()).
                get_child("f-spot").get_child("photos.db"),
            // where it seems to be in Ubuntu Jaunty
            File.new_for_path(Environment.get_home_dir()).get_child(".gnome2").
                get_child("f-spot").get_child("photos.db"),
            // where it should really be if it followed the XDG spec
            File.new_for_path(Environment.get_user_data_dir()).
                get_child("f-spot").get_child("photos.db")
        };
        
        foreach (File db_file in db_files) {
            if (db_file.query_exists(null)) {
                discovered_libraries += new FSpotImportableLibrary(db_file);
                message("Discovered importable library: %s", db_file.get_path());
            }
        }
        
        host.install_library_selection_pane(
            (discovered_libraries.length > 0 ? SERVICE_WELCOME_MESSAGE : SERVICE_WELCOME_MESSAGE_FILE_ONLY),
            discovered_libraries,
            FILE_IMPORT_LABEL
        );
    }
    
    public void on_library_selected(Spit.DataImports.ImportableLibrary library) {
        on_file_selected(((FSpotImportableLibrary)library).get_db_file());
    }
    
    public void on_file_selected(File file) {
        DataImports.FSpot.Db.FSpotDatabase database;
        FSpotTagsCache tags_cache;
        Gee.ArrayList<DataImports.FSpot.Db.FSpotPhotoRow> all_photos;
        double progress_delta_per_photo = 1.0;
        double progress_plugin_to_host_ratio = 0.5;
        double current_progress = 0.0;
        try {
            database = new DataImports.FSpot.Db.FSpotDatabase(file);
        } catch(DatabaseError e) {
            debug("FSpotDataImporter: Can't open database file: %s".printf(e.message));
            host.post_error_message(ERROR_CANT_OPEN_DB_FILE);
            return;
        } catch(Spit.DataImports.DataImportError e) {
            debug("FSpotDataImporter: Unsupported F-Spot database version: %s".printf(e.message));
            host.post_error_message(ERROR_UNSUPPORTED_DB_VERSION);
            return;
        }
        try {
            tags_cache = new FSpotTagsCache(database.tags_table);
        } catch(DatabaseError e) {
            debug("FSpotDataImporter: Can't read tags table: %s".printf(e.message));
            host.post_error_message(ERROR_CANT_READ_TAGS_TABLE);
            return;
        }
        host.install_import_progress_pane(_("Preparing to import"));
        try {
            all_photos = database.photos_table.get_all();
        } catch(DatabaseError e) {
            debug("FSpotDataImporter: Can't read photos table: %s".printf(e.message));
            host.post_error_message(ERROR_CANT_READ_PHOTOS_TABLE);
            return;
        }
        if (all_photos.size > 0)
            progress_delta_per_photo = 1.0 / all_photos.size;
        foreach (DataImports.FSpot.Db.FSpotPhotoRow photo_row in all_photos) {
            bool hidden = false;
            bool favorite = false;
            FSpotImportableTag[] tags = new FSpotImportableTag[0];
            FSpotImportableEvent? event = null;
            DataImports.FSpot.Db.FSpotRollRow? roll_row = null;
            
            // TODO: We do not convert F-Spot events to Shotwell events because F-Spot's events
            // are essentially tags.  We would need to detect if the tag is an event (use
            // is_tag_event) and then assign the event to the photo ... since a photo can be
            // in multiple F-Spot events, we would need to pick one, and since their tags
            // are hierarchical, we would need to pick a name (probably the leaf)
            try {
                foreach (
                    DataImports.FSpot.Db.FSpotTagRow tag_row in
                    database.tags_table.get_by_photo_id(photo_row.photo_id)
                ) {
                    FSpotImportableTag tag = tags_cache.get_tag(tag_row);
                    if (is_tag_hidden(tag, database.hidden_tag_id))
                        hidden = true;
                    else if (is_tag_favorite(tag))
                        favorite = true;
                    else
                        tags += tag;
                }
            } catch(DatabaseError e) {
                // log the error and leave the tag list empty
                message("Failed to retrieve tags for photo ID %ld: %s", (long) photo_row.photo_id,
                    e.message);
            }
            
            try {
                roll_row = database.rolls_table.get_by_id(photo_row.roll_id);
            } catch (DatabaseError e) {
                // log the error and leave the roll row null
                message("Failed to retrieve roll for photo ID %ld: %s", (long) photo_row.photo_id,
                    e.message);
            }
            
            Spit.DataImports.ImportableMediaItem[] importable_items = new Spit.DataImports.ImportableMediaItem[0];
            try {
                Gee.ArrayList<DataImports.FSpot.Db.FSpotPhotoVersionRow> photo_versions =
                    database.photo_versions_table.get_by_photo_id(photo_row.photo_id);
                bool photo_versions_added = false;   // set to true if at least one version was added
                bool photo_versions_skipped = false; // set to true if at least one version was skipped due to missing file details
                foreach (DataImports.FSpot.Db.FSpotPhotoVersionRow photo_version_row in photo_versions) {
                    if (photo_version_row.base_path != null && photo_version_row.filename != null) {
                        importable_items += new FSpotImportableItem(
                            photo_row, photo_version_row, roll_row, tags, event, hidden, favorite
                        );
                        photo_versions_added = true;
                    } else {
                        photo_versions_skipped = true;
                    }
                }
                
                // Older versions of F-Spot (0.4.3.1 at least, perhaps later) did not maintain photo_versions,
                // this handles that case
                // It also handles the case when we had to skip any photo version due to missing
                // file details
                if (photo_versions_skipped || !photo_versions_added) {
                    if (photo_row.base_path != null && photo_row.filename != null) {
                        importable_items += new FSpotImportableItem(
                            photo_row, null, roll_row, tags, event, hidden, favorite
                        );
                    }
                }
            } catch (DatabaseError e) {
                // if we can't load the different versions, do the best we can
                // and create one photo from the photo row that was found earlier
                message("Failed to retrieve versions for photo ID %ld: %s", (long) photo_row.photo_id,
                    e.message);
                if (photo_row.base_path != null && photo_row.filename != null) {
                    importable_items += new FSpotImportableItem(
                        photo_row, null, roll_row, tags, event, hidden, favorite
                    );
                }
            }
            // If the importer is still running, import the items and loop,
            // otherwise break the loop
            if (running) {
                host.prepare_media_items_for_import(
                    importable_items,
                    current_progress + (progress_delta_per_photo * progress_plugin_to_host_ratio),
                    progress_delta_per_photo * (1 - progress_plugin_to_host_ratio),
                    null
                );
                current_progress += progress_delta_per_photo;
                host.update_import_progress_pane(current_progress);
            } else {
                break;
            }
        }
        host.finalize_import(on_imported_items_count);
    }
    
    public void on_imported_items_count(int imported_items_count) {
        host.install_static_message_pane(
            MESSAGE_FINAL_SCREEN.printf(imported_items_count),
            Spit.DataImports.PluginHost.ButtonMode.CLOSE
        );
    }
    
    private bool is_tag_event(FSpotImportableTag tag) {
        bool result = (DataImports.FSpot.Db.FSpotTagsTable.STOCK_ICON_EVENTS == tag.get_stock_icon());
        if (!result) {
            FSpotImportableTag? parent = tag.get_fspot_parent();
            if (parent == null)
                result = false;
            else
                result = is_tag_event(parent);
        }
        return result;
    }
    
    private bool is_tag_hidden(FSpotImportableTag tag, int64 hidden_tag_id) {
        bool result = (hidden_tag_id == tag.get_id());
        if (!result) {
            FSpotImportableTag? parent = tag.get_fspot_parent();
            if (parent == null)
                result = false;
            else
                result = is_tag_hidden(parent, hidden_tag_id);
        }
        return result;
    }
    
    private bool is_tag_favorite(FSpotImportableTag tag) {
        bool result = (DataImports.FSpot.Db.FSpotTagsTable.STOCK_ICON_FAV == tag.get_stock_icon());
        if (!result) {
            FSpotImportableTag? parent = tag.get_fspot_parent();
            if (parent == null)
                result = false;
            else
                result = is_tag_favorite(parent);
        }
        return result;
    }
}

} // namespace

