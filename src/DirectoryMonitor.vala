/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

//
// DirectoryMonitor will monitor an entire directory for changes to all files and directories
// within it.  It uses FileMonitor to monitor all directories it discovers at initialization
// and reports changes to the files and directories just as FileMonitor reports them.  Subclasses
// can override the notify_* methods to filter or monitor events before the signal is fired,
// or can override the signals themselves to be notified afterwards.
//
// start_discovery() must be called to initiate monitoring.  Directories and files will be reported
// as they're discovered.  Directories will be monitored as they're discovered as well.  Discovery
// can only be initiated once.
//
// All signals are virtual and have a corresponding notify_* protected virtual function.
// Subclasses can either override the notify or the signal to decide when they want to process
// the event.
//
// DirectoryMonitor also adds a level of intelligence to GLib's monitoring API.Because certain
// file/directory events are decomposed by FileMonitor into more atomic events, it's difficult
// to know when these "composed" events have occurred.  (For example, a file move is reported
// as a DELETED event followed by a CREATED event, with no clue that the two are related.)  Later
// versions added the MOVE event, but we can't rely on those being installed.  Also, documentation
// suggests it's only available with certain back-ends.
//
// DirectoryMonitor attempts to solve this by deducing when a set of events actually equals
// a composite event.  It requires more memory in order to do this (i.e. it stores all files and
// their information), but the trade-off is easier file/directory monitoring via familiar
// semantics.
//
// Because of these requirements, DirectoryMonitor maintains a FileInfo struct on all directories 
// and files being monitored.  (It maintains the attributes gather during the discovery phase, i.e. 
// SUPPLIED_ATTRIBUTES.)  This information can be retrieved via get_info(), get_file_id(), and
// get_etag().  These calls can be made at any time; the information is stored before any signal
// is fired.
//
// Note that DirectoryMonitor currently only supports files and directories.  Other file types
// (special, symbolic links, shortcuts, and mount points) are not supported.  It has been seen
// when a temporary file is created for its file type to be reported as "unknown" and when it's
// altered/deleted to be reported as a regular file.  This means it's possible for a file not to
// be reported as discovered or created but to be reported as altered and/or deleted.
//
// DirectoryMonitor can be configured to not recurse (in which case it only discovers/monitors
// the root directory) and to not monitor (in which case only discovery occurs).
//

public class DirectoryMonitor : Object {
    public const string SUPPLIED_ATTRIBUTES = "standard::*,time::*,id::file,id::filesystem,etag::value";
    public const int DEFAULT_PRIORITY = Priority.LOW;
    
    private const FileMonitorFlags FILE_MONITOR_FLAGS = FileMonitorFlags.SEND_MOVED;
    private const uint DELETED_EXPIRATION_MSEC = 500;
    private const int MAX_EXPLORATION_DIRS = 5;
    
    private enum FType {
        FILE,
        DIRECTORY,
        UNSUPPORTED
    }
    
    private class QueryInfoQueueElement {
        private static uint current = 0;
        
        public DirectoryMonitor owner;
        public File file;
        public File? other_file;
        public FileMonitorEvent event;
        public uint position;
        public FileInfo info = null;
        public Error err = null;
        public bool completed = false;
        
        public QueryInfoQueueElement(DirectoryMonitor owner, File file, File? other_file, 
            FileMonitorEvent event) {
            this.owner = owner;
            this.file = file;
            this.other_file = other_file;
            this.event = event;
            this.position = current++;
        }
        
        public void on_completed(Object? source, AsyncResult aresult) {
            File source_file = (File) source;
            
            // finish the async operation to get the result
            try {
                info = source_file.query_info_async.end(aresult);
            } catch (Error err) {
                this.err = err;
            }
            
            // mark as completed
            completed = true;
            
            // notify owner this job is finished, to process the queue
            owner.on_query_finished(this);
        }
    }
    
    // The FileInfoMap solves several related problems while maintaining FileInfo's in memory
    // so they're available to users of DirectoryMonitor as well as DirectoryMonitor itself,
    // which uses them to detect certain conditions.  FileInfoMap uses a File ID to maintain
    // only unique references to each File (and thus can be used to detect symlinked files).
    private class FileInfoMap {
        private Gee.HashMap<File, FileInfo> map = new Gee.HashMap<File, FileInfo>(file_hash,
            file_equal);
        private Gee.HashMap<string, File> id_map = new Gee.HashMap<string, File>(str_hash,
            str_equal, file_equal);
        
        public FileInfoMap() {
        }
        
        protected bool normalize_file(File file, FileInfo? info, out File normalized, out string id) {
            // if no info is supplied, see if file straight-up corresponds .. if not, we're out of
            // luck
            FileInfo? local_info = info;
            if (local_info == null) {
                local_info = map.get(file);
                if (local_info == null)
                    return false;
            }
            
            string? file_id = get_file_info_id(local_info);
            if (file_id == null)
                return false;
            
            File? known_file = id_map.get(file_id);
            
            id = (string) file_id;
            normalized = (known_file != null) ? known_file : file;
            
            return true;
        }
        
