import network.udp as udp
import network.async as async

var _pass = 0
var _fail = 0
var _skip = 0
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

function check_true(label, v)
    check(label, v == true)
end

function skip(label, reason)
    _skip += 1
    system.out.println("[SKIP] " + _section + " | " + label + " -- " + reason)
end

section("U01: UDP sync loopback")

# Bind to port 0 so the OS assigns ephemeral ports -- avoids collisions
# when multiple test runs or CI jobs share a machine.
var sock_a = new udp.socket
var sock_b = new udp.socket

try
    sock_a.open_v4()
    sock_b.open_v4()
    sock_a.bind(udp.endpoint_v4(0))
    sock_b.bind(udp.endpoint_v4(0))
    check("U01-01: sockets opened and bound", true)
catch e
    check("U01-01: sockets opened and bound", false)
    system.out.println("  Error: " + e.what)
    system.exit(1)
end

var port_a = sock_a.local_endpoint().port()
var port_b = sock_b.local_endpoint().port()
check("U01-02: OS assigned nonzero ports", port_a != 0 && port_b != 0)

var msg = "UDP loopback test message"
sock_a.send_to(msg, udp.endpoint("127.0.0.1", port_b))

var ep_from = udp.endpoint_v4(0)
var received = sock_b.receive_from(msg.size, ep_from)
check_eq("U01-03: received message", received, msg)
check_eq("U01-04: received length", received.size, msg.size)
check("U01-05: sender is_v4", ep_from.is_v4())
check_eq("U01-06: sender port matches A", ep_from.port(), port_a)

sock_a.close()
sock_b.close()

section("U02: endpoint info")

var ep1 = udp.endpoint("127.0.0.1", 9000)
check("U02-01: is_v4", ep1.is_v4())
check_eq("U02-02: port", ep1.port(), 9000)
check_not_null("U02-03: address", ep1.address())
check("U02-04: address is 127.0.0.1", ep1.address() == "127.0.0.1")

var ep2 = udp.endpoint_v4(9999)
check("U02-05: endpoint_v4 is_v4", ep2.is_v4())
check_eq("U02-06: endpoint_v4 port", ep2.port(), 9999)

var ep3 = udp.endpoint_broadcast(8888)
check("U02-07: broadcast is_v4", ep3.is_v4())
check_eq("U02-08: broadcast port", ep3.port(), 8888)

section("U03: UDP async")

var guard = new async.work_guard
var sock_c = new udp.socket
var sock_d = new udp.socket

sock_c.open_v4()
sock_d.open_v4()
sock_c.bind(udp.endpoint_v4(0))
sock_d.bind(udp.endpoint_v4(0))
var port_c = sock_c.local_endpoint().port()
var port_d = sock_d.local_endpoint().port()

var recv_state = async.receive_from(sock_c, 100)

var send_state = async.send_to(sock_d, "async-udp-test", udp.endpoint("127.0.0.1", port_c))
var second_send_rejected = false
try
    async.send_to(sock_d, "duplicate", udp.endpoint("127.0.0.1", port_c))
catch e
    second_send_rejected = true
end
check("U03-01: second pending send rejected", second_send_rejected)

if recv_state.wait_for(3000)
    check("U03-02: async receive completed", true)
    var data = recv_state.get_result()
    check_eq("U03-03: async received data", data, "async-udp-test")

    var sender_ep = recv_state.get_endpoint()
    check("U03-04: sender endpoint is_v4", sender_ep.is_v4())
    check_eq("U03-05: sender port", sender_ep.port(), port_d)
else
    check("U03-02: async receive completed", false)
    system.out.println("  Receive timed out")
end

if send_state.wait_for(3000)
    check("U03-06: async send completed", send_state.get_error() == null)
else
    check("U03-06: async send completed", false)
end

sock_c.close()
sock_d.close()

section("U04: safe_close cancels pending receive")

