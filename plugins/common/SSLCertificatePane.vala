// SPDX-License-Identifer: LGPL-2.1-or-later
// SPDX-FileCopyrightText: 2022 Jens Georg <mail@jensge.org>

using Shotwell;
using Shotwell.Plugins;

public class Shotwell.Plugins.Common.SslCertificatePane : Common.BuilderPane {

    public signal void proceed ();
    public string host { owned get; construct; }
    public TlsCertificate? cert { get; construct; }
    public string error_text { owned get; construct; }

    public SslCertificatePane (Publishing.RESTSupport.Transaction transaction,
                               string host) {
        TlsCertificate cert;
        var flags = transaction.get_tls_error_details(out cert);
        var text = SslCertificatePane.get_certificate_error_details (flags);
        Object (resource_path : Resources.RESOURCE_PATH +
                                "/ssl_certificate_pane.ui",
                default_id: "default",
                cert : cert,
                error_text : text,
                host : host);
    }

    public SslCertificatePane.plain (TlsCertificate cert, TlsCertificateFlags flags, string host) {
        var text = SslCertificatePane.get_certificate_error_details (flags);

        Object (resource_path : Resources.RESOURCE_PATH +
                "/ssl_certificate_pane.ui",
        default_id: "default",
        cert : cert,
        error_text : text,
        host : host);
    }

    public override void constructed () {
        base.constructed ();

        var label = this.get_builder ().get_object ("main_text") as Gtk.Label;
        var bold_host = "<b>%s</b>".printf(host);
        // %s is the host name that we tried to connect to
        label.set_text (_("This does not look like the real %s. Attackers might be trying to steal or alter information going to or from this site (for example, private messages, credit card information, or passwords).").printf(bold_host));
        label.use_markup = true;

        label = this.get_builder ().get_object ("ssl_errors") as Gtk.Label;
        label.set_text (error_text);

        var info = this.get_builder ().get_object ("default") as Gtk.Button;
        if (cert != null) {
            info.clicked.connect (() => {
                var simple_cert = new Gcr.SimpleCertificate (cert.certificate.data);
                var widget = new Gcr.CertificateWidget (simple_cert);
                bool use_header = true;
                Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header);
                var flags = (Gtk.DialogFlags) 0;
                if (use_header) {
                    flags |= Gtk.DialogFlags.USE_HEADER_BAR;
                }

                var dialog = new Gtk.Dialog.with_buttons (
                                _("Certificate of %s").printf (host),
                                null,
                                flags,
                                _("_OK"), Gtk.ResponseType.OK);
                dialog.get_content_area ().add (widget);
                dialog.set_default_response (Gtk.ResponseType.OK);
                dialog.set_default_size (640, -1);
                dialog.show_all ();
                dialog.run ();
                dialog.destroy ();
            });
        } else {
            info.get_parent().remove(info);
        }

        var proceed = this.get_builder ().get_object ("proceed_button") as Gtk.Button;
        proceed.clicked.connect (() => { this.proceed (); });
    }

    public static string get_certificate_error_details(TlsCertificateFlags tls_errors) {
        var list = new Gee.ArrayList<string> ();
        if (TlsCertificateFlags.BAD_IDENTITY in tls_errors) {
            /* Possible error message when a site presents a bad certificate. */
            list.add (_("⚫ This website presented identification that belongs to a different website."));
        }

        if (TlsCertificateFlags.EXPIRED in tls_errors) {
            /* Possible error message when a site presents a bad certificate. */
            list.add (_("⚫ This website’s identification is too old to trust. Check the date on your computer’s calendar."));
        }

        if (TlsCertificateFlags.UNKNOWN_CA in tls_errors) {
            /* Possible error message when a site presents a bad certificate. */
            list.add (_("⚫ This website’s identification was not issued by a trusted organization."));
        }

        if (TlsCertificateFlags.GENERIC_ERROR in tls_errors) {
            /* Possible error message when a site presents a bad certificate. */
            list.add (_("⚫ This website’s identification could not be processed. It may be corrupted."));
        }

        if (TlsCertificateFlags.REVOKED in tls_errors) {
            /* Possible error message when a site presents a bad certificate. */
            list.add (_("⚫ This website’s identification has been revoked by the trusted organization that issued it."));
        }

        if (TlsCertificateFlags.INSECURE in tls_errors) {
            /* Possible error message when a site presents a bad certificate. */
            list.add (_("⚫ This website’s identification cannot be trusted because it uses very weak encryption."));
        }

        if (TlsCertificateFlags.NOT_ACTIVATED in tls_errors) {
            /* Possible error message when a site presents a bad certificate. */
            list.add (_("⚫ This website’s identification is only valid for future dates. Check the date on your computer’s calendar."));
        }

        var builder = new StringBuilder ();
        if (list.size == 1) {
            builder.append (list.get (0));
        } else {
            foreach (var entry in list) {
                builder.append_printf ("%s\n", entry);
            }
        }

        return builder.str;
    }

}
