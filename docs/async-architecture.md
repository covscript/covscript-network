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
        TLS[tls_stream / tls_ctx]
    end

    subgraph "Asio (standalone)"
        IO[io_context<br/>global singleton]
        TCP[ip::tcp::socket / acceptor]
        SSL[ssl::stream]
        UDP[ip::udp::socket]
    end

    CS -->|"async.read(sock, 100)"| OPS
    OPS -->|"async_read(sock, buffer, callback)"| SOCK
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
    CNI->>Socket: async_jobs.fetch_add(1)
    CNI->>Asio: sock.async_connect(ep, callback)
    CNI-->>Script: return state
    Script->>CNI: state.wait_for(5000)
    loop poll
        CNI->>Asio: io.poll()
    end
    Asio-->>CNI: callback(ec)
    CNI->>Socket: async_jobs.fetch_sub(1)
    CNI->>CNI: state.has_done = true
    Script->>CNI: state.get_error()
    CNI-->>Script: null (= success)

    Note over Script,Net: === 2. TLS 握手 (可选) ===
    Script->>CNI: async.connect_ssl(sock, host, options)
    CNI->>Socket: prepare_ssl(host, options)
    Socket->>TLS: new asio::ssl::stream(sock)
    TLS->>TLS: configure_client_context()
    CNI->>Socket: async_jobs.fetch_add(1)
    CNI->>TLS: tls_stream.async_handshake(client, callback)
    CNI-->>Script: return state
    Script->>CNI: state.wait()
    loop poll
        CNI->>Asio: io.poll()
    end
    Asio-->>CNI: callback(ec)
    alt ec fails
        CNI->>Socket: reset_ssl()
    end
    CNI->>Socket: async_jobs.fetch_sub(1)

    Note over Script,Net: === 3. 异步写 ===
    Script->>CNI: async.write(sock, data)
    CNI->>CNI: buffer << data
    CNI->>Socket: async_jobs.fetch_add(1)
    CNI->>TLS: async_write(tls_stream, buffer, callback)
    CNI-->>Script: return state
    Script->>CNI: state.wait()
    loop poll
        CNI->>Asio: io.poll()
    end
    Asio-->>CNI: callback(ec, bytes)
    CNI->>Socket: async_jobs.fetch_sub(1)

    Note over Script,Net: === 4. 异步读 ===
    Script->>CNI: async.read(sock, 1024)
    CNI->>CNI: buffer.prepare(1024)
    CNI->>Socket: async_jobs.fetch_add(1)
    CNI->>TLS: async_read(tls_stream, buffer, callback)
    CNI-->>Script: return state
    Script->>CNI: state.wait()
    loop poll
        CNI->>Asio: io.poll()
    end
    Asio-->>CNI: callback(ec, bytes)
    CNI->>CNI: buffer.commit(bytes)
    CNI->>Socket: async_jobs.fetch_sub(1)
    Script->>CNI: state.get_result()
    CNI-->>Script: data string

    Note over Script,Net: === 5. 安全关闭 ===
    Script->>CNI: sock.safe_shutdown()
    CNI->>Socket: check async_jobs == 0?
    loop while async_jobs > 0 (max 200ms)
        CNI->>Asio: io.poll()
        CNI->>Script: cs_runtime_yield()
    end
    alt async_jobs == 0
        CNI->>Socket: sock.shutdown()
        CNI->>TLS: tls_stream.shutdown(ec)
        CNI->>Socket: clear_ssl()
        CNI->>Socket: sock.close()
        CNI-->>Script: return true
    else async_jobs > 0
        CNI-->>Script: return false
    end
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
    CNI->>Asio: if io.stopped() → io.restart()
    CNI->>Asio: executor.on_work_started()
    CNI-->>Script: return work_guard

    Note over Script,Client: === 2. 异步接受连接 ===
    Script->>CNI: async.accept(server_sock, acceptor)
    CNI->>Socket: async_jobs.fetch_add(1)
    CNI->>Acpt: acceptor.async_accept(sock, callback)
    CNI-->>Script: return state
    Script->>CNI: state.wait()
    loop poll
        CNI->>Asio: io.poll()
    end
    Client->>Acpt: TCP SYN...
    Asio-->>CNI: callback(ec)
    CNI->>Socket: async_jobs.fetch_sub(1)

    Note over Script,Client: === 3. 异步读取请求 (可重入 read_until) ===
    Script->>CNI: new async.state
    Script->>CNI: async.read_until(sock, state, "\r\n\r\n")
    CNI->>Socket: async_jobs.fetch_add(1)
    CNI->>Socket: async_read_until(sock, buffer, "\r\n\r\n", callback)
    Client->>Socket: HTTP request data...
    Asio-->>CNI: callback(ec, bytes)
    CNI->>CNI: buffer.commit(bytes)
    CNI->>Socket: async_jobs.fetch_sub(1)
    Script->>CNI: state.get_result()
    CNI-->>Script: HTTP headers

    Note over Script,Client: === 4. 异步发送响应 ===
    Script->>CNI: async.write(sock, response)
    CNI->>Socket: async_jobs.fetch_add(1)
    CNI->>Socket: async_write(sock, buffer, callback)
    Asio-->>CNI: callback(ec, bytes)
    CNI->>Socket: async_jobs.fetch_sub(1)
