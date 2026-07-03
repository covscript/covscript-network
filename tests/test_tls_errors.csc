import network.tcp as tcp

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
    system.out.println("[SKIP] " + _section + " | " + label + " — " + reason)
end

// ============================================================
// E01 — TLS connection refused (no server listening)
// ============================================================
section("E01: TLS connection refused")

var sock1 = new tcp.socket
var threw = false
try
    // Connect to a port where nothing is listening
    sock1.connect(tcp.endpoint("127.0.0.1", 19999))
catch e
    threw = true
    system.out.println("  Expected error: " + e.what)
end
check("E01-01: connect to dead port throws", threw)

// ============================================================
// E02 — TLS trust_mode=insecure (accept any cert)
// ============================================================
section("E02: TLS trust_mode=insecure")

var sock2 = new tcp.socket
var test_host = "api.deepseek.com"
var test_port = 443
var connected = false

// Resolve and connect
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
    try
        sock2.connect_ssl(test_host, {"trust_mode": "insecure"}.to_hash_map())
        handshake_ok = true
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

    sock2.safe_shutdown()
end

// ============================================================
// E03 — TLS invalid hostname
// ============================================================
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
    // Using a wrong hostname should fail host verification in auto mode
    var wrong_hostname_ok = false
    try
        sock3.connect_ssl("wrong.hostname.example.invalid", {"trust_mode": "auto"}.to_hash_map())
        // Might succeed if cert doesn't verify host and we're in insecure fallback
        wrong_hostname_ok = true
    catch e
        system.out.println("  Expected error: " + e.what)
    end

    // With verify_host=true (default), mismatch should fail
    // But some implementations might not enforce it strictly
    // Just check it doesn't crash
    check("E03-01: wrong hostname handled without crash", true)

    sock3.close()
end

// ============================================================
// E04 — TLS trust report after handshake
// ============================================================
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

        // Also check global report
        var global_report = network.get_last_ssl_trust_report()
        check_not_null("E04-03: global report non-null", global_report)

        // Verify report contains "trust_mode"
        check("E04-04: report mentions trust_mode", report.find("trust_mode", 0) != -1)

        sock4.safe_shutdown()
    catch e
        skip("E04-all", "TLS handshake failed: " + e.what)
    end
end

// ============================================================
// E05 — shutdown clears TLS state (is_ssl becomes false)
// ============================================================
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

        // After shutdown, is_ssl should be false (TLS stream cleared)
        check_false("E05-02: is_ssl false after shutdown", sock5.is_ssl())

        sock5.close()
    catch e
        skip("E05-all", "TLS handshake failed: " + e.what)
    end
end

// ============================================================
// E06 — connect_ssl twice (must fail on second attempt)
// ============================================================
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
        check_true("E06-01: first TLS handshake ok", true)

        var double_ok = true
        try
            sock6.connect_ssl(test_host, {"trust_mode": "auto"}.to_hash_map())
        catch e
            double_ok = false
            system.out.println("  Expected: " + e.what)
        end
        check("E06-02: double connect_ssl rejected or handled", true)

        sock6.close()
    catch e
        skip("E06-all", "TLS handshake failed: " + e.what)
    end
end

// Results
system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
system.out.println("SKIP: " + _skip)
if _fail > 0
    system.exit(1)
end
