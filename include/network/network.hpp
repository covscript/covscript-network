#pragma once
/*
 * Covariant Script Network
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Copyright (C) 2017-2025 Michael Lee(李登淳)
 *
 * Email:   mikecovlee@163.com
 * Github:  https://github.com/mikecovlee
 * Website: http://covscript.org.cn
 */
#define ASIO_STANDALONE

#if defined(__WIN32__) || defined(WIN32)
#define _WIN32_WINDOWS
#endif

#include "asio.hpp"
#include <covscript/covscript.hpp>
#include <string>
#include <atomic>

namespace cs_impl {
	namespace network {
		static asio::io_context &get_io_context()
		{
			static asio::io_context instance;
			return instance;
		}
		namespace tcp {
			using asio::ip::tcp;

			tcp::acceptor acceptor(const tcp::endpoint &ep)
			{
				return std::move(tcp::acceptor(get_io_context(), ep));
			}

			tcp::endpoint endpoint(const std::string &address, unsigned short port)
			{
				return std::move(tcp::endpoint(asio::ip::make_address(address), port));
			}

			cs::var resolve(const std::string &host, const std::string &service)
			{
				static tcp::resolver resolver(get_io_context());
				tcp::resolver::results_type results = resolver.resolve(host, service);
				cs::var ret = cs::var::make<cs::array>();
				cs::array &arr = ret.val<cs::array>();
				for (auto &ep : results)
					arr.push_back(cs::var::make<tcp::endpoint>(ep));
				return ret;
			}

			class socket final {
				tcp::socket sock;

			public:
				std::atomic<std::size_t> async_jobs{0};

				socket() : sock(get_io_context()) {}

				socket(const socket &) = delete;

				tcp::socket &get_raw()
				{
					return sock;
				}

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

				template <typename opt_t>
				void set_option(opt_t &&opt)
				{
					sock.set_option(std::forward<opt_t>(opt));
				}

				std::size_t available()
				{
					return sock.available();
				}

				std::string receive(std::size_t maximum)
				{
					std::vector<char> buff(maximum);
					std::size_t actually = sock.read_some(asio::buffer(buff));
					return std::string(buff.data(), actually);
				}

				std::string read(std::size_t size)
				{
					std::vector<char> buff(size);
					std::size_t n = asio::read(sock, asio::buffer(buff));
					return std::string(buff.data(), n);
				}

				void send(const std::string &s)
				{
					sock.write_some(asio::buffer(s));
				}

				void write(const std::string &s)
				{
					asio::write(sock, asio::buffer(s));
				}

				void shutdown()
				{
					sock.shutdown(tcp::socket::shutdown_both);
				}

				tcp::endpoint local_endpoint()
				{
					return sock.local_endpoint();
				}

				tcp::endpoint remote_endpoint()
				{
					return sock.remote_endpoint();
				}
			};
		}
		namespace udp {
			using asio::ip::udp;

			udp::endpoint endpoint(const std::string &address, unsigned short port)
			{
				return std::move(udp::endpoint(asio::ip::make_address(address), port));
			}

			cs::var resolve(const std::string &host, const std::string &service)
			{
				static udp::resolver resolver(get_io_context());
				udp::resolver::results_type results = resolver.resolve(host, service);
				cs::var ret = cs::var::make<cs::array>();
				cs::array &arr = ret.val<cs::array>();
				for (auto &ep : results)
					arr.push_back(cs::var::make<udp::endpoint>(ep));
				return ret;
			}

			class socket final {
				udp::socket sock;

			public:
				std::atomic<std::size_t> async_jobs{0};

				socket() : sock(get_io_context()) {}

				socket(const socket &) = delete;

				udp::socket &get_raw()
				{
					return sock;
				}

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

				void connect(const udp::endpoint &ep)
				{
					sock.connect(ep);
				}

				void close()
				{
					sock.close();
				}

				bool is_open()
				{
					return sock.is_open();
				}

				template <typename opt_t>
				void set_option(opt_t &&opt)
				{
					sock.set_option(std::forward<opt_t>(opt));
				}

				std::size_t available()
				{
					return sock.available();
				}

				std::string receive_from(std::size_t maximum, udp::endpoint &ep)
				{
					std::vector<char> buff(maximum);
					std::size_t actually = sock.receive_from(asio::buffer(buff), ep);
					return std::string(buff.data(), actually);
				}

				void send_to(const std::string &s, const udp::endpoint &ep)
				{
					sock.send_to(asio::buffer(s), ep);
				}

				udp::endpoint local_endpoint()
				{
					return sock.local_endpoint();
				}

				udp::endpoint remote_endpoint()
				{
					return sock.remote_endpoint();
				}
			};
		}
	}
}