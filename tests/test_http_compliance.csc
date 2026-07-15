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

function check_contains(label, haystack, needle)
    if haystack == null
        check(label, false)
        system.out.println("  string is null")
    else
        var ok = haystack.find(needle, 0) != -1
        if !ok
            var preview = haystack
            if preview.size > 400
                preview = haystack.substr(0, 400)
            end
            system.out.println("  expected to contain: " + needle)
            system.out.println("  actual: " + preview)
        end
        check(label, ok)
    end
end

function check_not_contains(label, haystack, needle)
    if haystack == null
        check(label, false)
        system.out.println("  string is null")
    else
        var ok = haystack.find(needle, 0) == -1
        if !ok
            system.out.println("  found unexpected: " + needle)
        end
        check(label, ok)
    end
end

# ============================================================
# Port & server infrastructure
# ============================================================
var _next_port = 15800

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

# ---- single-server helpers ----
function drive(server)
    server.poll()
    async.poll_once()
end

function drive_n(server, n)
    var i = 0
    while i < n
        drive(server)
        i += 1
    end
end

# Shared response reader: polls srv_a (and srv_b when not null) while reading
# one HTTP response. Body reads are capped at the remaining Content-Length so
# bytes of a pipelined follow-up response are never consumed and discarded.
function read_response_from(client, srv_a, srv_b, timeout_ms)
    var buf = ""
    var start = runtime.time()

    while buf.find("\r\n\r\n", 0) == -1 && runtime.time() - start < timeout_ms
        var n = client.available()
        if n > 0
            var chunk = client.receive(n)
            if chunk != null && !chunk.empty()
                buf += chunk
            end
        else
            # No buffered data and the peer has closed: no response is coming
            if client.peer_closed()
                break
            end
        end
        srv_a.poll()
        if srv_b != null
            srv_b.poll()
        end
        async.poll_once()
        runtime.delay(2)
    end
    if buf.find("\r\n\r\n", 0) == -1
        return buf
    end

    var hdr_end = buf.find("\r\n\r\n", 0)
    var headers = buf.substr(0, hdr_end)
    var body_start = hdr_end + 4

    var cl = -1
    var cl_pos = headers.find("Content-Length:", 0)
    if cl_pos != -1
        var cl_end = headers.find("\r\n", cl_pos)
        if cl_end == -1
            cl_end = headers.size
        end
        var cl_str = headers.substr(cl_pos + 15, cl_end - cl_pos - 15).trim()
        try
            cl = to_integer(cl_str)
        catch e
            cl = -1
        end
    end

    if cl >= 0
        var body_got = buf.size - body_start
        while body_got < cl && runtime.time() - start < timeout_ms
            var n = client.available()
            if n > cl - body_got
                n = cl - body_got
            end
            if n > 0
                var chunk = client.receive(n)
                if chunk != null && !chunk.empty()
                    buf += chunk
                    body_got += chunk.size
                end
            else
                # Body truncated by peer close: stop waiting for the rest
                if client.peer_closed()
                    break
                end
            end
            srv_a.poll()
            if srv_b != null
                srv_b.poll()
            end
            async.poll_once()
            runtime.delay(2)
        end
    end
    return buf
end

function read_http_response(client, server, timeout_ms)
    return read_response_from(client, server, null, timeout_ms)
end

function http_req(method, path, host_port, headers, body)
    var s = method + " " + path + " HTTP/1.1\r\nHost: " + host_port + "\r\n"
    foreach h in headers
        s += h + "\r\n"
    end
    if body != null && !body.empty()
        s += "Content-Length: " + to_string(body.size) + "\r\n"
    end
    s += "\r\n"
    if body != null && !body.empty()
        s += body
    end
    return s
end

# ---- master-slave helpers ----
function drive_ms(master, slave)
    master.poll()
    slave.poll()
    async.poll_once()
end

function drive_ms_n(master, slave, n)
    var i = 0
    while i < n
        drive_ms(master, slave)
        i += 1
    end
end

function read_response_ms(client, master, slave, timeout_ms)
    return read_response_from(client, master, slave, timeout_ms)
end

# Shared handler state (reset per section)
var g_count = 0
var g_method = ""
var g_path = ""
var g_body = ""
var g_headers = null

function echo_handler(srv, session)
    g_count += 1
    g_method = session.method
    g_path = session.url
    g_body = session.post_data
    var resp = "method=" + session.method + " path=" + session.url
    if session.post_data != null && !session.post_data.empty()
        resp += " body=" + session.post_data
    end
    session.send_response("200 OK", resp, "text/plain")
end

function reset_state()
    g_count = 0
    g_method = ""
    g_path = ""
    g_body = ""
    g_headers = null
end

# ======================================================================
#  C01 — Request line: methods, URL, HTTP version
# ======================================================================
section("C01: request line parsing (single)")

reset_state()
var p = alloc_port()
system.out.println("port=" + to_string(p))

var srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
srv.bind_func("/api/v1/echo", echo_handler)
srv.listen(p)
drive_n(srv, 10)

# GET with query string
var c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write(http_req("GET", "/api/v1/echo?key=val&x=1", "127.0.0.1:" + to_string(p), {"Connection: close"}, null))
var r = read_http_response(c, srv, 5000)
check_contains("C01-01: 200 OK", r, "200 OK")
check_contains("C01-02: method=GET", r, "method=GET")
# url stores path only; query string goes to args (RFC 3986)
check_contains("C01-03: path (url excludes query)", r, "path=/api/v1/echo")
check_eq("C01-04: handler saw GET", g_method, "GET")
c.close()
drive_n(srv, 5)

