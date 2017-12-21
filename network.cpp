/*
* Covariant Script Darwin Extension
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
	static extension_t network_ext_shared=make_shared_extension(network_ext);
	namespace tcp {
		static extension tcp_ext;
		static extension_t tcp_ext_shared=make_shared_extension(tcp_ext);
		using socket_t=std::shared_ptr<cs_impl::network::tcp::socket>;
		using acceptor_t=std::shared_ptr<asio::ip::tcp::acceptor>;
		using endpoint_t=asio::ip::tcp::endpoint;
		var acceptor(const endpoint_t& ep)
		{
			return var::make<acceptor_t>(std::make_shared<asio::ip::tcp::acceptor>(cs_impl::network::tcp::acceptor(ep)));
		}
		var endpoint(const string& host,number port)
		{
			if(port<0)
				throw lang_error("Port number can not under zero.");
			else
				return var::make<endpoint_t>(cs_impl::network::tcp::endpoint(host,static_cast<unsigned short>(port)));
		}
		namespace socket {
			static extension socket_ext;
			static extension_t socket_ext_shared=make_shared_extension(socket_ext);
			var socket()
			{
				return var::make<socket_t>(std::make_shared<cs_impl::network::tcp::socket>());
			}
			void connect(socket_t& sock,const endpoint_t& ep)
			{
				try {
					sock->connect(ep);
				}
				catch(const std::exception& e) {
					throw lang_error(e.what());
				}
			}
			void accept(socket_t& sock,acceptor_t& a)
			{
				try {
					sock->accept(*a);
				}
				catch(const std::exception& e) {
					throw lang_error(e.what());
				}
			}
			void close(socket_t& sock)
			{
				try {
					sock->close();
				}
				catch(const std::exception& e) {
					throw lang_error(e.what());
				}
			}
			bool is_open(socket_t& sock)
			{
				return sock->is_open();
			}
			void receive(socket_t& sock,string& str,number max)
			{
				if(max<=0)
					throw lang_error("Buffer size must above zero.");
				else {
					try {
						sock->receive(str,static_cast<std::size_t>(max));
					}
					catch(const std::exception& e) {
						throw lang_error(e.what());
					}
				}
			}
			void send(socket_t& sock,const string& str)
			{
				try {
					sock->send(str);
				}
				catch(const std::exception& e) {
					throw lang_error(e.what());
				}
			}
			endpoint_t remote_endpoint(socket_t& sock)
			{
				try {
					return sock->remote_endpoint();
				}
				catch(const std::exception& e) {
					throw lang_error(e.what());
				}
			}
		}
	}
	void init()
	{
		string_cs_ext::init();
		network_ext.add_var("tcp",var::make_protect<extension_t>(tcp::tcp_ext_shared));
		tcp::tcp_ext.add_var("socket",var::make_constant<type>(tcp::socket::socket,typeid(tcp::socket_t).hash_code(),tcp::socket::socket_ext_shared));
		tcp::tcp_ext.add_var("acceptor",var::make_protect<callable>(cni(tcp::acceptor),true));
		tcp::tcp_ext.add_var("endpoint",var::make_protect<callable>(cni(tcp::endpoint),true));
		tcp::socket::socket_ext.add_var("connect",var::make_protect<callable>(cni(tcp::socket::connect)));
		tcp::socket::socket_ext.add_var("accept",var::make_protect<callable>(cni(tcp::socket::accept)));
		tcp::socket::socket_ext.add_var("close",var::make_protect<callable>(cni(tcp::socket::close)));
		tcp::socket::socket_ext.add_var("is_open",var::make_protect<callable>(cni(tcp::socket::is_open)));
		tcp::socket::socket_ext.add_var("receive",var::make_protect<callable>(cni(tcp::socket::receive)));
		tcp::socket::socket_ext.add_var("send",var::make_protect<callable>(cni(tcp::socket::send)));
		tcp::socket::socket_ext.add_var("remote_endpoint",var::make_protect<callable>(cni(tcp::socket::remote_endpoint)));
	}
}
namespace cs_impl {
	template<>
	cs::extension_t &get_ext<network_cs_ext::tcp::socket_t>()
	{
		return network_cs_ext::tcp::socket::socket_ext_shared;
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
}
cs::extension *cs_extension()
{
	network_cs_ext::init();
	return &network_cs_ext::network_ext;
}