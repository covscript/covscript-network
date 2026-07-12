import argparse

var _pass = 0
var _fail = 0

function check(label, ok)
    if ok
        system.out.println("[PASS] " + label)
        _pass += 1
    else
        system.out.println("[FAIL] " + label)
        _fail += 1
    end
end

var parser = new argparse.ArgumentParser
parser.add_option("--port", false, false, "Port")
parser.set_defaults("--port", "8080")

var missing_value_rejected = false
var missing_args = new array
missing_args.push_back("program")
missing_args.push_back("--port")
try
    parser.parse_args(missing_args)
catch e
    missing_value_rejected = true
end
check("A01: trailing value option rejected", missing_value_rejected)

var valid_args = new array
valid_args.push_back("program")
valid_args.push_back("--port")
valid_args.push_back("9090")
var parsed = parser.parse_args(valid_args)
check("A02: option value parsed", parsed.port == "9090")

parser.add_option("--verbose", true, false, "Verbose")
var adjacent_option_rejected = false
var adjacent_args = new array
adjacent_args.push_back("program")
adjacent_args.push_back("--port")
adjacent_args.push_back("--verbose")
try
    parser.parse_args(adjacent_args)
catch e
    adjacent_option_rejected = true
end
check("A03: value option does not consume next option", adjacent_option_rejected)

var negative_args = new array
negative_args.push_back("program")
negative_args.push_back("--port")
negative_args.push_back("-1")
parsed = parser.parse_args(negative_args)
check("A04: unregistered hyphen-prefixed value preserved", parsed.port == "-1")

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end