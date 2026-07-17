import netutils
import network.tcp as tcp
import network.async as async

# ============================================================================
# Stress test: single-process concurrent connections
#
# Rounds of N concurrent clients against one server, with a random half of
# the clients disconnecting before reading their response. The surviving
# clients must all receive 200s, and the server must stay healthy across
# every round (no wedged worker fibers, no leaked connection slots).
#
# No wall-clock randomness (deterministic pattern): even-indexed sockets
# are the deserters on odd rounds, odd-indexed on even rounds.
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

var _next_port = 16500

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

function drive(server)
    server.poll()
    async.poll_once()
end

function drive_n(server, n)
    var i = 0
    while i < n
        drive(server)
        i += 1
    end
end

function http_req(path)
    return "GET " + path + " HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
end

var g_count = 0

function echo_handler(srv, session)
    g_count += 1
    session.send_response("200 OK", "ok path=" + session.url, "text/plain")
end

section("S1: concurrent rounds with deserting clients")

var p = alloc_port()
var srv = new netutils.http_server
srv.set_config({"thread_count": 2, "worker_count": 32, "max_keep_alive": 100, "keep_alive_timeout": 10000}.to_hash_map())
srv.bind_func("/concurrent", echo_handler)
srv.listen(p)
drive_n(srv, 20)

var conns_per_round = 16
var rounds = 8
var round = 0
while round < rounds
    round += 1
    g_count = 0
    var socks = new array
    var idx = 0
    while idx < conns_per_round
        var sock = new tcp.socket
        sock.connect(tcp.endpoint("127.0.0.1", p))
        sock.write(http_req("/concurrent"))
        socks.push_back(sock)
        idx += 1
    end

    # Deterministic desertion: half the clients slam their connection shut
    # before the server has (necessarily) responded.
    idx = 0
    while idx < conns_per_round
        if (idx + round) % 2 == 0
            socks[idx].close()
        end
        idx += 1
    end

    # Survivors read their responses; the server is driven inside the loop
    var survivors = 0
    var served = 0
    idx = 0
    while idx < conns_per_round
        if (idx + round) % 2 != 0
            ++survivors
            var c = socks[idx]
            var buf = ""
            var start = runtime.time()
            while buf.find("\r\n\r\n", 0) == -1 && runtime.time() - start < 5000
                var n = c.available()
                if n > 0
                    var chunk = c.receive(n)
                    if chunk != null && !chunk.empty()
                        buf += chunk
                    end
                else
                    if c.peer_closed()
                        break
                    end
                end
                drive(srv)
                runtime.delay(2)
            end
            if buf.find("200 OK", 0) != -1
                ++served
            end
            c.close()
        end
        idx += 1
    end
    drive_n(srv, 10)

    check("round " + round + ": all " + survivors + " survivors served (got " + served + ", handlers " + g_count + ")", served == survivors)
end

srv.acceptor = null
srv = null

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
