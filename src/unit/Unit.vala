/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Unit {
    [CCode (has_target = false)]
    public delegate void Initializer() throws Error;
    
    [CCode (has_target = false)]
    public delegate void Terminator();
    
    public void init() throws Error {
    }
    
    public void terminate() {
    }
}

