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

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
