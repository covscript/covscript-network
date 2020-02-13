//
// Created by kiva on 2020/2/5.
//
#pragma once

#include <string>
#include <functional>

template <typename T>
using function = std::function<T>;

class download_task_base {
private:
    std::string _url;
    bool _resume = false;
    long _timeout = 10;
    long _start_pos = 0;

public:
    function<void()> _on_start;
    function<void()> _on_end;
    function<void(double, double)> _on_internal_progress;
    function<void(const char *, size_t, size_t, size_t *)> _on_internal_write;
    function<void()> _on_internal_ok;
    function<void(const std::string &)> _on_error;

public:
    download_task_base() = default;

    virtual ~download_task_base() = default;

public:
    void set_url(const std::string &url) {
        this->_url = url;
    }

    void resume_from_last(long position) {
        this->_resume = true;
        this->_start_pos = position;
    }

    void set_timeout(long timeout) {
        this->_timeout = timeout;
    }

    void perform();
};

template <typename T>
class download_task : public download_task_base {
private:
    T _buffer;

public:
    function<void(int)> _on_progress;
    function<void(T *)> _on_ok;
    function<void(T *, const char *, size_t, size_t, size_t *)> _on_write;

private:
    void init_callbacks() {
        _on_internal_ok = [this]() {
            if (_on_ok) {
                _on_ok(&_buffer);
            }
        };

        _on_internal_progress = [this](double total, double wrote) {
            if (_on_progress) {
                _on_progress(static_cast<int>(wrote / total * 100));
            }
        };

        _on_internal_write = [this](const char *data, size_t size,
                                    size_t nmemb, size_t *wrote) {
            if (_on_write) {
                _on_write(&_buffer, data, size, nmemb, wrote);
            }
        };
    }

protected:
    T &get_buffer() {
        return _buffer;
    }

public:
    download_task() {
        init_callbacks();
    }

    explicit download_task(const std::string &url) {
        set_url(url);
        init_callbacks();
    }

    ~download_task() override = default;

    download_task(download_task &&) = delete;

    download_task(const download_task &) = delete;

    download_task &operator=(download_task &&) = delete;

    download_task &operator=(const download_task &) = delete;
};

struct network final {
    static std::string get_url_text(const std::string &url);
};
