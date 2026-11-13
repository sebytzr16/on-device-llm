#pragma once
#include <cstddef>
#include <cstdint>

// Byte accounting and eviction order for the cross-request prompt store. Keep
// these helpers pure: a snapshot must be charged and room made for it *before*
// its state is allocated, because serializing first would hold the new copy
// beside the entries it replaces.
namespace od_prompt_store {
// Resident bytes of a stored sequence: serialized state and MTP head state,
// its rollback checkpoints, and the token ids kept with it (llama_token is a
// 32-bit id).
inline size_t entry_bytes(size_t state, size_t head, size_t marks, size_t tokens) {
    return state + head + marks + tokens * sizeof(int32_t);
}
// A single entry larger than the cap can never be cached, whatever is evicted.
inline bool admits(size_t limit, size_t entry) { return entry > 0 && entry <= limit; }
// Whether [entry] fits beside [total] resident bytes under [limit].
inline bool fits(size_t limit, size_t total, size_t entry) {
    return admits(limit, entry) && total <= limit - entry;
}
// Index of the least recently used unpinned entry, oldest first; -1 when none.
template <typename Used, typename Pinned>
int lru_victim(size_t count, Used used, Pinned pinned) {
    int victim = -1;
    for (size_t i = 0; i < count; ++i) {
        if (pinned(i)) continue;
        if (victim < 0 || used(i) < used((size_t)victim)) victim = (int)i;
    }
    return victim;
}
} // namespace od_prompt_store
