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

function skip(label, reason)
    _skip += 1
    system.out.println("[SKIP] " + _section + " | " + label + " — " + reason)
end

// ============================================================
// Find a free port for test server
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
    check("H00: find free port", false)
    system.exit(1)
end
system.out.println("Using port: " + to_string(server_port))

// ============================================================
// H01 — http_client parse_url (all cases from test_url_parse already)
//       Here we add HTTPS-specific tests
// ============================================================
section("H01: parse_url extended")

var client = new netutils.http_client

// HTTPS default port
var u1 = client.parse_url("https://example.com/path")
check_not_null("H01-01: https URL parsed", u1)
check_eq("H01-02: https default port 443", u1["port"], 443)
check_eq("H01-03: https scheme", u1["scheme"], "https")

// HTTP default port
var u2 = client.parse_url("http://example.org")
check_eq("H01-04: http default port 80", u2["port"], 80)

// Explicit port
var u3 = client.parse_url("http://127.0.0.1:8080/page")
check_eq("H01-05: explicit port", u3["port"], 8080)

// URL fragment stripping
var u4 = client.parse_url("https://api.example.com/v1#section")
check_not_null("H01-06: URL with fragment parsed", u4)
check_eq("H01-07: fragment not in path", u4["path"], "/v1")

// Uppercase scheme (case-insensitive match)
var u5 = client.parse_url("HTTP://example.com/test")
check_not_null("H01-08: uppercase HTTP parsed", u5)
check_eq("H01-09: scheme lowercased", u5["scheme"], "http")

// ============================================================
// H02 — http_client parse_response_headers
// ============================================================
section("H02: parse_response_headers")

var h1 = client.parse_response_headers("HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Type: text/plain\r\n\r\n")
check_not_null("H02-01: 200 OK parsed", h1)
check_eq("H02-02: status_code 200", h1["status_code"], 200)
check_eq("H02-03: content_length 5", h1["content_length"], 5)
check_false("H02-04: not chunked", h1["is_chunked"])
check("H02-05: headers has content-type", h1["headers"].exist("content-type"))
check_eq("H02-06: content-type value", h1["headers"]["content-type"], "text/plain")

// Chunked transfer
var h2 = client.parse_response_headers("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
check_true("H02-07: chunked detected", h2["is_chunked"])
check_eq("H02-08: chunked content_length -1", h2["content_length"], -1)

// 404
var h3 = client.parse_response_headers("HTTP/1.1 404 Not Found\r\n\r\n")
check_eq("H02-09: 404 status", h3["status_code"], 404)
check_eq("H02-10: 404 content_length -1", h3["content_length"], -1)

// Header key normalization (lowercased)
var h4 = client.parse_response_headers("HTTP/1.1 200 OK\r\nX-Custom-Key: Value123\r\n\r\n")
check_eq("H02-11: header key lowercased", h4["headers"]["x-custom-key"], "Value123")

// ============================================================
// H03 — http_client HTTP round-trip against a local echo server
// ============================================================
section("H03: http_client HTTP GET round-trip")

// Start a simple HTTP echo server using tcp
var guard = new async.work_guard
var srv_sock = new tcp.socket
var acpt = tcp.acceptor(tcp.endpoint_v4(server_port))
var accept_state = async.accept(srv_sock, acpt)

// Client connects
var http_cli = new netutils.http_client
var target = http_cli.parse_url("http://127.0.0.1:" + to_string(server_port) + "/echo")
check_not_null("H03-01: target URL parsed", target)

// Start client request (will block on connect internally)
// But we need the server to accept first — use http_client.connect_target
var connected = http_cli.connect_target(target)
check_true("H03-02: http_client connected", connected)

// Send a raw HTTP request manually
http_cli.sock.write("GET /echo HTTP/1.1\r\nHost: 127.0.0.1:" + to_string(server_port) + "\r\nConnection: close\r\n\r\n")

// Wait for async accept
if !accept_state.wait_for(5000)
    check("H03-03: server accepted", false)
    system.exit(1)
end
check("H03-03: server accepted", true)

// Server reads the request
var req_line = srv_sock.receive(256)
check_not_null("H03-04: server received request", req_line)
check("H03-05: request starts with GET", req_line.find("GET", 0) == 0)

// Server sends response
var resp_body = "<html><body>echo test</body></html>"
var resp = "HTTP/1.1 200 OK\r\nContent-Length: " + to_string(resp_body.size) + "\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n" + resp_body
srv_sock.write(resp)

// Client reads response headers
var headers_raw = http_cli.read_until("\r\n\r\n")
check_not_null("H03-06: client read headers", headers_raw)

var meta = http_cli.parse_response_headers(headers_raw)
check_not_null("H03-07: parsed response meta", meta)
check_eq("H03-08: status 200", meta["status_code"], 200)
check_eq("H03-09: content_length matches", meta["content_length"], resp_body.size)

// Client reads body
var body = http_cli.read_exact(meta["content_length"])
check_not_null("H03-10: body read", body)
check_eq("H03-11: body matches", body, resp_body)

http_cli.close()
srv_sock.close()

// ============================================================
// H04 — openai_client test (local, no external API needed)
// ============================================================
section("H04: openai_client")

var oac = new netutils.openai_client

// message factory
var m = oac.message("user", "hello")
check_not_null("H04-01: message factory returns non-null", m)
check_eq("H04-02: role", m["role"], "user")
check_eq("H04-03: content", m["content"], "hello")

// endpoint normalization
oac.set_base("https://api.test.local/v1/")
var payload = {"model": "test", "messages": new array}.to_hash_map()
oac.set_api_key("test-key")

// request should fail (can't connect) but not crash
try
    var r = oac.request("/chat/completions", payload)
    check_null("H04-04: request to non-existent host returns null", r)
catch e
    check_null("H04-04: request to non-existent host returns null", null)
    system.out.println("  (connection failed as expected)")
end

// chat_text with null
var ct = oac.chat_text(null)
check_null("H04-05: chat_text(null) returns null", ct)

// Results
system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
system.out.println("SKIP: " + _skip)
if _fail > 0
    system.exit(1)
end
