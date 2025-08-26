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
#include <streambuf>
#include <iostream>
#include <vector>
#include <string>

namespace cs_impl {
	namespace network {
		static asio::io_service cs_net_service;

		template <typename char_t = char>
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
			class socket_streambuf : public std::streambuf {
			private:
				bool flush_buffer()
				{
					std::ptrdiff_t n = pptr() - pbase();
					if (n <= 0)
						return true;

					asio::error_code ec;
					std::size_t written = asio::write(socket_, asio::buffer(pbase(), n), ec);

					if (ec || written != static_cast<std::size_t>(n)) {
						return false;
					}

					pbump(-n);
					return true;
				}

				tcp::socket &socket_;
				std::vector<char> buffer_;

			protected:
				int_type underflow() override
				{
					if (gptr() < egptr()) {
						return traits_type::to_int_type(*gptr());
					}

					asio::error_code ec;
					std::size_t n = socket_.read_some(asio::buffer(buffer_), ec);

					if (ec || n == 0) {
						return traits_type::eof();
					}

					setg(buffer_.data(), buffer_.data(), buffer_.data() + n);
					return traits_type::to_int_type(*gptr());
				}

				int_type overflow(int_type ch = traits_type::eof()) override
				{
					if (pptr() != pbase()) {
						if (!flush_buffer()) {
							return traits_type::eof();
						}
					}

					if (!traits_type::eq_int_type(ch, traits_type::eof())) {
						*pptr() = traits_type::to_char_type(ch);
						pbump(1);
					}

					return traits_type::not_eof(ch);
				}

				int sync() override
				{
					return flush_buffer() ? 0 : -1;
				}

			public:
				explicit socket_streambuf(tcp::socket &socket, std::size_t buff_sz = 8192)
					: socket_(socket), buffer_(buff_sz)
				{
					setg(buffer_.data(), buffer_.data(), buffer_.data());
					setp(buffer_.data(), buffer_.data() + buffer_.size());
				}

				~socket_streambuf()
				{
					sync();
				}
			};

			class socket_stream : public std::iostream {
			private:
				socket_streambuf buf_;

			public:
				explicit socket_stream(tcp::socket &socket) : std::iostream(nullptr), buf_(socket)
				{
					rdbuf(&buf_);
				}
			};

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

				std::size_t available()
				{
					return sock.available();
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

				cs::istream get_istream()
				{
					return std::shared_ptr<std::istream>(new socket_stream(sock));
				}

				cs::ostream get_ostream()
				{
					return std::shared_ptr<std::ostream>(new socket_stream(sock));
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