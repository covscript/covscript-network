import network.tcp as tcp
import network.async as async
import network

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

function check_true(label, v)
    check(label, v == true)
end

function check_false(label, v)
    check(label, v == false)
end

function skip(label, reason)
    _skip += 1
    system.out.println("[SKIP] " + _section + " | " + label + " -- " + reason)
end

section("E01: TLS connection refused")

var sock1 = new tcp.socket
var threw = false
try
    sock1.connect(tcp.endpoint("127.0.0.1", 19999))
catch e
    threw = true
    system.out.println("  Expected error: " + e.what)
end
check("E01-01: connect to dead port throws", threw)

section("E02: TLS trust_mode=insecure")

var sock2 = new tcp.socket
var test_host = "api.deepseek.com"
var test_port = 443
var connected = false

try
    var endpoints = tcp.resolve(test_host, to_string(test_port))
    foreach ep in endpoints
        try
            sock2.connect(ep)
            connected = true
            break
        catch e
            null
        end
    end
catch e
    null
end

if !connected
    skip("E02-all", "cannot reach " + test_host + ":" + to_string(test_port))
else
    var handshake_ok = false
    var guard2 = new async.work_guard
    var worker2a = new async.thread_worker
    var worker2b = new async.thread_worker
    try
        var handshake_state2 = async.connect_ssl(sock2, test_host, {"trust_mode": "insecure"}.to_hash_map())
        handshake_ok = handshake_state2.wait_for(10000)
    catch e
        system.out.println("  Handshake error: " + e.what)
    end
    check_true("E02-01: insecure handshake succeeds", handshake_ok)

    if handshake_ok
        check_true("E02-02: is_ssl after insecure handshake", sock2.is_ssl())

        var report = sock2.get_ssl_trust_report()
        check_not_null("E02-03: trust report for insecure", report)
        check("E02-04: insecure report mentions insecure", report.find("insecure", 0) != -1)
    end

    var shutdown_result2 = sock2.safe_shutdown()
    check_false("E02-05: safe_shutdown closes socket with workers", sock2.is_open())
    check("E02-06: safe_shutdown reports a boolean", shutdown_result2 == true || shutdown_result2 == false)
    guard2 = null
    worker2a = null
    worker2b = null
end

section("E03: TLS invalid hostname")

var sock3 = new tcp.socket
connected = false

try
    var endpoints = tcp.resolve(test_host, to_string(test_port))
    foreach ep in endpoints
        try
            sock3.connect(ep)
            connected = true
            break
        catch e
            null
        end
    end
catch e
    null
end

if !connected
    skip("E03-all", "cannot reach " + test_host)
else
    var wrong_hostname_ok = false
    try
        sock3.connect_ssl("wrong.hostname.example.invalid", {"trust_mode": "auto"}.to_hash_map())
        wrong_hostname_ok = true
    catch e
        system.out.println("  Expected error: " + e.what)
    end

    check_false("E03-01: wrong hostname rejected", wrong_hostname_ok)

    sock3.close()
end

section("E04: trust report after successful TLS")

var sock4 = new tcp.socket
connected = false

try
    var endpoints = tcp.resolve(test_host, to_string(test_port))
    foreach ep in endpoints
        try
            sock4.connect(ep)
            connected = true
            break
        catch e
            null
        end
    end
catch e
    null
end

if !connected
    skip("E04-all", "cannot reach " + test_host)
else
    try
        sock4.connect_ssl(test_host, {"trust_mode": "auto"}.to_hash_map())

        check_true("E04-01: is_ssl true after TLS", sock4.is_ssl())

        var report = sock4.get_ssl_trust_report()
        check_not_null("E04-02: per-socket report non-null", report)

        var global_report = network.get_last_global_ssl_trust_report()
        check_not_null("E04-03: global report snapshot non-null", global_report)
        check_eq("E04-04: global report matches socket report", global_report, report)

        check("E04-05: report mentions trust_mode", report.find("trust_mode", 0) != -1)

        sock4.safe_shutdown()
    catch e
        system.out.println("  TLS handshake failed: " + e.what)
        check("E04-all: connected TLS handshake succeeds", false)
    end
end

section("E05: shutdown clears TLS")

var sock5 = new tcp.socket
connected = false

try
    var endpoints = tcp.resolve(test_host, to_string(test_port))
    foreach ep in endpoints
        try
            sock5.connect(ep)
            connected = true
            break
        catch e
            null
        end
    end
catch e
    null
end

if !connected
    skip("E05-all", "cannot reach " + test_host)
else
    try
        sock5.connect_ssl(test_host, {"trust_mode": "auto"}.to_hash_map())
        check_true("E05-01: is_ssl true before shutdown", sock5.is_ssl())

        sock5.shutdown()

        check_false("E05-02: is_ssl false after shutdown", sock5.is_ssl())

        sock5.close()
    catch e
        system.out.println("  TLS handshake failed: " + e.what)
        check("E05-all: connected TLS handshake succeeds", false)
    end
end

section("E06: double connect_ssl")

var sock6 = new tcp.socket
connected = false

try
    var endpoints = tcp.resolve(test_host, to_string(test_port))
    foreach ep in endpoints
        try
            sock6.connect(ep)
            connected = true
            break
        catch e
            null
        end
    end
catch e
    null
end

if !connected
    skip("E06-all", "cannot reach " + test_host)
else
    try
        sock6.connect_ssl(test_host, {"trust_mode": "auto"}.to_hash_map())
        check_true("E06-01: first TLS handshake ok", sock6.is_ssl())

        var double_ok = true
        try
            sock6.connect_ssl(test_host, {"trust_mode": "auto"}.to_hash_map())
        catch e
            double_ok = false
            system.out.println("  Expected: " + e.what)
        end
        check_false("E06-02: double connect_ssl rejected", double_ok)
        check_true("E06-03: rejected upgrade preserves TLS state", sock6.is_ssl())

        sock6.close()
    catch e
        system.out.println("  TLS handshake failed: " + e.what)
        check("E06-all: connected TLS handshake succeeds", false)
    end
end

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
system.out.println("SKIP: " + _skip)
if _fail > 0
    system.exit(1)
end
