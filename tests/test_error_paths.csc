import netutils
import network.tcp as tcp
import network.async as async

# ============================================================================
# Error-path test: verify that failures produce the EXPECTED errors
#
#   E1 — wire shape of every server error response (status line, mandatory
#        Connection: close / Content-Length: 0, and the full-header shape
#        of routing errors that travel through session.send_response)
#   E2 — expected log messages: netutils.log_stream captures the error
#        text emitted by each failure path (also guards the catch-block
#        message concatenation — a broken log() call crashes this test)
#   E3 — master handshake robustness: garbage bytes on the slave port must
#        be rejected with a logged handshake error, exercising the
#        receive_content_s exception path, and a real slave must still be
#        able to attach afterwards
#   E4 — http_client negative API: malformed / unsupported URLs and dead
#        ports must return null, never throw
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

function check_contains(label, haystack, needle)
    var ok = haystack != null && haystack.find(needle, 0) != -1
    if !ok
        system.out.println("  expected to contain: " + needle)
    end
    check(label, ok)
end

var _next_port = 16700

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

function drive_ms(master, slave)
    master.poll()
    if slave != null
        slave.poll()
    end
    async.poll_once()
end

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

var g_count = 0

function echo_handler(srv, session)
    g_count += 1
    session.send_response("200 OK", "ok", "text/plain")
end

# Capture netutils error logs for the whole test run
var log_path = "build/test_error_paths.log"
var log_file = iostream.fstream(log_path, iostream.openmode.out)
netutils.log_stream = log_file

# ----------------------------------------------------------------------
# E1: wire shape of server error responses
# ----------------------------------------------------------------------
section("E1: error response wire shape")

var p = alloc_port()
var srv = new netutils.http_server
srv.set_config({"thread_count": 1, "worker_count": 4, "max_body_size": 100, "max_keep_alive": 100, "keep_alive_timeout": 500}.to_hash_map())
srv.listen(p)
drive_n(srv, 10)

# 400 — malformed request line (minimal compose_response shape)
var c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("GARBAGE\r\n\r\n")
var r = read_headers(c, srv, 5000)
check_contains("E1-01: 400 status line", r, "HTTP/1.1 400 Bad Request")
check_contains("E1-02: 400 Connection: close", r, "Connection: close")
check_contains("E1-03: 400 Content-Length: 0", r, "Content-Length: 0")
c.close()
drive_n(srv, 5)

# 403 — no route: travels through session.send_response, so it must carry
# the full header set (Date/Server) in addition to the close markers
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("GET /no/route HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: keep-alive\r\n\r\n")
r = read_headers(c, srv, 5000)
check_contains("E1-04: 403 status line", r, "HTTP/1.1 403 Forbidden")
check_contains("E1-05: 403 Connection: close", r, "Connection: close")
check_contains("E1-06: 403 Content-Length: 0", r, "Content-Length: 0")
check_contains("E1-07: 403 carries Server header", r, "Server: " + netutils.server_name + "/" + netutils.server_version)
check_contains("E1-08: 403 carries Date header", r, "Date: ")
c.close()
drive_n(srv, 5)

# 413 — body larger than max_body_size (100)
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
var big = new string
var bi = 0
while bi < 200
    big += "x"
    bi += 1
end
c.write("POST /x HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 200\r\nConnection: close\r\n\r\n" + big)
r = read_headers(c, srv, 5000)
check_contains("E1-09: 413 status line", r, "HTTP/1.1 413 Payload Too Large")
check_contains("E1-10: 413 Connection: close", r, "Connection: close")
c.close()
drive_n(srv, 5)

# 431 — header line beyond http_max_header_line_size
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
var huge = "GET /x HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Big: "
var hi = 0
while hi < 10000
    huge += "A"
    hi += 1
end
huge += "\r\nConnection: close\r\n\r\n"
c.write(huge)
r = read_headers(c, srv, 5000)
check_contains("E1-11: 431 status line", r, "HTTP/1.1 431 Request Header Fields Too Large")
check_contains("E1-12: 431 Connection: close", r, "Connection: close")
c.close()
drive_n(srv, 5)

# 408 — half a request, then silence past keep_alive_timeout (500ms)
c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", p))
c.write("GET /x HTTP/1.1\r\nHost: 127.0.")
var stall = runtime.time()
while runtime.time() - stall < 800
    drive(srv)
    runtime.delay(10)
