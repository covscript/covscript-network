import netutils

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

function check_null(label, v)
    check(label, v == null)
end

var client = new netutils.http_client

section("https default port")
var u1 = client.parse_url("https://api.openai.com/v1")
check_not_null("U01: https URL parsed", u1)
check_eq("U02: https scheme", u1["scheme"], "https")
check_eq("U03: https host", u1["host"], "api.openai.com")
check_eq("U04: https default port 443", u1["port"], 443)
check_eq("U05: https path", u1["path"], "/v1")

section("http default port")
var u2 = client.parse_url("http://example.com/index.html")
check_not_null("U06: http URL parsed", u2)
check_eq("U07: http scheme", u2["scheme"], "http")
check_eq("U08: http default port 80", u2["port"], 80)

section("explicit port")
var u3 = client.parse_url("http://127.0.0.1:8080/test?a=1")
check_not_null("U09: URL with explicit port", u3)
check_eq("U10: host from IP", u3["host"], "127.0.0.1")
check_eq("U11: explicit port", u3["port"], 8080)
check_eq("U12: path with query string", u3["path"], "/test?a=1")

var u4 = client.parse_url("https://example.com:8443/admin")
check_not_null("U13: https with explicit port", u4)
check_eq("U14: https explicit port", u4["port"], 8443)
check_eq("U15: path /admin", u4["path"], "/admin")

section("default path")
var u5 = client.parse_url("https://example.com")
check_not_null("U16: URL without path", u5)
check_eq("U17: default path /", u5["path"], "/")

section("invalid URLs")
check_null("U18: plain hostname", client.parse_url("not_a_url"))
check_null("U19: empty string", client.parse_url(""))
check_null("U20: ftp scheme", client.parse_url("ftp://files.example.com"))

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
