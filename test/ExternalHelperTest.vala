[DBus (name = "org.gnome.Shotwell.ExternalHelperTest1")]
public interface TestInterface : Object {
    public abstract async uint64 get_uint64(uint64 in_value) throws Error;
    //public abstract uint64 get_uint64_sync() throws Error;
}

internal class TestExternalProxy : ExternalProxy<TestInterface>, TestInterface {
    public TestExternalProxy(string helper) throws Error {
        Object(dbus_path : "/org/gnome/Shotwell/ExternalHelperTest1", remote_helper_path : helper);
        init();
    }

    public async uint64 get_uint64(uint64 in_value) throws Error {
        var r = yield get_remote();

        var d = yield r.get_uint64(in_value);

        return d;
    }
}

extern const string EXTERNAL_HELPER_EXECUTABLE;

void test_proxy_creation() {
    var p = new TestExternalProxy("does-not-exist-never");
    var loop = new MainLoop(null, false);
    AsyncResult? res = null;
    p.get_uint64.begin(10, (s, r) => {
        loop.quit();
        res = r;
    });

    loop.run();
    assert (res != null);

    // We get NOENT if the helper is not executable
    try {
        assert(p.get_uint64.end(res) == 20);
        assert_not_reached();
    } catch (Error error) {
        assert_error(error, SpawnError.quark(), SpawnError.NOENT);
    }

    p = new TestExternalProxy(EXTERNAL_HELPER_EXECUTABLE);
    p.get_uint64.begin(10, (s, r) => {
        loop.quit();
        res = r;
    });

    loop.run();
    assert (res != null);

    // We get NOENT if the helper is not executable
    try {
        assert(p.get_uint64.end(res) == 20);
    } catch (Error error) {
        critical("Got error %s", error.message);
        assert_not_reached();
    }
}

void main(string[] args) {
    Test.init (ref args);
    Test.add_func("/creation", test_proxy_creation);
    Test.run();
}
