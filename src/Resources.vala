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

#if NO_SVG
	public const string SVG_SUFFIX = ".png";
#else
	public const string SVG_SUFFIX = ".svg";
#endif    

    public const string ICON_APP = "shotwell" + SVG_SUFFIX;
    public const string ICON_ABOUT_LOGO = "shotwell-street.jpg";

    public const string ROTATE_CW_LABEL = _("Rotate");
    public const string ROTATE_CCW_LABEL = _("Rotate");
    public const string ROTATE_CW_TOOLTIP = _("Rotate the photo(s) right");
    public const string ROTATE_CCW_TOOLTIP = _("Rotate the photo(s) left");

    public const string ENHANCE_LABEL = _("Enhance");
    public const string ENHANCE_TOOLTIP = _("Automatically improve the photo's appearance");

    private Gtk.IconFactory factory = null;
    
    public void init () {
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
        
        factory.add_default();
    }
    
    public void terminate() {
    }

    public File get_ui(string filename) {
        return AppDirs.get_resources_dir().get_child("ui").get_child(filename);
    }
    
    public Gdk.Pixbuf? get_icon(string name, int scale = 24) {
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

