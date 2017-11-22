/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

using Shotwell;
using Shotwell.Plugins;

namespace Publishing.Authenticator.Shotwell.Facebook {
    private const string APPLICATION_ID = "1612018629063184";

    private class WebAuthenticationPane : Common.WebAuthenticationPane {
        private static bool cache_dirty = false;

        public signal void login_succeeded(string success_url);
        public signal void login_failed();

        public WebAuthenticationPane() {
            Object (login_uri : get_login_url ());
        }

        private class LocaleLookup {
            public string prefix;
            public string translation;
            public string? exception_code;
            public string? exception_translation;
            public string? exception_code_2;
            public string? exception_translation_2;

            public LocaleLookup(string prefix, string translation, string? exception_code = null,
                string? exception_translation  = null, string? exception_code_2  = null,
                string? exception_translation_2 = null) {
                this.prefix = prefix;
                this.translation = translation;
                this.exception_code = exception_code;
                this.exception_translation = exception_translation;
                this.exception_code_2 = exception_code_2;
                this.exception_translation_2 = exception_translation_2;
            }

        }

        private static LocaleLookup[] locale_lookup_table = {
            new LocaleLookup( "es", "es-la", "ES", "es-es" ),
            new LocaleLookup( "en", "en-gb", "US", "en-us" ),
            new LocaleLookup( "fr", "fr-fr", "CA", "fr-ca" ),
            new LocaleLookup( "pt", "pt-br", "PT", "pt-pt" ),
            new LocaleLookup( "zh", "zh-cn", "HK", "zh-hk", "TW", "zh-tw" ),
            new LocaleLookup( "af", "af-za" ),
            new LocaleLookup( "ar", "ar-ar" ),
            new LocaleLookup( "nb", "nb-no" ),
            new LocaleLookup( "no", "nb-no" ),
            new LocaleLookup( "id", "id-id" ),
            new LocaleLookup( "ms", "ms-my" ),
            new LocaleLookup( "ca", "ca-es" ),
            new LocaleLookup( "cs", "cs-cz" ),
            new LocaleLookup( "cy", "cy-gb" ),
            new LocaleLookup( "da", "da-dk" ),
            new LocaleLookup( "de", "de-de" ),
            new LocaleLookup( "tl", "tl-ph" ),
            new LocaleLookup( "ko", "ko-kr" ),
            new LocaleLookup( "hr", "hr-hr" ),
            new LocaleLookup( "it", "it-it" ),
            new LocaleLookup( "lt", "lt-lt" ),
            new LocaleLookup( "hu", "hu-hu" ),
            new LocaleLookup( "nl", "nl-nl" ),
            new LocaleLookup( "ja", "ja-jp" ),
            new LocaleLookup( "nb", "nb-no" ),
            new LocaleLookup( "no", "nb-no" ),
            new LocaleLookup( "pl", "pl-pl" ),
            new LocaleLookup( "ro", "ro-ro" ),
            new LocaleLookup( "ru", "ru-ru" ),
            new LocaleLookup( "sk", "sk-sk" ),
            new LocaleLookup( "sl", "sl-si" ),
            new LocaleLookup( "sv", "sv-se" ),
            new LocaleLookup( "th", "th-th" ),
            new LocaleLookup( "vi", "vi-vn" ),
            new LocaleLookup( "tr", "tr-tr" ),
            new LocaleLookup( "el", "el-gr" ),
            new LocaleLookup( "bg", "bg-bg" ),
            new LocaleLookup( "sr", "sr-rs" ),
            new LocaleLookup( "he", "he-il" ),
            new LocaleLookup( "hi", "hi-in" ),
            new LocaleLookup( "bn", "bn-in" ),
            new LocaleLookup( "pa", "pa-in" ),
            new LocaleLookup( "ta", "ta-in" ),
            new LocaleLookup( "te", "te-in" ),
            new LocaleLookup( "ml", "ml-in" )
        };

        private static string get_system_locale_as_facebook_locale() {
            unowned string? raw_system_locale = Intl.setlocale(LocaleCategory.ALL, "");
            if (raw_system_locale == null || raw_system_locale == "")
                return "www";

            string system_locale = raw_system_locale.split(".")[0];

            foreach (LocaleLookup locale_lookup in locale_lookup_table) {
                if (!system_locale.has_prefix(locale_lookup.prefix))
                    continue;

                if (locale_lookup.exception_code != null) {
                    assert(locale_lookup.exception_translation != null);

                    if (system_locale.contains(locale_lookup.exception_code))
                        return locale_lookup.exception_translation;
                }

                if (locale_lookup.exception_code_2 != null) {
                    assert(locale_lookup.exception_translation_2 != null);

                    if (system_locale.contains(locale_lookup.exception_code_2))
                        return locale_lookup.exception_translation_2;
                }

                return locale_lookup.translation;
            }

            // default
            return "www";
        }

        private static string get_login_url() {
            var facebook_locale = get_system_locale_as_facebook_locale();

            return "https://%s.facebook.com/dialog/oauth?client_id=%s&redirect_uri=https://www.facebook.com/connect/login_success.html&display=popup&scope=publish_actions,user_photos,user_videos&response_type=token".printf(facebook_locale, APPLICATION_ID);
        }

        public override void on_page_load() {
            string loaded_url = get_view ().uri.dup();
            debug("loaded url: " + loaded_url);

            // strip parameters from the loaded url
            if (loaded_url.contains("?")) {
                int index = loaded_url.index_of_char('?');
                string params = loaded_url[index:loaded_url.length];
                loaded_url = loaded_url.replace(params, "");
            }

            // were we redirected to the facebook login success page?
            if (loaded_url.contains("login_success")) {
                cache_dirty = true;
                login_succeeded(get_view ().uri);
                return;
            }

            // were we redirected to the login total failure page?
            if (loaded_url.contains("login_failure")) {
                login_failed();
                return;
            }
        }

