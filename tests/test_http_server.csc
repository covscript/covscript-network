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

# ============================================================
# Find free port
# ============================================================
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

# ============================================================
# Helpers: drive server fiber + async event loop together
# ============================================================
function drive_server()
    server.poll()
    async.poll_once()
end

function drive_server_cycles(count)
    var i = 0
    while i < count
        drive_server()
        i += 1
    end
end

# Drive server and poll until data is available on the client socket,
# or timeout expires. Returns true if data is ready to read.
function drive_until_data(client, timeout_ms)
    var start = runtime.time()
    while client.available() == 0 && runtime.time() - start < timeout_ms
        drive_server()
        runtime.delay(5)
    end
    return client.available() > 0
end

# Drain available response bytes while continuing to drive server workers.
function drain_response(client, expected, timeout_ms)
    var resp = ""
    var start = runtime.time()
    while runtime.time() - start < timeout_ms
        var n = client.available()
        if n > 0
            var chunk = client.receive(n)
            if chunk != null && !chunk.empty()
                resp += chunk
            end
            if resp.find(expected, 0) != -1
                break
            end
        end
        drive_server()
        runtime.delay(5)
    end
    return resp
end

# ============================================================
# S01 -- http_server basic setup and configuration
# ============================================================
section("S01: basic setup")

var server = new netutils.http_server
check_not_null("S01-01: server created", server)

server.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
check("S01-02: config set", true)

# ============================================================
# S02 -- bind_func with a dynamic handler
# ============================================================
section("S02: bind_func dynamic handler")

var handler_called = false
var handler_path = ""
var handler_call_count = 0

function test_handler(srv, session)
    handler_called = true
    handler_call_count += 1
    handler_path = session.url
    session.send_response("200 OK", "hello from handler", "text/plain")
end

server.bind_func("/test", test_handler)

server.listen(server_port)

# Prime the server: let workers start accepting
drive_server_cycles(5)

# Connect and send HTTP request
var client = new tcp.socket
client.connect(tcp.endpoint("127.0.0.1", server_port))
check("S02-01: client connected", client.is_open())

# Send HTTP request
client.write("GET /test HTTP/1.1\r\nHost: 127.0.0.1:" + to_string(server_port) + "\r\nConnection: close\r\n\r\n")

# Drive server until response data is available, with 5s timeout
if !drive_until_data(client, 5000)
    check("S02-02: received response (timed out after 5s)", false)
    system.out.println("  Server did not respond in time — possible deadlock")
else
    var response = drain_response(client, "hello from handler", 1000)
    check("S02-02: received response", response != null && !response.empty())
    if response != null && !response.empty()
        check("S02-03: response contains 200", response.find("200 OK", 0) != -1)
        check("S02-04: response contains body", response.find("hello from handler", 0) != -1)
    end
end
check("S02-05: handler invoked", handler_called)
check_eq("S02-06: handler received expected path", handler_path, "/test")

client.close()

# ============================================================
# S03 -- consume framed bodies for every method on keep-alive
# ============================================================
section("S03: keep-alive request body framing")

drive_server_cycles(5)

var client_framing = new tcp.socket
client_framing.connect(tcp.endpoint("127.0.0.1", server_port))
var pipelined = "GET /test HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 4\r\nConnection: keep-alive\r\n\r\nJUNK"
pipelined += "GET /test HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
client_framing.write(pipelined)

var framing_start = runtime.time()
while handler_call_count < 3 && runtime.time() - framing_start < 5000
    drive_server()
    runtime.delay(5)
end
if handler_call_count != 3
    system.out.println("  handler_call_count=" + to_string(handler_call_count))
end
check("S03-01: body bytes not parsed as next request", handler_call_count == 3)
client_framing.close()

# ============================================================
# S04 -- unmapped URL returns 403 (no wwwroot configured)
# ============================================================
section("S04: unmapped URL handling")

# Drive server to get worker back to accept state
drive_server_cycles(5)

var client2 = new tcp.socket
client2.connect(tcp.endpoint("127.0.0.1", server_port))
check("S04-01: client connected", client2.is_open())

client2.write("GET /nonexistent HTTP/1.1\r\nHost: 127.0.0.1:" + to_string(server_port) + "\r\nConnection: close\r\n\r\n")

# Drive server until response data is available, with 5s timeout
if !drive_until_data(client2, 5000)
    check("S04-02: received error response (timed out after 5s)", false)
    system.out.println("  Server did not respond in time — possible deadlock")
else
    var response2 = drain_response(client2, "403 Forbidden", 1000)
    check("S04-02: received error response", response2 != null && !response2.empty())
    if response2 != null && !response2.empty()
        check("S04-03: response contains 403 Forbidden", response2.find("403 Forbidden", 0) != -1)
    end
end

client2.close()

# ============================================================
# Cleanup
# ============================================================
section("S05: cleanup")

# Release the acceptor first so pending async accepts are cancelled before the
# executor and worker fibers are destroyed.
server.acceptor = null
server.async_guard = null
server.thread_pool = null
server.worker_list = null
server = null
check("S05-01: server resources released", server == null)

# Results
system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
