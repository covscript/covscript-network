#pragma once

#define ASIO_STANDALONE

#if defined(__WIN32__) || defined(WIN32)
#define _WIN32_WINDOWS
#endif

#include "asio.hpp"
#include <string>

namespace cs_impl {
	namespace network {
		static asio::io_service cs_net_service;
		namespace tcp {
			using asio::ip::tcp;

			tcp::acceptor acceptor(const tcp::endpoint &ep)
			{
				return std::move(tcp::acceptor(cs_net_service, ep));
			}

			tcp::endpoint endpoint(const std::string &address, unsigned short port)
			{
				return std::move(tcp::endpoint(asio::ip::address::from_string(address), port));
			}

			class socket final {
				tcp::socket sock;
			public:
				socket() : sock(cs_net_service) {}

				socket(const socket &) = delete;

				void connect(const tcp::endpoint &ep)
				{
					sock.connect(ep);
				}

				void close()
				{
					sock.close();
				}

				void accept(tcp::acceptor &a)
				{
					a.accept(sock);
				}

				bool is_open()
				{
					return sock.is_open();
				}

				void receive(std::string &str, std::size_t maximum)
				{
					char *buff = new char[maximum + 1];
					buff[sock.receive(asio::buffer(buff, maximum))] = '\0';
					str = buff;
					delete[] buff;
				}

				void send(const std::string &s)
				{
					sock.send(asio::buffer(s));
				}

				tcp::endpoint remote_endpoint()
				{
					return std::move(sock.remote_endpoint());
				}
			};
		}
	}
}