#include "network.hpp"
#include <iostream>
using asio::ip::tcp;
unsigned short port=1000;
int main()
{
	asio::io_service service;
	tcp::resolver resolver(service);
	tcp::socket client(service);
	asio::connect(client,resolver.resolve(tcp::endpoint(asio::ip::address_v4::from_string("127.0.0.1"),port)));
	char buff[64];
	std::cin>>buff;
	client.write_some(asio::buffer(buff));
	client.read_some(asio::buffer(buff));
	std::cout<<buff<<std::endl;
	return 0;
}