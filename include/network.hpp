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
#define WIN32_LEAN_AND_MEAN
#endif

#include <asio.hpp>
#include <asio/ssl.hpp>
#include <covscript/covscript.hpp>
#include <openssl/x509.h>

#ifdef _WIN32
#include <windows.h>
#include <wincrypt.h>
// undef WinCrypt macros that conflict with OpenSSL type names
#undef X509_NAME
#undef X509_CERT_PAIR
#undef X509_EXTENSIONS
#undef PKCS7_SIGNER_INFO
#undef OCSP_REQUEST
#undef OCSP_RESPONSE
#endif
#include <string>
#include <atomic>
#include <memory>
#include <mutex>
#include <vector>
#include <sstream>
#include <stdexcept>
#include <cstdlib>

namespace cs_impl {
	namespace network {
		enum class ssl_trust_mode {
			auto_mode,
			openssl,
			custom,
			insecure
		};

		struct ssl_options {
			ssl_trust_mode trust_mode = ssl_trust_mode::auto_mode;
			bool verify_peer = true;
			bool verify_host = true;
			std::string ca_file;
			std::string ca_path;
		};

		static asio::io_context &get_io_context()
		{
			static asio::io_context instance;
			return instance;
		}
		namespace detail {
			static std::string &last_tls_trust_report_slot()
			{
				static thread_local std::string report = "trust_mode=unset; loaded=(none); failed=(none)";
				return report;
			}

			static void set_last_tls_trust_report(const std::string &report)
			{
				last_tls_trust_report_slot() = report;
			}

			static const std::string &get_last_tls_trust_report()
			{
				return last_tls_trust_report_slot();
			}

			struct trust_load_report {
				bool loaded_any = false;
				std::vector<std::string> loaded_sources;
				std::vector<std::string> failed_sources;

				void mark_loaded(const std::string &src)
				{
					loaded_any = true;
					loaded_sources.push_back(src);
				}

				void mark_failed(const std::string &src, const std::string &reason)
				{
					failed_sources.push_back(src + " (" + reason + ")");
				}
			};

			static std::string join_items(const std::vector<std::string> &items)
			{
				if (items.empty())
					return "(none)";
				std::ostringstream oss;
				for (std::size_t i = 0; i < items.size(); ++i) {
					if (i != 0)
						oss << "; ";
					oss << items[i];
				}
				return oss.str();
			}

			static bool try_load_verify_file(asio::ssl::context &ctx, const std::string &path, trust_load_report &report, const std::string &source)
			{
				if (path.empty())
					return false;
				try {
					ctx.load_verify_file(path);
					report.mark_loaded(source + ":" + path);
					return true;
				}
				catch (const std::exception &e) {
					report.mark_failed(source + ":" + path, e.what());
					return false;
				}
			}

			static bool try_add_verify_path(asio::ssl::context &ctx, const std::string &path, trust_load_report &report, const std::string &source)
			{
				if (path.empty())
					return false;
				try {
					ctx.add_verify_path(path);
					report.mark_loaded(source + ":" + path);
					return true;
				}
				catch (const std::exception &e) {
					report.mark_failed(source + ":" + path, e.what());
					return false;
				}
			}

			static void try_load_env_trust_sources(asio::ssl::context &ctx, trust_load_report &report)
			{
				// Cache environment variables at first call (static local init is thread-safe in C++11+)
				static const std::string cert_file = []() -> std::string {
					const char *val = std::getenv("SSL_CERT_FILE");
					return (val != nullptr && val[0] != '\0') ? val : "";
				}();
				static const std::string cert_dir = []() -> std::string {
					const char *val = std::getenv("SSL_CERT_DIR");
					return (val != nullptr && val[0] != '\0') ? val : "";
				}();

				if (!cert_file.empty())
					try_load_verify_file(ctx, cert_file, report, "env:SSL_CERT_FILE");
				if (!cert_dir.empty())
					try_add_verify_path(ctx, cert_dir, report, "env:SSL_CERT_DIR");
			}

