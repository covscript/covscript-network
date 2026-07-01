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

# --- Check prerequisites ---
# 1) Environment variable DEEPSEEK_API_KEY
# 2) Local key file ~/.deepseek_key (one line: sk-...)
var api_key = null

try
    api_key = system.getenv("DEEPSEEK_API_KEY")
catch e
    null
end

if api_key == null || api_key.empty()
    try
        var home = system.getenv("HOME")
        if home == null || home.empty()
            home = system.getenv("USERPROFILE")
        end
        var key_file = iostream.ifstream(home + system.path.separator + ".deepseek_key")
        api_key = key_file.getline().trim()
        key_file.close()
    catch e
        null
    end
end

if api_key == null || api_key.empty()
    system.out.println("SKIP: Set DEEPSEEK_API_KEY env var or create ~/.deepseek_key file.")
    system.out.println("")
    system.out.println("=== Results ===")
    system.out.println("PASS: " + _pass)
    system.out.println("FAIL: " + _fail)
    system.out.println("SKIP: missing DEEPSEEK_API_KEY")
    system.exit(0)
end

# --- Setup client ---
var client = new netutils.openai_client
client.set_base("https://api.deepseek.com/")
client.set_model("deepseek-v4-flash")
client.set_api_key(api_key)

section("single-turn chat")
var messages = new array
messages.push_back(client.message("user", "Say exactly 'pong' and nothing else."))

var response = client.chat(messages)

if response == null
    check("D01: chat response not null", false)
    system.out.println("  Network/TLS/JSON error - check log above")
else
    check("D01: chat response not null", true)

    if response.exist("error")
        var err = response["error"]
        var err_msg = (err.exist("message") ? err["message"] : "(unknown)")
        system.out.println("  API Error: " + err_msg)
        system.out.println("  (skipping response shape checks - API key may be invalid)")
    else
        check("D02: no API error", true)

        if response.exist("choices") && !response["choices"].empty()
            var reply = response["choices"][0]["message"]["content"]
            check_not_null("D03: reply content non-null", reply)
            system.out.println("  Reply: " + reply)
        else
            check("D03: reply content non-null", false)
            system.out.println("  Unexpected response shape: " + json.to_string(json.from_var(response)))
        end
    end
end

section("error path: invalid API key")
var bad_client = new netutils.openai_client
bad_client.set_base("https://api.deepseek.com/v1")
bad_client.set_model("deepseek-v4-flash")
bad_client.set_api_key("sk-invalid-key-not-real")

var bad_messages = new array
bad_messages.push_back(client.message("user", "Hello"))

var bad_response = bad_client.chat(bad_messages)

if bad_response == null
    check("D04: bad key response not null", false)
else
    if bad_response.exist("error")
        check("D05: bad key gives API error", true)
        if bad_response["error"].exist("message")
            system.out.println("  Expected error: " + bad_response["error"]["message"])
        end
    else
        check("D05: bad key gives API error", false)
    end
end

system.out.println("")
system.out.println("=== Results ===")
system.out.println("PASS: " + _pass)
system.out.println("FAIL: " + _fail)
if _fail > 0
    system.exit(1)
end
