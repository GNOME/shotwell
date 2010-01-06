/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public abstract class Comparator<G> {
    public abstract int64 compare(G a, G b);
}

// Common comparators
public class FileComparator : Comparator<File> {
    public override int64 compare(File a, File b) {
        return strcmp(a.get_path(), b.get_path());
    }
}

public class SortedList<G> : Object, Gee.Iterable<G> {
    private Gee.List<G> list;
    private Comparator<G> cmp;
    
    public SortedList(Comparator<G>? cmp = null) {
        this.list = new Gee.ArrayList<G>();
        this.cmp = cmp;
    }
    
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

    public G? get_at(int index) {
        return list.get(index);
    }
    
    // index_of uses the Comparator to find the item being searched for.  Because SortedList allows
    // for items identified as equal by the Comparator to co-exist in the list, this method will
    // return the first item found where its compare() method returns zero.  Use locate() if a
    // specific EqualFunc is required for searching.
    public int index_of(G search) {
        // because the internal ArrayList has no equal_func (and can't easily provide one without
        // asking the user for a separate static comparator), search manually here
        int index = 0;
        foreach (G item in list) {
            // use direct_equal if no comparator installed
            bool found = (cmp != null) ? (cmp.compare(item, search) == 0) : direct_equal(item, search);
            if (found)
                return index;
            
            index++;
        }
        
        return -1;
    }
    
    // See notes at index_of for the difference between this method and it.
    public int locate(G search, EqualFunc equal_func = direct_equal) {
        int index = 0;
        foreach (G item in list) {
            if (equal_func(item, search))
                return index;
            
            index++;
        }
        
        return -1;
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
    
    // Returns true if item has moved.
    public bool resort_item(G item) {
        int index = locate(item);
        int new_index = get_sorted_insert_pos(item);
        
        if (index == new_index)
            return false;
        
        // insert first, as the indexes shift after the remove
        list.insert(new_index, item);
        list.remove_at(index);
        
        return true;
    }
    
    private int get_sorted_insert_pos(G? item) {
        int low = 0;
        int high = list.size;
        for (;;) {
            if (low == high)
                return low;
            
            int mid = low + ((high - low) / 2);
            
            // watch for the situation where the item is already in the list (can happen with
            // resort_item())
            G cmp_item = list.get(mid);
            if (item == cmp_item) {
                // if at the end of the list, add it there
                if (mid >= list.size - 1)
                    return list.size;
                
                cmp_item = list.get(mid + 1);
            }
            
            int64 result = cmp.compare(item, cmp_item);
            if (result < 0)
                high = mid;
            else if (result > 0)
                low = mid + 1;
            else
                return mid;
        }
    }

    public SortedList<G> copy() {
        SortedList<G> copy = new SortedList<G>(cmp);

        copy.list.add_all(list);

        return copy;
    }
}

