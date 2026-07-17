import netutils
import network.tcp as tcp
import network.async as async

# ============================================================================
# Stress test: single-process keep-alive lifecycle
#
#   Phase 1 — connection churn: many keep-alive connections driven to the
#             max_keep_alive limit; every response must be 200 and the
#             final one must advertise Connection: close
#   Phase 2 — slow-loris: a request delivered one byte at a time must still
#             parse; a half-request that stalls past keep_alive_timeout
#             must be rejected (408) and the connection closed
#   Phase 3 — RST bombardment: rounds of send-then-close must not wedge the
#             server; a normal request must succeed after every round
# ============================================================================

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

var _next_port = 16300

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

# Minimal response reader: returns raw bytes read until the header block is
# complete (plus whatever body arrived with it), the peer closes, or timeout.
function read_headers(client, server, timeout_ms)
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
            if client.peer_closed()
                break
            end
        end
        drive(server)
        runtime.delay(2)
    end
    return buf
end

function http_req(path, conn_hdr)
    return "GET " + path + " HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: " + conn_hdr + "\r\n\r\n"
end

var g_count = 0

function echo_handler(srv, session)
    g_count += 1
    session.send_response("200 OK", "ok", "text/plain")
end

# ----------------------------------------------------------------------
# Phase 1: keep-alive connection churn
# ----------------------------------------------------------------------
section("S1: keep-alive churn to the max_keep_alive limit")

g_count = 0
var p = alloc_port()
var srv = new netutils.http_server
srv.set_config({"thread_count": 2, "worker_count": 8, "max_keep_alive": 8, "keep_alive_timeout": 10000}.to_hash_map())
srv.bind_func("/churn", echo_handler)
srv.listen(p)
drive_n(srv, 10)

var conn_num = 0
var churn_ok = true
while conn_num < 6
    conn_num += 1
    var c = new tcp.socket
    c.connect(tcp.endpoint("127.0.0.1", p))
    var req_num = 0
    while req_num < 8
        req_num += 1
        c.write(http_req("/churn", "keep-alive"))
        var r = read_headers(c, srv, 5000)
        if r.find("200 OK", 0) == -1
            churn_ok = false
            system.out.println("  conn " + conn_num + " req " + req_num + ": no 200 (got " + r.size + " bytes)")
            break
        end
        # The final response on the connection must advertise the close
        if req_num == 8 && r.find("Connection: close", 0) == -1
            churn_ok = false
            system.out.println("  conn " + conn_num + " req 8: missing Connection: close")
        end
    end
    c.close()
    drive_n(srv, 5)
end
check("S1-01: 6 connections x 8 requests all served", churn_ok && g_count == 48)

srv.acceptor = null
srv = null

# ----------------------------------------------------------------------
# Phase 2: slow-loris
# ----------------------------------------------------------------------
section("S2: slow-loris parsing and timeout enforcement")

g_count = 0
p = alloc_port()
srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 2, "max_keep_alive": 100, "keep_alive_timeout": 500}.to_hash_map())
srv.bind_func("/slow", echo_handler)
srv.listen(p)
drive_n(srv, 10)

# 2a: a byte-at-a-time request must still parse (total delivery well under
# the 500ms budget)
var c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
var req = http_req("/slow", "close")
var bi = 0
while bi < req.size
    c.write(req.substr(bi, 1))
    drive(srv)
    bi += 1
end
var r = read_headers(c, srv, 5000)
check("S2-01: byte-at-a-time request served", r.find("200 OK", 0) != -1)
c.close()
drive_n(srv, 5)

# 2b: a half-request that stalls past keep_alive_timeout must be rejected
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("GET /slow HTTP/1.1\r\nHost: 127.0.")
var stall_start = runtime.time()
while runtime.time() - stall_start < 800
    drive(srv)
    runtime.delay(10)
end
r = read_headers(c, srv, 2000)
# Server must have given up: either a 408 response or a plain close
check("S2-02: stalled half-request rejected (408 or closed)", r.find("408", 0) != -1 || c.peer_closed())
check("S2-03: stalled request never reached a handler", g_count == 1)
c.close()

srv.acceptor = null
srv = null

# ----------------------------------------------------------------------
# Phase 3: RST bombardment
# ----------------------------------------------------------------------
section("S3: RST bombardment between normal requests")

g_count = 0
p = alloc_port()
srv = new netutils.http_server
srv.set_config({"thread_count": 2, "worker_count": 8, "max_keep_alive": 100, "keep_alive_timeout": 10000}.to_hash_map())
srv.bind_func("/rst", echo_handler)
srv.listen(p)
drive_n(srv, 10)

var round = 0
var healthy = true
while round < 10
    round += 1
    # Bombard: send a request and slam the connection shut immediately
    var k = 0
    while k < 4
        var b = new tcp.socket
        b.connect(tcp.endpoint("127.0.0.1", p))
        b.write(http_req("/rst", "keep-alive"))
        b.close()
        drive_n(srv, 2)
        k += 1
    end
    drive_n(srv, 10)
    # The server must still serve a well-behaved client
    var c2 = new tcp.socket
    c2.connect(tcp.endpoint("127.0.0.1", p))
    c2.write(http_req("/rst", "close"))
    var r2 = read_headers(c2, srv, 5000)
    if r2.find("200 OK", 0) == -1
        healthy = false
        system.out.println("  round " + round + ": healthy client got no 200")
    end
    c2.close()
    drive_n(srv, 5)
end
check("S3-01: server healthy through 10 RST rounds", healthy)

srv.acceptor = null
srv = null

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
