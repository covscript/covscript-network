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

var _next_port = 15300

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

function drive_both(master, slave)
    master.poll()
    slave.poll()
    async.poll_once()
end

function drive_both_cycles(master, slave, count)
    var i = 0
    while i < count
        drive_both(master, slave)
        i += 1
    end
end

function drive_until_data(client, master, slave, timeout_ms)
    var start = runtime.time()
    while client.available() == 0 && runtime.time() - start < timeout_ms
        drive_both(master, slave)
        runtime.delay(5)
    end
    return client.available() > 0
end

function drain_response(client, marker, master, slave, timeout_ms)
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
        drive_both(master, slave)
        runtime.delay(5)
    end
    return resp
end

var g_called = false
var g_path = ""
var g_body = ""

function echo_handler(srv, session)
    g_called = true
    g_path = session.url
    g_body = session.post_data
    var body = "echo: " + session.url
    if session.post_data != null && !session.post_data.empty()
        body = body + " body=" + session.post_data
    end
    session.send_response("200 OK", body, "text/plain")
end

# ============================================================
# M01 -- Multi-process POST
# ============================================================
section("M01: multi-process POST body forwarding")

g_called = false; g_path = ""; g_body = ""

var http1 = alloc_port()
var slave1 = alloc_port()
system.out.println("M01 HTTP=" + to_string(http1) + " Slave=" + to_string(slave1))

var m1 = new netutils.http_server
m1.set_config({"thread_count": 2, "worker_count": 2, "max_keep_alive": 2}.to_hash_map())
m1.bind_func("/api/echo", echo_handler)
m1.set_master(slave1)
m1.listen(http1)

var s1 = new netutils.http_server
s1.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
s1.bind_func("/api/echo", echo_handler)
s1.set_slave("127.0.0.1", slave1)

drive_both_cycles(m1, s1, 20)

var client = new tcp.socket
client.connect(tcp.endpoint("127.0.0.1", http1))
check("M01-01: client connected", client.is_open())

var post_body = "name=covscript&version=2.0"
client.write("POST /api/echo HTTP/1.1\r\nHost: 127.0.0.1:" + to_string(http1) + "\r\nContent-Length: " + to_string(post_body.size) + "\r\nConnection: close\r\n\r\n" + post_body)

if !drive_until_data(client, m1, s1, 5000)
    check("M01-02: received response (timed out)", false)
else
    var response = drain_response(client, "body=" + post_body, m1, s1, 2000)
    check("M01-02: received response", !response.empty())
    check("M01-03: response contains 200 OK", response.find("200 OK", 0) != -1)
    check("M01-04: body forwarded", response.find("body=" + post_body, 0) != -1)
end
check("M01-05: handler invoked", g_called)
check_eq("M01-06: handler path", g_path, "/api/echo")
check_eq("M01-07: handler body", g_body, post_body)

client.close()
s1.stop()
m1.stop()
s1 = null; m1 = null

# ============================================================
# M02 -- Multi-process PUT body
# ============================================================
section("M02: multi-process PUT body forwarding")

g_called = false; g_path = ""; g_body = ""

var http2 = alloc_port()
var slave2 = alloc_port()
system.out.println("M02 HTTP=" + to_string(http2) + " Slave=" + to_string(slave2))

var m2 = new netutils.http_server
m2.set_config({"thread_count": 2, "worker_count": 2, "max_keep_alive": 2}.to_hash_map())
m2.bind_func("/api/resource", echo_handler)
m2.set_master(slave2)
m2.listen(http2)

var s2 = new netutils.http_server
s2.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
s2.bind_func("/api/resource", echo_handler)
s2.set_slave("127.0.0.1", slave2)

drive_both_cycles(m2, s2, 20)

var client2 = new tcp.socket
client2.connect(tcp.endpoint("127.0.0.1", http2))
check("M02-01: client connected", client2.is_open())

var put_body = "{\"name\":\"updated\"}"
client2.write("PUT /api/resource HTTP/1.1\r\nHost: 127.0.0.1:" + to_string(http2) + "\r\nContent-Length: " + to_string(put_body.size) + "\r\nConnection: close\r\n\r\n" + put_body)

if !drive_until_data(client2, m2, s2, 5000)
    check("M02-02: timed out", false)
else
    var r2 = drain_response(client2, "body=" + put_body, m2, s2, 2000)
    check("M02-02: received", !r2.empty())
    check("M02-03: PUT body forwarded", r2.find("body=" + put_body, 0) != -1)
end
check("M02-04: handler invoked", g_called)
check_eq("M02-05: handler body", g_body, put_body)

client2.close()
s2.stop(); m2.stop(); s2 = null; m2 = null

# ============================================================
# M03 -- Malformed frame does not crash master
# ============================================================
section("M03: malformed framing does not crash master")

var http3 = alloc_port()
var slave3 = alloc_port()
system.out.println("M03 HTTP=" + to_string(http3) + " Slave=" + to_string(slave3))

var m3 = new netutils.http_server
m3.set_config({"thread_count": 2, "worker_count": 2, "slave_spawn_timeout": 500}.to_hash_map())
m3.bind_func("/echo", echo_handler)
m3.set_master(slave3)
m3.listen(http3)

