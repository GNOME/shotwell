/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// defined by ./configure or Makefile and included by gcc -D
extern const string _PREFIX;
extern const string _VERSION;
extern const string GETTEXT_PACKAGE;

namespace Resources {
    public const string APP_TITLE = "Shotwell";
    public const string APP_LIBRARY_ROLE = _("Photo Organizer");
    public const string APP_DIRECT_ROLE = _("Photo Viewer");
    public const string APP_VERSION = _VERSION;
    public const string COPYRIGHT = _("Copyright 2009 Yorba Foundation");
    public const string APP_GETTEXT_PACKAGE = GETTEXT_PACKAGE;
    
    public const string YORBA_URL = "http://www.yorba.org";
    public const string HELP_URL = "http://trac.yorba.org/wiki/Shotwell";
    
    public const string PREFIX = _PREFIX;

    public const double TRANSIENT_WINDOW_OPACITY = 0.90;
    
    public const int DEFAULT_ICON_SCALE = 24;
    
    public const string[] AUTHORS = { 
        "Jim Nelson <jim@yorba.org>", 
        "Lucas Beeler <lucas@yorba.org>",
        "Allison Barlow <allison@yorba.org>",
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

    public const string CLOCKWISE = "shotwell-rotate-clockwise";
    public const string COUNTERCLOCKWISE = "shotwell-rotate-counterclockwise";
    public const string MIRROR = "shotwell-mirror";
    public const string CROP = "shotwell-crop";
    public const string REDEYE = "shotwell-redeye";
    public const string ADJUST = "shotwell-adjust";
    public const string PIN_TOOLBAR = "shotwell-pin-toolbar";
    public const string RETURN_TO_PAGE = "shotwell-return-to-page";
    public const string MAKE_PRIMARY = "shotwell-make-primary";
    public const string IMPORT = "shotwell-import";
    public const string IMPORT_ALL = "shotwell-import-all";
    public const string ENHANCE = "shotwell-auto-enhance";
    public const string CROP_PIVOT_RETICLE = "shotwell-crop-pivot-reticle";
    public const string PUBLISH = "shotwell-publish";
    public const string HIDDEN = "shotwell-hidden";
    public const string FAVORITE = "shotwell-favorite";

#if NO_SVG
	public const string SVG_SUFFIX = ".png";
#else
	public const string SVG_SUFFIX = ".svg";
#endif    

    public const string ICON_APP = "shotwell" + SVG_SUFFIX;
    public const string ICON_ABOUT_LOGO = "shotwell-street.jpg";
    public const string ICON_HIDDEN = "hidden.svg";
    public const string ICON_FAVORITE = "favorite.svg";

    public const string ROTATE_CW_MENU = _("Rotate _Right");
    public const string ROTATE_CW_LABEL = _("Rotate");
    public const string ROTATE_CW_FULL_LABEL = _("Rotate Right");
    public const string ROTATE_CW_TOOLTIP = _("Rotate the photos right");
    
    public const string ROTATE_CCW_MENU = _("Rotate _Left");
    public const string ROTATE_CCW_LABEL = _("Rotate");
    public const string ROTATE_CCW_FULL_LABEL = _("Rotate Left");
    public const string ROTATE_CCW_TOOLTIP = _("Rotate the photos left");
    
    public const string MIRROR_MENU = _("_Mirror");
    public const string MIRROR_LABEL = _("Mirror");
    public const string MIRROR_TOOLTIP = _("Make mirror images of the photos");
    
    public const string ENHANCE_MENU = _("_Enhance");
    public const string ENHANCE_LABEL = _("Enhance");
    public const string ENHANCE_TOOLTIP = _("Automatically improve the photo's appearance");
    
    public const string REVERT_MENU = _("Re_vert to Original");
    public const string REVERT_LABEL = _("Revert to Original");
    public const string REVERT_TOOLTIP = _("Revert to the original photo");
    
    public const string UNDO_MENU = _("_Undo");
    public const string UNDO_LABEL = _("Undo");
    public const string UNDO_TOOLTIP = _("Undo the last action");
    
    public const string REDO_MENU = _("_Redo");
    public const string REDO_LABEL = _("Redo");
    public const string REDO_TOOLTIP = _("Redo the last undone action");
    
    public const string RENAME_EVENT_MENU = _("Re_name Event...");
    public const string RENAME_EVENT_LABEL = _("Rename Event");
    public const string RENAME_EVENT_TOOLTIP = _("Rename the selected event");
    
    public const string MAKE_KEY_PHOTO_MENU = _("Make _Key Photo for Event");
    public const string MAKE_KEY_PHOTO_LABEL = _("Make Key Photo for Event");
    public const string MAKE_KEY_PHOTO_TOOLTIP = _("Make the selected photo the thumbnail for the event");
    
    public const string NEW_EVENT_MENU = _("_New Event");
    public const string NEW_EVENT_LABEL = _("New Event");
    public const string NEW_EVENT_TOOLTIP = _("Create new event from the selected photos");
            
    public const string SET_PHOTO_EVENT_LABEL = _("Move Photos");
    public const string SET_PHOTO_EVENT_TOOLTIP = _("Move photos to an event");
    
    public const string MERGE_MENU = _("_Merge Events");
    public const string MERGE_LABEL = _("Merge");
    public const string MERGE_TOOLTIP = _("Merge into a single event");
    
    public const string FAVORITE_MENU = _("Mark as _Favorite");
    public const string FAVORITE_LABEL = _("Mark as Favorite");
    public const string FAVORITE_TOOLTIP = _("Mark the photo as one of your favorites");
    
    public const string UNFAVORITE_MENU = _("Unmark as _Favorite");
    public const string UNFAVORITE_LABEL = _("Unmark as Favorite");
    public const string UNFAVORITE_TOOLTIP = _("Unmark the photo as one of your favorites");
    
    public const string HIDE_MENU = _("_Hide");
    public const string HIDE_LABEL = _("Hide");
    public const string HIDE_TOOLTIP = _("Hide the selected photos");
    
    public const string UNHIDE_MENU = _("Un_hide");
    public const string UNHIDE_LABEL = _("Unhide");
    public const string UNHIDE_TOOLTIP = _("Unhide the selected photos");
    
    public const string DUPLICATE_PHOTO_MENU = _("_Duplicate");
    public const string DUPLICATE_PHOTO_LABEL = _("Duplicate");
    public const string DUPLICATE_PHOTO_TOOLTIP = _("Make a duplicate of the photo");

    private Gtk.IconFactory factory = null;
    private Gee.HashMap<string, Gdk.Pixbuf> icon_cache = null;
    
    public void init () {
        // load application-wide stock icons as IconSets
        factory = new Gtk.IconFactory();

        File icons_dir = AppDirs.get_resources_dir().get_child("icons");
        add_stock_icon(icons_dir.get_child("object-rotate-right" + SVG_SUFFIX), CLOCKWISE);
        add_stock_icon(icons_dir.get_child("object-rotate-left" + SVG_SUFFIX), COUNTERCLOCKWISE);
        add_stock_icon(icons_dir.get_child("object-flip-horizontal" + SVG_SUFFIX), MIRROR);
        add_stock_icon(icons_dir.get_child("crop" + SVG_SUFFIX), CROP);
        add_stock_icon(icons_dir.get_child("redeye.png"), REDEYE);
        add_stock_icon(icons_dir.get_child("adjust.png"), ADJUST);
        add_stock_icon(icons_dir.get_child("pin-toolbar" + SVG_SUFFIX), PIN_TOOLBAR);
        add_stock_icon(icons_dir.get_child("return-to-page" + SVG_SUFFIX), RETURN_TO_PAGE);
        add_stock_icon(icons_dir.get_child("make-primary" + SVG_SUFFIX), MAKE_PRIMARY);
        add_stock_icon(icons_dir.get_child("import" + SVG_SUFFIX), IMPORT);
        add_stock_icon(icons_dir.get_child("import-all.png"), IMPORT_ALL);
        add_stock_icon(icons_dir.get_child("enhance.png"), ENHANCE);
        add_stock_icon(icons_dir.get_child("crop-pivot-reticle.png"), CROP_PIVOT_RETICLE);
        add_stock_icon(icons_dir.get_child("publish.png"), PUBLISH);
        add_stock_icon(icons_dir.get_child("hidden.svg"), HIDDEN);
        add_stock_icon(icons_dir.get_child("favorite.svg"), FAVORITE);
        
        factory.add_default();
    }
    
    public void terminate() {
    }

    public File get_ui(string filename) {
        return AppDirs.get_resources_dir().get_child("ui").get_child(filename);
    }
    
    // This method returns a reference to a cached pixbuf that may be shared throughout the system.
    // If the pixbuf is to be modified, make a copy of it.
    public Gdk.Pixbuf? get_icon(string name, int scale = DEFAULT_ICON_SCALE) {
        // stash icons not available through the UI Manager (i.e. used directly as pixbufs)
        // in the local cache
        if (icon_cache == null)
            icon_cache = new Gee.HashMap<string, Gdk.Pixbuf>();
        
        // fetch from cache and if not present, from disk
        Gdk.Pixbuf? pixbuf = icon_cache.get(name);
        if (pixbuf == null) {
            pixbuf = load_icon(name, 0);
            if (pixbuf == null)
                return null;
            
            icon_cache.set(name, pixbuf);
        }
        
        return (scale > 0) ? scale_pixbuf(pixbuf, scale, Gdk.InterpType.BILINEAR, false) : pixbuf;
    }
    
    public Gdk.Pixbuf? load_icon(string name, int scale = DEFAULT_ICON_SCALE) {
        File icons_dir = AppDirs.get_resources_dir().get_child("icons");
        
        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = new Gdk.Pixbuf.from_file(icons_dir.get_child(name).get_path());
        } catch (Error err) {
            critical("Unable to load icon %s: %s", name, err.message);
        }

        if (pixbuf == null)
            return null;
        
        return (scale > 0) ? scale_pixbuf(pixbuf, scale, Gdk.InterpType.BILINEAR, false) : pixbuf;
    }
    
    private void add_stock_icon(File file, string stock_id) {
        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = new Gdk.Pixbuf.from_file(file.get_path());
        } catch (Error err) {
            error("%s", err.message);
        }
        
        Gtk.IconSet icon_set = new Gtk.IconSet.from_pixbuf(pixbuf);
        factory.add(stock_id, icon_set);
    }
}

