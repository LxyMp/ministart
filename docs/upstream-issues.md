# 上游 issue 对照档案

上游 [abue-ammar/tinycast](https://github.com/abue-ammar/tinycast) 的 issue 与本 fork 的对照记录。
每次查上游 issue 前先看这里，已判定的不重复排查；新查过的往这里补一行。
fork 点：`6029038f`（Send Apple Intelligence chats no instructions, #1693）。

## 已在本地修复的上游 issue

| Issue | 标题 | 本地修复 |
| --- | --- | --- |
| [#1722](https://github.com/abue-ammar/tinycast/issues/1722) | Show output hides a prompt's last line | drain 的阻塞 read 改为 40ms 定时 poll，静默期也强制 flush 未换行尾行 |
| [#1716](https://github.com/abue-ammar/tinycast/issues/1716) | `getSelectedText()` returns nothing in Chromium | 上游根因是读取时机在目标失焦后；本地 `selectedText()` 读的是被调色板顶掉的目标且不判空串即抛——空选区改为返回空串语义待实际复现后再修（本地暂未复现） |
| [#1707](https://github.com/abue-ammar/tinycast/issues/1707) | Extension OAuth cancellation leaves host call suspended | `ExtensionSignInSession` 加 `ResumeOnce`：onCancel 显式 resume，与浏览器回调路径先到先得、恰好一次 |
| [#1706](https://github.com/abue-ammar/tinycast/issues/1706) | Can't convert fractional units | tokenizer 重写 `数字/数字␣单位`（有空格、非率类单位）为除法结果值+单位附着；数字后的 `"` 识别为英寸符号；`5/16" in mm`、`5/16 inch in mm` 均正确 |
| [#1697](https://github.com/abue-ammar/tinycast/issues/1697) | Clipboard history silently drops copies that carry only HTML or RTF | 富文本回退：`poll()` 在纯文本与图片分支之间读 RTF/HTML 并拍平入库 |
| [#1655](https://github.com/abue-ammar/tinycast/issues/1655) | Long snippet template crashes the snippet editor | `FormTextArea` 自带 `NSScrollView` 并限高，超长文本内部滚动 |

## 已核查、不影响本地的（原因）

| Issue | 标题 | 原因 |
| --- | --- | --- |
| #1699 | OpenCode v2 cannot access MCP servers | AI/MCP 功能已删 |
| #1691 | Dictation shortcut closes Quick AI | 听写与 AI 已删 |
| #1675 | Caps Lock as hyper key locks state | Hyper Key 已删 |
| #1656 | Keyboard freezes after update installed without restart | 应用内更新已删，无新旧进程共存场景 |
| #1682 | System Translate prompt claims language missing | QuickActions 已删 |
| #1662 | Switch Windows omits minimized windows | 窗口切换器已删 |
| #1661 | Confluence extension OAuth fails | 第三方扩展自身问题 |
| #1704 | Visual glitch at launcher corners | 打开动画边角发丝线，无法稳定复现且不影响功能，观察 |
| #1669 | Calculator doesn't recognize decimal numbers | 实测正常；小数处理在 fork 后本地重写过（仅 `.` 为小数点） |
| #1676 | Escape doesn't bubble out of sub-screens | 本地有 `PaletteEscapeAction` 七级阶梯，palette-escape-test 覆盖 |
| #1672 | Esc sometimes closes instead of popping to root | esc 阶梯同上；"重开恢复上次模式"（`restoreAnyMode`）是有意设计，保留 |
| #1651 | Clipboard does not paste on Enter | 回车默认即粘贴（`ClipboardDefaultAction` 默认 `.paste`），日常使用正常 |

## 已核查、本地差距（未修，按需处理）

| Issue | 标题 | 现状 |
| --- | --- | --- |
| #1649 | Special characters and Chinese app names | 特殊字符（全角冒号等）搜索正常；应用名取磁盘名（英文），搜"终端"找不到 Terminal——本地化应用名未实现，个人版按需再加 |

## 纯功能请求（不跟进）

#1696（独立文件搜索作用域）、#1694（文件夹收藏）、#1663（New Application Window 动作）、
#1652（按需请求完全磁盘访问）、#886（剪贴板 iCloud 同步）。
