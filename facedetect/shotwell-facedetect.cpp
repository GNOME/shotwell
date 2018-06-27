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

using namespace std;
using namespace cv;

// DBus binding functions
static gboolean on_handle_detect_faces(ShotwellFaces1 *object,
                                       GDBusMethodInvocation *invocation,
                                       const gchar *arg_image,
                                       const gchar *arg_cascade,
                                       gdouble arg_scale) {
    GVariantBuilder *builder;
    GVariant *faces;
    vector<FaceRect> rects = 
        detectFaces(arg_image, arg_cascade, arg_scale);
    // Construct return value
    builder = g_variant_builder_new(G_VARIANT_TYPE ("a(dddd)"));
    for (vector<FaceRect>::const_iterator r = rects.begin(); r != rects.end(); r++) {
        GVariant *rect = g_variant_new("(dddd)", r->x, r->y, r->width, r->height);
        g_variant_builder_add(builder, "(dddd)", rect);
    }
    faces = g_variant_new("a(dddd)", builder);
    g_variant_builder_unref (builder);
    // Call return
    shotwell_faces1_complete_detect_faces(object, invocation,
                                          faces);
    g_free(faces);
    return TRUE;
}

gboolean on_handle_train_faces(ShotwellFaces1 *object,
                               GDBusMethodInvocation *invocation,
                               const gchar *const *arg_images,
                               const gchar *const *arg_labels,
                               const gchar *arg_model) {
    return TRUE;
}

gboolean on_handle_recognise_face(ShotwellFaces1 *object,
                                  GDBusMethodInvocation *invocation,
                                  const gchar *arg_image,
                                  const gchar *arg_model,
                                  gdouble arg_threshold) {
    return TRUE;
}

static void on_name_acquired(GDBusConnection *connection,
                             const gchar *name, gpointer user_data) {
    ShotwellFaces1 *interface;
    GError *error;
    interface = shotwell_faces1_skeleton_new();
    g_signal_connect(interface, "handle-detect-faces", G_CALLBACK (on_handle_detect_faces), NULL);
    error = NULL;
    !g_dbus_interface_skeleton_export(G_DBUS_INTERFACE_SKELETON(interface), connection, "/org/gnome/shotwell/faces", &error);
}

int main() {
	GMainLoop *loop;
	loop = g_main_loop_new (NULL, FALSE);
	g_bus_own_name(G_BUS_TYPE_SESSION, "org.gnome.shotwell.faces", G_BUS_NAME_OWNER_FLAGS_NONE, NULL,
                   on_name_acquired, NULL, NULL, NULL);
	g_main_loop_run (loop);

	return 0;
}
