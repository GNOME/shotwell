/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

// Semaphores may be used to be notified when a job is completed.  This provides an alternate
// mechanism (essentially, a blocking mechanism) to the system of callbacks that BackgroundJob
// offers.  They can also be used for other job-dependent notification mechanisms.
public abstract class AbstractSemaphore {
    public enum Type {
        SERIAL,
        BROADCAST
    }
    
    protected enum NotifyAction {
        NONE,
        SIGNAL
    }
    
    protected enum WaitAction {
        SLEEP,
        READY
    }
    
    private Type type;
    private Mutex mutex = Mutex();
    private Cond monitor = Cond();
    
    protected AbstractSemaphore(Type type) {
        assert(type == Type.SERIAL || type == Type.BROADCAST);
        
        this.type = type;
    }
    
    private void trigger() {
        if (type == Type.SERIAL)
            monitor.signal();
        else
            monitor.broadcast();
    }
    
    public void notify() {
        mutex.lock();
        
        NotifyAction action = do_notify();
        switch (action) {
            case NotifyAction.NONE:
                // do nothing
            break;
            
            case NotifyAction.SIGNAL:
                trigger();
            break;
            
            default:
                error("Unknown semaphore action: %s", action.to_string());
        }
        
        mutex.unlock();
    }
    
    // This method is called by notify() with the semaphore's mutex locked.
    protected abstract NotifyAction do_notify();
    
    public void wait() {
        mutex.lock();
        
        while (do_wait() == WaitAction.SLEEP)
            monitor.wait(mutex);
        
        mutex.unlock();
    }
    
    // This method is called by wait() with the semaphore's mutex locked.
    protected abstract WaitAction do_wait();
    
    // Returns true if the semaphore is reset, false otherwise.
    public bool reset() {
        mutex.lock();
        bool is_reset = do_reset();
        mutex.unlock();
        
        return is_reset;
    }
    
    // This method is called by reset() with the semaphore's mutex locked.  Returns true if reset,
    // false if not supported.
    protected virtual bool do_reset() {
        return false;
    }
}

public class Semaphore : AbstractSemaphore {
    bool passed = false;
    
    public Semaphore() {
        base (AbstractSemaphore.Type.BROADCAST);
    }
    
    protected override AbstractSemaphore.NotifyAction do_notify() {
        if (passed)
            return NotifyAction.NONE;
        
        passed = true;
        
        return NotifyAction.SIGNAL;
    }
    
    protected override AbstractSemaphore.WaitAction do_wait() {
        return passed ? WaitAction.READY : WaitAction.SLEEP;
    }
}

public class CountdownSemaphore : AbstractSemaphore {
    private int total;
    private int passed = 0;
    
    public CountdownSemaphore(int total) {
        base (AbstractSemaphore.Type.BROADCAST);
        
        this.total = total;
    }
    
    protected override AbstractSemaphore.NotifyAction do_notify() {
        if (passed >= total)
            critical("CountdownSemaphore overrun: %d/%d", passed + 1, total);
        
        return (++passed >= total) ? NotifyAction.SIGNAL : NotifyAction.NONE;
    }
    
    protected override AbstractSemaphore.WaitAction do_wait() {
        return (passed < total) ? WaitAction.SLEEP : WaitAction.READY;
    }
}

public class EventSemaphore : AbstractSemaphore {
    bool fired = false;
    
    public EventSemaphore() {
        base (AbstractSemaphore.Type.BROADCAST);
    }
    
    protected override AbstractSemaphore.NotifyAction do_notify() {
        fired = true;
        
        return NotifyAction.SIGNAL;
    }
    
    protected override AbstractSemaphore.WaitAction do_wait() {
        return fired ? WaitAction.READY : WaitAction.SLEEP;
    }
    
    protected override bool do_reset() {
        fired = false;
        
        return true;
    }
}

