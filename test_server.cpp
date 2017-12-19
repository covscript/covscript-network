#include "network.hpp"
#include <iostream>
using asio::ip::tcp;
using buffer_type=char[512];
unsigned short port=1000;
int main()
{
	asio::io_service service;
	tcp::acceptor a(service,tcp::endpoint(asio::ip::address::from_string("127.0.0.1"),port));
	while(true) {
		tcp::socket server(service);
		a.accept(server);
		buffer_type buff;
		server.receive(asio::buffer(buff));
		std::cout<<buff<<std::endl;
		server.send(asio::buffer(buff));
	}
	return 0;
}