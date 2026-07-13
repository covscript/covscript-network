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
 * Copyright (C) 2017-2026 Michael Lee(李登淳)
 *
 * Email:   mikecovlee@163.com
 * Github:  https://github.com/mikecovlee
 * Website: http://covscript.org.cn
 */

#include <covscript/dll.hpp>
#include <covscript/cni.hpp>
#include <network.hpp>
#include <chrono>
#include <optional>
#include <cstdio>
#include <thread>
#include <memory>
#include <mutex>
#include <regex>
#include <array>

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

	std::size_t checked_io_buffer_size(number size)
	{
		static_assert(NETWORK_MAX_IO_BUFFER_SIZE > 0,
		              "NETWORK_MAX_IO_BUFFER_SIZE must be greater than zero");
		if (size <= 0)
			throw lang_error("Buffer size must be greater than zero.");
		if (size > NETWORK_MAX_IO_BUFFER_SIZE)
			throw lang_error("Buffer size exceeds the configured limit of "
			                 + std::to_string(NETWORK_MAX_IO_BUFFER_SIZE) + " bytes.");
		return static_cast<std::size_t>(size);
	}

	bool is_null_var(const var &v)
	{
		if (v.type() == typeid(void))
			return true;
		if (v.is_type_of<pointer>()) {
			const auto &ptr = v.const_val<pointer>();
			return !ptr.data.usable();
		}
		return false;
	}

	cs_impl::network::ssl_options parse_ssl_options(const var &options_var)
	{
		cs_impl::network::ssl_options options;
		if (is_null_var(options_var))
			return options;
		if (!options_var.is_type_of<hash_map>())
			throw lang_error("TLS options must be null or hash_map.");
		const auto &options_map = options_var.const_val<hash_map>();
		bool has_trust_mode = false;
		for (const auto &entry : options_map) {
			if (!entry.first.is_type_of<string>())
				throw lang_error("TLS option keys must be strings.");
			const auto &key = entry.first.const_val<string>();
			const auto &value = entry.second;
			if (key == "trust_mode") {
				if (!value.is_type_of<string>())
					throw lang_error("TLS option \"trust_mode\" must be string.");
				const auto &mode = value.const_val<string>();
				has_trust_mode = true;
				if (mode == "auto")
					options.trust_mode = cs_impl::network::ssl_trust_mode::auto_mode;
				else if (mode == "openssl")
					options.trust_mode = cs_impl::network::ssl_trust_mode::openssl;
				else if (mode == "custom")
					options.trust_mode = cs_impl::network::ssl_trust_mode::custom;
				else if (mode == "insecure") {
					options.trust_mode = cs_impl::network::ssl_trust_mode::insecure;
					options.verify_peer = false;
					options.verify_host = false;
				}
				else
					throw lang_error("Unsupported TLS trust_mode: " + mode);
			}
			else if (key == "ca_file") {
				if (is_null_var(value))
					options.ca_file.clear();
				else if (value.is_type_of<string>())
					options.ca_file = value.const_val<string>();
				else
					throw lang_error("TLS option \"ca_file\" must be string or null.");
			}
			else if (key == "ca_path") {
				if (is_null_var(value))
					options.ca_path.clear();
				else if (value.is_type_of<string>())
					options.ca_path = value.const_val<string>();
				else
					throw lang_error("TLS option \"ca_path\" must be string or null.");
			}
			else if (key == "verify_peer" || key == "verify_host")
				throw lang_error("TLS option \"" + key + "\" is not exposed through CNI.");
			else
				throw lang_error("Unknown TLS option: " + key);
		}
		if (!options.ca_file.empty() || !options.ca_path.empty()) {
			if (!has_trust_mode)
				throw lang_error("TLS options \"ca_file\" and \"ca_path\" require trust_mode=\"custom\".");
			if (options.trust_mode != cs_impl::network::ssl_trust_mode::custom)
				throw lang_error("TLS options \"ca_file\" and \"ca_path\" can only be used with trust_mode=\"custom\".");
		}
		if (options.trust_mode == cs_impl::network::ssl_trust_mode::custom && options.ca_file.empty() && options.ca_path.empty())
			throw lang_error("TLS trust_mode \"custom\" requires ca_file or ca_path.");
		if (options.trust_mode == cs_impl::network::ssl_trust_mode::insecure && (!options.ca_file.empty() || !options.ca_path.empty()))
			throw lang_error("TLS trust_mode \"insecure\" cannot be combined with ca_file or ca_path.");
		return options;
	}

	std::string to_fixed_hex(const numeric &n)
	{
		static_assert(NETWORK_FIXED_HEX_SIZE >= 1 && NETWORK_FIXED_HEX_SIZE <= 256,
		              "NETWORK_FIXED_HEX_SIZE must be between 1 and 256");
		if (n.as_integer() < 0)
			throw cs::lang_error("Cannot convert negative number to fixed hex string.");
		std::array<char, NETWORK_FIXED_HEX_SIZE + 1> buf{};
		int written = snprintf(buf.data(), buf.size(), "%0*llX", static_cast<int>(NETWORK_FIXED_HEX_SIZE), static_cast<unsigned long long>(n.as_integer()));
		if (written != static_cast<int>(NETWORK_FIXED_HEX_SIZE))
			throw cs::lang_error("Failed to convert number to fixed hex string.");
		return std::string(buf.data(), NETWORK_FIXED_HEX_SIZE);
	}

	numeric from_fixed_hex(const std::string &s)
	{
		if (s.size() != NETWORK_FIXED_HEX_SIZE)
			throw cs::lang_error("Invalid byte string size, must be " + std::to_string(NETWORK_FIXED_HEX_SIZE) + ".");
		std::size_t idx = 0;
		unsigned long long val = 0;
		try {
			val = std::stoull(s, &idx, 16);
		}
		catch (const std::exception &e) {
			throw cs::lang_error(std::string("Invalid hex string: ") + e.what());
		}
		if (idx != s.size())
			throw cs::lang_error("Invalid hex string: unexpected trailing characters after " + std::to_string(NETWORK_FIXED_HEX_SIZE) + " hex digits.");
		return val;
	}

	string host_name()
	{
		return asio::ip::host_name();
	}

	string get_last_global_ssl_trust_report()
	{
		return cs_impl::network::detail::get_last_tls_trust_report();
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
			if (port < 0 || port > NETWORK_MAX_PORT)
				throw lang_error("Port number must be in range [0, " + std::to_string(NETWORK_MAX_PORT) + "].");
			else
				return var::make<endpoint_t>(cs_impl::network::tcp::endpoint(host, static_cast<unsigned short>(port)));
		}

		var endpoint_v4(number port)
		{
			if (port < 0 || port > NETWORK_MAX_PORT)
				throw lang_error("Port number must be in range [0, " + std::to_string(NETWORK_MAX_PORT) + "].");
			else
				return var::make<endpoint_t>(asio::ip::tcp::v4(), static_cast<unsigned short>(port));
		}

		var endpoint_v6(number port)
		{
			if (port < 0 || port > NETWORK_MAX_PORT)
				throw lang_error("Port number must be in range [0, " + std::to_string(NETWORK_MAX_PORT) + "].");
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

		string get_ssl_trust_report(socket_t &sock)
		{
			return sock->get_ssl_trust_report();
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

			void connect_ssl(socket_t &sock, const string &host, const var &options)
			{
				try {
					sock->connect_ssl(host, parse_ssl_options(options));
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

			bool is_ssl(socket_t &sock)
			{
				return sock->is_ssl();
			}

			string get_ssl_trust_report(socket_t &sock)
			{
				return sock->get_ssl_trust_report();
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
				auto size = checked_io_buffer_size(max);
				try {
					return sock->receive(size);
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
				}
			}

			string read(socket_t &sock, number size)
			{
				auto checked_size = checked_io_buffer_size(size);
				try {
					return sock->read(checked_size);
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
				}
			}

			std::size_t send(socket_t &sock, const string &str)
			{
				try {
					return sock->send(str);
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
			if (port < 0 || port > NETWORK_MAX_PORT)
				throw lang_error("Port number must be in range [0, " + std::to_string(NETWORK_MAX_PORT) + "].");
			else
				return var::make<endpoint_t>(cs_impl::network::udp::endpoint(host, static_cast<unsigned short>(port)));
		}

		var endpoint_v4(number port)
		{
			if (port < 0 || port > NETWORK_MAX_PORT)
				throw lang_error("Port number must be in range [0, " + std::to_string(NETWORK_MAX_PORT) + "].");
			else
				return var::make<endpoint_t>(asio::ip::udp::v4(), static_cast<unsigned short>(port));
		}

		var endpoint_broadcast(number port)
		{
			if (port < 0 || port > NETWORK_MAX_PORT)
				throw lang_error("Port number must be in range [0, " + std::to_string(NETWORK_MAX_PORT) + "].");
			else
				return var::make<endpoint_t>(asio::ip::address_v4::broadcast(), static_cast<unsigned short>(port));
		}

		var endpoint_v6(number port)
		{
			if (port < 0 || port > NETWORK_MAX_PORT)
				throw lang_error("Port number must be in range [0, " + std::to_string(NETWORK_MAX_PORT) + "].");
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
				auto size = checked_io_buffer_size(max);
				try {
					return sock->receive_from(size, ep);
				}
				catch (const std::exception &e) {
					throw lang_error(e.what());
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
			std::mutex lifecycle_mutex;

			inline std::size_t poll()
			{
				if (thread_executors.load(std::memory_order_acquire) != 0)
					return 0;
				std::lock_guard<std::mutex> lock(lifecycle_mutex);
				if (thread_executors.load(std::memory_order_acquire) == 0)
					return io.poll();
				else
					return 0;
			}

			inline std::size_t poll_one()
			{
				if (thread_executors.load(std::memory_order_acquire) != 0)
					return 0;
				std::lock_guard<std::mutex> lock(lifecycle_mutex);
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
			std::atomic<bool> running{true};
			std::shared_ptr<asio::executor_work_guard<asio::io_context::executor_type>> work_guard;

		public:
			void executor()
			{
				auto &io = cs_impl::network::get_io_context();
				while (true) {
					// Drain all ready handlers without blocking
					while (io.poll_one() > 0);
					if (!running.load(std::memory_order_acquire))
						break;
					// Block until a handler is ready or the timeout expires.
					// run_one_for uses the OS-native I/O demux timeout (IOCP /
					// epoll / kqueue), so it is NOT affected by the Windows
					// default timer resolution (~15.6 ms) the way sleep_for is.
					io.run_one_for(std::chrono::milliseconds(NETWORK_THREAD_WORKER_POLL_MS));
				}
			}
			thread_executor_type()
			{
				auto &settings = get_global_settings();
				{
					std::lock_guard<std::mutex> lock(settings.lifecycle_mutex);
					if (settings.thread_executors.load(std::memory_order_acquire) == 0 && settings.io.stopped())
						settings.io.restart();
					work_guard = std::make_shared<asio::executor_work_guard<asio::io_context::executor_type>>(settings.io.get_executor());
					settings.thread_executors.fetch_add(1, std::memory_order_release);
				}
				try {
					worker = std::thread([this]() {
						try {
							executor();
						}
						catch (const std::exception &e) {
							// Log or report the error instead of calling
							// std::terminate via the uncaught-exception path.
							fprintf(stderr, "[network] executor thread"
							                " terminated by exception: %s\n",
							        e.what());
						}
						catch (...) {
							fprintf(stderr, "[network] executor thread"
							                " terminated by unknown exception\n");
						}
						get_global_settings().thread_executors.fetch_sub(1, std::memory_order_release);
					});
				}
				catch (...) {
					get_global_settings().thread_executors.fetch_sub(1, std::memory_order_release);
					throw;
				}
			}
			~thread_executor_type()
			{
				running.store(false, std::memory_order_release);
				// Post an empty handler to wake up run_one_for immediately
				// so the worker thread can see running == false and exit
				// without waiting for the full timeout.
				try {
					asio::post(cs_impl::network::get_io_context(), [] {});
				}
				catch (...) {
					// Worker will wake on next run_one_for timeout and exit.
				}
				if (worker.joinable())
					worker.join();
			}
		};

		struct state_type {
			bool init = false;
			bool is_udp = false;
			bool is_read = false;
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

		cs::var get_buffer(const state_t &state, number max_bytes)
		{
			auto checked_max_bytes = checked_io_buffer_size(max_bytes);
			if (!state->is_read)
				throw cs::lang_error("Asynchronous operation not a read/receive session.");
			if (!state->has_done.load(std::memory_order_acquire))
				return cs::null_pointer;
			if (state->buffer.size() == 0)
				return cs::var::make<cs::string>();
			std::size_t to_read = (std::min)(checked_max_bytes, state->buffer.size());
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

		bool wait_impl(const state_t &state, std::optional<std::chrono::milliseconds> timeout)
		{
			auto start = std::chrono::steady_clock::now();
			while (true) {
				get_global_settings().poll();
				if (state->has_done.load(std::memory_order_acquire))
					return !state->ec;
				if (timeout.has_value()) {
					if (std::chrono::steady_clock::now() - start >= *timeout)
						return state->has_done.load(std::memory_order_acquire) && !state->ec;
				}
				cs_runtime_yield();
			}
		}

		bool wait(const state_t &state)
		{
			return wait_impl(state, std::nullopt);
		}

		bool wait_for(const state_t &state, std::size_t timeout_ms)
		{
			return wait_impl(state, std::chrono::milliseconds(timeout_ms));
		}

		static namespace_t async_ext = make_shared_namespace<name_space>();

		template <typename BeginOperation>
		void begin_tcp_async_io(BeginOperation &&begin_operation)
		{
			try {
				begin_operation();
			}
			catch (const std::exception &e) {
				throw cs::lang_error(e.what());
			}
		}

		template <typename BeginOperation>
		void begin_udp_async_io(BeginOperation &&begin_operation)
		{
			try {
				begin_operation();
			}
			catch (const std::exception &e) {
				throw cs::lang_error(e.what());
			}
		}

		void begin_tcp_tls_handshake(const tcp::socket_t &sock)
		{
			try {
				sock->begin_tls_handshake();
			}
			catch (const std::exception &e) {
				throw cs::lang_error(e.what());
			}
		}

		state_t accept(tcp::socket_t &sock, tcp::acceptor_t &acceptor)
		{
			state_t state = std::make_shared<state_type>();
			state->init = true;
			begin_tcp_async_io([&sock] { sock->begin_async_connect(); });
			try {
				acceptor->async_accept(sock->get_raw(), [sock, state](const asio::error_code &ec) {
					state->ec = ec;
					sock->end_async_connect();
					state->has_done.store(true, std::memory_order_release);
				});
			}
			catch (...) {
				sock->end_async_connect();
				throw;
			}
			return state;
		}

		state_t connect(tcp::socket_t &sock, const tcp::endpoint_t &ep)
		{
			state_t state = std::make_shared<state_type>();
			state->init = true;
			begin_tcp_async_io([&sock] { sock->begin_async_connect(); });
			try {
				sock->get_raw().async_connect(ep, [sock, state](const asio::error_code &ec) {
					state->ec = ec;
					sock->end_async_connect();
					state->has_done.store(true, std::memory_order_release);
				});
			}
			catch (...) {
				sock->end_async_connect();
				throw;
			}
			return state;
		}

		state_t connect_ssl(tcp::socket_t &sock, const std::string &host, const cs::var &options)
		{
			state_t state = std::make_shared<state_type>();
			state->init = true;
			auto ssl_options = parse_ssl_options(options);
			begin_tcp_tls_handshake(sock);
			try {
				sock->prepare_ssl(host, ssl_options);
			}
			catch (const std::exception &e) {
				sock->end_tls_handshake();
				throw cs::lang_error(e.what());
			}
			try {
				sock->get_tls_raw().async_handshake(asio::ssl::stream_base::client,
				asio::bind_executor(sock->get_tls_strand(), [sock, state](const asio::error_code &ec) {
					if (ec)
						sock->reset_ssl();
					state->ec = ec;
					sock->end_tls_handshake();
					state->has_done.store(true, std::memory_order_release);
				}));
			}
			catch (const std::exception &e) {
				sock->reset_ssl();
				sock->end_tls_handshake();
				throw cs::lang_error(e.what());
			}
			return state;
		}

		void read_until(tcp::socket_t &sock, state_t &state, const std::string &pattern)
		{
			if (state->init && !state->has_done.load(std::memory_order_acquire))
				throw cs::lang_error("Last asynchronous operation have not done yet.");
			begin_tcp_async_io([&sock] { sock->begin_async_read(); });
			const bool previous_init = state->init;
			const bool previous_is_read = state->is_read;
			const bool previous_has_done = state->has_done.load(std::memory_order_relaxed);
			const asio::error_code previous_ec = state->ec;
			state->init = true;
			state->is_read = true;
			state->has_done = false;
			state->ec.clear();
			try {
				auto on_done = [sock, state](const asio::error_code &ec, std::size_t bytes) {
					// async_read_until already committed data to the streambuf
					// internally; we must NOT call commit() again here.
					state->bytes_transferred = bytes;
					state->ec = ec;
					sock->end_async_read();
					state->has_done.store(true, std::memory_order_release);
				};
				if (sock->is_ssl())
					asio::async_read_until(sock->get_tls_raw(), state->buffer, pattern,
					                       asio::bind_executor(sock->get_tls_strand(), on_done));
				else
					asio::async_read_until(sock->get_raw(), state->buffer, pattern, on_done);
			}
			catch (...) {
				sock->end_async_read();
				state->init = previous_init;
				state->is_read = previous_is_read;
				state->ec = previous_ec;
				state->has_done.store(previous_has_done, std::memory_order_release);
				throw;
			}
		}

		state_t read(tcp::socket_t &sock, number requested_size)
		{
			auto n = checked_io_buffer_size(requested_size);
			state_t state = std::make_shared<state_type>();
			state->init = true;
			state->is_read = true;
			begin_tcp_async_io([&sock] { sock->begin_async_read(); });
			try {
				auto on_done = [sock, state](const asio::error_code &ec, std::size_t bytes) {
					state->buffer.commit(bytes);
					state->bytes_transferred = bytes;
					state->ec = ec;
					sock->end_async_read();
					state->has_done.store(true, std::memory_order_release);
				};
				if (sock->is_ssl())
					asio::async_read(sock->get_tls_raw(), state->buffer.prepare(n),
					                 asio::bind_executor(sock->get_tls_strand(), on_done));
				else
					asio::async_read(sock->get_raw(), state->buffer.prepare(n), on_done);
			}
			catch (...) {
				sock->end_async_read();
				throw;
			}
			return state;
		}

		state_t write(tcp::socket_t &sock, const std::string &data)
		{
			state_t state = std::make_shared<state_type>();
			state->init = true;
			begin_tcp_async_io([&sock] { sock->begin_async_write(); });
			try {
				std::ostream os(&state->buffer);
				os.exceptions(std::ostream::badbit | std::ostream::failbit);
				os.write(data.data(), data.size());
				auto on_done = [sock, state](const asio::error_code &ec, std::size_t bytes) {
					state->bytes_transferred = bytes;
					state->ec = ec;
					sock->end_async_write();
					state->has_done.store(true, std::memory_order_release);
				};
				if (sock->is_ssl())
					asio::async_write(sock->get_tls_raw(), state->buffer,
					                  asio::bind_executor(sock->get_tls_strand(), on_done));
				else
					asio::async_write(sock->get_raw(), state->buffer, on_done);
			}
			catch (...) {
				sock->end_async_write();
				throw;
			}
			return state;
		}

		state_t receive_from(udp::socket_t &sock, number requested_size)
		{
			auto n = checked_io_buffer_size(requested_size);
			state_t state = std::make_shared<state_type>();
			state->init = true;
			state->is_udp = true;
			state->is_read = true;
			begin_udp_async_io([&sock] { sock->begin_async_receive(); });
			try {
				sock->get_raw().async_receive_from(state->buffer.prepare(n), state->udp_endpoint,
				[sock, state](const asio::error_code &ec, std::size_t bytes) {
					state->buffer.commit(bytes);
					state->bytes_transferred = bytes;
					state->ec = ec;
					sock->end_async_receive();
					state->has_done.store(true, std::memory_order_release);
				});
			}
			catch (...) {
				sock->end_async_receive();
				throw;
			}
			return state;
		}

		state_t send_to(udp::socket_t &sock, const std::string &data, const udp::endpoint_t &ep)
		{
			state_t state = std::make_shared<state_type>();
			state->init = true;
			state->is_udp = true;
			state->udp_endpoint = ep;
			begin_udp_async_io([&sock] { sock->begin_async_send(); });
			// Pass streambuf data() directly as ConstBufferSequence to avoid
			// truncation when the streambuf spans multiple internal blocks.
			try {
				std::ostream os(&state->buffer);
				os.exceptions(std::ostream::badbit | std::ostream::failbit);
				os.write(data.data(), data.size());
				sock->get_raw().async_send_to(state->buffer.data(), state->udp_endpoint,
				[sock, state](const asio::error_code &ec, std::size_t bytes) {
					state->buffer.consume(bytes);
					state->bytes_transferred = bytes;
					state->ec = ec;
					sock->end_async_send();
					state->has_done.store(true, std::memory_order_release);
				});
			}
			catch (...) {
				sock->end_async_send();
				throw;
			}
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
			auto &settings = get_global_settings();
			std::lock_guard<std::mutex> lock(settings.lifecycle_mutex);
			if (settings.thread_executors.load(std::memory_order_acquire) == 0 && settings.io.stopped())
				settings.io.restart();
		}

		using work_guard_t = std::shared_ptr<asio::executor_work_guard<asio::io_context::executor_type>>;

		var work_guard()
		{
			auto &settings = get_global_settings();
			std::lock_guard<std::mutex> lock(settings.lifecycle_mutex);
			if (settings.thread_executors.load(std::memory_order_acquire) == 0 && settings.io.stopped())
				settings.io.restart();
			return std::make_shared<asio::executor_work_guard<asio::io_context::executor_type>>(settings.io.get_executor());
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
		.add_var("get_last_global_ssl_trust_report", make_cni(get_last_global_ssl_trust_report))
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
		.add_var("connect_ssl", make_cni(async::connect_ssl))
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
		.add_var("resolve", make_cni(tcp::resolve, true))
		.add_var("get_ssl_trust_report", make_cni(tcp::get_ssl_trust_report));
		(*tcp::socket::socket_ext)
		.add_var("connect", make_cni(tcp::socket::connect))
		.add_var("connect_ssl", make_cni(tcp::socket::connect_ssl))
		.add_var("accept", make_cni(tcp::socket::accept))
		.add_var("close", make_cni(tcp::socket::close))
		.add_var("is_open", make_cni(tcp::socket::is_open))
		.add_var("is_ssl", make_cni(tcp::socket::is_ssl))
		.add_var("get_ssl_trust_report", make_cni(tcp::socket::get_ssl_trust_report))
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
	// Block new I/O atomically, then wait for existing jobs to drain.
	// No timeout — safe_shutdown blocks until all pending I/O completes
	// or the peer closes the connection.
	try {
		sock->begin_draining_exclusive();
	}
	catch (const std::exception &) {
		return false;
	}
	// RAII: release exclusive reservation on any exit path.
	struct exclusive_guard {
		socket_t &s;
		explicit exclusive_guard(socket_t &sock_ref) : s(sock_ref) {}
		~exclusive_guard()
		{
			s->end_draining_exclusive();
		}
	} guard(sock);
	network_cs_ext::async::restart();
	while (sock->async_jobs.load(std::memory_order_acquire) > 0) {
		network_cs_ext::async::get_global_settings().poll();
		cs_runtime_yield();
	}
	bool success = true;
	// TLS: async_shutdown avoids blocking the OS thread.
	// A strand-bound timer closes the raw socket on timeout so the
	// shutdown operation completes before TLS state is destroyed.
	if (sock->is_ssl()) {
		struct tls_shutdown_state {
			asio::error_code ec;
			std::atomic<bool> done{false};
			bool timed_out = false;
		};
		auto state = std::make_shared<tls_shutdown_state>();
		auto timer = std::make_shared<asio::steady_timer>(
		                 cs_impl::network::get_io_context(),
		                 std::chrono::milliseconds(NETWORK_TLS_SHUTDOWN_TIMEOUT_MS));
		auto cancellation = std::make_shared<asio::cancellation_signal>();
		bool shutdown_started = false;
		try {
			sock->get_tls_raw().async_shutdown(
			    asio::bind_cancellation_slot(cancellation->slot(),
			                                 asio::bind_executor(sock->get_tls_strand(),
			[state, timer, cancellation](const asio::error_code &ec) {
				state->ec = ec;
				timer->cancel();
				state->done.store(true, std::memory_order_release);
			})));
			shutdown_started = true;
			timer->async_wait(asio::bind_executor(sock->get_tls_strand(),
			[sock, state, cancellation](const asio::error_code &ec) {
				if (ec || state->done.load(std::memory_order_acquire))
					return;
				state->timed_out = true;
				cancellation->emit(asio::cancellation_type::terminal);
				asio::error_code ignored;
				sock->get_raw().cancel(ignored);
				sock->get_raw().close(ignored);
			}));
		}
		catch (const std::exception &) {
			success = false;
			timer->cancel();
			if (shutdown_started) {
				cancellation->emit(asio::cancellation_type::terminal);
				asio::error_code ignored;
				sock->get_raw().cancel(ignored);
				sock->get_raw().close(ignored);
			}
			else
				state->done.store(true, std::memory_order_release);
		}
		while (!state->done.load(std::memory_order_acquire)) {
			network_cs_ext::async::get_global_settings().poll();
			cs_runtime_yield();
		}
		if (state->timed_out || (state->ec && state->ec != asio::error::eof))
			success = false;
		sock->reset_ssl();
	}
	// Raw socket shutdown
	if (sock->get_raw().is_open()) {
		asio::error_code ec;
		sock->get_raw().shutdown(asio::ip::tcp::socket::shutdown_both, ec);
		if (ec && ec != asio::error::not_connected)
			success = false;
	}
	// Close
	if (sock->get_raw().is_open()) {
		asio::error_code ec;
		sock->get_raw().close(ec);
		if (ec)
			success = false;
	}
	return success;
}
bool network_cs_ext::udp::socket::safe_close(socket_t &sock)
{
	if (!sock->get_raw().is_open())
		return true;
	// Spin until async_jobs drains or timeout expires.
	auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(NETWORK_SAFE_SHUTDOWN_TIMEOUT_MS);
	while (std::chrono::steady_clock::now() < deadline) {
		while (sock->async_jobs.load(std::memory_order_acquire) > 0) {
			if (std::chrono::steady_clock::now() >= deadline)
				break;
			network_cs_ext::async::get_global_settings().poll();
			cs_runtime_yield();
		}
		if (sock->async_jobs.load(std::memory_order_acquire) == 0)
			break;
	}
	if (sock->async_jobs.load(std::memory_order_acquire) > 0)
		return false;
	try {
		sock->close();
		return true;
	}
	catch (const std::exception &) {
		return false;
	}
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