/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Publishing.RESTSupport.OAuth1 {
    internal const string ENCODE_RFC_3986_EXTRA = "!*'();:@&=+$,/?%#[] \\";

    public class Session : Publishing.RESTSupport.Session {
        private string? request_phase_token = null;
        private string? request_phase_token_secret = null;
        private string? access_phase_token = null;
        private string? access_phase_token_secret = null;
        private string? username = null;
        private string? consumer_key = null;
        private string? consumer_secret = null;

        public Session(string? endpoint_uri = null) {
            base(endpoint_uri);
        }

        public override bool is_authenticated() {
            return (access_phase_token != null && access_phase_token_secret != null &&
                    username != null);
        }

        public void authenticate_from_persistent_credentials(string token, string secret,
                string username) {
            this.access_phase_token = token;
            this.access_phase_token_secret = secret;
            this.username = username;

            this.authenticated();
        }

        public void deauthenticate() {
            access_phase_token = null;
            access_phase_token_secret = null;
            username = null;
        }

        public void set_api_credentials(string consumer_key, string consumer_secret) {
            this.consumer_key = consumer_key;
            this.consumer_secret = consumer_secret;
        }

        public string sign_transaction(Publishing.RESTSupport.Transaction txn,
                                     Publishing.RESTSupport.Argument[]? extra_arguments = null) {
            string http_method = txn.get_method().to_string();

            debug("signing transaction with parameters:");
            debug("HTTP method = " + http_method);

            Publishing.RESTSupport.Argument[] base_string_arguments = txn.get_arguments();

            foreach (var arg in extra_arguments) {
                base_string_arguments += arg;
            }

            Publishing.RESTSupport.Argument[] sorted_args =
                Publishing.RESTSupport.Argument.sort(base_string_arguments);

            var arguments_string = Argument.serialize_list(sorted_args);

            string? signing_key = null;
            if (access_phase_token_secret != null) {
                debug("access phase token secret available; using it as signing key");

                signing_key = consumer_secret + "&" + access_phase_token_secret;
            } else if (request_phase_token_secret != null) {
                debug("request phase token secret available; using it as signing key");

                signing_key = consumer_secret + "&" + request_phase_token_secret;
            } else {
                debug("neither access phase nor request phase token secrets available; using API " +
                        "key as signing key");

                signing_key = consumer_secret + "&";
            }

            string signature_base_string = http_method + "&" + Soup.URI.encode(
                    txn.get_endpoint_url(), ENCODE_RFC_3986_EXTRA) + "&" +
                Soup.URI.encode(arguments_string, ENCODE_RFC_3986_EXTRA);

            debug("signature base string = '%s'", signature_base_string);

            debug("signing key = '%s'", signing_key);

            // compute the signature
            string signature = RESTSupport.hmac_sha1(signing_key, signature_base_string);
            signature = Soup.URI.encode(signature, ENCODE_RFC_3986_EXTRA);

            debug("signature = '%s'", signature);

            return signature;
        }

        public void set_request_phase_credentials(string token, string secret) {
            this.request_phase_token = token;
            this.request_phase_token_secret = secret;
        }

        public void set_access_phase_credentials(string token, string secret, string username) {
            this.access_phase_token = token;
            this.access_phase_token_secret = secret;
            this.username = username;

            authenticated();
        }

        public string get_oauth_nonce() {
            TimeVal currtime = TimeVal();
            currtime.get_current_time();

            return Checksum.compute_for_string(ChecksumType.MD5, currtime.tv_sec.to_string() +
                    currtime.tv_usec.to_string());
        }

        public string get_oauth_timestamp() {
            return GLib.get_real_time().to_string().substring(0, 10);
        }

        public string get_consumer_key() {
            assert(consumer_key != null);
            return consumer_key;
        }

        public string get_request_phase_token() {
            assert(request_phase_token != null);
            return request_phase_token;
        }

        public string get_access_phase_token() {
            assert(access_phase_token != null);
            return access_phase_token;
        }

        public bool has_access_phase_token() {
            return access_phase_token != null;
        }

        public string get_access_phase_token_secret() {
            assert(access_phase_token_secret != null);
            return access_phase_token_secret;
        }

        public string get_username() {
            assert(is_authenticated());
            return username;
        }
    }

    public class Transaction : Publishing.RESTSupport.Transaction {
        public Transaction(Session session, Publishing.RESTSupport.HttpMethod method =
                Publishing.RESTSupport.HttpMethod.POST) {
            base(session, method);
            setup_arguments();
        }

        public Transaction.with_uri(Session session, string uri,
                Publishing.RESTSupport.HttpMethod method = Publishing.RESTSupport.HttpMethod.POST) {
            base.with_endpoint_url(session, uri, method);
            setup_arguments();
        }

        private void setup_arguments() {
            var session = (Session) get_parent_session();

            add_argument("oauth_nonce", session.get_oauth_nonce());
            add_argument("oauth_signature_method", "HMAC-SHA1");
            add_argument("oauth_version", "1.0");
            add_argument("oauth_timestamp", session.get_oauth_timestamp());
            add_argument("oauth_consumer_key", session.get_consumer_key());
            if (session.has_access_phase_token()) {
                add_argument("oauth_token", session.get_access_phase_token());
            }
        }


        public override void execute() throws Spit.Publishing.PublishingError {
            var signature = ((Session) get_parent_session()).sign_transaction(this);
            add_argument("oauth_signature", signature);

            base.execute();
        }
    }

    public class UploadTransaction : Publishing.RESTSupport.UploadTransaction {
        protected unowned Publishing.RESTSupport.OAuth1.Session session;
        private Publishing.RESTSupport.Argument[] auth_header_fields;

        public UploadTransaction(Publishing.RESTSupport.OAuth1.Session session,
                                 Spit.Publishing.Publishable publishable,
                                 string endpoint_uri) {
            base.with_endpoint_url(session, publishable, endpoint_uri);

            this.auth_header_fields = new Publishing.RESTSupport.Argument[0];
            this.session = session;

            add_authorization_header_field("oauth_nonce", session.get_oauth_nonce());
            add_authorization_header_field("oauth_signature_method", "HMAC-SHA1");
            add_authorization_header_field("oauth_version", "1.0");
            add_authorization_header_field("oauth_timestamp", session.get_oauth_timestamp());
            add_authorization_header_field("oauth_consumer_key", session.get_consumer_key());
            add_authorization_header_field("oauth_token", session.get_access_phase_token());
        }

        public void add_authorization_header_field(string key, string value) {
            auth_header_fields += new Publishing.RESTSupport.Argument(key, value);
        }

        public string get_authorization_header_string() {
            return "OAuth " + Argument.serialize_list(auth_header_fields, true, ", ");
        }

        public void authorize() {
            var signature = session.sign_transaction(this, auth_header_fields);
            add_authorization_header_field("oauth_signature", signature);


            string authorization_header = get_authorization_header_string();

            debug("executing upload transaction: authorization header string = '%s'",
                    authorization_header);
            add_header("Authorization", authorization_header);

        }
    }
}


