import network.tcp as tcp
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

function skip(label, reason)
    _skip += 1
    system.out.println("[SKIP] " + _section + " | " + label + " -- " + reason)
end

# Grab ephemeral ports by binding UDP sockets to port 0. Acceptors expose
# no local_endpoint binding, so TCP test ports are discovered this way and
# then tried as candidates (the port space is shared in practice).
function grab_free_ports(n)
    var ports = new array
    var i = 0
    while i < n
        var s = new udp.socket
        s.open_v6()
        s.bind(udp.endpoint("::1", 0))
        ports.push_back(s.local_endpoint().port())
        s.close()
        i += 1
    end
    return ports
end

section("V01: IPv6 availability")

# Everything in this suite runs over the IPv6 loopback (::1). Platforms
# without IPv6 (or with it disabled) skip the whole suite.
var v6_available = true
var v6_reason = ""
var probe_a = new udp.socket
var probe_b = new udp.socket
try
    probe_a.open_v6()
    probe_b.open_v6()
    probe_a.bind(udp.endpoint("::1", 0))
    probe_b.bind(udp.endpoint("::1", 0))
catch e
    v6_available = false
    v6_reason = e.what
end

if !v6_available
    skip("V01: IPv6 loopback available", v6_reason)
    skip("V02: IPv6 UDP loopback", "IPv6 unavailable")
    skip("V03: IPv6 TCP sync loopback", "IPv6 unavailable")
    skip("V04: IPv6 TCP async loopback", "IPv6 unavailable")
    system.out.println("")
    system.out.println("=== Results ===")
    system.out.println("PASS: " + _pass)
    system.out.println("FAIL: " + _fail)
    system.out.println("SKIP: " + _skip)
    system.exit(0)
end
check("V01-01: IPv6 loopback available", true)

var ep_v6 = tcp.endpoint("::1", 0)
check("V01-02: tcp endpoint parses ::1", ep_v6.is_v6())

section("V02: IPv6 UDP loopback")

var port_a = probe_a.local_endpoint().port()
var port_b = probe_b.local_endpoint().port()
check("V02-01: OS assigned nonzero ports", port_a != 0 && port_b != 0)

var msg = "ipv6-udp-message"
probe_a.send_to(msg, udp.endpoint("::1", port_b))

var ep_from = udp.endpoint_v6(0)
var received = probe_b.receive_from(msg.size, ep_from)
check_eq("V02-02: received message", received, msg)
check("V02-03: sender is_v6", ep_from.is_v6())
check_eq("V02-04: sender port matches A", ep_from.port(), port_a)

probe_a.close()
probe_b.close()

section("V03: IPv6 TCP sync loopback")

var guard = new async.work_guard

# Try several candidate ports for the acceptor (a UDP-free port is almost
# always TCP-free too, but retrying keeps the test robust).
var acc = null
var tcp_port = 0
foreach p in grab_free_ports(5)
    try
        acc = tcp.acceptor(tcp.endpoint("::1", p))
        tcp_port = p
        break
    catch e
        continue
    end
end

if acc == null
    skip("V03: IPv6 TCP sync loopback", "no free port for acceptor")
else
    var server = new tcp.socket
    var acc_state = async.accept(server, acc)

    var client = new tcp.socket
    client.connect(tcp.endpoint("::1", tcp_port))

    if acc_state.wait_for(5000)
        check("V03-01: accepted over ::1", true)
        check("V03-02: server side remote is_v6", server.remote_endpoint().is_v6())

        client.write("hello-v6")
        check_eq("V03-03: server received", server.receive(8), "hello-v6")

        server.write("pong-v6")
        check_eq("V03-04: client received", client.receive(7), "pong-v6")
        check("V03-05: client local is_v6", client.local_endpoint().is_v6())
    else
        check("V03-01: accepted over ::1", false)
    end
    client.close()
    server.close()
end

section("V04: IPv6 TCP async loopback")

var acc2 = null
var tcp_port2 = 0
foreach p in grab_free_ports(5)
    try
        acc2 = tcp.acceptor(tcp.endpoint("::1", p))
        tcp_port2 = p
        break
    catch e
        continue
    end
end

if acc2 == null
    skip("V04: IPv6 TCP async loopback", "no free port for acceptor")
else
    var server2 = new tcp.socket
    var acc_state2 = async.accept(server2, acc2)

    var client2 = new tcp.socket
    var connect_state = async.connect(client2, tcp.endpoint("::1", tcp_port2))

    if connect_state.wait_for(5000) && acc_state2.wait_for(5000)
        check("V04-01: async connect + accept over ::1", true)

        var write_state = async.write(client2, "async-v6")
        check("V04-02: async write done", write_state.wait_for(5000))

        var read_state = async.read(server2, 8)
        if read_state.wait_for(5000)
            check_eq("V04-03: async read data", read_state.get_result(), "async-v6")
        else
            check("V04-03: async read data", false)
        end
    else
        check("V04-01: async connect + accept over ::1", false)
    end
    client2.close()
    server2.close()
end

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
system.out.println("SKIP: " + _skip)
if _fail > 0
    system.exit(1)
end