        public virtual bool update(File file, FileInfo info) {
            string id;
            File normalized;
            if (!normalize_file(file, info, out normalized, out id))
                return false;
            
            map.set(normalized, info);
            id_map.set(id, normalized);
            
            return true;
        }
        
        public virtual bool remove(File file, FileInfo? info) {
            string id;
            File normalized;
            if (!normalize_file(file, info, out normalized, out id))
                return false;
            
            map.unset(normalized);
            id_map.unset(id);
            
            return true;
        }
        
        // This calls the virtual function remove() for all files, so overriding it is sufficient
        // (but not necessarily most efficient)
        public virtual void remove_all(Gee.Collection<File> files) {
            foreach (File file in files)
                remove(file, null);
        }
        
        // This calls the virtual function remove() for all files in the map.
        public virtual void remove_map(Gee.Map<File, FileInfo> file_map) {
            foreach (File file in file_map.keys)
                remove(file, file_map.get(file));
        }
        
        public bool contains(File file, FileInfo? info) {
            string id;
            File normalized;
            if (!normalize_file(file, info, out normalized, out id))
                return false;
            
            return id_map.has_key(id);
        }
        
        public string? get_id(File file, FileInfo? info) {
            // if FileInfo is valid, easy pickings
            if (info != null)
                return get_file_info_id(info);
            
            string id;
            File normalized;
            if (!normalize_file(file, null, out normalized, out id))
                return null;
            
            return id;
        }
        
        public FileInfo? get_info(File file) {
            // if file is known as-is, use that
            FileInfo? info = map.get(file);
            if (info != null)
                return info;
            
            string id;
            File normalized;
            if (!normalize_file(file, null, out normalized, out id))
                return null;
            
            return map.get(normalized);
        }
        
        public FileInfo? query_info(File file, Cancellable? cancellable) {
            FileInfo? info = get_info(file);
            if (info != null)
                return info;
            
            // This *only* retrieves the file ID, which is then used to obtain the in-memory file
            // information.
            try {
                info = file.query_info(FILE_ATTRIBUTE_ID_FILE, FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                    cancellable);
            } catch (Error err) {
                warning("Unable to query file ID of %s: %s", file.get_path(), err.message);
                
                return null;
            }
            
            string? id = info.get_attribute_string(FILE_ATTRIBUTE_ID_FILE);
            if (id == null)
                return null;
            
            File? normalized = id_map.get(id);
            if (normalized == null)
                return null;
            
            return map.get(file);
        }
        
        public File? get_file(string id) {
            return id_map.get(id);
        }
        
         public File? find_match(FileInfo match) {
            string? match_id = get_file_info_id(match);
            if (match_id == null)
                return null;
            
            // get all the interesting matchable items from the supplied FileInfo
            int64 match_size = match.get_size();
            TimeVal match_time;
            match.get_modification_time(out match_time);
            
            foreach (File file in map.keys) {
                FileInfo info = map.get(file);
                
                // file id match is instant match
                if (get_file_info_id(info) == match_id)
                    return file;
                
                // if file size *and* modification time match, stop
                if (match_size != info.get_size())
                    continue;
                
                TimeVal time;
                info.get_modification_time(out time);
                
                if (time.tv_sec != match_time.tv_sec)
                    continue;
                
                return file;
            }
            
            return null;
        }
        
        public int get_count() {
            return map.size;
        }
        
        public void remove_descendents(File root, FileInfoMap descendents) {
            Gee.ArrayList<File> pruned = null;
            foreach (File file in map.keys) {
                File? parent = file.get_parent();
                while (parent != null) {
                    if (parent.equal(root)) {
                        if (pruned == null)
                            pruned = new Gee.ArrayList<File>();
                        
                        pruned.add(file);
                        descendents.update(file, map.get(file));
                        
                        break;
                    }
                    
                    parent = parent.get_parent();
                }
            }
            
            if (pruned != null)
                remove_all(pruned);
        }
    }
    
    // A TimedFileInfoMap merely adds a timestamp to each file as it's added, and thus can be
    // used to timeout certain operations.
    private class TimedFileInfoMap : FileInfoMap {
        private Gee.HashMap<string, ulong> time_added = new Gee.HashMap<string, ulong>(str_hash,
            str_equal);
        
        public TimedFileInfoMap() {
        }
        
        public override bool update(File file, FileInfo info) {
            if (!base.update(file, info))
                return false;
            
            string? id = get_id(file, info);
            assert(id != null);
            
            time_added.set(id, now_ms());
            
            return true;
        }
        
        public override bool remove(File file, FileInfo? info) {
            if (!base.remove(file, info))
                return false;
            
            string? id = get_id(file, info);
            assert(id != null);
            
            time_added.unset(id);
            
            return true;
        }
        
