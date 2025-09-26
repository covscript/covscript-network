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

# Create a TCP socket
var sock = new tcp.socket

block
    # Create a work guard to ensure asynchronous sessions remain valid
    var guard = new async.work_guard
    # Submit an asynchronous connect session and obtain its state
    var state = async.connect(sock, tcp.endpoint("127.0.0.1", 1024))
    # Loop to periodically check connection status
    loop
        system.out.println("Waiting for connection...")
    until wait_for(state, 1000)  # Wait up to 1 second per iteration
    # Handle any connection error
    if state.get_error() != null
        system.out.println("Error: " + state.get_error())
        system.exit(0)
    end
end

system.out.println("Connection Established.")

# Coroutine to handle standard input and send it to the TCP server
function stdio_worker(sock)
    loop
        # Prompt user for input
        system.out.println("Waiting for user input...")
        var input = runtime.await(system.in.getline)
        # Exit the loop if user types "EXIT"
        if input.toupper() == "EXIT"
            sock.close()
            break
        end
        # Skip empty lines to avoid sending unnecessary messages
        if input == ""
            continue
        end
        # Send the input line to the server with CRLF delimiter
        sock.write(input + "\r\n")
    end
end

# Create a coroutine (fiber) to run the stdio_worker
var stdio_co = fiber.create(stdio_worker, sock)

# Loop to resume the coroutine and process user input
# Uses a small delay to reduce CPU busy-waiting
while stdio_co.resume()
    runtime.delay(10)
end

system.out.println("Connection Closed.")
