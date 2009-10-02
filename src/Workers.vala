/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// This callback is executed when an associated BackgroundJob completes.  It is called from within
// the Gtk event loop, *not* the background thread's context.
public delegate void CompletionCallback(BackgroundJob job);

// This abstract class represents a unit of work that can be executed within a background thread's
// context.  If specified, the job may be cancellable (which can be checked by execute() and the
// worker thread prior to calling execute()).  The BackgroundJob may also specify a
// CompletionCallback to be executed within Gtk's event loop.
public abstract class BackgroundJob {
    private CompletionCallback callback;
    private Cancellable cancellable;
    private BackgroundJob self = null;
    
    public BackgroundJob(CompletionCallback? callback = null, Cancellable? cancellable = null) {
        this.callback = callback;
        this.cancellable = cancellable;
    }
    
    public abstract void execute();
    
    public bool is_cancelled() {
        return (cancellable != null) ? cancellable.is_cancelled() : false;
    }
    
    public void cancel() {
        if (cancellable != null)
            cancellable.cancel();
    }
    
    // This should only be called by Workers.  Beware to all who fail to heed.
    public void internal_notify_completion() {
        if (callback == null)
            return;
        
        // Because Idle doesn't maintain a ref count of the job, and it's going to be dropped by
        // the worker thread soon, need to maintain a ref until the completion callback is made
        self = this;
        
        Idle.add_full(Priority.HIGH, on_notify_completion);
    }
    
    private bool on_notify_completion() {
        // it's still possible the caller cancelled this operation during or after the execute()
        // method was called ... since the completion work can be costly for a job that was
        // already cancelled, and the caller might've dropped all references to the job by now,
        // only notify completion in this context if not cancelled
        if (!is_cancelled())
            callback(this);
        
        // drop the ref so this object can be freed ... must not touch "this" after this point
        self = null;
        
        return false;
    }
}

// Workers wraps some of ThreadPool's oddities up into an interface that emphasizes BackgroundJob's
// and offers features for the user to be called in particular contexts.
//
// TODO: ThreadPool's bindings are currently broken (in particular, g_thread_pool_free in the
// finalizer) and so we're using a more naive implementation, where each Workers object maintains
// a pool of max_threads threads.  Thus, exclusive is ignored (always true) and UNLIMITED_THREADS
// defaults to THREAD_PER_CPU.
public class Workers {
    public const int UNLIMITED_THREADS = -1;
    public const int THREAD_PER_CPU = 0;
    
    private AsyncQueue<BackgroundJob> queue;
    
    public Workers(int max_threads, bool exclusive) {
        if (max_threads == UNLIMITED_THREADS)
            max_threads = THREAD_PER_CPU;
        
        if (max_threads == THREAD_PER_CPU) {
            max_threads = (int) ExtendedPosix.sysconf(ExtendedPosix.ConfName._SC_NPROCESSORS_ONLN);
            if (max_threads <= 0)
                max_threads = 1;
        }
        
        queue = new AsyncQueue<BackgroundJob>();
        
        assert(max_threads > 0);
        for (int ctr = 0; ctr < max_threads; ctr++) {
            try {
                Thread.create(thread_start, false);
            } catch (Error err) {
                error("Unable to create worker thread: %s", err.message);
            }
        }
    }

    // Enqueues a BackgroundJob for work in a thread context.  BackgroundJob.execute() is called
    // within the thread's context, while its CompletionCallback is called within the Gtk event loop.
    public void enqueue(BackgroundJob background_job) throws Error {
        queue.push(background_job);
    }
    
    private void *thread_start() {
        for (;;) {
            BackgroundJob job = queue.pop();
            if (job == null)
                break;
            
            thread_work(job);
        }
        
        return null;
    }
    
    private void thread_work(BackgroundJob job) {
        if (job.is_cancelled())
            return;
        
        job.execute();
        
        job.internal_notify_completion();
    }
}