```

---

## 4. 异步 UDP 流程

```mermaid
sequenceDiagram
    actor Script as CovScript
    participant CNI as CNI (network.cpp)
    participant Sock as udp::socket
    participant Asio as io_context

    Note over Script,Asio: === 异步接收 ===
    Script->>CNI: async.receive_from(sock, 1024)
    CNI->>CNI: buffer.prepare(1024)
    CNI->>Sock: async_jobs.fetch_add(1)
    CNI->>Sock: sock.async_receive_from(buffer, ep, callback)
    CNI-->>Script: return state
    Script->>CNI: state.wait()
    loop poll
        CNI->>Asio: io.poll()
    end
    Asio-->>CNI: callback(ec, bytes)
    CNI->>CNI: buffer.commit(bytes)
    CNI->>Sock: async_jobs.fetch_sub(1)
    Script->>CNI: state.get_result()
    CNI-->>Script: data
    Script->>CNI: state.get_endpoint()
    CNI-->>Script: sender endpoint

    Note over Script,Asio: === 异步发送 ===
    Script->>CNI: async.send_to(sock, data, ep)
    CNI->>CNI: buffer << data
    CNI->>Sock: async_jobs.fetch_add(1)
    CNI->>Sock: sock.async_send_to(buffer, ep, callback)
    CNI-->>Script: return state
    Asio-->>CNI: callback(ec, bytes)
    CNI->>Sock: async_jobs.fetch_sub(1)
```

---

## 5. Async State 对象生命周期状态机

`async.state` 对象的状态转换：

```mermaid
stateDiagram-v2
    [*] --> Created: new async.state
    Created --> Init: async.read(sock, n) 绑定
    Created --> Init: async.read_until(sock, state, pat) 绑定
    Created --> Init: async.write(sock, data) 绑定
    Created --> Init: async.receive_from(sock, n) 绑定
    Created --> Init: async.send_to(sock, data, ep) 绑定
    note right of Created: init=false<br/>has_done=false

    Init --> Pending: Asio 异步操作提交
    note right of Init: init=true<br/>async_jobs += 1<br/>is_read=true (读类)

    Pending --> Done: Asio callback 触发
    note right of Pending: has_done=false<br/>可通过 wait() / wait_for() / poll() 驱动

    Done --> Consumed: get_result() / get_buffer()
    note right of Done: has_done=true<br/>可检查 ec / eof / get_error

    Consumed --> [*]

    state Error_check <<choice>>
    Done --> Error_check: get_error()
    Error_check --> Success: ec == null
    Error_check --> Failed: ec != null
    Success --> Consumed: 取数据
    Failed --> [*]: 读取失败,丢弃数据
```

### State 对象可重入 (read_until)

```mermaid
stateDiagram-v2
    [*] --> Ready: new async.state
    Ready --> Reading: async.read_until(sock, state, "\n")
    Reading --> Ready: callback done<br/>(可立即再次 read_until)
    Ready --> Reading: async.read_until(sock, state, "\r\n\r\n")
    Reading --> Ready: callback done
