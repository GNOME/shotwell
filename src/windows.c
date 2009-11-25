/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#include <stdlib.h>
#include <time.h>
#include <windows.h>

// We implement localtime_r here since Vala expects it (it's referenced in glib-2.0.vapi)
// but Windows doesn't have it.
// I *believe* that the Windows implementation of localtime uses thread-local storage
// and that this function is thread-safe as a result.  We could investigate this more.
struct tm *localtime_r(const time_t *t, struct tm *result) {
   struct tm *local_result = localtime(t);
   if (local_result == NULL || result == NULL)
     return NULL;

   memcpy(result, local_result, sizeof(*result));
   return result;
}

BOOL already_running() {
    HANDLE mutex = CreateMutex(NULL, TRUE, "shotwell_mutex");
    return mutex && GetLastError() == ERROR_ALREADY_EXISTS;
}

int number_of_processors() {
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    return info.dwNumberOfProcessors;
}

void sys_show_uri(void *screen, const char *uri, void *error) {
    ShellExecute(NULL, "open", uri, NULL, NULL, SW_SHOWNORMAL);
}

