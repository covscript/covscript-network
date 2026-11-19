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

section("U01: to_fixed_hex / from_fixed_hex")

var val = 42
var hex = network.to_fixed_hex(val)
check_not_null("U01-01: to_fixed_hex returns non-null", hex)
check_eq("U01-02: hex string length is 16", hex.size, 16)
check_eq("U01-03: hex decode round-trip", network.from_fixed_hex(hex), 42)

var val2 = 65535
check_eq("U01-04: to_fixed_hex 65535 round-trip", network.from_fixed_hex(network.to_fixed_hex(val2)), 65535)

var val3 = 0
check_eq("U01-05: to_fixed_hex 0 round-trip", network.from_fixed_hex(network.to_fixed_hex(val3)), 0)

var val4 = 2147483647
check_eq("U01-06: to_fixed_hex large int round-trip", network.from_fixed_hex(network.to_fixed_hex(val4)), 2147483647)

section("U02: host_name")

var host = network.host_name()
check_not_null("U02-01: host_name returns non-null", host)
check("U02-02: host_name is non-empty", !host.empty())

section("U03: get_last_global_ssl_trust_report")

var report = network.get_last_global_ssl_trust_report()
check_not_null("U03-01: get_last_global_ssl_trust_report returns non-null", report)
check("U03-02: report is non-empty string", !report.empty())
check("U03-03: default report mentions unset", report.find("unset", 0) != -1 || report.find("trust_mode", 0) != -1)

section("U04: from_fixed_hex error path")

var threw = false
try
    network.from_fixed_hex("too_short")
catch e
    threw = true
end
check("U04-01: from_fixed_hex throws on short input", threw)

threw = false
try
    network.from_fixed_hex("12345678901234567")
catch e
    threw = true
end
check("U04-02: from_fixed_hex throws on long input", threw)

# std::stoull would accept a leading sign ("-" wraps modulo 2^64); the
# framing helpers must stay symmetric with to_fixed_hex, which rejects
# negative numbers.
threw = false
try
    network.from_fixed_hex("-000000000000001")
catch e
    threw = true
end
check("U04-03: from_fixed_hex throws on negative sign", threw)

threw = false
try
    network.from_fixed_hex("+000000000000001")
catch e
    threw = true
end
check("U04-04: from_fixed_hex throws on plus sign", threw)

threw = false
try
    network.from_fixed_hex(" 00000000000000F")
catch e
    threw = true
end
check("U04-05: from_fixed_hex throws on leading whitespace", threw)

section("U05: resolve hostname")

var results = network.tcp.resolve("localhost", "80")
check("U05-01: resolve localhost returns results", !results.empty())

section("U06: port validation")

var threw6 = false
try
    network.tcp.endpoint("127.0.0.1", 70000)
catch e
    threw6 = true
end
check("U06-01: port > 65535 rejected", threw6)

threw6 = false
try
    network.tcp.endpoint("127.0.0.1", -1)
catch e
    threw6 = true
end
check("U06-02: port < 0 rejected", threw6)

threw6 = false
try
    network.tcp.endpoint_v4(70000)
catch e
    threw6 = true
end
check("U06-03: endpoint_v4 port > 65535 rejected", threw6)

threw6 = false
try
    network.tcp.endpoint_v6(70000)
catch e
    threw6 = true
end
check("U06-04: endpoint_v6 port > 65535 rejected", threw6)

section("U07: endpoint address validation")

# endpoint() accepts numeric addresses only; host names must go through
# resolve(). The failure must be a catchable language error whose message
# points at resolve().
var err7 = null
try
    network.tcp.endpoint("localhost", 80)
catch e
    err7 = e.what
end
check("U07-01: tcp endpoint host name throws catchable error", err7 != null)
check("U07-02: error message suggests resolve()", err7 != null && err7.find("resolve", 0) != -1)

err7 = null
try
    network.udp.endpoint("localhost", 80)
catch e
    err7 = e.what
end
check("U07-03: udp endpoint host name throws catchable error", err7 != null)

# Numeric addresses keep working
var ok7 = false
try
    var ep7 = network.tcp.endpoint("127.0.0.1", 80)
    ok7 = ep7.address() == "127.0.0.1" && ep7.port() == 80
catch e
    ok7 = false
end
check("U07-04: tcp endpoint numeric address accepted", ok7)

var ok7v6 = false
try
    var ep7v6 = network.tcp.endpoint("::1", 80)
    ok7v6 = ep7v6.is_v6()
catch e
    ok7v6 = false
end
check("U07-05: tcp endpoint IPv6 numeric address accepted", ok7v6)

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
