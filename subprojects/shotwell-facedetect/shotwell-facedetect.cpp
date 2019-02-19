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

// DBus binding functions
static gboolean on_handle_detect_faces(ShotwellFaces1 *object,
                                       GDBusMethodInvocation *invocation,
                                       const gchar *arg_image,
                                       const gchar *arg_cascade,
                                       gdouble arg_scale,
                                       gboolean arg_infer) {
    GVariantBuilder *builder;
    GVariant *faces;
    std::vector<FaceRect> rects = 
        detectFaces(arg_image, arg_cascade, arg_scale, arg_infer);
    // Construct return value
    builder = g_variant_builder_new(G_VARIANT_TYPE ("a(ddddad)"));
    for (std::vector<FaceRect>::const_iterator r = rects.begin(); r != rects.end(); r++) {
        GVariantBuilder *arr_builder = g_variant_builder_new(G_VARIANT_TYPE ("ad"));
        for (std::vector<double>::const_iterator v = r->vec.begin(); v != r->vec.end(); v++) {
            GVariant *d = g_variant_new("d", *v);
            g_variant_builder_add(arr_builder, "d", d);
        }
        GVariant *vec = g_variant_new("ad", arr_builder);
        g_variant_builder_unref(arr_builder);
        GVariant *rect = g_variant_new("(dddd@ad)", r->x, r->y, r->width, r->height, vec);
        g_variant_builder_add(builder, "@(ddddad)", rect);
        g_debug("Returning %f,%f-%f", r->x, r->y, r->vec.back());
    }
    faces = g_variant_new("a(ddddad)", builder);
    g_variant_builder_unref (builder);
    // Call return
    shotwell_faces1_complete_detect_faces(object, invocation,
                                          faces);
    return TRUE;
}

static gboolean on_handle_load_net(ShotwellFaces1 *object,
                                   GDBusMethodInvocation *invocation,
                                   const gchar *arg_net) {
    bool ret = loadNet(arg_net);
    // Call return
    shotwell_faces1_complete_load_net(object, invocation,
                                      ret);
    return TRUE;
}

static gboolean on_handle_face_to_vec(ShotwellFaces1 *object,
                                      GDBusMethodInvocation *invocation,
                                      const gchar *arg_image) {
    GVariantBuilder *builder;
    GVariant *ret;
    std::vector<double> vec = faceToVec(arg_image);
    builder = g_variant_builder_new(G_VARIANT_TYPE ("ad"));
    for (std::vector<double>::const_iterator r = vec.begin(); r != vec.end(); r++) {
        GVariant *v = g_variant_new("d", *r);
        g_variant_builder_add(builder, "d", v);
    }
    ret = g_variant_new("ad", builder);
    g_variant_builder_unref(builder);
    shotwell_faces1_complete_face_to_vec(object, invocation,
                                         ret);
    return TRUE;
}

static gboolean on_handle_terminate(ShotwellFaces1 *object,
                                    GDBusMethodInvocation *invocation,
                                    gpointer user_data) {
    g_debug("Exiting...");
    shotwell_faces1_complete_terminate(object, invocation);
    g_main_loop_quit(reinterpret_cast<GMainLoop *>(user_data));

    return TRUE;
}

static void on_name_acquired(GDBusConnection *connection,
                             const gchar *name, gpointer user_data) {
    ShotwellFaces1 *interface;
    GError *error;
    interface = shotwell_faces1_skeleton_new();
    g_debug("Got name %s", name);
    g_signal_connect(interface, "handle-detect-faces", G_CALLBACK (on_handle_detect_faces), NULL);
    g_signal_connect(interface, "handle-terminate", G_CALLBACK (on_handle_terminate), user_data);
    g_signal_connect(interface, "handle-load-net", G_CALLBACK (on_handle_load_net), NULL);
    g_signal_connect(interface, "handle-face-to-vec", G_CALLBACK (on_handle_face_to_vec), NULL);
    error = NULL;
    g_dbus_interface_skeleton_export(G_DBUS_INTERFACE_SKELETON(interface), connection, "/org/gnome/shotwell/faces", &error);
}

static void on_name_lost(GDBusConnection *connection,
                         const gchar *name, gpointer user_data) {
    if (connection == NULL) {
        g_debug("Unable to establish connection for name %s", name);
    } else {
        g_debug("Connection for name %s disconnected", name);
    }
    g_main_loop_quit((GMainLoop *)user_data);
}

int main(int argc, char **argv) {
    GMainLoop *loop;
    loop = g_main_loop_new (NULL, FALSE);
	g_bus_own_name(G_BUS_TYPE_SESSION, "org.gnome.Shotwell.Faces1", G_BUS_NAME_OWNER_FLAGS_NONE, NULL,
                   on_name_acquired, on_name_lost, loop, NULL);
    g_main_loop_run (loop);
    return 0;
}
