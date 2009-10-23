#if NO_LIBUNIQUE
extern bool already_running();
#endif

#if NO_EXTENDED_POSIX
extern int number_of_processors();
#else
int number_of_processors() {
    int n = (int) ExtendedPosix.sysconf(ExtendedPosix.ConfName._SC_NPROCESSORS_ONLN) - 1;
    return n <= 0 ? 1 : n;
}
#endif

