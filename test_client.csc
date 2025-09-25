import network
using network

var sock = new tcp.socket
sock.connect(tcp.endpoint("127.0.0.1", 1024))
sock.set_opt_no_delay(true)

loop
    sock.write(system.in.getline() + "\r\n")
end
