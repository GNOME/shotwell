/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

namespace Debug {
    private const LogLevelFlags DEFAULT_LOG_MASK =
        LogLevelFlags.LEVEL_CRITICAL |
        LogLevelFlags.LEVEL_WARNING |
        LogLevelFlags.LEVEL_MESSAGE;
    
    public const string VIEWER_PREFIX = "V";
    public const string LIBRARY_PREFIX = "L";
    
    // Ideally, there would be a LogLevelFlags.NONE constant to use as
    // empty value but failing that, 0 works as well
    private LogLevelFlags log_mask = 0;
    private string log_app_version_prefix;
    // log_file_stream is the canonical reference to the file stream (and owns
    // it), while log_out and log_err are indirections that can point to
    // log_file_stream or stdout and stderr respectively
    private unowned FileStream log_out = null;
    private unowned FileStream log_err = null;
    private FileStream log_file_stream = null;
    
    public static void init(string app_version_prefix) {
        log_app_version_prefix = app_version_prefix;
        
        // default to stdout/stderr if file cannot be opened or console is specified
        log_out = stdout;
        log_err = stderr;
        
        string log_file_error_msg = null;
        
        // logging to disk is currently off for viewer more; see http://trac.yorba.org/ticket/2078
        File? log_file = (log_app_version_prefix == LIBRARY_PREFIX) ? AppDirs.get_log_file() : null;
        if(log_file != null) {
            File log_dir = log_file.get_parent();
            try {
                if (log_dir.query_exists(null) == false) {
                    if (!log_dir.make_directory_with_parents(null)) {
                        log_file_error_msg = "Unable to create data directory %s".printf(log_dir.get_path());
                    }
                } 
            } catch (Error err) {
                log_file_error_msg = err.message;
            }
            // overwrite the log file every time the application is started
            // to ensure it doesn't grow too large; if there is a need for
            // keeping the log, the 'w' should be replaced by 'a' and some sort
            // of log rotation implemented
            log_file_stream = FileStream.open(log_file.get_path(), "w");
            if(log_file_stream != null) {
                log_out = log_file_stream;
                log_err = log_file_stream;
            } else {
                log_file_error_msg = "Unable to open or create log file %s".printf(log_file.get_path());
            }
        }
        
        if (Environment.get_variable("SHOTWELL_LOG") != null) {
            log_mask = LogLevelFlags.LEVEL_MASK;
        } else {
            log_mask = ((Environment.get_variable("SHOTWELL_INFO") != null) ?
                log_mask | LogLevelFlags.LEVEL_INFO :
                log_mask);
            log_mask = ((Environment.get_variable("SHOTWELL_DEBUG") != null) ?
                log_mask | LogLevelFlags.LEVEL_DEBUG :
                log_mask);
            log_mask = ((Environment.get_variable("SHOTWELL_MESSAGE") != null) ?
                log_mask | LogLevelFlags.LEVEL_MESSAGE :
                log_mask);
            log_mask = ((Environment.get_variable("SHOTWELL_WARNING") != null) ?
                log_mask | LogLevelFlags.LEVEL_WARNING :
                log_mask);
            log_mask = ((Environment.get_variable("SHOTWELL_CRITICAL") != null) ?
                log_mask | LogLevelFlags.LEVEL_CRITICAL :
                log_mask);
        }

        Log.set_handler(null, LogLevelFlags.LEVEL_INFO, info_handler);
        Log.set_handler(null, LogLevelFlags.LEVEL_DEBUG, debug_handler);
        Log.set_handler(null, LogLevelFlags.LEVEL_MESSAGE, message_handler);
        Log.set_handler(null, LogLevelFlags.LEVEL_WARNING, warning_handler);
        Log.set_handler(null, LogLevelFlags.LEVEL_CRITICAL, critical_handler);
        
        if(log_mask == 0 && log_file != null) {
            // if the log mask is still 0 and we have a log file, set the
            // mask to the default
            log_mask = DEFAULT_LOG_MASK;
        }
        
        if(log_file_error_msg != null) {
            warning("%s", log_file_error_msg);
        }
    }
    
    public static void terminate() {
    }
    
    private bool is_enabled(LogLevelFlags flag) {
        return ((log_mask & flag) > 0);
    }
    
    private void log(FileStream stream, string prefix, string message) {
        time_t now = time_t();
        stream.printf("%s %d %s [%s] %s\n",
            log_app_version_prefix,
            Posix.getpid(),
            Time.local(now).to_string(),
            prefix,
            message
        );
        stream.flush();
    }
    
    private void info_handler(string? domain, LogLevelFlags flags, string message) {
        if (is_enabled(LogLevelFlags.LEVEL_INFO))
            log(log_out, "INF", message);
    }
    
    private void debug_handler(string? domain, LogLevelFlags flags, string message) {
        if (is_enabled(LogLevelFlags.LEVEL_DEBUG))
            log(log_out, "DBG", message);
    }
    
    private void message_handler(string? domain, LogLevelFlags flags, string message) {
        if (is_enabled(LogLevelFlags.LEVEL_MESSAGE))
            log(log_err, "MSG", message);
    }

    private void warning_handler(string? domain, LogLevelFlags flags, string message) {
        if (is_enabled(LogLevelFlags.LEVEL_WARNING))
            log(log_err, "WRN", message);
    }

    private void critical_handler(string? domain, LogLevelFlags flags, string message) {
        if (is_enabled(LogLevelFlags.LEVEL_CRITICAL)) {
            log(log_err, "CRT", message);
            if (log_file_stream != null)
                log(stderr, "CRT", message);    // also log to console
        }
    }
}

