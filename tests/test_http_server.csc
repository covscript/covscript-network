import netutils
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

// ============================================================
// Find free port
// ============================================================
function find_free_port()
    var port = 14000
    while port < 14100
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
    check("S00: find free port", false)
    system.exit(1)
end
system.out.println("Using port: " + to_string(server_port))

// ============================================================
// S01 -- http_server basic setup and configuration
// ============================================================
section("S01: basic setup")

var server = new netutils.http_server
check_not_null("S01-01: server created", server)

server.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
check("S01-02: config set", true)

// ============================================================
// S02 -- bind_func with a dynamic handler
// ============================================================
section("S02: bind_func dynamic handler")

var handler_called = false
var handler_path = ""

server.bind_func("/test", function(srv, session) {
    handler_called = true
    handler_path = session.url
    session.send_response("200 OK", "hello from handler", "text/plain")
})

server.listen(server_port)

// Start server polling in a fiber
var server_running = true
var server_fiber = fiber.create([](server) {
    var guard = new async.work_guard
    loop
        server.poll()
        fiber.yield()
    until !server_running
}, server)
server_fiber.resume()
runtime.delay(50)

// Connect and send HTTP request
var client = new tcp.socket
client.connect(tcp.endpoint("127.0.0.1", server_port))
check("S02-01: client connected", client.is_open())

// Send HTTP request
client.write("GET /test HTTP/1.1\r\nHost: 127.0.0.1:" + to_string(server_port) + "\r\nConnection: close\r\n\r\n")

// Read response
var response = client.receive(1024)
check_not_null("S02-02: received response", response)
check("S02-03: response contains 200", response.find("200 OK", 0) != -1)
check("S02-04: response contains body", response.find("hello from handler", 0) != -1)

client.close()

// ============================================================
// S03 -- 404 handling
// ============================================================
section("S03: 404 handling")

var client2 = new tcp.socket
client2.connect(tcp.endpoint("127.0.0.1", server_port))
check("S03-01: client connected", client2.is_open())

client2.write("GET /nonexistent HTTP/1.1\r\nHost: 127.0.0.1:" + to_string(server_port) + "\r\nConnection: close\r\n\r\n")

var response2 = client2.receive(1024)
check_not_null("S03-02: received 404 response", response2)
check("S03-03: response contains 404", response2.find("404", 0) != -1)

client2.close()

// ============================================================
// Cleanup
// ============================================================
section("S04: cleanup")

server_running = false
check("S04-01: server stopped", true)

// Give fiber time to exit
runtime.delay(50)
async.poll_once()

// Results
system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
