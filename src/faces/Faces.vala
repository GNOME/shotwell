/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

#if ENABLE_FACES

namespace Faces {

public void init() throws Error {
	Faces.SidebarEntry.init();
}

public void terminate() {
	Faces.SidebarEntry.terminate();
}

}

#else

namespace Faces {

public void init() throws Error {
	// do nothing; this method is here only
	// to make the unitizing mechanism happy
}

public void terminate() {
	// do nothing; this method is here only
	// to make the unitizing mechanism happy
}

}

#endif
