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

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
