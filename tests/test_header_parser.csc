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

section("chunked body trailers")
client.pending = "4\r\nWiki\r\n0\r\nX-Trace: one\r\nX-Extra: two\r\n\r\nNEXT"
check_eq("H11: chunked body decoded", client.read_chunked_body(), "Wiki")
check_eq("H12: all trailers consumed", client.pending, "NEXT")

section("header key normalization")
var raw3 = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nX-CUSTOM-KEY: value\r\n\r\n"
var h3 = client.parse_response_headers(raw3)
check_not_null("H13: headers parsed", h3)
check_eq("H14: content-type lowercased", h3["headers"]["content-type"], "application/json")
check_eq("H15: x-custom-key lowercased", h3["headers"]["x-custom-key"], "value")

section("connection close without body info")
var raw4 = "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"
var h4 = client.parse_response_headers(raw4)
check_not_null("H16: 204 parsed", h4)
check_eq("H17: status code 204", h4["status_code"], 204)
check_eq("H18: no content-length -> -1", h4["content_length"], -1)
check("H19: not chunked", !h4["is_chunked"])

section("invalid status lines")
check_null("H20: not HTTP status line", client.parse_response_headers("NOT_HTTP_STATUS\r\nX-Test: abc\r\n\r\n"))
check_null("H21: empty string", client.parse_response_headers(""))

section("invalid response framing")
check_null("H22: duplicate content-length rejected", client.parse_response_headers("HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n"))
check_null("H23: transfer-encoding with content-length rejected", client.parse_response_headers("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 4\r\n\r\n"))
check_null("H24: oversized content-length rejected", client.parse_response_headers("HTTP/1.1 200 OK\r\nContent-Length: 67108865\r\n\r\n"))

client.pending = "Z\r\n"
check_null("H25: invalid chunk size rejected", client.read_chunked_body())
client.pending = "FFFFFFFFF\r\n"
check_null("H26: oversized chunk size rejected", client.read_chunked_body())

section("invalid request framing")
var transfer_encoded_request = new array
transfer_encoded_request.push_back("POST / HTTP/1.1")
transfer_encoded_request.push_back("Host: localhost")
transfer_encoded_request.push_back("Transfer-Encoding: chunked")
check_null("H27: request transfer-encoding rejected", netutils.create_http_session(transfer_encoded_request))
var duplicate_length_request = new array
duplicate_length_request.push_back("POST / HTTP/1.1")
duplicate_length_request.push_back("Host: localhost")
duplicate_length_request.push_back("Content-Length: 1")
duplicate_length_request.push_back("Content-Length: 1")
check_null("H28: duplicate request content-length rejected", netutils.create_http_session(duplicate_length_request))
var oversized_length_request = new array
oversized_length_request.push_back("POST / HTTP/1.1")
oversized_length_request.push_back("Host: localhost")
oversized_length_request.push_back("Content-Length: 67108865")
check_null("H29: oversized request content-length rejected", netutils.create_http_session(oversized_length_request))

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
