/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

// Class for aggregating one-off "upgrade" tasks that occur at startup, such as
// moving or deleting files. This occurs after the UI is shown, so it's not appropriate
// for database updates and such.
public class Upgrades {
    private static Upgrades? instance = null;
    private uint64 total_steps = 0;
    private Gee.LinkedList<UpgradeTask> task_list = new Gee.LinkedList<UpgradeTask>();
    
    private Upgrades() {
        // Add all upgrade tasks here.
        add(new MimicsRemovalTask());
        
        if (Application.get_instance().get_raw_thumbs_fix_required())
            add(new FixupRawThumbnailsTask());
    }
    
    // Call this to initialize the subsystem.
    public static void init() {
        assert(instance == null);
        instance = new Upgrades();
    }

    public static Upgrades get_instance() {
        return instance;
    }
    
    // Gets the total number of steps for the progress monitor.
    public uint64 get_step_count() {
        return total_steps;
    }
    
    // Performs all upgrade tasks.
    public void execute(ProgressMonitor? monitor = null) {
        foreach (UpgradeTask task in task_list)
            task.execute(monitor);
    }
    
    private void add(UpgradeTask task) {
        total_steps += task.get_step_count();
        task_list.add(task);
    }
}

// Interface for upgrades that happen on startup.
// When creating a new upgrade task, you MUST add it to the constructor
// supplied in Upgrades (see above.)
private interface UpgradeTask : Object{
    // Returns the number of steps involved in the upgrade.
    public abstract uint64 get_step_count();
    
    // Performs the upgrade.  Note that when using the progress
    // monitor, the total number of steps must be equal to the
    // step count above.
    public abstract void execute(ProgressMonitor? monitor = null);
}

// Deletes the mimics folder, if it still exists.
// Note: for the step count to be consistent, files cannot be written
// to the mimcs folder for the duration of this task.
private class MimicsRemovalTask : Object, UpgradeTask {
    // Mimics folder (to be deleted, if present)
    private File mimic_dir = AppDirs.get_data_dir().get_child("mimics");
    private uint64 num_mimics = 0;
    
    public uint64 get_step_count() {
        try {
            num_mimics = count_files_in_directory(mimic_dir);
        } catch (Error e) {
            debug("Error on deleting mimics: %s", e.message);
        }
        return num_mimics;
    }
    
    public void execute(ProgressMonitor? monitor = null) {
        try {
            delete_all_files(mimic_dir, null, monitor, num_mimics, null);
            mimic_dir.delete();
        } catch (Error e) {
            debug("Could not delete mimics: %s", e.message);
        }
    }
}

// Deletes 'stale' thumbnails from camera raw files whose default developer was
// CAMERA and who may have been incorrectly generated from the embedded preview by
// previous versions of the application that had bug 4692.
private class FixupRawThumbnailsTask : Object, UpgradeTask {
    public uint64 get_step_count() {
        int num_raw_files = 0;
        
        foreach (PhotoRow phr in PhotoTable.get_instance().get_all()) {
            if (phr.master.file_format == PhotoFileFormat.RAW)
                num_raw_files++;
        }
        return num_raw_files;
    }
    
    public void execute(ProgressMonitor? monitor = null) {
        debug("Executing thumbnail deletion and fixup");
        
        foreach (PhotoRow phr in PhotoTable.get_instance().get_all()) {
            if ((phr.master.file_format == PhotoFileFormat.RAW) &&
                (phr.developer == RawDeveloper.CAMERA)) {
                ThumbnailCache.remove(LibraryPhoto.global.fetch(phr.photo_id));
            }
        }
    }
}

