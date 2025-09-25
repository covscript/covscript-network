import network
using network

function wait_for(state, time)
    var start_time = runtime.time()
    while !state.has_done()
        async.poll_once()
        if runtime.time() - start_time > time
            break
        else
            runtime.delay(10)
        end
    end
end

var sock = new tcp.socket
var acpt = tcp.acceptor(tcp.endpoint_v4(1024))
var state = async.accept(sock, acpt)
while !state.has_done()
    system.out.println("Waiting...")
    wait_for(state, 1000)
end
state = new async.state
loop
    if !async.poll()
        async.restart()
    end
    async.read_until(sock, state, "\r\n")
    while !state.has_done()
        system.out.println("Receiving...")
        wait_for(state, 1000)
    end
    system.out.print(state.get_result())
end
