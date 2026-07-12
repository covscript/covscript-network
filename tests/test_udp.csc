import network.udp as udp
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

function check_true(label, v)
    check(label, v == true)
end

section("U01: UDP sync loopback")

var port = 13000
var sock_a = new udp.socket
var sock_b = new udp.socket

try
    sock_a.open_v4()
    sock_b.open_v4()
    sock_a.bind(udp.endpoint_v4(port))
    sock_b.bind(udp.endpoint_v4(port + 1))
    check("U01-01: sockets opened and bound", true)
catch e
    check("U01-01: sockets opened and bound", false)
    system.out.println("  Error: " + e.what)
    system.exit(1)
end

var msg = "UDP loopback test message"
sock_a.send_to(msg, udp.endpoint("127.0.0.1", port + 1))

var ep_from = udp.endpoint_v4(0)
var received = sock_b.receive_from(msg.size, ep_from)
check_eq("U01-02: received message", received, msg)
check_eq("U01-03: received length", received.size, msg.size)
check("U01-04: sender is_v4", ep_from.is_v4())
check_eq("U01-05: sender port matches A", ep_from.port(), port)

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
var port3 = 13002
var sock_c = new udp.socket
var sock_d = new udp.socket

sock_c.open_v4()
sock_d.open_v4()
sock_c.bind(udp.endpoint_v4(port3))
sock_d.bind(udp.endpoint_v4(port3 + 1))

var recv_state = async.receive_from(sock_c, 100)

var send_state = async.send_to(sock_d, "async-udp-test", udp.endpoint("127.0.0.1", port3))
var second_send_rejected = false
try
    async.send_to(sock_d, "duplicate", udp.endpoint("127.0.0.1", port3))
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
    check_eq("U03-05: sender port", sender_ep.port(), port3 + 1)
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

section("U04: safe_close rejects pending receive")

var sock_e = new udp.socket
var sock_f = new udp.socket
sock_e.open_v4()
sock_f.open_v4()
sock_e.bind(udp.endpoint_v4(port3 + 2))
sock_f.bind(udp.endpoint_v4(port3 + 3))

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
check("U04-03: safe_close reports pending receive", sock_e.safe_close() == false)
check("U04-04: socket remains open after rejected close", sock_e.is_open())

sock_f.send_to("release", udp.endpoint("127.0.0.1", port3 + 2))
check("U04-05: pending receive completes", pending_receive.wait_for(3000))
check("U04-06: safe_close succeeds after receive", sock_e.safe_close())
check("U04-07: socket closed after safe_close", !sock_e.is_open())
sock_f.close()

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

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
