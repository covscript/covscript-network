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

section("valid 200 OK response")
var raw1 = "HTTP/1.1 200 OK\r\nContent-Length: 12\r\nX-Test: abc\r\n\r\n"
var h1 = client.parse_response_headers(raw1)
check_not_null("H01: 200 OK parsed", h1)
check_eq("H02: status code 200", h1["status_code"], 200)
check_eq("H03: content-length 12", h1["content_length"], 12)
check("H04: not chunked", !h1["is_chunked"])
check("H05: headers contain x-test", h1["headers"].exist("x-test"))
check_eq("H06: x-test value", h1["headers"]["x-test"], "abc")

section("chunked transfer-encoding")
var raw2 = "HTTP/1.1 201 Created\r\nTransfer-Encoding: gzip, chunked\r\n\r\n"
var h2 = client.parse_response_headers(raw2)
check_not_null("H07: 201 Created parsed", h2)
check_eq("H08: status code 201", h2["status_code"], 201)
check_eq("H09: no content-length -> -1", h2["content_length"], -1)
check("H10: is chunked", h2["is_chunked"])

section("header key normalization")
var raw3 = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nX-CUSTOM-KEY: value\r\n\r\n"
var h3 = client.parse_response_headers(raw3)
check_not_null("H11: headers parsed", h3)
check_eq("H12: content-type lowercased", h3["headers"]["content-type"], "application/json")
check_eq("H13: x-custom-key lowercased", h3["headers"]["x-custom-key"], "value")

section("connection close without body info")
var raw4 = "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"
var h4 = client.parse_response_headers(raw4)
check_not_null("H14: 204 parsed", h4)
check_eq("H15: status code 204", h4["status_code"], 204)
check_eq("H16: no content-length -> -1", h4["content_length"], -1)
check("H17: not chunked", !h4["is_chunked"])

section("invalid status lines")
check_null("H18: not HTTP status line", client.parse_response_headers("NOT_HTTP_STATUS\r\nX-Test: abc\r\n\r\n"))
check_null("H19: empty string", client.parse_response_headers(""))

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
