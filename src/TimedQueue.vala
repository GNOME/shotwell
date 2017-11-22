/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// TimedQueue is a specialized collection class.  It holds items in order, but rather than being
// manually dequeued, they are dequeued automatically after a specified amount of time has elapsed
// for that item.  As of today, it's possible the item will be dequeued a bit later than asked
// for, but it will never be early.  Future implementations might tighten up the lateness.
//
// The original design was to use a signal to notify when an item has been dequeued, but Vala has
// a bug with passing an unnamed type as a signal parameter:
// https://bugzilla.gnome.org/show_bug.cgi?id=628639
//
// The rate the items come off the queue can be spaced out.  Note that this can cause items to back
// up.  As of today, TimedQueue makes no effort to combat this.

public delegate void DequeuedCallback<G>(G item);

public class TimedQueue<G> {
    private class Element<G> {
        public G item;
        public ulong ready;
        
        public Element(G item, ulong ready) {
            this.item = item;
            this.ready = ready;
        }
        
        public static int64 comparator(void *a, void *b) {
            return (int64) ((Element *) a)->ready - (int64) ((Element *) b)->ready;
        }
    }
    
    private uint hold_msec;
    private unowned DequeuedCallback<G> callback;
    private Gee.EqualDataFunc<G> equal_func;
    private int priority;
    private uint timer_id = 0;
    private SortedList<Element<G>> queue;
    private uint dequeue_spacing_msec = 0;
    private ulong last_dequeue = 0;
    private bool paused_state = false;
    
    public virtual signal void paused(bool is_paused) {
    }
    
    // Initial design was to have a signal that passed the dequeued G, but bug in valac meant
    // finding a workaround, namely using a delegate:
    // https://bugzilla.gnome.org/show_bug.cgi?id=628639
    public TimedQueue(uint hold_msec, DequeuedCallback<G> callback,
        owned Gee.EqualDataFunc? equal_func = null, int priority = Priority.DEFAULT) {
        this.hold_msec = hold_msec;
        this.callback = callback;
        
        if (equal_func != null)
            this.equal_func = (owned) equal_func;
        else
            this.equal_func = (Gee.EqualDataFunc<G>) (Gee.Functions.get_equal_func_for(typeof(G)));
            
        this.priority = priority;
        
        queue = new SortedList<Element<G>>(Element.comparator);
        
        timer_id = Timeout.add(get_heartbeat_timeout(), on_heartbeat, priority);
    }
    
    ~TimedQueue() {
        if (timer_id != 0)
            Source.remove(timer_id);
    }
    
    public uint get_dequeue_spacing_msec() {
        return dequeue_spacing_msec;
    }
    
    public void set_dequeue_spacing_msec(uint msec) {
        if (msec == dequeue_spacing_msec)
            return;
        
        if (timer_id != 0)
            Source.remove(timer_id);
        
        dequeue_spacing_msec = msec;
        
        timer_id = Timeout.add(get_heartbeat_timeout(), on_heartbeat, priority);
    }
    
    private uint get_heartbeat_timeout() {
        return ((dequeue_spacing_msec == 0)
            ? (hold_msec / 10) 
            : (dequeue_spacing_msec / 2)).clamp(10, uint.MAX);
    }
    
    protected virtual void notify_dequeued(G item) {
        callback(item);
    }
    
    public bool is_paused() {
        return paused_state;
    }
    
    public void pause() {
        if (paused_state)
            return;
        
        paused_state = true;
        
        paused(true);
    }
    
    public void unpause() {
        if (!paused_state)
            return;
        
        paused_state = false;
        
        paused(false);
    }
    
    public virtual void clear() {
        queue.clear();
    }
    
    public virtual bool contains(G item) {
        foreach (Element<G> e in queue) {
            if (equal_func(item, e.item))
                return true;
        }
        
        return false;
    }
    
    public virtual bool enqueue(G item) {
        return queue.add(new Element<G>(item, calc_ready_time()));
    }
    
    public virtual bool enqueue_many(Gee.Collection<G> items) {
        ulong ready_time = calc_ready_time();
        
        Gee.ArrayList<Element<G>> elements = new Gee.ArrayList<Element<G>>();
        foreach (G item in items)
            elements.add(new Element<G>(item, ready_time));
        
        return queue.add_list(elements);
    }
    
    public virtual bool remove_first(G item) {
        Gee.Iterator<Element<G>> iter = queue.iterator();
        while (iter.next()) {
            Element<G> e = iter.get();
            if (equal_func(item, e.item)) {
                iter.remove();
                
                return true;
            }
        }
        
        return false;
    }
    
    public virtual int size {
        get {
            return queue.size;
        }
    }
    
    private ulong calc_ready_time() {
        return now_ms() + (ulong) hold_msec;
    }
    
    private bool on_heartbeat() {
        if (paused_state)
            return true;
        
        ulong now = 0;
        
        for (;;) {
            if (queue.size == 0)
                break;
            
            Element<G>? head = queue.get_at(0);
            assert(head != null);
            
            if (now == 0)
                now = now_ms();
            
            if (head.ready > now)
                break;
            
            // if a space of time is required between dequeues, check now
            if ((dequeue_spacing_msec != 0) && ((now - last_dequeue) < dequeue_spacing_msec))
                break;
            
            Element<G>? h = queue.remove_at(0);
            assert(head == h);
            
            notify_dequeued(head.item);
            last_dequeue = now;
            
            // if a dequeue spacing is in place, it's a lock that only one item is dequeued per
            // heartbeat
            if (dequeue_spacing_msec != 0)
                break;
        }
        
        return true;
    }
}

// HashTimedQueue uses a HashMap for quick lookups of elements via contains().

public class HashTimedQueue<G> : TimedQueue<G> {
    private Gee.HashMap<G, int> item_count;
    
    public HashTimedQueue(uint hold_msec, DequeuedCallback<G> callback,
        owned Gee.HashDataFunc<G>? hash_func = null, owned Gee.EqualDataFunc<G>? equal_func = null,
        int priority = Priority.DEFAULT) {
        base (hold_msec, callback, (owned) equal_func, priority);
        
        item_count = new Gee.HashMap<G, int>((owned) hash_func, (owned) equal_func);
    }
    
    protected override void notify_dequeued(G item) {
        removed(item);
        
        base.notify_dequeued(item);
    }
    
    public override void clear() {
        item_count.clear();
        
        base.clear();
    }
    
    public override bool contains(G item) {
        return item_count.has_key(item);
    }
    
    public override bool enqueue(G item) {
        if (!base.enqueue(item))
            return false;
        
        item_count.set(item, item_count.has_key(item) ? item_count.get(item) + 1 : 1);
        
        return true;
    }
    
    public override bool enqueue_many(Gee.Collection<G> items) {
        if (!base.enqueue_many(items))
            return false;
        
        foreach (G item in items)
            item_count.set(item, item_count.has_key(item) ? item_count.get(item) + 1 : 1);
        
        return true;
    }
    
    public override bool remove_first(G item) {
        if (!base.remove_first(item))
            return false;
        
        removed(item);
        
        return true;
    }
    
    private void removed(G item) {
        // item in question is either already removed
        // or was never added, safe to do nothing here
        if (!item_count.has_key(item))
            return;
        
        int count = item_count.get(item);
        assert(count > 0);
        
        if (--count == 0)
            item_count.unset(item);
        else
            item_count.set(item, count);
    }
}

