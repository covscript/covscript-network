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
    check(label, a == b)
end

function check_not_null(label, v)
    check(label, v != null)
end

# Poll async events until state completes or timeout
function wait_for(state, timeout_ms)
    var start = runtime.time()
    loop
        async.poll_once()
        if runtime.time() - start >= timeout_ms
            break
        end
        runtime.delay(10)
    until state.has_done()
    return state.has_done()
end

section("async accept + sync client round-trip")

# Find a free port
var server_port = 0
var acceptor = null
var server = new tcp.socket
var test_port = 12000
while test_port < 12100
    try
        acceptor = tcp.acceptor(tcp.endpoint_v4(test_port))
        server_port = test_port
        break
    catch e
        test_port += 1
    end
end

if server_port == 0
    check("T00: find free port", false)
    system.out.println("  Could not bind to any port in range 12000-12099")
    system.exit(1)
end

system.out.println("  Server port: " + to_string(server_port))

# Start async accept
var guard = new async.work_guard
var accept_state = async.accept(server, acceptor)

# Client connects synchronously
var client = new tcp.socket
try
    client.connect(tcp.endpoint("127.0.0.1", server_port))
    check("T01: client connected", true)
catch e
    check("T01: client connected", false)
    system.out.println("  Connect error: " + e.what)
    system.exit(1)
end

# Wait for async accept to complete
if wait_for(accept_state, 5000)
    check("T02: server accepted", true)
else
    check("T02: server accepted", false)
    system.out.println("  Accept timed out")
    system.exit(1)
end

if accept_state.get_error() != null
    check("T03: no accept error", false)
    system.out.println("  Accept error: " + accept_state.get_error())
    system.exit(1)
else
    check("T03: no accept error", true)
end

# Client sends test message
var test_msg = "hello world\n"
try
    client.write(test_msg)
    check("T04: client wrote data", true)
catch e
    check("T04: client wrote data", false)
    system.out.println("  Write error: " + e.what)
end

# Server reads via async read_until
var read_state = new async.state
async.read_until(server, read_state, "\n")
if wait_for(read_state, 5000)
    check("T05: server read completed", true)
else
    check("T05: server read completed", false)
    system.out.println("  Read timed out")
end

if read_state.get_error() != null
    check("T06: no read error", false)
    system.out.println("  Read error: " + read_state.get_error())
else
    check("T06: no read error", true)
end

var received = read_state.get_result()
check("T07: received non-empty data", received != null && received.size > 0)
system.out.println("  Received: " + received)

# Server echoes back
try
    server.write("echo: " + received)
    check("T08: server echoed back", true)
catch e
    check("T08: server echoed back", false)
    system.out.println("  Echo error: " + e.what)
end

# Client reads response
try
    var response = client.read(("echo: " + test_msg).size)
    check_eq("T09: echo response matches", response, "echo: " + test_msg)
catch e
    check("T09: echo response matches", false)
    system.out.println("  Response error: " + e.what)
end

# Cleanup
try
    client.close()
    check("T10: client closed", true)
catch e
    check("T10: client closed", false)
end

try
    server.close()
    check("T11: server closed", true)
catch e
    check("T11: server closed", false)
end

section("async connect + server write")

# Find a free port
var port2 = 0
var acceptor2 = null
var server2 = new tcp.socket
test_port = 12100
while test_port < 12200
    try
        acceptor2 = tcp.acceptor(tcp.endpoint_v4(test_port))
        port2 = test_port
        break
    catch e
        test_port += 1
    end
end

if port2 == 0
    check("T12: find free port", false)
    system.out.println("  Could not bind to any port in range 12100-12199")
    system.exit(1)
end

system.out.println("  Server port: " + to_string(port2))

guard = new async.work_guard
accept_state = async.accept(server2, acceptor2)

# Async connect from client
var client2 = new tcp.socket
var connect_state = async.connect(client2, tcp.endpoint("127.0.0.1", port2))

# Wait for both accept and connect
if wait_for(accept_state, 5000)
    check("T12: server accepted (async connect)", true)
else
    check("T12: server accepted (async connect)", false)
end

if wait_for(connect_state, 5000)
    check("T13: client connected (async connect)", true)
else
    check("T13: client connected (async connect)", false)
end

if connect_state.get_error() != null
    check("T14: no connect error", false)
    system.out.println("  Connect error: " + connect_state.get_error())
else
    check("T14: no connect error", true)
end

# Server sends message
try
    server2.write("ping from server\n")
    check("T15: server wrote data", true)
catch e
    check("T15: server wrote data", false)
end

# Client reads via async
var read_state2 = new async.state
async.read_until(client2, read_state2, "\n")
if wait_for(read_state2, 5000)
    check("T16: client read completed", true)
else
    check("T16: client read completed", false)
end