			// Platform-specific fallback certificate paths.
			//
			// These are tried ONLY when OpenSSL's set_default_verify_paths() fails
			// (e.g., OpenSSL was built with a non-default OPENSSLDIR, or the system
			// cert store is in an unexpected location). The paths listed here are
			// common defaults for each platform and may drift over time as package
			// managers change layouts.
			//
			// The "auto" trust mode uses a layered strategy for resilience:
			//   1. OpenSSL's set_default_verify_paths() (compile-time OPENSSLDIR)
			//   2. Environment variables SSL_CERT_FILE / SSL_CERT_DIR
			//   3. Platform-specific fallback paths (this function)
			//
			// If you need a specific cert file or directory, use trust_mode="custom"
			// with ca_file / ca_path instead of relying on these fallbacks.
			static void try_load_platform_fallback_trust_sources(asio::ssl::context &ctx, trust_load_report &report)
			{
#if defined(__linux__)
				const char *file_candidates[] = {
					"/etc/ssl/certs/ca-certificates.crt",
					"/etc/pki/tls/certs/ca-bundle.crt",
					"/etc/ssl/ca-bundle.pem",
					"/etc/pki/tls/cacert.pem",
					"/etc/ssl/cert.pem"
				};
				const char *dir_candidates[] = {
					"/etc/ssl/certs",
					"/etc/pki/tls/certs"
				};
				for (const auto *path : file_candidates)
					try_load_verify_file(ctx, path, report, "linux:file");
				for (const auto *path : dir_candidates)
					try_add_verify_path(ctx, path, report, "linux:dir");
#elif defined(__APPLE__)
				const char *file_candidates[] = {
					"/etc/ssl/cert.pem",
					"/opt/homebrew/etc/openssl@3/cert.pem",
					"/usr/local/etc/openssl@3/cert.pem",
					"/opt/homebrew/etc/openssl@1.1/cert.pem",
					"/usr/local/etc/openssl@1.1/cert.pem"
				};
				const char *dir_candidates[] = {
					"/opt/homebrew/etc/openssl@3/certs",
					"/usr/local/etc/openssl@3/certs",
					"/opt/homebrew/etc/openssl@1.1/certs",
					"/usr/local/etc/openssl@1.1/certs"
				};
				for (const auto *path : file_candidates)
					try_load_verify_file(ctx, path, report, "macos:file");
				for (const auto *path : dir_candidates)
					try_add_verify_path(ctx, path, report, "macos:dir");
#elif defined(__FreeBSD__) || defined(__FreeBSD_kernel__) || defined(__OpenBSD__) || defined(__NetBSD__) || defined(__DragonFly__)
				const char *file_candidates[] = {
					"/usr/local/share/certs/ca-root-nss.crt",
					"/etc/ssl/cert.pem"
				};
				const char *dir_candidates[] = {
					"/usr/local/share/certs",
					"/etc/ssl/certs"
				};
				for (const auto *path : file_candidates)
					try_load_verify_file(ctx, path, report, "bsd:file");
				for (const auto *path : dir_candidates)
					try_add_verify_path(ctx, path, report, "bsd:dir");
#else
				(void)ctx;
				(void)report;
#endif
			}

			static std::runtime_error build_trust_error(const char *mode, const trust_load_report &report)
			{
				std::ostringstream oss;
				oss << "TLS " << mode << " trust store initialization failed. "
				    << "Loaded: " << join_items(report.loaded_sources) << ". "
				    << "Tried/failed: " << join_items(report.failed_sources) << ".";
				return std::runtime_error(oss.str());
			}

