/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

// defined by ./configure or Makefile and included by gcc -D
extern const string _PREFIX;
extern const string _VERSION;
extern const string GETTEXT_PACKAGE;
extern const string _LIB;
extern const string _LIBEXECDIR;
extern const string? _GIT_VERSION;

namespace Resources {
    public const string APP_TITLE = "Shotwell";
    public const string APP_LIBRARY_ROLE = _("Photo Manager");
    public const string APP_DIRECT_ROLE = _("Photo Viewer");
    public const string APP_VERSION = _VERSION;

#if _GITVERSION
    public const string? GIT_VERSION = _GIT_VERSION;
#else
    public const string? GIT_VERSION = null;
#endif

    public const string COPYRIGHT = _("Copyright 2016 Software Freedom Conservancy Inc.");
    public const string APP_GETTEXT_PACKAGE = GETTEXT_PACKAGE;
    
    public const string HOME_URL = "https://wiki.gnome.org/Apps/Shotwell";
    public const string FAQ_URL = "https://wiki.gnome.org/Apps/Shotwell/FAQ";
    public const string BUG_DB_URL = "https://wiki.gnome.org/Apps/Shotwell/ReportingABug";
    public const string DIR_PATTERN_URI_SYSWIDE = "help:shotwell/other-files";

    private const string LIB = _LIB;
    private const string LIBEXECDIR = _LIBEXECDIR;

    public const string PREFIX = _PREFIX;

    public const double TRANSIENT_WINDOW_OPACITY = 0.90;
    
    public const int DEFAULT_ICON_SCALE = 24;
   
    public const string[] AUTHORS = { 
        "Jim Nelson <jim@yorba.org>", 
        "Lucas Beeler <lucas@yorba.org>",
        "Allison Barlow <allison@yorba.org>",
        "Eric Gregory <eric@yorba.org>",
        "Clinton Rogers <clinton@yorba.org>",
        null
    };

    public const string LICENSE = """
Shotwell is free software; you can redistribute it and/or modify it under the 
terms of the GNU Lesser General Public License as published by the Free 
Software Foundation; either version 2.1 of the License, or (at your option) 
any later version.

Shotwell is distributed in the hope that it will be useful, but WITHOUT 
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for 
more details.

You should have received a copy of the GNU Lesser General Public License 
along with Shotwell; if not, write to the Free Software Foundation, Inc., 
51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
""";

    public const string CLOCKWISE = "object-rotate-right-symbolic";
    public const string COUNTERCLOCKWISE = "object-rotate-left-symbolic";
    public const string HFLIP = "object-flip-horizontal-symbolic";
    public const string VFLIP = "object-flip-vertical-symbolic";
    public const string STRAIGHTEN = "straighten-symbolic";
    public const string ADJUST = "image-adjust-color-symbolic";
    public const string IMPORT = "image-x-generic-symbolic";
    public const string IMPORT_ALL = "filter-photos-symbolic";
    public const string ENHANCE = "image-auto-adjust-symbolic";
    public const string PUBLISH = "send-to-symbolic";
    public const string FACES_TOOL = "avatar-default-symbolic";

    public const string GO_NEXT = "go-next-symbolic";
    public const string GO_PREVIOUS = "go-previous-symbolic";

    public const string ICON_ABOUT_LOGO = "about-celle.jpg";
    public const string ICON_GENERIC_PLUGIN = "application-x-addon-symbolic";
    public const string ICON_SLIDESHOW_EXTENSION_POINT = "slideshow-extension-point";
    public const int ICON_FILTER_REJECTED_OR_BETTER_FIXED_SIZE = 32;
    public const int ICON_FILTER_UNRATED_OR_BETTER_FIXED_SIZE = 16;
    public const int ICON_ZOOM_SCALE = 16;

    public const string ICON_CAMERAS = "camera-photo-symbolic";
    public const string ICON_EVENTS = "multiple-events-symbolic";
    public const string ICON_ONE_EVENT = "one-event-symbolic";
    public const string ICON_NO_EVENT = "no-event-symbolic";
    public const string ICON_ONE_TAG = "one-tag-symbolic";
    public const string ICON_TAGS = "multiple-tags-symbolic";
    public const string ICON_FOLDER = "folder-symbolic";
    public const string ICON_FOLDER_DOCUMENTS = "folder-documents-symbolic";
    public const string ICON_IMPORTING = "go-down-symbolic";
    public const string ICON_LAST_IMPORT = "document-open-recent-symbolic";
    public const string ICON_MISSING_FILES = "process-stop-symbolic";
    public const string ICON_PHOTOS = "shotwell-symbolic";
    public const string ICON_SINGLE_PHOTO = "image-x-generic-symbolic";
    public const string ICON_TRASH_EMPTY = "user-trash-symbolic";
    public const string ICON_TRASH_FULL = "user-trash-full-symbolic";
    public const string ICON_ONE_FACE = "avatar-default-symbolic";
    public const string ICON_FACES = "avatar-default-symbolic";

    public const string ROTATE_CW_MENU = _("Rotate _Right");
    public const string ROTATE_CW_LABEL = _("Rotate");
    public const string ROTATE_CW_FULL_LABEL = _("Rotate Right");
    public const string ROTATE_CW_TOOLTIP = _("Rotate the photos right (press Ctrl to rotate left)");
    
    public const string ROTATE_CCW_MENU = _("Rotate _Left");
    public const string ROTATE_CCW_LABEL = _("Rotate");
    public const string ROTATE_CCW_FULL_LABEL = _("Rotate Left");
    public const string ROTATE_CCW_TOOLTIP = _("Rotate the photos left");
    
    public const string HFLIP_MENU = _("Flip Hori_zontally");
    public const string HFLIP_LABEL = _("Flip Horizontally");
    
    public const string VFLIP_MENU = _("Flip Verti_cally");
    public const string VFLIP_LABEL = _("Flip Vertically");
    
