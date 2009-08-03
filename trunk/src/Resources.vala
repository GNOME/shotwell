/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// defined by ./configure or Makefile and included by gcc -D
extern const string _PREFIX;
extern const string _VERSION;

namespace Resources {
    public const string APP_TITLE = "Shotwell";
    public const string APP_SUBTITLE = "Photo Organizer";
    public const string APP_VERSION = _VERSION;
    public const string COPYRIGHT = "Copyright 2009 Yorba Foundation";
    
    public const string YORBA_URL = "http://www.yorba.org";
    public const string HELP_URL = "http://trac.yorba.org/wiki/Shotwell";
    
    public const string PREFIX = _PREFIX;

    public const string[] AUTHORS = { 
        "Jim Nelson <jim@yorba.org>", 
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
    
    public const string ICON_APP = "shotwell.svg";
    public const string ICON_ABOUT_LOGO = "shotwell-street.jpg";

    public const string ROTATE_CLOCKWISE_LABEL = "Rotate";
    public const string ROTATE_CLOCKWISE_TOOLTIP = "Rotate the photo(s) right";
    
    public const string ROTATE_COUNTERCLOCKWISE_LABEL = "Rotate";
    public const string ROTATE_COUNTERCLOCKWISE_TOOLTIP = "Rotate the photo(s) left";
    
    private Gtk.IconFactory factory = null;
    
    public void init () {
        factory = new Gtk.IconFactory();
        
        File icons_dir = AppWindow.get_resources_dir().get_child("icons");
        add_stock_icon(icons_dir.get_child("object-rotate-right.svg"), CLOCKWISE);
        add_stock_icon(icons_dir.get_child("object-rotate-left.svg"), COUNTERCLOCKWISE);
        add_stock_icon(icons_dir.get_child("object-flip-horizontal.svg"), MIRROR);
        add_stock_icon(icons_dir.get_child("crop.svg"), CROP);
        add_stock_icon(icons_dir.get_child("redeye.png"), REDEYE);
        add_stock_icon(icons_dir.get_child("adjust.png"), ADJUST);
        add_stock_icon(icons_dir.get_child("pin-toolbar.svg"), PIN_TOOLBAR);
        add_stock_icon(icons_dir.get_child("return-to-page.svg"), RETURN_TO_PAGE);
        add_stock_icon(icons_dir.get_child("make-primary.svg"), MAKE_PRIMARY);
        add_stock_icon(icons_dir.get_child("import.svg"), IMPORT);
        add_stock_icon(icons_dir.get_child("import-all.png"), IMPORT_ALL);
        
        factory.add_default();
    }
    
    public void terminate() {
    }
    
    public File get_ui(string filename) {
        return AppWindow.get_resources_dir().get_child("ui").get_child(filename);
    }
    
    public Gdk.Pixbuf? get_icon(string name, int scale = 24) {
        File icons_dir = AppWindow.get_resources_dir().get_child("icons");
        
        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = new Gdk.Pixbuf.from_file(icons_dir.get_child(name).get_path());
        } catch (Error err) {
            critical("Unable to load icon %s: %s", name, err.message);
        }

        if (pixbuf == null)
            return null;
        
        return (scale > 0) ? scale_pixbuf(pixbuf, scale, Gdk.InterpType.BILINEAR) : pixbuf;
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

