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
            list.add("picasa");
            list.add("youtube");
            list.add("tumblr");

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
                    return new Shotwell.Google.Google("https://picasaweb.google.com/data/", _("You are not currently logged into Picasa Web Albums.\n\nClick Log in to log into Picasa Web Albums in your Web browser. You will have to authorize Shotwell Connect to link to your Picasa Web Albums account."), host);

                case "youtube":
                    return new Shotwell.Google.Google("https://gdata.youtube.com/", _("You are not currently logged into YouTube.\n\nYou must have already signed up for a Google account and set it up for use with YouTube to continue. You can set up most accounts by using your browser to log into the YouTube site at least once."), host);
                case "tumblr":
                    return new Shotwell.Tumblr.Tumblr(host);
                default:
                    return null;
            }
        }
    }
}
