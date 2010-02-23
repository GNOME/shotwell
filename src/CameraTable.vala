/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

#if !NO_CAMERA

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
    
    // list of subsystems being monitored for events
    private const string[] SUBSYSTEMS = { "usb", "block", null };
    
    private static CameraTable instance = null;
    
    private GUdev.Client client = new GUdev.Client(SUBSYSTEMS);
    private OneShotScheduler camera_update_scheduler = null;
    private GPhoto.Context null_context = new GPhoto.Context();
    private GPhoto.CameraAbilitiesList abilities_list;
    
    private Gee.HashMap<string, DiscoveredCamera> camera_map = new Gee.HashMap<string, DiscoveredCamera>(
        str_hash, str_equal, direct_equal);

    public signal void camera_added(DiscoveredCamera camera);
    
    public signal void camera_removed(DiscoveredCamera camera);
    
    private CameraTable() {
        camera_update_scheduler = new OneShotScheduler("CameraTable update scheduler",
            on_update_cameras);
        
        // listen for interesting events on the specified subsystems
        client.uevent += on_udev_event;
        
        // because loading the camera abilities list takes a bit of time and slows down app
        // startup, delay loading it (and notifying any observers) for a small period of time,
        // after the dust has settled
        Timeout.add(500, delayed_init);
    }
    
    private bool delayed_init() {
        try {
            init_camera_table();
        } catch (GPhotoError err) {
            warning("Unable to initialize camera table: %s", err.message);
            
            return false;
        }
        
        try {
            update_camera_table();
        } catch (GPhotoError err) {
            warning("Unable to update camera table: %s", err.message);
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
    
    private string[] get_all_usb_cameras() {
        string[] cameras = new string[0];
        
        USB.find_busses();
        USB.find_devices();
        
        unowned USB.Bus? bus = USB.get_busses();
        while (bus != null) {
            unowned USB.Device? device = bus.devices;
            while (device != null) {
                for (int ictr = 0; ictr < device.config.bNumInterfaces; ictr++) {
                    unowned USB.Interface uif = device.config.interface[ictr];
                    for (int dctr = 0; dctr < uif.altsetting.length; dctr++) {
                        unowned USB.InterfaceDescriptor uifd = uif.altsetting[dctr];
                        if (uifd.bInterfaceClass == USB.Class.PTP) {
                            string camera = "usb:%s,%s".printf(bus.dirname, device.filename);
                            debug("USB camera detected at %s", camera);
                            
                            cameras += camera;
                            
                            break;
                        }
                    }
                }
                
                device = device.next;
            }
            
            bus = bus.next;
        }
        
        return cameras;
    }
    
    // USB (or libusb) is a funny beast; if only one USB device is present (i.e. the camera),
    // then a single camera is detected at port usb:.  However, if multiple USB devices are
    // present (including non-cameras), then the first attached camera will be listed twice,
    // first at usb:, then at usb:xxx,yyy.  If the usb: device is removed, another usb:xxx,yyy
    // device will lose its full-path name and be referred to as usb: only.
    //
    // This function gleans the full port name of a particular port, even if it's the unadorned
    // "usb:", by using GUdev.
    private bool usb_esp(int current_camera_count, string[] usb_cameras, string port, 
        out string full_port) {
        // sanity
        assert(current_camera_count > 0);
        
        debug("USB ESP: current_camera_count=%d port=%s", current_camera_count, port);
        
        // if GPhoto detects one camera, and USB reports one camera, all is swell
        if (current_camera_count == 1 && usb_cameras.length == 1) {
            full_port = usb_cameras[0];
            
            debug("USB ESP: port=%s full_port=%s", port, full_port);
            
            return true;
        }

        // with more than one camera, skip the mirrored "usb:" port
        if (port == "usb:") {
            debug("USB ESP: Skipping %s", port);
            
            return false;
        }
        
        // parse out the bus and device ID
        int bus, device;
        if (port.scanf("usb:%d,%d", out bus, out device) < 2) {
            critical("USB ESP: Failed to scanf %s", port);
            
            return false;
        }
        
        foreach (string usb_camera in usb_cameras) {
            int camera_bus, camera_device;
            if (usb_camera.scanf("usb:%d,%d", out camera_bus, out camera_device) < 2) {
                critical("USB ESP: Failed to scanf %s", usb_camera);
                
                continue;
            }
            
            if ((bus == camera_bus) && (device == camera_device)) {
                full_port = port;
                
                debug("USB ESP: port=%s full_port=%s", port, full_port);

                return true;
            }
        }
        
        debug("USB ESP: No matching bus/device found for port=%s", port);
        
        return false;
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
        
        // walk the USB chain and find all PTP cameras; this is necessary for usb_esp
        string[] usb_cameras = get_all_usb_cameras();
        
        // go through the detected camera list and glean their ports
        for (int ctr = 0; ctr < camera_list.count(); ctr++) {
            string name;
            do_op(camera_list.get_name(ctr, out name), "get detected camera name");

            string port;
            do_op(camera_list.get_value(ctr, out port), "get detected camera port");
            
            debug("Detected %d/%d %s @ %s", ctr + 1, camera_list.count(), name, port);
            
            // do some USB ESP, skipping ports that cannot be deduced
            if (port.has_prefix("usb:")) {
                string full_port;
                if (!usb_esp(camera_list.count(), usb_cameras, port, out full_port))
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
                debug("Found camera for %s @ %s in detected map", abilities.model, port_info.path);
                
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
    
    private void on_udev_event(string action, GUdev.Device device) {
        debug("udev event: %s on %s", action, device.get_name());
        
        // Device add/removes often arrive in pairs; this allows for a single
        // update to occur when they come in all at once
        camera_update_scheduler.after_timeout(UPDATE_DELAY_MSEC, true);
    }
    
    private void on_update_cameras() {
        try {
            get_instance().update_camera_table();
        } catch (GPhotoError err) {
            warning("Error updating camera table: %s", err.message);
        }
    }
}

#endif