# POST
reset_state()
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write(http_req("POST", "/api/v1/echo", "127.0.0.1:" + to_string(p), {"Connection: close"}, "hello=world"))
r = read_http_response(c, srv, 5000)
check_contains("C01-05: POST 200", r, "200 OK")
check_contains("C01-06: body forwarded", r, "body=hello=world")
check_eq("C01-07: handler saw POST", g_method, "POST")
c.close()
drive_n(srv, 5)

# PUT
reset_state()
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write(http_req("PUT", "/api/v1/echo", "127.0.0.1:" + to_string(p), {"Connection: close"}, "put-data"))
r = read_http_response(c, srv, 5000)
check_contains("C01-08: PUT 200", r, "200 OK")
check_eq("C01-09: handler saw PUT", g_method, "PUT")
c.close()
drive_n(srv, 5)

# HTTP/1.0
reset_state()
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("GET /api/v1/echo HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n")
r = read_http_response(c, srv, 5000)
check_contains("C01-10: HTTP/1.0 gets 200", r, "200 OK")
check_contains("C01-11: HTTP/1.0 defaults to Connection: close", r, "close")
c.close()

srv.acceptor = null
srv = null

# ======================================================================
#  C02 — Response structure: status line & mandatory headers
# ======================================================================
section("C02: response structure (single)")

reset_state()
p = alloc_port()
system.out.println("port=" + to_string(p))

srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
srv.bind_func("/resp", echo_handler)
srv.listen(p)
drive_n(srv, 10)

c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write(http_req("GET", "/resp", "127.0.0.1:" + to_string(p), {"Connection: close"}, null))
r = read_http_response(c, srv, 5000)
check("C02-01: response received", !r.empty())

# Status line
check_contains("C02-02: HTTP/1.1 in status", r, "HTTP/1.1")
check_contains("C02-03: 200 OK", r, "200 OK")
# Mandatory headers (RFC 7231)
check_contains("C02-04: Date header", r, "Date: ")
check_contains("C02-05: Server header", r, "Server: " + netutils.server_name + "/" + netutils.server_version)
check_contains("C02-06: Content-Length header", r, "Content-Length: ")
check_contains("C02-07: Content-Type header", r, "Content-Type: ")
check_contains("C02-08: Connection header", r, "Connection: ")

c.close()
srv.acceptor = null
srv = null

# ======================================================================
#  C03 — Error status codes
# ======================================================================
section("C03: error status codes (single)")

reset_state()
p = alloc_port()
system.out.println("port=" + to_string(p))

srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 1, "max_body_size": 100}.to_hash_map())
srv.listen(p)
drive_n(srv, 10)

# 400 Bad Request — malformed
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("GARBAGE\r\n\r\n")
r = read_http_response(c, srv, 5000)
check_contains("C03-01: 400 for garbage", r, "400")
c.close()
drive_n(srv, 5)

# 404 Not Found — no route, no wwwroot
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write(http_req("GET", "/no/such/path", "127.0.0.1:" + to_string(p), {"Connection: close"}, null))
r = read_http_response(c, srv, 5000)
check("C03-02: 403 or 404", r.find("403", 0) != -1 || r.find("404", 0) != -1)
c.close()
drive_n(srv, 5)

# 413 Payload Too Large
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
var big = new string
var bi = 0
while bi < 200
    big += "x"
    bi += 1
end
c.write(http_req("POST", "/echo", "127.0.0.1:" + to_string(p), {"Connection: close"}, big))
r = read_http_response(c, srv, 5000)
check_contains("C03-03: 413 for oversized body", r, "413")
c.close()
drive_n(srv, 5)

# 431 — header too large
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
var huge_hdr = "GET /echo HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Big: "
var hi = 0
while hi < 10000
    huge_hdr += "A"
    hi += 1
end
huge_hdr += "\r\nConnection: close\r\n\r\n"
c.write(huge_hdr)
r = read_http_response(c, srv, 5000)
check_contains("C03-04: 431 for huge header", r, "431")
c.close()

srv.acceptor = null
srv = null

# ======================================================================
#  C04 — Keep-alive: max requests, client close, timeout (single)
# ======================================================================
section("C04: keep-alive lifecycle (single)")

reset_state()
p = alloc_port()
system.out.println("port=" + to_string(p))

srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 1, "max_keep_alive": 3, "keep_alive_timeout": 10000}.to_hash_map())
srv.bind_func("/ka", echo_handler)
srv.listen(p)
drive_n(srv, 10)

c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))

# Request 1 → keep-alive
c.write(http_req("GET", "/ka", "127.0.0.1", {"Connection: keep-alive"}, null))
r = read_http_response(c, srv, 5000)
check_contains("C04-01: resp-1 keep-alive", r, "keep-alive")
check_not_contains("C04-02: resp-1 no 408", r, "408 Request Timeout")

# Request 2 → keep-alive
c.write(http_req("GET", "/ka", "127.0.0.1", {"Connection: keep-alive"}, null))
r = read_http_response(c, srv, 5000)
check_contains("C04-03: resp-2 keep-alive", r, "keep-alive")
check_not_contains("C04-04: resp-2 no 408", r, "408 Request Timeout")

