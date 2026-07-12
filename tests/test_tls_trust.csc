import network.tcp as tcp

var _pass = 0
var _fail = 0
var _skip = 0
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

function skip(label, reason)
    _skip += 1
    system.out.println("[SKIP] " + _section + " | " + label + " -- " + reason)
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
    var connected = false
    var resolved = false

    # --- Phase 1: DNS + TCP connect ---
    try
        var endpoints = tcp.resolve(host, to_string(port))
        resolved = true
        foreach ep in endpoints
            try
                sock.connect(ep)
                connected = true
                break
            catch e
                null
            end
        end
    catch e
        error_msg = e.what
    end

    # Connectivity failure → skip (offline / no route to host)
    if !resolved
        skip("handshake " + mode_name, "DNS resolution failed for " + host + ":" + to_string(port) + " -- " + error_msg)
        try
            sock.safe_shutdown()
        catch e
            null
        end
        return
    end
    if !connected
        skip("handshake " + mode_name, "TCP connect failed to " + host + ":" + to_string(port) + " -- " + (error_msg.empty() ? "no reachable endpoint" : error_msg))
        try
            sock.safe_shutdown()
        catch e
            null
        end
        return
    end

    # --- Phase 2: TLS handshake (we are connected; failures are real) ---
    try
        sock.connect_ssl(host, options)
        handshake_ok = true
    catch e
        error_msg = e.what
        handshake_ok = false
    end

    check("handshake " + mode_name, handshake_ok)
    if !handshake_ok && error_msg != ""
        system.out.println("  Error: " + error_msg)
    end

    # --- Phase 3: Trust report ---
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

var has_custom_ca = (ca_file != null && !ca_file.empty()) || (ca_path != null && !ca_path.empty())

if has_custom_ca
    # When a custom CA file/path is provided, we are testing against a server
    # that presents a self-signed certificate. Auto and openssl trust modes
    # would reject this certificate by design, so we skip them here.
    # They are tested separately against real-world servers in the other CI step.
    system.out.println("")
    system.out.println("[Mode auto] skipped (custom CA provided; auto trust tested separately)")
    _skip += 1
    system.out.println("")
    system.out.println("[Mode openssl] skipped (custom CA provided; openssl trust tested separately)")
    _skip += 1
else
    # Test auto mode
    run_trust_check("auto", {"trust_mode": "auto"}.to_hash_map())

    # Test openssl mode
    # Windows uses its own system certificate store (ROOT/CA/AuthRoot) via
    # load_windows_root_certs, not OpenSSL's set_default_verify_paths.
    # The "openssl" trust mode relies solely on OpenSSL defaults, which are
    # typically not configured on Windows — so we skip it there. The "auto"
    # mode already exercises Windows cert store loading.
    if system.is_platform_windows()
        system.out.println("")
        system.out.println("[Mode openssl] skipped (Windows uses system cert store, not OpenSSL defaults)")
        _skip += 1
    else
        run_trust_check("openssl", {"trust_mode": "openssl"}.to_hash_map())
    end
end

# Test custom mode (only when ca_file/ca_path provided)
if has_custom_ca
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
    _skip += 1
end

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
system.out.println("SKIP: " + _skip)
if _fail > 0
    system.exit(1)
end
