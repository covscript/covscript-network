#include "network.hpp"
#include <iostream>
int main()
{
	using namespace cs_impl;
	network::tcp::socket sock;
	sock.connect(network::tcp::endpoint("127.0.0.1",1000));
	while(true) {
		std::string s;
		std::getline(std::cin,s);
		if(!s.empty())
		{
			sock.send(s);
			sock.receive(s,512);
			std::cout<<s<<std::endl;
		}
	}
	return 0;
}