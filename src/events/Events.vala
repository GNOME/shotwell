/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Events {

public void init() throws Error {
    Events.Branch.init();
}

public void terminate() {
    Events.Branch.terminate();
}

}

