# Network Extension — Async Architecture

本文件描述了 CovScript Network Extension 中所有异步 I/O 操作的时序和生命周期。
图表使用 [Mermaid](https://mermaid.js.org/) 语法，GitHub / VS Code 均可直接渲染。

---

## 1. 整体架构

```mermaid
graph TB
    subgraph "CovScript User Code"
        CS[CovScript Script<br/>import network.async as async]
    end

    subgraph "CNI Layer (network.cpp)"
        OPS[Async Operations<br/>accept / connect / connect_ssl<br/>read / read_until / write<br/>receive_from / send_to]
        STATE[State Object<br/>has_done / get_result / wait / get_error]
        LIFECYCLE[Event Loop<br/>poll / poll_once / work_guard<br/>thread_worker / stopped / restart]
    end

    subgraph "cs_impl::network (network.hpp)"
        SOCK[tcp::socket / udp::socket<br/>async_jobs counter]
        TLS[tls_stream / tls_ctx<br/>exclusive_operation flag]
    end

    subgraph "Asio (standalone)"
        IO[io_context<br/>global singleton]
        TCP[ip::tcp::socket / acceptor]
        SSL[ssl::stream]
        UDP[ip::udp::socket]
    end

    CS -->|"async.read(sock, 100)"| OPS
    OPS -->|"begin_async_read/write() → asio call"| SOCK
    OPS -->|"returns"| STATE
    SOCK -->|"wraps"| TLS
    SOCK -->|"wraps"| TCP
    TLS --> SSL
    TCP --> IO
    UDP --> IO
    LIFECYCLE -->|"poll / poll_one"| IO
    STATE -->|"wait / wait_for → poll"| LIFECYCLE
```

---

## 2. 异步 TCP 客户端完整流程

从 connect → TLS → write → read → shutdown 的完整时序：

```mermaid
sequenceDiagram
    actor Script as CovScript
    participant CNI as CNI (network.cpp)
    participant Socket as tcp::socket
    participant TLS as tls_stream
    participant Asio as io_context
    participant Net as Network

    Note over Script,Net: === 1. 建立 TCP 连接 ===
    Script->>CNI: async.connect(sock, endpoint)
    CNI->>Socket: begin_async_connect() (独占)
    CNI->>Asio: sock.async_connect(ep, callback)
    CNI-->>Script: return state
    Script->>CNI: state.wait_for(5000)
    loop poll
        CNI->>Asio: io.poll()
    end
    Asio-->>CNI: callback(ec)
    CNI->>Socket: end_async_io()
    CNI->>CNI: state.has_done = true
    Script->>CNI: state.get_error()
    CNI-->>Script: null (= success)

    Note over Script,Net: === 2. TLS 握手 (可选) ===
    Script->>CNI: async.connect_ssl(sock, host, options)
    CNI->>Socket: begin_tls_handshake()<br/>(CAS exclusive_operation + async_jobs)
    CNI->>Socket: prepare_ssl(host, options)
    Socket->>TLS: new asio::ssl::stream(sock)
    TLS->>TLS: configure_client_context()
    CNI->>TLS: tls_stream.async_handshake(client, callback)
    CNI-->>Script: return state
    Script->>CNI: state.wait()
    loop poll
        CNI->>Asio: io.poll()
    end
    Asio-->>CNI: callback(ec)
    alt ec fails
        CNI->>Socket: reset_ssl() (保留 trust report)
    end
    CNI->>Socket: end_tls_handshake()
    CNI->>CNI: state.has_done = true

    Note over Script,Net: === 3. 异步写 ===
    Script->>CNI: async.write(sock, data)
    CNI->>CNI: buffer << data
    CNI->>Socket: begin_async_write()
    CNI->>TLS: async_write(tls_stream, buffer, strand-bound callback)
    CNI-->>Script: return state
    Script->>CNI: state.wait()
    loop poll
        CNI->>Asio: io.poll()
    end
    Asio-->>CNI: callback(ec, bytes)
    CNI->>Socket: end_async_io()
    CNI->>CNI: state.has_done = true

    Note over Script,Net: === 4. 异步读 ===
    Script->>CNI: async.read(sock, 1024)
    CNI->>CNI: buffer.prepare(1024)
    CNI->>Socket: begin_async_read()
    CNI->>TLS: async_read(tls_stream, buffer, strand-bound callback)
    CNI-->>Script: return state
    Script->>CNI: state.wait()
    loop poll
        CNI->>Asio: io.poll()
    end
    Asio-->>CNI: callback(ec, bytes)
    CNI->>CNI: buffer.commit(bytes)
    CNI->>Socket: end_async_io()
    CNI->>CNI: state.has_done = true
    Script->>CNI: state.get_result()
    CNI-->>Script: data string (ec≠null 时仍可返回部分数据)

    Note over Script,Net: === 5. 安全关闭 ===
    Script->>CNI: sock.safe_shutdown()
    CNI->>Socket: begin_draining_exclusive()<br/>(先阻止新 I/O)
    loop while async_jobs > 0 (NETWORK_SAFE_SHUTDOWN_TIMEOUT_MS)
        CNI->>Asio: io.poll()
        CNI->>Script: cs_runtime_yield()
    end
    opt TLS enabled
        CNI->>TLS: async_shutdown(strand-bound callback)
        loop close-notify 未完成且未超时
            CNI->>Asio: io.poll()
            CNI->>Script: cs_runtime_yield()
        end
        alt close-notify 超时
            CNI->>Socket: cancel + close raw socket
            CNI->>Asio: 驱动 handler 完成后 clear_ssl()
        else close-notify 完成
            CNI->>Socket: clear_ssl()
        end
    end
    CNI->>Socket: raw shutdown + close
    CNI->>Socket: end_draining_exclusive()
    CNI-->>Script: return success
```

---

## 3. 异步 TCP 服务端流程

```mermaid
sequenceDiagram
    actor Script as CovScript
    participant CNI as CNI (network.cpp)
    participant Socket as tcp::socket
    participant Acpt as tcp::acceptor
    participant Asio as io_context
    participant Client as Client

    Note over Script,Client: === 1. 创建 work_guard 防止 io_context 提前退出 ===
    Script->>CNI: new async.work_guard
    CNI->>CNI: lifecycle_mutex lock
    CNI->>Asio: if thread_executors==0 && io.stopped() → io.restart()
    CNI->>CNI: lifecycle_mutex unlock
    CNI-->>Script: return work_guard

    Note over Script,Client: === 2. 异步接受连接 ===
    Script->>CNI: async.accept(server_sock, acceptor)
    CNI->>Socket: begin_async_connect() (独占)
    CNI->>Acpt: acceptor.async_accept(sock, callback)
    CNI-->>Script: return state
    Script->>CNI: state.wait()
    loop poll
        CNI->>Asio: io.poll()
    end
    Client->>Acpt: TCP SYN...
    Asio-->>CNI: callback(ec)
    CNI->>Socket: end_async_io()
    CNI->>CNI: state.has_done = true

    Note over Script,Client: === 3. 异步读取请求 (可重入 read_until) ===
    Script->>CNI: new async.state
    Script->>CNI: async.read_until(sock, state, "\r\n\r\n")
    CNI->>Socket: begin_async_read()
    CNI->>CNI: state.init=true, has_done=false
    CNI->>Socket: async_read_until(sock, buffer, "\r\n\r\n", callback)
    Client->>Socket: HTTP request data...
    Asio-->>CNI: callback(ec, bytes)
    Note over CNI: async_read_until 已在内部提交 streambuf 数据<br/>回调不得再次 commit
    CNI->>Socket: end_async_io()
    CNI->>CNI: state.has_done = true
    Script->>CNI: state.get_result()
    CNI-->>Script: HTTP headers

    Note over Script,Client: === 4. 异步发送响应 ===
    Script->>CNI: async.write(sock, response)
    CNI->>Socket: begin_async_write()
    CNI->>Socket: async_write(sock, buffer, callback)
    Asio-->>CNI: callback(ec, bytes)
    CNI->>Socket: end_async_io()
    CNI->>CNI: state.has_done = true
```

---

## 4. 异步 UDP 流程

UDP 与 TCP 一样通过方向级准入跟踪异步收发，并用 `exclusive_operation` 防止 close 与新 I/O 交错。每个 socket 最多同时存在一个 receive 和一个 send；同方向重叠会被拒绝。UDP 没有 TLS，但关闭 socket 仍需要独占准入。

```mermaid
sequenceDiagram
    actor Script as CovScript
    participant CNI as CNI (network.cpp)
    participant Sock as udp::socket
    participant Asio as io_context

    Note over Script,Asio: === 异步接收 ===
    Script->>CNI: async.receive_from(sock, 1024)
    CNI->>CNI: buffer.prepare(1024)
    CNI->>Sock: begin_async_receive()<br/>(方向 CAS + 双检 exclusive_operation + async_jobs)
    CNI->>Sock: sock.async_receive_from(buffer, ep, callback)
    CNI-->>Script: return state
    Script->>CNI: state.wait()
    loop poll
        CNI->>Asio: io.poll()
    end
    Asio-->>CNI: callback(ec, bytes)
    CNI->>CNI: buffer.commit(bytes)
    CNI->>Sock: end_async_io()
    CNI->>CNI: state.has_done = true
    Script->>CNI: state.get_result()
    CNI-->>Script: data
    Script->>CNI: state.get_endpoint()
    CNI-->>Script: sender endpoint

    Note over Script,Asio: === 异步发送 ===
    Script->>CNI: async.send_to(sock, data, ep)
    CNI->>CNI: buffer << data
    CNI->>Sock: begin_async_send()<br/>(方向 CAS + 双检 exclusive_operation + async_jobs)
    CNI->>Sock: sock.async_send_to(buffer, ep, callback)
    CNI-->>Script: return state
    Asio-->>CNI: callback(ec, bytes)
    CNI->>Sock: end_async_io()
    CNI->>CNI: state.has_done = true
```

---

## 5. Async State 对象生命周期状态机

异步函数通常创建并返回已经进入 Pending 的 state；只有 `read_until` 接受调用方创建的 state，并允许完成后复用：

```mermaid
stateDiagram-v2
    [*] --> Ready: new async.state<br/>(仅供 read_until)
    [*] --> Pending: accept / connect / connect_ssl<br/>read / write / receive_from / send_to
    Ready --> Pending: read_until 准入并提交成功
    note right of Ready: init=false 或上次操作已完成
    note right of Pending: init=true<br/>async_jobs += 1<br/>is_read=true (读类)

    Pending --> Done: Asio callback 触发
    note right of Pending: has_done=false<br/>可通过 wait() / wait_for() / poll() 驱动

    Done --> Consumed: get_result() / get_buffer()
    note right of Done: has_done=true<br/>可检查 ec / eof / get_error
    Consumed --> Pending: 再次 read_until<br/>(仅复用型 state)
    Consumed --> [*]: state 释放

    state Error_check <<choice>>
    Done --> Error_check: get_error()
    Error_check --> Success: ec == null
    Error_check --> Partial: ec != null (EOF / 对端关闭)
    Success --> Consumed: 取完整数据
    Partial --> Consumed: 取部分数据 (ec≠null 时仍可读取)
```

> **部分数据语义 (v1.4)**：异步读操作完成时如果 `ec != null`（例如对端关闭连接），`get_result()` 和 `get_buffer()` 仍然返回已传输的部分数据。调用者应先通过 `get_error()` / `eof()` 判断结束原因，再决定如何处理数据。

### State 对象可重入 (read_until)

`read_until` 是唯一**可重入**的异步操作。同一个 `state` 对象可在 callback 完成并消费当前匹配结果后复用；若尚未消费，streambuf 中的旧分隔符仍可能立即再次匹配。

```mermaid
stateDiagram-v2
    [*] --> Ready: new async.state
    Ready --> Reading: async.read_until(sock, state, "\n")
    Reading --> ResultReady: callback done
    ResultReady --> Ready: get_result() / get_buffer()<br/>消费当前匹配段
    Ready --> Reading: async.read_until(sock, state, "\r\n\r\n")
    Reading --> ResultReady: callback done
```

> **失败回滚**：如果 I/O 准入失败，state 不会被修改；如果 `begin_async_read()` 成功但 `async_read_until` 发起失败（例如 `std::bad_alloc`），catch 块会恢复 `init`、`is_read`、`has_done`、`ec` 到调用前的值，state 对象保持可用。

---

## 6. 事件循环管理

```mermaid
sequenceDiagram
    actor Script as CovScript
    participant GL as global_settings
    participant IO as io_context
    participant Worker as thread_executor
    participant WG as work_guard

    Note over Script,WG: === 单线程模式 (无 thread_worker) ===
    Script->>GL: async.poll()
    GL->>GL: thread_executors != 0 ? → return 0 (fast path)
    GL->>GL: lifecycle_mutex lock
    GL->>GL: thread_executors == 0 ?
    GL->>IO: io.poll()
    IO-->>GL: handlers executed
    GL->>GL: lifecycle_mutex unlock
    GL-->>Script: return has_work

    Script->>WG: new async.work_guard
    WG->>GL: lifecycle_mutex lock
    WG->>GL: thread_executors==0 && io.stopped() ?
    alt needs restart
        WG->>IO: io.restart()
    end
    WG->>GL: lifecycle_mutex unlock
    Note over WG: work_guard 持有 io_context executor 引用

    Script->>WG: guard = null (析构)
    Note over IO: work_guard 释放 → io_context 可能 stopped

    Note over Script,WG: === 多线程模式 (有 thread_worker) ===
    Script->>Worker: new async.thread_worker
    Worker->>GL: lifecycle_mutex lock
    Worker->>GL: thread_executors==0 && stopped → io.restart()
    Worker->>GL: create work_guard
    Worker->>GL: thread_executors++
    Worker->>GL: lifecycle_mutex unlock
    Worker->>Worker: spawn thread → executor()
    activate Worker

    loop executor loop
        Worker->>IO: while poll_one() > 0 (drain)
        Worker->>Worker: running == false ?
        Worker->>IO: run_one_for(默认 1ms)
    end
    Worker->>GL: thread_executors-- (在 lambda 退出时)
    deactivate Worker

    Script->>GL: async.poll()
    GL->>GL: thread_executors > 0 ? → return 0 (skip)
    Note over GL: worker 线程负责驱动 io_context

    Script->>Worker: worker = null (析构)
    Worker->>Worker: running = false
    Worker->>Worker: try asio::post(io, wakeup)
    Worker->>Worker: worker.join()

    Note over Script,WG: === restart 语义 ===
    Script->>GL: async.restart()
    GL->>GL: lifecycle_mutex lock
    GL->>GL: thread_executors==0 && stopped ?
    alt yes
        GL->>IO: io.restart()
    else no
        Note over GL: skip — worker 构造时已 restart
    end
    GL->>GL: lifecycle_mutex unlock
```

> **关键变更 (v1.4)**：`poll()` 在 `thread_executors > 0` 时走无锁快路径直接返回 0，避免与 worker 线程竞争 `lifecycle_mutex`。Worker 线程的 `io.restart()` 调用已移至构造函数内（在 `lifecycle_mutex` 保护下），不再在事件循环中每轮检查。`run_one_for` 的默认等待为 1ms，可通过 CMake 的 `NETWORK_THREAD_WORKER_POLL_MS` 调整。

---

## 7. async_jobs 计数器与 exclusive_operation

### I/O 准入机制

TCP socket 的所有 I/O 操作（同步和异步）都必须通过方向级 `begin_io_job()` 或 `begin_exclusive_operation()` 准入：

| 准入方式 | 使用者 | 原子操作 | 阻塞条件 |
|---------|--------|---------|---------|
| `begin_io_job(direction)` | 普通 I/O（read/write/send/receive） | 方向 CAS + `fetch_add(1)` + 双检 `exclusive_operation` | 同方向已有操作或 `exclusive_operation == true` |
| `begin_exclusive_operation()` | TLS 握手、close、shutdown | CAS `exclusive_operation` + CAS `async_jobs` | 已有独占操作或 `async_jobs > 0` |

```mermaid
sequenceDiagram
    actor Script as CovScript
    participant Sock as tcp::socket
    participant IO as io_context

    Note over Script,IO: async_jobs 跟踪进行中的 I/O；exclusive_operation 标记独占操作

    rect rgb(220, 255, 220)
    Note over Script,IO: 普通 I/O: async.read()
    Script->>Sock: begin_io_job(read): CAS read_operation → check exclusive_operation → fetch_add(1)
    Script->>IO: async_read(sock, buffer, callback)
    end

    rect rgb(255, 220, 220)
    Note over Script,IO: 独占操作: close()
    Script->>Sock: begin_exclusive_operation(): CAS exclusive_operation → CAS async_jobs
    Note over Sock: 此时新 I/O 的 begin_io_job() 会被 exclusive_operation 拒绝
    end

    IO-->>Sock: callback: end_async_io() → fetch_sub(1)

    Note over Script,IO: === safe_shutdown 流程 ===
    Script->>Sock: sock.safe_shutdown()
    Sock->>Sock: begin_draining_exclusive()
    Note over Sock: 新 I/O 被 exclusive_operation 拒绝
    loop async_jobs > 0 (NETWORK_SAFE_SHUTDOWN_TIMEOUT_MS)
        Script->>IO: io.poll()
        Script->>Script: runtime.yield()
    end
    opt TLS enabled
        Sock->>IO: tls_stream.async_shutdown(strand)
        loop close-notify 未完成且未超时
            Script->>IO: io.poll()
            Script->>Script: runtime.yield()
        end
        alt TLS timeout
            Sock->>Sock: cancel + close raw socket
            Script->>IO: 驱动 shutdown handler 完成
        end
        Sock->>Sock: clear_ssl()
    end
    Sock->>Sock: raw shutdown + close
    Sock->>Sock: end_draining_exclusive()
    Sock-->>Script: return success
```

> **设计要点**：`close()` 和 `shutdown()` 通过 `scoped_exclusive_operation` 原子地占用 socket 独占权，防止 TOCTOU 窗口。普通 I/O 先预约 read/write 方向，再双检 `exclusive_operation`；同方向重叠直接拒绝，一读一写仍可全双工并行。TLS composed operation 的 handler 绑定到每个 socket 的 strand，多个 worker 不会并发访问同一 SSL stream。TCP `safe_shutdown()` 和 UDP `safe_close()` 的 drain 超时（默认 200ms）均通过 CMake 的 `NETWORK_SAFE_SHUTDOWN_TIMEOUT_MS` 调整。TLS close-notify 阶段的超时独立使用 `NETWORK_TLS_SHUTDOWN_TIMEOUT_MS`（默认 5000ms）。

---

## 8. 带 Fiber 的异步协作模式

```mermaid
sequenceDiagram
    actor Main as Main Fiber
    actor SrvFiber as Server Fiber
    participant CNI as CNI
    participant Asio as io_context

    Note over Main,Asio: Fiber 模式: 手动调度,协同多任务

    Main->>SrvFiber: fiber.create(server_func, sock)
    Main->>SrvFiber: server_fiber.resume()

    activate SrvFiber
    SrvFiber->>CNI: async.accept(sock, acceptor)
    CNI-->>SrvFiber: return state

    loop until state.has_done()
        SrvFiber->>CNI: async.poll_once()
        SrvFiber->>SrvFiber: fiber.yield()
        deactivate SrvFiber
        Main->>SrvFiber: server_fiber.resume()
        activate SrvFiber
    end

    SrvFiber->>CNI: sock.receive(128)
    CNI-->>SrvFiber: data
    SrvFiber->>CNI: sock.write(data)
    SrvFiber->>CNI: sock.close()
    deactivate SrvFiber

    Main->>CNI: async.poll()
```

---

## 9. 操作速查表

### 异步操作 (返回 state)

| 操作 | 方向 | TLS 支持 | 可重入 | I/O 准入 |
|------|------|---------|--------|---------|
| `async.accept` | 服务端 | — | ❌ | `begin_async_connect` (独占) |
| `async.connect` | 客户端 | — | ❌ | `begin_async_connect` (独占) |
| `async.connect_ssl` | 客户端 | ✅ | ❌ | `begin_tls_handshake` (独占) |
| `async.read` | 双向 | ✅ | ❌ | `begin_async_read` |
| `async.read_until` | 双向 | ✅ | ✅ (同 state) | `begin_async_read` |
| `async.write` | 双向 | ✅ | ❌ | `begin_async_write` |
| `async.receive_from` | UDP | — | ❌ | `begin_async_receive` |
| `async.send_to` | UDP | — | ❌ | `begin_async_send` |

### 同步操作

| 操作 | I/O 准入 | 说明 |
|------|---------|------|
| `connect` / `accept` | `scoped_io_job` | RAII 守卫 |
| `receive` / `read` / `send` / `write` | `scoped_io_job` | RAII 守卫 |
| `connect_ssl` | `begin/end_tls_handshake` | 独占 socket，异常路径释放预约 |
| `close` / `shutdown` | `scoped_exclusive_operation` | 独占 socket |
| `available` | `try_begin_io_job` (noexcept) | 被拒绝时返回 0 |
| `peer_closed` | `try_begin_io_job` (noexcept) | 被拒绝时返回 false；非阻塞 `MSG_PEEK` 探测对端关闭，临时切换并恢复 `non_blocking` 模式（仅影响同步操作，异步操作不受该标志影响） |

UDP 的同步 `receive_from` / `send_to` 使用 `scoped_io_job`，`close` 使用独占预约，`available` 在独占关闭期间返回 0。

### 同步等待

| 方法 | 超时 | 行为 |
|------|------|------|
| `state.wait()` | 无（直到完成） | 循环 poll + yield |
| `state.wait_for(ms)` | 自定义 | 循环 poll + yield |
| `state.has_done()` | 无 | 非阻塞检查 |

### 生命周期管理

| 对象/函数 | 作用 |
|-----------|------|
| `work_guard` | RAII 防止 io_context 因无工作而停止 |
| `thread_worker` | 后台线程持续 drive 事件循环 |
| `poll()` / `poll_once()` | 单线程模式的手动事件驱动 |
| `restart()` | 重启已停止的 io_context (需 `thread_executors==0`) |
| `safe_shutdown()` | TCP: 先原子设置 draining-exclusive 阻止新 I/O，再协作式等待 async_jobs 清零后关闭（drain 超时 `NETWORK_SAFE_SHUTDOWN_TIMEOUT_MS`，默认 200ms）。TLS close-notify 超时默认 5000ms（`NETWORK_TLS_SHUTDOWN_TIMEOUT_MS`） |
| `safe_close()` | UDP: 等待 async_jobs=0 后关闭（默认 200ms 超时，通过 `NETWORK_SAFE_SHUTDOWN_TIMEOUT_MS` 配置） |
