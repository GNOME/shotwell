/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

private class PositionMarker : Object {
    private MapWidget map_widget;

    protected PositionMarker.from_group(MapWidget map_widget) {
        this.map_widget = map_widget;
    }

    public PositionMarker(MapWidget map_widget, DataView view, Champlain.Marker marker) {
        this.map_widget = map_widget;
        this.view = view;
        marker.selectable = true;
        marker.button_release_event.connect ((event) => {
            if (event.button > 1)
                return true;
            map_widget.select_data_view(this);
            return true;
        });
        marker.enter_event.connect ((event) => {
            map_widget.highlight_data_view(this);
            return true;
        });
        marker.leave_event.connect ((event) => {
            map_widget.unhighlight_data_view(this);
            return true;
        });
        this.marker = marker;
    }

    public bool selected {
        get {
            return marker.get_selected();
        }
        set {
            marker.set_selected(value);
        }
    }

    public Champlain.Marker marker { get; protected set; }
    // Geo lookup
    // public string location_country { get; set; }
    // public string location_city { get; set; }
    public unowned DataView view { get; protected set; }
}

private class MarkerGroup : PositionMarker {
    private Gee.Set<PositionMarker> markers = new Gee.HashSet<PositionMarker>();
    public MarkerGroup(MapWidget map_widget, PositionMarker first_marker) {
        base.from_group(map_widget);
        markers.add(first_marker);
        // use the first markers internal texture as the group's
        marker = first_marker.marker;
        view = first_marker.view;
    }
    public void add_marker(PositionMarker marker) {
        markers.add(marker);
    }
    public Gee.Set<PositionMarker> get_markers() {
        return markers;
    }
}

private class MapWidget : Gtk.Bin {
    private const uint DEFAULT_ZOOM_LEVEL = 8;
    private const long MARKER_GROUP_RASTER_WIDTH = 30l;

    private static MapWidget instance = null;

    private GtkChamplain.Embed gtk_champlain_widget = new GtkChamplain.Embed();
    private Champlain.View map_view = null;
    private uint last_zoom_level = DEFAULT_ZOOM_LEVEL;
    private Champlain.Scale map_scale = new Champlain.Scale();
    private Champlain.MarkerLayer marker_layer = new Champlain.MarkerLayer();
    private Gee.Map<DataView, PositionMarker> position_markers =
        new Gee.HashMap<DataView, PositionMarker>();
    private Gee.TreeMap<long, Gee.TreeMap<long, MarkerGroup>> marker_groups_tree =
        new Gee.TreeMap<long, Gee.TreeMap<long, MarkerGroup>>();
    private Gee.Collection<MarkerGroup> marker_groups = new Gee.LinkedList<MarkerGroup>();
    private unowned Page page = null;

    public float marker_image_width { get; private set; }
    public float marker_image_height { get; private set; }
    public Clutter.Image? marker_image { get; private set; }
    public Clutter.Image? marker_selected_image { get; private set; }
    public const Clutter.Color marker_point_color = { 10, 10, 255, 192 };

    private MapWidget() {
        setup_map();
        add(gtk_champlain_widget);
    }

    public static MapWidget get_instance() {
        if (instance == null)
            instance = new MapWidget();
        return instance;
    }

    public override void drag_data_received(Gdk.DragContext context, int x, int y,
        Gtk.SelectionData selection_data, uint info, uint time) {
        bool success = false;
        Gee.List<MediaSource>? media = unserialize_media_sources(selection_data.get_data(),
            selection_data.get_length());
        if (media != null && media.size > 0) {
            double lat = map_view.y_to_latitude(y);
            double lon = map_view.x_to_longitude(x);
            success = internal_drop_received(media, lat, lon);
        }

        Gtk.drag_finish(context, success, false, time);
    }

    public void set_page(Page page) {
        this.page = page;
    }

    public void clear() {
        marker_layer.remove_all();
        marker_groups_tree.clear();
        marker_groups.clear();
        position_markers.clear();
    }