        public Gee.Map<File, FileInfo>? remove_older_than(ulong time) {
            Gee.Map<File, FileInfo> retirees = null;
            foreach (string id in time_added.keys) {
                ulong added = time_added.get(id);
                if (added <= time) {
                    if (retirees == null)
                        retirees = new Gee.HashMap<File, FileInfo>(file_hash, file_equal);
                    
                    File? file = get_file(id);
                    assert(file != null);
                    
                    FileInfo? info = get_info(file);
                    assert(info != null);
                    
                    retirees.set(file, info);
                }
            }
            
            if (retirees != null)
                remove_map(retirees);
            
            return retirees;
        }
    }
    
    private File root;
    private bool recurse;
    private bool monitoring;
    private Gee.HashMap<string, FileMonitor> monitors = new Gee.HashMap<string, FileMonitor>();
    private Gee.Queue<QueryInfoQueueElement> query_info_queue = new Gee.LinkedList<
        QueryInfoQueueElement>();
    private FileInfoMap files = new FileInfoMap();
    private TimedFileInfoMap deleted = new TimedFileInfoMap();
    private FileInfoMap parent_moved = new FileInfoMap();
    private Cancellable cancellable = new Cancellable();
    private int outstanding_exploration_dirs = 0;
    private bool has_discovery_started = false;
    private bool delete_timer_active = false;
    
    // This signal will be fired *after* directory-moved has been fired.
    public virtual signal void root_moved(File old_root, File new_root, FileInfo new_root_info) {
    }
    
    // If the root is deleted, then the DirectoryMonitor is essentially dead; it has no monitor
    // to wait for the root to be re-created, and everything beneath the root is obviously blown
    // away as well.
    //
    // This signal will be fired *after* directory-deleted has been fired.
    public virtual signal void root_deleted(File root) {
    }
    
    public virtual signal void discovery_started() {
    }
    
    public virtual signal void file_discovered(File file, FileInfo info) {
    }
    
    public virtual signal void directory_discovered(File file, FileInfo info) {
    }
    
    // reason is a user-visible string.  May be called more than once during discovery.
    // Discovery always completes with discovery-completed.
    public virtual signal void discovery_failed(string reason) {
    }
    
    public virtual signal void discovery_completed() {
        has_discovery_started = false;
        mdbg("discovery completed");
    }
    
    public virtual signal void file_created(File file, FileInfo info) {
    }
    
    public virtual signal void file_moved(File old_file, File new_file, FileInfo new_file_info) {
    }
    
    // FileInfo is not updated for each file-altered signal.
    public virtual signal void file_altered(File file) {
    }
    
    public virtual signal void file_alteration_completed(File file, FileInfo info) {
    }
    
    public virtual signal void file_attributes_altered(File file, FileInfo info) {
    }
    
    public virtual signal void file_deleted(File file) {
    }
    
    // This implies that the directory is now being monitored.
    public virtual signal void directory_created(File dir, FileInfo info) {
    }
    
    // This implies that the old directory is no longer being monitored and the new one is.
    public virtual signal void directory_moved(File old_dir, File new_dir, FileInfo new_dir_info) {
    }
    
    // FileInfo is not updated for each directory-altered signal.
    public virtual signal void directory_altered(File dir) {
    }
    
    public virtual signal void directory_alteration_completed(File dir, FileInfo info) {
    }
    
    public virtual signal void directory_attributes_altered(File dir, FileInfo info) {
    }
    
    // This implies that the directory is now no longer be monitored (unsurprisingly).
    public virtual signal void directory_deleted(File dir) {
    }
    
    public virtual signal void closed() {
    }
    
    public DirectoryMonitor(File root, bool recurse, bool monitoring) {
        this.root = root;
        this.recurse = recurse;
        this.monitoring = monitoring;
    }
    
    ~DirectoryMonitor() {
        close();
    }
    
    protected void mdbg(string msg) {
#if TRACE_MONITORING
        debug("%s", msg);
#endif
    }
    
    protected virtual void notify_root_deleted(File root) {
        assert(this.root.equal(root));
        
        mdbg("root deleted");
        root_deleted(root);
    }
    
    private void internal_notify_root_moved(File old_root, File new_root, FileInfo new_root_info) {
        bool removed = files.remove(old_root, null);
        assert(removed);
        
        bool updated = files.update(new_root, new_root_info);
        assert(updated);
        
        root = new_root;
        
        notify_root_moved(old_root, new_root, new_root_info);
    }
    
    protected virtual void notify_root_moved(File old_root, File new_root, FileInfo new_root_info) {
        assert(this.root.equal(old_root));
        
        mdbg("root moved: %s -> %s".printf(old_root.get_path(), new_root.get_path()));
        root_moved(old_root, new_root, new_root_info);
    }
    
