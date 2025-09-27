import network.tcp as tcp
import network.async as async

# Wait for an asynchronous state to complete or until a timeout
function wait_for(state, time)
    var start_time = runtime.time()
    loop
        # Poll pending asynchronous events once
        async.poll_once()
        # Break if the specified timeout is reached
        if runtime.time() - start_time >= time
            break
        end
        # Small delay to reduce busy-waiting CPU usage
        runtime.delay(10)
    until state.has_done()
    # Return true if the state has completed, false if timeout
    return state.has_done()
end

# Create a work guard to ensure asynchronous sessions remain valid
var guard = new async.work_guard, state = null

# Create a TCP socket for communication
var sock = new tcp.socket
# Create a TCP acceptor to listen for incoming connections on port 1024
var acpt = tcp.acceptor(tcp.endpoint_v4(1024))

# Submit an asynchronous accept session and obtain its state
state = async.accept(sock, acpt)
# Loop until a client connection is accepted
loop
    system.out.println("Waiting for incoming connection...")
until wait_for(state, 1000)  # Poll every 1 second

# Handle any errors during the accept operation
if state.get_error() != null
    system.out.println("Error: " + state.get_error())
    system.exit(-1)
end

system.out.println("Connection Established.")

# Prepare a new asynchronous state object for reading data
state = new async.state

# Loop to read data from the connected socket until program termination
loop
    # Submit an asynchronous read operation until the delimiter "\r\n"
    async.read_until(sock, state, "\r\n")
    # Wait for the read operation to complete
    loop
        system.out.println("Receiving data...")
    until wait_for(state, 1000)
    # Handle read errors
    if state.get_error() != null
        system.out.println("Error: " + state.get_error())
        system.exit(-1)
    end
    # Output the received data to console
    system.out.print(state.get_result())
end