    public void add_position_marker(DataView view) {
        DataSource view_source = view.get_source();
        if (!(view_source is Positionable)) {
            return;
        }
        Positionable p = (Positionable) view_source;
        GpsCoords gps_coords = p.get_gps_coords();
        if (gps_coords.has_gps <= 0) {
            return;
        }

        // rasterize coords
        long x = (long)(map_view.longitude_to_x(gps_coords.longitude) / MARKER_GROUP_RASTER_WIDTH);
        long y = (long)(map_view.latitude_to_y(gps_coords.latitude) / MARKER_GROUP_RASTER_WIDTH);
        PositionMarker position_marker = create_position_marker(view);
        var yg = marker_groups_tree.get(x);
        if (yg == null) {
            // y group doesn't exist, initialize it
            yg = new Gee.TreeMap<long, MarkerGroup>();
            var mg = new MarkerGroup(this, position_marker);
            yg.set(y, mg);
            marker_groups.add(mg);
            marker_groups_tree.set(x, yg);
            add_marker(mg.marker);
        } else {
            var mg = yg.get(y);
            if (mg == null) {
                // first marker in this group
                mg = new MarkerGroup(this, position_marker);
                yg.set(y, mg);
                marker_groups.add(mg);
                add_marker(mg.marker);
            } else {
                // marker group already exists
                mg.add_marker(position_marker);
            }
        }

        position_markers.set(view, position_marker);
    }

    public void show_position_markers() {
        if (!position_markers.is_empty) {
            if (map_view.get_zoom_level() < DEFAULT_ZOOM_LEVEL) {
                map_view.set_zoom_level(DEFAULT_ZOOM_LEVEL);
            }
            Champlain.BoundingBox bbox = marker_layer.get_bounding_box();
            map_view.ensure_visible(bbox, true);
        }
    }

    public void select_data_view(PositionMarker m) {
        ViewCollection page_view = null;
        if (page != null)
            page_view = page.get_view();
        if (page_view != null && m.view is CheckerboardItem) {
            Marker marked = page_view.start_marking();
            marked.mark(m.view);
            page_view.unselect_all();
            page_view.select_marked(marked);
        }
    }

    public void highlight_data_view(PositionMarker m) {
        if (page != null && m.view is CheckerboardItem) {
            CheckerboardItem item = (CheckerboardItem) m.view;

            // if item is in any way out of view, scroll to it
            Gtk.Adjustment vadj = page.get_vadjustment();

            if (!(get_adjustment_relation(vadj, item.allocation.y) == AdjustmentRelation.IN_RANGE
                && (get_adjustment_relation(vadj, item.allocation.y + item.allocation.height) == AdjustmentRelation.IN_RANGE))) {

                // scroll to see the new item
                int top = 0;
                if (item.allocation.y < vadj.get_value()) {
                    top = item.allocation.y;
                    top -= CheckerboardLayout.ROW_GUTTER_PADDING / 2;
                } else {
                    top = item.allocation.y + item.allocation.height - (int) vadj.get_page_size();
                    top += CheckerboardLayout.ROW_GUTTER_PADDING / 2;
                }

                vadj.set_value(top);
            }
            item.brighten();
        }
    }

    public void unhighlight_data_view(PositionMarker m) {
        if (page != null && m.view is CheckerboardItem) {
            CheckerboardItem item = (CheckerboardItem) m.view;
            item.unbrighten();
        }
    }

    public void highlight_position_marker(DataView v) {
        PositionMarker? m = position_markers.get(v);
        if (m != null) {
            m.selected = true;
        }
    }

    public void unhighlight_position_marker(DataView v) {
        PositionMarker? m = position_markers.get(v);
        if (m != null) {
            m.selected = false;
        }
    }

    private void setup_map() {
        map_view = gtk_champlain_widget.get_view();
        map_view.add_layer(marker_layer);

        // add scale to bottom left corner of the map
        map_scale.content_gravity = Clutter.ContentGravity.BOTTOM_LEFT;
        map_scale.connect_view(map_view);
        map_view.bin_layout_add(map_scale, Clutter.BinAlignment.START, Clutter.BinAlignment.END);

        map_view.set_zoom_on_double_click(false);
        map_view.layer_relocated.connect(map_relocated_handler);

        Gtk.TargetEntry[] dnd_targets = {
            LibraryWindow.DND_TARGET_ENTRIES[LibraryWindow.TargetType.URI_LIST],
            LibraryWindow.DND_TARGET_ENTRIES[LibraryWindow.TargetType.MEDIA_LIST]
        };
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, dnd_targets,
            Gdk.DragAction.COPY | Gdk.DragAction.LINK | Gdk.DragAction.ASK);
        button_press_event.connect(map_zoom_handler);
        set_size_request(200, 200);