    protected virtual void notify_discovery_started() {
        mdbg("discovery started");
        discovery_started();
    }
    
    protected virtual void internal_notify_file_discovered(File file, FileInfo info) {
        bool updated = files.update(file, info);
        assert(updated);
        
        notify_file_discovered(file, info);
    }
    
    protected virtual void notify_file_discovered(File file, FileInfo info) {
        mdbg("file discovered: %s".printf(file.get_path()));
        file_discovered(file, info);
    }
    
    protected virtual void internal_notify_directory_discovered(File dir, FileInfo info) {
        bool updated = files.update(dir, info);
        assert(updated);
        
        notify_directory_discovered(dir, info);
    }
    
    protected virtual void notify_directory_discovered(File dir, FileInfo info) {
        mdbg("directory discovered: %s".printf(dir.get_path()));
        directory_discovered(dir, info);
    }
    
    protected virtual void notify_discovery_failed(string reason) {
        warning("discovery failed: %s", reason);
        discovery_failed(reason);
    }
    
    protected virtual void notify_discovery_completed() {
        discovery_completed();
    }
    
    private void internal_notify_file_created(File file, FileInfo info) {
        File old_file;
        FileInfo old_file_info;
        if (is_file_create_move(file, info, out old_file, out old_file_info)) {
            internal_notify_file_moved(old_file, file, info);
        } else {
            bool updated = files.update(file, info);
            assert(updated);
            
            notify_file_created(file, info);
        }
    }
    
    protected virtual void notify_file_created(File file, FileInfo info) {
        mdbg("file created: %s".printf(file.get_path()));
        file_created(file, info);
    }
    
    private void internal_notify_file_moved(File old_file, File new_file, FileInfo new_file_info) {
        // don't assert because it's possible this call was generated via a deleted-created
        // sequence, in which case the old_file won't be in files
        files.remove(old_file, null);
        
        bool updated = files.update(new_file, new_file_info);
        assert(updated);
        
        notify_file_moved(old_file, new_file, new_file_info);
    }
    
    protected virtual void notify_file_moved(File old_file, File new_file, FileInfo new_file_info) {
        mdbg("file moved: %s -> %s".printf(old_file.get_path(), new_file.get_path()));
        file_moved(old_file, new_file, new_file_info);
    }
    
    protected virtual void notify_file_altered(File file) {
        mdbg("file altered: %s".printf(file.get_path()));
        file_altered(file);
    }
    
    private void internal_notify_file_alteration_completed(File file, FileInfo info) {
        bool updated = files.update(file, info);
        assert(updated);
        
        notify_file_alteration_completed(file, info);
    }
    
    protected virtual void notify_file_alteration_completed(File file, FileInfo info) {
        mdbg("file alteration completed: %s".printf(file.get_path()));
        file_alteration_completed(file, info);
    }
    
    private void internal_notify_file_attributes_altered(File file, FileInfo info) {
        bool updated = files.update(file, info);
        assert(updated);
        
        notify_file_attributes_altered(file, info);
    }
    
    protected virtual void notify_file_attributes_altered(File file, FileInfo info) {
        mdbg("file attributes altered: %s".printf(file.get_path()));
        file_attributes_altered(file, info);
    }
    
    private void internal_notify_file_deleted(File file) {
        // shim to look for file moves ... this also handles updating the file info map
        if (on_file_deleted(file))
            return;
        
        notify_file_deleted(file);
    }
    
    protected virtual void notify_file_deleted(File file) {
        mdbg("file deleted: %s".printf(file.get_path()));
        file_deleted(file);
    }
    
    private void internal_notify_directory_created(File dir, FileInfo info) {
        File old_dir;
        FileInfo old_dir_info;
        if (is_file_create_move(dir, info, out old_dir, out old_dir_info)) {
            // A directory move, like a file move, is actually a directory-deleted followed
            // by a directory-created.  Unlike a file move, what follows directory-created
            // is a file/directory-created for each file and directory inside the folder
            // (although the matching deletes are never fired).  We want to issue moves for 
            // all those files as well and suppress the create calls.
            files.remove_descendents(old_dir, parent_moved);
            
            internal_notify_directory_moved(old_dir, old_dir_info, dir, info);
        } else {
            bool updated = files.update(dir, info);
            assert(updated);
            
            notify_directory_created(dir, info);
        }
    }
    
    protected virtual void notify_directory_created(File dir, FileInfo info) {
        mdbg("directory created: %s".printf(dir.get_path()));
        directory_created(dir, info);
    }
    
    private void internal_notify_directory_moved(File old_dir, FileInfo old_dir_info, File new_dir,
        FileInfo new_dir_info) {
        // Don't assert here because it's possible this call was made due to a deleted-created
        // sequence, in which case the directory has already been removed from files
        files.remove(old_dir, null);
        
        bool updated = files.update(new_dir, new_dir_info);
        assert(updated);
        
        // remove the old monitor and add the new one
        remove_monitor(old_dir, old_dir_info);
        add_monitor(new_dir, new_dir_info);
        
        notify_directory_moved(old_dir, new_dir, new_dir_info);
    }
    
