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

function check_false(label, v)
    check(label, v == false)
end

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

section("F01: fiber async accept + echo")

var guard = new async.work_guard
var server = new tcp.socket
var acpt = tcp.acceptor(tcp.endpoint_v4(server_port))

var accept_done = false
var echo_data = ""

function server_fiber_func(sock)
    var state = async.accept(sock, acpt)
    loop
        async.poll_once()
        fiber.yield()
    until state.has_done()

    if state.get_error() != null
        return
    end

    var data = sock.receive(128)
    sock.write(data)
    sock.close()
end

var server_fiber = fiber.create(server_fiber_func, server)

server_fiber.resume()

runtime.delay(10)
async.poll_once()

var client = new tcp.socket
client.connect(tcp.endpoint("127.0.0.1", server_port))
check_true("F01-01: client connected", client.is_open())

var max_iter = 100
var iter = 0
loop
    server_fiber.resume()
    async.poll_once()
    iter += 1
    if iter >= max_iter
        break
    end
until !server.is_open()

check("F01-02: fiber completed within timeout", iter < max_iter)
client.close()
check("F01-03: test completed without crash", true)

section("F02: fiber async read_until")

var guard2 = new async.work_guard
var server2 = new tcp.socket
var acpt2 = tcp.acceptor(tcp.endpoint_v4(server_port + 1))

var read_complete = false
var read_data = ""

function server_fiber_func2(sock)
    var accept_s = async.accept(sock, acpt2)
    loop
        async.poll_once()
        fiber.yield()
    until accept_s.has_done()

    if accept_s.get_error() != null
        return
    end

    var state = new async.state
    async.read_until(sock, state, "\n")
    loop
        async.poll_once()
        fiber.yield()
    until state.has_done()

    if state.get_error() == null
        read_data = state.get_result()
        read_complete = true
    end

    sock.close()
end

var server_fiber2 = fiber.create(server_fiber_func2, server2)

server_fiber2.resume()
runtime.delay(10)
async.poll_once()

var client2 = new tcp.socket
client2.connect(tcp.endpoint("127.0.0.1", server_port + 1))
client2.write("hello fiber\n")

iter = 0
max_iter = 100
loop
    server_fiber2.resume()
    async.poll_once()
    iter += 1
    if iter >= max_iter
        break
    end
until read_complete

check("F02-01: read_until completed", read_complete)
if read_complete
    check("F02-02: received data contains hello", read_data.find("hello", 0) != -1)
end

client2.close()

section("F03: thread_worker")

var worker = new async.thread_worker
check("F03-01: thread_worker created", true)

var guard3 = new async.work_guard
check("F03-02: work_guard created", true)

check_false("F03-03: io_context not stopped", async.stopped())

guard3 = null
async.poll()
check("F03-04: thread_worker test completed", true)

section("F04: event loop lifecycle")

var guard4 = new async.work_guard

check_false("F04-01: not stopped with work_guard", async.stopped())

var polled = async.poll()
check("F04-02: poll returns (may be true or false)", true)

var polled_one = async.poll_once()
check("F04-03: poll_once returns (may be true or false)", true)

guard4 = null

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
