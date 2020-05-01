namespace Publishing.Authenticator {
    public class Factory : Spit.Publishing.AuthenticatorFactory, Object {
        private static Factory instance = null;

        public static Factory get_instance() {
            if (Factory.instance == null) {
                Factory.instance = new Factory();
            }

            return Factory.instance;
        }

        public Gee.List<string> get_available_authenticators() {
            var list = new Gee.ArrayList<string>();
            list.add("flickr");
            list.add("facebook");
            list.add("youtube");
            list.add("tumblr");
            list.add("google-photos");

            return list;
        }

        public Spit.Publishing.Authenticator? create(string provider,
                                                     Spit.Publishing.PluginHost host) {
            switch (provider) {
                case "flickr":
                    return new Shotwell.Flickr.Flickr(host);
                case "youtube":
                    return new Shotwell.Google.Google("https://www.googleapis.com/auth/youtube", _("You are not currently logged into YouTube.\n\nYou must have already signed up for a Google account and set it up for use with YouTube to continue. You can set up most accounts by using your browser to log into the YouTube site at least once."), host);
                case "tumblr":
                    return new Shotwell.Tumblr.Tumblr(host);
                case "google-photos":
                    return new Shotwell.Google.Google("https://www.googleapis.com/auth/photoslibrary", _("You are not currently logged into Google Photos.\n\nYou must have already signed up for a Google account and set it up for use with Google Photos.\n\nYou will have to authorize Shotwell to link to your Google Photos account."), host);
               default:
                    return null;
            }
        }
    }
}
