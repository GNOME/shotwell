/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

//
// LibraryMonitor uses DirectoryMonitor to track assets in the user's library directory and make
// sure they're reflected in the application.
//
// NOTE: There appears to be a bug where prior versions of Shotwell (>= 0.6.x) were not
// properly loading the file modification timestamp during import.  This was no issue
// before but becomes imperative now with file monitoring.  A "proper" algorithm is
// to reimport an entire photo if the modification time in the database is different
// than the file's, but that's Real Bad when the user first turns on monitoring, as it
// will cause a lot of reimports (think of a 10,000 photo database) and will blow away
// ALL transformations, as they are now suspect.
//
// So: If the modification time is zero and filesize is the same, simply update the
// timestamp in the database and move on.
//
// TODO: Although it seems highly unlikely that a file's timestamp could change but the file size
// has not and the file really be "changed", it *is* possible, even in the case of complex little
// animals like photo files.  We could be more liberal and treat this case as a metadata-changed
// situation (since that's a likely case).
//
// NOTE: Current implementation is only to check all photos at initialization, with no auto-import
// and no realtime monitoring (http://trac.yorba.org/ticket/2302).  Auto-import and realtime
// monitoring will be added later.
//

public class LibraryMonitor : DirectoryMonitor {
    private Cancellable cancellable = new Cancellable();
    private Gee.HashSet<LibraryPhoto> discovered = null;
    private Gee.ArrayList<LibraryPhoto> external_mark_online = null;
    private Gee.ArrayList<LibraryPhoto> external_mark_offline = null;
    private int verify_external_outstanding = 0;
    
    public LibraryMonitor(File root, bool recurse, bool monitoring) {
        base (root, recurse, monitoring);
    }
    
    public override void close() {
        cancellable.cancel();
        
        base.close();
    }
    
    public override void discovery_started() {
        discovered = new Gee.HashSet<LibraryPhoto>();
        
        base.discovery_started();
    }
    
    public override void file_discovered(File file, FileInfo info) {
        // convert file to photo (if possible) and store in discovered list
        LibraryPhotoSourceCollection.State state;
        LibraryPhoto? photo = LibraryPhoto.global.get_state_by_file(file, out state);
        if (photo != null) {
            switch (state) {
                case LibraryPhotoSourceCollection.State.ONLINE:
                case LibraryPhotoSourceCollection.State.OFFLINE:
                    discovered.add(photo);
                break;
                
                case LibraryPhotoSourceCollection.State.TRASH:
                case LibraryPhotoSourceCollection.State.EDITABLE:
                default:
                    // ignored ... trash always stays in trash, offline or not, and editables are
                    // simply attached to online/offline photos
                break;
            }
        }
        
        base.file_discovered(file, info);
    }
    
    public override void discovery_completed() {
        Marker to_offline = LibraryPhoto.global.start_marking();
        Marker to_online = LibraryPhoto.global.start_marking();
        
        // go through all discovered online photos and see if they're online
        foreach (LibraryPhoto photo in discovered) {
            // for now, only interested in marking files online/offline depending on whether or
            // not they exist ... do NOT process their state or determine if they've changed or
            // renamed
            FileInfo? master_info = get_file_info(photo.get_master_file());
            if (master_info != null && photo.is_offline()) {
                to_online.mark(photo);
            } else if (master_info == null && !photo.is_offline()) {
                // this indicates the file was discovered and then deleted before discovery ended
                // (still counts as offline)
                to_offline.mark(photo);
            }
        }
        
        // go through all known photos and mark offline if not in discovered list
        foreach (DataObject object in LibraryPhoto.global.get_all()) {
            LibraryPhoto photo = (LibraryPhoto) object;
            
            // only deal with photos under this monitor; external photos get a simpler verification
            if (!is_in_root(photo.get_master_file())) {
                launch_verify_external_photo(photo);
                
                continue;
            }
            
            // Don't mark online if in discovered, the prior loop works through those issues
            if (!discovered.contains(photo))
                to_offline.mark(photo);
        }
        
        LibraryPhoto.global.mark_online_offline(to_online, to_offline);
        
        // go through all the offline photos and see if they're online now
        foreach (LibraryPhoto photo in LibraryPhoto.global.get_offline())
            launch_verify_external_photo(photo);
        
        discovered = null;
        
        mdbg("all checksums completed");
        
        // only report discovery completed here, which keeps DirectoryMonitor from initiating
        // another one
        base.discovery_completed();
    }
    
    private void launch_verify_external_photo(LibraryPhoto photo) {
        if (external_mark_online == null)
            external_mark_online = new Gee.ArrayList<LibraryPhoto>();
        
        if (external_mark_offline == null)
            external_mark_offline = new Gee.ArrayList<LibraryPhoto>();
        
        verify_external_outstanding++;
        verify_external_photo.begin(photo, verify_external_complete);
    }
    
    private async void verify_external_photo(LibraryPhoto photo) {
        File master = photo.get_master_file();
        try {
            // interested in nothing more than if the file exists
            FileInfo? info = yield master.query_info_async(FILE_ATTRIBUTE_ACCESS_CAN_READ,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, DEFAULT_PRIORITY, cancellable);
            if (info != null && photo.is_offline())
                external_mark_online.add(photo);
            else if (info == null && !photo.is_offline())
                external_mark_offline.add(photo);
        } catch (Error err) {
            if (!photo.is_offline())
                external_mark_offline.add(photo);
        }
    }
    
    private void verify_external_complete() {
        assert(verify_external_outstanding > 0);
        if (--verify_external_outstanding > 0)
            return;
        
        LibraryPhoto.global.freeze_notifications();
        
        int count = external_mark_online.size;
        for (int ctr = 0; ctr < count; ctr++)
            external_mark_online[ctr].mark_online();
        
        count = external_mark_offline.size;
        for (int ctr = 0; ctr < count; ctr++)
            external_mark_offline[ctr].mark_offline();
        
        LibraryPhoto.global.thaw_notifications();
        
        external_mark_online = null;
        external_mark_offline = null;
    }
}