    public const string ABOUT_LABEL = _("_About");
    public const string APPLY_LABEL = _("_Apply");
    public const string CANCEL_LABEL = _("_Cancel");
    public const string DELETE_LABEL = _("_Delete");
    public const string EDIT_LABEL = _("_Edit");
    public const string FORWARD_LABEL = _("_Forward");
    public const string FULLSCREEN_LABEL = _("Fulls_creen");
    public const string HELP_LABEL = _("_Help");
    public const string LEAVE_FULLSCREEN_LABEL = _("Leave _Fullscreen");
    public const string NEW_LABEL = _("_New");
    public const string NEXT_LABEL = _("_Next");
    public const string OK_LABEL = _("_OK");
    public const string PLAY_LABEL = _("_Play");
    public const string PREFERENCES_LABEL = _("_Preferences");
    public const string PREVIOUS_LABEL = _("_Previous");
    public const string PRINT_LABEL = _("_Print");
    public const string QUIT_LABEL = _("_Quit");
    public const string REFRESH_LABEL = _("_Refresh");
    public const string REMOVE_LABEL = _("_Remove");
    public const string REVERT_TO_SAVED_LABEL = _("_Revert");
    public const string SAVE_LABEL = _("_Save");
    public const string SAVE_AS_LABEL = _("Save _As");
    public const string SORT_ASCENDING_LABEL = _("Sort _Ascending");
    public const string SORT_DESCENDING_LABEL = _("Sort _Descending");
    public const string STOP_LABEL = _("_Stop");
    public const string UNDELETE_LABEL = _("_Undelete");
    public const string ZOOM_100_LABEL = _("_Normal Size");
    public const string ZOOM_FIT_LABEL = _("Best _Fit");
    public const string ZOOM_IN_LABEL = _("Zoom _In");
    public const string ZOOM_OUT_LABEL = _("Zoom _Out");
    
    public const string ENHANCE_MENU = _("_Enhance");
    public const string ENHANCE_LABEL = _("Enhance");
    public const string ENHANCE_TOOLTIP = _("Automatically improve the photo’s appearance");
    
    public const string COPY_ADJUSTMENTS_MENU = _("_Copy Color Adjustments");
    public const string COPY_ADJUSTMENTS_LABEL = _("Copy Color Adjustments");
    public const string COPY_ADJUSTMENTS_TOOLTIP = _("Copy the color adjustments applied to the photo");
    
    public const string PASTE_ADJUSTMENTS_MENU = _("_Paste Color Adjustments");
    public const string PASTE_ADJUSTMENTS_LABEL = _("Paste Color Adjustments");
    public const string PASTE_ADJUSTMENTS_TOOLTIP = _("Apply copied color adjustments to the selected photos");
    
    public const string CROP_MENU = _("_Crop");
    public const string CROP_LABEL = _("Crop");
    public const string CROP_TOOLTIP = _("Crop the photo’s size");

    public const string STRAIGHTEN_MENU = _("_Straighten");
    public const string STRAIGHTEN_LABEL = _("Straighten");    
    public const string STRAIGHTEN_TOOLTIP = _("Straighten the photo");    
    
    public const string RED_EYE_MENU = _("_Red-eye");
    public const string RED_EYE_LABEL = _("Red-eye");
    public const string RED_EYE_TOOLTIP = _("Reduce or eliminate any red-eye effects in the photo");
    
    public const string ADJUST_MENU = _("_Adjust");
    public const string ADJUST_LABEL = _("Adjust");
    public const string ADJUST_TOOLTIP = _("Adjust the photo’s color and tone");
    
    public const string REVERT_MENU = _("Re_vert to Original");
    public const string REVERT_LABEL = _("Revert to Original");
    
    public const string REVERT_EDITABLE_MENU = _("Revert External E_dits");
    public const string REVERT_EDITABLE_TOOLTIP = _("Revert to the master photo");
    
    public const string SET_BACKGROUND_MENU = _("Set as _Desktop Background");
    public const string SET_BACKGROUND_TOOLTIP = _("Set selected image to be the new desktop background");
    public const string SET_BACKGROUND_SLIDESHOW_MENU = _("Set as _Desktop Slideshow…");
    
    public const string UNDO_MENU = _("_Undo");
    public const string UNDO_LABEL = _("Undo");
    
    public const string REDO_MENU = _("_Redo");
    public const string REDO_LABEL = _("Redo");
    
    public const string RENAME_EVENT_MENU = _("Re_name Event…");
    public const string RENAME_EVENT_LABEL = _("Rename Event");
    
    public const string MAKE_KEY_PHOTO_MENU = _("Make _Key Photo for Event");
    public const string MAKE_KEY_PHOTO_LABEL = _("Make Key Photo for Event");
    
    public const string NEW_EVENT_MENU = _("_New Event");
    public const string NEW_EVENT_LABEL = _("New Event");
            
    public const string SET_PHOTO_EVENT_LABEL = _("Move Photos");
    public const string SET_PHOTO_EVENT_TOOLTIP = _("Move photos to an event");
    
    public const string MERGE_MENU = _("_Merge Events");
    public const string MERGE_LABEL = _("Merge");
    public const string MERGE_TOOLTIP = _("Combine events into a single event");

    public const string RATING_MENU = _("_Set Rating");
    public const string RATING_LABEL = _("Set Rating");
    public const string RATING_TOOLTIP = _("Change the rating of your photo");

    public const string INCREASE_RATING_MENU = _("_Increase");
    public const string INCREASE_RATING_LABEL = _("Increase Rating");
    
    public const string DECREASE_RATING_MENU = _("_Decrease");
    public const string DECREASE_RATING_LABEL = _("Decrease Rating");

    public const string RATE_UNRATED_MENU = _("_Unrated");
    public const string RATE_UNRATED_COMBO_BOX = _("Unrated");
    public const string RATE_UNRATED_LABEL = _("Rate Unrated");
    public const string RATE_UNRATED_PROGRESS = _("Setting as unrated");
    public const string RATE_UNRATED_TOOLTIP = _("Remove any ratings");
    
    public const string RATE_REJECTED_MENU = _("_Rejected");
    public const string RATE_REJECTED_COMBO_BOX = _("Rejected");
    public const string RATE_REJECTED_LABEL = _("Rate Rejected");
    public const string RATE_REJECTED_PROGRESS = _("Setting as rejected");
    public const string RATE_REJECTED_TOOLTIP = _("Set rating to rejected");
    
