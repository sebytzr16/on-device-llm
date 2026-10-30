#include "../src/load_policy.h"
#include <cstdlib>
#include <iostream>
#include <vector>
static void check(bool ok) { if (!ok) { std::cerr << "load policy test failed\n"; std::exit(1); } }
int main() {
    using namespace od_load_policy;
    check(mtp_only("qwen35moe", 1, false)); // measured 23-tensor head, no blk.0
    check(!mtp_only("qwen35moe", 1, true)); // integrated heads
    check(!mtp_only("qwen35moe", 0, false));
    check(mtp_only("gemma4-assistant", 0, true));
    check(all_layers(64, 41)); check(all_layers(42, 41));
    check(!all_layers(41, 41)); check(!all_layers(20, 41));
    check(!all_layers(0, 41)); check(all_layers(999, 0)); check(!all_layers(64, 0));
    std::vector<std::string> a = {"zero", "one", "two", "three", "four", "five"}, b = a;
    auto ta = [&](int i) { return a[i].c_str(); };
    auto tb = [&](int i) { return b[i].c_str(); };
    check(vocabulary_difference(6, 6, ta, tb).empty());
    check(!vocabulary_difference(6, 7, ta, tb).empty());
    for (int i = 0; i < 6; ++i) { b = a; b[i] = "different"; check(!vocabulary_difference(6, 6, ta, tb).empty()); }
    std::cout << "load_policy: all tests passed\n";
}
