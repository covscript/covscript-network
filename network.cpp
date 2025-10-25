/*
 * Covariant Script Network Extension
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

#include <network/network.hpp>
#include <covscript/dll.hpp>
#include <covscript/cni.hpp>
#include <thread>
#include <memory>
#include <regex>

inline void cs_runtime_yield()
{
#if COVSCRIPT_ABI_VERSION >= 250908
	if (cs::current_process->fiber_stack.empty())
		std::this_thread::sleep_for(std::chrono::milliseconds(1));
	else
		cs::fiber::yield();
#else
	std::this_thread::sleep_for(std::chrono::milliseconds(1));
#endif
}

namespace network_cs_ext {
	using namespace cs;

	std::string to_fixed_hex(const numeric &n)
	{
		numeric_integer val = n.as_integer();
		std::ostringstream oss;
		oss << std::hex << std::uppercase << std::setw(16) << std::setfill('0') << val;
		return oss.str();
	}

	numeric from_fixed_hex(const std::string &s)
	{
		if (s.size() != 16)
			throw cs::lang_error("Invalid byte string size, must be 16.");
		return std::stoull(s, nullptr, 16);
	}

	string host_name()
	{
		return asio::ip::host_name();
	}

	namespace tcp {
		static namespace_t tcp_ext = make_shared_namespace<name_space>();
		using socket_t = std::shared_ptr<cs_impl::network::tcp::socket>;
		using acceptor_t = std::shared_ptr<asio::ip::tcp::acceptor>;
		using endpoint_t = asio::ip::tcp::endpoint;

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
				return cs_impl::network::tcp::resolve(host, service);
			}
			catch (const std::exception &e) {
				throw lang_error(e.what());
			}
		}

		namespace socket {
			static namespace_t socket_ext = make_shared_namespace<name_space>();

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

			void set_opt_reuse_address(socket_t &sock, bool value)
			{
				sock->set_option(asio::ip::tcp::socket::reuse_address(value));
			}

			void set_opt_no_delay(socket_t &sock, bool value)
			{
				sock->set_option(asio::ip::tcp::no_delay(value));
			}

			void set_opt_keep_alive(socket_t &sock, bool value)
			{
				sock->set_option(asio::socket_base::keep_alive(value));
			}

			number available(socket_t &sock)
			{
				try {
					return sock->available();
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
				}
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

			string read(socket_t &sock, number size)
			{
				if (size <= 0)
					throw lang_error("Buffer size must above zero.");
				else {
					try {
						return sock->read(static_cast<std::size_t>(size));
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

			void write(socket_t &sock, const string &str)
			{
				try {
					sock->write(str);
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
				}
			}

			void shutdown(socket_t &sock)
			{
				try {
					sock->shutdown();
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
				}
			}

			bool safe_shutdown(socket_t &);

			endpoint_t local_endpoint(socket_t &sock)
			{
				try {
					return sock->local_endpoint();
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

		namespace ep {
			static namespace_t ep_ext = make_shared_namespace<name_space>();

			string address(const endpoint_t &ep)
			{
				return ep.address().to_string();
			}

			bool is_v4(const endpoint_t &ep)
			{
				return ep.address().is_v4();
			}

			bool is_v6(const endpoint_t &ep)
			{
				return ep.address().is_v6();
			}

			number port(const endpoint_t &ep)
			{
				return ep.port();
			}
		}
	}

	namespace udp {
		static namespace_t udp_ext = make_shared_namespace<name_space>();
		using socket_t = std::shared_ptr<cs_impl::network::udp::socket>;
		using endpoint_t = asio::ip::udp::endpoint;

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

		var endpoint_broadcast(number port)
		{
			if (port < 0)
				throw lang_error("Port number can not under zero.");
			else
				return var::make<endpoint_t>(asio::ip::address_v4::broadcast(), static_cast<unsigned short>(port));
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
				return cs_impl::network::udp::resolve(host, service);
			}
			catch (const std::exception &e) {
				throw lang_error(e.what());
			}
		}

		namespace socket {
			static namespace_t socket_ext = make_shared_namespace<name_space>();

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

			void connect(socket_t &sock, const endpoint_t &ep)
			{
				try {
					sock->connect(ep);
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

			bool safe_close(socket_t &);

			bool is_open(socket_t &sock)
			{
				return sock->is_open();
			}

			void set_opt_reuse_address(socket_t &sock, bool value)
			{
				sock->set_option(asio::ip::udp::socket::reuse_address(value));
			}

			void set_opt_broadcast(socket_t &sock, bool value)
			{
				sock->set_option(asio::socket_base::broadcast(value));
			}

			number available(socket_t &sock)
			{
				try {
					return sock->available();
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
				}
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

			endpoint_t local_endpoint(socket_t &sock)
			{
				try {
					return sock->local_endpoint();
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

		namespace ep {
			static namespace_t ep_ext = make_shared_namespace<name_space>();

			string address(const endpoint_t &ep)
			{
				return ep.address().to_string();
			}

			bool is_v4(const endpoint_t &ep)
			{
				return ep.address().is_v4();
			}

			bool is_v6(const endpoint_t &ep)
			{
				return ep.address().is_v6();
			}

			number port(const endpoint_t &ep)
			{
				return ep.port();
			}
		}
	}

	// Asynchronous

	namespace async {
		class global_settings_type {
			friend global_settings_type &get_global_settings();
			global_settings_type() = default;

		public:
			asio::io_context &io = cs_impl::network::get_io_context();
			std::atomic<std::size_t> thread_executors{0};

			inline std::size_t poll()
			{
				if (thread_executors.load(std::memory_order_acquire) == 0)
					return io.poll();
				else
					return 0;
			}

			inline std::size_t poll_one()
			{
				if (thread_executors.load(std::memory_order_acquire) == 0)
					return io.poll_one();
				else
					return 0;
			}
		};

		global_settings_type &get_global_settings()
		{
			static global_settings_type settings;
			return settings;
		}

		class thread_executor_type {
			std::thread worker;

		public:
			static void executor()
			{
				cs_impl::network::get_io_context().run();
			}
			thread_executor_type() : worker(thread_executor_type::executor)
			{
				get_global_settings().thread_executors.fetch_add(1, std::memory_order_relaxed);
			}
			~thread_executor_type()
			{
				worker.join();
				get_global_settings().thread_executors.fetch_sub(1, std::memory_order_relaxed);
			}
		};

		struct state_type {
			bool init = false;
			bool is_udp = false;
			bool is_read = false;
			bool is_reentrant = false;
			std::atomic<bool> has_done{false};
			std::size_t bytes_transferred = 0;
			udp::endpoint_t udp_endpoint;
			asio::streambuf buffer;
			asio::error_code ec;
		};

		using state_t = std::shared_ptr<state_type>;

		state_t create_async_state()
		{
			return std::make_shared<state_type>();
		}

		static namespace_t state_ext = make_shared_namespace<name_space>();

		bool has_done(const state_t &state)
		{
			return state->has_done.load(std::memory_order_acquire);
		}

		cs::var get_result(const state_t &state)
		{
			if (!state->is_read)
				throw cs::lang_error("Asynchronous operation not a read/receive session.");
			if (!state->has_done.load(std::memory_order_acquire))
				return cs::null_pointer;
			if (state->bytes_transferred == 0)
				return cs::var::make<cs::string>();
			std::string data(asio::buffers_begin(state->buffer.data()), asio::buffers_begin(state->buffer.data()) + state->bytes_transferred);
			state->buffer.consume(state->bytes_transferred);
			state->bytes_transferred = 0;
			return cs::var::make<cs::string>(std::move(data));
		}

		cs::var get_buffer(const state_t &state, std::size_t max_bytes)
		{
			if (!state->is_read)
				throw cs::lang_error("Asynchronous operation not a read/receive session.");
			if (!state->has_done.load(std::memory_order_acquire))
				return cs::null_pointer;
			if (state->buffer.size() == 0)
				return cs::var::make<cs::string>();
			std::size_t to_read = (std::min)(max_bytes, state->buffer.size());
			std::string data(asio::buffers_begin(state->buffer.data()), asio::buffers_begin(state->buffer.data()) + to_read);
			state->buffer.consume(to_read);
			state->bytes_transferred = state->bytes_transferred > to_read ? state->bytes_transferred - to_read : 0;
			return cs::var::make<cs::string>(std::move(data));
		}

		std::size_t available(const state_t &state)
		{
			if (state->is_read && state->has_done.load(std::memory_order_acquire))
				return state->buffer.size();
			else
				return 0;
		}

		bool eof(const state_t &state)
		{
			if (!state->has_done.load(std::memory_order_acquire))
				return false;
			return state->ec == asio::error::eof || state->ec == asio::error::connection_reset;
		}

		cs::var get_error(const state_t &state)
		{
			if (!state->has_done.load(std::memory_order_acquire))
				return cs::null_pointer;
			if (!state->ec)
				return cs::null_pointer;
			else
				return cs::var::make<cs::string>(state->ec.message());
		}

		udp::endpoint_t get_endpoint(const state_t &state)
		{
			if (!state->is_udp || !state->is_read)
				throw cs::lang_error("Asynchronous operation not a receive_from session.");
			if (!state->has_done.load(std::memory_order_acquire))
				throw cs::lang_error("Asynchronous operation not finished.");
			if (state->ec)
				throw cs::lang_error("Asynchronous operation has encountered an error: " + state->ec.message());
			return state->udp_endpoint;
		}

		bool wait(const state_t &state)
		{
			while (true) {
				get_global_settings().poll();
				if (state->has_done.load(std::memory_order_acquire))
					return !state->ec;
				cs_runtime_yield();
			}
		}

		bool wait_for(const state_t &state, std::size_t timeout_ms)
		{
			auto start = std::chrono::steady_clock::now();
			std::chrono::milliseconds timeout_duration(timeout_ms);
			while (true) {
				get_global_settings().poll();
				if (state->has_done.load(std::memory_order_acquire))
					return !state->ec;
				auto now = std::chrono::steady_clock::now();
				if (now - start >= timeout_duration)
					return state->has_done.load(std::memory_order_acquire) && !state->ec;
				cs_runtime_yield();
			}
		}

		static namespace_t async_ext = make_shared_namespace<name_space>();

		state_t accept(tcp::socket_t &sock, tcp::acceptor_t &acceptor)
		{
			state_t state = std::make_shared<state_type>();
			state->init = true;
			sock->async_jobs.fetch_add(1, std::memory_order_relaxed);
			acceptor->async_accept(sock->get_raw(), [sock, state](const asio::error_code &ec) {
				state->ec = ec;
				state->has_done.store(true, std::memory_order_release);
				sock->async_jobs.fetch_sub(1, std::memory_order_relaxed);
			});
			return state;
		}

		state_t connect(tcp::socket_t &sock, const tcp::endpoint_t &ep)
		{
			state_t state = std::make_shared<state_type>();
			state->init = true;
			sock->async_jobs.fetch_add(1, std::memory_order_relaxed);
			sock->get_raw().async_connect(ep, [sock, state](const asio::error_code &ec) {
				state->ec = ec;
				state->has_done.store(true, std::memory_order_release);
				sock->async_jobs.fetch_sub(1, std::memory_order_relaxed);
			});
			return state;
		}

		void read_until(tcp::socket_t &sock, state_t &state, const std::string &pattern)
		{
			if (!state->init) {
				state->init = true;
				state->is_read = true;
				state->is_reentrant = true;
			}
			else if (!state->has_done.load(std::memory_order_acquire))
				throw cs::lang_error("Last asynchronous operation have not done yet.");
			state->has_done = false;
			state->ec.clear();
			sock->async_jobs.fetch_add(1, std::memory_order_relaxed);
			asio::async_read_until(sock->get_raw(), state->buffer, pattern,
			[sock, state](const asio::error_code &ec, std::size_t bytes) {
				state->buffer.commit(bytes);
				state->bytes_transferred = bytes;
				state->ec = ec;
				state->has_done.store(true, std::memory_order_release);
				sock->async_jobs.fetch_sub(1, std::memory_order_relaxed);
			});
		}

		state_t read(tcp::socket_t &sock, std::size_t n)
		{
			state_t state = std::make_shared<state_type>();
			state->init = true;
			state->is_read = true;
			sock->async_jobs.fetch_add(1, std::memory_order_relaxed);
			asio::async_read(sock->get_raw(), state->buffer.prepare(n),
			[sock, state](const asio::error_code &ec, std::size_t bytes) {
				state->buffer.commit(bytes);
				state->bytes_transferred = bytes;
				state->ec = ec;
				state->has_done.store(true, std::memory_order_release);
				sock->async_jobs.fetch_sub(1, std::memory_order_relaxed);
			});
			return state;
		}

		state_t write(tcp::socket_t &sock, const std::string &data)
		{
			state_t state = std::make_shared<state_type>();
			state->init = true;
			std::ostream os(&state->buffer);
			os.write(data.data(), data.size());
			sock->async_jobs.fetch_add(1, std::memory_order_relaxed);
			asio::async_write(sock->get_raw(), state->buffer,
			[sock, state](const asio::error_code &ec, std::size_t bytes) {
				state->buffer.consume(bytes);
				state->bytes_transferred = bytes;
				state->ec = ec;
				state->has_done.store(true, std::memory_order_release);
				sock->async_jobs.fetch_sub(1, std::memory_order_relaxed);
			});
			return state;
		}

		state_t receive_from(udp::socket_t &sock, std::size_t n)
		{
			state_t state = std::make_shared<state_type>();
			state->init = true;
			state->is_udp = true;
			state->is_read = true;
			sock->async_jobs.fetch_add(1, std::memory_order_relaxed);
			sock->get_raw().async_receive_from(state->buffer.prepare(n), state->udp_endpoint,
			[sock, state](const asio::error_code &ec, std::size_t bytes) {
				state->buffer.commit(bytes);
				state->bytes_transferred = bytes;
				state->ec = ec;
				state->has_done.store(true, std::memory_order_release);
				sock->async_jobs.fetch_sub(1, std::memory_order_relaxed);
			});
			return state;
		}

		state_t send_to(udp::socket_t &sock, const std::string &data, const udp::endpoint_t &ep)
		{
			state_t state = std::make_shared<state_type>();
			state->init = true;
			state->is_udp = true;
			state->udp_endpoint = ep;
			std::ostream os(&state->buffer);
			os.write(data.data(), data.size());
			sock->async_jobs.fetch_add(1, std::memory_order_relaxed);
			sock->get_raw().async_send_to(asio::buffer(state->buffer.data(), state->buffer.size()), state->udp_endpoint,
			[sock, state](const asio::error_code &ec, std::size_t bytes) {
				state->buffer.consume(bytes);
				state->bytes_transferred = bytes;
				state->ec = ec;
				state->has_done.store(true, std::memory_order_release);
				sock->async_jobs.fetch_sub(1, std::memory_order_relaxed);
			});
			return state;
		}

		bool poll()
		{
			return get_global_settings().poll() > 0;
		}

		bool poll_once()
		{
			return get_global_settings().poll_one() > 0;
		}

		bool stopped()
		{
			return cs_impl::network::get_io_context().stopped();
		}

		void restart()
		{
			cs_impl::network::get_io_context().restart();
		}

		using work_guard_t = asio::executor_work_guard<asio::io_context::executor_type>;

		var work_guard()
		{
			if (stopped())
				restart();
			return var::make<work_guard_t>(cs_impl::network::get_io_context().get_executor());
		}

		using thread_executor_t = std::shared_ptr<thread_executor_type>;

		thread_executor_t thread_worker()
		{
			return std::make_shared<thread_executor_type>();
		}
	}

	void init(name_space *network_ext)
	{
		(*network_ext)
		.add_var("tcp", make_namespace(tcp::tcp_ext))
		.add_var("udp", make_namespace(udp::udp_ext))
		.add_var("host_name", make_cni(host_name))
		.add_var("to_fixed_hex", make_cni(to_fixed_hex))
		.add_var("from_fixed_hex", make_cni(from_fixed_hex))
		.add_var("async", make_namespace(async::async_ext));
		(*async::state_ext)
		.add_var("has_done", make_cni(async::has_done))
		.add_var("get_result", make_cni(async::get_result))
		.add_var("get_buffer", make_cni(async::get_buffer))
		.add_var("eof", make_cni(async::eof))
		.add_var("available", make_cni(async::available))
		.add_var("get_error", make_cni(async::get_error))
		.add_var("get_endpoint", make_cni(async::get_endpoint))
		.add_var("wait", make_cni(async::wait))
		.add_var("wait_for", make_cni(async::wait_for));
		(*async::async_ext)
		.add_var("state", var::make_constant<type_t>(async::create_async_state, type_id(typeid(async::state_t)), async::state_ext))
		.add_var("accept", make_cni(async::accept))
		.add_var("connect", make_cni(async::connect))
		.add_var("read_until", make_cni(async::read_until))
		.add_var("read", make_cni(async::read))
		.add_var("write", make_cni(async::write))
		.add_var("receive_from", make_cni(async::receive_from))
		.add_var("send_to", make_cni(async::send_to))
		.add_var("poll", make_cni(async::poll))
		.add_var("poll_once", make_cni(async::poll_once))
		.add_var("stopped", make_cni(async::stopped))
		.add_var("restart", make_cni(async::restart))
		.add_var("work_guard", var::make_constant<type_t>(async::work_guard, type_id(typeid(async::work_guard_t))))
		.add_var("thread_worker", var::make_constant<type_t>(async::thread_worker, type_id(typeid(async::thread_executor_t))));
		(*tcp::tcp_ext)
		.add_var("socket", var::make_constant<type_t>(tcp::socket::socket, type_id(typeid(tcp::socket_t)), tcp::socket::socket_ext))
		.add_var("acceptor", make_cni(tcp::acceptor, true))
		.add_var("endpoint", make_cni(tcp::endpoint, true))
		.add_var("endpoint_v4", make_cni(tcp::endpoint_v4, true))
		.add_var("endpoint_v6", make_cni(tcp::endpoint_v6, true))
		.add_var("resolve", make_cni(tcp::resolve, true));
		(*tcp::socket::socket_ext)
		.add_var("connect", make_cni(tcp::socket::connect))
		.add_var("accept", make_cni(tcp::socket::accept))
		.add_var("close", make_cni(tcp::socket::close))
		.add_var("is_open", make_cni(tcp::socket::is_open))
		.add_var("set_opt_reuse_address", make_cni(tcp::socket::set_opt_reuse_address))
		.add_var("set_opt_no_delay", make_cni(tcp::socket::set_opt_no_delay))
		.add_var("set_opt_keep_alive", make_cni(tcp::socket::set_opt_keep_alive))
		.add_var("available", make_cni(tcp::socket::available))
		.add_var("receive", make_cni(tcp::socket::receive))
		.add_var("read", make_cni(tcp::socket::read))
		.add_var("send", make_cni(tcp::socket::send))
		.add_var("write", make_cni(tcp::socket::write))
		.add_var("shutdown", make_cni(tcp::socket::shutdown))
		.add_var("safe_shutdown", make_cni(tcp::socket::safe_shutdown))
		.add_var("local_endpoint", make_cni(tcp::socket::local_endpoint))
		.add_var("remote_endpoint", make_cni(tcp::socket::remote_endpoint));
		(*tcp::ep::ep_ext)
		.add_var("address", make_cni(tcp::ep::address, true))
		.add_var("is_v4", make_cni(tcp::ep::is_v4, true))
		.add_var("is_v6", make_cni(tcp::ep::is_v6, true))
		.add_var("port", make_cni(tcp::ep::port, true));
		(*udp::udp_ext)
		.add_var("socket", var::make_constant<type_t>(udp::socket::socket, type_id(typeid(udp::socket_t)), udp::socket::socket_ext))
		.add_var("endpoint", make_cni(udp::endpoint, true))
		.add_var("endpoint_v4", make_cni(udp::endpoint_v4, true))
		.add_var("endpoint_broadcast", make_cni(udp::endpoint_broadcast, true))
		.add_var("endpoint_v6", make_cni(udp::endpoint_v6, true))
		.add_var("resolve", make_cni(udp::resolve, true));
		(*udp::socket::socket_ext)
		.add_var("open_v4", make_cni(udp::socket::open_v4))
		.add_var("open_v6", make_cni(udp::socket::open_v6))
		.add_var("bind", make_cni(udp::socket::bind))
		.add_var("connect", make_cni(udp::socket::connect))
		.add_var("close", make_cni(udp::socket::close))
		.add_var("safe_close", make_cni(udp::socket::safe_close))
		.add_var("is_open", make_cni(udp::socket::is_open))
		.add_var("set_opt_reuse_address", make_cni(udp::socket::set_opt_reuse_address))
		.add_var("set_opt_broadcast", make_cni(udp::socket::set_opt_broadcast))
		.add_var("available", make_cni(udp::socket::available))
		.add_var("receive_from", make_cni(udp::socket::receive_from))
		.add_var("send_to", make_cni(udp::socket::send_to))
		.add_var("local_endpoint", make_cni(udp::socket::local_endpoint))
		.add_var("remote_endpoint", make_cni(udp::socket::remote_endpoint));
		(*udp::ep::ep_ext)
		.add_var("address", make_cni(udp::ep::address, true))
		.add_var("is_v4", make_cni(udp::ep::is_v4, true))
		.add_var("is_v6", make_cni(udp::ep::is_v6, true))
		.add_var("port", make_cni(udp::ep::port, true));
	}
}

bool network_cs_ext::tcp::socket::safe_shutdown(socket_t &sock)
{
	if (!sock->get_raw().is_open())
		return true;
	while (sock->async_jobs.load(std::memory_order_acquire) > 0) {
		network_cs_ext::async::get_global_settings().poll();
		cs_runtime_yield();
	}
	asio::error_code shutdown_ec, close_ec;
	sock->get_raw().shutdown(asio::ip::tcp::socket::shutdown_both, shutdown_ec);
	sock->get_raw().close(close_ec);
	return !static_cast<bool>(shutdown_ec) && !static_cast<bool>(close_ec);
}

bool network_cs_ext::udp::socket::safe_close(socket_t &sock)
{
	if (!sock->get_raw().is_open())
		return true;
	while (sock->async_jobs.load(std::memory_order_acquire) > 0) {
		network_cs_ext::async::get_global_settings().poll();
		cs_runtime_yield();
	}
	asio::error_code ec;
	sock->get_raw().close(ec);
	return !static_cast<bool>(ec);
}

namespace cs_impl {
	template <>
	cs::namespace_t &get_ext<network_cs_ext::tcp::socket_t>()
	{
		return network_cs_ext::tcp::socket::socket_ext;
	}

	template <>
	cs::namespace_t &get_ext<network_cs_ext::tcp::endpoint_t>()
	{
		return network_cs_ext::tcp::ep::ep_ext;
	}

	template <>
	cs::namespace_t &get_ext<network_cs_ext::udp::socket_t>()
	{
		return network_cs_ext::udp::socket::socket_ext;
	}

	template <>
	cs::namespace_t &get_ext<network_cs_ext::udp::endpoint_t>()
	{
		return network_cs_ext::udp::ep::ep_ext;
	}

	template <>
	cs::namespace_t &get_ext<network_cs_ext::async::state_t>()
	{
		return network_cs_ext::async::state_ext;
	}

	template <>
	constexpr const char *get_name_of_type<network_cs_ext::tcp::socket_t>()
	{
		return "cs::network::tcp::socket";
	}

	template <>
	constexpr const char *get_name_of_type<network_cs_ext::tcp::acceptor_t>()
	{
		return "cs::network::tcp::acceptor";
	}

	template <>
	constexpr const char *get_name_of_type<network_cs_ext::tcp::endpoint_t>()
	{
		return "cs::network::tcp::endpoint";
	}

	template <>
	constexpr const char *get_name_of_type<network_cs_ext::udp::socket_t>()
	{
		return "cs::network::udp::socket";
	}

	template <>
	constexpr const char *get_name_of_type<network_cs_ext::udp::endpoint_t>()
	{
		return "cs::network::udp::endpoint";
	}

	template <>
	constexpr const char *get_name_of_type<network_cs_ext::async::state_t>()
	{
		return "cs::network::async::state";
	}

	template <>
	constexpr const char *get_name_of_type<network_cs_ext::async::work_guard_t>()
	{
		return "cs::network::async::work_guard";
	}

	template <>
	constexpr const char *get_name_of_type<network_cs_ext::async::thread_executor_t>()
	{
		return "cs::network::async::thread_executor";
	}
}

void cs_extension_main(cs::name_space *ns)
{
	network_cs_ext::init(ns);
}