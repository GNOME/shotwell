/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

private class MarkerImageSet {
    public float marker_image_width;
    public float marker_image_height;
    public Clutter.Image? marker_image;
    public Clutter.Image? marker_selected_image;
    public Clutter.Image? marker_highlighted_image;
}

private enum SelectionAction {
    SET,
    ADD,
    REMOVE
}

private abstract class PositionMarker : Object {
    protected bool _highlighted = false;
    protected bool _selected = false;
    protected MarkerImageSet image_set;

    protected PositionMarker(Champlain.Marker champlain_marker, MarkerImageSet image_set) {
        this.champlain_marker = champlain_marker;
        this.image_set = image_set;
        champlain_marker.selectable = true;
        champlain_marker.set_content(image_set.marker_image);
        float w = image_set.marker_image_width;
        float h = image_set.marker_image_height;
        champlain_marker.set_size(w, h);
        champlain_marker.set_translation(-w * MapWidget.MARKER_IMAGE_HORIZONTAL_PIN_RATIO,
                                         -h * MapWidget.MARKER_IMAGE_VERTICAL_PIN_RATIO, 0);
    }

    public Champlain.Marker champlain_marker { get; protected set; }

    public bool highlighted {
        get {
            return _highlighted;
        }
        set {
            if (_highlighted == value)
                return;
            _highlighted = value;
            var base_image = _selected ? image_set.marker_selected_image : image_set.marker_image;
            champlain_marker.set_content(value ? image_set.marker_highlighted_image : base_image);
        }
    }
    public bool selected {
        get {
            return _selected;
        }
        set {
            if (_selected == value)
                return;
            _selected = value;
            if (!_highlighted) {
                var base_image = value ?  image_set.marker_selected_image : image_set.marker_image;
                champlain_marker.set_content(base_image);
            }
            champlain_marker.set_selected(value);
        }
    }
}

private class DataViewPositionMarker : PositionMarker {
    private Gee.LinkedList<weak DataViewPositionMarker> _data_view_position_markers =
            new Gee.LinkedList<weak DataViewPositionMarker>();

    public weak DataView view { get; protected set; }

    public DataViewPositionMarker(DataView view, Champlain.Marker champlain_marker,
            MarkerImageSet image_set) {
        base(champlain_marker, image_set);
        this.view = view;

        this._data_view_position_markers.add(this);
    }

    public void bind_mouse_events(MapWidget map_widget) {
        champlain_marker.button_release_event.connect ((event) => {
            if (event.button > 1)
                return true;
            bool mod = (bool)(event.modifier_state &
                    (Clutter.ModifierType.CONTROL_MASK | Clutter.ModifierType.SHIFT_MASK));
            SelectionAction action = SelectionAction.SET;
            if (mod)
                action = _selected ? SelectionAction.REMOVE : SelectionAction.ADD;
            selected = (action != SelectionAction.REMOVE);
            map_widget.select_data_views(_data_view_position_markers, action);
            return true;
        });
        champlain_marker.enter_event.connect ((event) => {
            highlighted = true;
            map_widget.highlight_data_views(_data_view_position_markers);
            return true;
        });
        champlain_marker.leave_event.connect ((event) => {
            highlighted = false;
            map_widget.unhighlight_data_views(_data_view_position_markers);
            return true;
        });
    }
}

private class MarkerGroup : PositionMarker {
    private Gee.Collection<DataViewPositionMarker> _data_view_position_markers =
        new Gee.LinkedList<DataViewPositionMarker>();
    private Gee.Collection<PositionMarker> _position_markers = new Gee.LinkedList<PositionMarker>();
    private Champlain.BoundingBox bbox = new Champlain.BoundingBox();

    public void bind_mouse_events(MapWidget map_widget) {
        champlain_marker.button_release_event.connect ((event) => {
            if (event.button > 1)
                return true;
            bool mod = (bool)(event.modifier_state &
                    (Clutter.ModifierType.CONTROL_MASK | Clutter.ModifierType.SHIFT_MASK));
            SelectionAction action = SelectionAction.SET;
            if (mod)
                action = _selected ? SelectionAction.REMOVE : SelectionAction.ADD;
            selected = (action != SelectionAction.REMOVE);
            foreach (var m in _data_view_position_markers) {
                m.selected = _selected;
            }
            map_widget.select_data_views(_data_view_position_markers.read_only_view, action);
            return true;
        });
        champlain_marker.enter_event.connect ((event) => {
            highlighted = true;
            map_widget.highlight_data_views(_data_view_position_markers.read_only_view);
            return true;
        });
        champlain_marker.leave_event.connect ((event) => {
            highlighted = false;
            map_widget.unhighlight_data_views(_data_view_position_markers.read_only_view);
            return true;
        });
    }