    protected virtual void notify_directory_moved(File old_dir, File new_dir, FileInfo new_dir_info) {
        mdbg("directory moved: %s -> %s".printf(old_dir.get_path(), new_dir.get_path()));
        directory_moved(old_dir, new_dir, new_dir_info);
        
        if (old_dir.equal(root))
            internal_notify_root_moved(old_dir, new_dir, new_dir_info);
    }
    
    protected virtual void notify_directory_altered(File dir) {
        mdbg("directory altered: %s".printf(dir.get_path()));
        directory_altered(dir);
    }
    
    private void internal_notify_directory_alteration_completed(File dir, FileInfo info) {
        bool updated = files.update(dir, info);
        assert(updated);
        
        notify_directory_alteration_completed(dir, info);
    }
    
    protected virtual void notify_directory_alteration_completed(File dir, FileInfo info) {
        mdbg("directory alteration completed: %s".printf(dir.get_path()));
        directory_alteration_completed(dir, info);
    }
    
    private void internal_notify_directory_attributes_altered(File dir, FileInfo info) {
        bool updated = files.update(dir, info);
        assert(updated);
        
        notify_directory_attributes_altered(dir, info);
    }
    
    protected virtual void notify_directory_attributes_altered(File dir, FileInfo info) {
        mdbg("directory attributes altered: %s".printf(dir.get_path()));
        directory_attributes_altered(dir, info);
    }
    
    private void internal_notify_directory_deleted(File dir) {
        FileInfo? info = files.get_info(dir);
        assert(info != null);
        
        // stop monitoring this directory
        remove_monitor(dir, info);
        
        // see if should report this or wait ... this updates the file map as well
        if (on_file_deleted(dir))
            return;
        
        notify_directory_deleted(dir);
    }
    
    protected virtual void notify_directory_deleted(File dir) {
        mdbg("directory deleted: %s".printf(dir.get_path()));
        directory_deleted(dir);
        
        if (dir.equal(root))
            notify_root_deleted(dir);
    }
    
    protected virtual void notify_closed() {
        mdbg("monitoring of %s closed".printf(root.get_path()));
        closed();
    }
    
    public File get_root() {
        return root;
    }
    
    public bool is_in_root(File file) {
        File? parent = file;
        do {
            if (parent.equal(root))
                return true;
            
            parent = parent.get_parent();
        } while (parent != null);
        
        return false;
    }
    
    public void start_discovery() throws Error {
        assert(!has_discovery_started);
        
        has_discovery_started = true;
        notify_discovery_started();
        
        // start exploring the directory, adding monitors as the directories are discovered
        outstanding_exploration_dirs = 1;
        explore_async.begin(root, null, true);
    }
    
    // This should be called when a DirectoryMonitor needs to be destroyed or released.  This
    // will halt background exploration and close all resources.
    public virtual void close() {
        // cancel any outstanding async I/O
        cancellable.cancel();
        
        // cancel all monitors
        foreach (FileMonitor monitor in monitors.values)
            cancel_monitor(monitor);
        
        monitors.clear();
        
        notify_closed();
    }
    
    private FType get_ftype(FileInfo info) {
        FileType file_type = info.get_file_type();
        switch (file_type) {
            case FileType.REGULAR:
                return FType.FILE;
            
            case FileType.DIRECTORY:
                return FType.DIRECTORY;
            
            default:
                mdbg("query_ftype: Unknown file type %s".printf(file_type.to_string()));
                return FType.UNSUPPORTED;
        }
    }
    