        public static bool is_cache_dirty() {
            return cache_dirty;
        }
    }

    internal class Facebook : Spit.Publishing.Authenticator, GLib.Object {
        private Spit.Publishing.PluginHost host;
        private Publishing.Authenticator.Shotwell.Facebook.WebAuthenticationPane web_auth_pane = null;
        private GLib.HashTable<string, Variant> params;

        private const string SERVICE_WELCOME_MESSAGE =
    _("You are not currently logged into Facebook.\n\nIf you don’t yet have a Facebook account, you can create one during the login process. During login, Shotwell Connect may ask you for permission to upload photos and publish to your feed. These permissions are required for Shotwell Connect to function.");
        private const string RESTART_ERROR_MESSAGE =
    _("You have already logged in and out of Facebook during this Shotwell session.\nTo continue publishing to Facebook, quit and restart Shotwell, then try publishing again.");

        /* Interface functions */
        public Facebook(Spit.Publishing.PluginHost host) {
            this.host = host;
            this.params = new GLib.HashTable<string, Variant>(str_hash, str_equal);
        }

        public void authenticate() {
            // Do we have saved user credentials? If so, go ahead and authenticate the session
            // with the saved credentials and proceed with the publishing interaction. Otherwise, show
            // the Welcome pane
            if (is_persistent_session_valid()) {
                var access_token = get_persistent_access_token();
                this.params.insert("AccessToken", new Variant.string(access_token));
                this.authenticated();
                return;
            }

            // FIXME: Find a way for a proper logout
            if (WebAuthenticationPane.is_cache_dirty()) {
                host.set_service_locked(false);
                host.install_static_message_pane(RESTART_ERROR_MESSAGE,
                                                 Spit.Publishing.PluginHost.ButtonMode.CANCEL);
            } else {
                this.do_show_service_welcome_pane();
            }
        }

        public bool can_logout() {
            return true;
        }

        public GLib.HashTable<string, Variant> get_authentication_parameter() {
            return this.params;
        }

        public void invalidate_persistent_session() {
            debug("invalidating saved Facebook session.");
            set_persistent_access_token("");
        }

        public void logout() {
            invalidate_persistent_session();
        }

        public void refresh() {
            // No-Op with Flickr
        }

        /* Private functions */
        private bool is_persistent_session_valid() {
            string? token = get_persistent_access_token();

            if (token != null)
                debug("existing Facebook session found in configuration database (access_token = %s).",
                        token);
            else
                debug("no existing Facebook session available.");

            return token != null;
        }

        private string? get_persistent_access_token() {
            return host.get_config_string("access_token", null);
        }

        private void set_persistent_access_token(string access_token) {
            host.set_config_string("access_token", access_token);
        }

        private void do_show_service_welcome_pane() {
            debug("ACTION: showing service welcome pane.");

            host.install_welcome_pane(SERVICE_WELCOME_MESSAGE, on_login_clicked);
            host.set_service_locked(false);
        }

        private void on_login_clicked() {
            debug("EVENT: user clicked 'Login' on welcome pane.");

            do_hosted_web_authentication();
        }

        private void do_hosted_web_authentication() {
            debug("ACTION: doing hosted web authentication.");

            this.host.set_service_locked(false);

            this.web_auth_pane = new WebAuthenticationPane();
            this.web_auth_pane.login_succeeded.connect(on_web_auth_pane_login_succeeded);
            this.web_auth_pane.login_failed.connect(on_web_auth_pane_login_failed);

            this.host.install_dialog_pane(this.web_auth_pane,
                                          Spit.Publishing.PluginHost.ButtonMode.CANCEL);

        }

        private void on_web_auth_pane_login_succeeded(string success_url) {
            debug("EVENT: hosted web login succeeded.");

            do_authenticate_session(success_url);
        }

        private void on_web_auth_pane_login_failed() {
            debug("EVENT: hosted web login failed.");

            // In this case, "failed" doesn't mean that the user didn't enter the right username and
            // password -- Facebook handles that case inside the Facebook Connect web control. Instead,
            // it means that no session was initiated in response to our login request. The only
            // way this happens is if the user clicks the "Cancel" button that appears inside
            // the web control. In this case, the correct behavior is to return the user to the
            // service welcome pane so that they can start the web interaction again.
            do_show_service_welcome_pane();
        }

        private void do_authenticate_session(string good_login_uri) {
            debug("ACTION: preparing to extract session information encoded in uri = '%s'",
                 good_login_uri);

            // the raw uri is percent-encoded, so decode it
            string decoded_uri = Soup.URI.decode(good_login_uri);

            // locate the access token within the URI
            string? access_token = null;
            int index = decoded_uri.index_of("#access_token=");
            if (index >= 0)
                access_token = decoded_uri[index:decoded_uri.length];
            if (access_token == null) {
                host.post_error(new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                    "Server redirect URL contained no access token"));
                return;
            }

            // remove any trailing parameters from the session description string
            string? trailing_params = null;
            index = access_token.index_of_char('&');
            if (index >= 0)
                trailing_params = access_token[index:access_token.length];
            if (trailing_params != null)
                access_token = access_token.replace(trailing_params, "");

            // remove the key from the session description string
            access_token = access_token.replace("#access_token=", "");
            this.params.insert("AccessToken", new Variant.string(access_token));
            set_persistent_access_token(access_token);

            this.authenticated();
        }
    }
} // namespace Publishing.Facebook;
