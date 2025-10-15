# CovScript-NetUtils 协议文档

版本：1.2.0
作者：CovScript 网络工具库

## 1. 总览

CovScript-NetUtils 支持单机或多进程模式：

单机模式：Worker 直接处理 HTTP 请求。

多进程模式：Master 节点接收 HTTP 请求并分发给多个 Slave Worker 节点进行处理。

协议设计目标：

HTTP 请求队列异步派发。

单条 session 异步发送，多条 session 并发需要多个 Slave。

Master ↔ Slave 通过自定义内容长度编码 (16 字节十六进制) 进行通信。

## 2. HTTP Session 格式
### 2.1 Session 内容

Master 与 Slave 通信使用 http_session 序列化对象：

{
  "url": "/example",
  "args": "id=1",
  "host": "127.0.0.1",
  "method": "GET",
  "version": "1.1",
  "connection": "keep-alive",
  "content_length": 0,
  "post_data": ""
}


method 支持 GET 和 POST。

connection 表示是否 keep-alive。

post_data 包含 POST 请求的原始内容。

### 2.2 序列化/反序列化

serialize() → JSON 字符串。

deserialize() ← JSON 字符串重建 http_session 对象。

发送前通过 send_content(sock, data) 包装为固定长度头 + 内容：

[16字节十六进制长度][序列化内容]

## 3. Master ↔ Slave 协议
### 3.1 Handshake

Master 接收新 Slave 连接：

Master 发送：

SERVER 1.2.0 <rank>


Slave 回复：

WORKER 1.2.0 <rank>


Master 验证版本号与 rank。

成功后 Slave 状态设置为 state=1（空闲）。

### 3.2 心跳 (Heartbeat)

Master 定期向空闲 Slave 发送：

SLAVE_HEALTH_QUERY


Slave 回复：

SLAVE_HEALTH_CONFIRM


Master 更新 last_conn_time，维持心跳计时。

心跳失败则将 Slave 状态设为 -1（断开）。

### 3.3 请求分发 (Dispatch)

Master 选择空闲 Slave (state=1)。

从 conn->request_queue[request_idx++] 取出下一条 HTTP session。

Master 使用 send_content 发送序列化 session 给 Slave。

Slave 反序列化 session 并处理：

调用绑定的 URL handler 或文件服务。

生成响应并通过 send_content 返回给 Master。

Master 收到响应：

放入 session.response。

request_queue.pop_front() 并 --request_idx。

### 3.4 Keep-Alive / Timeout 控制

Master 每个 HTTP 连接有：

keep_alive_timeout：毫秒级超时时间。

max_keep_alive：最大请求数。

超过请求数或超时：

Master 返回 HTTP/1.1 408 Request Timeout 或关闭连接。

Slave 对每条 session 独立处理，可以并发处理多条 session（前提是有多个 Slave）。

### 3.5 错误处理
错误码	描述
200 OK	成功响应
400 Bad Request	请求头为空或解析失败
403 Forbidden	访问文件受限或路径非法
404 Not Found	文件不存在
408 Request Timeout	Keep-Alive 超时或 Slave 超时
500 Internal Server Error	读取文件或网络错误
503 Service Unavailable	Slave 无可用
000 End of file	EOF

Master 会根据 state_codes 返回对应的 HTTP 响应。

Slave 也会直接返回 HTTP 响应给 Master。

## 4. HTTP 文件服务规则

URL → 文件映射：

绑定 URL 使用 bind_page(url, path, state_code)。

默认服务 wwwroot/index.html 对目录请求。

MIME 类型：

自动根据扩展名推导：

.html/.htm → text/html
.txt → text/plain
.js → application/javascript
.css → text/css
.png → image/png
.jpg/.jpeg → image/jpeg
.gif → image/gif
.json → application/json


其它扩展名默认 application/octet-stream。

## 5. Session 队列 & request_idx

每个 HTTP 连接使用 request_queue 存储待处理 session。

Master 分发：

request_idx 指向下一个待 dispatch 的 session。

Master 响应：

完成 response 后 pop_front() 并 --request_idx。

保证单 connection 内 session 顺序正确，避免越界。