# safe_close() cancels pending async operations (mirroring TCP safe_shutdown)
# so a UDP socket with an outstanding receive_from can always be closed
# instead of leaking open until a datagram happens to arrive.
var sock_e = new udp.socket
sock_e.open_v4()
sock_e.bind(udp.endpoint_v4(0))

var pending_receive = async.receive_from(sock_e, 100)
var second_receive_rejected = false
try
    async.receive_from(sock_e, 100)
catch e
    second_receive_rejected = true
end
check("U04-01: second pending receive rejected", second_receive_rejected)

var close_rejected = false
try
    sock_e.close()
catch e
    close_rejected = true
end
check("U04-02: close rejected while receive pending", close_rejected)

check_true("U04-03: safe_close cancels pending receive and closes", sock_e.safe_close())
check("U04-04: socket closed after safe_close", !sock_e.is_open())
check("U04-05: pending receive marked done after cancel", pending_receive.has_done())
check_not_null("U04-06: pending receive reports cancellation error", pending_receive.get_error())

section("U05: socket options")

var sock4 = new udp.socket
sock4.open_v4()
sock4.set_opt_reuse_address(true)
sock4.set_opt_broadcast(true)
check("U05-01: options set without error", true)
sock4.close()

section("U06: resolve")

var results = udp.resolve("127.0.0.1", "53")
check("U06-01: resolve returns results", !results.empty())
if !results.empty()
    check("U06-02: resolved endpoint is_v4", results[0].is_v4())
end

section("U07: buffer size limits")

var limit_sock = new udp.socket
var negative_receive_rejected = false
try
    async.receive_from(limit_sock, -1)
catch e
    negative_receive_rejected = true
end
check("U07-01: negative async receive size rejected", negative_receive_rejected)

var oversized_receive_rejected = false
try
    async.receive_from(limit_sock, 67108865)
catch e
    oversized_receive_rejected = true
end
check("U07-02: oversized async receive rejected", oversized_receive_rejected)

section("U08: broadcast send")

# Sending to the broadcast endpoint must succeed with SO_BROADCAST set.
# Actual delivery of broadcast datagrams depends on the platform/network
# (containers and some CI runners drop them), so the receive leg skips
# when nothing arrives.
var bcast_rx = new udp.socket
var bcast_tx = new udp.socket
bcast_rx.open_v4()
bcast_rx.set_opt_reuse_address(true)
bcast_rx.bind(udp.endpoint_v4(0))
var bcast_port = bcast_rx.local_endpoint().port()

bcast_tx.open_v4()
bcast_tx.set_opt_broadcast(true)

var bcast_send_ok = true
var bcast_send_error = ""
try
    bcast_tx.send_to("bcast-probe", udp.endpoint_broadcast(bcast_port))
catch e
    bcast_send_ok = false
    bcast_send_error = e.what
end
check("U08-01: broadcast send with SO_BROADCAST does not throw", bcast_send_ok)
if !bcast_send_ok
    system.out.println("  Error: " + bcast_send_error)
end

var bcast_state = async.receive_from(bcast_rx, 64)
if bcast_state.wait_for(1000)
    check_eq("U08-02: broadcast datagram received", bcast_state.get_result(), "bcast-probe")
else
    skip("U08-02: broadcast datagram received", "no broadcast delivery on this platform")
end

var nobroadcast_rejected = false
var no_bcast_sock = new udp.socket
no_bcast_sock.open_v4()
try
    # Without SO_BROADCAST the OS must reject the broadcast send
    no_bcast_sock.send_to("x", udp.endpoint_broadcast(bcast_port))
catch e
    nobroadcast_rejected = true
end
check("U08-03: broadcast send without SO_BROADCAST rejected", nobroadcast_rejected)
no_bcast_sock.close()
bcast_rx.close()
bcast_tx.close()

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
system.out.println("SKIP: " + _skip)
if _fail > 0
    system.exit(1)
end
