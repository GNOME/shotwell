/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public abstract class Comparator<G> {
    public abstract int64 compare(G a, G b);
}

public class SortedList<G> : Object, Gee.Iterable<G> {
    private Gee.List<G> list;
    private Comparator<G> cmp;
    
    public SortedList(Comparator<G>? cmp = null) {
        this.list = new Gee.ArrayList<G>();
        this.cmp = cmp;
    }
    
    // for libgee <= 0.1.6
    public Type get_element_type() {
        return typeof(G);
    }
    
    // for libgee >= 0.3.0
    public Type element_type {
        get { return typeof(G); } 
    }
    
    public Gee.Iterator<G?> iterator() {
        return list.iterator();
    }
    
    public bool add(G? item) {
        if (cmp == null)
            list.add(item);
        else
            list.insert(get_sorted_insert_pos(item), item);
        
        return true;
    }
    
    public void clear() {
        list.clear();
    }
    
    public bool contains(G? item) {
        return list.contains(item);
    }
    
    public bool remove(G? item) {
        return list.remove(item);
    }
    
    public int size {
        get { return list.size; }
    }

    public new G? get(int index) {
        return list.get(index);
    }
    
    public new void set(int index, G item) {
        list.set(index, item);
    }

    public int index_of(G item) {
        return list.index_of(item);
    }
    
    public void insert(int index, G item) {
        list.insert(index, item);
    }
    
    public void remove_at(int index) {
        list.remove_at(index);
    }
    
    public void resort(Comparator<G> new_cmp) {
        cmp = new_cmp;
        
        Gee.List<G> old_list = list;
        list = new Gee.ArrayList<G>();
        
        foreach (G item in old_list)
            list.insert(get_sorted_insert_pos(item), item);
    }
    
    private int get_sorted_insert_pos(G? item) {
        int low = 0;
        int high = list.size;
        for (;;) {
            if (low == high)
                return low;
                
            int mid = low + ((high - low) / 2);

            int64 result = cmp.compare(item, list.get(mid));
            if (result < 0)
                high = mid;
            else if (result > 0)
                low = mid + 1;
            else
                return mid;
        }
        
    }
}

