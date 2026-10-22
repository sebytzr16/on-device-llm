# Upstream ZIM regression archives

Unmodified fixtures from [openzim/zim-testing-suite](https://github.com/openzim/zim-testing-suite/tree/2edf72096208e60c82b6ebbe313baa552cc6af52), pinned at `2edf72096208e60c82b6ebbe313baa552cc6af52`. They supplement the hand-built fixture; their successful reads do not establish compatibility with every large archive.

| Local file | Upstream path | Bytes | SHA-256 |
|---|---|---:|---|
| libzim-modern.zim | data/noTitleListingV0/small.zim | 42,098 | 5ce75d0ac511dce286418d81216ea8cfce20280248200aaa737b8f2c73730aaa |
| kiwix-wikibooks.zim | data/withns/wikibooks_be_all_nopic_2017-02.zim | 152,865 | 99465e14effc7f951e9c017b4b3cee91967eb49c556d9f4f0d674adbe80d78c2 |

The first archive exercises the modern title listing without a legacy listing. The second is a real Kiwix Wikibooks archive with Belarusian Unicode titles and legacy namespaces. Archive content retains its upstream attribution and licensing. Do not regenerate or alter these files.
