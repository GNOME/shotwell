/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public delegate int64 Comparator(void *a, void *b);

public class SortedList<G> : Object, Gee.Traversable<G>, Gee.Iterable<G>, Gee.Collection<G> {
    private Gee.ArrayList<G> list;
    private unowned Comparator? cmp;
    
    public SortedList(Comparator? cmp = null) {
        this.list = new Gee.ArrayList<G>();
        this.cmp = cmp;
    }
    
    public Type element_type {
        get { return typeof(G); } 
    }
    
    public bool read_only {
        get { return list.read_only; }
    }
    
    public Gee.Iterator<G?> iterator() {
        return list.iterator();
    }
    
    public bool foreach(Gee.ForallFunc<G> f) {
        return list.foreach(f);
    }
    
    public bool add(G? item) {
        if (cmp == null)
            list.add(item);
        else
            list.insert(get_sorted_insert_pos(item), item);
        
#if VERIFY_SORTED_LIST
        assert(is_sorted());
#endif
        
        return true;
    }
    
    public bool add_all(Gee.Collection<G> collection) {
        if (collection.size == 0)
            return false;
        
        Gee.List<G> as_list = collection as Gee.List<G>;
        if (as_list != null)
            return add_list(as_list);
        
        if (cmp == null)
            return list.add_all(collection);
        
        bool changed = false;
        if (collection.size == 1) {
            Gee.Iterator<G> iter = collection.iterator();
            iter.next();
            G item = iter.get();
            
            list.insert(get_sorted_insert_pos(item), item);
            changed = true;
        } else {
            Gee.List<G> items = new Gee.ArrayList<G>();
            items.add_all(collection);
            
            changed = merge_sort(items);
        }
        
#if VERIFY_SORTED_LIST
        assert(is_sorted());
#endif
        return changed;
    }
    
    public bool add_list(Gee.List<G> items) {
        bool added = false;
        if (items.size == 0) {
            // do nothing, return false
        } else if (cmp != null) {
            // don't use a full merge sort if the number of items is one ... a binary
            // insertion sort with the insert is quicker
            if (items.size == 1) {
                list.insert(get_sorted_insert_pos(items.get(0)), items.get(0));
                added = true;
            } else {
                added = merge_sort(items);
            }
        } else {
            added = list.add_all(items);
        }
        
#if VERIFY_SORTED_LIST
        assert(is_sorted());
#endif
        
        return added;
    }
    
    public void clear() {
        list.clear();
    }
    
    public bool contains(G? item) {
        return list.contains(item);
    }
    
    public bool contains_all(Gee.Collection<G> collection) {
        return list.contains_all(collection);
    }
    
    public bool is_empty {
        get {
            return list.is_empty;
        }
    }
    
    public bool remove(G? item) {
        return list.remove(item);
    }
    
    public bool remove_all(Gee.Collection<G> collection) {
        return list.remove_all(collection);
    }
    
    public bool retain_all(Gee.Collection<G> collection) {
        return list.retain_all(collection);
    }
    
    public int size {
        get { return list.size; }
    }
    
    public inline int get_count() {
        return list.size;
    }
    
    public G? get_at(int index) {
        return list.get(index);
    }
    
    private int binary_search(G search, EqualFunc? equal_func) {
        assert(cmp != null);
        
        int min = 0;
        int max = list.size;
        for (;;) {
            int mid = min + ((max - min) / 2);
            G item = list.get(mid);
            
            if (equal_func != null && equal_func(item, search))
                return mid;
            
            int64 compare = cmp(item, search);
            if (compare == 0)
                return mid;
            else if (compare > 0)
                max =  mid - 1;
            else
                min = mid + 1;
            
            if (min > max)
                break;
        }
        
        return -1;
    }
    
    // index_of uses the Comparator to find the item being searched for.  Because SortedList allows
    // for items identified as equal by the Comparator to co-exist in the list, this method will
    // return the first item found where its compare() method returns zero.  Use locate() if a
    // specific EqualFunc is required for searching.
    //
    // Also, index_of() cannot be reliably used to find an item if it has been altered in such a
    // way that it is no longer sorted properly.  Use locate() for that.
    public int index_of(G search) {
        return cmp != null ? binary_search(search, null) : locate(search, false);
    }
    
    // See notes at index_of for the difference between this method and it.
    public int locate(G search, bool altered, EqualFunc equal_func = direct_equal) {
        if (cmp == null || altered) {
            int count = list.size;
            for (int ctr = 0; ctr < count; ctr++) {
                if (equal_func(list.get(ctr), search))
                    return ctr;
            }
            
            return -1;
        }
        
        return binary_search(search, equal_func);
    }
    
