/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * Copyright 2011 Valentín Barros Puertas <valentin(at)sanva(dot)net>
 * Copyright 2018 Ricardo Fantin da Costa <ricardofantin(at)gmail(dot)com>
 * Copyright 2018 Narendra A <narendra_m_a(at)yahoo(dot)com>
 * 
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

#include "shotwell-facedetect.hpp"
#include "dbus-interface.h"

#include <gio/gio.h>
#include <glib.h>

#include <iostream>

constexpr std::string_view FACEDETECT_INTERFACE_NAME{ "org.gnome.Shotwell.Faces1" };
constexpr std::string_view FACEDETECT_PATH{ "/org/gnome/shotwell/faces" };

GVariant *FaceRect::serialize() const
{
    return g_variant_new("(dddd@ad)", x, y, width, height,
                         g_variant_new_fixed_array(G_VARIANT_TYPE_DOUBLE, vec.data(), vec.size(), sizeof(double)));
}

// DBus binding functions
static gboolean on_handle_detect_faces(ShotwellFaces1 *object, GDBusMethodInvocation *invocation,
                                       [[maybe_unused]]const gchar *arg_image, const gchar *arg_cascade, gdouble arg_scale,
                                       gboolean arg_infer)
{
    g_auto(GVariantBuilder) builder = G_VARIANT_BUILDER_INIT(G_VARIANT_TYPE("a(ddddad)"));
    auto rects = detectFaces(arg_image, arg_scale, arg_infer == TRUE);

    // Construct return value
    for(const auto &rect : rects) {
        g_variant_builder_add(&builder, "@(ddddad)", rect.serialize());
        g_debug("Returning %f,%f-%f", rect.x, rect.y, rect.vec.back());
    }

    // Call return
    shotwell_faces1_complete_detect_faces(object, invocation, g_variant_builder_end(&builder));
    return TRUE;
}

static gboolean on_handle_load_net(ShotwellFaces1 *object, GDBusMethodInvocation *invocation, const gchar *arg_net)
{
    // Call return
    shotwell_faces1_complete_load_net(object, invocation, loadNet(arg_net) ? TRUE : FALSE);
    return TRUE;
}

static gboolean on_handle_terminate(ShotwellFaces1 *object, GDBusMethodInvocation *invocation, gpointer user_data)
{
    g_debug("Exiting...");
    shotwell_faces1_complete_terminate(object, invocation);
    g_main_loop_quit(static_cast<GMainLoop *>(user_data));

    return TRUE;
}

static void on_name_acquired(GDBusConnection *connection,
                             const gchar *name, gpointer user_data) {
    g_debug("Got name %s", name);

    auto *interface = shotwell_faces1_skeleton_new();
    g_signal_connect(interface, "handle-detect-faces", G_CALLBACK (on_handle_detect_faces), nullptr);
    g_signal_connect(interface, "handle-terminate", G_CALLBACK (on_handle_terminate), user_data);
    g_signal_connect(interface, "handle-load-net", G_CALLBACK (on_handle_load_net), nullptr);

    g_autoptr(GError) error = nullptr;
    g_dbus_interface_skeleton_export(G_DBUS_INTERFACE_SKELETON(interface), connection, FACEDETECT_PATH.data(), &error);
    if (error != nullptr) {
        g_print("Failed to export interface: %s", error->message);
    }
}

static void on_name_lost(GDBusConnection *connection,
                         const gchar *name, gpointer user_data) {
    if (connection == nullptr) {
        g_debug("Unable to establish connection for name %s", name);
    } else {
        g_debug("Connection for name %s disconnected", name);
    }
    g_main_loop_quit(static_cast<GMainLoop *>(user_data));
}

static char* address = nullptr;

static GOptionEntry entries[] = {
    { "address", 'a', 0, G_OPTION_ARG_STRING, &address, "Use private DBus ADDRESS instead of session", "ADDRESS" },
    { nullptr }
};

static gboolean on_authorize_authenticated_peer([[maybe_unused]] GIOStream *iostream, GCredentials *credentials,
                                                [[maybe_unused]] gpointer user_data)
{
    g_autoptr(GCredentials) own_credentials = nullptr;

    g_debug("Authorizing peer with credentials %s\n", g_credentials_to_string(credentials));

    if(credentials == nullptr) {
        return FALSE;
    }

    own_credentials = g_credentials_new();

    {
        g_autoptr(GError) error = nullptr;

        if(g_credentials_is_same_user(credentials, own_credentials, &error) == FALSE) {
            g_warning("Unable to authorize peer: %s", error->message);

            return FALSE;
        }
    }

    return TRUE;
}

int main(int argc, char **argv) {
    GMainLoop *loop;
    GError *error = nullptr;
    GOptionContext *context;

    context = g_option_context_new ("- Shotwell face detection helper service");
    g_option_context_add_main_entries (context, entries, "shotwell");
    if (g_option_context_parse (context, &argc, &argv, &error) == FALSE) {
        g_print ("Failed to parse options: %s\n", error->message);
        exit(1);
    }

    loop = g_main_loop_new (nullptr, FALSE);


    // We are running on the session bus
    if (address == nullptr) {
        g_debug("Starting %s on G_BUS_TYPE_SESSION", argv[0]);
        g_bus_own_name(G_BUS_TYPE_SESSION, FACEDETECT_INTERFACE_NAME.data(), G_BUS_NAME_OWNER_FLAGS_NONE,
                nullptr, on_name_acquired, on_name_lost, loop, nullptr);

    } else {
        g_debug("Starting %s on %s", argv[0], address);
        GDBusAuthObserver *observer = g_dbus_auth_observer_new ();
        g_signal_connect (G_OBJECT (observer), "authorize-authenticated-peer",
                G_CALLBACK (on_authorize_authenticated_peer), nullptr);

        GDBusConnection *connection = g_dbus_connection_new_for_address_sync (address,
                                                             G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT,
                                                             observer,
                                                             nullptr,
                                                             &error);
        if (connection != nullptr) {
            on_name_acquired (connection, FACEDETECT_INTERFACE_NAME.data (), loop);
        }
    }

    if (error != nullptr) {
        g_error("Failed to get connection on %s bus: %s",
                address == nullptr ? "session" : "private",
                error->message);
    }

    g_main_loop_run (loop);
    return 0;
}
