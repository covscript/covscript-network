#pragma once
/*
* Covariant Script Network
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU Affero General Public License as published
* by the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU Affero General Public License for more details.
*
* You should have received a copy of the GNU Affero General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*
* Copyright (C) 2018 Michael Lee(李登淳)
* Email: mikecovlee@163.com
* Github: https://github.com/mikecovlee
*/
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
					std::size_t actually = sock.read_some(asio::buffer(buff.get(), maximum));
					return std::string(buff.get(), actually);
				}

				void send(const std::string &s)
				{
					sock.write_some(asio::buffer(s));
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
					return std::string(buff.get(), actually);
				}

				void send_to(const std::string &s, const udp::endpoint &ep)
				{
					sock.send_to(asio::buffer(s), ep);
				}
			};
		}
	}
}