/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if ENABLE_TESTS

public class SortedListTests : Valadate.Fixture, Object {
    
    public int64 int_comparator(void *a, void *b) {
        int a_prime = (int) a;
        int b_prime = (int) b;
        
        if (a_prime > b_prime) return 1;
        if (a_prime < b_prime) return -1;
        return 0;
    }    
    
    public void test_add() {
        var sl = new SortedList<int>();
        sl.add<int>(1);
        sl.add<int>(2);
        sl.add<int>(3);
        
        assert(sl.get_count() == 3);
    }

    public void test_remove() {
        var sl = new SortedList<int>();
        sl.add<int>(1);
        sl.add<int>(2);
        sl.add<int>(3);
        
        sl.remove<int>(3);
        
        assert(sl.get_count() == 2);
    }

    public void test_remove_nonexistant() {
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

    public void test_contains() {
        Rand r = new Rand();
        var sl = new SortedList<int>();
        
        // set up list of 1000 elements, and place 'sentinel' 
        // value near the middle, but away from it.
        for(int i = 0; i < 496; i++) {
            sl.add<int>((int)r.next_int());
        }
        sl.add(-1);
        
        for(int i = 0; i < 505; i++) {
            sl.add<int>((int)r.next_int());
        }
    
        assert(sl.contains<int>(-1));
    }
    
    public void test_is_empty() {
        var sl = new SortedList<int>();
        
        for(int i = 0; i < 10; i++) {
            sl.add<int>(3);
        }
        
        assert(!sl.is_empty);

        for(int i = 0; i < 10; i++) {
            sl.remove<int>(3);
        }

        assert(sl.is_empty);
    }    
    
    public void test_remove_all() {
        var sl = new SortedList<int>(int_comparator);
        var col = new Gee.ArrayList<int>();
        
        col.add(3);
        
        for(int i = 0; i < 1000; i++) {
            sl.add<int>(3);
        }        
        
        assert(!sl.is_empty);
        
        for(int i = 0; i < 1000; i++) {
            sl.remove_all(col);
        }
        
        assert(sl.is_empty);
    }
    
    public void test_resort() {
        Rand r = new Rand();
        var sl = new SortedList<int>(int_comparator);
        
        for(int i = 0; i < 1000; i++) {
            sl.add<int>((int)r.next_int());
        }

        sl.resort(int_comparator);
        
        for(int i = 1; i < sl.get_count(); i++) {
            int a = sl.get_at(i - 1);
            int b = sl.get_at(i);
            assert(int_comparator((void *)a, (void *)b) < 0);
        }
    }
}

#endif
