import netutils
import network.tcp as tcp
import network.async as async

var _pass = 0
var _fail = 0
var _section = ""
var _skip = 0

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

function check_null(label, v)
    check(label, v == null)
end

function check_true(label, v)
    check(label, v == true)
end

function check_false(label, v)
    check(label, v == false)
end

function skip(label, reason)
    _skip += 1
    system.out.println("[SKIP] " + _section + " | " + label + " -- " + reason)
end

# Shared port counter to avoid reusing ports across sections
var _next_port = 15500

function alloc_port()
    var port = _next_port
    _next_port += 1
    var max_port = _next_port + 100
    while port < max_port
        try
            var acpt = tcp.acceptor(tcp.endpoint_v4(port))
            acpt = null
            return port
        catch e
            port = _next_port
            _next_port += 1
        end
    end
    return 0
end

var backend_port = alloc_port()
if backend_port == 0
    check("P00: find free port for backend", false)
    system.exit(1)
end

var proxy_port = alloc_port()
if proxy_port == 0
    check("P00: find free port for proxy", false)
    system.exit(1)
end

system.out.println("Backend port: " + to_string(backend_port))
system.out.println("Proxy port: " + to_string(proxy_port))

# ============================================================
# Worker threads needed for async I/O
# ============================================================
var guard = new async.work_guard

# ============================================================
# Helpers: drive both servers cooperatively
# ============================================================
function drive_both(backend, proxy)
    backend.poll()
    proxy.poll()
    async.poll_once()
end

function drive_both_cycles(backend, proxy, count)
    var i = 0
    while i < count
        drive_both(backend, proxy)
        i += 1
    end
end

function drive_until_data(client, backend, proxy, timeout_ms)
    var start = runtime.time()
    while client.available() == 0 && runtime.time() - start < timeout_ms
        drive_both(backend, proxy)
        runtime.delay(5)
    end
    return client.available() > 0
end

function drain_response(client, marker, backend, proxy, timeout_ms)
    var resp = ""
    var start = runtime.time()
    while runtime.time() - start < timeout_ms
        var n = client.available()
        if n > 0
            var chunk = client.receive(n)
            if chunk != null && !chunk.empty()
                resp += chunk
            end
            if resp.find(marker, 0) != -1
                break
            end
        end
        drive_both(backend, proxy)
        runtime.delay(5)
    end
    return resp
end

# ============================================================
# P01 -- bind_proxy: basic GET forwarding
# ============================================================
section("P01: bind_proxy GET forwarding")

# Backend server: serves /api/hello
var backend = new netutils.http_server
backend.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())

var backend_handler_called = false
var backend_request_path = ""

function backend_hello(srv, session)
    backend_handler_called = true
    backend_request_path = session.url
    session.send_response("200 OK", "Hello from backend", "text/plain")
end

backend.bind_func("/api/hello", backend_hello)
backend.listen(backend_port)

# Proxy server: forwards /api/* to backend
var proxy = new netutils.http_server
proxy.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
proxy.bind_proxy("/api/", "http://127.0.0.1:" + to_string(backend_port), 5000)
proxy.listen(proxy_port)

# Drive both servers to get workers accepting
drive_both_cycles(backend, proxy, 5)

# Client connects to proxy
var client = new tcp.socket
client.connect(tcp.endpoint("127.0.0.1", proxy_port))
check("P01-01: client connected to proxy", client.is_open())

# Send GET request to proxy
client.write("GET /api/hello HTTP/1.1\r\nHost: 127.0.0.1:" + to_string(proxy_port) + "\r\nConnection: close\r\n\r\n")

if !drive_until_data(client, backend, proxy, 5000)
    check("P01-02: received response (timed out)", false)
else
    var response = drain_response(client, "Hello from backend", backend, proxy, 2000)
    check("P01-02: received response", response != null && !response.empty())
    if response != null && !response.empty()
        check("P01-03: response contains 200 OK", response.find("200 OK", 0) != -1)
        check("P01-04: body forwarded from backend", response.find("Hello from backend", 0) != -1)
    end
