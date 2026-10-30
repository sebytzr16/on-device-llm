#pragma once
#include <cstdint>
#include <string>

namespace od_load_policy {
// GGUF identity and tensor-directory facts, independent of filename/payload.
inline bool mtp_only(const std::string & arch, uint32_t nextn, bool has_block_zero) {
    return (arch.size() >= 10 && arch.compare(arch.size() - 10, 10, "-assistant") == 0)
        || (nextn > 0 && !has_block_zero);
}
inline bool all_layers(int requested, uint32_t blocks) {
    return requested >= 999 || (blocks > 0 && requested >= int64_t(blocks) + 1);
}
// Stricter than common/speculative.cpp's legacy 128-token/first-five
// exceptions: this bridge shares every token ID directly, without mapping.
template <class TargetToken, class DraftToken>
std::string vocabulary_difference(int target_size, int draft_size, TargetToken target, DraftToken draft) {
    if (target_size != draft_size) return "the draft model's vocabulary size differs (" + std::to_string(draft_size) + " vs " + std::to_string(target_size) + ")";
    for (int i = 0; i < target_size; ++i) {
        const char * a = target(i), * b = draft(i);
        if (!a || !b || std::string(a) != b) return "the draft model's vocabulary differs at token " + std::to_string(i);
    }
    return "";
}
}