        // Load icons
        float w, h;
        marker_image = Resources.get_icon_as_clutter_image(
                Resources.ICON_GPS_MARKER, out w, out h);
        marker_image_width = w;
        marker_image_height = h;
        marker_selected_image = Resources.get_icon_as_clutter_image(
                Resources.ICON_GPS_MARKER_SELECTED, out w, out h);
        }
    }

    private PositionMarker create_position_marker(DataView view) {
        DataSource data_source = view.get_source();
        Positionable p = (Positionable) data_source;
        GpsCoords gps_coords = p.get_gps_coords();
        assert(gps_coords.has_gps > 0);
        Champlain.Marker champlain_marker;
        if (marker_image == null) {
            // Fall back to the generic champlain marker
            champlain_marker = new Champlain.Point.full(12, marker_point_color);
        } else {
            champlain_marker = new Champlain.Marker();
            champlain_marker.set_content(marker_image);
            champlain_marker.set_size(marker_image_width, marker_image_height);
            champlain_marker.notify.connect((o, p) => {
                Champlain.Marker? m = o as Champlain.Marker;
                if (p.name == "selected")
                    m.set_content(m.selected ? marker_selected_image : marker_image);
            });
        }
        champlain_marker.set_pivot_point(0.5f, 0.5f); // set center of marker
        champlain_marker.set_location(gps_coords.latitude, gps_coords.longitude);
        return new PositionMarker(this, view, champlain_marker);
    }

    private void add_marker(Champlain.Marker marker) {
        marker_layer.add_marker(marker);
    }

    private bool map_zoom_handler(Gdk.EventButton event) {
        if (event.type == Gdk.EventType.2BUTTON_PRESS) {
            if (event.button == 1 || event.button == 3) {
                double lat = map_view.y_to_latitude(event.y);
                double lon = map_view.x_to_longitude(event.x);
                if (event.button == 1) {
                    map_view.zoom_in();
                } else {
                    map_view.zoom_out();
                }
                map_view.center_on(lat, lon);
                return true;
            }
        }
        return false;
    }

    private void map_relocated_handler() {
        uint new_zoom_level = map_view.get_zoom_level();
        if (last_zoom_level != new_zoom_level) {
            rezoom();
            last_zoom_level = new_zoom_level;
        }
    }

    private void rezoom() {
        marker_groups_tree.clear();
        Gee.Collection<MarkerGroup> marker_groups_new = new Gee.LinkedList<MarkerGroup>();
        foreach (var marker_group in marker_groups) {
            marker_layer.remove_marker(marker_group.marker);
            foreach (var position_marker in marker_group.get_markers()) {
                // rasterize coords
                long x = (long)(map_view.longitude_to_x(position_marker.marker.longitude) / MARKER_GROUP_RASTER_WIDTH);
                long y = (long)(map_view.latitude_to_y(position_marker.marker.latitude) / MARKER_GROUP_RASTER_WIDTH);
                var yg = marker_groups_tree.get(x);
                if (yg == null) {
                    // y group doesn't exist, initialize it
                    yg = new Gee.TreeMap<long, MarkerGroup>();
                    var mg = new MarkerGroup(this, position_marker);
                    yg.set(y, mg);
                    marker_groups_new.add(mg);
                    marker_groups_tree.set(x, yg);
                    add_marker(mg.marker);
                } else {
                    var mg = yg.get(y);
                    if (mg == null) {
                        // first marker -> create new group
                        mg = new MarkerGroup(this, position_marker);
                        yg.set(y, mg);
                        marker_groups_new.add(mg);
                        add_marker(mg.marker);
                    } else {
                        // marker group already exists
                        mg.add_marker(position_marker);
                    }
                }
            }
        }
        marker_groups = marker_groups_new;
    }

    private bool internal_drop_received(Gee.List<MediaSource> media, double lat, double lon) {
        int i = 0;
        bool success = false;
        while (i < media.size) {
            Positionable p = media.get(i) as Positionable;
            if (p != null) {
                GpsCoords gps_coords = GpsCoords() {
                    has_gps = 1,
                    latitude = lat,
                    longitude = lon
                };
                p.set_gps_coords(gps_coords);
                success = true;
            }
            ++i;
        }
        return success;
    }
}
