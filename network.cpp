/*
* Covariant Script Network Extension
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
* Copyright (C) 2018 Michael Lee(李登淳)
* Email: mikecovlee@163.com
* Github: https://github.com/mikecovlee
*/
#include <network/network.hpp>
#include <covscript/cni.hpp>
#include <covscript/extension.hpp>
#include <memory>

namespace network_cs_ext {
	using namespace cs;
	static extension network_ext;
	static extension_t network_ext_shared = make_shared_namespace(network_ext);

	string host_name()
	{
		return asio::ip::host_name();
	}

	namespace tcp {
		static extension tcp_ext;
		static extension_t tcp_ext_shared = make_shared_namespace(tcp_ext);
		using socket_t=std::shared_ptr<cs_impl::network::tcp::socket>;
		using acceptor_t=std::shared_ptr<asio::ip::tcp::acceptor>;
		using endpoint_t=asio::ip::tcp::endpoint;

		var acceptor(const endpoint_t &ep)
		{
			try {
				return var::make<acceptor_t>(
				           std::make_shared<asio::ip::tcp::acceptor>(cs_impl::network::tcp::acceptor(ep)));
			}
			catch (const std::exception &e) {
				throw lang_error(e.what());
			}
		}

		var endpoint(const string &host, number port)
		{
			if (port < 0)
				throw lang_error("Port number can not under zero.");
			else
				return var::make<endpoint_t>(cs_impl::network::tcp::endpoint(host, static_cast<unsigned short>(port)));
		}

		var endpoint_v4(number port)
		{
			if (port < 0)
				throw lang_error("Port number can not under zero.");
			else
				return var::make<endpoint_t>(asio::ip::tcp::v4(), static_cast<unsigned short>(port));
		}

		var endpoint_v6(number port)
		{
			if (port < 0)
				throw lang_error("Port number can not under zero.");
			else
				return var::make<endpoint_t>(asio::ip::tcp::v6(), static_cast<unsigned short>(port));
		}

		var resolve(const string &host, const string &service)
		{
			try {
				return var::make<endpoint_t>(cs_impl::network::tcp::resolve(host, service));
			}
			catch (const std::exception &e) {
				throw lang_error(e.what());
			}
		}

		namespace socket {
			static extension socket_ext;
			static extension_t socket_ext_shared = make_shared_namespace(socket_ext);

			var socket()
			{
				return var::make<socket_t>(std::make_shared<cs_impl::network::tcp::socket>());
			}

			void connect(socket_t &sock, const endpoint_t &ep)
			{
				try {
					sock->connect(ep);
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
				}
			}

			void accept(socket_t &sock, acceptor_t &a)
			{
				try {
					sock->accept(*a);
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
				}
			}

			void close(socket_t &sock)
			{
				try {
					sock->close();
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
				}
			}

			bool is_open(socket_t &sock)
			{
				return sock->is_open();
			}

			string receive(socket_t &sock, number max)
			{
				if (max <= 0)
					throw lang_error("Buffer size must above zero.");
				else {
					try {
						return sock->receive(static_cast<std::size_t>(max));
					}
					catch (const std::exception &e) {
						throw lang_error(e.what());
					}
				}
			}

			void send(socket_t &sock, const string &str)
			{
				try {
					sock->send(str);
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
				}
			}

			endpoint_t remote_endpoint(socket_t &sock)
			{
				try {
					return sock->remote_endpoint();
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
				}
			}
		}

		namespace ep
		{
			static extension ep_ext;
			static extension_t ep_ext_shared = make_shared_namespace(ep_ext);

			string address(const endpoint_t& ep)
			{
				return ep.address().to_string();
			}

			number port(const endpoint_t& ep)
			{
				return ep.port();
			}
		}
	}

	namespace udp {
		static extension udp_ext;
		static extension_t udp_ext_shared = make_shared_namespace(udp_ext);
		using socket_t=std::shared_ptr<cs_impl::network::udp::socket>;
		using endpoint_t=asio::ip::udp::endpoint;

		var endpoint(const string &host, number port)
		{
			if (port < 0)
				throw lang_error("Port number can not under zero.");
			else
				return var::make<endpoint_t>(cs_impl::network::udp::endpoint(host, static_cast<unsigned short>(port)));
		}

		var endpoint_v4(number port)
		{
			if (port < 0)
				throw lang_error("Port number can not under zero.");
			else
				return var::make<endpoint_t>(asio::ip::udp::v4(), static_cast<unsigned short>(port));
		}

		var endpoint_v6(number port)
		{
			if (port < 0)
				throw lang_error("Port number can not under zero.");
			else
				return var::make<endpoint_t>(asio::ip::udp::v6(), static_cast<unsigned short>(port));
		}

		var resolve(const string &host, const string &service)
		{
			try {
				return var::make<endpoint_t>(cs_impl::network::udp::resolve(host, service));
			}
			catch (const std::exception &e) {
				throw lang_error(e.what());
			}
		}

		namespace socket {
			static extension socket_ext;
			static extension_t socket_ext_shared = make_shared_namespace(socket_ext);

			var socket()
			{
				return var::make<socket_t>(std::make_shared<cs_impl::network::udp::socket>());
			}

