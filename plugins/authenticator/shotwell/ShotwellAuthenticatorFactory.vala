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
                case "facebook":
                    return new Shotwell.Facebook.Facebook(host);
                case "youtube":
                    return new Shotwell.Google.Google("https://www.googleapis.com/auth/youtube", _("You are not currently logged into YouTube.\n\nYou must have already signed up for a Google account and set it up for use with YouTube to continue. You can set up most accounts by using your browser to log into the YouTube site at least once.\n\nShotwell uses the YouTube API services <a href=\"https://developers.google.com/youtube\">https://developers.google.com/youtube</a> for accessing your YouTube channel and upload the videos. By using Shotwell to access YouTube, you agree to be bound to the YouTube Terms of Service as available at <a href=\"https://www.youtube.com/t/terms\">https://www.youtube.com/t/terms</a>\n\nShotwell's privacy policy regarding the use of data related to your Google account in general and YouTube in particular can be found in our <a href=\"help:shotwell/privacy-policy\">online services privacy policy</a>\n\nFor Google's own privacy policy, please refer to <a href=\"https://policies.google.com/privacy\">https://policies.google.com/privacy</a>"), host);
                case "tumblr":
                    return new Shotwell.Tumblr.Tumblr(host);
                case "google-photos":
                    return new Shotwell.Google.Google("https://www.googleapis.com/auth/photoslibrary", _("You are not currently logged into Google Photos.\n\nYou must have already signed up for a Google account and set it up for use with Google Photos. Shotwell uses the Google Photos API services <a href=\"https://developers.google.com/photos/\">https://developers.google.com/photos/</a> for all interaction with your Google Photos data.You will have to grant access Shotwell to your Google Photos library.\n\nShotwell's privacy policy regarding the use of data related to your Google account in general and Google Photos in particular can be found in our <a href=\"help:shotwell/privacy-policy\">online services privacy policy</a>For Google's own privacy policy, please refer to <a href=\"https://policies.google.com/privacy\">https://policies.google.com/privacy</a>"), host);
               default:
                    return null;
            }
        }
    }
}
