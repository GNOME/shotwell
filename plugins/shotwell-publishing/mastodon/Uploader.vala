// SPDX-License-Identifer: LGPL-2.1-or-later
// SPDX-FileCopyrightText: 2022 Jens Georg <mail@jensge.org>


internal class Publishing.Mastodon.Transactions.MediaUpload : Publishing.RESTSupport.UploadTransaction {
    public MediaUpload(Session session, Parameters parameters, Spit.Publishing.Publishable publishable) {
        base.with_endpoint_url(session, publishable, "https://%s/api/v2/media".printf(parameters.account.instance));

        add_header("Authorization", "Bearer " + session.access_token);

        add_argument("description", parameters.alt_text);

        var disposition_table =
            new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);

        string? filename = publishable.get_publishing_name();
        if (filename == null || filename == "")
            filename = publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME);

        disposition_table.insert("filename", GLib.Uri.escape_string(
                                                                publishable.get_param_string(Spit.Publishing.Publishable.PARAM_STRING_BASENAME), null));
        disposition_table.insert("name", "file");

        set_binary_disposition_table(disposition_table);
    }
}

internal class Publishing.Mastodon.Uploader : Publishing.RESTSupport.BatchUploader {
    private Parameters parameters;

    public Uploader(Session session, Spit.Publishing.Publishable[] publishables,
        Parameters parameters) {
        base(session, publishables);
        session.set_insecure();

        this.parameters = parameters;
    }

    protected override Publishing.RESTSupport.Transaction create_transaction(Spit.Publishing.Publishable publishable) {
        var txn = new Transactions.MediaUpload((Session) get_session(), parameters,
                                               publishable);

        // We need to collect the media ids from the transactions after they are finised to attach to the status post later
        txn.completed.connect(on_transaction_completed);

        return txn;
    }

    private void on_transaction_completed(Publishing.RESTSupport.Transaction txn) {
        var response = txn.get_response();
        var parser = new Json.Parser();
        
        try {
            parser.load_from_data(response);
        } catch (Error err) {
            critical("Could not parse answer from transaction: %s", err.message);

            return;
        }

        var response_obj = parser.get_root().get_object();
        if (!response_obj.has_member("id")) {
            critical("Media upload response did not have a media id");
            return;
        }

        parameters.media_ids.add(response_obj.get_string_member("id"));
        print("Adding media id %s", response_obj.get_string_member("id"));
    }
}
