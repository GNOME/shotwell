prefix=_PREFIX_
exec_prefix=${prefix}
libdir=${exec_prefix}/_LIB_
includedir=${prefix}/include

Name: Shotwell Plugin Development
Description: Headers for building Shotwell plugins
Requires: _REQUIREMENTS_
Version: _VERSION_
Cflags: -I${includedir}/shotwell

