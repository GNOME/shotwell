[DBus (name = "org.gnome.Shotwell.VideoMetadata1")]
public interface VideoMetadataReaderInterface : Object {
    public abstract async uint64 get_duration(string uri) throws Error;
}
