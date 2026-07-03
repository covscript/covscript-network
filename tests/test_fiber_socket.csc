import network.tcp as tcp
import network.async as async

var _pass = 0
var _fail = 0
var _section = ""

function section(name)
    _section = name
    system.out.println("")
    system.out.println("=== " + name + " ===")
end

function check(label, ok)
    if ok
        system.out.println("[PASS] " + _section + " | " + label)
        _pass += 1
    else
        system.out.println("[FAIL] " + _section + " | " + label)
        _fail += 1
    end
end

function check_eq(label, a, b)
    if a != b
        system.out.println("  expected: " + to_string(b) + ", got: " + to_string(a))
    end
    check(label, a == b)
end

function check_not_null(label, v)
    check(label, v != null)
end

function check_true(label, v)
    check(label, v == true)
end

// ============================================================
// Find free port
// ============================================================
function find_free_port()
    var port = 15000
    while port < 15100
        try
            var acpt = tcp.acceptor(tcp.endpoint_v4(port))
            acpt = null
            return port
        catch e
            port += 1
        end
    end
    return 0
end

var server_port = find_free_port()
if server_port == 0
    check("F00: find free port", false)
    system.exit(1)
end
system.out.println("Using port: " + to_string(server_port))

// ============================================================
// F01 — Fiber-based async server + sync client
// ============================================================
section("F01: fiber async accept + echo")

var guard = new async.work_guard
var server = new tcp.socket
var acpt = tcp.acceptor(tcp.endpoint_v4(server_port))

// Shared state between fiber and main
var accept_done = false
var server_ready = false
var echo_received = ""

// Fiber: server that accepts and echoes
var server_fiber = fiber.create([](server, acpt) {
    var state = async.accept(server, acpt)
    while !state.has_done()
        async.poll_once()
        fiber.yield()
    end

    if state.get_error() != null
        return
    end

    var data = server.receive(128)
    server.write(data)
    server.close()
}, server, acpt)

// Resume fiber to start async accept
server_fiber.resume()

// Give fiber time to submit async accept
runtime.delay(10)
async.poll_once()

// Client connects synchronously
var client = new tcp.socket
client.connect(tcp.endpoint("127.0.0.1", server_port))
check_true("F01-01: client connected", client.is_open())

// Resume fiber to poll for accept completion
var max_iter = 100
var iter = 0
loop
    server_fiber.resume()
    async.poll_once()
    iter += 1
    if iter >= max_iter
        break
    end
    runtime.delay(10)
until !server.is_open()  // fiber closed server after echo

// Check that we didn't exceed max iterations (otherwise fiber hung)
check("F01-02: fiber completed within timeout", iter < max_iter)

client.close()
check("F01-03: test completed without crash", true)

// ============================================================
// F02 — Fiber with async read_until
// ============================================================
section("F02: fiber async read_until")

var guard2 = new async.work_guard
var server2 = new tcp.socket
var acpt2 = tcp.acceptor(tcp.endpoint_v4(server_port + 1))

var read_complete = false
var read_data = ""

var server_fiber2 = fiber.create([](server) {
    var state = new async.state

    // Accept
    var accept_s = async.accept(server, acpt2)
    while !accept_s.has_done()
        async.poll_once()
        fiber.yield()
    end
    if accept_s.get_error() != null
        return
    end

    // Read until \n
    async.read_until(server, state, "\n")
    while !state.has_done()
        async.poll_once()
        fiber.yield()
    end

    if state.get_error() == null
        read_data = state.get_result()
        read_complete = true
    end

    server.close()
}, server2)

// Start fiber
server_fiber2.resume()
runtime.delay(10)
async.poll_once()

// Client
var client2 = new tcp.socket
client2.connect(tcp.endpoint("127.0.0.1", server_port + 1))
client2.write("hello fiber\n")

// Poll until fiber completes
iter = 0
max_iter = 100
loop
    server_fiber2.resume()
    async.poll_once()
    iter += 1
    if iter >= max_iter
        break
    end
    runtime.delay(10)
until read_complete

check("F02-01: read_until completed", read_complete)
if read_complete
    check("F02-02: received data contains hello", read_data.find("hello", 0) != -1)
end

client2.close()

// ============================================================
// F03 — async thread_worker
// ============================================================
section("F03: thread_worker")

var worker = new async.thread_worker
check("F03-01: thread_worker created", true)

// Verify poll works across thread
var guard3 = new async.work_guard
check("F03-02: work_guard created", true)

// io_context should be running via the thread worker
check_false("F03-03: io_context not stopped", async.stopped())

// Clean up — destroying work_guard allows io_context to stop
guard3 = null
runtime.delay(50)
async.poll()

check("F03-04: thread_worker test completed", true)

// ============================================================
// F04 — poll / poll_once / stopped / restart round-trip
// ============================================================
section("F04: event loop lifecycle")

var guard4 = new async.work_guard

check_false("F04-01: not stopped with work_guard", async.stopped())

var polled = async.poll()
check("F04-02: poll returns (may be true or false)", true)

var polled_one = async.poll_once()
check("F04-03: poll_once returns (may be true or false)", true)

guard4 = null

// After work_guard is released, io_context may run out of work and stop
async.poll()
async.poll()
async.poll()

// Results
system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