			static std::string build_trust_report(const char *mode, const trust_load_report &report)
			{
				std::ostringstream oss;
				oss << "trust_mode=" << mode
				    << "; loaded=" << join_items(report.loaded_sources)
				    << "; failed=" << join_items(report.failed_sources);
				return oss.str();
			}

#ifdef _WIN32
			static void load_windows_root_certs(asio::ssl::context &ctx, trust_load_report &report)
			{
				// Load from multiple Windows system certificate stores to cover
				// enterprise and platform-managed chains.
				const char *stores[] = {"ROOT", "CA", "AuthRoot"};
				for (const auto *store_name : stores) {
					HCERTSTORE hStore = CertOpenSystemStoreA(0, store_name);
					if (!hStore) {
						report.mark_failed(std::string("windows:") + store_name,
						                   "failed to open " + std::string(store_name) + " cert store");
						continue;
					}
					PCCERT_CONTEXT pCert = nullptr;
					bool loaded_any = false;
					while ((pCert = CertEnumCertificatesInStore(hStore, pCert)) != nullptr) {
						const unsigned char *enc = pCert->pbCertEncoded;
						X509 *x509 = d2i_X509(nullptr, &enc, static_cast<long>(pCert->cbCertEncoded));
						if (x509) {
							if (X509_STORE_add_cert(SSL_CTX_get_cert_store(ctx.native_handle()), x509))
								loaded_any = true;
							X509_free(x509);
						}
					}
					if (loaded_any)
						report.mark_loaded(std::string("windows:") + store_name);
					else
						report.mark_failed(std::string("windows:") + store_name,
						                   "no certificates decoded from " + std::string(store_name) + " store");
					CertCloseStore(hStore, 0);
				}
			}
#endif

			static std::string configure_client_context(asio::ssl::context &ctx, const ssl_options &options)
			{
				switch (options.trust_mode) {
				case ssl_trust_mode::auto_mode: {
					trust_load_report report;
					try {
						ctx.set_default_verify_paths();
						report.mark_loaded("openssl:default_verify_paths");
					}
					catch (const std::exception &e) {
						report.mark_failed("openssl:default_verify_paths", e.what());
					}
					try_load_env_trust_sources(ctx, report);
#ifdef _WIN32
					load_windows_root_certs(ctx, report);
#else
					try_load_platform_fallback_trust_sources(ctx, report);
#endif
					if (!report.loaded_any)
						throw build_trust_error("auto", report);
					return build_trust_report("auto", report);
				}
				case ssl_trust_mode::openssl: {
					trust_load_report report;
					try {
						ctx.set_default_verify_paths();
						report.mark_loaded("openssl:default_verify_paths");
					}
					catch (const std::exception &e) {
						report.mark_failed("openssl:default_verify_paths", e.what());
					}
					try_load_env_trust_sources(ctx, report);
					if (!report.loaded_any)
						throw build_trust_error("openssl", report);
					return build_trust_report("openssl", report);
				}
				case ssl_trust_mode::custom: {
					trust_load_report report;
					if (options.ca_file.empty() && options.ca_path.empty())
						throw std::runtime_error("TLS custom trust mode requires ca_file or ca_path.");
					if (!options.ca_file.empty())
						try_load_verify_file(ctx, options.ca_file, report, "custom:ca_file");
					if (!options.ca_path.empty())
						try_add_verify_path(ctx, options.ca_path, report, "custom:ca_path");
					if (!report.loaded_any)
						throw build_trust_error("custom", report);
					return build_trust_report("custom", report);
				}
				case ssl_trust_mode::insecure:
					return "trust_mode=insecure; loaded=(none); failed=(none)";
				default:
					throw std::runtime_error("Unsupported TLS trust mode.");
				}
			}

			// Precondition: options.verify_host && !options.verify_peer must be
			// rejected by the caller (init_ssl) before reaching this point.
			template <typename stream_t>
			static void configure_client_stream(stream_t &stream, const std::string &host, const ssl_options &options)
			{
				if (!SSL_set_tlsext_host_name(stream.native_handle(), host.c_str()))
					throw std::runtime_error("Failed to set TLS SNI host name.");
				if (options.trust_mode == ssl_trust_mode::insecure || !options.verify_peer)
					stream.set_verify_mode(asio::ssl::verify_none);
				else
					stream.set_verify_mode(asio::ssl::verify_peer);
				if (options.trust_mode != ssl_trust_mode::insecure && options.verify_host)
					stream.set_verify_callback(asio::ssl::host_name_verification(host));
			}
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
				tcp::resolver resolver(get_io_context());
				tcp::resolver::results_type results = resolver.resolve(host, service);
				cs::var ret = cs::var::make<cs::array>();
				cs::array &arr = ret.val<cs::array>();
				for (auto &ep : results)
					arr.push_back(cs::var::make<tcp::endpoint>(ep));
				return ret;
			}