    private async void explore_async(File dir, FileInfo? dir_info, bool in_discovery) {
        if (files.contains(dir, dir_info)) {
            warning("Directory loop detected at %s, not exploring", dir.get_path());
            
            explore_directory_completed(in_discovery);
            
            return;
        }
        
        // if FileInfo wasn't supplied by caller, fetch it now
        FileInfo? local_dir_info = dir_info;
        if (local_dir_info == null) {
            try {
                local_dir_info = yield dir.query_info_async(SUPPLIED_ATTRIBUTES,
                    FileQueryInfoFlags.NONE, DEFAULT_PRIORITY, cancellable);
            } catch (Error err) {
                warning("Unable to retrieve info on %s: %s", dir.get_path(), err.message);
                
                explore_directory_completed(in_discovery);
                
                return;
            }
        }
        
        // verify this is a directory
        if (local_dir_info.get_file_type() != FileType.DIRECTORY) {
            notify_discovery_failed(_("Unable to monitor %s: Not a directory (%s)").printf(
                dir.get_path(), local_dir_info.get_file_type().to_string()));
            
            explore_directory_completed(in_discovery);
            
            return;
        }
        
        // collect all directories and files in the directory, to consolidate reporting them as
        // well as traversing the subdirectories -- but to avoid a lot of unnecessary resource
        // allocations (think empty directories, or leaf nodes with only files), only allocate
        // the maps when necessary
        Gee.HashMap<File, FileInfo> dir_map = null;
        Gee.HashMap<File, FileInfo> file_map = null;
        
        try {
            FileEnumerator enumerator = yield dir.enumerate_children_async(SUPPLIED_ATTRIBUTES,
                FileQueryInfoFlags.NONE, DEFAULT_PRIORITY, cancellable);
            for (;;) {
                List<FileInfo>? infos = yield enumerator.next_files_async(10, DEFAULT_PRIORITY,
                    cancellable);
                if (infos == null)
                    break;
                
                foreach (FileInfo info in infos) {
                    switch (info.get_file_type()) {
                        case FileType.REGULAR:
                            if (file_map == null)
                                file_map = new Gee.HashMap<File, FileInfo>(file_hash, file_equal);
                            
                            file_map.set(dir.get_child(info.get_name()), info);
                        break;
                        
                        case FileType.DIRECTORY:
                            if (dir_map == null)
                                dir_map = new Gee.HashMap<File, FileInfo>(file_hash, file_equal);
                            
                            dir_map.set(dir.get_child(info.get_name()), info);
                        break;
                        
                        default:
                            // ignored
                        break;
                    }
                }
            }
        } catch (Error err2) {
            warning("Aborted directory traversal of %s: %s", dir.get_path(), err2.message);
            
            explore_directory_completed(in_discovery);
            
            return;
        }
        
        // report the local (caller-supplied) directory as discovered *before* reporting its files
        if (in_discovery)
            internal_notify_directory_discovered(dir, local_dir_info);
        else
            internal_notify_directory_created(dir, local_dir_info);
        
        // now with everything snarfed up and the directory reported as discovered, begin 
        // monitoring the directory
        add_monitor(dir, local_dir_info);
        
        // report files in local directory
        if (file_map != null) {
            foreach (File file in file_map.keys) {
                if (in_discovery)
                    internal_notify_file_discovered(file, file_map.get(file));
                else
                    internal_notify_file_created(file, file_map.get(file));
            }
        }
        
        // post all the subdirectory traversals, allowing them to report themselves as discovered
        if (recurse && dir_map != null) {
            foreach (File subdir in dir_map.keys) {
                if (++outstanding_exploration_dirs > MAX_EXPLORATION_DIRS)
                    yield explore_async(subdir, dir_map.get(subdir), in_discovery);
                else
                    explore_async.begin(subdir, dir_map.get(subdir), in_discovery);
            }
        }
        
        explore_directory_completed(in_discovery);
    }
    
    // called whenever exploration of a directory is completed, to know when to signal that
    // discovery has ended
    private void explore_directory_completed(bool in_discovery) {
        assert(outstanding_exploration_dirs > 0);
        outstanding_exploration_dirs--;
        
        if (in_discovery && outstanding_exploration_dirs == 0)
            notify_discovery_completed();
    }
    
    // Only submit directories ... file monitoring is wasteful when a single directory monitor can
    // do all the work.  Returns true if monitor added, false if already monitored (or not
    // monitoring, or unable to  monitor due to error).
    private bool add_monitor(File dir, FileInfo info) {
        if (!monitoring)
            return false;
        
        string? id = files.get_id(dir, info);
        if (id == null)
            return false;
        
        // if one already exists, nop
        if (monitors.has_key(id))
            return false;
        
        FileMonitor monitor = null;
        try {
            monitor = dir.monitor_directory(FILE_MONITOR_FLAGS, null);
        } catch (Error err) {
            warning("Unable to monitor %s: %s", dir.get_path(), err.message);
            
            return false;
        }
        
        monitors.set(id, monitor);
        monitor.changed.connect(on_monitor_notification);
        
        mdbg("Added monitor for %s".printf(dir.get_path()));
        
        return true;
    }
    
    // Returns true if the directory is removed (i.e. was being monitored).
    private bool remove_monitor(File dir, FileInfo info) {
        if (!monitoring)
            return false;
        
        string? id = files.get_id(dir, info);
        if (id == null)
            return false;
        
        FileMonitor? monitor = monitors.get(id);
        if (monitor == null)
            return false;
        
        bool removed = monitors.unset(id);
        assert(removed);
        
        cancel_monitor(monitor);
        
        mdbg("Removed monitor for %s".printf(dir.get_path()));
        
        return true;
    }
    
    private void cancel_monitor(FileMonitor monitor) {
        monitor.changed.disconnect(on_monitor_notification);
        monitor.cancel();
    }
    
