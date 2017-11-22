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