    public Gee.Collection<PositionMarker> position_markers {
        owned get { return _position_markers.read_only_view; }
    }

    public MarkerGroup(Champlain.Marker champlain_marker, MarkerImageSet image_set) {
        base(champlain_marker, image_set);
    }

    public void add_position_marker(PositionMarker marker) {
        var data_view_position_marker = marker as DataViewPositionMarker;
        if (data_view_position_marker != null)
            _data_view_position_markers.add(data_view_position_marker);
        var new_champlain_marker = marker.champlain_marker;
        bbox.extend(new_champlain_marker.latitude, new_champlain_marker.longitude);
        double lat, lon;
        bbox.get_center(out lat, out lon);
        champlain_marker.set_location(lat, lon);
        _position_markers.add(marker);
    }
}

private class MarkerGroupRaster : Object {
    private const long MARKER_GROUP_RASTER_WIDTH_PX = 30l;
    private const long MARKER_GROUP_RASTER_HEIGHT_PX = 30l;

    private weak MapWidget map_widget;
    private weak Champlain.View map_view;
    private weak Champlain.MarkerLayer marker_layer;

    public bool is_empty {
        get {
            return position_markers.is_empty;
        }
    }

    // position_markers_tree is a two-dimensional tree for grouping position
    // markers indexed by x (outer tree) and y (inner tree) raster coordinates.
    // It maps coordinates to the PositionMarker (DataViewMarker or MarkerGroup)
    // corresponding to them.
    // If either raster index keys are empty, there is no marker within the
    // raster cell. If both exist there are two possibilities:
    // (1) the value is a MarkerGroup which means that multiple markers are
    // grouped together, or (2) the value is a PositionMarker (but not a
    // MarkerGroup) which means that there is exactly one marker in the raster
    // cell. The tree is recreated every time the zoom level changes.
    private Gee.TreeMap<long, Gee.TreeMap<long, unowned PositionMarker?>?> position_markers_tree =
        new Gee.TreeMap<long, Gee.TreeMap<long, unowned PositionMarker?>?>();
    // The marker group's collection keeps track of and owns all PositionMarkers including the marker groups
    private Gee.Map<DataView, unowned PositionMarker> data_view_map = new Gee.HashMap<DataView, unowned PositionMarker>();
    private Gee.Set<PositionMarker> position_markers = new Gee.HashSet<PositionMarker>();

    public MarkerGroupRaster(MapWidget map_widget, Champlain.View map_view, Champlain.MarkerLayer marker_layer) {
        this.map_widget = map_widget;
        this.map_view = map_view;
        this.marker_layer = marker_layer;
        map_widget.zoom_changed.connect(regroup);
    }

    public void clear() {
        lock (position_markers) {
            data_view_map.clear();
            position_markers_tree.clear();
            position_markers.clear();
        }
    }

    public void clear_selection() {
        lock (position_markers) {
            foreach (PositionMarker m in position_markers) {
                m.selected = false;
            }
        }
    }

    public unowned PositionMarker? find_position_marker(DataView data_view) {
        if (!data_view_map.has_key(data_view))
            return null;
        unowned PositionMarker? m;
        lock (position_markers) {
            m = data_view_map.get(data_view);
        }
        return m;
    }