    public const string DISPLAY_REJECTED_ONLY_MENU = _("Rejected _Only");
    public const string DISPLAY_REJECTED_ONLY_LABEL = _("Rejected Only");
    public const string DISPLAY_REJECTED_ONLY_TOOLTIP = _("Show only rejected photos");
    
    public const string DISPLAY_REJECTED_OR_HIGHER_MENU = _("All + _Rejected");
    public const string DISPLAY_REJECTED_OR_HIGHER_TOOLTIP = NC_("Tooltip", "Show all photos, including rejected");
    
    public const string DISPLAY_UNRATED_OR_HIGHER_MENU = _("_All Photos");
    // Button tooltip
    public const string DISPLAY_UNRATED_OR_HIGHER_TOOLTIP = _("Show all photos");

    public const string VIEW_RATINGS_MENU = _("_Ratings");
    public const string VIEW_RATINGS_TOOLTIP = _("Display each photo’s rating");

    public const string FILTER_PHOTOS_MENU = _("_Filter Photos");
    public const string FILTER_PHOTOS_LABEL = _("Filter Photos");
    public const string FILTER_PHOTOS_TOOLTIP = _("Limit the number of photos displayed based on a filter");
    
    public const string DUPLICATE_PHOTO_MENU = _("_Duplicate");
    public const string DUPLICATE_PHOTO_LABEL = _("Duplicate");
    public const string DUPLICATE_PHOTO_TOOLTIP = _("Make a duplicate of the photo");

    public const string EXPORT_MENU = _("_Export…");
    
    public const string PRINT_MENU = _("_Print…");
    
    public const string PUBLISH_MENU = _("Pu_blish…");
    public const string PUBLISH_LABEL = _("Publish");
    public const string PUBLISH_TOOLTIP = _("Publish to various websites");

    public const string EDIT_TITLE_MENU = _("Edit _Title…");
    // Button label
    public const string EDIT_TITLE_LABEL = NC_("Button Label", "Edit Title");

    public const string EDIT_COMMENT_MENU = _("Edit _Comment…");
    // Button label
    public const string EDIT_COMMENT_LABEL = _("Edit Comment");

    public const string EDIT_EVENT_COMMENT_MENU = _("Edit Event _Comment…");
    public const string EDIT_EVENT_COMMENT_LABEL = _("Edit Event Comment");

    public const string ADJUST_DATE_TIME_MENU = _("_Adjust Date and Time…");
    public const string ADJUST_DATE_TIME_LABEL = _("Adjust Date and Time");
    
    public const string ADD_TAGS_MENU = _("Add _Tags…");
    public const string ADD_TAGS_CONTEXT_MENU = _("_Add Tags…");
    // Dialog title
    public const string ADD_TAGS_TITLE = NC_("Dialog Title", "Add Tags");

    public const string PREFERENCES_MENU = _("_Preferences");
    
    public const string EXTERNAL_EDIT_MENU = _("Open With E_xternal Editor");
    
    public const string EXTERNAL_EDIT_RAW_MENU = _("Open With RA_W Editor");
    
    public const string SEND_TO_MENU = _("Send _To…");
    public const string SEND_TO_CONTEXT_MENU = _("Send T_o…");
    
    public const string FIND_MENU = _("_Find…");
    public const string FIND_LABEL = _("Find");
    public const string FIND_TOOLTIP = _("Find an image by typing text that appears in its name or tags");
    
    public const string FLAG_MENU = _("_Flag");
    
    public const string UNFLAG_MENU = _("Un_flag");

    public const string FACES_MENU = _("Faces");
    public const string FACES_LABEL = _("Faces");
    public const string FACES_TOOLTIP = _("Mark faces of people in the photo");
    public const string MODIFY_FACES_LABEL = _("Modify Faces");
    public const string DELETE_FACE_TITLE = _("Delete Face");
    public const string DELETE_FACE_SIDEBAR_MENU = _("_Delete");
    public const string RENAME_FACE_SIDEBAR_MENU = _("_Rename…");
    public const string FACES_MENU_SECTION = "FacesMenuPlaceholder";

    public string launch_editor_failed(Error err) {
        return _("Unable to launch editor: %s").printf(err.message);
    }
    
    public string add_tags_label(string[] names) {
        if (names.length == 1) {
            return _("Add Tag “%s”").printf(HierarchicalTagUtilities.get_basename(names[0]));
        } else if (names.length == 2) {
            // Used when adding two tags to photo(s)
            return _("Add Tags “%s” and “%s”").printf(
                HierarchicalTagUtilities.get_basename(names[0]),
                HierarchicalTagUtilities.get_basename(names[1]));
        } else {
            // Undo/Redo command name (in Edit menu)
            return C_("UndoRedo menu entry", "Add Tags");
        }
    }
    
    public string delete_tag_menu(string name) {
        return _("_Delete Tag “%s”").printf(name);
    }
    
    public string delete_tag_label(string name) {
        return _("Delete Tag “%s”").printf(name);
    }
    
    public const string DELETE_TAG_TITLE = _("Delete Tag");
    public const string DELETE_TAG_SIDEBAR_MENU = _("_Delete");
    
    public const string NEW_CHILD_TAG_SIDEBAR_MENU = _("_New");
    
    public string rename_tag_menu(string name) {
        return _("Re_name Tag “%s”…").printf(name);
    }
    
    public string rename_tag_label(string old_name, string new_name) {
        return _("Rename Tag “%s” to “%s”").printf(old_name, new_name);
    }
    
    public const string RENAME_TAG_SIDEBAR_MENU = _("_Rename…");
    
    public const string MODIFY_TAGS_MENU = _("Modif_y Tags…");
    public const string MODIFY_TAGS_LABEL = _("Modify Tags");
    
    public string tag_photos_label(string name, int count) {
        return ngettext ("Tag Photo as “%s”",
                         "Tag Photos as “%s”",
                         count).printf(name);
    }
    
    public string tag_photos_tooltip(string name, int count) {
        return ngettext ("Tag the selected photo as “%s”",
                         "Tag the selected photos as “%s”",
                         count).printf(name);
    }
    
    public string untag_photos_menu(string name, int count) {
        return ngettext ("Remove Tag “%s” From _Photo",
                         "Remove Tag “%s” From _Photos",
                         count).printf(name);
    }
    