```

> `read_until` 是唯一**可重入**的异步操作——同一个 `state` 对象可以在 callback 完成后立即复用，无需创建新 state。

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
    GL->>GL: thread_executors == 0 ?
    GL->>IO: io.poll()
    IO-->>GL: handlers executed
    GL-->>Script: return has_work

    Script->>WG: new async.work_guard
    WG->>IO: io.stopped() ?
    alt stopped
        WG->>IO: io.restart()
    end
    WG->>IO: on_work_started()
    Note over WG: io_context 不会因无工作而停止

    Script->>WG: guard = null (析构)
    WG->>IO: on_work_finished()
    Note over IO: 若无其他 work,下次 poll 后 stopped=true

    Note over Script,WG: === 多线程模式 (有 thread_worker) ===
    Script->>Worker: new async.thread_worker
    Worker->>GL: thread_executors++
    Worker->>Worker: spawn thread → executor()
    activate Worker

    loop executor loop
        Worker->>IO: if stopped → io.restart()
        Worker->>IO: while poll_one() > 0
        Worker->>IO: run_one_for(1ms)
    end

    Script->>GL: async.poll()
    GL->>GL: thread_executors > 0 ?
    GL-->>Script: return 0 (skip! worker handles it)

    Script->>Worker: worker = null (析构)
    Worker->>Worker: running = false
    Worker->>IO: asio::post(io, wakeup)
    Worker->>Worker: worker.join()
    Worker->>GL: thread_executors--
    deactivate Worker

    Note over Script,WG: === restart 语义 ===
    Script->>GL: async.restart()
    GL->>GL: thread_executors == 0 ?
    alt thread_executors == 0
        GL->>IO: io.restart()
    else thread_executors > 0
        Note over GL: NO-OP: worker 内部自行 restart
    end
```

---

## 7. async_jobs 计数器和 safe_shutdown

```mermaid
sequenceDiagram
    actor Script as CovScript
    participant Sock as tcp::socket
    participant IO as io_context

    Note over Script,IO: async_jobs 跟踪所有进行中的异步操作

    rect rgb(220, 255, 220)
    Note over Script,IO: 异步操作 A: async.read()
    Script->>Sock: async_jobs++ (now 1)
    Script->>IO: async_read(sock, buffer, callback)
    end

    rect rgb(220, 220, 255)
    Note over Script,IO: 异步操作 B: async.write()
    Script->>Sock: async_jobs++ (now 2)
    Script->>IO: async_write(sock, buffer, callback)
    end

    IO-->>Sock: callback A: async_jobs-- (now 1)
    IO-->>Sock: callback B: async_jobs-- (now 0)

    Note over Script,IO: === safe_shutdown 流程 ===
    Script->>Sock: sock.safe_shutdown()
    Sock->>Sock: async_jobs == 0 ?

    alt async_jobs > 0
        loop max 200ms
            Script->>IO: io.poll()
            Script->>Script: runtime.yield()
        end
        alt async_jobs still > 0
            Sock-->>Script: return false (拒绝关闭)
        end
    end

    Sock->>Sock: sock.shutdown()
    Sock->>Sock: tls_stream.shutdown()
    Sock->>Sock: clear_ssl()
    Sock->>Sock: sock.close()
    Sock-->>Script: return true
```

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

| 操作 | 方向 | TLS 支持 | 可重入 | async_jobs |
|------|------|---------|--------|------------|
| `async.accept` | 服务端 | — | ❌ | ✅ |
| `async.connect` | 客户端 | — | ❌ | ✅ |
| `async.connect_ssl` | 客户端 | ✅ | ❌ | ✅ |
| `async.read` | 双向 | ✅ | ❌ | ✅ |
| `async.read_until` | 双向 | ✅ | ✅ (同 state) | ✅ |
| `async.write` | 双向 | ✅ | ❌ | ✅ |
| `async.receive_from` | UDP | — | ❌ | ✅ |
| `async.send_to` | UDP | — | ❌ | ✅ |

### 同步等待

| 方法 | 超时 | 行为 |
|------|------|------|
| `state.wait()` | 30s | 循环 poll + yield |
| `state.wait_for(ms)` | 自定义 | 循环 poll + yield |
| `state.has_done()` | 无 | 非阻塞检查 |

### 生命周期管理

| 对象/函数 | 作用 |
|-----------|------|
| `work_guard` | RAII 防止 io_context 因无工作而停止 |
| `thread_worker` | 后台线程持续 drive 事件循环 |
| `poll()` | 单线程模式的手动事件驱动 |
| `restart()` | 重启已停止的 io_context |
| `safe_shutdown()` | 等待 async_jobs=0 后关闭 (200ms 超时) |
