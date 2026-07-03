import network

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

// ============================================================
// U01 — to_fixed_hex / from_fixed_hex round-trip
// ============================================================
section("U01: to_fixed_hex / from_fixed_hex")

var val = 42
var hex = to_fixed_hex(val)
check_not_null("U01-01: to_fixed_hex returns non-null", hex)
check_eq("U01-02: hex string length is 16", hex.size, 16)
check_eq("U01-03: hex decode round-trip", from_fixed_hex(hex), 42)

var val2 = 65535
check_eq("U01-04: to_fixed_hex 65535 round-trip", from_fixed_hex(to_fixed_hex(val2)), 65535)

var val3 = 0
check_eq("U01-05: to_fixed_hex 0 round-trip", from_fixed_hex(to_fixed_hex(val3)), 0)

var val4 = 2147483647
check_eq("U01-06: to_fixed_hex large int round-trip", from_fixed_hex(to_fixed_hex(val4)), 2147483647)

// ============================================================
// U02 — host_name
// ============================================================
section("U02: host_name")

var host = host_name()
check_not_null("U02-01: host_name returns non-null", host)
check("U02-02: host_name is non-empty", !host.empty())

// ============================================================
// U03 — get_last_ssl_trust_report (returns default when no TLS)
// ============================================================
section("U03: get_last_ssl_trust_report")

var report = get_last_ssl_trust_report()
check_not_null("U03-01: get_last_ssl_trust_report returns non-null", report)
check("U03-02: report is non-empty string", !report.empty())
// Default before any TLS init should contain "unset"
check("U03-03: default report mentions unset", report.find("unset", 0) != -1 || report.find("trust_mode", 0) != -1)

// ============================================================
// U04 — from_fixed_hex invalid input
// ============================================================
section("U04: from_fixed_hex error path")

var threw = false
try
    from_fixed_hex("too_short")
catch e
    threw = true
end
check("U04-01: from_fixed_hex throws on short input", threw)

threw = false
try
    from_fixed_hex("12345678901234567")
catch e
    threw = true
end
check("U04-02: from_fixed_hex throws on long input", threw)

// ============================================================
// U05 — tcp.resolve with hostname
// ============================================================
section("U05: resolve hostname")

import network.tcp as tcp

var results = tcp.resolve("localhost", "80")
check("U05-01: resolve localhost returns results", !results.empty())

// ============================================================
// U06 — endpoint port validation (must reject > 65535)
// ============================================================
section("U06: port validation")

var threw6 = false
try
    tcp.endpoint("127.0.0.1", 70000)
catch e
    threw6 = true
end
check("U06-01: port > 65535 rejected", threw6)

threw6 = false
try
    tcp.endpoint("127.0.0.1", -1)
catch e
    threw6 = true
end
check("U06-02: port < 0 rejected", threw6)

threw6 = false
try
    tcp.endpoint_v4(70000)
catch e
    threw6 = true
end
check("U06-03: endpoint_v4 port > 65535 rejected", threw6)

threw6 = false
try
    tcp.endpoint_v6(70000)
catch e
    threw6 = true
end
check("U06-04: endpoint_v6 port > 65535 rejected", threw6)

// Results
system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
