/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

#ifndef GPHOTO_H
#define GPHOTO_H

#define GPHOTO_REF_CAMERA(c)    (gp_camera_ref(c) == GP_OK ? c : NULL)

#define GPHOTO_REF_FILE(c)      (gp_file_ref(c) == GP_OK ? c : NULL)

#define GPHOTO_REF_LIST(c)      (gp_list_ref(c) == GP_OK ? c : NULL)

#define GPHOTO_REF_CONTEXT(c)   (gp_context_ref(c) == GP_OK ? c : NULL)

#endif /* GPHOTO_H */
