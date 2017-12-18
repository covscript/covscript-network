#pragma once

#define ASIO_STANDALONE

#if defined(__WIN32__) || defined(WIN32)
#define _WIN32_WINDOWS
#endif

#include "asio.hpp"

namespace cs_impl {
}