    public string untag_photos_label(string name, int count) {
        return ngettext ("Remove Tag “%s” From Photo",
                         "Remove Tag “%s” From Photos",
                         count).printf(name);
    }
    
    public static string rename_tag_exists_message(string name) {
        return _("Unable to rename tag to “%s” because the tag already exists.").printf(name);
    }
    
    public static string rename_search_exists_message(string name) {
        return _("Unable to rename search to “%s” because the search already exists.").printf(name);
    }
    
    public const string DEFAULT_SAVED_SEARCH_NAME = _("Saved Search");
    
    public const string DELETE_SAVED_SEARCH_DIALOG_TITLE = _("Delete Search");
    
    public const string DELETE_SEARCH_MENU = _("_Delete");
    public const string EDIT_SEARCH_MENU = _("_Edit…");
    public const string RENAME_SEARCH_MENU = _("Re_name…");
    
    public string rename_search_label(string old_name, string new_name) {
        return _("Rename Search “%s” to “%s”").printf(old_name, new_name);
    }
    
    public string delete_search_label(string name) {
        return _("Delete Search “%s”").printf(name);
    }

#if ENABLE_FACES
    public static string rename_face_exists_message(string name) {
        return _("Unable to rename face to “%s” because the face already exists.").printf(name);
    }
    
    public string remove_face_from_photos_menu(string name, int count) {
        return ngettext ("Remove Face “%s” From _Photo",
                         "Remove Face “%s” From _Photos", count).printf(name);
    }
    
    public string remove_face_from_photos_label(string name, int count) {
        return ngettext ("Remove Face “%s” From Photo",
                         "Remove Face “%s” From Photos", count).printf(name);
    }
    
    public string rename_face_menu(string name) {
        return _("Re_name Face “%s”…").printf(name);
    }
    
    public string rename_face_label(string old_name, string new_name) {
        return _("Rename Face “%s” to “%s”").printf(old_name, new_name);
    }
    
    public string delete_face_menu(string name) {
        return _("_Delete Face “%s”").printf(name);
    }
    
    public string delete_face_label(string name) {
        return _("Delete Face “%s”").printf(name);
    }
#endif
    
    private unowned string rating_label(Rating rating) {
        switch (rating) {
            case Rating.REJECTED:
                return RATE_REJECTED_LABEL;
            case Rating.UNRATED:
                return RATE_UNRATED_LABEL;
            case Rating.ONE:
                return RATE_ONE_LABEL;
            case Rating.TWO:
                return RATE_TWO_LABEL;
            case Rating.THREE:
                return RATE_THREE_LABEL;
            case Rating.FOUR:
                return RATE_FOUR_LABEL;
            case Rating.FIVE:
                return RATE_FIVE_LABEL;
            default:
                return RATE_UNRATED_LABEL;
        }
    }
    
    private unowned string rating_combo_box(Rating rating) {
        switch (rating) {
            case Rating.REJECTED:
                return RATE_REJECTED_COMBO_BOX;
            case Rating.UNRATED:
                return RATE_UNRATED_COMBO_BOX;
            case Rating.ONE:
                return RATE_ONE_MENU;
            case Rating.TWO:
                return RATE_TWO_MENU;
            case Rating.THREE:
                return RATE_THREE_MENU;
            case Rating.FOUR:
                return RATE_FOUR_MENU;
            case Rating.FIVE:
                return RATE_FIVE_MENU;
            default:
                return RATE_UNRATED_MENU;
        }
    }
    
    private string get_rating_filter_tooltip(RatingFilter filter) {
        switch (filter) {
            case RatingFilter.REJECTED_OR_HIGHER:
                return Resources.DISPLAY_REJECTED_OR_HIGHER_TOOLTIP;
            
            case RatingFilter.ONE_OR_HIGHER:
                return Resources.DISPLAY_ONE_OR_HIGHER_TOOLTIP;
            
            case RatingFilter.TWO_OR_HIGHER:
                return Resources.DISPLAY_TWO_OR_HIGHER_TOOLTIP;
            
            case RatingFilter.THREE_OR_HIGHER:
                return Resources.DISPLAY_THREE_OR_HIGHER_TOOLTIP;
            
            case RatingFilter.FOUR_OR_HIGHER:
                return Resources.DISPLAY_FOUR_OR_HIGHER_TOOLTIP;
            
            case RatingFilter.FIVE_ONLY:
            case RatingFilter.FIVE_OR_HIGHER:
                return Resources.DISPLAY_FIVE_OR_HIGHER_TOOLTIP;
            
            case RatingFilter.REJECTED_ONLY:
                return Resources.DISPLAY_REJECTED_ONLY_TOOLTIP;
            
            case RatingFilter.UNRATED_OR_HIGHER:
            default:
                return Resources.DISPLAY_UNRATED_OR_HIGHER_TOOLTIP;
        }
    }

    private string rating_progress(Rating rating) {
        switch (rating) {
            case Rating.REJECTED:
                return RATE_REJECTED_PROGRESS;
            case Rating.UNRATED:
                return RATE_UNRATED_PROGRESS;
            case Rating.ONE:
                return RATE_ONE_PROGRESS;
            case Rating.TWO:
                return RATE_TWO_PROGRESS;
            case Rating.THREE:
                return RATE_THREE_PROGRESS;
            case Rating.FOUR:
                return RATE_FOUR_PROGRESS;
            case Rating.FIVE:
                return RATE_FIVE_PROGRESS;
            default:
                return RATE_UNRATED_PROGRESS;
        }
    }

    private const int[] rating_thresholds = { 0, 1, 25, 50, 75, 99 };

    private string get_stars(Rating rating) {
        switch (rating) {
            case Rating.REJECTED:
                return "\xE2\x9D\x8C";
            case Rating.ONE:
                return "\xE2\x98\x85";
            case Rating.TWO:
                return "\xE2\x98\x85\xE2\x98\x85";
            case Rating.THREE:
                return "\xE2\x98\x85\xE2\x98\x85\xE2\x98\x85";
            case Rating.FOUR:
                return "\xE2\x98\x85\xE2\x98\x85\xE2\x98\x85\xE2\x98\x85";
            case Rating.FIVE:
                return "\xE2\x98\x85\xE2\x98\x85\xE2\x98\x85\xE2\x98\x85\xE2\x98\x85";
            default:
                return "";
        }
    }

