namespace Publishing.Authenticator {
    public class Factory : Spit.Publishing.AuthenticatorFactory, Object {
        private static Factory instance = null;

        public static Factory get_instance() {
            if (Factory.instance == null) {
                Factory.instance = new Factory();
            }

            return Factory.instance;
        }

        public GLib.List<string> get_available_authenticators() {
            var list = new GLib.List<string>();
            list.append("flickr");
            list.append("facebook");
            list.append("picasa");
            list.append("youtube");

            return list;
        }

        public Spit.Publishing.Authenticator? create(string provider,
                                                     Spit.Publishing.PluginHost host) {
            switch (provider) {
                case "flickr":
                    return new Shotwell.Flickr.Flickr(host);
                case "facebook":
                    return new Shotwell.Facebook.Facebook(host);
                case "picasa":
                    return new Shotwell.Google.Google("https://picasaweb.google.com/data/", host);

                case "youtube":
                    return new Shotwell.Google.Google("https://gdata.youtube.com/", host);
                default:
                    return null;
            }
        }
    }
}
