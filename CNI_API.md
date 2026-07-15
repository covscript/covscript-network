# CovScript Network CNI API Reference

CovScript 网络扩展，基于 [Asio](https://think-async.com/Asio/) (standalone)。支持 TCP/UDP 套接字、TLS/SSL 加密、异步 I/O。

## 快速导入

```ecs
import network.tcp as tcp
import network.udp as udp
import network.async as async
```

或使用通配符导入：

```ecs
import network.*
```

## TLS 信任模式

TLS 连接通过 `ssl_options` 配置信任行为。`ssl_options` 是一个 `hash_map`，支持以下键：

| 键 | 类型 | 默认值 | 说明 |
|---|------|--------|------|
| `trust_mode` | `string` | `"auto"` | 信任模式（见下表） |
| `ca_file` | `string` | `null` | CA 证书文件路径（仅 `custom` 模式） |
| `ca_path` | `string` | `null` | CA 证书目录路径（仅 `custom` 模式） |

### trust_mode 选项

| 模式 | 说明 |
|------|------|
| `"auto"` | 自动检测：先尝试 OpenSSL 默认路径，再尝试环境变量，最后回退到平台特定路径（Windows ROOT 证书库 / Linux 常见 CA 路径 / macOS Homebrew 路径） |
| `"openssl"` | 仅使用 OpenSSL 默认验证路径 + 环境变量 |
| `"custom"` | 自定义 CA：需要同时提供 `ca_file` 或 `ca_path` |
| `"insecure"` | 跳过所有证书验证（**仅用于测试，生产环境禁止使用**） |

> **注意**：`verify_peer` 和 `verify_host` 选项在 CNI 层被屏蔽。如需禁用对等验证，使用 `trust_mode = "insecure"`。

> **环境变量缓存**：`auto` 和 `openssl` 模式下，环境变量 `SSL_CERT_FILE` 和 `SSL_CERT_DIR` 在**首次 TLS 初始化时读取并缓存**。之后对进程环境变量的修改不会影响后续 TLS 连接。如需动态切换信任源，使用 `trust_mode = "custom"` 并显式传入 `ca_file` / `ca_path`。

### 示例

```ecs
// 默认信任模式（推荐）
sock.connect_ssl("api.example.com", {"trust_mode": "auto"}.to_hash_map())

// 自定义 CA 证书
sock.connect_ssl("internal.example.com", {
    "trust_mode": "custom",
    "ca_file": "/etc/ssl/custom-ca.pem"
}.to_hash_map())

// 仅测试环境
sock.connect_ssl("localhost", {"trust_mode": "insecure"}.to_hash_map())
```

## 全局工具函数

`import network` 后可直接使用：

| 函数 | 签名 | 返回值 | 说明 |
|------|------|--------|------|
| `host_name` | `() → string` | `string` | 获取本机主机名 |
| `to_fixed_hex` | `(n: int) → string` | `string` | 整数转 16 字节 ASCII 十六进制字符串 |
| `from_fixed_hex` | `(s: string) → int` | `integer` | 16 字节 ASCII 十六进制字符串转整数。输入必须恰好 16 字节 |
| `get_last_global_ssl_trust_report` | `() → string` | `string` | 获取当前线程上最近一次 TLS 握手的信任存储加载报告 |

> **注意**：`get_last_global_ssl_trust_report()` 返回的是**线程级别**的"最近一次"报告。多个 socket 在同一线程上建立 TLS 连接时，后建立的会覆盖前一个的报告。如需获取特定 socket 的报告，使用 `sock.get_ssl_trust_report()`。

---

## TCP

导入：`import network.tcp as tcp`

### 构造函数

| 函数 | 签名 | 返回值 | 说明 |
|------|------|--------|------|
| `tcp.socket` | `() → socket` | `tcp_socket` | 创建 TCP 套接字 |
| `tcp.acceptor` | `(ep: endpoint) → acceptor` | `tcp_acceptor` | 创建 TCP 监听器，绑定到指定端点 |
| `tcp.endpoint` | `(host: string, port: int) → endpoint` | `tcp_endpoint` | 通过主机名和端口创建端点 |
| `tcp.endpoint_v4` | `(port: int) → endpoint` | `tcp_endpoint` | 创建 IPv4 通配端点（`0.0.0.0:port`） |
| `tcp.endpoint_v6` | `(port: int) → endpoint` | `tcp_endpoint` | 创建 IPv6 通配端点（`[::]:port`） |
| `tcp.resolve` | `(host: string, service: string) → array` | `array<endpoint>` | DNS 解析，返回端点列表 |

> **端口范围**：`port` 必须在 `[0, 65535]` 范围内。超出范围会抛出异常。

### socket 方法

| 方法 | 签名 | 说明 |
|------|------|------|
| `connect` | `(ep: endpoint)` | 建立 TCP 连接到指定端点 |
| `connect_ssl` | `(host: string, options: hash_map)` | 建立 TCP 连接后执行 TLS 握手。`options` 为 `ssl_options`（可为 `null`，使用默认值） |
| `accept` | `(acpt: acceptor)` | 接受一个传入连接。阻塞直到有连接到达 |
| `close` | `()` | 关闭套接字。若存在进行中的异步操作会抛出异常（提示使用 `safe_shutdown()`） |

> **说明**：`close()` 会在检测到进行中的异步操作时主动抛出异常，以避免 TLS/socket 生命周期竞态。需要等待异步任务收敛时，请优先使用 `safe_shutdown()`。

| `is_open` | `() → boolean` | 套接字是否打开 |
| `is_ssl` | `() → boolean` | 是否已启用 TLS |
| `get_ssl_trust_report` | `() → string` | 获取此 socket 的 TLS 信任存储加载报告 |
| `set_opt_reuse_address` | `(value: boolean)` | 设置 `SO_REUSEADDR` 选项 |
| `set_opt_no_delay` | `(value: boolean)` | 设置 `TCP_NODELAY` 选项（禁用 Nagle 算法） |
| `set_opt_keep_alive` | `(value: boolean)` | 设置 `SO_KEEPALIVE` 选项 |
| `available` | `() → int` | 可读取的字节数（非阻塞） |
| `receive` | `(max: int) → string` | 读取最多 `max` 字节。阻塞直到至少 1 字节可读 |
| `read` | `(size: int) → string` | 读取恰好 `size` 字节。阻塞直到全部读完 |
| `send` | `(data: string) → int` | 发送数据（单次部分写入，返回实际写入字节数）。需完整发送时使用 `write` |
| `write` | `(data: string)` | 发送数据（保证全部写入，阻塞直到完成） |
| `shutdown` | `()` | 关闭套接字通信通道。与 `close()` 的区别：`shutdown()` 仅关闭通信，socket 保持打开且资源不释放；`close()` 释放所有资源 |
| `safe_shutdown` | `() → boolean` | 安全关闭：协作式等待异步操作全部完成后关闭 TLS 和 TCP。成功返回 `true`；关闭过程中发生错误返回 `false`。在 fiber 环境中通过 `poll` + `yield` 协作等待，不阻塞 OS 线程 |
| `local_endpoint` | `() → endpoint` | 获取本地端点地址 |
| `remote_endpoint` | `() → endpoint` | 获取远程端点地址 |

> **`send` 与 `write` 的区别**：`send` 使用 `write_some`，执行单次写入并返回实际写入的字节数，可能只发送部分数据。`write` 使用 `asio::write`，循环写入直到全部数据发送完毕。**当你需要保证数据完整发送时，请使用 `write`**。此设计对应 BSD socket `send()` vs `write()` 的语义差异。

### socket 静态方法

| 函数 | 签名 | 说明 |
|------|------|------|
| `tcp.get_ssl_trust_report` | `(sock: socket) → string` | 获取指定 socket 的 TLS 信任报告（与实例方法等价） |

### endpoint 方法

| 方法 | 签名 | 返回值 | 说明 |
|------|------|--------|------|
| `address` | `() → string` | `string` | 获取 IP 地址字符串 |
| `is_v4` | `() → boolean` | `boolean` | 是否为 IPv4 地址 |
| `is_v6` | `() → boolean` | `boolean` | 是否为 IPv6 地址 |
| `port` | `() → int` | `integer` | 获取端口号 |

---

## UDP

导入：`import network.udp as udp`

### 构造函数

| 函数 | 签名 | 返回值 | 说明 |
|------|------|--------|------|
| `udp.socket` | `() → socket` | `udp_socket` | 创建 UDP 套接字 |
| `udp.endpoint` | `(host: string, port: int) → endpoint` | `udp_endpoint` | 通过主机名和端口创建端点 |
| `udp.endpoint_v4` | `(port: int) → endpoint` | `udp_endpoint` | 创建 IPv4 通配端点 |
| `udp.endpoint_v6` | `(port: int) → endpoint` | `udp_endpoint` | 创建 IPv6 通配端点 |
| `udp.endpoint_broadcast` | `(port: int) → endpoint` | `udp_endpoint` | 创建 IPv4 广播端点 |
| `udp.resolve` | `(host: string, service: string) → array` | `array<endpoint>` | DNS 解析 |

### socket 方法

| 方法 | 签名 | 说明 |
|------|------|------|
| `open_v4` | `()` | 打开 IPv4 套接字 |
| `open_v6` | `()` | 打开 IPv6 套接字 |
| `bind` | `(ep: endpoint)` | 绑定到指定端点 |
| `connect` | `(ep: endpoint)` | 连接到指定端点（设置默认目标） |
| `close` | `()` | 关闭套接字。若存在进行中的 I/O 会抛出异常（提示使用 `safe_close()`） |
| `safe_close` | `() → boolean` | 安全关闭：等待异步操作完成（默认最多 200ms，可在构建时配置）后独占关闭；超时或独占竞争失败返回 `false` |
| `is_open` | `() → boolean` | 套接字是否打开 |
| `set_opt_reuse_address` | `(value: boolean)` | 设置 `SO_REUSEADDR` |
| `set_opt_broadcast` | `(value: boolean)` | 设置 `SO_BROADCAST` |
| `available` | `() → int` | 可读取的字节数（非阻塞） |
| `receive_from` | `(max: int, ep: endpoint) → string` | 接收数据并获取发送方地址。`ep` 为输出参数 |
| `send_to` | `(data: string, ep: endpoint)` | 向指定端点发送数据 |
| `local_endpoint` | `() → endpoint` | 获取本地端点 |
| `remote_endpoint` | `() → endpoint` | 获取远程端点 |

### endpoint 方法

与 TCP endpoint 相同：`address()`、`is_v4()`、`is_v6()`、`port()`。

---

## 异步 I/O

导入：`import network.async as async`

### 异步状态对象

所有异步操作返回一个 `async.state` 对象，用于轮询操作结果。

#### 创建状态对象

| 函数 | 签名 | 说明 |
|------|------|------|
| `async.state` | `() → state` | 创建新的异步状态对象（通常由异步函数自动创建） |

#### state 方法

| 方法 | 签名 | 返回值 | 说明 |
|------|------|--------|------|
| `has_done` | `() → boolean` | `boolean` | 异步操作是否已完成 |
| `get_result` | `() → string or null` | `string` 或 `null` | 获取读取操作的结果。未完成时返回 `null`。**消耗性操作**：每次调用消耗已读数据 |
| `get_buffer` | `(max_bytes: int) → string or null` | `string` 或 `null` | 从缓冲区读取最多 `max_bytes` 字节。未完成时返回 `null`。**消耗性操作**。单次请求默认上限为 64 MiB |
| `available` | `() → int` | `integer` | 缓冲区中可读字节数（仅对读取操作有效） |
| `eof` | `() → boolean` | `boolean` | 是否遇到 EOF 或连接重置 |
| `get_error` | `() → string or null` | `string` 或 `null` | 获取错误消息。无错误返回 `null` |
| `get_endpoint` | `() → endpoint` | `udp_endpoint` | 获取 UDP 发送方端点（仅 `receive_from` 操作有效） |
| `wait` | `() → boolean` | `boolean` | 阻塞等待操作完成。`true` 表示操作已完成且成功；`false` 表示操作已完成但失败。需获取失败原因时使用 `get_error()` |
| `wait_for` | `(timeout_ms: int) → boolean` | `boolean` | 带超时等待。`true` 表示操作已完成且成功；`false` 表示超时**或**操作已完成但失败。需区分时先用 `has_done()` 判断是否超时，再用 `get_error()` 获取失败原因 |

### 异步 TCP 操作

| 函数 | 签名 | 返回值 | 说明 |
|------|------|--------|------|
| `async.accept` | `(sock: tcp_socket, acpt: acceptor) → state` | `state` | 异步接受连接 |
| `async.connect` | `(sock: tcp_socket, ep: endpoint) → state` | `state` | 异步建立 TCP 连接 |
| `async.connect_ssl` | `(sock: tcp_socket, host: string, options: var) → state` | `state` | 异步 TLS 握手（socket 必须先建立 TCP 连接） |
| `async.read` | `(sock: tcp_socket, n: int) → state` | `state` | 异步读取恰好 `n` 字节 |
| `async.read_until` | `(sock: tcp_socket, state: state, pattern: string)` | - | 异步读取直到匹配 `pattern`。**可重入**：`state` 参数可复用 |
| `async.write` | `(sock: tcp_socket, data: string) → state` | `state` | 异步写入全部数据 |

### 异步 UDP 操作

| 函数 | 签名 | 返回值 | 说明 |
|------|------|--------|------|
| `async.receive_from` | `(sock: udp_socket, n: int) → state` | `state` | 异步接收 UDP 数据 |
| `async.send_to` | `(sock: udp_socket, data: string, ep: endpoint) → state` | `state` | 异步发送 UDP 数据 |

### 事件循环管理

| 函数 | 签名 | 返回值 | 说明 |
|------|------|--------|------|
| `async.poll` | `() → boolean` | `boolean` | 轮询所有待处理事件（非阻塞）。有事件处理返回 `true` |
| `async.poll_once` | `() → boolean` | `boolean` | 轮询最多一个待处理事件（非阻塞） |
| `async.stopped` | `() → boolean` | `boolean` | 事件循环是否已停止 |
| `async.restart` | `()` | - | 重启已停止的事件循环 |
| `async.work_guard` | `() → work_guard` | `work_guard` | 创建 work guard，防止事件循环在没有待处理操作时停止 |
| `async.thread_worker` | `() → thread_worker` | `thread_worker` | 创建工作线程来运行事件循环。析构时自动 join |

### 典型用法

```ecs
// 异步客户端
var sock = new tcp.socket
var guard = new async.work_guard           // 防止 io_context 提前退出
var state = async.connect(sock, tcp.endpoint("127.0.0.1", 8080))

// 等待连接完成（最多 5 秒）
if state.wait_for(5000) && state.get_error() == null
    // 发送请求
    async.write(sock, "Hello\r\n")

    // 异步读取
    state = async.read(sock, 100)
    if state.wait()
        system.out.println(state.get_result())
    end
end

sock.close()
```

```ecs
// 异步服务器
var sock = new tcp.socket
var acpt = tcp.acceptor(tcp.endpoint_v4(8080))
var guard = new async.work_guard
var accept_state = async.accept(sock, acpt)

system.out.println("Waiting for connection...")
if accept_state.wait_for(5000)
    system.out.println("Client connected from " + sock.remote_endpoint().address())
end
```

---

## 完整示例

### TCP 客户端（TLS）

```ecs
import network.tcp as tcp

var sock = new tcp.socket
var endpoints = tcp.resolve("api.deepseek.com", "443")

// 连接到第一个可达端点
foreach ep in endpoints
    try
        sock.connect(ep)
        break
    catch e
        null
    end
end

// TLS 握手
sock.connect_ssl("api.deepseek.com", {"trust_mode": "auto"}.to_hash_map())

// 检查信任报告
system.out.println("TLS trust: " + sock.get_ssl_trust_report())

// 发送和接收
sock.write("GET /v1/models HTTP/1.1\r\nHost: api.deepseek.com\r\nConnection: close\r\n\r\n")
system.out.println(sock.receive(4096))

sock.safe_shutdown()
```

### TCP 服务器

```ecs
import network.tcp as tcp

var acpt = tcp.acceptor(tcp.endpoint_v4(8080))
system.out.println("Listening on port 8080...")

loop
    var sock = new tcp.socket
    sock.accept(acpt)
    system.out.println("Accepted: " + sock.remote_endpoint().address())

    var data = sock.receive(1024)
    sock.write(data)  // echo back
    sock.close()
end
```

---

## 类型说明

| CovScript 类型 | C++ 类型 | 说明 |
|---------------|----------|------|
| `tcp_socket` | `std::shared_ptr<cs_impl::network::tcp::socket>` | TCP 套接字（含 TLS 支持） |
| `tcp_acceptor` | `std::shared_ptr<asio::ip::tcp::acceptor>` | TCP 监听器 |
| `tcp_endpoint` | `asio::ip::tcp::endpoint` | TCP 端点（IP + 端口） |
| `udp_socket` | `std::shared_ptr<cs_impl::network::udp::socket>` | UDP 套接字 |
| `udp_endpoint` | `asio::ip::udp::endpoint` | UDP 端点 |
| `state` | `std::shared_ptr<async::state_type>` | 异步操作状态 |
| `work_guard` | `std::shared_ptr<asio::executor_work_guard<...>>` | 工作守卫 |
| `thread_worker` | `std::shared_ptr<thread_executor_type>` | 事件循环工作线程 |

## 注意事项

1. **异步操作生命周期**：异步操作期间 socket 必须保持存活。创建 `work_guard` 可防止事件循环在所有异步操作完成前停止。
2. **TLS 连接**：同步 `connect_ssl` 方法先建立 TCP 连接再执行 TLS 握手；异步 `async.connect_ssl` 仅执行 TLS 握手（socket 必须先建立 TCP 连接）。握手失败时 SSL 上下文会被自动清理。
3. **`send` vs `write`**：`send` 执行单次写入并返回实际写入字节数，类似 BSD `send()`；`write` 保证全部写入，类似 POSIX `write()`。需要可靠传输时使用 `write`。
4. **`shutdown` vs `close` vs `safe_shutdown`**：`shutdown` 关闭通信通道但不释放资源（socket 保持 `is_open()` 为 true）；`close` 立即关闭并释放 TLS 上下文（如有进行中的异步操作会抛出异常）；`safe_shutdown` 协作式等待所有异步操作完成后关闭 TLS 和 TCP。异步任务等待无超时；TLS close-notify 超时默认 5000ms（`NETWORK_TLS_SHUTDOWN_TIMEOUT_MS`）。在 fiber 环境中通过 `poll` + `yield` 协作等待，不阻塞 OS 线程；非 fiber 环境调用线程一直阻塞到关闭完成。推荐在异步场景中使用 `safe_shutdown`。
5. **信任报告**：建议使用 `sock.get_ssl_trust_report()`（每个 socket 独立），而非全局的 `get_last_global_ssl_trust_report()`（线程级别，可能被覆盖）。
6. **线程安全**：同一 socket 不应并发混合同步和异步操作。异步 API 最多允许一个 pending read/receive 和一个 pending write/send；同方向重叠操作会被拒绝，读写可全双工并行。TLS 异步 handler 绑定到每个 socket 的 strand，可由多个 `async.thread_worker` 安全驱动。
7. **netutils HTTP 客户端**：`netutils` 提供 `http_client` 类（`http_request` / `post` 方法）和 `openai_client` 子类。TLS 验证通过客户端实例的 `set_tls_options({"trust_mode": "auto"}.to_hash_map())` 控制，不再使用全局 `ssl_verify` 标志。详见 [NETUTILS.md](NETUTILS.md)。
8. **异步部分数据**：读取操作可能同时返回错误和已传输数据，例如对端在发送部分内容后关闭连接。完成后应先用 `get_error()`/`eof()` 判断结束原因；`get_result()`、`get_buffer()` 和 `available()` 仍允许读取错误发生前已收到的数据。
9. **缓冲区上限**：TCP/UDP 的同步读取、异步读取及 `state.get_buffer()` 单次默认最多请求 64 MiB；可通过 CMake 的 `NETWORK_MAX_IO_BUFFER_SIZE` 调整。非正数或超限请求会在分配前抛出异常。
