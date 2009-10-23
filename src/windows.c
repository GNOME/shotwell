#include <windows.h>

BOOL already_running() {
    HANDLE mutex = CreateMutex(NULL, TRUE, "shotwell_mutex");
    return mutex && GetLastError() == ERROR_ALREADY_EXISTS;
}

int number_of_processors() {
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    return info.dwNumberOfProcessors;
}

