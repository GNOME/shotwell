/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class DiscoveredCamera {
    public GPhoto.Camera gcamera;
    public string uri;
    
    public DiscoveredCamera(GPhoto.Camera gcamera, string uri) {
        this.gcamera = gcamera;
        this.uri = uri;
    }
}

public class CameraTable {
    private const int UPDATE_DELAY_MSEC = 500;
    
    private static CameraTable instance = null;
    private static bool camera_update_scheduled = false;
    
    // these need to be ref'd the lifetime of the instance, of which there is only one
    private Hal.Context hal_context = new Hal.Context();
    private DBus.Connection hal_conn = null;

    private GPhoto.Context null_context = new GPhoto.Context();
    private GPhoto.CameraAbilitiesList abilities_list;
    
    private Gee.HashMap<string, DiscoveredCamera> camera_map = new Gee.HashMap<string, DiscoveredCamera>(
        str_hash, str_equal, direct_equal);

    public signal void camera_added(DiscoveredCamera camera);
    
    public signal void camera_removed(DiscoveredCamera camera);
    
    private CameraTable() {
        // set up HAL connection to monitor for device insertion/removal, to look for cameras
        hal_conn = DBus.Bus.get(DBus.BusType.SYSTEM);
        if (!hal_context.set_dbus_connection(hal_conn.get_connection()))
            error("Unable to set DBus connection for HAL");

        DBus.RawError raw = DBus.RawError();
        if (!hal_context.init(ref raw))
            error("Unable to initialize context: %s", raw.message);

        if (!hal_context.set_device_added(on_device_added))
            error("Unable to register device-added callback");
        if (!hal_context.set_device_removed(on_device_removed))
            error("Unable to register device-removed callback");

        // because loading the camera abilities list takes a bit of time and slows down app
        // startup, delay loading it (and notifying any observers) for a small period of time,
        // after the dust has settled
        Timeout.add(500, delayed_init);
    }
    
    private bool delayed_init() {
        try {
            init_camera_table();
            update_camera_table();
        } catch (GPhotoError err) {
            error("%s", err.message);
        }
        
        return false;
    }
    
    public static CameraTable get_instance() {
        if (instance == null)
            instance = new CameraTable();
        
        return instance;
    }
    
    public Gee.Iterable<DiscoveredCamera> get_cameras() {
        return camera_map.values;
    }
    
    public int get_count() {
        return camera_map.size;
    }
    
    public DiscoveredCamera? get_for_uri(string uri) {
        return camera_map.get(uri);
    }

    private void do_op(GPhoto.Result res, string op) throws GPhotoError {
        if (res != GPhoto.Result.OK)
            throw new GPhotoError.LIBRARY("[%d] Unable to %s: %s", (int) res, op, res.as_string());
    }
    
    private void init_camera_table() throws GPhotoError {
        do_op(GPhoto.CameraAbilitiesList.create(out abilities_list), "create camera abilities list");
        do_op(abilities_list.load(null_context), "load camera abilities list");
    }
    
    // USB (or libusb) is a funny beast; if only one USB device is present (i.e. the camera),
    // then a single camera is detected at port usb:.  However, if multiple USB devices are
    // present (including non-cameras), then the first attached camera will be listed twice,
    // first at usb:, then at usb:xxx,yyy.  If the usb: device is removed, another usb:xxx,yyy
    // device will lose its full-path name and be referred to as usb: only.
    //
    // This function gleans the full port name of a particular port, even if it's the unadorned
    // "usb:", by using HAL.
    private string? esp_usb_to_udi(int camera_count, string port, out string full_port) {
        // sanity
        assert(camera_count > 0);
        
        debug("ESP: camera_count=%d port=%s", camera_count, port);

        DBus.RawError raw = DBus.RawError();
        string[] udis = hal_context.find_device_by_capability("camera", ref raw);
        
        string[] usbs = new string[0];
        foreach (string udi in udis) {
            if (hal_context.device_get_property_string(udi, "info.subsystem", ref raw) == "usb")
                usbs += udi;
        }

        // if GPhoto detects one camera, and HAL reports one USB camera, all is swell
        if (camera_count == 1 && usbs.length ==1) {
            string usb = usbs[0];
            
            int hal_bus = hal_context.device_get_property_int(usb, "usb.bus_number", ref raw);
            int hal_device = hal_context.device_get_property_int(usb, "usb.linux.device_number",
                ref raw);

            if (port == "usb:") {
                // the most likely case, so make a full path
                full_port = "usb:%03d,%03d".printf(hal_bus, hal_device);
            } else {
                full_port = port;
            }
            
            debug("ESP: port=%s full_port=%s udi=%s", port, full_port, usb);
            
            return usb;
        }

        // with more than one camera, skip the mirrored "usb:" port
        if (port == "usb:") {
            debug("ESP: Skipping %s", port);
            
            return null;
        }
        
        // parse out the bus and device ID
        int bus, device;
        if (port.scanf("usb:%d,%d", out bus, out device) < 2)
            error("ESP: Failed to scanf %s", port);
        
        foreach (string usb in usbs) {
            int hal_bus = hal_context.device_get_property_int(usb, "usb.bus_number", ref raw);
            int hal_device = hal_context.device_get_property_int(usb, "usb.linux.device_number", ref raw);
            
            if ((bus == hal_bus) && (device == hal_device)) {
                full_port = port;
                
                debug("ESP: port=%s full_port=%s udi=%s", port, full_port, usb);

                return usb;
            }
        }
        
        debug("ESP: No UDI found for port=%s", port);
        
        return null;
    }
    
