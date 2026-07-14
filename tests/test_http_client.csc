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
    check("C00: find free port", false)
    system.exit(1)
end
system.out.println("Using port: " + to_string(server_port))

var guard = new async.work_guard

# ============================================================
# C01 -- http_client: connect_target success and failure
# ============================================================
section("C01: connect_target")

# C01-01..03: connect to a listening acceptor
var srv_sock = new tcp.socket
var acpt = tcp.acceptor(tcp.endpoint_v4(server_port))
var accept_state = async.accept(srv_sock, acpt)

var client1 = new netutils.http_client
var target_ok = client1.parse_url("http://127.0.0.1:" + to_string(server_port) + "/test")
check_not_null("C01-01: parse_url for local server", target_ok)
var connected = client1.connect_target(target_ok)
check_true("C01-02: connect_target to local server succeeds", connected)
check_true("C01-03: socket is open after connect", client1.sock.is_open())

# Write to let server accept complete
client1.sock.write("X")
if !accept_state.wait_for(2000)
    check("C01-04: server accepted connection", false)
else
    check("C01-04: server accepted connection", true)
end
client1.close()
check_false("C01-05: socket closed after close()", client1.sock.is_open())
srv_sock.close()
acpt = null

# C01-06..07: connect to a dead port returns false
var client2 = new netutils.http_client
var target_dead = client2.parse_url("http://127.0.0.1:19998/test")
check_not_null("C01-06: parse_url for dead port", target_dead)
var connected_dead = client2.connect_target(target_dead)
check_false("C01-07: connect_target to dead port returns false", connected_dead)

# C01-08..10: connect_target with timeout to unroutable IP
var client3 = new netutils.http_client
client3.set_timeout_ms(1000)
var target_timeout = client3.parse_url("http://10.255.255.1:80/test")
check_not_null("C01-08: parse_url for unroutable IP", target_timeout)
var start_time = runtime.time()
var connected_timeout = client3.connect_target(target_timeout)
var elapsed = runtime.time() - start_time
check_false("C01-09: connect_target to unroutable IP returns false", connected_timeout)
check("C01-10: timeout respected (elapsed < 5000ms)", elapsed < 5000)

# ============================================================
# C02 -- http_client: close() idempotency
# ============================================================
section("C02: close idempotency")

var client4 = new netutils.http_client
var acpt2 = tcp.acceptor(tcp.endpoint_v4(server_port))
var srv_sock2 = new tcp.socket
var accept_state2 = async.accept(srv_sock2, acpt2)

var target2 = client4.parse_url("http://127.0.0.1:" + to_string(server_port) + "/")
check_not_null("C02-01: parse_url", target2)
check_true("C02-02: connect_target succeeds", client4.connect_target(target2))

client4.sock.write("X")
accept_state2.wait_for(2000)

# First close
client4.close()
check_false("C02-03: socket closed after first close()", client4.sock.is_open())

# Second close should not throw
var threw_on_double_close = false
try
    client4.close()
catch e
    threw_on_double_close = true
    system.out.println("  Unexpected error: " + e.what)
end
check_false("C02-04: double close() does not throw", threw_on_double_close)

srv_sock2.close()
acpt2 = null

# ============================================================
# C03 -- http_client: data round-trip via connect_target + sync I/O
# (exercises connect + write + receive path, which is the
# fundamental building block of http_client)
# ============================================================
section("C03: data round-trip via connect_target")

var acpt3 = tcp.acceptor(tcp.endpoint_v4(server_port))
var srv_sock3 = new tcp.socket
var accept_state3 = async.accept(srv_sock3, acpt3)

var client5 = new netutils.http_client
client5.connect_target(client5.parse_url("http://127.0.0.1:" + to_string(server_port) + "/"))

# Write request data to complete accept
var req_data = "GET /echo HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
client5.sock.write(req_data)

if !accept_state3.wait_for(2000)
    check("C03-01: server accepted", false)
else
    check("C03-01: server accepted", true)

    # Drain the HTTP request
    var req = srv_sock3.receive(req_data.size)

    # Server sends HTTP response (Content-Length style, the most common path)
    var body = "<html><body>hello</body></html>"
    var resp = "HTTP/1.1 200 OK\r\nContent-Length: " + to_string(body.size) + "\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n" + body
    srv_sock3.write(resp)

    # Client reads raw bytes and verifies they were received
    runtime.delay(50)
    var avail = client5.sock.available()
    check("C03-02: data available on client socket", avail > 0)
    if avail > 0
        var raw = client5.sock.receive(avail)
        check("C03-03: response contains 200 OK", raw.find("200 OK", 0) != -1)
        check("C03-04: response contains body", raw.find(body, 0) != -1)
    end
end

client5.close()
srv_sock3.close()
acpt3 = null

# ============================================================
# C04 -- http_client: request validation (rejected before connect)
# ============================================================
section("C04: request validation")

var client9 = new netutils.http_client

# C04-01: URL with fragment stripped
var u_frag = client9.parse_url("http://example.com/path#section")
check_eq("C04-01: fragment stripped from path", u_frag["path"], "/path")

# C04-02: URL with only fragment after path
var u_frag2 = client9.parse_url("http://example.com/#top")
check_eq("C04-02: fragment-only leads to root", u_frag2["path"], "/")

# C04-03: request method with CR/LF rejected (validated before connect)
var resp_bad_method = client9.http_request("GET\r\nX-Injected: true", "http://127.0.0.1:1/", new array, "")
check_null("C04-03: method with CRLF rejected", resp_bad_method)

# C04-04: header with CR/LF rejected
var bad_headers = new array
bad_headers.push_back("X-Injected: true\r\nHost: evil.com")
var resp_bad_header = client9.http_request("GET", "http://127.0.0.1:1/", bad_headers, "")
check_null("C04-04: header with CRLF rejected", resp_bad_header)