end

check("P01-05: backend handler was called", backend_handler_called)
check_eq("P01-06: backend received correct path", backend_request_path, "/api/hello")

client.close()

# ============================================================
# P02 -- bind_proxy: backend returns non-200 status
# ============================================================

# Need fresh servers for this test since the previous ones are used up
backend.stop()
proxy.stop()

section("P02: bind_proxy non-200 status forwarding")

var backend2_port = alloc_port()
var proxy2_port = alloc_port()
system.out.println("Backend2 port: " + to_string(backend2_port) + ", Proxy2 port: " + to_string(proxy2_port))

var backend2 = new netutils.http_server
backend2.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())

var not_found_called = false
function backend_404(srv, session)
    not_found_called = true
    session.send_response("404 Not Found", "{\"error\":\"not found\"}", "application/json")
end

backend2.bind_func("/api/missing", backend_404)
backend2.listen(backend2_port)

var proxy2 = new netutils.http_server
proxy2.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
proxy2.bind_proxy("/api/", "http://127.0.0.1:" + to_string(backend2_port), 5000)
proxy2.listen(proxy2_port)

drive_both_cycles(backend2, proxy2, 5)

var client2 = new tcp.socket
client2.connect(tcp.endpoint("127.0.0.1", proxy2_port))
check("P02-01: client connected to proxy2", client2.is_open())

client2.write("GET /api/missing HTTP/1.1\r\nHost: 127.0.0.1:" + to_string(proxy2_port) + "\r\nConnection: close\r\n\r\n")

if !drive_until_data(client2, backend2, proxy2, 5000)
    check("P02-02: received response (timed out)", false)
else
    var response2 = drain_response(client2, "not found", backend2, proxy2, 2000)
    check("P02-02: received response", response2 != null && !response2.empty())
    if response2 != null && !response2.empty()
        check("P02-03: response contains 404", response2.find("404", 0) != -1)
        check("P02-04: JSON error body forwarded", response2.find("not found", 0) != -1)
    end
end
check("P02-05: backend 404 handler called", not_found_called)

client2.close()
backend2.stop()
proxy2.stop()

# ============================================================
# P03 -- bind_proxy: content-type preservation from backend
# ============================================================
section("P03: bind_proxy content-type preservation")

var backend3_port = alloc_port()
var proxy3_port = alloc_port()
system.out.println("Backend3 port: " + to_string(backend3_port) + ", Proxy3 port: " + to_string(proxy3_port))

var backend3 = new netutils.http_server
backend3.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())

function backend_html(srv, session)
    session.send_response("200 OK", "<h1>Title</h1>", "text/html")
end

backend3.bind_func("/api/page", backend_html)
backend3.listen(backend3_port)

var proxy3 = new netutils.http_server
proxy3.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
proxy3.bind_proxy("/api/", "http://127.0.0.1:" + to_string(backend3_port), 5000)
proxy3.listen(proxy3_port)

drive_both_cycles(backend3, proxy3, 5)

var client3 = new tcp.socket
client3.connect(tcp.endpoint("127.0.0.1", proxy3_port))
check("P03-01: client connected to proxy3", client3.is_open())

client3.write("GET /api/page HTTP/1.1\r\nHost: 127.0.0.1:" + to_string(proxy3_port) + "\r\nConnection: close\r\n\r\n")

if !drive_until_data(client3, backend3, proxy3, 5000)
    check("P03-02: received response (timed out)", false)
else
    var response3 = drain_response(client3, "</h1>", backend3, proxy3, 2000)
    check("P03-02: received response", response3 != null && !response3.empty())
    if response3 != null && !response3.empty()
        check("P03-03: content-type text/html preserved", response3.find("text/html", 0) != -1)
        check("P03-04: HTML body forwarded", response3.find("<h1>Title</h1>", 0) != -1)
    end
end

client3.close()
backend3.stop()
proxy3.stop()

# ============================================================
# P04 -- bind_proxy: POST data forwarding
# ============================================================
section("P04: bind_proxy POST forwarding")