end
r = read_headers(c, srv, 2000)
check_contains("E1-13: 408 status line", r, "HTTP/1.1 408 Request Timeout")
check_contains("E1-14: 408 Connection: close", r, "Connection: close")
c.close()

srv.acceptor = null
srv = null

# ----------------------------------------------------------------------
# E2: expected log messages for each failure path
# ----------------------------------------------------------------------
section("E2: error log text")

log_file.flush()
var logdata = ""
var ifs = iostream.fstream(log_path, iostream.openmode.in)
while ifs.good()
    logdata += ifs.getline() + "\n"
end
ifs = null

check_contains("E2-01: parse error logged", logdata, "Parse request header error.")
check_contains("E2-02: body-too-large logged", logdata, "Request body too large")
check_contains("E2-03: header-limit logged", logdata, "Header limit exceeded")
check_contains("E2-04: keep-alive timeout logged", logdata, "Keep-alive timeout")

# ----------------------------------------------------------------------
# E3: master handshake robustness against garbage
# ----------------------------------------------------------------------
section("E3: master handshake rejects garbage")

g_count = 0
var http_p = alloc_port()
var slave_p = alloc_port()

var master = new netutils.http_server
master.set_config({"thread_count": 2, "worker_count": 2, "heartbeat_interval": 200, "slave_spawn_timeout": 300, "slave_keep_alive_timeout": 2000}.to_hash_map())
master.bind_func("/echo", echo_handler)
master.set_master(slave_p)
master.listen(http_p)
drive_ms(master, null)

# 3a: raw non-frame garbage — from_fixed_hex must fail inside
# receive_content_s and the master must log a handshake failure
var raw = new tcp.socket
raw.connect(tcp.endpoint("127.0.0.1", slave_p))
raw.write("THIS IS NOT A VALID FRAME AT ALL................")
var wd = 0
while wd < 60
    drive_ms(master, null)
    runtime.delay(10)
    wd += 1
end
raw.close()

# 3b: well-formed frame with a bogus handshake payload
raw = new tcp.socket
raw.connect(tcp.endpoint("127.0.0.1", slave_p))
# frame = 16-hex-digit length prefix + payload ("BOGUS 9.9 0" = 11 bytes)
raw.write("000000000000000b" + "BOGUS 9.9 0")
wd = 0
while wd < 60
    drive_ms(master, null)
    runtime.delay(10)
    wd += 1
end
raw.close()

log_file.flush()
logdata = ""
ifs = iostream.fstream(log_path, iostream.openmode.in)
while ifs.good()
    logdata += ifs.getline() + "\n"
end
ifs = null
check_contains("E3-01: handshake failure logged", logdata, "Handshake")

# 3c: a real slave must still be able to attach and serve
var slave = new netutils.http_server
slave.set_config({"thread_count": 2, "worker_count": 2, "heartbeat_interval": 200, "slave_keep_alive_timeout": 2000}.to_hash_map())
slave.bind_func("/echo", echo_handler)
slave.set_slave("127.0.0.1", slave_p)

c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", http_p))
c.write("GET /echo HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
var start = runtime.time()
var buf = ""
while buf.find("200 OK", 0) == -1 && runtime.time() - start < 8000
    var n = c.available()
    if n > 0
        var chunk = c.receive(n)
        if chunk != null && !chunk.empty()
            buf += chunk
        end
    end
    drive_ms(master, slave)
    runtime.delay(2)
end
check_contains("E3-02: real slave attaches after garbage peers", buf, "200 OK")
check("E3-03: handler executed once", g_count == 1)
c.close()

slave.stop()
master.stop()
slave = null
master = null

# ----------------------------------------------------------------------
# E4: http_client negative API
# ----------------------------------------------------------------------
section("E4: http_client negative API")

var client = new netutils.http_client
check("E4-01: parse_url rejects garbage", client.parse_url("not a url") == null)
check("E4-02: parse_url rejects unsupported scheme", client.parse_url("ftp://host/x") == null)

var dead_p = alloc_port()
var resp = client.http_request("GET", "http://127.0.0.1:" + to_string(dead_p) + "/x", {}.to_hash_map(), "")
check("E4-03: http_request to dead port returns null", resp == null)

var resp2 = client.http_request("GET", "definitely not a url", {}.to_hash_map(), "")
check("E4-04: http_request with bad URL returns null", resp2 == null)

netutils.log_stream = null
log_file = null

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