var i = 0
while i < 10
    m3.poll()
    async.poll_once()
    i += 1
end

# Attack 1: garbage
var a1 = new tcp.socket
a1.connect(tcp.endpoint("127.0.0.1", slave3))
check("M03-01: attacker connected", a1.is_open())
a1.write("GARBAGE")
a1.close()

# Attack 2: non-hex frame
var a2 = new tcp.socket
a2.connect(tcp.endpoint("127.0.0.1", slave3))
check("M03-02: attacker2 connected", a2.is_open())
a2.write("XXXXXXXXXXXXXXXX")
a2.close()

runtime.delay(800)
i = 0
while i < 20
    m3.poll()
    async.poll_once()
    runtime.delay(5)
    i += 1
end

var client3 = new tcp.socket
client3.connect(tcp.endpoint("127.0.0.1", http3))
check("M03-03: master still accepts connections after attacks", client3.is_open())
client3.close()
m3.stop(); m3 = null

# ============================================================
# M04 -- Slave disconnect: master survives
# ============================================================
section("M04: slave disconnect")

g_called = false; g_path = ""; g_body = ""

var http4 = alloc_port()
var slave4 = alloc_port()
system.out.println("M04 HTTP=" + to_string(http4) + " Slave=" + to_string(slave4))

var m4 = new netutils.http_server
m4.set_config({"thread_count": 2, "worker_count": 2, "max_keep_alive": 2}.to_hash_map())
m4.bind_func("/echo", echo_handler)
m4.set_master(slave4)
m4.listen(http4)

var s4 = new netutils.http_server
s4.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
s4.bind_func("/echo", echo_handler)
s4.set_slave("127.0.0.1", slave4)

drive_both_cycles(m4, s4, 20)

# Verify slave works
var c4a = new tcp.socket
c4a.connect(tcp.endpoint("127.0.0.1", http4))
check("M04-01: client connected", c4a.is_open())
c4a.write("GET /echo HTTP/1.1\r\nHost: 127.0.0.1:" + to_string(http4) + "\r\nConnection: close\r\n\r\n")

if !drive_until_data(c4a, m4, s4, 5000)
    check("M04-02: slave timed out", false)
else
    var r4a = drain_response(c4a, "echo:", m4, s4, 2000)
    check("M04-02: slave responded", !r4a.empty() && r4a.find("200 OK", 0) != -1)
end
c4a.close()

# Kill slave — master must survive
s4.stop(); s4 = null

runtime.delay(500)
var i4 = 0
while i4 < 30
    m4.poll()
    async.poll_once()
    runtime.delay(5)
    i4 += 1
end

# Master still accepts TCP connections
var c4b = new tcp.socket
c4b.connect(tcp.endpoint("127.0.0.1", http4))
check("M04-03: master still accepts after slave disconnect", c4b.is_open())
c4b.close()
m4.stop(); m4 = null

# ============================================================
# M05 -- Consecutive async writes regression
# ============================================================
section("M05: consecutive async writes regression")

g_called = false; g_path = ""; g_body = ""

var http5 = alloc_port()
var slave5 = alloc_port()
system.out.println("M05 HTTP=" + to_string(http5) + " Slave=" + to_string(slave5))

var m5 = new netutils.http_server
m5.set_config({"thread_count": 2, "worker_count": 2, "max_keep_alive": 2}.to_hash_map())
m5.bind_func("/echo", echo_handler)
m5.set_master(slave5)
m5.listen(http5)

var s5 = new netutils.http_server
s5.set_config({"thread_count": 2, "worker_count": 2}.to_hash_map())
s5.bind_func("/echo", echo_handler)
s5.set_slave("127.0.0.1", slave5)

drive_both_cycles(m5, s5, 20)

var client5 = new tcp.socket
client5.connect(tcp.endpoint("127.0.0.1", http5))
check("M05-01: client connected", client5.is_open())

var ba = "request_one"
client5.write("POST /echo HTTP/1.1\r\nHost: 127.0.0.1:" + to_string(http5) + "\r\nContent-Length: " + to_string(ba.size) + "\r\nConnection: keep-alive\r\n\r\n" + ba)

if !drive_until_data(client5, m5, s5, 5000)
    check("M05-02: first POST timed out", false)
else
    var r5a = drain_response(client5, ba, m5, s5, 2000)
    check("M05-02: first POST echoed", !r5a.empty() && r5a.find(ba, 0) != -1)
end

var bb = "request_two_longer"
client5.write("POST /echo HTTP/1.1\r\nHost: 127.0.0.1:" + to_string(http5) + "\r\nContent-Length: " + to_string(bb.size) + "\r\nConnection: close\r\n\r\n" + bb)

if !drive_until_data(client5, m5, s5, 5000)
    check("M05-03: second POST timed out", false)
else
    var r5b = drain_response(client5, bb, m5, s5, 2000)
    check("M05-03: second POST echoed", !r5b.empty() && r5b.find(bb, 0) != -1)
end
check("M05-04: handler called", g_called)

client5.close()
s5.stop(); m5.stop(); s5 = null; m5 = null

# ============================================================
# Results
# ============================================================
section("Results")
system.out.println("")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