			class socket final {
				tcp::socket sock;
				asio::strand<asio::io_context::executor_type> tls_strand;
				std::unique_ptr<asio::ssl::context> tls_ctx;
				std::unique_ptr<asio::ssl::stream<tcp::socket &>> tls_stream;
				std::string last_tls_trust_report = "trust_mode=unset; loaded=(none); failed=(none)";
				mutable std::mutex tls_report_mutex;
				std::atomic<bool> tls_enabled{false};
				std::atomic<bool> exclusive_operation{false};
				std::atomic<bool> read_operation{false};
				std::atomic<bool> write_operation{false};

				enum class io_direction { read, write };

				bool try_begin_io_job() noexcept
				{
					if (exclusive_operation.load(std::memory_order_acquire))
						return false;
					async_jobs.fetch_add(1, std::memory_order_acq_rel);
					if (exclusive_operation.load(std::memory_order_acquire)) {
						async_jobs.fetch_sub(1, std::memory_order_release);
						return false;
					}
					return true;
				}

				bool try_begin_io_job(io_direction direction) noexcept
				{
					auto &operation = direction == io_direction::read ? read_operation : write_operation;
					bool expected = false;
					if (!operation.compare_exchange_strong(expected, true,
					                                       std::memory_order_acq_rel, std::memory_order_acquire))
						return false;
					if (!try_begin_io_job()) {
						operation.store(false, std::memory_order_release);
						return false;
					}
					return true;
				}

				void begin_io_job(io_direction direction)
				{
					auto &operation = direction == io_direction::read ? read_operation : write_operation;
					bool expected = false;
					if (!operation.compare_exchange_strong(expected, true,
					                                       std::memory_order_acq_rel, std::memory_order_acquire))
						throw std::runtime_error(direction == io_direction::read
						                         ? "Another read operation is already pending on this socket."
						                         : "Another write operation is already pending on this socket.");
					if (!try_begin_io_job()) {
						operation.store(false, std::memory_order_release);
						throw std::runtime_error("Cannot start I/O while an exclusive socket operation is pending.");
					}
				}

				void finish_io_job(io_direction direction) noexcept
				{
					async_jobs.fetch_sub(1, std::memory_order_release);
					auto &operation = direction == io_direction::read ? read_operation : write_operation;
					operation.store(false, std::memory_order_release);
				}

				class scoped_io_job {
					socket &owner;
					io_direction direction;

				public:
					scoped_io_job(socket &sock, io_direction operation_direction)
						: owner(sock), direction(operation_direction)
					{
						owner.begin_io_job(direction);
					}
					~scoped_io_job()
					{
						owner.finish_io_job(direction);
					}
				};

				void begin_exclusive_operation(const char *active_io_error)
				{
					bool expected_exclusive = false;
					if (!exclusive_operation.compare_exchange_strong(expected_exclusive, true,
					        std::memory_order_acq_rel, std::memory_order_acquire))
						throw std::runtime_error("Another exclusive socket operation is already pending.");
					std::size_t expected_jobs = 0;
					if (!async_jobs.compare_exchange_strong(expected_jobs, 1,
					                                        std::memory_order_acq_rel, std::memory_order_acquire)) {
						exclusive_operation.store(false, std::memory_order_release);
						throw std::runtime_error(active_io_error);
					}
				}

				void end_exclusive_operation() noexcept
				{
					async_jobs.fetch_sub(1, std::memory_order_release);
					exclusive_operation.store(false, std::memory_order_release);
				}

				class scoped_exclusive_operation {
					socket &owner;

				public:
					scoped_exclusive_operation(socket &sock, const char *active_io_error) : owner(sock)
					{
						owner.begin_exclusive_operation(active_io_error);
					}
					~scoped_exclusive_operation()
					{
						owner.end_exclusive_operation();
					}
				};

