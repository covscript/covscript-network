import network.tcp as tcp

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

function check_not_null(label, v)
    check(label, v != null)
end

# --- Parse command-line args ---
var host = "api.deepseek.com"
var port = 443
var ca_file = null
var ca_path = null

if context.cmd_args.size > 1
    host = context.cmd_args[1]
end
if context.cmd_args.size > 2
    port = context.cmd_args[2]
end
if context.cmd_args.size > 3
    ca_file = context.cmd_args[3]
end
if context.cmd_args.size > 4
    ca_path = context.cmd_args[4]
end

system.out.println("TLS trust self-check")
system.out.println("Target: " + host + ":" + to_string(port))

function run_trust_check(mode_name, options)
    var sock = new tcp.socket
    section("trust_mode=" + mode_name)

    var handshake_ok = false
    var error_msg = ""

    try
        var endpoints = tcp.resolve(host, to_string(port))
        var connected = false
        foreach ep in endpoints
            try
                sock.connect(ep)
                connected = true
                break
            catch e
                null
            end
        end
        if !connected
            error_msg = "TCP connect failed"
        else
            sock.connect_ssl(host, options)
            handshake_ok = true
        end
    catch e
        error_msg = e.what
        handshake_ok = false
    end

    check("handshake " + mode_name, handshake_ok)
    if !handshake_ok && error_msg != ""
        system.out.println("  Error: " + error_msg)
    end

    try
        var report = sock.get_ssl_trust_report()
        system.out.println("  Trust report: " + report)
        check_not_null("trust report non-null for " + mode_name, report)
    catch e
        system.out.println("  Trust report unavailable: " + e.what)
    end

    try
        sock.safe_shutdown()
    catch e
        null
    end
end

# Test auto mode
run_trust_check("auto", {"trust_mode": "auto"}.to_hash_map())

# Test openssl mode
if system.is_platform_windows()
    system.out.println("Skipping openssl mode on Windows (not supported)")
else
    run_trust_check("openssl", {"trust_mode": "openssl"}.to_hash_map())
end

# Test custom mode (only when ca_file/ca_path provided)
if (ca_file != null && !ca_file.empty()) || (ca_path != null && !ca_path.empty())
    var custom_opts = {"trust_mode": "custom"}.to_hash_map()
    if ca_file != null && !ca_file.empty()
        custom_opts.insert("ca_file", ca_file)
    end
    if ca_path != null && !ca_path.empty()
        custom_opts.insert("ca_path", ca_path)
    end
    run_trust_check("custom", custom_opts)
else
    system.out.println("")
    system.out.println("[Mode custom] skipped (pass ca_file or ca_path as args)")
end

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
