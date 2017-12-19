#include "network.hpp"
#include <iostream>
using asio::ip::tcp;
using buffer_type=char[512];
unsigned short port=1000;
int main()
{
	asio::io_service service;
	tcp::socket client(service);
	client.connect(tcp::endpoint(asio::ip::address::from_string("127.0.0.1"),port));
	buffer_type buff;
	std::cin>>buff;
	client.send(asio::buffer(buff));
	client.receive(asio::buffer(buff));
	std::cout<<buff<<std::endl;
	return 0;
}