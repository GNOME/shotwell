
#ifndef GPHOTO_H
#define GPHOTO_H

#define GPHOTO_REF_CAMERA(c)    (gp_camera_ref(c) == GP_OK ? c : NULL)

#define GPHOTO_REF_FILE(c)      (gp_file_ref(c) == GP_OK ? c : NULL)

#define GPHOTO_REF_LIST(c)      (gp_list_ref(c) == GP_OK ? c : NULL)

#define GPHOTO_REF_CONTEXT(c)   (gp_context_ref(c) == GP_OK ? c : NULL)

#endif /* GPHOTO_H */