var backend4_port = alloc_port()
var proxy4_port = alloc_port()
system.out.println("Backend4 port: " + to_string(backend4_port) + ", Proxy4 port: " + to_string(proxy4_port))

var backend4 = new netutils.http_server
backend4.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())

var post_received = false
var post_body_received = ""

function backend_post(srv, session)
    post_received = true
    post_body_received = session.post_data
    session.send_response("200 OK", "{\"result\":\"saved\"}", "application/json")
end

backend4.bind_func("/api/submit", backend_post)
backend4.listen(backend4_port)

var proxy4 = new netutils.http_server
proxy4.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
proxy4.bind_proxy("/api/", "http://127.0.0.1:" + to_string(backend4_port), 5000)
proxy4.listen(proxy4_port)

drive_both_cycles(backend4, proxy4, 5)

var client4 = new tcp.socket
client4.connect(tcp.endpoint("127.0.0.1", proxy4_port))
check("P04-01: client connected to proxy4", client4.is_open())

var post_data = "name=test&value=123"
client4.write("POST /api/submit HTTP/1.1\r\nHost: 127.0.0.1:" + to_string(proxy4_port) + "\r\nContent-Length: " + to_string(post_data.size) + "\r\nContent-Type: application/x-www-form-urlencoded\r\nConnection: close\r\n\r\n" + post_data)

if !drive_until_data(client4, backend4, proxy4, 5000)
    check("P04-02: received response (timed out)", false)
else
    var response4 = drain_response(client4, "saved", backend4, proxy4, 2000)
    check("P04-02: received response", response4 != null && !response4.empty())
    if response4 != null && !response4.empty()
        check("P04-03: response contains saved", response4.find("saved", 0) != -1)
    end
end
check("P04-04: backend received POST", post_received)
check_eq("P04-05: POST body forwarded correctly", post_body_received, post_data)

client4.close()
backend4.stop()
proxy4.stop()

# ============================================================
# P05 -- bind_proxy: proxy to unreachable backend returns 503
# ============================================================
section("P05: bind_proxy unreachable backend")

var proxy5_port = alloc_port()
system.out.println("Proxy5 port: " + to_string(proxy5_port))

var proxy5 = new netutils.http_server
proxy5.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
# Point to a dead backend
proxy5.bind_proxy("/api/", "http://127.0.0.1:19997", 1000)
proxy5.listen(proxy5_port)

# Drive proxy to get workers accepting
var null_backend = null
var drive_count = 0
while drive_count < 5
    proxy5.poll()
    async.poll_once()
    drive_count += 1
end

var client5 = new tcp.socket
client5.connect(tcp.endpoint("127.0.0.1", proxy5_port))
check("P05-01: client connected to proxy5", client5.is_open())

client5.write("GET /api/anything HTTP/1.1\r\nHost: 127.0.0.1:" + to_string(proxy5_port) + "\r\nConnection: close\r\n\r\n")

var start5 = runtime.time()
var resp5 = ""
while runtime.time() - start5 < 5000
    var n = client5.available()
    if n > 0
        var chunk = client5.receive(n)
        if chunk != null && !chunk.empty()
            resp5 += chunk
        end
        if resp5.find("503", 0) != -1 || resp5.find("Backend unavailable", 0) != -1
            break
        end
    end
    proxy5.poll()
    async.poll_once()
    runtime.delay(10)
end
check("P05-01: response received", !resp5.empty())
check("P05-02: 503 Service Unavailable", resp5.find("503", 0) != -1 || resp5.find("Backend unavailable", 0) != -1)

client5.close()
proxy5.stop()

# ============================================================
# P06 -- bind_proxy: URL prefix routing
# ============================================================
section("P06: bind_proxy prefix routing")

var backend6_port = alloc_port()
var proxy6_port = alloc_port()
system.out.println("Backend6 port: " + to_string(backend6_port) + ", Proxy6 port: " + to_string(proxy6_port))

var backend6 = new netutils.http_server
backend6.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())

