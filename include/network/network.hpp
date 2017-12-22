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

		template<typename char_t=char>
		class buffer final {
			char_t *buff = nullptr;
		public:
			buffer() = delete;

			buffer(const buffer &) = delete;

			buffer(buffer &b) noexcept
			{
				std::swap(this->buff, b.buff);
			}

			buffer(std::size_t size) : buff(new char_t[size]) {}

			~buffer()
			{
				delete[] buff;
			}

			char_t *get() const
			{
				return buff;
			}
		};
		namespace tcp {
			using asio::ip::tcp;
			static tcp::resolver resolver(cs_net_service);

			tcp::acceptor acceptor(const tcp::endpoint &ep)
			{
				return std::move(tcp::acceptor(cs_net_service, ep));
			}

			tcp::endpoint endpoint(const std::string &address, unsigned short port)
			{
				return std::move(tcp::endpoint(asio::ip::address::from_string(address), port));
			}

			tcp::endpoint resolve(const std::string &host, const std::string &service)
			{
				return *resolver.resolve({host, service});
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

				std::string receive(std::size_t maximum)
				{
					buffer<> buff(maximum);
					std::size_t actually = sock.receive(asio::buffer(buff.get(), maximum));
					return std::string(buff.get(), actually);
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
		namespace udp {
			using asio::ip::udp;
			static udp::resolver resolver(cs_net_service);

			udp::endpoint endpoint(const std::string &address, unsigned short port)
			{
				return std::move(udp::endpoint(asio::ip::address::from_string(address), port));
			}

			udp::endpoint resolve(const std::string &host, const std::string &service)
			{
				return *resolver.resolve({host, service});
			}

			class socket final {
				udp::socket sock;
			public:
				socket() : sock(cs_net_service) {}

				socket(const socket &) = delete;

				void open_v4()
				{
					sock.open(udp::v4());
				}

				void open_v6()
				{
					sock.open(udp::v6());
				}

				void bind(const udp::endpoint &ep)
				{
					sock.bind(ep);
				}

				void close()
				{
					sock.close();
				}

				bool is_open()
				{
					return sock.is_open();
				}

				std::string receive_from(std::size_t maximum, udp::endpoint &ep)
				{
					buffer<> buff(maximum);
					std::size_t actually = sock.receive_from(asio::buffer(buff.get(), maximum), ep);
					return std::string(buff.get(),actually);
				}

				void send_to(const std::string &s, const udp::endpoint &ep)
				{
					sock.send_to(asio::buffer(s), ep);
				}
			};
		}
	}
}