var received2 = read_state2.get_result()
check("T17: received data matches", received2 == "ping from server\n")
system.out.println("  Received: " + received2)

# Cleanup
try
    client2.close()
    server2.close()
catch e
    null
end

section("partial data preserved after EOF")

var port3 = 0
var acceptor3 = null
var server3 = new tcp.socket
test_port = 12200
while test_port < 12300
    try
        acceptor3 = tcp.acceptor(tcp.endpoint_v4(test_port))
        port3 = test_port
        break
    catch e
        test_port += 1
    end
end

check("T18: partial-read test found free port", port3 != 0)
if port3 != 0
    guard = new async.work_guard
    var accept_state3 = async.accept(server3, acceptor3)
    var client3 = new tcp.socket
    client3.connect(tcp.endpoint("127.0.0.1", port3))
    check("T19: partial-read server accepted", wait_for(accept_state3, 5000))

    var read_state3 = async.read(server3, 8192)
    var partial_payload = ""
    foreach i in range(4096)
        partial_payload += "x"
    end
    client3.write(partial_payload)
    client3.close()

    check("T20: partial read completed after peer close", wait_for(read_state3, 5000))
    check("T21: partial read reports EOF/error", read_state3.get_error() != null)
    check_eq("T22: partial bytes remain available", read_state3.available(), partial_payload.size)
    check_eq("T23: get_result returns partial bytes", read_state3.get_result(), partial_payload)

    try
        server3.close()
    catch e
        null
    end
end

section("TLS upgrade rejects pending I/O")

var port4 = 0
var acceptor4 = null
var server4 = new tcp.socket
test_port = 12300
while test_port < 12400
    try
        acceptor4 = tcp.acceptor(tcp.endpoint_v4(test_port))
        port4 = test_port
        break
    catch e
        test_port += 1
    end
end

check("T24: TLS upgrade test found free port", port4 != 0)
if port4 != 0
    guard = new async.work_guard
    var accept_state4 = async.accept(server4, acceptor4)
    var client4 = new tcp.socket
    client4.connect(tcp.endpoint("127.0.0.1", port4))
    check("T25: TLS upgrade server accepted", wait_for(accept_state4, 5000))

    var read_state4 = async.read(server4, 1)
    var close_rejected = false
    try
        server4.close()
    catch e
        close_rejected = true
    end
    check("T26: close rejected while read pending", close_rejected)

    var upgrade_rejected = false
    try
        server4.connect_ssl("localhost", {"trust_mode": "insecure"}.to_hash_map())
    catch e
        upgrade_rejected = true
    end
    check("T27: TLS upgrade rejected while read pending", upgrade_rejected)
    check("T28: rejected upgrade leaves plain socket", !server4.is_ssl())

    client4.write("x")
    check("T29: original read still completes", wait_for(read_state4, 5000))
    check_eq("T30: original read result preserved", read_state4.get_result(), "x")

    client4.close()
    server4.close()
end

section("TLS handshake blocks new I/O")

var port5 = 0
var acceptor5 = null
var server5 = new tcp.socket
test_port = 12400
while test_port < 12500
    try
        acceptor5 = tcp.acceptor(tcp.endpoint_v4(test_port))
        port5 = test_port
        break
    catch e
        test_port += 1
    end
end

check("T31: pending handshake test found free port", port5 != 0)
if port5 != 0
    guard = new async.work_guard
    var accept_state5 = async.accept(server5, acceptor5)
    var client5 = new tcp.socket
    client5.connect(tcp.endpoint("127.0.0.1", port5))
    check("T32: pending handshake server accepted", wait_for(accept_state5, 5000))

    var reusable_state5 = new async.state
    client5.write("ready\n")
    async.read_until(server5, reusable_state5, "\n")
    check("T33: reusable state primed", wait_for(reusable_state5, 5000))
    check_eq("T34: reusable state initial result", reusable_state5.get_result(), "ready\n")

    var handshake_state5 = async.connect_ssl(server5, "localhost", {"trust_mode": "insecure"}.to_hash_map())
    var fresh_state5 = new async.state
    var fresh_error_first = ""
    var fresh_error_second = ""
    try
        async.read_until(server5, fresh_state5, "\n")
    catch e
        fresh_error_first = e.what
    end
    try
        async.read_until(server5, fresh_state5, "\n")
    catch e
        fresh_error_second = e.what
    end
    check("T35: fresh state rejects while handshake pending", !fresh_error_first.empty())
    check("T36: rejected fresh state is not poisoned", fresh_error_second.find("Last asynchronous operation", 0) == -1)

    var async_read_rejected = false
    try
        async.read_until(server5, reusable_state5, "\n")
    catch e
        async_read_rejected = true
    end
    check("T37: read_until rejected during handshake", async_read_rejected)
    check("T38: rejected read_until keeps state reusable", reusable_state5.has_done())
    check_eq("T39: available returns zero during handshake", server5.available(), 0)

    var sync_write_rejected = false
    try
        server5.write("x")
    catch e
        sync_write_rejected = true
    end
    check("T40: sync write rejected during handshake", sync_write_rejected)

    client5.close()
    check("T41: failed handshake completes", wait_for(handshake_state5, 5000))
    check("T42: failed handshake reports error", handshake_state5.get_error() != null)
    check("T43: failed handshake clears TLS state", !server5.is_ssl())
    check("T44: failed handshake preserves trust report", server5.get_ssl_trust_report().find("insecure", 0) != -1)
    server5.close()