    public void rasterize_marker(PositionMarker position_marker, bool already_on_map=false) {
        var data_view_position_marker = position_marker as DataViewPositionMarker;
        var champlain_marker = position_marker.champlain_marker;
        long x, y;

        lock (position_markers) {
            rasterize_coords(champlain_marker.longitude, champlain_marker.latitude, out x, out y);
            var yg = position_markers_tree.get(x);
            if (yg == null) {
                yg = new Gee.TreeMap<long, unowned PositionMarker?>();
                position_markers_tree.set(x, yg);
            }
            var cell = yg.get(y);
            if (cell == null) {
                // first marker in this raster cell
                yg.set(y, position_marker);
                position_markers.add(position_marker);
                if (!already_on_map)
                    marker_layer.add_marker(position_marker.champlain_marker);
                if (data_view_position_marker != null)
                    data_view_map.set(data_view_position_marker.view, position_marker);

            } else {
                var marker_group = cell as MarkerGroup;
                if (marker_group == null) {
                    // single marker already occupies raster cell: create new group
                    GpsCoords rasterized_gps_coords = GpsCoords() {
                        has_gps = 1,
                        longitude = map_view.x_to_longitude(x),
                        latitude = map_view.y_to_latitude(y)
                    };
                    marker_group = map_widget.create_marker_group(rasterized_gps_coords);
                    marker_group.add_position_marker(cell);
                    if (cell.selected) // group becomes selected if any contained marker is
                        marker_group.selected = true;
                    if (cell is DataViewPositionMarker)
                        data_view_map.set(((DataViewPositionMarker) cell).view, marker_group);
                    yg.set(y, marker_group);
                    position_markers.add(marker_group);
                    position_markers.remove(cell);
                    marker_layer.add_marker(marker_group.champlain_marker);
                    marker_layer.remove_marker(cell.champlain_marker);
                }
                // group already exists, add new marker to it
                marker_group.add_position_marker(position_marker);
                if (already_on_map)
                    marker_layer.remove_marker(position_marker.champlain_marker);
                if (data_view_position_marker != null)
                    data_view_map.set(data_view_position_marker.view, marker_group);
            }
        }
    }

    private void rasterize_coords(double longitude, double latitude, out long x, out long y) {
        x = (Math.lround(map_view.longitude_to_x(longitude) / MARKER_GROUP_RASTER_WIDTH_PX)) *
            MARKER_GROUP_RASTER_WIDTH_PX + (MARKER_GROUP_RASTER_WIDTH_PX / 2);
        y = (Math.lround(map_view.latitude_to_y(latitude) / MARKER_GROUP_RASTER_HEIGHT_PX)) *
            MARKER_GROUP_RASTER_HEIGHT_PX + (MARKER_GROUP_RASTER_HEIGHT_PX / 2);
    }

    internal void regroup() {
        lock (position_markers) {
            var position_markers_current = (owned) position_markers;
            position_markers = new Gee.HashSet<PositionMarker>();
            position_markers_tree.clear();

            foreach (var pm in position_markers_current) {
                var marker_group = pm as MarkerGroup;
                if (marker_group != null) {
                    marker_layer.remove_marker(marker_group.champlain_marker);
                    foreach (var position_marker in marker_group.position_markers) {
                        rasterize_marker(position_marker, false);
                    }
                } else {
                    rasterize_marker(pm, true);
                }
            }
            position_markers_current = null;
        }
    }
}

private class MapWidget : Gtk.Bin {
    private const uint DEFAULT_ZOOM_LEVEL = 8;

    private static MapWidget instance = null;
    private bool hide_map = false;

    private GtkChamplain.Embed gtk_champlain_widget = new GtkChamplain.Embed();
    private Champlain.View map_view = null;
    private Champlain.Scale map_scale = new Champlain.Scale();
    private Champlain.MarkerLayer marker_layer = new Champlain.MarkerLayer();
    public bool map_edit_lock { get; set; }
    private MarkerGroupRaster marker_group_raster = null;
    private Gee.Map<DataView, unowned DataViewPositionMarker> data_view_marker_cache =
        new Gee.HashMap<DataView, unowned DataViewPositionMarker>();
    private weak Page? page = null;
    private Clutter.Image? map_edit_locked_image;
    private Clutter.Image? map_edit_unlocked_image;
    private Clutter.Actor map_edit_lock_button = new Clutter.Actor();
    private uint position_markers_timeout = 0;

    public const float MARKER_IMAGE_HORIZONTAL_PIN_RATIO = 0.5f;
    public const float MARKER_IMAGE_VERTICAL_PIN_RATIO = 0.825f;
    public float map_edit_lock_image_width { get; private set; }
    public float map_edit_lock_image_height { get; private set; }
    public MarkerImageSet marker_image_set { get; private set; }
    public MarkerImageSet marker_group_image_set { get; private set; }
    public const Clutter.Color marker_point_color = { 10, 10, 255, 192 };

    public signal void zoom_changed();

    private MapWidget() {
        setup_map();
        add(gtk_champlain_widget);
    }

