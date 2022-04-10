/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Camera {

public void init() throws Error {
    Camera.Branch.init();
}

public void terminate() {
    Camera.Branch.terminate();
}

}