    public static string get_port_uri(string port) {
        return "gphoto2://[%s]/".printf(port);
    }

    private void update_camera_table() throws GPhotoError {
        // need to do this because virtual ports come and go in the USB world (and probably others)
        GPhoto.PortInfoList port_info_list;
        do_op(GPhoto.PortInfoList.create(out port_info_list), "create port list");
        do_op(port_info_list.load(), "load port list");

        GPhoto.CameraList camera_list;
        do_op(GPhoto.CameraList.create(out camera_list), "create camera list");
        do_op(abilities_list.detect(port_info_list, camera_list, null_context), "detect cameras");
        
        Gee.HashMap<string, string> detected_map = new Gee.HashMap<string, string>(str_hash, str_equal,
            str_equal);
        
        // go through the detected camera list and glean their ports
        for (int ctr = 0; ctr < camera_list.count(); ctr++) {
            string name;
            do_op(camera_list.get_name(ctr, out name), "get detected camera name");

            string port;
            do_op(camera_list.get_value(ctr, out port), "get detected camera port");
            
            debug("Detected %s @ %s", name, port);
            
            // do some USB ESP, skipping ports that cannot be deduced
            if (port.has_prefix("usb:")) {
                string full_port;
                string udi = esp_usb_to_udi(camera_list.count(), port, out full_port);
                if (udi == null)
                    continue;
                
                port = full_port;
            }

            detected_map.set(port, name);
        }
        
        // find cameras that have disappeared
        DiscoveredCamera[] missing = new DiscoveredCamera[0];
        foreach (DiscoveredCamera camera in camera_map.values) {
            GPhoto.PortInfo port_info;
            do_op(camera.gcamera.get_port_info(out port_info), 
                "retrieve missing camera port information");
            
            GPhoto.CameraAbilities abilities;
            do_op(camera.gcamera.get_abilities(out abilities), "retrieve camera abilities");
            
            if (detected_map.has_key(port_info.path)) {
                debug("Found page for %s @ %s in detected cameras", abilities.model, port_info.path);
                
                continue;
            }
            
            debug("%s @ %s missing", abilities.model, port_info.path);
            
            missing += camera;
        }
        
        // have to remove from hash map outside of iterator
        foreach (DiscoveredCamera camera in missing) {
            GPhoto.PortInfo port_info;
            do_op(camera.gcamera.get_port_info(out port_info),
                "retrieve missing camera port information");
            
            GPhoto.CameraAbilities abilities;
            do_op(camera.gcamera.get_abilities(out abilities), "retrieve missing camera abilities");

            debug("Removing from camera table: %s @ %s", abilities.model, port_info.path);

            camera_map.unset(get_port_uri(port_info.path));
            
            camera_removed(camera);
        }

        // add cameras which were not present before
        foreach (string port in detected_map.keys) {
            string name = detected_map.get(port);
            string uri = get_port_uri(port);

            if (camera_map.has_key(uri)) {
                // already known about
                debug("%s @ %s already registered, skipping", name, port);
                
                continue;
            }
            
            int index = port_info_list.lookup_path(port);
            if (index < 0)
                do_op((GPhoto.Result) index, "lookup port %s".printf(port));
            
            GPhoto.PortInfo port_info;
            do_op(port_info_list.get_info(index, out port_info), "get port info for %s".printf(port));
            
            // this should match, every time
            assert(port == port_info.path);
            
            index = abilities_list.lookup_model(name);
            if (index < 0)
                do_op((GPhoto.Result) index, "lookup camera model %s".printf(name));

            GPhoto.CameraAbilities camera_abilities;
            do_op(abilities_list.get_abilities(index, out camera_abilities), 
                "lookup camera abilities for %s".printf(name));
                
            GPhoto.Camera gcamera;
            do_op(GPhoto.Camera.create(out gcamera), "create camera object for %s".printf(name));
            do_op(gcamera.set_abilities(camera_abilities), "set camera abilities for %s".printf(name));
            do_op(gcamera.set_port_info(port_info), "set port info for %s on %s".printf(name, port));
            
            debug("Adding to camera table: %s @ %s", name, port);
            
            DiscoveredCamera camera = new DiscoveredCamera(gcamera, uri);
            camera_map.set(uri, camera);
            
            camera_added(camera);
        }
    }
    
    private static void on_device_added(Hal.Context context, string udi) {
        debug("on_device_added: %s", udi);
        
        schedule_camera_update();
    }
    
    private static void on_device_removed(Hal.Context context, string udi) {
        debug("on_device_removed: %s", udi);
        
        schedule_camera_update();
    }
    
    // Device add/removes often arrive in pairs; this allows for a single
    // update to occur when they come in all at once
    private static void schedule_camera_update() {
        if (camera_update_scheduled)
            return;
        
        Timeout.add(UPDATE_DELAY_MSEC, background_camera_update);
        camera_update_scheduled = true;
    }
    
    private static bool background_camera_update() {
        debug("background_camera_update");
    
        try {
            get_instance().update_camera_table();
        } catch (GPhotoError err) {
            debug("Error updating camera table: %s", err.message);
        }
        
        camera_update_scheduled = false;

        return false;
    }
}