    public Gee.Collection<G> read_only_view {
        owned get {
            return list.read_only_view;
        }
    }
    
    public Gee.List<G> read_only_view_as_list {
        owned get {
            return list.read_only_view;
        }
    }
    
    public G? remove_at(int index) {
        return list.remove_at(index);
    }
    
    public G[] to_array() {
        return list.to_array();
    }
    
    public void resort(Comparator new_cmp) {
        cmp = new_cmp;
        
        merge_sort();
        
#if VERIFY_SORTED_LIST
        assert(is_sorted());
#endif
    }
    
    // Returns true if item has moved.
    public bool resort_item(G item) {
        int index = locate(item, true);
        assert(index >= 0);
        
        int new_index = get_sorted_insert_pos(item);
        
        if (index == new_index)
            return false;
        
        // insert in such a way to avoid index shift (performing the rightmost
        // operation before the leftmost)
        if (new_index > index) {
            list.insert(new_index, item);
            G removed_item = list.remove_at(index);
            assert(item == removed_item);
        } else {
            G removed_item = list.remove_at(index);
            assert(item == removed_item);
            list.insert(new_index, item);
        }
        
#if VERIFY_SORTED_LIST
        assert(is_sorted());
#endif
        
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
            
            int64 result = cmp(item, cmp_item);
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
    
#if VERIFY_SORTED_LIST
    private bool is_sorted() {
        if (cmp == null)
            return true;
        
        int length = list.size;
        for (int ctr = 1; ctr < length; ctr++) {
            if (cmp(list.get(ctr - 1), list.get(ctr)) >= 0) {
                critical("Out of order: %d and %d", ctr - 1, ctr);
                
                return false;
            }
        }
        
        return true;
    }
#endif
    
    private bool merge_sort(Gee.List<G>? add = null) {
        assert(cmp != null);
        
        int list_count = list.size;
        int add_count = (add != null) ? add.size : 0;
        
        int count = list_count + add_count;
        if (count == 0)
            return false;
        
        // because list access is slow in large-scale sorts, flatten list (with additions) to
        // an array, merge sort that, and then place them back in the internal ArrayList.
        G[] array = new G[count];
        int offset = 0;
        
        while (offset < list_count) {
            array[offset] = list.get(offset);
            offset++;
        }
        
        if (add != null) {
            int add_ctr = 0;
            while (offset < count) {
                array[offset] = add.get(add_ctr++);
                offset++;
            }
        }
        
        assert(offset == count);
        
        _merge_sort(array, new G[count], 0, count - 1);
        
        offset = 0;
        while (offset < list_count) {
            list.set(offset, array[offset]);
            offset++;
        }
        
        while (offset < count) {
            list.insert(offset, array[offset]);
            offset++;
        }
        
        return true;
    }
    
    private void _merge_sort(G[] array, G[] scratch, int start_index, int end_index) {
        assert(start_index <= end_index);
        
        int count = end_index - start_index + 1;
        if (count <= 1)
            return;
        
        int middle_index = start_index + (count / 2);
        
        _merge_sort(array, scratch, start_index, middle_index - 1);
        _merge_sort(array, scratch, middle_index, end_index);
        
        if (cmp(array[middle_index - 1], array[middle_index]) > 0)
            merge(array, scratch, start_index, middle_index, end_index);
    }
    
    private void merge(G[] array, G[] scratch, int start_index, int middle_index, int end_index) {
        assert(start_index < end_index);
        
        int count = end_index - start_index + 1;
        int left_start = start_index;
        int left_end = middle_index - 1;
        int right_start = middle_index;
        int right_end = end_index;
        
        assert(scratch.length >= count);
        int scratch_index = 0;
        
        while (left_start <= left_end && right_start <= right_end) {
            G left = array[left_start];
            G right = array[right_start];
            
            if (cmp(left, right) <= 0) {
                scratch[scratch_index++] = left;
                left_start++;
            } else {
                scratch[scratch_index++] = right;
                right_start++;
            }
        }
        
        while (left_start <= left_end)
            scratch[scratch_index++] = array[left_start++];
        
        while (right_start <= right_end)
            scratch[scratch_index++] = array[right_start++];
        
        assert(scratch_index == count);
        
        scratch_index = 0;
        for (int list_index = start_index; list_index <= end_index; list_index++)
            array[list_index] = scratch[scratch_index++];
    }
}

