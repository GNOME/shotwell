prefix=_PREFIX_
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: Shotwell Plugin Development
Description: Headers for building Shotwell plugins
Requires: _REQUIREMENTS_
Version: _VERSION_
Cflags: -I${includedir}/shotwell

