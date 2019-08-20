/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

// This callback is executed when an associated BackgroundJob completes.  It is called from within
// the Gtk event loop, *not* the background thread's context.
public delegate void CompletionCallback(BackgroundJob job);

// This callback is executed when an associated BackgroundJob has been cancelled (via its
// Cancellable).  Note that it's *possible* the BackgroundJob performed some or all of its work
// prior to executing this delegate.
public delegate void CancellationCallback(BackgroundJob job);

// This callback is executed by the BackgroundJob when a unit of work is completed, but not the
// entire job.  It is called from within the Gtk event loop, *not* the background thread's
// context.
//
// Note that there does not seem to be any guarantees of order in the Idle queue documentation,
// and this it's possible (and, depending on assigned priorities, likely) that notifications could
// arrive in different orders, and even after the CompletionCallback.  Thus, no guarantee of
// ordering is made here.
//
// NOTE: Would like Value to be nullable, but can't due to this bug:
// https://bugzilla.gnome.org/show_bug.cgi?id=607098
//
// NOTE: There will be a memory leak using NotificationCallbacks due to this bug:
// https://bugzilla.gnome.org/show_bug.cgi?id=571264
//
// NOTE: Because of these two bugs, using an abstract base class rather than Value.  When both are
// fixed (at least the second), may consider going back to Value.

public abstract class NotificationObject {
}

public abstract class InterlockedNotificationObject : NotificationObject {
    private Semaphore semaphore = new Semaphore();
    
    // Only called by BackgroundJob; no need for users or subclasses to use
    public void internal_wait_for_completion() {
        semaphore.wait();
    }
    
    // Only called by BackgroundJob; no need for users or subclasses to use
    public void internal_completed() {
        semaphore.notify();
    }
}

public delegate void NotificationCallback(BackgroundJob job, NotificationObject? user);

// This abstract class represents a unit of work that can be executed within a background thread's
// context.  If specified, the job may be cancellable (which can be checked by execute() and the
// worker thread prior to calling execute()).  The BackgroundJob may also specify a
// CompletionCallback and/or a CancellationCallback to be executed within Gtk's event loop.
// A BackgroundJob may also emit NotificationCallbacks, all of which are also executed within
// Gtk's event loop.
//
// The BackgroundJob may be constructed with a reference to its "owner".  This is not used directly
// by BackgroundJob or Worker, but merely exists to hold a reference to the Object that is receiving
// the various callbacks from BackgroundJob.  Without this, it's possible for the object creating
// BackgroundJobs to be freed before all the callbacks have been received, or even during a callback,
// which is an unstable situation.
public abstract class BackgroundJob {
    public enum JobPriority {
        HIGHEST = 100,
        HIGH = 75,
        NORMAL = 50,
        LOW = 25,
        LOWEST = 0;
        
        // Returns negative if this is higher, zero if equal, positive if this is lower
        public int compare(JobPriority other) {
            return (int) other - (int) this;
        }
        
        public static int compare_func(JobPriority a, JobPriority b) {
            return (int) b - (int) a;
        }
    }
    
    private class NotificationJob {
        public unowned NotificationCallback callback;
        public BackgroundJob background_job;
        public NotificationObject? user;
        
        public NotificationJob(NotificationCallback callback, BackgroundJob background_job,
            NotificationObject? user) {
            this.callback = callback;
            this.background_job = background_job;
            this.user = user;
        }
    }
    
    private static Gee.ArrayList<NotificationJob> notify_queue = new Gee.ArrayList<NotificationJob>();
    
    private Object owner;
    private unowned CompletionCallback callback;
    private Cancellable cancellable;
    private unowned CancellationCallback cancellation;
    private BackgroundJob self = null;
    private AbstractSemaphore semaphore = null;
    
    // The thinking here is that there is exactly one CompletionCallback per job, and the caller
    // probably wants to know that to set off UI and other events in response.  There are several
    // (possibly hundreds or thousands) or notifications, and thus should arrive in a more
    // controlled way (to avoid locking up the UI, for example).  This has ramifications about
    // the order in which completion and notifications arrive (see above note).
    private int completion_priority = Priority.HIGH;
    private int notification_priority = Priority.DEFAULT_IDLE;
    