				void init_ssl(const std::string &host, const ssl_options &options)
				{
					if (!sock.is_open())
						throw std::runtime_error("TCP socket is not connected.");
					if (tls_stream)
						throw std::runtime_error("TLS has already been enabled on this socket.");
					// Validate options before allocating OpenSSL state for fail-fast behavior
					if (options.verify_host && !options.verify_peer)
						throw std::runtime_error("TLS host verification requires peer verification.");
					auto new_ctx = std::make_unique<asio::ssl::context>(asio::ssl::context::tls_client);
					try {
						auto report = detail::configure_client_context(*new_ctx, options);
						{
							std::lock_guard<std::mutex> lock(tls_report_mutex);
							last_tls_trust_report = report;
						}
						detail::set_last_tls_trust_report(report);
					}
					catch (const std::exception &e) {
						auto report = std::string("trust_mode=error; loaded=(none); failed=") + e.what();
						{
							std::lock_guard<std::mutex> lock(tls_report_mutex);
							last_tls_trust_report = report;
						}
						detail::set_last_tls_trust_report(report);
						throw;
					}
					auto new_stream = std::make_unique<asio::ssl::stream<tcp::socket &>>(sock, *new_ctx);
					detail::configure_client_stream(*new_stream, host, options);
					tls_ctx = std::move(new_ctx);
					tls_stream = std::move(new_stream);
					tls_enabled.store(true, std::memory_order_release);
				}

				void clear_ssl(bool clear_report = true)
				{
					tls_enabled.store(false, std::memory_order_release);
					tls_stream.reset();
					tls_ctx.reset();
					if (clear_report) {
						std::lock_guard<std::mutex> lock(tls_report_mutex);
						last_tls_trust_report = "trust_mode=unset; loaded=(none); failed=(none)";
					}
				}

			public:
				// Counts active I/O jobs; exclusive operations reserve one slot.
				std::atomic<std::size_t> async_jobs{0};

				socket() : sock(get_io_context()), tls_strand(asio::make_strand(get_io_context())) {}

				socket(const socket &) = delete;

				tcp::socket &get_raw()
				{
					return sock;
				}

				void connect(const tcp::endpoint &ep)
				{
					scoped_exclusive_operation operation(
					    *this, "Cannot connect while socket I/O is pending.");
					sock.connect(ep);
				}

				void connect_ssl(const std::string &host, const ssl_options &options = ssl_options())
				{
					begin_tls_handshake();
					try {
						prepare_ssl(host, options);
					}
					catch (...) {
						end_tls_handshake();
						throw;
					}
					try {
						tls_stream->handshake(asio::ssl::stream_base::client);
					}
					catch (...) {
						clear_ssl(false);
						end_tls_handshake();
						throw;
					}
					end_tls_handshake();
				}

				void begin_tls_handshake()
				{
					if (tls_enabled.load(std::memory_order_acquire))
						throw std::runtime_error("TLS has already been enabled on this socket.");
					begin_exclusive_operation("Cannot enable TLS while asynchronous operations are pending.");
				}

				void end_tls_handshake() noexcept
				{
					end_exclusive_operation();
				}

				void begin_async_read()
				{
					begin_io_job(io_direction::read);
				}
				void end_async_read() noexcept
				{
					finish_io_job(io_direction::read);
				}
				void begin_async_write()
				{
					begin_io_job(io_direction::write);
				}
				void end_async_write() noexcept
				{
					finish_io_job(io_direction::write);
				}
				void begin_async_connect()
				{
					begin_exclusive_operation("Cannot connect while socket I/O is pending.");
				}
				void end_async_connect() noexcept
				{
					end_exclusive_operation();
				}

				// Draining-exclusive reservation for safe_shutdown.
				// Sets exclusive_operation to block new I/O, then the
				// caller drains existing async_jobs cooperatively.
				void begin_draining_exclusive()
				{
					bool expected = false;
					if (!exclusive_operation.compare_exchange_strong(expected, true,
					        std::memory_order_acq_rel, std::memory_order_acquire))
						throw std::runtime_error(
						    "Another exclusive socket operation is already pending.");
				}
				void end_draining_exclusive() noexcept
				{
					exclusive_operation.store(false, std::memory_order_release);
				}

