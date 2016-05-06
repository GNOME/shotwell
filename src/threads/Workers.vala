/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */


public class BackgroundJobBatch : SortedList<BackgroundJob> {
    public BackgroundJobBatch() {
        base (BackgroundJob.priority_comparator);
    }
}

// Workers wraps some of ThreadPool's oddities up into an interface that emphasizes BackgroundJobs.
public class Workers {
    public const int UNLIMITED_THREADS = -1;
    
    private ThreadPool<void *> thread_pool;
    private AsyncQueue<BackgroundJob> queue = new AsyncQueue<BackgroundJob>();
    private EventSemaphore empty_event = new EventSemaphore();
    private int enqueued = 0;
    
    public Workers(uint max_threads, bool exclusive) {
        if (max_threads <= 0 && max_threads != UNLIMITED_THREADS)
            max_threads = 1;
        
        // event starts as set because queue is empty
        empty_event.notify();
        
        try {
            thread_pool = new ThreadPool<void *>.with_owned_data(thread_start, (int) max_threads, exclusive);
        } catch (ThreadError err) {
            error("Unable to create thread pool: %s", err.message);
        }
    }
    
    public static uint threads_per_cpu(int per = 1, int max = -1) requires (per > 0) ensures (result > 0) {
        var count = GLib.get_num_processors() * per;
        
        return (max < 0) ? count : count.clamp(0, max);
    }
    
    // This is useful when the intent is for the worker threads to use all the CPUs minus one for
    // the main/UI thread.  (No guarantees, of course.)
    public static uint thread_per_cpu_minus_one() ensures (result > 0) {
        return (GLib.get_num_processors() - 1).clamp(1, int.MAX);
    }
    
    // Enqueues a BackgroundJob for work in a thread context.  BackgroundJob.execute() is called
    // within the thread's context, while its CompletionCallback is called within the Gtk event loop.
    public void enqueue(BackgroundJob job) {
        empty_event.reset();
        
        lock (queue) {
            queue.push_sorted(job, BackgroundJob.priority_compare_func);
            enqueued++;
        }
        
        try {
            thread_pool.add(job);
        } catch (ThreadError err) {
            // error should only occur when a thread could not be created, in which case, the
            // BackgroundJob is queued up
            warning("Unable to create worker thread: %s", err.message);
        }
    }
    
    public void enqueue_many(BackgroundJobBatch batch) {
        foreach (BackgroundJob job in batch)
            enqueue(job);
    }
    
    public void wait_for_empty_queue() {
        empty_event.wait();
    }
    
    // Returns the number of BackgroundJobs on the queue, not including active jobs.
    public int get_pending_job_count() {
        lock (queue) {
            return enqueued;
        }
    }
    
    private void thread_start(void *ignored) {
        BackgroundJob? job;
        bool empty;
        lock (queue) {
            job = queue.try_pop();
            assert(job != null);
            
            assert(enqueued > 0);
            empty = (--enqueued == 0);
        }
        
        if (!job.is_cancelled())
            job.execute();
        
        job.internal_notify_completion();
        
        if (empty)
            empty_event.notify();
    }
}