    private void on_monitor_notification(File file, File? other_file, FileMonitorEvent event) {
        mdbg("%s: file=%s other_file=%s".printf(event.to_string(), file.get_path(),
            other_file != null ? other_file.get_path() : "(none)"));
        
        // The problem: Having basic file information about each file is valuable (and necessary
        // in certain situations), but it is a blocking operation, no matter how "quick" it
        // may seem.  Async I/O is perfect to handle this, but it can complete out of order, and
        // it's highly desirous to report events in the same order they're received.  FileInfo
        // queries are queued up then and processed in order as they're completed.
        
        // Every event needs to be queued, but not all events generates query I/O
        QueryInfoQueueElement query_event = new QueryInfoQueueElement(this, file, other_file, event);
        query_info_queue.offer(query_event);
        
        switch (event) {
            case FileMonitorEvent.CREATED:
            case FileMonitorEvent.CHANGES_DONE_HINT:
            case FileMonitorEvent.ATTRIBUTE_CHANGED:
                file.query_info_async.begin(SUPPLIED_ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                    DEFAULT_PRIORITY, cancellable, query_event.on_completed);
            break;
            
            case FileMonitorEvent.MOVED:
                // unlike the others, other_file is the destination of the move, and therefore the
                // one we need to get info on
                if (other_file != null) {
                    other_file.query_info_async.begin(SUPPLIED_ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                        DEFAULT_PRIORITY, cancellable, query_event.on_completed);
                } else {
                    warning("Unable to process MOVED event: no other_file");
                    query_info_queue.remove(query_event);
                }
            break;
            
            default:
                // artifically complete it
                query_event.completed = true;
                on_query_finished(query_event);
            break;
        }
    }
    
    private void on_query_finished(QueryInfoQueueElement queue_event) {
        // peel off completed events from the queue in order
        for (;;) {
            // check if empty or waiting for completion on the next event
            QueryInfoQueueElement? next = query_info_queue.peek();
            if (next == null || !next.completed)
                break;
            
            // remove
            query_info_queue.poll();
            
            mdbg("Completed info query %u for %s on %s".printf(next.position, next.event.to_string(),
                next.file.get_path()));
            
            if (next.err != null) {
                warning("Unable to retrieve file information for %s, dropping %s: %s",
                    next.file.get_path(), next.event.to_string(), next.err.message);
                
                continue;
            }
            
            on_monitor_notification_ready(next.file, next.other_file, next.info, next.event);
        }
    }
    
    private void on_monitor_notification_ready(File file, File? other_file, FileInfo? info,
        FileMonitorEvent event) {
        mdbg("READY %s: file=%s other_file=%s".printf(event.to_string(), file.get_path(),
            other_file != null ? other_file.get_path() : "(null)"));
        
        // Nasty, nasty switches-in-a-switch construct, but this demuxes the possibilities into
        // easily digestible upcalls and signals
        switch (event) {
            case FileMonitorEvent.CREATED:
                assert(info != null);
                
                FType ftype = get_ftype(info);
                switch (ftype) {
                    case FType.FILE:
                        internal_notify_file_created(file, info);
                    break;
                    
                    case FType.DIRECTORY:
                        // other files may have been created under this new directory before we have
                        // a change to register a monitor, so scan it now looking for new additions
                        // (this call will notify of creation and monitor this new directory once 
                        // it's been scanned)
                        explore_async.begin(file, info, false);
                    break;
                    
                    default:
                        assert(ftype == FType.UNSUPPORTED);
                    break;
                }
            break;
            
            case FileMonitorEvent.CHANGED:
                // don't query info for each change, but only when done hint comes down the pipe
                assert(info == null);
                
                FileInfo local_info = get_file_info(file);
                if (local_info == null) {
                    warning("Changed event for unknown file %s", file.get_path());
                    
                    break;
                }
                
                FType ftype = get_ftype(local_info);
                switch (ftype) {
                    case FType.FILE:
                        notify_file_altered(file);
                    break;
                    
                    case FType.DIRECTORY:
                        notify_directory_altered(file);
                    break;
                    
                    default:
                        assert(ftype == FType.UNSUPPORTED);
                    break;
                }
            break;
            
            case FileMonitorEvent.CHANGES_DONE_HINT:
                assert(info != null);
                
                FType ftype = get_ftype(info);
                switch (ftype) {
                    case FType.FILE:
                        internal_notify_file_alteration_completed(file, info);
                    break;
                    
                    case FType.DIRECTORY:
                        internal_notify_directory_alteration_completed(file, info);
                    break;
                    
                    default:
                        assert(ftype == FType.UNSUPPORTED);
                    break;
                }
            break;
            
            case FileMonitorEvent.MOVED:
                assert(info != null);
                assert(other_file != null);
                
                // in the moved case, file info is for other file (the destination in the move
                // operation)
                FType ftype = get_ftype(info);
                switch (ftype) {
                    case FType.FILE:
                        internal_notify_file_moved(file, other_file, info);
                    break;
                    
                    case FType.DIRECTORY:
                        // get the old FileInfo (contained in files)
                        FileInfo? old_dir_info = files.get_info(file);
                        if (old_dir_info == null) {
                            warning("Directory moved event for unknown file %s", file.get_path());
                            
                            break;
                        }
                        
                        internal_notify_directory_moved(file, old_dir_info, other_file, info);
                    break;
                    
                    default:
                        assert(ftype == FType.UNSUPPORTED);
                    break;
                }
            break;
            
            case FileMonitorEvent.DELETED:
                assert(info == null);
                
                FileInfo local_info = get_file_info(file);
                if (local_info == null) {
                    warning("Deleted event for unknown file %s", file.get_path());
                    
                    break;
                }
                
                FType ftype = get_ftype(local_info);
                switch (ftype) {
                    case FType.FILE:
                        internal_notify_file_deleted(file);
                    break;
                    
                    case FType.DIRECTORY:
                        internal_notify_directory_deleted(file);
                    break;
                    
                    default:
                        assert(ftype == FType.UNSUPPORTED);
                    break;
                }
            break;
            
            case FileMonitorEvent.ATTRIBUTE_CHANGED:
                assert(info != null);
                
                FType ftype = get_ftype(info);
                switch (ftype) {
                    case FType.FILE:
                        internal_notify_file_attributes_altered(file, info);
                    break;
                    
                    case FType.DIRECTORY:
                        internal_notify_directory_attributes_altered(file, info);
                    break;
                    
                    default:
                        assert(ftype == FType.UNSUPPORTED);
                    break;
                }
            break;
            
            case FileMonitorEvent.PRE_UNMOUNT:
            case FileMonitorEvent.UNMOUNTED:
                // not currently handling these events
            break;
            
            default:
                warning("Unknown directory monitor event %s", event.to_string());
            break;
        }
    }
    
