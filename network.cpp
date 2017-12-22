/*
* Covariant Script Network Extension
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
* Copyright (C) 2017 Michael Lee(李登淳)
* Email: mikecovlee@163.com
* Github: https://github.com/mikecovlee
*/
#include <network/network.hpp>
#include <covscript/extension.hpp>
#include <covscript/cni.hpp>
#include <covscript/extensions/string.hpp>
#include <memory>

namespace network_cs_ext {
	using namespace cs;
	static extension network_ext;
	static extension_t network_ext_shared = make_shared_extension(network_ext);

	string host_name()
	{
		return asio::ip::host_name();
	}

	namespace tcp {
		static extension tcp_ext;
		static extension_t tcp_ext_shared = make_shared_extension(tcp_ext);
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
			static extension_t socket_ext_shared = make_shared_extension(socket_ext);

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
	}

	namespace udp {
		static extension udp_ext;
		static extension_t udp_ext_shared = make_shared_extension(udp_ext);
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
			static extension_t socket_ext_shared = make_shared_extension(socket_ext);

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
	}

	void init()
	{
		string_cs_ext::init();
		network_ext.add_var("tcp", var::make_protect<extension_t>(tcp::tcp_ext_shared));
		network_ext.add_var("udp", var::make_protect<extension_t>(udp::udp_ext_shared));
		network_ext.add_var("host_name", var::make_protect<callable>(cni(host_name), true));
		tcp::tcp_ext.add_var("socket", var::make_constant<type>(tcp::socket::socket, typeid(tcp::socket_t).hash_code(),
		                     tcp::socket::socket_ext_shared));
		tcp::tcp_ext.add_var("acceptor", var::make_protect<callable>(cni(tcp::acceptor), true));
		tcp::tcp_ext.add_var("endpoint", var::make_protect<callable>(cni(tcp::endpoint), true));
		tcp::tcp_ext.add_var("endpoint_v4", var::make_protect<callable>(cni(tcp::endpoint_v4), true));
		tcp::tcp_ext.add_var("endpoint_v6", var::make_protect<callable>(cni(tcp::endpoint_v6), true));
		tcp::tcp_ext.add_var("resolve", var::make_protect<callable>(cni(tcp::resolve), true));
		tcp::socket::socket_ext.add_var("connect", var::make_protect<callable>(cni(tcp::socket::connect)));
		tcp::socket::socket_ext.add_var("accept", var::make_protect<callable>(cni(tcp::socket::accept)));
		tcp::socket::socket_ext.add_var("close", var::make_protect<callable>(cni(tcp::socket::close)));
		tcp::socket::socket_ext.add_var("is_open", var::make_protect<callable>(cni(tcp::socket::is_open)));
		tcp::socket::socket_ext.add_var("receive", var::make_protect<callable>(cni(tcp::socket::receive)));
		tcp::socket::socket_ext.add_var("send", var::make_protect<callable>(cni(tcp::socket::send)));
		tcp::socket::socket_ext.add_var("remote_endpoint",
		                                var::make_protect<callable>(cni(tcp::socket::remote_endpoint)));
		udp::udp_ext.add_var("socket", var::make_constant<type>(udp::socket::socket, typeid(udp::socket_t).hash_code(),
		                     udp::socket::socket_ext_shared));
		udp::udp_ext.add_var("endpoint", var::make_protect<callable>(cni(udp::endpoint), true));
		udp::udp_ext.add_var("endpoint_v4", var::make_protect<callable>(cni(udp::endpoint_v4), true));
		udp::udp_ext.add_var("endpoint_v6", var::make_protect<callable>(cni(udp::endpoint_v6), true));
		udp::udp_ext.add_var("resolve", var::make_protect<callable>(cni(udp::resolve), true));
		udp::socket::socket_ext.add_var("open_v4", var::make_protect<callable>(cni(udp::socket::open_v4)));
		udp::socket::socket_ext.add_var("open_v6", var::make_protect<callable>(cni(udp::socket::open_v6)));
		udp::socket::socket_ext.add_var("bind", var::make_protect<callable>(cni(udp::socket::bind)));
		udp::socket::socket_ext.add_var("close", var::make_protect<callable>(cni(udp::socket::close)));
		udp::socket::socket_ext.add_var("is_open", var::make_protect<callable>(cni(udp::socket::is_open)));
		udp::socket::socket_ext.add_var("receive_from", var::make_protect<callable>(cni(udp::socket::receive_from)));
		udp::socket::socket_ext.add_var("send_to", var::make_protect<callable>(cni(udp::socket::send_to)));
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