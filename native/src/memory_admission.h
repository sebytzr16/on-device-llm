#pragma once
#include <mutex>
#include <new>
#include <cstdint>
#include <cstddef>
#include <algorithm>
#include <limits>
#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <cwchar>
#endif

// A std::mutex in each DLL is not process-wide. Use the same OS mutex in
// every llama variant and the SD bridge. Serialize live measurement through
// allocation, including lazy helper growth and resolution-dependent SD graphs.
// Resident allocations are already reflected in the next live memory query.
class MemoryAdmission {
#if defined(_WIN32)
    HANDLE handle = nullptr;
#else
    static std::recursive_mutex & mutex() { static std::recursive_mutex m; return m; }
    std::unique_lock<std::recursive_mutex> lock{mutex(), std::defer_lock};
#endif
public:
    // [wait] false tries once: an optional allocation (the prompt store is a
    // cache) is skipped when another transaction is in progress rather than
    // stalling behind it.
    explicit MemoryAdmission(bool wait = true) noexcept {
#if defined(_WIN32)
        wchar_t name[96];
        std::swprintf(name, 96, L"Local\\OnDeviceLLM-memory-%lu", static_cast<unsigned long>(GetCurrentProcessId()));
        handle = CreateMutexW(nullptr, FALSE, name);
        if (!handle) return;
        const auto result = WaitForSingleObject(handle, wait ? INFINITE : 0);
        if (result != WAIT_OBJECT_0 && result != WAIT_ABANDONED) {
            CloseHandle(handle); handle = nullptr;
            return;
        }
#else
        if (wait) lock.lock(); else lock.try_lock();
#endif
    }
    // Same Windows headroom as llama RAM admission. Existing resident
    // runtimes are already subtracted from ullAvailPhys by the OS.
    static size_t & reserved_host() { static size_t bytes = 0; return bytes; }
    static size_t host_budget() {
#if defined(_WIN32)
        MEMORYSTATUSEX ram{}; ram.dwLength = sizeof(ram);
        if (!GlobalMemoryStatusEx(&ram)) return 0;
        const uint64_t margin = std::max<uint64_t>(1ull << 30, ram.ullTotalPhys / 8);
        const uint64_t free = ram.ullAvailPhys > margin ? ram.ullAvailPhys - margin : 0;
        return free > reserved_host() ? static_cast<size_t>(free - reserved_host()) : 0;
#else
        return std::numeric_limits<size_t>::max();
#endif
    }
    static void require_host(size_t pending) {
        if (pending > host_budget()) throw std::bad_alloc();
    }
    // Keep the output copies out of the RAM available to measured graphs.
    // All users run under this allocation transaction's OS mutex.
    class HostReservation {
        size_t bytes;
    public:
        explicit HostReservation(size_t pending) : bytes(pending) {
            require_host(bytes);
            reserved_host() += bytes;
        }
        ~HostReservation() { reserved_host() -= bytes; }
        HostReservation(const HostReservation &) = delete;
        HostReservation & operator=(const HostReservation &) = delete;
    };
    bool held() const {
#if defined(_WIN32)
        return handle != nullptr;
#else
        return lock.owns_lock();
#endif
    }
    void check() const {
        if (!held()) throw std::bad_alloc();
    }
    ~MemoryAdmission() {
#if defined(_WIN32)
        if (handle) { ReleaseMutex(handle); CloseHandle(handle); }
#endif
    }
    MemoryAdmission(const MemoryAdmission &) = delete;
    MemoryAdmission & operator=(const MemoryAdmission &) = delete;
};