# Request 3 → max_keep_alive reached → Connection: close
c.write(http_req("GET", "/ka", "127.0.0.1", {"Connection: keep-alive"}, null))
r = read_http_response(c, srv, 5000)
check_contains("C04-05: resp-3 close", r, "close")
check_contains("C04-06: resp-3 200 OK", r, "200 OK")
check_not_contains("C04-07: resp-3 no 408", r, "408 Request Timeout")

# Request 4 → connection already closed by server
c.write(http_req("GET", "/ka", "127.0.0.1", {"Connection: keep-alive"}, null))
r = read_http_response(c, srv, 1000)
check("C04-08: req-4 gets no response", r.empty() || r.find("200 OK", 0) == -1)
check_eq("C04-09: exactly 3 handler calls", g_count, 3)

c.close()
srv.acceptor = null
srv = null

# ======================================================================
#  C05 — Request body: various Content-Length values
# ======================================================================
section("C05: request body sizes (single)")

reset_state()
p = alloc_port()
system.out.println("port=" + to_string(p))

srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 1, "max_body_size": 65536}.to_hash_map())
srv.bind_func("/body", echo_handler)
srv.listen(p)
drive_n(srv, 10)

# Zero-length body
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write(http_req("POST", "/body", "127.0.0.1:" + to_string(p), {"Connection: close"}, ""))
r = read_http_response(c, srv, 5000)
check_contains("C05-01: empty body 200", r, "200 OK")
check_eq("C05-02: empty body null", g_body == null || g_body.empty(), true)
c.close()
drive_n(srv, 5)

# Small body
reset_state()
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write(http_req("POST", "/body", "127.0.0.1:" + to_string(p), {"Connection: close"}, "ABC"))
r = read_http_response(c, srv, 5000)
check_contains("C05-03: small body 200", r, "200 OK")
check_eq("C05-04: body=ABC", g_body, "ABC")
c.close()
drive_n(srv, 5)

# 4KB body
reset_state()
var kb4 = new string
var i4 = 0
while i4 < 4096
    kb4 += "X"
    i4 += 1
end
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write(http_req("POST", "/body", "127.0.0.1:" + to_string(p), {"Connection: close"}, kb4))
r = read_http_response(c, srv, 5000)
check_contains("C05-05: 4KB body 200", r, "200 OK")
check_eq("C05-06: handler got 4096 bytes", g_body.size, 4096)
c.close()

srv.acceptor = null
srv = null

# ======================================================================
#  C06 — Concurrent connections (single)
# ======================================================================
section("C06: concurrent connections (single)")

reset_state()
p = alloc_port()
system.out.println("port=" + to_string(p))

srv = new netutils.http_server
srv.set_config({"thread_count": 2, "worker_count": 32}.to_hash_map())
srv.bind_func("/concurrent", echo_handler)
srv.listen(p)
drive_n(srv, 20)

var sockets = new array
var idx = 0
while idx < 8
    var sock = new tcp.socket
    sock.connect(tcp.endpoint("127.0.0.1", p))
    check("C06-01: socket-" + to_string(idx) + " connected", sock.is_open())
    sock.write(http_req("GET", "/concurrent", "127.0.0.1", {"Connection: close"}, null))
    sockets.push_back(sock)
    idx += 1
end

var start6 = runtime.time()
while g_count < 8 && runtime.time() - start6 < 5000
    drive(srv)
    runtime.delay(5)
end
check_eq("C06-02: all 8 concurrent handled", g_count, 8)

foreach s in sockets
    s.close()
end
srv.acceptor = null
srv = null

# ======================================================================
#  C07 — Error responses are Connection: close (single)
# ======================================================================
section("C07: error responses use Connection: close (single)")

reset_state()
p = alloc_port()
system.out.println("port=" + to_string(p))

srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
srv.listen(p)
drive_n(srv, 10)

c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("BOGUS * / HTTP/1.1\r\nHost: x\r\nConnection: keep-alive\r\n\r\n")
r = read_http_response(c, srv, 5000)
check_contains("C07-01: error response has Connection: close", r, "Connection: close")
c.close()

srv.acceptor = null
srv = null

# ======================================================================
#  C08 — bind_func vs bind_page vs wwwroot (single)
# ======================================================================
section("C08: routing priority (single)")

reset_state()
p = alloc_port()
system.out.println("port=" + to_string(p))

srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
# bind_func has highest priority
function exact_handler(srv2, sess)
    sess.send_response("200 OK", "exact-match", "text/plain")
end
srv.bind_func("/exact", exact_handler)

srv.listen(p)
drive_n(srv, 10)

# Exact function match
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write(http_req("GET", "/exact", "127.0.0.1:" + to_string(p), {"Connection: close"}, null))
r = read_http_response(c, srv, 5000)
check_contains("C08-01: bind_func exact match", r, "exact-match")
c.close()

srv.acceptor = null
srv = null

# ======================================================================
#  C09 — Custom error page binding (bind_code)
# ======================================================================
section("C09: custom error pages (single)")

reset_state()
p = alloc_port()
system.out.println("port=" + to_string(p))

srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
srv.bind_func("/ok", echo_handler)
function custom_403_handler(srv2, sess)
    sess.send_response("403 Forbidden", "custom-403-page", "text/html")
end
srv.bind_func("403 Forbidden", custom_403_handler)
srv.listen(p)
drive_n(srv, 10)