    // Returns true if a move occurred.  Internal state is modified to recognize the
    // situation (i.e. the move should be reported).
    private bool is_file_create_move(File file, FileInfo info, out File old_file,
        out FileInfo old_file_info) {
        // look for created file whose parent was actually moved
        File? match = parent_moved.find_match(info);
        if (match != null) {
            old_file = match;
            old_file_info = parent_moved.get_info(match);
            
            parent_moved.remove(match, info);
            
            return true;
        }
        
        // look for deleted file with matching attributes
        match = deleted.find_match(info);
        if (match != null) {
            old_file = match;
            old_file_info = deleted.get_info(match);
            
            deleted.remove(match, info);
            
            return true;
        }
        
        return false;
    }
    
    // Returns true if the caller should wait to report the deletion.  If returns false caller
    // should treat as an unknown file.
    private bool on_file_deleted(File file) {
        // add to deleted list and suppress firing the signal until (a) timeout (in which case
        // it's an actual delete) or (b) a create event occurs on a matching file, in which case
        // it's a move
        FileInfo? info = files.get_info(file);
        if (info == null) {
            // watch for double-deletions, which occur some times
            if (deleted.contains(file, null))
                return true;
            
            warning("Unknown file %s deleted from monitor on %s", file.get_path(),
                get_root().get_path());
            
            return false;
        }
        
        bool removed = files.remove(file, info);
        assert(removed);
        
        bool updated = deleted.update(file, info);
        assert(updated);
        
        if (!delete_timer_active) {
            Timeout.add(DELETED_EXPIRATION_MSEC / 2, on_deleted_timeout);
            delete_timer_active = true;
        }
        
        return true;
    }
    
    private bool on_deleted_timeout() {
        ulong expiration = now_ms() - DELETED_EXPIRATION_MSEC;
        
        // anything overdue on the deleted lists is considered gone
        Gee.Map<File, FileInfo>? overdue = deleted.remove_older_than(expiration);
        if (overdue != null) {
            foreach (File file in overdue.keys) {
                // Do NOT call the internal_* versions of deleted notifications, as these are
                // synthesized calls not "real" events (in other words, it's the internal calls
                // that got us to this point)
                FType ftype = get_ftype(overdue.get(file));
                switch (ftype) {
                    case FType.FILE:
                        notify_file_deleted(file);
                    break;
                    
                    case FType.DIRECTORY:
                        notify_directory_deleted(file);
                    break;
                    
                    default:
                        assert(ftype == FType.UNSUPPORTED);
                    break;
                }
            }
        }
        
        delete_timer_active = deleted.get_count() > 0;
        
        return delete_timer_active;
    }
    
    // This method does its best to return FileInfo for the file.  It performs no I/O.
    public FileInfo? get_file_info(File file) {
        return files.get_info(file);
    }
    
    // This method will attempt to find the in-memory FileInfo for the file, but if it cannot
    // be found it will query the file for it's ID and obtain in-memory file information from
    // there.
    public FileInfo? query_file_info(File file) {
        return files.query_info(file, cancellable);
    }
}

