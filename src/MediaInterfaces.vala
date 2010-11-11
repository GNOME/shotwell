/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

//
// Going forward, Shotwell will use MediaInterfaces, which allow for various operations and features
// to be added only to the MediaSources that support them (or make sense for).  For example, adding
// a library-mode photo or video to an Event makes perfect sense, but does not make sense for a
// direct-mode photo.  All three are MediaSources, and to make DirectPhoto descend from another
// base class is only inviting chaos and a tremendous amount of replicated code.
//
// A key point to make of all MediaInterfaces is that they require MediaSource as a base class.
// Thus, any code dealing with one of these interfaces knows they are also dealing with a
// MediaSource.
//
// TODO: Make Eventable and Taggable interfaces, which are the only types Event and Tag will deal
// with (rather than MediaSources).
//
// TODO: Make Trashable and Offlineable interfaces, which are much like Flaggable.
//
// TODO: ContainerSources may also have specific needs in the future; an interface-based system
// may make sense as well when that need arises.
//

//
// Flaggable
//

// Flaggable media can be marked for later use in batch operations.
//
// The mark_flagged() and mark_unflagged() methods should fire "metadata:flags" and "metadata:flagged"
// alterations if the flag has changed.
public interface Flaggable : MediaSource {
    public abstract bool is_flagged();
    
    public abstract void mark_flagged();
    
    public abstract void mark_unflagged();
}

