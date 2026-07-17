import netutils
import network.tcp as tcp
import network.async as async

# ============================================================================
# Stress test: master-slave dispatch resilience
#
# Validates that the master/slave machinery survives adversarial conditions:
#   Phase 1 — concurrent requests with client RST injection and scheduling
#             stalls that exceed slave_keep_alive_timeout (forcing the slave
#             to reconnect and the master to re-dispatch in-flight requests)
#   Phase 2 — full slave death: requests queue while no slave is connected,
#             then a fresh slave instance attaches and drains the queue
#             (exercises rank recycling and the dispatch wait loop)
#
# Timeouts are shortened via set_config so the failure paths trigger in
# milliseconds instead of seconds; assertions use generous windows and
# >= semantics (re-dispatch is at-least-once for idempotent methods).
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

var _next_port = 16100

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

function drive_ms(master, slave)
    master.poll()
    if slave != null
        slave.poll()
    end
    async.poll_once()
end

function http_req(path)
    return "GET " + path + " HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
end

var g_count = 0

function echo_handler(srv, session)
    g_count += 1
    session.send_response("200 OK", "ok path=" + session.url, "text/plain")
end

function make_master(http_p, slave_p)
    var master = new netutils.http_server
    master.set_config({"thread_count": 2, "worker_count": 4, "max_keep_alive": 100, "keep_alive_timeout": 10000, "heartbeat_interval": 200, "slave_keep_alive_timeout": 1000}.to_hash_map())
    master.bind_func("/echo", echo_handler)
    master.set_master(slave_p)
    master.listen(http_p)
    return move(master)
end

function make_slave(slave_p)
    var slave = new netutils.http_server
    slave.set_config({"thread_count": 2, "worker_count": 2, "heartbeat_interval": 200, "slave_keep_alive_timeout": 1000}.to_hash_map())
    slave.bind_func("/echo", echo_handler)
    slave.set_slave("127.0.0.1", slave_p)
    return move(slave)
end

# ----------------------------------------------------------------------
# Phase 1: RST injection + scheduling stalls
# ----------------------------------------------------------------------
section("S1: dispatch resilience under RST + stalls")

var iterations = 12
var it_num = 0
while it_num < iterations
    it_num += 1
    g_count = 0
    var http_p = alloc_port()
    var slave_p = alloc_port()

    var master = make_master(http_p, slave_p)
    var slave = make_slave(slave_p)

    var w = 0
    while w < 30
        drive_ms(master, slave)
        w += 1
    end

    var socks = new array
    var j = 0
    while j < 4
        var sock = new tcp.socket
        sock.connect(tcp.endpoint("127.0.0.1", http_p))
        sock.write(http_req("/echo"))
        socks.push_back(sock)
        j += 1
    end

    # Adversarial timing: on odd iterations kill one client early (RST with
    # an unread response); every 4th iteration stall past the 1000ms slave
    # keep-alive timeout so the slave reconnects mid-dispatch.
    var stalled = (it_num % 4 == 0)
    var start = runtime.time()
    var spin = 0
    var window = (stalled ? 8000 : 5000)
    while g_count < 4 && runtime.time() - start < window
        drive_ms(master, slave)
        ++spin
        if spin == 3 && it_num % 2 == 1
            socks[0].close()
        end
        if spin == 5 && stalled
            runtime.delay(1200)
        end
        runtime.delay(2)
    end
    # RST may race the master's read: the killed client's request is
    # legitimately lost, so 3 is acceptable on odd iterations.
    var expect = (it_num % 2 == 1 ? 3 : 4)
    check("iter " + it_num + (stalled ? " (stalled)" : "") + ": handled >= " + expect + " (got " + g_count + ")", g_count >= expect)

    foreach s in socks
        s.close()
    end
    slave.stop()
    master.stop()
    slave = null
    master = null
end

# ----------------------------------------------------------------------
# Phase 2: full slave death and replacement
# ----------------------------------------------------------------------
section("S2: slave death, queued requests, fresh slave attaches")

g_count = 0
var http_p = alloc_port()
var slave_p = alloc_port()

var master = make_master(http_p, slave_p)
var slave = make_slave(slave_p)

var w = 0
while w < 30
    drive_ms(master, slave)
    w += 1
end

# Sanity round trip through the first slave
var c = new tcp.socket
c.connect(tcp.endpoint("127.0.0.1", http_p))
c.write(http_req("/echo"))
var start = runtime.time()
while g_count < 1 && runtime.time() - start < 5000
    drive_ms(master, slave)
    runtime.delay(2)
end
check("S2-01: round trip via first slave", g_count == 1)
c.close()

# Kill the slave entirely; queue requests while no slave is connected
slave.stop()
slave = null
var wd = 0
while wd < 20
    drive_ms(master, null)
    runtime.delay(2)
    wd += 1
end

var socks = new array
var j = 0
while j < 3
    var sock = new tcp.socket
    sock.connect(tcp.endpoint("127.0.0.1", http_p))
    check("S2-02: master still accepts (conn " + j + ")", sock.is_open())
    sock.write(http_req("/echo"))
    socks.push_back(sock)
    j += 1
end

# Drive the master alone so the queued requests are read and parked
wd = 0
while wd < 30
    drive_ms(master, null)
    runtime.delay(2)
    wd += 1
end

# Attach a fresh slave instance — the queue must drain through it
var slave2 = make_slave(slave_p)
start = runtime.time()
while g_count < 4 && runtime.time() - start < 8000
    drive_ms(master, slave2)
    runtime.delay(2)
end
check("S2-03: queued requests drained by fresh slave (got " + (g_count - 1) + "/3)", g_count >= 4)

foreach s in socks
    s.close()
end
slave2.stop()
master.stop()
slave2 = null
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
