/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Library {

public void init() throws Error {
    Library.TrashSidebarEntry.init();
    Photo.develop_raw_photos_to_files = true;
}

public void terminate() {
    Library.TrashSidebarEntry.terminate();
}

}

namespace Library {
    private static bool _entry_initialized = false;

    public void init_entry() throws Error {
        if (_entry_initialized)
            return;
        _entry_initialized = true;

        Unit.init_entry(); Util.init_entry(); Threads.init_entry(); Db.init_entry(); Plugins.init_entry(); Slideshow.init_entry();
        Photos.init_entry(); Publishing.init_entry(); Core.init_entry(); Sidebar.init_entry(); Events.init_entry(); Tags.init_entry();
        Camera.init_entry(); Searches.init_entry();  Folders.init_entry();

        Library.init();
    }

    public void terminate_entry() {


        Library.terminate();

        Unit.terminate_entry(); Util.terminate_entry(); Threads.terminate_entry(); Db.terminate_entry(); Plugins.terminate_entry();
        Slideshow.terminate_entry(); Photos.terminate_entry(); Publishing.terminate_entry(); Core.terminate_entry(); Sidebar.terminate_entry();
        Events.terminate_entry(); Tags.terminate_entry(); Camera.terminate_entry(); Searches.terminate_entry();
        Folders.terminate_entry();
    }
}

namespace Library {

public void app_init() throws Error {
    Library.init_entry();
}

public void app_terminate() {
    Library.terminate_entry();
}

}

