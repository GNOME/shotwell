// SPDX-License-Identifer: LGPL-2.1-or-later
// SPDX-FileCopyrightText: 2022 Jens Georg <mail@jensge.org>

internal class Publishing.Mastodon.Session : Publishing.RESTSupport.Session {
    public string? access_token;

    public Session() {
        base("");
    }

    public override bool is_authenticated() {
        return (access_token != null);
    }
}

internal class Publishing.Mastodon.Parameters {
    public Account account;
    public bool sensitive = false;
    public bool strip_metadata = false;
    public string alt_text = "";
    public string post = "";
    public string cw = "";
    public Gee.ArrayList<string> media_ids = new Gee.ArrayList<string>();
}

[GtkTemplate (ui = "/org/gnome/Shotwell/Publishing/mastodon/options.ui")]
internal class Publishing.Mastodon.Options : Gtk.Box, Spit.Publishing.DialogPane {
    [GtkChild]
    private unowned Gtk.Label login_identity_label;

    [GtkChild]
    private unowned Gtk.Button publish_button;

    [GtkChild]
    private unowned Gtk.Button logout_button;

    public signal void publish();
    public signal void logout();

    public Options(Parameters parameters) {
        Object();

        login_identity_label.set_text(_("Posting media as %s").printf(parameters.account.display_name()));
        publish_button.clicked.connect(on_publish_clicked);
    }

    public Gtk.Widget get_widget() {
        return this;
    }

    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }

    public void on_pane_installed() {
    }

    public void on_pane_uninstalled() {
    }

    private void on_publish_clicked() {
        publish();
    }
}

namespace Publishing.Mastodon.Transactions {
    internal class Status : global::Publishing.RESTSupport.Transaction {
        const string ENDPOINT_URL = "https://%s/api/v1/statuses";

        public Status(Session session, Parameters parameters) {
            base.with_endpoint_url(session, ENDPOINT_URL.printf(parameters.account.instance));

            add_header("Authorization", "Bearer " + session.access_token);

            if (parameters.post != "") {
                add_argument("status", "This+is+a+test+post");
            }

            foreach (var arg in parameters.media_ids) {
                add_argument("media_ids[]", arg);
            }

            if (parameters.sensitive) {
                add_argument("sensitive", "true");
            }

            if (parameters.cw != "") {
                add_argument("spoiler_text", parameters.cw);
            }
        }
    }
}

public class Publishing.Mastodon.Publisher : Spit.Publishing.Publisher, GLib.Object {
    private Spit.Publishing.Service service;
    private Spit.Publishing.PluginHost host;
    private Publishing.Mastodon.Account? account = null;
    private bool running = false;
    private Session session;
    private Spit.Publishing.Authenticator authenticator;
    private Parameters parameters = new Parameters();
    private Spit.Publishing.ProgressCallback progress_reporter = null;

    public Publisher(Spit.Publishing.Service service,
        Spit.Publishing.PluginHost host,
        Spit.Publishing.Account? account) {

        debug ("Mastodon Publisher instantiated.");

        this.service = service;
        this.host = host;
        this.session = new Session();

        if (account is Publishing.Mastodon.Account) {
            this.account = (Publishing.Mastodon.Account) account;
            this.parameters.account = this.account;
        }

        this.authenticator = Publishing.Authenticator.Factory.get_instance().create("mastodon", host);
        this.authenticator.authenticated.connect(on_authenticator_authenticated);
    }

    // Publisher interface implementation
    public Spit.Publishing.Service get_service() {
        return service;
    }

    public Spit.Publishing.PluginHost get_host() {
        return host;
    }

    public bool is_running() {
        return running;
    }

    public void start() {
        if (is_running()) {
            return;
        }

        debug("Mastodon.Publisher: starting interaction");

        running = true;

        if (session.is_authenticated()) {
            Idle.add(() => {
                do_show_publishing_options_pane();

                return false;
            });
        }

        if (this.account != null) {
            this.authenticator.set_accountname(this.account.display_name());
        }

        this.authenticator.authenticate();
    }

    public void stop() {
        running = false;
    }

    private void on_authenticator_authenticated() {
        if (!is_running()) {
            return;
        }

        var params = this.authenticator.get_authentication_parameter();
        this.account.user = params["User"].get_string();
        this.account.instance = params["Instance"].get_string();
        this.session.access_token = params["AccessToken"].get_string();

        this.parameters.account = this.account;
        debug("EVENT: a fully authenticated session has become available");

        do_show_publishing_options_pane();
    }

    private void do_show_publishing_options_pane() {
        debug("ACTION: displaying publishing options pane");
        host.set_service_locked(false);

        var pane = new Options(this.parameters);
        pane.publish.connect(do_publish);
        host.install_dialog_pane(pane);
    }

    private async void do_publish() {
        this.progress_reporter = host.serialize_publishables(-1, parameters.strip_metadata);
        var publishables = host.get_publishables();
        var uploader = new Uploader(this.session, publishables, this.parameters);
        var num_published = yield uploader.upload_async(on_upload_status_updated);

        var txn = new Transactions.Status(session, parameters);
        yield txn.execute_async();
    }
    

    /**
     * Event triggered when upload progresses and the status needs to be updated.
     */
    private void on_upload_status_updated(int file_number, double completed_fraction) {
        if (!is_running())
            return;

        debug("EVENT: uploader reports upload %.2f percent complete.", 100.0 * completed_fraction);

        assert(progress_reporter != null);

        progress_reporter(file_number, completed_fraction);
    }
}
