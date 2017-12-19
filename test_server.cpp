#include "network.hpp"
#include <iostream>
int main()
{
	using namespace cs_impl;
	auto acceptor=network::tcp::acceptor(network::tcp::endpoint("127.0.0.1",1000));
	network::tcp::socket sock;
	sock.accept(acceptor);
	while(true) {
		std::string s;
		sock.receive(s,512);
		std::cout<<s<<std::endl;
		sock.send(s+"[RECEIVED]");
	}
	return 0;
}