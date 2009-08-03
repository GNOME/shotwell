/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

namespace Debug {
    private bool info_enabled = false;
    private bool debug_enabled = false;
    private bool message_enabled = false;
    private bool warning_enabled = false;
    private bool critical_enabled = false;
    
    public void init() {
        if (Environment.get_variable("SHOTWELL_LOG") != null) {
            info_enabled = true;
            debug_enabled = true;
            message_enabled = true;
            warning_enabled = true;
            critical_enabled = true;
        } else {
            info_enabled = (Environment.get_variable("SHOTWELL_INFO") != null);
            debug_enabled = (Environment.get_variable("SHOTWELL_DEBUG") != null);
            message_enabled = (Environment.get_variable("SHOTWELL_MESSAGE") != null);
            warning_enabled = (Environment.get_variable("SHOTWELL_WARNING") != null);
            critical_enabled = (Environment.get_variable("SHOTWELL_CRITICAL") != null);
        }

        Log.set_handler(null, LogLevelFlags.LEVEL_INFO, info_handler);
        Log.set_handler(null, LogLevelFlags.LEVEL_DEBUG, debug_handler);
        Log.set_handler(null, LogLevelFlags.LEVEL_MESSAGE, message_handler);
        Log.set_handler(null, LogLevelFlags.LEVEL_WARNING, warning_handler);
        Log.set_handler(null, LogLevelFlags.LEVEL_CRITICAL, critical_handler);
    }
    
    public void terminate() {
    }
    
    private void log(FileStream stream, string prefix, string message) {
        stream.puts(prefix);
        stream.puts(message);
        stream.putc('\n');
        stream.flush();
    }
    
    private void info_handler(string? domain, LogLevelFlags flags, string message) {
        if (info_enabled)
            log(stdout, "[INF] ", message);
    }
    
    private void debug_handler(string? domain, LogLevelFlags flags, string message) {
        if (debug_enabled)
            log(stdout, "[DBG] ", message);
    }
    
    private void message_handler(string? domain, LogLevelFlags flags, string message) {
        if (message_enabled)
            log(stderr, "[MSG] ", message);
    }

    private void warning_handler(string? domain, LogLevelFlags flags, string message) {
        if (warning_enabled)
            log(stderr, "[WRN] ", message);
    }

    private void critical_handler(string? domain, LogLevelFlags flags, string message) {
        if (critical_enabled)
            log(stderr, "[CRT] ", message);
    }
}