c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write(http_req("GET", "/nonexistent", "127.0.0.1:" + to_string(p), {"Connection: close"}, null))
r = read_http_response(c, srv, 5000)
check_contains("C09-01: custom 403 status", r, "403 Forbidden")
check_contains("C09-02: custom 403 body", r, "custom-403-page")
c.close()

srv.acceptor = null
srv = null

# ======================================================================
#  C10 — Request header handling (Host, Content-Length edge cases)
# ======================================================================
section("C10: request header handling (single)")

reset_state()
p = alloc_port()
system.out.println("port=" + to_string(p))

srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
srv.bind_func("/headers", echo_handler)
srv.listen(p)
drive_n(srv, 10)

# Missing Host header
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("GET /headers HTTP/1.1\r\nConnection: close\r\n\r\n")
r = read_http_response(c, srv, 5000)
# Host is optional in HTTP/1.1 per some interpretations, but many servers require it.
# This server creates the session anyway — just check it doesn't crash.
check("C10-01: survives missing Host", !r.empty())
c.close()
drive_n(srv, 5)

# Duplicate Content-Length → rejected (400)
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("POST /headers HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\nContent-Length: 5\r\nConnection: close\r\n\r\nbody")
r = read_http_response(c, srv, 5000)
check_contains("C10-02: duplicate Content-Length rejected", r, "400")
c.close()
drive_n(srv, 5)

# Content-Length mismatch (negative) → rejected
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("POST /headers HTTP/1.1\r\nHost: x\r\nContent-Length: -1\r\nConnection: close\r\n\r\n")
r = read_http_response(c, srv, 5000)
check_contains("C10-03: negative Content-Length rejected", r, "400")
c.close()

srv.acceptor = null
srv = null

# ======================================================================
#  C11 — Transfer-Encoding in request → rejected
# ======================================================================
section("C11: Transfer-Encoding request rejected (single)")

reset_state()
p = alloc_port()
system.out.println("port=" + to_string(p))

srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
srv.bind_func("/chunked", echo_handler)
srv.listen(p)
drive_n(srv, 10)

c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("POST /chunked HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n")
r = read_http_response(c, srv, 5000)
check_contains("C11-01: chunked request rejected", r, "400")
c.close()

srv.acceptor = null
srv = null

# ======================================================================
#  C12 — Keep-alive: client close & timeout (single)
# ======================================================================
section("C12: keep-alive client close & timeout (single)")

# --- C12a: client-requested Connection: close ---
reset_state()
p = alloc_port()
system.out.println("port=" + to_string(p))

srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 1, "max_keep_alive": 100, "keep_alive_timeout": 10000}.to_hash_map())
srv.bind_func("/cc", echo_handler)
srv.listen(p)
drive_n(srv, 10)

c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))

# Request 1: keep-alive
c.write(http_req("GET", "/cc", "127.0.0.1", {"Connection: keep-alive"}, null))
r = read_http_response(c, srv, 5000)
check_contains("C12-01: resp-1 keep-alive", r, "keep-alive")
check_contains("C12-02: resp-1 200 OK", r, "200 OK")

# Request 2: client asks to close
c.write(http_req("GET", "/cc", "127.0.0.1", {"Connection: close"}, null))
r = read_http_response(c, srv, 5000)
check_contains("C12-03: resp-2 Connection: close", r, "close")
check_contains("C12-04: resp-2 200 OK", r, "200 OK")
check_not_contains("C12-05: resp-2 no 408", r, "408 Request Timeout")

# Request 3: must fail — server already closed
c.write(http_req("GET", "/cc", "127.0.0.1", {"Connection: keep-alive"}, null))
r = read_http_response(c, srv, 1000)
check("C12-06: req-3 no response after client close", r.empty() || r.find("200 OK", 0) == -1)
check_eq("C12-07: handler called twice", g_count, 2)
c.close()
drive_n(srv, 5)

# --- C12b: keep-alive timeout ---
reset_state()
srv.acceptor = null
srv = null

p = alloc_port()
system.out.println("port=" + to_string(p))

srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 1, "max_keep_alive": 100, "keep_alive_timeout": 500}.to_hash_map())
srv.bind_func("/to", echo_handler)
srv.listen(p)
drive_n(srv, 10)

c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write(http_req("GET", "/to", "127.0.0.1", {"Connection: keep-alive"}, null))
r = read_http_response(c, srv, 5000)
check_contains("C12-08: first response 200 OK", r, "200 OK")

# Wait past the keep-alive timeout so server closes
system.out.println("C12: waiting for keep-alive timeout (500ms)...")
runtime.delay(800)
drive_n(srv, 20)

c.write(http_req("GET", "/to", "127.0.0.1", {"Connection: keep-alive"}, null))
r = read_http_response(c, srv, 1000)
check("C12-09: no response after timeout", r.empty() || r.find("200 OK", 0) == -1)
check_eq("C12-10: handler called once", g_count, 1)
c.close()

srv.acceptor = null
srv = null

# ======================================================================
#  C13 — Method semantics: HEAD, OPTIONS, no-body responses
# ======================================================================
section("C13: method semantics (single)")

reset_state()
p = alloc_port()
system.out.println("port=" + to_string(p))

srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
srv.bind_func("/methods", echo_handler)
srv.listen(p)
drive_n(srv, 10)