    public static MapWidget get_instance() {
        if (instance == null)
            instance = new MapWidget();
        return instance;
    }

    public override bool drag_motion(Gdk.DragContext context, int x, int y, uint time) {
        if (!map_edit_lock)
            map_view.stop_go_to();
        else
            Gdk.drag_status(context, 0, time);
        return true;
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

    public new void set_visible(bool visible) {
        /* hides Gtk.Widget.set_visible */
        hide_map = !visible;
        base.set_visible(visible);
    }

    public override void show_all() {
        if (!hide_map)
            base.show_all();
    }

    public void set_page(Page page) {
        bool page_changed = false;
        if (this.page != page) {
            this.page = page;
            page_changed = true;
            clear();
        }
        ViewCollection view_collection = page.get_view();
        if (view_collection == null)
            return;

        if (page_changed) {
            data_view_marker_cache.clear();
            foreach (DataObject view in view_collection.get_all()) {
                if (view is DataView)
                    add_data_view((DataView) view);
            }
            show_position_markers();
        }
        // In any case, the selection did change..
        var selected = view_collection.get_selected();
        if (selected != null) {
            marker_group_raster.clear_selection();
            foreach (DataView v in view_collection.get_selected()) {

                var position_marker = marker_group_raster.find_position_marker(v);
                if (position_marker != null)
                    position_marker.selected = true;
                if (position_marker is MarkerGroup) {
                    DataViewPositionMarker? m = data_view_marker_cache.get(v);
                    if (m != null)
                        m.selected = true;
                }
            }
        }
    }

    public void clear() {
        data_view_marker_cache.clear();
        marker_layer.remove_all();
        marker_group_raster.clear();
    }

    public void add_data_view(DataView view) {
        DataSource view_source = view.get_source();
        if (!(view_source is Positionable))
            return;
        Positionable p = (Positionable) view_source;
        GpsCoords gps_coords = p.get_gps_coords();
        if (gps_coords.has_gps <= 0)
            return;
        PositionMarker position_marker = create_position_marker(view);
        marker_group_raster.rasterize_marker(position_marker);
    }

    public void show_position_markers() {
        if (marker_group_raster.is_empty)
            return;

        map_view.stop_go_to();
        double lat, lon;
        var bbox = marker_layer.get_bounding_box();
        var zoom_level = map_view.get_zoom_level();
        var zoom_level_test = zoom_level < 2 ? 0 : zoom_level - 2;
        bbox.get_center(out lat, out lon);

        if (map_view.get_bounding_box_for_zoom_level(zoom_level_test).covers(lat, lon)) {
            // Don't zoom in/out if target is in proximity
            map_view.ensure_visible(bbox, true);
        } else if (zoom_level >= DEFAULT_ZOOM_LEVEL) {
            // zoom out to DEFAULT_ZOOM_LEVEL first, then move
            map_view.set_zoom_level(DEFAULT_ZOOM_LEVEL);
            map_view.ensure_visible(bbox, true);
        } else {
            // move first, then zoom in to DEFAULT_ZOOM_LEVEL
            map_view.go_to(lat, lon);
            // There seems to be a runtime issue with the animation_completed signal
            // sig = map_view.animation_completed["go-to"].connect((v) => { ... }
            // so we're using a timeout-based approach instead. It should be kept in sync with
            // the animation time (500ms by default.)
            if (position_markers_timeout > 0)
                Source.remove(position_markers_timeout);
            position_markers_timeout = Timeout.add(500, () => {
                map_view.center_on(lat, lon); // ensure the timeout wasn't too fast
                if (map_view.get_zoom_level() < DEFAULT_ZOOM_LEVEL)
                    map_view.set_zoom_level(DEFAULT_ZOOM_LEVEL);
                map_view.ensure_visible(bbox, true);
                position_markers_timeout = 0;
                return Source.REMOVE;
            });
        }
    }

    public void select_data_views(Gee.Collection<unowned DataViewPositionMarker> ms,
            SelectionAction action = SelectionAction.SET) {
        if (page == null)
            return;

        ViewCollection page_view = page.get_view();
        if (page_view != null) {
            Marker marked = page_view.start_marking();
            foreach (var m in ms) {
                if (m.view is CheckerboardItem) {
                    marked.mark(m.view);
                }
            }
            if (action == SelectionAction.REMOVE) {
                page_view.unselect_marked(marked);
            } else {
                if (action == SelectionAction.SET)
                    page_view.unselect_all();
                page_view.select_marked(marked);
            }
        }
    }

    public void highlight_data_views(Gee.Collection<unowned DataViewPositionMarker> ms) {
        if (page == null)
            return;

        bool did_adjust_view = false;
        foreach (var m in ms) {
            if (m.view is CheckerboardItem) {
                CheckerboardItem item = (CheckerboardItem) m.view;

                if (!did_adjust_view) {
                    // if first item is in any way out of view, scroll to it
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
                    did_adjust_view = true;
                }
                item.brighten();
            }
        }
    }

    public void unhighlight_data_views(Gee.Collection<unowned DataViewPositionMarker> ms) {
        if (page == null)
            return;

        foreach (var m in ms) {
            if (m.view is CheckerboardItem) {
                CheckerboardItem item = (CheckerboardItem) m.view;
                item.unbrighten();
            }
        }
    }

    public void highlight_position_marker(DataView v) {
        var position_marker = marker_group_raster.find_position_marker(v);
        if (position_marker != null) {
            position_marker.highlighted = true;
        }
    }

    public void unhighlight_position_marker(DataView v) {
        var position_marker = marker_group_raster.find_position_marker(v);
        if (position_marker != null) {
            position_marker.highlighted = false;
        }
    }

    public void media_source_position_changed(Gee.List<MediaSource> media, GpsCoords gps_coords) {
        if (page == null)
            return;
        var view_collection = page.get_view();
        foreach (var source in media) {
            var view = view_collection.get_view_for_source(source);
            if (view == null)
                continue;
            var marker = data_view_marker_cache.get(view);
            if (marker != null) {
                if (gps_coords.has_gps > 0) {
                    // update individual marker cache
                    marker.champlain_marker.set_location(gps_coords.latitude, gps_coords.longitude);
                } else {
                    // TODO: position removal not supported by GUI
                    // remove marker from cache, map_layer
                    // remove from marker_group_raster (needs a removal method which also removes the
                    // item from the group if (marker_group_raster.find_position_marker(view) is MarkerGroup)
                }
            }
        }
        marker_group_raster.regroup();
    }

    private void setup_map() {
        map_view = gtk_champlain_widget.get_view();
        map_view.add_layer(marker_layer);

        // add lock/unlock button to top left corner of map
        map_edit_lock_button.content_gravity = Clutter.ContentGravity.TOP_RIGHT;
        map_edit_lock_button.reactive = true;
        map_edit_lock_button.button_release_event.connect((a, e) => {
            if (e.button != 1 /* CLUTTER_BUTTON_PRIMARY */)
                return false;
            map_edit_lock = !map_edit_lock;
            map_edit_lock_button.set_content(map_edit_lock ?
                map_edit_locked_image : map_edit_unlocked_image);
            return true;
        });
        map_view.bin_layout_add(map_edit_lock_button, Clutter.BinAlignment.END, Clutter.BinAlignment.START);
        gtk_champlain_widget.has_tooltip = true;
        gtk_champlain_widget.query_tooltip.connect((x, y, keyboard_tooltip, tooltip) => {
            Gdk.Rectangle lock_rect = {
                (int) map_edit_lock_button.x,
                (int) map_edit_lock_button.y,
                (int) map_edit_lock_button.width,
                (int) map_edit_lock_button.height,
            };
            Gdk.Rectangle mouse_pos = { x, y, 1, 1 };
            if (!lock_rect.intersect(mouse_pos, null))
                return false;
            tooltip.set_text(_("Lock or unlock map for geotagging by dragging pictures onto the map"));
            return true;
        });

        // add scale to bottom left corner of the map
        map_scale.content_gravity = Clutter.ContentGravity.BOTTOM_LEFT;
        map_scale.connect_view(map_view);
        map_view.bin_layout_add(map_scale, Clutter.BinAlignment.START, Clutter.BinAlignment.END);

        map_view.set_zoom_on_double_click(false);
        map_view.notify.connect((o, p) => {
            if (p.name == "zoom-level")
                zoom_changed();
        });

        Gtk.TargetEntry[] dnd_targets = {
            LibraryWindow.DND_TARGET_ENTRIES[LibraryWindow.TargetType.URI_LIST],
            LibraryWindow.DND_TARGET_ENTRIES[LibraryWindow.TargetType.MEDIA_LIST]
        };
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, dnd_targets,
            Gdk.DragAction.COPY | Gdk.DragAction.LINK | Gdk.DragAction.ASK);
        button_press_event.connect(map_zoom_handler);
        set_size_request(200, 200);

        marker_group_raster = new MarkerGroupRaster(this, map_view, marker_layer);

        // Load icons
        float w, h;
        marker_image_set = new MarkerImageSet();
        marker_group_image_set = new MarkerImageSet();
        marker_image_set.marker_image = Resources.get_icon_as_clutter_image(
                Resources.ICON_GPS_MARKER, out w, out h);
        marker_image_set.marker_image_width = w;
        marker_image_set.marker_image_height = h;
        marker_image_set.marker_selected_image = Resources.get_icon_as_clutter_image(
                Resources.ICON_GPS_MARKER_SELECTED, out w, out h);
        marker_image_set.marker_highlighted_image = Resources.get_icon_as_clutter_image(
                Resources.ICON_GPS_MARKER_HIGHLIGHTED, out w, out h);

        marker_group_image_set.marker_image = Resources.get_icon_as_clutter_image(
                Resources.ICON_GPS_GROUP_MARKER, out w, out h);
        marker_group_image_set.marker_image_width = w;
        marker_group_image_set.marker_image_height = h;
        marker_group_image_set.marker_selected_image = Resources.get_icon_as_clutter_image(
                Resources.ICON_GPS_GROUP_MARKER_SELECTED, out w, out h);
        marker_group_image_set.marker_highlighted_image = Resources.get_icon_as_clutter_image(
                Resources.ICON_GPS_GROUP_MARKER_HIGHLIGHTED, out w, out h);

        map_edit_locked_image = Resources.get_icon_as_clutter_image(
                Resources.ICON_MAP_EDIT_LOCKED, out w, out h);
        map_edit_unlocked_image = Resources.get_icon_as_clutter_image(
                Resources.ICON_MAP_EDIT_UNLOCKED, out w, out h);
        map_edit_lock_image_width = w;
        map_edit_lock_image_height = h;
        if (map_edit_locked_image == null) {
            warning("Couldn't load map edit lock image");
        } else {
            map_edit_lock_button.set_content(map_edit_locked_image);
            map_edit_lock_button.set_size(map_edit_lock_image_width, map_edit_lock_image_height);
            map_edit_lock = true;
        }
    }

