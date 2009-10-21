#include <windows.h>

BOOL already_running() {
    HANDLE mutex = CreateMutex(NULL, TRUE, "shotwell_mutex");
    return mutex && GetLastError() == ERROR_ALREADY_EXISTS;
}

