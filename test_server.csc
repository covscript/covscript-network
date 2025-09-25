import network
using network

function wait_for(co, time)
    var start_time = runtime.time()
    var result = null
    while (result = co.resume()) && runtime.time() - start_time < time
        runtime.delay(10)
    end
    return result
end

var sock = new tcp.socket
var acpt = tcp.acceptor(tcp.endpoint_v4(1024))
var acpt_co = fiber.create([]()->runtime.await(sock.accept, acpt))

var wait_times = 0
while wait_for(acpt_co, 1000)
    system.out.println("Waiting for " + ++wait_times + "s")
end

var state = new async.state

loop
    async.read_until(sock, state, "\r\n")
    var start_time = runtime.time()
    while !state.has_done()
        async.poll_once()
        if runtime.time() - start_time > 1000
            system.out.println("Receiving...")
            start_time = runtime.time()
        end
        runtime.delay(100)
    end
    system.out.print(state.get_result())
    if !async.poll()
        async.restart()
    end
end
