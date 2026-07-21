# Covariant Script Network Extension

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

A high-performance network extension for the [Covariant Script](http://covscript.org.cn) programming language. Built on [ASIO](https://think-async.com/Asio/) (v1.38.0) and [OpenSSL](https://www.openssl.org/), it provides low-level networking primitives and a full HTTP server framework.

## Packages

| Package | Type | Version | Description |
|---|---|---|---|
| `network` | C++ Extension | `1.38.0_v6.6` | TCP/UDP sockets, TLS/SSL, async I/O, event loop |
| `netutils` | CovScript | `2.3` | HTTP server/client framework with single-process, distributed master/slave, and OpenAI API modes |
| `argparse` | CovScript | `1.1` | Lightweight command-line argument parser |

> **Note:** `netutils` and `argparse` are provided as both source (`.ecs`), compiled package (`.csp`), and bytecode module (`.csym`) — place them in your project's `imports/` directory.

---

## Features

- **TCP Sockets** — connect, accept, send/receive, read/write, shutdown with full endpoint management
- **UDP Sockets** — unicast, broadcast, async send/receive with IPv4/IPv6 support
- **TLS/SSL** — encrypted TCP with configurable trust modes (`auto`, `openssl`, `custom`, `insecure`) and detailed trust reporting
- **Asynchronous I/O** — non-blocking `async` namespace with `poll`/`poll_once` event loop, `thread_worker`, `work_guard`, and fiber-cooperative patterns
- **HTTP Server** (`netutils`) — multi-worker, configurable keep-alive, static file serving, custom route binding, and SQLite integration
- **HTTP Client** (`netutils`) — asynchronous HTTP/HTTPS client with TLS, timeouts, header parsing, and keep-alive
- **OpenAI Client** (`netutils`) — OpenAI/DeepSeek API-compatible chat client built on the HTTP client
- **Distributed Multi-Node** — master/slave architecture with TCP IPC for horizontal scaling of HTTP services
- **Reverse Proxy** — prefix-based request forwarding to backend servers with hop-by-hop header filtering and `X-Forwarded-For` injection
- **SM2 Key Support** — GM/T Chinese cryptographic key generation and simple TLS via `gmssl`
- **Utilities** — `host_name`, `to_fixed_hex`/`from_fixed_hex` for framing protocols

---

## Requirements

| Dependency | Notes |
|---|---|
| [Covariant Script](http://covscript.org.cn) | Set `CS_DEV_PATH` to the SDK root |
| [OpenSSL](https://www.openssl.org/) | Runtime and development headers |
| CMake ≥ 3.16 | Build system |
| C++17 compiler | GCC, Clang, or MSVC |
| pthread (Unix) / ws2_32 (Windows) | Platform socket libraries |

---

## Build

### Auto Build

Unix (Linux / macOS) or MSYS2 on Windows

```bash
bash ./csbuild/make.sh
```

MinGW-w64 on Windows

```batch
csbuild/make.bat
```

The compiled shared library (`network.cse`) will be placed in `build/imports/`.

> On some Linux distributions you may need to install OpenSSL manually
> (e.g., `apt install libssl-dev` on Ubuntu/Debian).

### Manual CMake

```bash
mkdir -p cmake-build && cd cmake-build
cmake .. -DCS_DEV_PATH=/path/to/covscript-sdk
cmake --build . -j4
```

### Compile-Time Options

All options can be overridden with `-D<option>=<value>`:

| Option | Default | Description |
|---|---|---|
| `NETWORK_FIXED_HEX_SIZE` | `16` | Hex string length for framing protocol helpers |
| `NETWORK_MAX_PORT` | `65535` | Maximum valid TCP/UDP port number |
| `NETWORK_MAX_IO_BUFFER_SIZE` | `67108864` | Max bytes per single read/receive call (64 MiB) |
| `NETWORK_SAFE_SHUTDOWN_TIMEOUT_MS` | `200` | Drain-loop deadline for UDP `safe_close` and TCP `safe_shutdown` |
| `NETWORK_TLS_SHUTDOWN_TIMEOUT_MS` | `5000` | TLS close-notify timeout |
| `NETWORK_THREAD_WORKER_POLL_MS` | `1` | Thread executor polling interval |
| `NETWORK_WAIT_SLEEP_MS` | `1` | Sleep duration (ms) in `wait_impl` / drain loops between poll iterations |
| `NETWORK_FAST_SPIN_COUNT` | `10` | Yield-without-sleep iterations in graduated wait before escalating to sleep |

---

## Quick Start

### TCP Echo (sync client + async accept)

```ruby
import network.tcp as tcp
import network.async as async

var guard = new async.work_guard
var port = 8888

# Server: bind and start async accept
var server = new tcp.socket
var acceptor = tcp.acceptor(tcp.endpoint_v4(port))
var accept_state = async.accept(server, acceptor)

# Client: connect synchronously
var client = new tcp.socket
client.connect(tcp.endpoint("127.0.0.1", port))

# Wait for server to accept
if accept_state.wait_for(5000)
    # Exchange data
    client.write("Hello, CovScript!")
    var received = server.receive(18)
    system.out.println("Server got: " + received)

    server.write("Echo: " + received)
    var echoed = client.read(23)
    system.out.println("Client got: " + echoed)
end

client.close()
server.close()
```

### Async TCP Client

```ruby
import network.tcp as tcp
import network.async as async

var guard = new async.work_guard

var sock = new tcp.socket
var connect_state = async.connect(sock, tcp.endpoint("example.com", 80))
connect_state.wait_for(5000)

var write_state = async.write(sock, "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")
write_state.wait_for(5000)

var read_state = async.read(sock, 4096)
read_state.wait_for(5000)

system.out.println(read_state.get_result())
sock.close()
```

### TLS Client

```ruby
import network.tcp as tcp

var sock = new tcp.socket
var options = {"trust_mode": "auto"}.to_hash_map()

sock.connect_ssl("example.com", options)
sock.write("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")
system.out.println(sock.read(4096))
sock.close()
```

### HTTP Server with `netutils`

```bash
ecs http_server.ecs examples/simple_config.json
# Server starts at http://localhost:8080/
```

Endpoints:
- `GET /test` — Echo request data  
- `GET /set?id=key&val=value` — Store a key-value record (SQLite)  
- `GET /get?id=key` — Retrieve a stored record  
- `GET /block` — Test the blocking API (50 ms delay)

---

## Examples

The [examples/](examples/) directory contains complete applications:

| File | Description |
|---|---|
| [`http_server.ecs`](examples/http_server.ecs) | Full HTTP server with SQLite-backed REST endpoints, static file serving, and multi-node support |
| [`spawn_http_server.ecs`](examples/spawn_http_server.ecs) | Distributed HTTP server spawner with master/slave process management |
| [`tls_client.ecs`](examples/tls_client.ecs) | Interactive TLS client with keyboard input and authorized key authentication |
| [`tls_server.ecs`](examples/tls_server.ecs) | Simple-TLS server with interactive stdio worker |
| [`tls_keygen.ecs`](examples/tls_keygen.ecs) | SM2 key-pair generator with password protection |
| [`simple_tls.ecs`](examples/simple_tls.ecs) | Custom TLS library using GmSSL (SM2/SM3/SM4) |
| [`simple_config.json`](examples/simple_config.json) | Standalone HTTP server configuration |
| [`distributed_config.json`](examples/distributed_config.json) | Multi-node HTTP server configuration |
| [`setup_macos.sh`](examples/setup_macos.sh) | macOS kernel tuning for high-concurrency servers |

---

## API Overview

### `network` (root namespace)

| Symbol | Description |
|---|---|
| `tcp` | TCP socket & endpoint operations |
| `udp` | UDP socket & endpoint operations |
| `async` | Asynchronous I/O primitives |
| `host_name()` | Returns the local hostname |
| `to_fixed_hex(n)` / `from_fixed_hex(s)` | Hex string ↔ number conversion for framing |
| `get_last_global_ssl_trust_report()` | Retrieve the last TLS trust verification report |

### `network.tcp`

- **Types (construct with `new`):** `socket`, `acceptor(endpoint)` — factory function, not a type
- **Endpoints:** `endpoint(host, port)`, `endpoint_v4(port)`, `endpoint_v6(port)`
- **DNS:** `resolve(host, service)`
- **Socket methods:** `connect`, `connect_ssl`, `accept`, `send`, `receive`, `read`, `write`
- **Lifecycle:** `close`, `is_open`, `is_ssl`, `shutdown`, `safe_shutdown`
- **Options:** `set_opt_reuse_address`, `set_opt_no_delay`, `set_opt_keep_alive`
- **Info:** `available`, `local_endpoint`, `remote_endpoint`, `get_ssl_trust_report`
- **Endpoint methods:** `address()`, `port()`, `is_v4()`, `is_v6()`

> **`send` vs `write`:** `send(data)` returns bytes actually sent (may be partial). `write(data)` blocks until all data is sent.
> **`receive` vs `read`:** `receive(max)` reads up to `max` bytes (whatever is available). `read(size)` blocks until exactly `size` bytes are received.

### `network.udp`

- **Type (construct with `new`):** `socket`
- **Endpoints:** `endpoint(host, port)`, `endpoint_v4(port)`, `endpoint_v6(port)`, `endpoint_broadcast(port)`
- **DNS:** `resolve(host, service)`
- **Socket methods:** `open_v4`, `open_v6`, `bind`, `connect`, `send_to`, `receive_from`
- **Lifecycle:** `close`, `safe_close`, `is_open`
- **Options:** `set_opt_reuse_address`, `set_opt_broadcast`
- **Info:** `available`, `local_endpoint`, `remote_endpoint`

### `network.async`

- **Types (construct with `new`):** `state`, `work_guard`, `thread_worker`
- **Operations (return state):** `accept(sock, acceptor)`, `connect(sock, ep)`, `connect_ssl(sock, host, opts)`, `read(sock, size)`, `write(sock, data)`, `receive_from(sock, size)`, `send_to(sock, data, ep)`
- **In-place operation:** `read_until(sock, state, pattern)` — reuses an existing state object
- **Event loop:** `poll()`, `poll_once()`, `stopped()`, `restart()`

#### Async State Methods

| Method | Description |
|---|---|
| `has_done()` | Check if the operation completed |
| `wait()` / `wait_for(ms)` | Block until completion (with optional timeout) |
| `get_result()` | Retrieve all received data |
| `get_buffer(max_bytes)` | Consume buffered data incrementally |
| `available()` | Bytes remaining in buffer |
| `eof()` | Check for EOF or connection reset |
| `get_error()` | Retrieve error message (or `null`) |
| `get_endpoint()` | Retrieve UDP sender endpoint |

---

## Architecture

```
┌──────────────────────────────────────────────────┐
│              Covariant Script Layer               │
│  (import network / import netutils)               │
├──────────────────────────────────────────────────┤
│  network.cpp (CNI bindings)                       │
│  ┌──────────┬──────────┬───────────────────────┐ │
│  │   TCP    │   UDP    │   Async (io_context)   │ │
│  └──────────┴──────────┴───────────────────────┘ │
├──────────────────────────────────────────────────┤
│  ASIO (include/asio/)           OpenSSL (TLS)     │
├──────────────────────────────────────────────────┤
│  OS sockets (epoll / kqueue / IOCP)               │
└──────────────────────────────────────────────────┘
```

The extension connects to Covariant Script via the CNI (Covariant Native Interface). It wraps ASIO's socket primitives and exposes them as named types and functions. The async subsystem uses ASIO's `io_context` with a shared event loop that can be driven manually (`poll`) or by dedicated worker threads.

---

## Documentation

| Document | Language | Description |
|---|---|---|
| [CNI_API.md](CNI_API.md) | 中文 | Complete CNI API reference with type mappings and behavioral notes |
| [NETUTILS.md](NETUTILS.md) | 中文 | NetUtils HTTP framework protocol documentation with sequence diagrams |
| [ARGPARSE.md](ARGPARSE.md) | 中文 | Argparse command-line parser API reference |
| [async-architecture.md](docs/async-architecture.md) | 中文 | Async I/O architecture with Mermaid sequence diagrams |

---

## Testing

The [tests/](tests/) directory contains 22 test suites covering TCP, UDP, HTTP, TLS, async I/O, OpenAI client, API integration, error paths (response shapes, log text, protocol garbage), and stress scenarios (RST injection, scheduling stalls, slave failover):

```bash
# Unix
./run_tests.sh

# Windows
run_tests.bat

# Concurrency benchmark (requires wrk)
./bench_concurrent.sh
```

CI runs across **Ubuntu, macOS, and Windows** on both release and nightly Covariant Script channels via [GitHub Actions](.github/workflows/ci.yml).

---

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full text.

Copyright (C) 2017-2026 Michael Lee (李登淳)

---

## Links

- [Covariant Script Official Site](http://covscript.org.cn)
- [Author's GitHub](https://github.com/mikecovlee)
- [ASIO Documentation](https://think-async.com/Asio/)
