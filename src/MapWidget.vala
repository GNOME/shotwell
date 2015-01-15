 /* Copyright 2015 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

private class MapWidget : GtkChamplain.Embed {
    private const uint DEFAULT_ZOOM_LEVEL = 8;

    private static MapWidget? instance = null;

    public Cogl.Handle marker_cogl_texture { get; private set; }
    
    private Champlain.View? map_view = null;
    private Champlain.Scale map_scale = new Champlain.Scale();
    private Champlain.MarkerLayer marker_layer = new Champlain.MarkerLayer();

    public static MapWidget get_instance() {
        if (instance == null)
            instance = new MapWidget();
        
        return instance;
    }

    private MapWidget() {
        // add scale to bottom left corner of the map
        map_view = get_view();
        map_view.add_layer(marker_layer);
        map_scale.x_align = Clutter.ActorAlign.START;
        map_scale.y_align = Clutter.ActorAlign.END;
        map_scale.connect_view(map_view);
        map_view.add(map_scale);

        map_view.set_zoom_on_double_click(false);

        button_press_event.connect(map_zoom_handler);
        set_size_request(200, 200);

        // Load gdk pixbuf via Resources class
        Gdk.Pixbuf gdk_marker = Resources.get_icon(Resources.ICON_GPS_MARKER);
        try {
            // this is what GtkClutter.Texture.set_from_pixmap does
            Clutter.Texture tex = new Clutter.Texture();
            tex.set_from_rgb_data(gdk_marker.get_pixels(),
                gdk_marker.get_has_alpha(),
                gdk_marker.get_width(),
                gdk_marker.get_height(),
                gdk_marker.get_rowstride(),
                gdk_marker.get_has_alpha() ? 4 : 3,
                Clutter.TextureFlags.NONE);
            marker_cogl_texture = tex.get_cogl_texture();
        } catch (GLib.Error e) {
            // Fall back to the generic champlain marker
            marker_cogl_texture = null;
        }
    }

    public void clear() {
        marker_layer.remove_all();
    }

    public void add_position_marker(DataView view) {
        clear();
        
        Positionable? positionable = view.get_source() as Positionable;
        if (positionable == null)
            return;
        
        GpsCoords? gps_coords = positionable.get_gps_coords();
        if (gps_coords == null)
            return;
        
        Champlain.Marker marker = create_champlain_marker(gps_coords);
        marker_layer.add_marker(marker);
    }

    public void show_position_markers() {
        if (marker_layer.get_markers().length() != 0) {
            if (map_view.get_zoom_level() < DEFAULT_ZOOM_LEVEL) {
                map_view.set_zoom_level(DEFAULT_ZOOM_LEVEL);
            }
            Champlain.BoundingBox bbox = marker_layer.get_bounding_box();
            map_view.ensure_visible(bbox, true);
        }
    }

    private Champlain.Marker create_champlain_marker(GpsCoords gps_coords) {
        Champlain.Marker champlain_marker;
        if (marker_cogl_texture == null) {
            // Fall back to the generic champlain marker
            champlain_marker = new Champlain.Point.full(12, { red:10, green:10, blue:255, alpha:255 });
        } else {
            champlain_marker = new Champlain.Marker();
            Clutter.Texture t = new Clutter.Texture();
            t.set_cogl_texture(marker_cogl_texture);
            champlain_marker.add(t);
        }
        champlain_marker.set_pivot_point(0.5f, 0.5f); // set center of marker
        champlain_marker.set_location(gps_coords.latitude, gps_coords.longitude);
        
        return champlain_marker;
    }

    private bool map_zoom_handler(Gdk.EventButton event) {
        if (event.type != Gdk.EventType.2BUTTON_PRESS)
            return false;
        
        // fetch before zooming
        double lat = map_view.y_to_latitude(event.y);
        double lon = map_view.x_to_longitude(event.x);
        
        switch (event.button) {
            case 1:
                map_view.zoom_in();
            break;
            
            case 3:
                map_view.zoom_out();
            break;
            
            default:
                return false;
        }
        
        map_view.center_on(lat, lon);
        
        return true;
    }
}