# HEAD — response must have no body but correct Content-Length
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write(http_req("HEAD", "/methods", "127.0.0.1:" + to_string(p), {"Connection: close"}, null))
r = read_http_response(c, srv, 5000)
check_contains("C13-01: HEAD 200 OK", r, "200 OK")
check_contains("C13-02: Content-Length present", r, "Content-Length: ")
check_eq("C13-03: handler saw HEAD", g_method, "HEAD")
c.close()
drive_n(srv, 5)

# DELETE
reset_state()
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write(http_req("DELETE", "/methods", "127.0.0.1:" + to_string(p), {"Connection: close"}, null))
r = read_http_response(c, srv, 5000)
check_contains("C13-04: DELETE 200 OK", r, "200 OK")
check_eq("C13-05: handler saw DELETE", g_method, "DELETE")
c.close()
drive_n(srv, 5)

# Unknown method (e.g. FOO) should still parse correctly
reset_state()
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("FOO /methods HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
r = read_http_response(c, srv, 5000)
check_contains("C13-06: unknown method still 200 OK", r, "200 OK")
c.close()

srv.acceptor = null
srv = null

# ======================================================================
#  C14 — URL handling: percent-encoding, special characters
# ======================================================================
section("C14: URL handling (single)")

reset_state()
p = alloc_port()
system.out.println("port=" + to_string(p))

srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 1}.to_hash_map())
srv.bind_func("/path/with%20spaces", echo_handler)
srv.bind_func("/path/%2525encoded", echo_handler)
srv.listen(p)
drive_n(srv, 10)

# Percent-encoded characters in URL — kept literal per RFC 3986; the raw
# request-line path is what the handler sees (no decoding by the server).
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("GET /path/with%20spaces HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
r = read_http_response(c, srv, 5000)
check_contains("C14-01: percent-encoded URL matched literally", r, "200 OK")
c.close()
drive_n(srv, 5)

# Double-encoded percent sign preserved as-is in the raw URL
reset_state()
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("GET /path/%2525encoded HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
r = read_http_response(c, srv, 5000)
check_contains("C14-02: double-encoded percent matched literally", r, "200 OK")
c.close()
drive_n(srv, 5)

# Query string with percent-encoded value
reset_state()
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("GET /path/with%20spaces?key=hello%20world HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
r = read_http_response(c, srv, 5000)
check_contains("C14-03: query string with encoded values", r, "200 OK")
c.close()

srv.acceptor = null
srv = null

# ======================================================================
#  C15 — Pipelining: multiple requests before reading responses
# ======================================================================
section("C15: pipelining (single)")

reset_state()
p = alloc_port()
system.out.println("port=" + to_string(p))

srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 1, "max_keep_alive": 10, "keep_alive_timeout": 10000}.to_hash_map())
srv.bind_func("/pipe", echo_handler)
srv.listen(p)
drive_n(srv, 10)

c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))

# Pipeline 3 requests before reading any response
var pl_req = http_req("GET", "/pipe?n=1", "127.0.0.1", {"Connection: keep-alive"}, null)
pl_req += http_req("GET", "/pipe?n=2", "127.0.0.1", {"Connection: keep-alive"}, null)
pl_req += http_req("GET", "/pipe?n=3", "127.0.0.1", {"Connection: close"}, null)
c.write(pl_req)

# Read responses in order
r = read_http_response(c, srv, 5000)
check_contains("C15-01: pipelined resp-1 200", r, "200 OK")
check_contains("C15-02: pipelined resp-1 body has path", r, "path=/pipe")

r = read_http_response(c, srv, 5000)
check_contains("C15-03: pipelined resp-2 200", r, "200 OK")
check_contains("C15-04: pipelined resp-2 body has path", r, "path=/pipe")

r = read_http_response(c, srv, 5000)
check_contains("C15-05: pipelined resp-3 200", r, "200 OK")
check_contains("C15-06: pipelined resp-3 body has path", r, "path=/pipe")
check_contains("C15-07: last response close", r, "close")

check_eq("C15-08: handler called 3 times", g_count, 3)
c.close()

srv.acceptor = null
srv = null

# ======================================================================
#  C16 — Edge cases: null bytes, oversized URL, empty body POST
# ======================================================================
section("C16: edge cases (single)")

reset_state()
p = alloc_port()
system.out.println("port=" + to_string(p))

srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 1, "max_body_size": 65536}.to_hash_map())
srv.bind_func("/edge", echo_handler)
srv.listen(p)
drive_n(srv, 10)