    private Champlain.Marker create_champlain_marker(GpsCoords gps_coords) {
        assert(gps_coords.has_gps > 0);

        Champlain.Marker champlain_marker;
        champlain_marker = new Champlain.Marker();
        champlain_marker.set_pivot_point(0.5f, 0.5f); // set center of marker
        champlain_marker.set_location(gps_coords.latitude, gps_coords.longitude);
        return champlain_marker;
    }

    private DataViewPositionMarker create_position_marker(DataView view) {
        var position_marker = data_view_marker_cache.get(view);
        if (position_marker != null)
            return position_marker;
        DataSource data_source = view.get_source();
        Positionable p = (Positionable) data_source;
        GpsCoords gps_coords = p.get_gps_coords();
        Champlain.Marker champlain_marker = create_champlain_marker(gps_coords);
        position_marker = new DataViewPositionMarker(view, champlain_marker, marker_image_set);
        position_marker.bind_mouse_events(this);
        data_view_marker_cache.set(view, position_marker);
        return (owned) position_marker;
    }

    internal MarkerGroup create_marker_group(GpsCoords gps_coords) {
        Champlain.Marker champlain_marker = create_champlain_marker(gps_coords);
        var g = new MarkerGroup(champlain_marker, marker_group_image_set);
        g.bind_mouse_events(this);
        return (owned) g;
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

    private bool internal_drop_received(Gee.List<MediaSource> media, double lat, double lon) {
        if (map_edit_lock)
            return false;

        bool success = false;
        GpsCoords gps_coords = GpsCoords() {
            has_gps = 1,
            latitude = lat,
            longitude = lon
        };
        foreach (var m in media) {
            Positionable p = m as Positionable;
            if (p != null) {
                p.set_gps_coords(gps_coords);
                success = true;
            }
        }
        media_source_position_changed(media, gps_coords);
        return success;
    }
}
