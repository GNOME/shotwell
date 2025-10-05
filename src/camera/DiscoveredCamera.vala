/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class DiscoveredCamera {
    public GPhoto.Camera gcamera;
    public string uri;
    public string display_name;
    public string? icon;

    private string port;
    private string camera_name;
    private string[] mount_uris;

    public DiscoveredCamera(string name, string port, GPhoto.PortInfo port_info, GPhoto.CameraAbilities camera_abilities) throws GPhotoError {
        this.port = port;
        this.camera_name = name;
        this.uri = "gphoto2://[%s]".printf(port);

        this.mount_uris = new string[0];
        this.mount_uris += this.uri;
        this.mount_uris += "mtp://[%s]".printf(port);

        var res = GPhoto.Camera.create(out this.gcamera);

        if (res != GPhoto.Result.OK) {
            throw new GPhotoError.LIBRARY("[%d] Unable to create camera object for %s: %s",
                (int) res, name, res.as_string());
        }

        res = gcamera.set_abilities(camera_abilities);
        if (res != GPhoto.Result.OK) {
            throw new GPhotoError.LIBRARY("[%d] Unable to set camera abilities for %s: %s",
                (int) res, name, res.as_string());
        }

        res = gcamera.set_port_info(port_info);
        if (res != GPhoto.Result.OK) {
            throw new GPhotoError.LIBRARY("[%d] Unable to set port info for %s: %s",
                (int) res, name, res.as_string());
        }

        var path = get_port_path(port);
        if (path != null) {
            var monitor = VolumeMonitor.get();
            foreach (var volume in monitor.get_volumes()) {
                if (volume.get_identifier(VolumeIdentifier.UNIX_DEVICE) == path) {
                    this.display_name = volume.get_name();
                    this.icon = volume.get_symbolic_icon().to_string();
                }
            }

#if HAVE_UDEV
            var client = new GUdev.Client(null);
            var device = client.query_by_device_file(path);


            // Create alternative uris (used for unmount)
            var serial = device.get_property("ID_SERIAL");
            this.mount_uris += "gphoto2://%s".printf(serial);
            this.mount_uris += "mtp://%s".printf(serial);

            // Look-up alternative display names
            if (display_name == null) {
                display_name = device.get_sysfs_attr("product");
            }

            if (display_name == null) {
                display_name = device.get_property("ID_MODEL");
            }
#endif
        }

        if (port.has_prefix("disk:")) {
            try {
                var mount = File.new_for_path (port.substring(5)).find_enclosing_mount();
                var volume = mount.get_volume();
                if (volume != null) {
                    // Translators: First %s is the name of camera as gotten from GPhoto, second is the GVolume name, e.g. Mass storage camera (510MB volume)
                    display_name = _("%s (%s)").printf (name, volume.get_name ());
                    icon = volume.get_symbolic_icon().to_string();
                } else {
                    // Translators: First %s is the name of camera as gotten from GPhoto, second is the GMount name, e.g. Mass storage camera (510MB volume)
                    display_name = _("%s (%s)").printf (name, mount.get_name ());
                    icon = mount.get_symbolic_icon().to_string();
                }

            } catch (Error e) { }
        }

        if (display_name == null) {
            this.display_name = camera_name;
        }
    }

    public Mount? get_mount() {
        foreach (var uri in this.mount_uris) {
            var f = File.new_for_uri(uri);
            try {
                var mount = f.find_enclosing_mount(null);
                if (mount != null)
                    return mount;
            } catch (Error error) {}
        }

        return null;
    }

    private string? get_port_path(string port) {
        // Accepted format is usb:001,005
        return port.has_prefix("usb:") ? 
            "/dev/bus/usb/%s".printf(port.substring(4).replace(",", "/")) : null;
    }
 
}