			void open_v4(socket_t &sock)
			{
				try {
					sock->open_v4();
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
				}
			}

			void open_v6(socket_t &sock)
			{
				try {
					sock->open_v6();
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
				}
			}

			void bind(socket_t &sock, const endpoint_t &ep)
			{
				try {
					sock->bind(ep);
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
				}
			}

			void close(socket_t &sock)
			{
				try {
					sock->close();
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
				}
			}

			bool is_open(socket_t &sock)
			{
				return sock->is_open();
			}

			string receive_from(socket_t &sock, number max, endpoint_t &ep)
			{
				if (max <= 0)
					throw lang_error("Buffer size must above zero.");
				else {
					try {
						return sock->receive_from(static_cast<std::size_t>(max), ep);
					}
					catch (const std::exception &e) {
						throw lang_error(e.what());
					}
				}
			}

			void send_to(socket_t &sock, const string &str, const endpoint_t &ep)
			{
				try {
					sock->send_to(str, ep);
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
				}
			}
		}

		namespace ep
		{
			static extension ep_ext;
			static extension_t ep_ext_shared = make_shared_namespace(ep_ext);

			string address(const endpoint_t& ep)
			{
				return ep.address().to_string();
			}

			number port(const endpoint_t& ep)
			{
				return ep.port();
			}
		}
	}

	void init()
	{
		network_ext.add_var("tcp", var::make_protect<extension_t>(tcp::tcp_ext_shared));
		network_ext.add_var("udp", var::make_protect<extension_t>(udp::udp_ext_shared));
		network_ext.add_var("host_name", make_cni(host_name, true));
		tcp::tcp_ext
		.add_var("socket", var::make_constant<type>(tcp::socket::socket, type_id(typeid(tcp::socket_t)), tcp::socket::socket_ext_shared))
		.add_var("acceptor", make_cni(tcp::acceptor, true))
		.add_var("endpoint", make_cni(tcp::endpoint, true))
		.add_var("endpoint_v4", make_cni(tcp::endpoint_v4, true))
		.add_var("endpoint_v6", make_cni(tcp::endpoint_v6, true))
		.add_var("resolve", make_cni(tcp::resolve, true));
		tcp::socket::socket_ext
		.add_var("connect", make_cni(tcp::socket::connect))
		.add_var("accept", make_cni(tcp::socket::accept))
		.add_var("close", make_cni(tcp::socket::close))
		.add_var("is_open", make_cni(tcp::socket::is_open))
		.add_var("receive", make_cni(tcp::socket::receive))
		.add_var("send", make_cni(tcp::socket::send))
		.add_var("remote_endpoint", make_cni(tcp::socket::remote_endpoint));
		tcp::ep::ep_ext
		.add_var("address", make_cni(tcp::ep::address, true))
		.add_var("port", make_cni(tcp::ep::port, true));
		udp::udp_ext
		.add_var("socket", var::make_constant<type>(udp::socket::socket, type_id(typeid(udp::socket_t)), udp::socket::socket_ext_shared))
		.add_var("endpoint", make_cni(udp::endpoint, true))
		.add_var("endpoint_v4", make_cni(udp::endpoint_v4, true))
		.add_var("endpoint_v6", make_cni(udp::endpoint_v6, true))
		.add_var("resolve", make_cni(udp::resolve, true));
		udp::socket::socket_ext
		.add_var("open_v4", make_cni(udp::socket::open_v4))
		.add_var("open_v6", make_cni(udp::socket::open_v6))
		.add_var("bind", make_cni(udp::socket::bind))
		.add_var("close", make_cni(udp::socket::close))
		.add_var("is_open", make_cni(udp::socket::is_open))
		.add_var("receive_from", make_cni(udp::socket::receive_from))
		.add_var("send_to", make_cni(udp::socket::send_to));
		udp::ep::ep_ext
		.add_var("address", make_cni(udp::ep::address, true))
		.add_var("port", make_cni(udp::ep::port, true));
	}
}
namespace cs_impl {
	template<>
	cs::extension_t &get_ext<network_cs_ext::tcp::socket_t>()
	{
		return network_cs_ext::tcp::socket::socket_ext_shared;
	}

	template<>
	cs::extension_t &get_ext<network_cs_ext::udp::socket_t>()
	{
		return network_cs_ext::udp::socket::socket_ext_shared;
	}

	template<>
	constexpr const char *get_name_of_type<network_cs_ext::tcp::socket_t>()
	{
		return "cs::network::tcp::socket";
	}

	template<>
	constexpr const char *get_name_of_type<network_cs_ext::tcp::acceptor_t>()
	{
		return "cs::network::tcp::acceptor";
	}

	template<>
	constexpr const char *get_name_of_type<network_cs_ext::tcp::endpoint_t>()
	{
		return "cs::network::tcp::endpoint";
	}

	template<>
	constexpr const char *get_name_of_type<network_cs_ext::udp::socket_t>()
	{
		return "cs::network::udp::socket";
	}

	template<>
	constexpr const char *get_name_of_type<network_cs_ext::udp::endpoint_t>()
	{
		return "cs::network::udp::endpoint";
	}
}

cs::extension *cs_extension()
{
	network_cs_ext::init();
	return &network_cs_ext::network_ext;
}