# Empty POST with Content-Length: 0
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("POST /edge HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
r = read_http_response(c, srv, 5000)
check_contains("C16-01: empty POST 200", r, "200 OK")
check_eq("C16-02: empty body in handler", g_body == null || g_body.empty(), true)
c.close()
drive_n(srv, 5)

# Double Host header — the second one should overwrite
reset_state()
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("GET /edge HTTP/1.1\r\nHost: first.example.com\r\nHost: second.example.com\r\nConnection: close\r\n\r\n")
r = read_http_response(c, srv, 5000)
check_contains("C16-03: double Host survives", r, "200 OK")
c.close()
drive_n(srv, 5)

# Very long URL (but within header limits)
reset_state()
var long_path = "/edge/"
var li = 0
while li < 200
    long_path += "a"
    li += 1
end
srv.bind_func(long_path, echo_handler)
drive_n(srv, 5)
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write(http_req("GET", long_path, "127.0.0.1:" + to_string(p), {"Connection: close"}, null))
r = read_http_response(c, srv, 5000)
check_contains("C16-04: long URL 200", r, "200 OK")
c.close()

srv.acceptor = null
srv = null

# ======================================================================
#  M01 — Master-slave: basic request/response round-trip
# ======================================================================
section("M01: master-slave basic round-trip")

reset_state()
var http_p = alloc_port()
var slave_p = alloc_port()
system.out.println("http=" + to_string(http_p) + " slave=" + to_string(slave_p))

var master = new netutils.http_server
master.set_config({"thread_count": 2, "worker_count": 2, "max_keep_alive": 100, "keep_alive_timeout": 10000}.to_hash_map())
master.bind_func("/api/echo", echo_handler)
master.set_master(slave_p)
master.listen(http_p)

var slave = new netutils.http_server
slave.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
slave.bind_func("/api/echo", echo_handler)
slave.set_slave("127.0.0.1", slave_p)

drive_ms_n(master, slave, 30)

c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", http_p))
check("M01-01: connected", c.is_open())

# GET
c.write(http_req("GET", "/api/echo", "127.0.0.1:" + to_string(http_p), {"Connection: close"}, null))
r = read_response_ms(c, master, slave, 5000)
check_contains("M01-02: 200 OK", r, "200 OK")
check_contains("M01-03: method=GET", r, "method=GET")
check_contains("M01-04: path=/api/echo", r, "path=/api/echo")
check_eq("M01-05: handler called", g_count, 1)
c.close()
drive_ms_n(master, slave, 10)

# POST with body
reset_state()
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", http_p))
c.write(http_req("POST", "/api/echo", "127.0.0.1:" + to_string(http_p), {"Connection: close"}, "ms-post-body"))
r = read_response_ms(c, master, slave, 5000)
check_contains("M01-06: POST 200", r, "200 OK")
check_contains("M01-07: body forwarded", r, "body=ms-post-body")
check_eq("M01-08: handler got body", g_body, "ms-post-body")
c.close()

slave.stop()
master.stop()
slave = null
master = null

# ======================================================================
#  M02 — Master-slave: keep-alive max & no stray 408
# ======================================================================
section("M02: master-slave keep-alive")

reset_state()
http_p = alloc_port()
slave_p = alloc_port()
system.out.println("http=" + to_string(http_p) + " slave=" + to_string(slave_p))

master = new netutils.http_server
master.set_config({"thread_count": 2, "worker_count": 2, "max_keep_alive": 2, "keep_alive_timeout": 10000}.to_hash_map())
master.bind_func("/ka", echo_handler)
master.set_master(slave_p)
master.listen(http_p)

slave = new netutils.http_server
slave.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
slave.bind_func("/ka", echo_handler)
slave.set_slave("127.0.0.1", slave_p)

drive_ms_n(master, slave, 30)

c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", http_p))

# Request 1 → keep-alive
c.write(http_req("GET", "/ka", "127.0.0.1", {"Connection: keep-alive"}, null))
r = read_response_ms(c, master, slave, 5000)
check_contains("M02-01: resp-1 keep-alive", r, "keep-alive")
check_not_contains("M02-02: resp-1 no 408", r, "408 Request Timeout")

# Request 2 → max_keep_alive=2, should be the last → Connection: close
c.write(http_req("GET", "/ka", "127.0.0.1", {"Connection: keep-alive"}, null))
r = read_response_ms(c, master, slave, 5000)
check_contains("M02-03: resp-2 close", r, "close")
check_contains("M02-04: resp-2 200 OK", r, "200 OK")
check_not_contains("M02-05: resp-2 no 408", r, "408 Request Timeout")

# Request 3 → should fail
c.write(http_req("GET", "/ka", "127.0.0.1", {"Connection: keep-alive"}, null))
r = read_response_ms(c, master, slave, 1000)
check("M02-06: req-3 gets no response", r.empty() || r.find("200 OK", 0) == -1)
check_eq("M02-07: exactly 2 handler calls", g_count, 2)

c.close()
slave.stop()
master.stop()
slave = null
master = null

# ======================================================================
#  M03 — Master-slave: error code propagation
# ======================================================================
section("M03: master-slave error propagation")

reset_state()
http_p = alloc_port()
slave_p = alloc_port()
system.out.println("http=" + to_string(http_p) + " slave=" + to_string(slave_p))

master = new netutils.http_server
master.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
master.bind_func("/ok", echo_handler)
master.set_master(slave_p)
master.listen(http_p)

slave = new netutils.http_server
slave.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
slave.bind_func("/ok", echo_handler)
slave.set_slave("127.0.0.1", slave_p)

drive_ms_n(master, slave, 30)

# Request to unmapped URL → slave returns the error via the framed
# protocol and the master delivers it to the client. The original
# status code (403, no wwwroot configured) must pass through intact
# instead of degrading to a generic 500.
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", http_p))
c.write(http_req("GET", "/no/route", "127.0.0.1:" + to_string(http_p), {"Connection: close"}, null))
r = read_response_ms(c, master, slave, 5000)
check("M03-01: error response received", !r.empty())
check("M03-02: response is HTTP", r.find("HTTP/", 0) != -1)
check_contains("M03-03: original status propagated", r, "403")
check_not_contains("M03-04: not degraded to 500", r, "500 Internal Server Error")
c.close()

slave.stop()
master.stop()
slave = null
master = null

# ======================================================================
#  M04 — Master-slave: concurrent requests
# ======================================================================
section("M04: master-slave concurrent")

reset_state()
http_p = alloc_port()
slave_p = alloc_port()
system.out.println("http=" + to_string(http_p) + " slave=" + to_string(slave_p))

master = new netutils.http_server
master.set_config({"thread_count": 2, "worker_count": 4, "max_keep_alive": 100, "keep_alive_timeout": 10000}.to_hash_map())
master.bind_func("/echo", echo_handler)
master.set_master(slave_p)
master.listen(http_p)

slave = new netutils.http_server
slave.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
slave.bind_func("/echo", echo_handler)
slave.set_slave("127.0.0.1", slave_p)

drive_ms_n(master, slave, 30)

var ms_sockets = new array
var j = 0
while j < 4
    var sock = new tcp.socket
    sock.connect(tcp.endpoint("127.0.0.1", http_p))
    check("M04-01: socket-" + to_string(j) + " connected", sock.is_open())
    sock.write(http_req("GET", "/echo", "127.0.0.1", {"Connection: close"}, null))
    ms_sockets.push_back(sock)
    j += 1
end

var ms_start = runtime.time()
while g_count < 4 && runtime.time() - ms_start < 5000
    drive_ms(master, slave)
    runtime.delay(5)
end
check_eq("M04-02: all 4 concurrent handled", g_count, 4)

foreach s in ms_sockets
    s.close()
end
slave.stop()
master.stop()
slave = null
master = null

# ======================================================================
#  M05 — Master-slave: POST body forwarding (various sizes)
# ======================================================================
section("M05: master-slave POST body")

reset_state()
http_p = alloc_port()
slave_p = alloc_port()
system.out.println("http=" + to_string(http_p) + " slave=" + to_string(slave_p))

master = new netutils.http_server
master.set_config({"thread_count": 2, "worker_count": 2, "max_keep_alive": 100, "keep_alive_timeout": 10000}.to_hash_map())
master.bind_func("/post", echo_handler)
master.set_master(slave_p)
master.listen(http_p)

slave = new netutils.http_server
slave.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
slave.bind_func("/post", echo_handler)
slave.set_slave("127.0.0.1", slave_p)

drive_ms_n(master, slave, 30)

# Small POST
var body_small = "name=cov"
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", http_p))
c.write(http_req("POST", "/post", "127.0.0.1:" + to_string(http_p), {"Connection: close"}, body_small))
r = read_response_ms(c, master, slave, 5000)
check_contains("M05-01: small POST 200", r, "200 OK")
check_contains("M05-02: body forwarded", r, "body=" + body_small)
check_eq("M05-03: handler body", g_body, body_small)
c.close()
drive_ms_n(master, slave, 10)

# 2KB POST
reset_state()
var body_2k = new string
var k = 0
while k < 2048
    body_2k += "Y"
    k += 1
end
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", http_p))
c.write(http_req("POST", "/post", "127.0.0.1:" + to_string(http_p), {"Connection: close"}, body_2k))
r = read_response_ms(c, master, slave, 5000)
check_contains("M05-04: 2KB POST 200", r, "200 OK")
check_eq("M05-05: handler body size 2048", g_body.size, 2048)
c.close()

slave.stop()
master.stop()
slave = null
master = null

# ======================================================================
#  M06 — Master-slave: slave disconnect, master survives
# ======================================================================
section("M06: master-slave slave disconnect")

reset_state()
http_p = alloc_port()
slave_p = alloc_port()
system.out.println("http=" + to_string(http_p) + " slave=" + to_string(slave_p))

master = new netutils.http_server
master.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
master.bind_func("/echo", echo_handler)
master.set_master(slave_p)
master.listen(http_p)

slave = new netutils.http_server
slave.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
slave.bind_func("/echo", echo_handler)
slave.set_slave("127.0.0.1", slave_p)

drive_ms_n(master, slave, 30)

# Verify working state
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", http_p))
c.write(http_req("GET", "/echo", "127.0.0.1:" + to_string(http_p), {"Connection: close"}, null))
r = read_response_ms(c, master, slave, 5000)
check_contains("M06-01: pre-disconnect 200", r, "200 OK")
c.close()

# Kill slave
slave.stop()
slave = null
runtime.delay(200)
drive_n(master, 20)

# Master must still accept TCP
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", http_p))
check("M06-02: master still accepts after slave death", c.is_open())
c.close()

master.stop()
master = null

# ======================================================================
#  M07 — Master-slave: client close & timeout
# ======================================================================
section("M07: master-slave client close & timeout")

# --- M07a: client-requested close ---
reset_state()
http_p = alloc_port()
slave_p = alloc_port()
system.out.println("http=" + to_string(http_p) + " slave=" + to_string(slave_p))

master = new netutils.http_server
master.set_config({"thread_count": 2, "worker_count": 2, "max_keep_alive": 100, "keep_alive_timeout": 10000}.to_hash_map())
master.bind_func("/ms-cc", echo_handler)
master.set_master(slave_p)
master.listen(http_p)

slave = new netutils.http_server
slave.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
slave.bind_func("/ms-cc", echo_handler)
slave.set_slave("127.0.0.1", slave_p)

drive_ms_n(master, slave, 30)

c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", http_p))

# Request 1: keep-alive
c.write(http_req("GET", "/ms-cc", "127.0.0.1", {"Connection: keep-alive"}, null))
r = read_response_ms(c, master, slave, 5000)
check_contains("M07-01: resp-1 keep-alive", r, "keep-alive")
check_not_contains("M07-02: resp-1 no 408", r, "408 Request Timeout")

# Request 2: client close
c.write(http_req("GET", "/ms-cc", "127.0.0.1", {"Connection: close"}, null))
r = read_response_ms(c, master, slave, 5000)
check_contains("M07-03: resp-2 close", r, "close")
check_not_contains("M07-04: resp-2 no 408", r, "408 Request Timeout")

# Request 3: must fail
c.write(http_req("GET", "/ms-cc", "127.0.0.1", {"Connection: keep-alive"}, null))
r = read_response_ms(c, master, slave, 1000)
check("M07-05: req-3 no response", r.empty() || r.find("200 OK", 0) == -1)
check_eq("M07-06: handler called twice", g_count, 2)
c.close()

slave.stop()
master.stop()
slave = null
master = null

# --- M07b: keep-alive timeout ---
reset_state()
http_p = alloc_port()
slave_p = alloc_port()
system.out.println("http=" + to_string(http_p) + " slave=" + to_string(slave_p))

master = new netutils.http_server
master.set_config({"thread_count": 2, "worker_count": 2, "max_keep_alive": 100, "keep_alive_timeout": 500}.to_hash_map())
master.bind_func("/ms-to", echo_handler)
master.set_master(slave_p)
master.listen(http_p)

slave = new netutils.http_server
slave.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
slave.bind_func("/ms-to", echo_handler)
slave.set_slave("127.0.0.1", slave_p)

drive_ms_n(master, slave, 30)

c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", http_p))
c.write(http_req("GET", "/ms-to", "127.0.0.1", {"Connection: keep-alive"}, null))
r = read_response_ms(c, master, slave, 5000)
check_contains("M07-07: first response 200 OK", r, "200 OK")

system.out.println("M07: waiting for keep-alive timeout (500ms)...")
runtime.delay(800)
drive_ms_n(master, slave, 20)

c.write(http_req("GET", "/ms-to", "127.0.0.1", {"Connection: keep-alive"}, null))
r = read_response_ms(c, master, slave, 1000)
check("M07-08: no response after timeout", r.empty() || r.find("200 OK", 0) == -1)
check_eq("M07-09: handler called once", g_count, 1)
c.close()

slave.stop()
master.stop()
slave = null
master = null

# ======================================================================
#  M08 — Master-slave: pipelining
# ======================================================================
section("M08: master-slave pipelining")

reset_state()
http_p = alloc_port()
slave_p = alloc_port()
system.out.println("http=" + to_string(http_p) + " slave=" + to_string(slave_p))

master = new netutils.http_server
master.set_config({"thread_count": 2, "worker_count": 4, "max_keep_alive": 10, "keep_alive_timeout": 10000}.to_hash_map())
master.bind_func("/pipe", echo_handler)
master.set_master(slave_p)
master.listen(http_p)

slave = new netutils.http_server
slave.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
slave.bind_func("/pipe", echo_handler)
slave.set_slave("127.0.0.1", slave_p)

drive_ms_n(master, slave, 30)

c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", http_p))

var ms_pl = http_req("GET", "/pipe?n=a", "127.0.0.1", {"Connection: keep-alive"}, null)
ms_pl += http_req("GET", "/pipe?n=b", "127.0.0.1", {"Connection: keep-alive"}, null)
ms_pl += http_req("GET", "/pipe?n=c", "127.0.0.1", {"Connection: close"}, null)
c.write(ms_pl)

r = read_response_ms(c, master, slave, 5000)
check_contains("M08-01: resp-1 200", r, "200 OK")
check_contains("M08-02: resp-1 body", r, "path=/pipe")

r = read_response_ms(c, master, slave, 5000)
check_contains("M08-03: resp-2 200", r, "200 OK")
check_contains("M08-04: resp-2 body", r, "path=/pipe")

r = read_response_ms(c, master, slave, 5000)
check_contains("M08-05: resp-3 200", r, "200 OK")
check_contains("M08-06: resp-3 body", r, "path=/pipe")
check_contains("M08-07: last response close", r, "close")

check_eq("M08-08: handler called 3 times", g_count, 3)
c.close()

slave.stop()
master.stop()
slave = null
master = null

# ======================================================================
#  M09 — Master-slave: HEAD method
# ======================================================================
section("M09: master-slave HEAD method")

reset_state()
http_p = alloc_port()
slave_p = alloc_port()
system.out.println("http=" + to_string(http_p) + " slave=" + to_string(slave_p))

master = new netutils.http_server
master.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
master.bind_func("/head-test", echo_handler)
master.set_master(slave_p)
master.listen(http_p)

slave = new netutils.http_server
slave.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
slave.bind_func("/head-test", echo_handler)
slave.set_slave("127.0.0.1", slave_p)

drive_ms_n(master, slave, 30)

c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", http_p))
c.write(http_req("HEAD", "/head-test", "127.0.0.1:" + to_string(http_p), {"Connection: close"}, null))
r = read_response_ms(c, master, slave, 5000)
check_contains("M09-01: HEAD 200", r, "200 OK")
check_contains("M09-02: Content-Length present", r, "Content-Length: ")
check_eq("M09-03: handler saw HEAD", g_method, "HEAD")
c.close()

slave.stop()
master.stop()
slave = null
master = null

# ======================================================================
# Results
# ======================================================================
section("Results")
system.out.println("")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