    private GLib.HashTable<int?, Gdk.Pixbuf> trinket_cache = null;
    private Gdk.Pixbuf? get_cached_trinket(int key) {
        if (trinket_cache == null) {
            trinket_cache = new GLib.HashTable<int?, Gdk.Pixbuf>(int_hash, int_equal);
        }

        if (trinket_cache[key] != null) {
            return trinket_cache[key];
        }

        return null;
    }

    public Gdk.Pixbuf? get_video_trinket(int scale) {
        int cache_key = scale << 18;
        var cached_pixbuf = get_cached_trinket(cache_key);

        if (cached_pixbuf != null)
            return cached_pixbuf;

        try {
            var theme = Gtk.IconTheme.get_default();
            var info = theme.lookup_icon ("filter-videos-symbolic", (int)(scale * 2), Gtk.IconLookupFlags.GENERIC_FALLBACK);
            var icon = info.load_symbolic({0.8, 0.8, 0.8, 1.0}, null, null, null);
            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, icon.width, icon.height);
            var ctx = new Cairo.Context(surface);
            ctx.set_source_rgba(0.0, 0.0, 0.0, 0.35);
            ctx.rectangle(0, 0, icon.width, icon.height);
            ctx.fill();
            Gdk.cairo_set_source_pixbuf(ctx, icon, 0, 0);
            ctx.paint();

            trinket_cache[cache_key] = Gdk.pixbuf_get_from_surface(surface, 0, 0, icon.width, icon.height);
            return trinket_cache[cache_key];
        } catch (Error err) {
            critical ("%s", err.message);

            return null;
        }
    }

    public Gdk.Pixbuf? get_flagged_trinket(int scale) {
        int cache_key = scale << 16;
        var cached_pixbuf = get_cached_trinket(cache_key);

        if (cached_pixbuf != null)
            return cached_pixbuf;

        try {
            var theme = Gtk.IconTheme.get_default();
            var info = theme.lookup_icon ("filter-flagged-symbolic", (int)(scale * 1.33), Gtk.IconLookupFlags.GENERIC_FALLBACK);
            var icon = info.load_symbolic({0.8, 0.8, 0.8, 1.0}, null, null, null);
            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, icon.width, icon.height);
            var ctx = new Cairo.Context(surface);
            ctx.set_source_rgba(0.0, 0.0, 0.0, 0.35);
            ctx.rectangle(0, 0, icon.width, icon.height);
            ctx.fill();
            Gdk.cairo_set_source_pixbuf(ctx, icon, 0, 0);
            ctx.paint();

            trinket_cache[cache_key] = Gdk.pixbuf_get_from_surface(surface, 0, 0, icon.width, icon.height);
            return trinket_cache[cache_key];
        } catch (Error err) {
            critical ("%s", err.message);

            return null;
        }
    }

    private Gdk.Pixbuf? get_rating_trinket(Rating rating, int scale) {
        if (rating == Rating.UNRATED)
            return null;

        int rating_key = (rating << 8) + scale;

        var cached_pixbuf = get_cached_trinket(rating_key);
        if (cached_pixbuf != null)
            return cached_pixbuf;

        var layout = AppWindow.get_instance().create_pango_layout(get_stars(rating));

        // Adjust style according to scale (depending on whether it is rendered on a Thumbnail or on a full foto)
        var att = new Pango.AttrList();
        var a = Pango.attr_scale_new((double)scale/12.0);
        att.insert(a.copy());
        layout.set_attributes(att);

        // Render the layout with a slight dark background so it stands out on all kinds of images
        // FIXME: Cache the result
        int width, height;
        layout.get_pixel_size(out width, out height);
        var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, width, height);
        var ctx = new Cairo.Context(surface);
        ctx.set_source_rgba(0.0, 0.0, 0.0, 0.35);
        ctx.rectangle(0,0,width,height);
        ctx.fill();
        if (rating == Rating.REJECTED)
            ctx.set_source_rgba(0.8, 0.0, 0.0, 1.0);
        else
            ctx.set_source_rgba(0.8, 0.8, 0.8, 1.0);

        ctx.move_to(0, 0);
        Pango.cairo_show_layout(ctx, layout);

        cached_pixbuf = Gdk.pixbuf_get_from_surface(surface, 0, 0, width, height);
        trinket_cache[rating_key] = cached_pixbuf;

        return cached_pixbuf;
    }

    private void generate_rating_strings() {
        string menu_base = "%s";
        string label_base = _("Rate %s");
        string tooltip_base = _("Set rating to %s");
        string progress_base = _("Setting rating to %s");
        string display_rating_menu_base = "%s";
        string display_rating_label_base = _("Display %s");
        string display_rating_tooltip_base = _("Only show photos with a rating of %s");
        string display_rating_or_higher_menu_base = _("%s or Better");
        string display_rating_or_higher_label_base = _("Display %s or Better");
        string display_rating_or_higher_tooltip_base = _("Only show photos with a rating of %s or better");

        RATE_ONE_MENU = menu_base.printf(get_stars(Rating.ONE));
        RATE_TWO_MENU = menu_base.printf(get_stars(Rating.TWO));
        RATE_THREE_MENU = menu_base.printf(get_stars(Rating.THREE));
        RATE_FOUR_MENU = menu_base.printf(get_stars(Rating.FOUR));
        RATE_FIVE_MENU = menu_base.printf(get_stars(Rating.FIVE));

        RATE_ONE_LABEL = label_base.printf(get_stars(Rating.ONE));
        RATE_TWO_LABEL = label_base.printf(get_stars(Rating.TWO));
        RATE_THREE_LABEL = label_base.printf(get_stars(Rating.THREE));
        RATE_FOUR_LABEL = label_base.printf(get_stars(Rating.FOUR));
        RATE_FIVE_LABEL = label_base.printf(get_stars(Rating.FIVE));

        RATE_ONE_TOOLTIP = tooltip_base.printf(get_stars(Rating.ONE));
        RATE_TWO_TOOLTIP = tooltip_base.printf(get_stars(Rating.TWO));
        RATE_THREE_TOOLTIP = tooltip_base.printf(get_stars(Rating.THREE));
        RATE_FOUR_TOOLTIP = tooltip_base.printf(get_stars(Rating.FOUR));
        RATE_FIVE_TOOLTIP = tooltip_base.printf(get_stars(Rating.FIVE));

        RATE_ONE_PROGRESS = progress_base.printf(get_stars(Rating.ONE));
        RATE_TWO_PROGRESS = progress_base.printf(get_stars(Rating.TWO));
        RATE_THREE_PROGRESS = progress_base.printf(get_stars(Rating.THREE));
        RATE_FOUR_PROGRESS = progress_base.printf(get_stars(Rating.FOUR));
        RATE_FIVE_PROGRESS = progress_base.printf(get_stars(Rating.FIVE));

        DISPLAY_ONE_OR_HIGHER_MENU = display_rating_or_higher_menu_base.printf(get_stars(Rating.ONE));
        DISPLAY_TWO_OR_HIGHER_MENU = display_rating_or_higher_menu_base.printf(get_stars(Rating.TWO));
        DISPLAY_THREE_OR_HIGHER_MENU = display_rating_or_higher_menu_base.printf(get_stars(Rating.THREE));
        DISPLAY_FOUR_OR_HIGHER_MENU = display_rating_or_higher_menu_base.printf(get_stars(Rating.FOUR));
        DISPLAY_FIVE_OR_HIGHER_MENU = display_rating_menu_base.printf(get_stars(Rating.FIVE));

        DISPLAY_ONE_OR_HIGHER_LABEL = display_rating_or_higher_label_base.printf(get_stars(Rating.ONE));
        DISPLAY_TWO_OR_HIGHER_LABEL = display_rating_or_higher_label_base.printf(get_stars(Rating.TWO));
        DISPLAY_THREE_OR_HIGHER_LABEL = display_rating_or_higher_label_base.printf(get_stars(Rating.THREE));
        DISPLAY_FOUR_OR_HIGHER_LABEL = display_rating_or_higher_label_base.printf(get_stars(Rating.FOUR));
        DISPLAY_FIVE_OR_HIGHER_LABEL = display_rating_label_base.printf(get_stars(Rating.FIVE));

        DISPLAY_ONE_OR_HIGHER_TOOLTIP = display_rating_or_higher_tooltip_base.printf(get_stars(Rating.ONE));
        DISPLAY_TWO_OR_HIGHER_TOOLTIP = display_rating_or_higher_tooltip_base.printf(get_stars(Rating.TWO));
        DISPLAY_THREE_OR_HIGHER_TOOLTIP = display_rating_or_higher_tooltip_base.printf(get_stars(Rating.THREE));
        DISPLAY_FOUR_OR_HIGHER_TOOLTIP = display_rating_or_higher_tooltip_base.printf(get_stars(Rating.FOUR));
        DISPLAY_FIVE_OR_HIGHER_TOOLTIP = display_rating_tooltip_base.printf(get_stars(Rating.FIVE));
    }

    private string RATE_ONE_MENU;
    private string RATE_ONE_LABEL;
    private string RATE_ONE_TOOLTIP;
    private string RATE_ONE_PROGRESS;
    
    private string RATE_TWO_MENU;
    private string RATE_TWO_LABEL;
    private string RATE_TWO_TOOLTIP;
    private string RATE_TWO_PROGRESS;

    private string RATE_THREE_MENU;
    private string RATE_THREE_LABEL;
    private string RATE_THREE_TOOLTIP;
    private string RATE_THREE_PROGRESS;

    private string RATE_FOUR_MENU;
    private string RATE_FOUR_LABEL;
    private string RATE_FOUR_TOOLTIP;
    private string RATE_FOUR_PROGRESS;

    private string RATE_FIVE_MENU;
    private string RATE_FIVE_LABEL;
    private string RATE_FIVE_TOOLTIP;
    private string RATE_FIVE_PROGRESS;

    private string DISPLAY_ONE_OR_HIGHER_MENU;
    private string DISPLAY_ONE_OR_HIGHER_LABEL;
    private string DISPLAY_ONE_OR_HIGHER_TOOLTIP;

    private string DISPLAY_TWO_OR_HIGHER_MENU;
    private string DISPLAY_TWO_OR_HIGHER_LABEL;
    private string DISPLAY_TWO_OR_HIGHER_TOOLTIP;

    private string DISPLAY_THREE_OR_HIGHER_MENU;
    private string DISPLAY_THREE_OR_HIGHER_LABEL;
    private string DISPLAY_THREE_OR_HIGHER_TOOLTIP;

    private string DISPLAY_FOUR_OR_HIGHER_MENU;
    private string DISPLAY_FOUR_OR_HIGHER_LABEL;
    private string DISPLAY_FOUR_OR_HIGHER_TOOLTIP;

    private string DISPLAY_FIVE_OR_HIGHER_MENU;
    private string DISPLAY_FIVE_OR_HIGHER_LABEL;
    private string DISPLAY_FIVE_OR_HIGHER_TOOLTIP;

    public const string DELETE_PHOTOS_MENU = _("_Delete");
    public const string DELETE_FROM_TRASH_TOOLTIP = _("Remove the selected photos from the trash");
    public const string DELETE_FROM_LIBRARY_TOOLTIP = _("Remove the selected photos from the library");
    
    public const string RESTORE_PHOTOS_MENU = _("_Restore");
    public const string RESTORE_PHOTOS_TOOLTIP = _("Move the selected photos back into the library");
    
    public const string JUMP_TO_FILE_MENU = _("Show in File Mana_ger");
    public const string JUMP_TO_FILE_TOOLTIP = _("Open the selected photo’s directory in the file manager");
    
    public string jump_to_file_failed(Error err) {
        return _("Unable to open in file manager: %s").printf(err.message);
    }
    
    public const string REMOVE_FROM_LIBRARY_MENU = _("R_emove From Library");
    
    public const string MOVE_TO_TRASH_MENU = _("_Move to Trash");
    
    public const string SELECT_ALL_MENU = _("Select _All");
    public const string SELECT_ALL_TOOLTIP = _("Select all items");
    
    private Gee.HashMap<string, Gdk.Pixbuf> icon_cache = null;
    Gee.HashMap<string, Gdk.Pixbuf> scaled_icon_cache = null;
    
    private string HH_MM_FORMAT_STRING = null;
    private string HH_MM_SS_FORMAT_STRING = null;
    private string LONG_DATE_FORMAT_STRING = null;
    private string START_MULTIDAY_DATE_FORMAT_STRING = null;
    private string END_MULTIDAY_DATE_FORMAT_STRING = null;
    private string START_MULTIMONTH_DATE_FORMAT_STRING = null;
    private string END_MULTIMONTH_DATE_FORMAT_STRING = null;

    public void init () {
        get_icon_theme_engine();
        // load application-wide stock icons as IconSets
        generate_rating_strings();
    }
    
    public void terminate() {
    }
    
    /**
     * @brief Helper for getting a format string that matches the
     * user's LC_TIME settings from the system.  This is intended 
     * to help support the use case where a user wants the text 
     * from one locale, but the timestamp format of another.
     * 
     * Stolen wholesale from code written for Geary by Jim Nelson
     * and from Marcel Stimberg's original patch to Shotwell to 
     * try to fix this; both are graciously thanked for their help.
     */
    private void fetch_lc_time_format() {
        // temporarily unset LANGUAGE, as it interferes with LC_TIME
        // and friends.
        string? old_language = Environment.get_variable("LANGUAGE");
        if (old_language != null) {
            Environment.unset_variable("LANGUAGE");
        }
        
        // switch LC_MESSAGES to LC_TIME...
        string? old_messages = Intl.setlocale(LocaleCategory.MESSAGES, null);
        string? lc_time = Intl.setlocale(LocaleCategory.TIME, null);
        
        if (lc_time != null) {
            Intl.setlocale(LocaleCategory.MESSAGES, lc_time);
        }
        
        // ...precache the timestamp string...
        /// Locale-specific time format for 12-hour time, i.e. 8:31 PM
        /// Precede modifier with a dash ("-") to pad with spaces, otherwise will pad with zeroes
        /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
        HH_MM_FORMAT_STRING = "%X";
        
        /// Locale-specific time format for 12-hour time with seconds, i.e. 8:31:42 PM
        /// Precede modifier with a dash ("-") to pad with spaces, otherwise will pad with zeroes
        /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
        HH_MM_SS_FORMAT_STRING = Posix.nl_langinfo (Posix.NLItem.T_FMT);

        /// Locale-specific calendar date format, i.e. "Tue Mar 08, 2006"
        /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
        LONG_DATE_FORMAT_STRING = _("%a %b %d, %Y");
        
        /// Locale-specific starting date format for multi-date strings,
        /// i.e. the "Tue Mar 08" in "Tue Mar 08 - 10, 2006"
        /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
        START_MULTIDAY_DATE_FORMAT_STRING = C_("MultidayFormat", "%a %b %d");
        
        /// Locale-specific ending date format for multi-date strings,
        /// i.e. the "10, 2006" in "Tue Mar 08 - 10, 2006"
        /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
        END_MULTIDAY_DATE_FORMAT_STRING = C_("MultidayFormat", "%d, %Y");
        
        /// Locale-specific calendar date format for multi-month strings,
        /// i.e. the "Tue Mar 08" in "Tue Mar 08 to Mon Apr 06, 2006"
        /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
        START_MULTIMONTH_DATE_FORMAT_STRING = C_("MultimonthFormat", "%a %b %d");

        /// Locale-specific calendar date format for multi-month strings,
        /// i.e. the "Mon Apr 06, 2006" in "Tue Mar 08 to Mon Apr 06, 2006"
        /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
        END_MULTIMONTH_DATE_FORMAT_STRING = C_("MultimonthFormat", "%a %b %d, %Y");

        // ...put everything back like we found it.
        if (old_messages != null) {
            Intl.setlocale(LocaleCategory.MESSAGES, old_messages);
        }
        
        if (old_language != null) {
            Environment.set_variable("LANGUAGE", old_language, true);
        }

    }

    public enum UnitSystem {
        IMPERIAL,
        METRIC,
        UNKNOWN
    }

    private string lc_measurement = null;
    private UnitSystem unit_system = UnitSystem.UNKNOWN;
    private const string IMPERIAL_COUNTRIES[] = {"unm_US", "es_US", "en_US", "yi_US" };

    public UnitSystem get_default_measurement_unit() {
        if (unit_system != UnitSystem.UNKNOWN) {
            return unit_system;
        }

        lc_measurement = Environment.get_variable("LC_MEASUREMENT");
        if (lc_measurement == null) {
            lc_measurement = Intl.get_language_names()[0];
        }

        var index = lc_measurement.last_index_of_char('.');
        if (index > 0) {
            lc_measurement = lc_measurement.substring(0, index);
        }

        unit_system = UnitSystem.METRIC;
        if (lc_measurement in IMPERIAL_COUNTRIES) {
            unit_system = UnitSystem.IMPERIAL;
        }

        return unit_system;
    }
    
    /**
     * @brief Returns a precached format string that matches the
     * user's LC_TIME settings.  
     */
    public string get_hh_mm_format_string() {
        if (HH_MM_FORMAT_STRING == null) {
            fetch_lc_time_format();
        }
        
        return HH_MM_FORMAT_STRING;
    }
    
    public string get_hh_mm_ss_format_string() {
        if (HH_MM_SS_FORMAT_STRING == null) {
            fetch_lc_time_format();
        }
        
        return HH_MM_SS_FORMAT_STRING;
    }
    
    public string get_long_date_format_string() {
        if (LONG_DATE_FORMAT_STRING == null) {
            fetch_lc_time_format();
        }
        
        return LONG_DATE_FORMAT_STRING;
    }
    
    public string get_start_multiday_span_format_string() {
        if (START_MULTIDAY_DATE_FORMAT_STRING == null) {
            fetch_lc_time_format();
        }
        
        return START_MULTIDAY_DATE_FORMAT_STRING;
    }

    public string get_end_multiday_span_format_string() {
        if (END_MULTIDAY_DATE_FORMAT_STRING == null) {
            fetch_lc_time_format();
        }
        
        return END_MULTIDAY_DATE_FORMAT_STRING;
    }

    public string get_start_multimonth_span_format_string() {
        if (START_MULTIMONTH_DATE_FORMAT_STRING == null) {
            fetch_lc_time_format();
        }
        
        return START_MULTIMONTH_DATE_FORMAT_STRING;
    }

    public string get_end_multimonth_span_format_string() {
        if (END_MULTIMONTH_DATE_FORMAT_STRING == null) {
            fetch_lc_time_format();
        }

        return END_MULTIMONTH_DATE_FORMAT_STRING;
    }

    public string get_ui(string filename) {
        return "/org/gnome/Shotwell/ui/%s".printf(filename);
    }

    private const string NONINTERPRETABLE_BADGE_FILE = "noninterpretable-video.png";
    private Gdk.Pixbuf? noninterpretable_badge_pixbuf = null;

    public Gdk.Pixbuf? get_noninterpretable_badge_pixbuf() {
        if (noninterpretable_badge_pixbuf == null) {
            try {
                var path = "/org/gnome/Shotwell/icons/" + NONINTERPRETABLE_BADGE_FILE;
                noninterpretable_badge_pixbuf = new Gdk.Pixbuf.from_resource(path);
            } catch (Error err) {
                error("VideoReader can't load noninterpretable badge image: %s", err.message);
            }
        }
        
        return noninterpretable_badge_pixbuf;
    }
    
    public Gtk.IconTheme get_icon_theme_engine() {
        Gtk.IconTheme icon_theme = Gtk.IconTheme.get_default();
        icon_theme.add_resource_path("/org/gnome/Shotwell/icons");
        
        return icon_theme;
    }
    
    // This method returns a reference to a cached pixbuf that may be shared throughout the system.
    // If the pixbuf is to be modified, make a copy of it.
    public Gdk.Pixbuf? get_icon(string name, int scale = DEFAULT_ICON_SCALE) {
        if (scaled_icon_cache != null) {
            string scaled_name = "%s-%d".printf(name, scale);
            if (scaled_icon_cache.has_key(scaled_name))
                return scaled_icon_cache.get(scaled_name);
        }
        
        // stash icons not available through the UI Manager (i.e. used directly as pixbufs)
        // in the local cache
        if (icon_cache == null)
            icon_cache = new Gee.HashMap<string, Gdk.Pixbuf>();
        
        // fetch from cache and if not present, from disk
        Gdk.Pixbuf? pixbuf = icon_cache.get(name);
        if (pixbuf == null) {
            pixbuf = load_icon(name, scale);
            if (pixbuf == null)
                return null;
            
            icon_cache.set(name, pixbuf);
        }
        
        if (scale <= 0)
            return pixbuf;
        
        Gdk.Pixbuf scaled_pixbuf = scale_pixbuf(pixbuf, scale, Gdk.InterpType.BILINEAR, false);
        
        if (scaled_icon_cache == null)
            scaled_icon_cache = new Gee.HashMap<string, Gdk.Pixbuf>();
        
        scaled_icon_cache.set("%s-%d".printf(name, scale), scaled_pixbuf);
        
        return scaled_pixbuf;
    }
    
    public Gdk.Pixbuf? load_icon(string name, int scale = DEFAULT_ICON_SCALE) {
        Gdk.Pixbuf pixbuf = null;
        try {
            var theme = Gtk.IconTheme.get_default();
            var info = theme.lookup_icon(name, scale, Gtk.IconLookupFlags.GENERIC_FALLBACK);
            pixbuf = info.load_symbolic_for_context(AppWindow.get_instance().get_style_context(), null);
        } catch (Error err) {
            debug("Failed to find icon %s in theme, falling back to resources", name);
        }

        if (pixbuf == null) {
            try {
                var path = "/org/gnome/Shotwell/icons/%s".printf(name);
                pixbuf = new Gdk.Pixbuf.from_resource(path);
            } catch (Error err) {
                critical("Unable to load icon %s: %s", name, err.message);
            }
        }

        if (pixbuf == null)
            return null;

        return (scale > 0) ? scale_pixbuf(pixbuf, scale, Gdk.InterpType.BILINEAR, false) : pixbuf;
    }
    
    // Get the directory where our help files live.  Returns a string
    // describing the help path we want, or, if we're installed system
    // -wide already, returns null.
    public static string? get_help_path() {
        // Try looking for our 'index.page' in the build directory.
        //
        // TODO: Need to look for internationalized help before falling back on help/C
        File dir = AppDirs.get_exec_dir();
        
        if (dir.get_path().has_suffix("src")) {
            dir = dir.get_parent().get_parent();
        }
        
        File help_dir = dir.get_child("help").get_child("C");
        File help_index = help_dir.get_child("index.page");
        
        if (help_index.query_exists(null)) {
            string help_path;

            help_path = help_dir.get_path();
         
            if (!help_path.has_suffix("/"))
                help_path += "/";
            
            // Found it.
            return help_path;
        }
        
        // "./help/C/index.page" doesn't exist, so we're installed  
        // system-wide, and the caller should assume the default 
        // help location. 
        return null;
    }

    public static void launch_help(Gtk.Window window, string? anchor=null) throws Error {
        string? help_path = get_help_path();
        
        if(help_path != null) {
            // We're running from the build directory; use local help.
            
            // Allow the caller to request a specific page.
            if (anchor != null) {
                help_path +=anchor;
            }
            
            string[] argv = new string[3];
            argv[0] = "yelp";
            argv[1] = help_path;
            argv[2] = null;
            
            Pid pid;
            if (Process.spawn_async(AppDirs.get_exec_dir().get_path(), argv, null,
                SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL, null, out pid)) {
                return;
            }
            
            warning("Unable to launch %s", argv[0]);
        }
        
        // launch from system-installed help
        var uri = "help:shotwell";
        if (anchor != null) {
            uri += anchor;
        }

        Gtk.show_uri_on_window(window, uri, Gdk.CURRENT_TIME);
    }
    
    public const int ALL_DATA = -1;
    
    public static int use_header_bar() {
        if (Environment.get_variable("SHOTWELL_USE_HEADERBARS") != null) {
            return 0;
        }

        bool use_header;
        Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header);

        return use_header ? 1 : 0;
    }

    public const string ONIMAGE_FONT_COLOR = "#000000";
    public const string ONIMAGE_FONT_BACKGROUND = "rgba(255,255,255,0.5)";
}

