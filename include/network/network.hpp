#pragma once
/*
* Covariant Script Network
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*
* Copyright (C) 2020 Michael Lee(李登淳)
* Email: mikecovlee@163.com
* Github: https://github.com/mikecovlee
*/
#define ASIO_STANDALONE

#if defined(__WIN32__) || defined(WIN32)
#define _WIN32_WINDOWS
#endif

#include "asio.hpp"
#include <covscript/covscript.hpp>
#include <string>

namespace cs_impl {
	namespace network {
		static asio::io_service cs_net_service;

		template<typename _fT, typename ...ArgsT>
		auto do_for(std::size_t time_ms, _fT&& func, ArgsT&&...args)
		{
			using ret_t = decltype(func(std::declval<ArgsT>(args)...));
			std::future<ret_t> future = std::async(std::launch::async, func, std::forward<ArgsT>(args)...);
			if (future.wait_for(std::chrono::milliseconds(time_ms)) != std::future_status::ready)
				throw cs::lang_error("Connect Timeout.");
			return future.get();
		}

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
				std::size_t timeout_time=1000;
				tcp::socket sock;
			public:
				socket() : sock(cs_net_service) {}

				socket(const socket &) = delete;

				void set_timeout(std::size_t time)
				{
					timeout_time=time;
				}

				void connect(const tcp::endpoint &ep)
				{
					try {
						do_for(timeout_time, [this, &ep]{ sock.connect(ep); });
					} catch(...) {
						sock.close();
						throw;
					}
					if (!sock.is_open())
						throw cs::lang_error("Connect failed.");
				}

				void close()
				{
					sock.close();
				}

				void accept(tcp::acceptor &a)
				{
					try {
						do_for(timeout_time, [this, &a]{ a.accept(sock); });
					} catch(...) {
						sock.close();
						throw;
					}
					if (!sock.is_open())
						throw cs::lang_error("Accept failed.");
				}

				bool is_open()
				{
					return sock.is_open();
				}

				std::string receive(std::size_t maximum)
				{
					return do_for(timeout_time, [this, maximum]{
						buffer<> buff(maximum);
						std::size_t actually = sock.read_some(asio::buffer(buff.get(), maximum));
						return std::string(buff.get(), actually);
					});
				}

				void send(const std::string &s)
				{
					do_for(timeout_time, [this, &s]{
						sock.write_some(asio::buffer(s));
					});
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