				void prepare_ssl(const std::string &host, const ssl_options &options = ssl_options())
				{
					init_ssl(host, options);
				}

				asio::ssl::stream<tcp::socket &> &get_tls_raw()
				{
					// Internal binding access. The caller must already hold an I/O or
					// exclusive-operation reservation for the stream's full use.
					if (!tls_stream)
						throw std::runtime_error("TLS is not enabled on this socket.");
					return *tls_stream;
				}

				asio::strand<asio::io_context::executor_type> &get_tls_strand()
				{
					return tls_strand;
				}

				void reset_ssl()
				{
					clear_ssl(false);
				}

				std::string get_ssl_trust_report() const
				{
					std::lock_guard<std::mutex> lock(tls_report_mutex);
					return last_tls_trust_report;
				}

				bool is_ssl() const
				{
					return tls_enabled.load(std::memory_order_acquire);
				}

				void close()
				{
					scoped_exclusive_operation operation(
					    *this, "close() called with async operations still in flight. Use safe_shutdown() instead.");
					if (tls_stream) {
						asio::error_code ec;
						tls_stream->shutdown(ec);
						clear_ssl();
					}
					sock.close();
				}

				void accept(tcp::acceptor &a)
				{
					scoped_exclusive_operation operation(
					    *this, "Cannot accept into a socket while socket I/O is pending.");
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
					if (!try_begin_io_job(io_direction::read))
						return 0;
					struct job_guard {
						socket &owner;
						~job_guard()
						{
							owner.finish_io_job(io_direction::read);
						}
					} job{*this};
					if (tls_enabled.load(std::memory_order_acquire))
						return 0; // asio::ssl::stream does not support available(); encrypted byte count is meaningless
					return sock.available();
				}

				std::string receive(std::size_t maximum)
				{
					scoped_io_job job(*this, io_direction::read);
					std::vector<char> buff(maximum);
					std::size_t actually = tls_stream
					                       ? tls_stream->read_some(asio::buffer(buff))
					                       : sock.read_some(asio::buffer(buff));
					return std::string(buff.data(), actually);
				}

				std::string read(std::size_t size)
				{
					scoped_io_job job(*this, io_direction::read);
					std::vector<char> buff(size);
					std::size_t n = tls_stream
					                ? asio::read(*tls_stream, asio::buffer(buff))
					                : asio::read(sock, asio::buffer(buff));
					return std::string(buff.data(), n);
				}

				std::size_t send(const std::string &s)
				{
					scoped_io_job job(*this, io_direction::write);
					if (tls_stream)
						return tls_stream->write_some(asio::buffer(s));
					else
						return sock.write_some(asio::buffer(s));
				}

				void write(const std::string &s)
				{
					scoped_io_job job(*this, io_direction::write);
					if (tls_stream)
						asio::write(*tls_stream, asio::buffer(s));
					else
						asio::write(sock, asio::buffer(s));
				}

				void shutdown()
				{
					scoped_exclusive_operation operation(
					    *this, "shutdown() called with async operations still in flight. Use safe_shutdown() instead.");
					if (tls_stream) {
						asio::error_code ec;
						tls_stream->shutdown(ec);
						clear_ssl();
					}
					asio::error_code ec;
					sock.shutdown(tcp::socket::shutdown_both, ec);
					if (ec && ec != asio::error::not_connected)
						throw asio::system_error(ec);
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
				udp::resolver resolver(get_io_context());
				udp::resolver::results_type results = resolver.resolve(host, service);
				cs::var ret = cs::var::make<cs::array>();
				cs::array &arr = ret.val<cs::array>();
				for (auto &ep : results)
					arr.push_back(cs::var::make<udp::endpoint>(ep));
				return ret;
			}

			class socket final {
				udp::socket sock;
				std::atomic<bool> exclusive_operation{false};
				std::atomic<bool> read_operation{false};
				std::atomic<bool> write_operation{false};

				enum class io_direction { read, write };