    protected BackgroundJob(Object? owner = null, CompletionCallback? callback = null,
        Cancellable? cancellable = null, CancellationCallback? cancellation = null,
        AbstractSemaphore? completion_semaphore = null) {
        this.owner = owner;
        this.callback = callback;
        this.cancellable = cancellable;
        this.cancellation = cancellation;
        this.semaphore = completion_semaphore;
    }
    
    public abstract void execute();
    
    public virtual JobPriority get_priority() {
        return JobPriority.NORMAL;
    }
    
    // For the CompareFunc delegate, according to JobPriority.
    public static int priority_compare_func(BackgroundJob a, BackgroundJob b) {
        return a.get_priority().compare(b.get_priority());
    }
    
    // For the Comparator delegate, according to JobPriority.
    public static int64 priority_comparator(void *a, void *b) {
        return priority_compare_func((BackgroundJob) a, (BackgroundJob) b);
    }
    
    // This method is not thread-safe.  Best to set priority before the job is enqueued.
    public void set_completion_priority(int priority) {
        completion_priority = priority;
    }
    
    // This method is not thread-safe.  Best to set priority before the job is enqueued.
    public void set_notification_priority(int priority) {
        notification_priority = priority;
    }
    
    // This method is thread-safe, but only waits if a completion semaphore has been set, otherwise
    // exits immediately.  Note that blocking for a semaphore does NOT spin the event loop, so a
    // thread relying on it to continue should not use this.
    public void wait_for_completion() {
        if (semaphore != null)
            semaphore.wait();
    }
    
    public Cancellable? get_cancellable() {
        return cancellable;
    }
    
    public bool is_cancelled() {
        return (cancellable != null) ? cancellable.is_cancelled() : false;
    }
    
    public void cancel() {
        if (cancellable != null)
            cancellable.cancel();
    }
    
    // This should only be called by Workers.  Beware to all who fail to heed.
    public void internal_notify_completion() {
        if (semaphore != null)
            semaphore.notify();
        
        if (callback == null && cancellation == null)
            return;
        
        if (is_cancelled() && cancellation == null)
            return;
        
        // Because Idle doesn't maintain a ref count of the job, and it's going to be dropped by
        // the worker thread soon, need to maintain a ref until the completion callback is made
        self = this;
        
        Idle.add_full(completion_priority, on_notify_completion);
    }
    
    private bool on_notify_completion() {
        // it's still possible the caller cancelled this operation during or after the execute()
        // method was called ... since the completion work can be costly for a job that was
        // already cancelled, and the caller might've dropped all references to the job by now,
        // only notify completion in this context if not cancelled
        if (is_cancelled()) {
            if (cancellation != null)
                cancellation(this);
        } else {
            if (callback != null)
                callback(this);
        }
        
        // drop the ref so this object can be freed ... must not touch "this" after this point
        self = null;
        
        return false;
    }
    
    // This call may be executed by the child class during execute() to inform of a unit of
    // work being completed
    protected void notify(NotificationCallback callback, NotificationObject? user) {
        lock (notify_queue) {
            notify_queue.add(new NotificationJob(callback, this, user));
        }
        
        Idle.add_full(notification_priority, on_notification_ready);
        
        // If an interlocked notification, block until the main thread completes the notification
        // callback
        InterlockedNotificationObject? interlocked = user as InterlockedNotificationObject;
        if (interlocked != null)
            interlocked.internal_wait_for_completion();
    }
    
    private bool on_notification_ready() {
        // this is called once for every notification added, so there should always be something
        // waiting for us
        NotificationJob? notification_job = null;
        lock (notify_queue) {
            if (notify_queue.size > 0)
                notification_job = notify_queue.remove_at(0);
        }
        assert(notification_job != null);
        
        notification_job.callback(notification_job.background_job, notification_job.user);
        
        // Release the blocked thread waiting for this notification to complete
        InterlockedNotificationObject? interlocked = notification_job.user as InterlockedNotificationObject;
        if (interlocked != null)
            interlocked.internal_completed();
        
        return false;
    }
}

