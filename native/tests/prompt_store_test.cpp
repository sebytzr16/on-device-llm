#include "../src/prompt_store.h"
#include <cstdlib>
#include <iostream>
#include <vector>
static void check(bool ok, const char* what = "") { if (!ok) { std::cerr << "prompt store test failed " << what << "\n"; std::exit(1); } }
int main() {
    using namespace od_prompt_store;
    // The whole snapshot is charged: state, MTP head, checkpoint data and ids.
    check(entry_bytes(10, 2, 3, 4) == 10 + 2 + 3 + 4 * sizeof(int32_t));
    check(entry_bytes(0, 0, 0, 0) == 0);
    // A snapshot larger than the cap is rejected instead of evicting for it.
    check(admits(100, 100));
    check(!admits(100, 101));
    check(!admits(0, 1));
    check(!admits(100, 0));
    check(fits(100, 40, 60));
    check(!fits(100, 41, 60));
    check(!fits(100, 0, 101));
    // Least recently used goes first, and the entry being restored is kept.
    std::vector<uint64_t> used = {7, 3, 9, 5};
    std::vector<bool> pinned = {false, false, false, false};
    auto oldest = [&](size_t i) { return used[i]; };
    auto pinned_at = [&](size_t i) { return pinned[i]; };
    check(lru_victim(used.size(), oldest, pinned_at) == 1);
    pinned[1] = true;
    check(lru_victim(used.size(), oldest, pinned_at) == 3);
    // Evicting the least recently used entries leaves room for the new one.
    pinned = {false, false, false, false};
    std::vector<bool> evicted(used.size(), false);
    size_t total = 100;
    for (int i = 0; i < 3; ++i) {
        const int victim = lru_victim(used.size(), oldest, pinned_at);
        check(victim >= 0 && !evicted[victim], "evicted an entry twice");
        evicted[victim] = true;
        pinned[victim] = true;
        total -= 20;
    }
    check(evicted[1] && evicted[3] && evicted[0], "eviction order is not LRU");
    check(fits(100, total, 60), "room was not made for the new entry");
    // With every entry pinned there is no victim, so the snapshot is skipped.
    pinned = {true, true, true, true};
    check(lru_victim(used.size(), oldest, pinned_at) == -1);
    check(lru_victim(0, oldest, pinned_at) == -1);
    std::cout << "prompt_store: all tests passed\n";
}