				bool try_begin_io_job() noexcept
				{
					if (exclusive_operation.load(std::memory_order_acquire))
						return false;
					async_jobs.fetch_add(1, std::memory_order_acq_rel);
					if (exclusive_operation.load(std::memory_order_acquire)) {
						async_jobs.fetch_sub(1, std::memory_order_release);
						return false;
					}
					return true;
				}

				bool try_begin_io_job(io_direction direction) noexcept
				{
					auto &operation = direction == io_direction::read ? read_operation : write_operation;
					bool expected = false;
					if (!operation.compare_exchange_strong(expected, true,
					                                       std::memory_order_acq_rel, std::memory_order_acquire))
						return false;
					if (!try_begin_io_job()) {
						operation.store(false, std::memory_order_release);
						return false;
					}
					return true;
				}

				void begin_io_job(io_direction direction)
				{
					auto &operation = direction == io_direction::read ? read_operation : write_operation;
					bool expected = false;
					if (!operation.compare_exchange_strong(expected, true,
					                                       std::memory_order_acq_rel, std::memory_order_acquire))
						throw std::runtime_error(direction == io_direction::read
						                         ? "Another receive operation is already pending on this UDP socket."
						                         : "Another send operation is already pending on this UDP socket.");
					if (!try_begin_io_job()) {
						operation.store(false, std::memory_order_release);
						throw std::runtime_error("Cannot start UDP I/O while close is pending.");
					}
				}

				void finish_io_job(io_direction direction) noexcept
				{
					async_jobs.fetch_sub(1, std::memory_order_release);
					auto &operation = direction == io_direction::read ? read_operation : write_operation;
					operation.store(false, std::memory_order_release);
				}

				class scoped_io_job {
					socket &owner;
					io_direction direction;

				public:
					scoped_io_job(socket &sock, io_direction operation_direction)
						: owner(sock), direction(operation_direction)
					{
						owner.begin_io_job(direction);
					}
					~scoped_io_job()
					{
						owner.finish_io_job(direction);
					}
				};

				void begin_exclusive_close()
				{
					bool expected_exclusive = false;
					if (!exclusive_operation.compare_exchange_strong(expected_exclusive, true,
					        std::memory_order_acq_rel, std::memory_order_acquire))
						throw std::runtime_error("Another UDP close operation is already pending.");
					std::size_t expected_jobs = 0;
					if (!async_jobs.compare_exchange_strong(expected_jobs, 1,
					                                        std::memory_order_acq_rel, std::memory_order_acquire)) {
						exclusive_operation.store(false, std::memory_order_release);
						throw std::runtime_error(
						    "close() called with async operations still in flight. Use safe_close() instead.");
					}
				}

				void end_exclusive_close() noexcept
				{
					async_jobs.fetch_sub(1, std::memory_order_release);
					exclusive_operation.store(false, std::memory_order_release);
				}

				class scoped_exclusive_close {
					socket &owner;

				public:
					explicit scoped_exclusive_close(socket &sock) : owner(sock)
					{
						owner.begin_exclusive_close();
					}
					~scoped_exclusive_close()
					{
						owner.end_exclusive_close();
					}
				};

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
					scoped_exclusive_close operation(*this);
					sock.close();
				}

				void begin_async_receive()
				{
					begin_io_job(io_direction::read);
				}
				void end_async_receive() noexcept
				{
					finish_io_job(io_direction::read);
				}
				void begin_async_send()
				{
					begin_io_job(io_direction::write);
				}
				void end_async_send() noexcept
				{
					finish_io_job(io_direction::write);
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
					if (!try_begin_io_job(io_direction::read))
						return 0;
					struct job_guard {
						socket &owner;
						~job_guard()
						{
							owner.finish_io_job(io_direction::read);
						}
					} job{*this};
					return sock.available();
				}

				std::string receive_from(std::size_t maximum, udp::endpoint &ep)
				{
					scoped_io_job job(*this, io_direction::read);
					std::vector<char> buff(maximum);
					std::size_t actually = sock.receive_from(asio::buffer(buff), ep);
					return std::string(buff.data(), actually);
				}

				void send_to(const std::string &s, const udp::endpoint &ep)
				{
					scoped_io_job job(*this, io_direction::write);
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