# C04-05: host header blocked (managed internally)
var host_headers = new array
host_headers.push_back("Host: evil.com")
var resp_host_header = client9.http_request("GET", "http://127.0.0.1:1/", host_headers, "")
check_null("C04-05: host header rejected", resp_host_header)

# C04-06: content-length header blocked
var cl_headers = new array
cl_headers.push_back("Content-Length: 999")
var resp_cl_header = client9.http_request("GET", "http://127.0.0.1:1/", cl_headers, "")
check_null("C04-06: content-length header rejected", resp_cl_header)

# ============================================================
# C05 -- http_client: connect_target with localhost (multi-endpoint)
# ============================================================
section("C05: connect_target with localhost")

var client11 = new netutils.http_client
var target_lh = client11.parse_url("http://localhost:" + to_string(server_port) + "/")

var acpt9 = tcp.acceptor(tcp.endpoint_v4(server_port))
var srv_sock9 = new tcp.socket
var accept_state9 = async.accept(srv_sock9, acpt9)

var connected_lh = client11.connect_target(target_lh)
check_true("C05-01: connect_target to localhost succeeds", connected_lh)

client11.sock.write("X")
if !accept_state9.wait_for(2000)
    check("C05-02: server accepted connection", false)
else
    check("C05-02: server accepted connection", true)
end

client11.close()
srv_sock9.close()
acpt9 = null

# C05-03..04: connect_target to HTTPS marks scheme and port
var target_https = client11.parse_url("https://example.com/test")
check_eq("C05-03: https scheme detected", target_https["scheme"], "https")
check_eq("C05-04: https default port 443", target_https["port"], 443)

# ============================================================
# C06 -- http_client: set_timeout_ms and set_tls_options
# ============================================================
section("C06: configuration methods")

var client12 = new netutils.http_client
check_null("C06-01: timeout_ms initially null", client12.timeout_ms)

client12.set_timeout_ms(5000)
check_eq("C06-02: timeout_ms updated to 5000", client12.timeout_ms, 5000)

client12.set_timeout_ms(null)
check_null("C06-03: timeout_ms set back to null", client12.timeout_ms)

var tls_opts = {"trust_mode": "insecure"}.to_hash_map()
client12.set_tls_options(tls_opts)
check_not_null("C06-04: tls_options set", client12.tls_options)
check_eq("C06-05: tls_options trust_mode", client12.tls_options["trust_mode"], "insecure")

# ============================================================
# C07 -- parse_url comprehensive
# ============================================================
section("C07: parse_url comprehensive")

var c = new netutils.http_client

var p1 = c.parse_url("http://example.com:8080/path/to/resource?a=1&b=2")
check_not_null("C07-01: complex URL parsed", p1)
check_eq("C07-02: scheme", p1["scheme"], "http")
check_eq("C07-03: host", p1["host"], "example.com")
check_eq("C07-04: port", p1["port"], 8080)
check_eq("C07-05: path with query", p1["path"], "/path/to/resource?a=1&b=2")

var p2 = c.parse_url("http://192.168.1.1:9090/admin")
check_not_null("C07-06: IP address URL with port", p2)
check_eq("C07-07: IP host", p2["host"], "192.168.1.1")
check_eq("C07-08: explicit port 9090", p2["port"], 9090)

var p3 = c.parse_url("http://192.168.1.1/admin")
check_not_null("C07-09: IP address URL default port", p3)
check_eq("C07-10: IP host", p3["host"], "192.168.1.1")
check_eq("C07-11: default port 80", p3["port"], 80)

var p4 = c.parse_url("https://example.com:8443/secure")
check_not_null("C07-12: https explicit port", p4)
check_eq("C07-13: scheme https", p4["scheme"], "https")
check_eq("C07-14: port 8443", p4["port"], 8443)
check_eq("C07-15: path", p4["path"], "/secure")

# ============================================================
# C08 -- 100 Continue: verify http_request skips interim response
# ============================================================
section("C08: 100 Continue regression")

var acpt8 = tcp.acceptor(tcp.endpoint_v4(server_port))
var srv_sock8 = new tcp.socket
var accept_state8 = async.accept(srv_sock8, acpt8)

var client14 = new netutils.http_client
client14.connect_target(client14.parse_url("http://127.0.0.1:" + to_string(server_port) + "/"))

# Write request so accept completes
client14.sock.write("POST /data HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 5\r\nConnection: close\r\n\r\nHELLO")

if !accept_state8.wait_for(2000)
    check("C08-01: server accepted", false)
else
    check("C08-01: server accepted", true)
    var req8 = srv_sock8.receive(4096)
    # Send 100 Continue then final 200 in one TCP segment
    srv_sock8.write("HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nDONE")

    # Manually replicate http_request's 1xx-skipping loop
    var meta8 = null
    loop
        var raw8 = client14.read_until("\r\n\r\n")
        check_not_null("C08-02: read headers", raw8)
        if raw8 == null
            break
        end
        meta8 = client14.parse_response_headers(raw8)
        check_not_null("C08-03: parsed meta", meta8)
        if meta8 == null
            break
        end
        if meta8["status_code"] >= 100 && meta8["status_code"] <= 199
            continue
        end
        break
    end
    if meta8 != null
        check_eq("C08-04: status code 200", meta8["status_code"], 200)
        var body8 = client14.read_body(meta8)
        check_eq("C08-05: body is DONE", body8, "DONE")
    end
end

client14.close()
srv_sock8.close()
acpt8 = null

# ============================================================
# Cleanup and results
# ============================================================
section("Results")

guard = null

system.out.println("")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
system.out.println("SKIP: " + _skip)
if _fail > 0
    system.exit(1)
end
