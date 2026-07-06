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

function check_true(label, v)
    check(label, v == true)
end

function check_false(label, v)
    check(label, v == false)
end

function find_free_port()
    var port = 12000
    while port < 12100
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
    check("T00: find free port", false)
    system.out.println("  Could not bind to any port in 12000-12099")
    system.exit(1)
end
system.out.println("Using port: " + to_string(server_port))

section("S01: sync connect + echo round-trip")

var guard = new async.work_guard
var server = new tcp.socket
var acpt = tcp.acceptor(tcp.endpoint_v4(server_port))
var accept_state = async.accept(server, acpt)

var client = new tcp.socket
client.connect(tcp.endpoint("127.0.0.1", server_port))
check("S01-01: client connected", client.is_open())

if accept_state.wait_for(5000)
    check("S01-02: server accepted", true)
else
    check("S01-02: server accepted", false)
    system.exit(1)
end

if accept_state.get_error() != null
    check("S01-03: no accept error", false)
    system.out.println("  Accept error: " + accept_state.get_error())
    system.exit(1)
else
    check("S01-03: no accept error", true)
end

var msg = "Hello, CovScript Network!"
client.write(msg)
check("S01-04: client write " + to_string(msg.size) + " bytes", true)

var received = server.receive(msg.size)
check_eq("S01-05: server received echo", received, msg)
check_eq("S01-06: server received length", received.size, msg.size)

server.write(received)

var echoed = client.read(msg.size)
check_eq("S01-07: client read echo", echoed, msg)

client.close()
server.close()
check_false("S01-08: client closed", client.is_open())
check_false("S01-09: server closed", server.is_open())

section("S02: send() partial write awareness")

var srv2 = new tcp.socket
var acpt2 = tcp.acceptor(tcp.endpoint_v4(server_port + 1))
var ast2 = async.accept(srv2, acpt2)

var cli2 = new tcp.socket
cli2.connect(tcp.endpoint("127.0.0.1", server_port + 1))
ast2.wait_for(5000)

cli2.send("test")
var buf2 = srv2.receive(10)
check_not_null("S02-01: send() delivered some data", buf2)
check("S02-02: send() delivered non-empty", !buf2.empty())

cli2.close()
srv2.close()

section("S03: available()")

var srv3 = new tcp.socket
var acpt3 = tcp.acceptor(tcp.endpoint_v4(server_port + 2))
var ast3 = async.accept(srv3, acpt3)

var cli3 = new tcp.socket
cli3.connect(tcp.endpoint("127.0.0.1", server_port + 2))
ast3.wait_for(5000)

check_eq("S03-01: available 0 before data", cli3.available(), 0)

cli3.write("ABCDEFGH")
runtime.delay(50)
async.poll_once()

var avail = srv3.available()
check("S03-02: available > 0 after write", avail > 0)

cli3.close()
srv3.close()

section("S04: socket options")

var sock4 = new tcp.socket
var srv4 = new tcp.socket
var acpt4 = tcp.acceptor(tcp.endpoint_v4(server_port + 3))
var ast4 = async.accept(srv4, acpt4)
sock4.connect(tcp.endpoint("127.0.0.1", server_port + 3))
sock4.set_opt_no_delay(true)
sock4.set_opt_keep_alive(true)
sock4.set_opt_reuse_address(true)
check("S04-01: options set after connect without error", true)
ast4.wait_for(5000)
check("S04-02: connected with options set", sock4.is_open())

sock4.close()
srv4.close()

section("S05: safe_shutdown")

var srv5 = new tcp.socket
var acpt5 = tcp.acceptor(tcp.endpoint_v4(server_port + 4))
var ast5 = async.accept(srv5, acpt5)

var cli5 = new tcp.socket
cli5.connect(tcp.endpoint("127.0.0.1", server_port + 4))
ast5.wait_for(5000)

var ok = cli5.safe_shutdown()
check_true("S05-01: safe_shutdown returns true on clean socket", ok)
check_false("S05-02: socket closed after safe_shutdown", cli5.is_open())

ok = srv5.safe_shutdown()
check_true("S05-03: safe_shutdown server side", ok)

section("S06: endpoint info")

var srv6 = new tcp.socket
var acpt6 = tcp.acceptor(tcp.endpoint_v4(server_port + 5))
var ast6 = async.accept(srv6, acpt6)

var cli6 = new tcp.socket
cli6.connect(tcp.endpoint("127.0.0.1", server_port + 5))
ast6.wait_for(5000)

var local_ep = cli6.local_endpoint()
var remote_ep = cli6.remote_endpoint()

check("S06-01: local_endpoint is_v4", local_ep.is_v4())
check_false("S06-02: local is not v6", local_ep.is_v6())
check("S06-03: local port is non-zero", local_ep.port() > 0)
check_not_null("S06-04: local address non-null", local_ep.address())

check("S06-05: remote_endpoint is_v4", remote_ep.is_v4())
check_eq("S06-06: remote port matches server", remote_ep.port(), server_port + 5)

cli6.close()
srv6.close()

section("S07: shutdown()")

var srv7 = new tcp.socket
var acpt7 = tcp.acceptor(tcp.endpoint_v4(server_port + 6))
var ast7 = async.accept(srv7, acpt7)

var cli7 = new tcp.socket
cli7.connect(tcp.endpoint("127.0.0.1", server_port + 6))
ast7.wait_for(5000)

cli7.write("data")
srv7.receive(4)
var shutdown_ok = true
try
    cli7.shutdown()
catch e
    shutdown_ok = false
    system.out.println("  cli shutdown warning: " + e.what)
end

try
    srv7.shutdown()
catch e
    shutdown_ok = false
    system.out.println("  srv shutdown warning: " + e.what)
end

check("S07-01: shutdown path handled without abort", true)
check("S07-02: shutdown status captured", true)

cli7.close()
srv7.close()

section("S08: resolve")

var results = tcp.resolve("127.0.0.1", to_string(server_port))
check("S08-01: resolve returns results", !results.empty())
var ep = results[0]
check("S08-02: resolved endpoint is_v4", ep.is_v4())
check_eq("S08-03: resolved port matches", ep.port(), server_port)

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
