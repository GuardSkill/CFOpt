# Domestic document services direct routing

## Goal

Route Feishu, Yuque, QQ and QQ Mail, Youdao Dictionary and Notes, Baidu, and Zhihu domains directly in every generated subscription configuration.

## Design

All three Subconverter configuration files already route `rules/MainlandDirect.list` to the `Direct` group before fallback proxy rules. The change remains centralized in that list, avoiding duplicated inline domain rules and preserving identical behaviour in the full and lite configurations.

Existing coverage already includes Feishu/Lark, QQ/QQ Mail, Youdao, and Baidu. Add the missing Yuque domain suffixes (`yuque.com`, `yuque.com.cn`, `yuqueapp.com`, `yuqueapp.cn`, `yuqueusercontent.com`) and Zhihu domain suffixes (`zhihu.com`, `zhihu.cn`, `zhimg.com`, `zhihuishu.com`).

## Validation

Extend the existing Linux script test to assert every requested service suffix is present in `rules/MainlandDirect.list`, and retain the existing assertion that every Subconverter configuration references that list as `Direct`.

## Taiwan benchmark exception

TW remains a candidate and dedicated focus country in both runners, but has no country download-speed floor. Remove `TW=3` from the Windows and Linux default floor strings and update their tests and documentation. Other country floors remain unchanged.
