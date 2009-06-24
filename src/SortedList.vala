/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public abstract class Comparator<G> {
    public abstract int64 compare(G a, G b);
}

public class SortedList<G> : Gee.CollectionObject, Gee.Iterable<G>, Gee.Collection<G>, Gee.List<G> {
    private Gee.List<G> list;
    private Comparator<G> cmp;
    
    public SortedList(Gee.List<G> list, Comparator<G>? cmp = null) {
        this.list = list;
        this.cmp = cmp;
    }
    
    public Type get_element_type() {
        return list.get_element_type();
    }
    
    public Gee.Iterator<G?> iterator() {
        return list.iterator();
    }
    
    public bool add(G? item) {
        if (cmp == null) {
            list.insert(list.size, item);
            
            return true;
        }

        int ctr = 0;
        bool insert = false;
        foreach (G added in list) {
            if (cmp.compare(item, added) < 0) {
                // smaller, insert before this element
                insert = true;
                
                break;
            }
            
            ctr++;
        }

        if (insert) {
            list.insert(ctr, item);
            
            return true;
        }

        // went off the end of the list, so add at end
        list.insert(list.size, item);
        
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
    
    public G? get(int index) {
        return list.get(index);
    }
    
    public void set(int index, G item) {
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
}


