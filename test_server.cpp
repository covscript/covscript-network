#include "network.hpp"
#include <iostream>
using asio::ip::tcp;
unsigned short port=1000;
int main()
{
	asio::io_service service;
	tcp::acceptor a(service,tcp::endpoint(asio::ip::address_v4::from_string("127.0.0.1"),port));
	while(true) {
		tcp::socket server(service);
		a.accept(server);
		char buff[64];
		server.read_some(asio::buffer(buff));
		std::cout<<buff<<std::endl;
		server.write_some(asio::buffer(buff));
	}
	return 0;
}