var path_received = ""
function backend_echo_path(srv, session)
    path_received = session.url
    session.send_response("200 OK", session.url, "text/plain")
end

backend6.bind_func("/api/v1/users", backend_echo_path)
backend6.listen(backend6_port)

var proxy6 = new netutils.http_server
proxy6.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
proxy6.bind_proxy("/api/", "http://127.0.0.1:" + to_string(backend6_port), 5000)
proxy6.listen(proxy6_port)

drive_both_cycles(backend6, proxy6, 5)

var client6 = new tcp.socket
client6.connect(tcp.endpoint("127.0.0.1", proxy6_port))
check("P06-01: client connected", client6.is_open())

client6.write("GET /api/v1/users HTTP/1.1\r\nHost: 127.0.0.1:" + to_string(proxy6_port) + "\r\nConnection: close\r\n\r\n")

if !drive_until_data(client6, backend6, proxy6, 5000)
    check("P06-02: response timed out", false)
else
    var response6 = drain_response(client6, "/api/v1/users", backend6, proxy6, 2000)
    check("P06-02: response received", !response6.empty())
end
check_eq("P06-03: backend received correct path", path_received, "/api/v1/users")

client6.close()
backend6.stop()
proxy6.stop()

# ============================================================
# P07 -- Request headers forwarded to backend
# ============================================================
section("P07: request headers forwarded")

var backend7_port = alloc_port()
var proxy7_port = alloc_port()
system.out.println("Backend7 port: " + to_string(backend7_port) + ", Proxy7 port: " + to_string(proxy7_port))

var backend7 = new netutils.http_server
backend7.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())

var received_ct = ""
var received_auth = ""
var received_custom = ""
var received_host = ""

function backend_header_check(srv, session)
    if session.request_headers != null
        if session.request_headers.exist("content-type")
            received_ct = session.request_headers["content-type"]
        end
        if session.request_headers.exist("authorization")
            received_auth = session.request_headers["authorization"]
        end
        if session.request_headers.exist("x-custom")
            received_custom = session.request_headers["x-custom"]
        end
    end
    # Host goes to session.host (dedicated field), not request_headers
    if session.host != null
        received_host = session.host
    end
    session.send_response("200 OK", "ok", "text/plain")
end

backend7.bind_func("/api/check", backend_header_check)
backend7.listen(backend7_port)

var proxy7 = new netutils.http_server
proxy7.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
proxy7.bind_proxy("/api/", "http://127.0.0.1:" + to_string(backend7_port), 5000)
proxy7.listen(proxy7_port)

drive_both_cycles(backend7, proxy7, 5)

var client7 = new tcp.socket
client7.connect(tcp.endpoint("127.0.0.1", proxy7_port))
check("P07-01: client connected", client7.is_open())

client7.write("GET /api/check HTTP/1.1\r\nHost: original.example.com\r\nContent-Type: application/json\r\nAuthorization: Bearer test123\r\nX-Custom: value456\r\nConnection: close\r\n\r\n")

if !drive_until_data(client7, backend7, proxy7, 5000)
    check("P07-02: response timed out", false)
else
    var resp7 = drain_response(client7, "ok", backend7, proxy7, 2000)
    check("P07-02: received response", resp7.find("200 OK", 0) != -1)
end

check_eq("P07-03: Content-Type forwarded", received_ct, "application/json")
check_eq("P07-04: Authorization forwarded", received_auth, "Bearer test123")
check_eq("P07-05: X-Custom forwarded", received_custom, "value456")
# Host is stored in session.host (dedicated field), not request_headers
check("P07-06: Host forwarded", !received_host.empty())

client7.close()
backend7.stop()
proxy7.stop()

# ============================================================
# Cleanup and results
# ============================================================
section("Results")

backend = null
proxy = null
backend2 = null
proxy2 = null
backend3 = null
proxy3 = null
backend4 = null
proxy4 = null
proxy5 = null
backend6 = null
proxy6 = null
guard = null

system.out.println("")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
system.out.println("SKIP: " + _skip)
if _fail > 0
    system.exit(1)
end
