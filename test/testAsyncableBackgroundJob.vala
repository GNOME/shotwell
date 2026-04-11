// SPDX-License-Identifier: LGPL-2.1-or-later
// SPDX-FileCopyrightText: 2025 Jens Georg <mail@jensge.org>

class TestJob : BackgroundJob {
    private unowned SourceFunc callback;

    public TestJob() {
        base(null, TestJob.completed, null, TestJob.completed);
    }

    static void completed(BackgroundJob job) {
        print("static complete\n");
        assert(job is TestJob);
        ((TestJob)job).callback();
    }

    public override void execute() {
        Thread.usleep(5000000);
    }

    public async void run(Workers workers) {
        this.callback = run.callback;
        workers.enqueue(this);
        yield;
    }
}

void basic_test() {
    var workers = new Workers(1, true);
    var loop = new MainLoop(null, false);
    new TestJob().run.begin(workers, () => {loop.quit();});
    loop.run();
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/basic", basic_test);

    return Test.run();
}
