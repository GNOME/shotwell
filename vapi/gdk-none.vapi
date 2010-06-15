/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/* GDK_NONE (the null value for GdkAtom) is not bound in gdk-2.0.vapi.
 * This is a temporarry fix until the following ticket is closed.
 * https://bugzilla.gnome.org/show_bug.cgi?id=621318
 */

namespace Gdk {
    [CCode (cname="GDK_NONE")]
    public Gdk.Atom NONE;
}