end

section("TLS configuration failure restores socket")

var port6 = 0
var acceptor6 = null
var server6 = new tcp.socket
test_port = 12500
while test_port < 12600
    try
        acceptor6 = tcp.acceptor(tcp.endpoint_v4(test_port))
        port6 = test_port
        break
    catch e
        test_port += 1
    end
end

check("T45: TLS configuration test found free port", port6 != 0)
if port6 != 0
    guard = new async.work_guard
    var accept_state6 = async.accept(server6, acceptor6)
    var client6 = new tcp.socket
    client6.connect(tcp.endpoint("127.0.0.1", port6))
    check("T46: TLS configuration server accepted", wait_for(accept_state6, 5000))

    var config_rejected = false
    try
        client6.connect_ssl("localhost", {"trust_mode": "custom", "ca_file": "__covscript_network_missing_ca__.pem"}.to_hash_map())
    catch e
        config_rejected = true
    end
    check("T47: invalid custom CA rejected", config_rejected)
    check("T48: configuration failure clears TLS state", !client6.is_ssl())
    check("T49: configuration error report preserved", client6.get_ssl_trust_report().find("trust_mode=error", 0) != -1)

    client6.write("x")
    check_eq("T50: plain TCP remains usable after failure", server6.receive(1), "x")
    client6.close()
    server6.close()
end

section("overlapping reads rejected, full duplex preserved")

var port7 = 0
var acceptor7 = null
var server7 = new tcp.socket
test_port = 12600
while test_port < 12700
    try
        acceptor7 = tcp.acceptor(tcp.endpoint_v4(test_port))
        port7 = test_port
        break
    catch e
        test_port += 1
    end
end

check("T51: directional admission test found free port", port7 != 0)
if port7 != 0
    guard = new async.work_guard
    var accept_state7 = async.accept(server7, acceptor7)
    var client7 = new tcp.socket
    client7.connect(tcp.endpoint("127.0.0.1", port7))
    check("T52: directional admission server accepted", wait_for(accept_state7, 5000))

    var first_read7 = async.read(server7, 1)
    var second_read_rejected7 = false
    try
        async.read(server7, 1)
    catch e
        second_read_rejected7 = true
    end
    check("T53: second pending read rejected", second_read_rejected7)

    var read_until_state7 = new async.state
    var read_until_rejected7 = false
    try
        async.read_until(server7, read_until_state7, "\n")
    catch e
        read_until_rejected7 = true
    end
    check("T54: read_until rejected while read pending", read_until_rejected7)
    check("T55: rejected read_until state remains fresh", !read_until_state7.has_done())

    var concurrent_write7 = async.write(server7, "duplex")
    check_eq("T56: write can overlap pending read", client7.read(6), "duplex")
    check("T57: concurrent write completes", wait_for(concurrent_write7, 5000))

    var first_write7 = async.write(server7, "w")
    var second_write_rejected7 = false
    try
        async.write(server7, "z")
    catch e
        second_write_rejected7 = true
    end
    check("T58: second pending write rejected", second_write_rejected7)
    check_eq("T59: first pending write preserved", client7.read(1), "w")
    wait_for(first_write7, 5000)

    client7.write("x")
    wait_for(first_read7, 5000)
    client7.close()
    server7.close()
end

section("buffer size limits")

var limit_sock = new tcp.socket
var negative_async_read_rejected = false
try
    async.read(limit_sock, -1)
catch e
    negative_async_read_rejected = true
end
check("T60: negative async read size rejected", negative_async_read_rejected)

var oversized_async_read_rejected = false
try
    async.read(limit_sock, 67108865)
catch e
    oversized_async_read_rejected = true
end
check("T61: oversized async read rejected", oversized_async_read_rejected)

var oversized_sync_read_rejected = false
try
    limit_sock.read(67108865)
catch e
    oversized_sync_read_rejected = true
end
check("T62: oversized sync read rejected", oversized_sync_read_rejected)

var limit_state = new async.state
var negative_get_buffer_rejected = false
try
    limit_state.get_buffer(-1)
catch e
    negative_get_buffer_rejected = true
end
check("T63: negative get_buffer size rejected", negative_get_buffer_rejected)

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
