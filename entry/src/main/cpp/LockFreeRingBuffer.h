//
// Created on 2025/11/8.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".
#include <atomic>
#include <array>
#include <string>
#include <vector>
#include <mutex>
#include <utility>

template<size_t N>
class LockFreeRingBuffer {
private:
    std::array<std::string, N> buffer_;
    std::atomic<size_t> write_index_{0};
    std::atomic<size_t> read_index_{0};
    mutable std::mutex buffer_mutex_;

public:
    // 多线程安全写入
    bool write(const std::string& message) {
        std::lock_guard<std::mutex> lock(buffer_mutex_);
        size_t current_write = write_index_.load(std::memory_order_relaxed);
        size_t next_write = (current_write + 1) % N;
        
        // 检查是否追上了读指针（缓冲区满）
        if (next_write == read_index_.load(std::memory_order_acquire)) {
            return false; // 缓冲区满，丢弃这条消息
        }
        
        buffer_[current_write] = message;
        write_index_.store(next_write, std::memory_order_release);
        return true;
    }

    // 单线程安全读取所有可用消息
    std::vector<std::string> read_all() {
        std::vector<std::string> result;
        
        std::lock_guard<std::mutex> lock(buffer_mutex_);
        
        size_t current_read = read_index_.load(std::memory_order_relaxed);
        size_t current_write = write_index_.load(std::memory_order_acquire);
        
        // 收集所有可读消息
        while (current_read != current_write) {
            result.push_back(std::move(buffer_[current_read]));
            std::string().swap(buffer_[current_read]);
            current_read = (current_read + 1) % N;
        }
        
        // 更新读指针（标记这些消息已读）
        read_index_.store(current_read, std::memory_order_release);
        return result;
    }

    // 获取可读消息数量
    size_t available() const {
        size_t read_idx = read_index_.load(std::memory_order_acquire);
        size_t write_idx = write_index_.load(std::memory_order_acquire);
        
        if (write_idx >= read_idx) {
            return write_idx - read_idx;
        } else {
            return N - read_idx + write_idx;
        }
    }

    // 清空缓冲区
    void clear() {
        std::lock_guard<std::mutex> lock(buffer_mutex_);
        read_index_.store(write_index_.load(std::memory_order_acquire), std::memory_order_release);
    }
};
