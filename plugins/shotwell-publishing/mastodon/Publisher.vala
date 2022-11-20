// SPDX-License-Identifer: LGPL-2.1-or-later
// SPDX-FileCopyrightText: 2022 Jens Georg <mail@jensge.org>

internal class Publishing.Mastodon.Session : Publishing.RESTSupport.Session {
    public string? client_id;
    public string? client_secret;
    public string? access_token;

    public string? user;
    public string? instance;

    public Session() {
        base("");
    }

    public override bool is_authenticated() {
        return (access_token != null);
    }
}

public class Publishing.Mastodon.Publisher : Spit.Publishing.Publisher, GLib.Object {
    private Spit.Publishing.Service service;
    private Spit.Publishing.PluginHost host;
    private Publishing.Mastodon.Account? account = null;
    private bool running = false;
    private Session session;
    private Spit.Publishing.Authenticator authenticator;

    public Publisher(Spit.Publishing.Service service,
        Spit.Publishing.PluginHost host,
        Spit.Publishing.Account? account) {

        debug ("Mastodon Publisher instantiated.");

        this.service = service;
        this.host = host;
        this.session = new Session();

        if (account is Publishing.Mastodon.Account) {
            this.account = (Publishing.Mastodon.Account) account;
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

        debug("EVENT: a fully authenticated session has become available");

        do_show_publishing_options_pane();
    }

    private void do_show_publishing_options_pane() {
        debug("ACTION: displaying publishing options pane");
        host.set_service_locked(false);
    }
}
