/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 *
 * Auto-generated file.  Do not modify!
 */

namespace _UNIT_NAME_ {

private int _unit_init_count = 0;

public void init_entry() throws Error {
    if (_unit_init_count++ != 0)
        return;
    
    _UNIT_USES_INITS_
    
    _UNIT_NAME_.init();
}

public void terminate_entry() {
    if (_unit_init_count == 0 || --_unit_init_count != 0)
        return;
    
    _UNIT_NAME_.terminate();
    
    _UNIT_USES_TERMINATORS_
}

}

