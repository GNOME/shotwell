/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if ENABLE_TESTS

public class SortedListTests : Valadate.Fixture, Object {
    public void test_add_items_and_check_theyre_added() {
        var sl = new SortedList<int>();
        sl.add<int>(1);
        sl.add<int>(2);
        sl.add<int>(3);
        
        assert(sl.get_count() == 3);
    }

    public void test_remove_items_and_check_theyre_removed() {
        var sl = new SortedList<int>();
        sl.add<int>(1);
        sl.add<int>(2);
        sl.add<int>(3);
        
        sl.remove<int>(3);
        
        assert(sl.get_count() == 2);
    }

    public void test_remove_nonexistant_item() {
        var sl = new SortedList<int>();
        sl.add<int>(1);
        sl.add<int>(2);
        sl.add<int>(3);
        
        sl.remove<int>(4);
        
        assert(sl.get_count() == 3);
    }    
    
    public void test_copy() {
        Rand r = new Rand();
        var sl = new SortedList<int>();
        var sl_copy = new SortedList<int>();
        
        for(int i = 0; i < 1000; i++) {
            sl.add<int>((int)r.next_int());
        }
    
        sl_copy = sl.copy();

        for(int i = 0; i < 1000; i++) {
            assert(sl.get_at(i) == sl_copy.get_at(i));
        }
    }
        
}

#endif
