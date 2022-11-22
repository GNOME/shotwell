// SPDX-License-Identifer: LGPL-2.1-or-later
// SPDX-FileCopyrightText: 2022 Jens Georg <mail@jensge.org>

using Shotwell;
using Shotwell.Plugins;

/**
 * Dialog to show the details of a TLS certificate
 */
private class GcrDetailsDialog : Gtk.Window {
    public GcrDetailsDialog(Gtk.Window? parent, string host, Gcr.Certificate certificate) {
        Object(transient_for: parent, modal: true, title: _("TLS Certificate details for %s").printf(host));

        set_default_size(-1, 400);
        set_resizable(true);
        set_hide_on_close(false);

        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        var scrolled = new Gtk.ScrolledWindow();
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scrolled.set_child(box);
        set_child(scrolled);
        var primary = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        var secondary = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        box.append(primary);
        box.append(secondary);
        var action = new Gtk.CallbackAction(() => {
            close();

            return true;
        });

        var controller = new Gtk.ShortcutController();
        var shortcut = new Gtk.Shortcut(new Gtk.KeyvalTrigger(Gdk.Key.Escape, 0), action);
        controller.add_shortcut(shortcut);
        ((Gtk.Widget)this).add_controller(controller);

        foreach (var section in certificate.get_interface_elements()) {
            var label = new Gtk.Label (section.get_label());
            label.add_css_class("heading");
            label.hexpand = true;
            label.halign = Gtk.Align.START;
            label.margin_start = 16;
            label.margin_top = 32;
            var section_box = new Gtk.ListBox();
            section_box.margin_start = 16;
            section_box.margin_end = 16;
            section_box.set_selection_mode(Gtk.SelectionMode.NONE);
            section_box.add_css_class("boxed-list");
            var size_group = new Gtk.SizeGroup(Gtk.SizeGroupMode.HORIZONTAL);
            section_box.bind_model(section.get_fields(), (field) => {
                return create_detail_row((Gcr.CertificateField) field, size_group);
            });
            if (Gcr.CertificateSectionFlags.IMPORTANT in section.get_flags()) {
                primary.append(label);
                primary.append(section_box);    
            } else {
                secondary.append(label);
                secondary.append(section_box);    
            }
        }
    }
     string hexdump (uint8[] data) {
        var builder = new StringBuilder.sized (16);
        var i = 0;

        foreach (var c in data) {
            if (i % 16 == 0 && i != 0) {
                builder.append_c('\n');
            }
            i++;
            builder.append_printf ("%02x ", c);
        }

        return builder.str;
    }

    private Gtk.Widget create_detail_row (Gcr.CertificateField field, Gtk.SizeGroup size_group) {
        var row = new Gtk.ListBoxRow();
        row.set_activatable (false);
        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        box.margin_top = 12;
        box.margin_bottom = 12;
        box.margin_start = 12;
        box.margin_end = 12;
        var label = new Gtk.Label(field.get_label());
        label.xalign = 0.0f;
        label.yalign = 0.0f;
        label.add_css_class("dim-label");
        box.prepend(label);
        row.set_child(box);

        var type = field.get_value_type();
        var value = field.value;

        if (value.holds(typeof(string))) {
            label = new Gtk.Label(value.get_string());
            label.xalign = 1.0f;
            label.hexpand = true;
            box.append(label);
        }
        if (type.is_a(typeof(string[]))) {
            var strs = (string[]) value.get_boxed();
            label = new Gtk.Label(string.joinv("\n", strs));
            label.xalign = 1.0f;
            label.hexpand = true;
            box.append(label);
        }
        if (type.is_a(typeof(Bytes))) {
            var bytes = (Bytes)value.get_boxed();
            label = new Gtk.Label(hexdump(bytes.get_data()));
            label.xalign = 1.0f;
            label.yalign = 0.0f;
            label.hexpand = true;
            box.append(label);
            label.add_css_class("monospace");
        }

        size_group.add_widget(row);
        return row;
    }
}

[GtkTemplate (ui = "/org/gnome/Shotwell/Publishing/Common/ssl_certificate_pane.ui")]
public class Shotwell.Plugins.Common.SslCertificatePane : Gtk.Box, Spit.Publishing.DialogPane {

    [GtkChild]
    private unowned Gtk.Label main_text;
    [GtkChild]
    private unowned Gtk.Label ssl_errors;
    [GtkChild]
    private unowned Gtk.Button default_button;
    [GtkChild]
    private unowned Gtk.Button proceed_button;

    public signal void proceed ();
    public string host { owned get; construct; }
    public TlsCertificate? cert { get; construct; }
    public string error_text { owned get; construct; }
    public Spit.Publishing.PluginHost plugin_host {get; construct; }

    public SslCertificatePane (Publishing.RESTSupport.Transaction transaction,
        Spit.Publishing.PluginHost plugin_host,
                               string host) {
        TlsCertificate cert;
        var flags = transaction.get_tls_error_details(out cert);
        Object (cert : cert,
        Object (resource_path : Resources.RESOURCE_PATH +
                                "/ssl_certificate_pane.ui",
                default_id: "default",
                cert : cert,
                error_text : text,
                host : host);
    }

    public SslCertificatePane.plain (TlsCertificate cert, TlsCertificateFlags flags, string host) {
        var text = SslCertificatePane.get_certificate_error_details (flags);

        error_text : text,
                plugin_host : plugin_host,
        host : host);
    }

    public override void constructed () {
        base.constructed ();

        var bold_host = "<b>%s</b>".printf(host);
        // %s is the host name that we tried to connect to
        main_text.set_text (_("This does not look like the real %s. Attackers might be trying to steal or alter information going to or from this site (for example, private messages, credit card information, or passwords).").printf(bold_host));
        main_text.use_markup = true;

        ssl_errors.set_text (error_text);

        if (cert != null) {
            default_button.clicked.connect (() => {
                var simple_cert = new Gcr.SimpleCertificate (cert.certificate.data);
                var widget = new GcrDetailsDialog(plugin_host.get_dialog(), host, simple_cert);
                widget.set_visible(true);
            });
        } else {
            default_button.unparent();
        }

        proceed_button.clicked.connect(on_proceed_button_clicked);
    }

    private void on_proceed_button_clicked() {
        proceed();
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
