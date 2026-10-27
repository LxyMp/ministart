# "分组排序"弹窗（拖拽排序，持久化）

## 交互
- "新增分组"按钮**右侧**新增"分组排序"按钮（`arrow.up.arrow.down` 图标）。
- 点击弹出一个**独立小窗口**（复用 `AppWindowController`，标题"分组排序"，与设置窗同风格）：列出全部分组（**不含"默认"**——默认组恒在第一，不参与排序），每行 📁 + 组名；通过**拖拽行**调整顺序，改动即时保存。
- 关闭弹窗后设置页分组按新顺序渲染。

## 持久化（顺序需要跨会话保留）
新建 `quicklink_groups(name TEXT PRIMARY KEY NOT NULL, position INTEGER NOT NULL)` 表（沿用现有 schema/一次性 `CREATE TABLE IF NOT EXISTS` 模式，无需 ALTER）。

### `QuicklinkStore.swift`
- schema 加该表。
- 新增：
  - `func groupOrder() -> [String]`（按 position 读，包含当前没有链接的组——**同时解决"空组重启后消失"**：组成为一等实体）
  - `func setGroupOrder(_ names: [String])`（事务内整表重写 position；对未知组名忽略）
  - `addGroup`（新组落库，position = max+1）
  - 删除/重命名组时同步清理/改名 order 表
- `sections` 派生改为：默认 → `store.groupOrder()` 中顺序；组内仍 `precedes`。
- `pendingGroups` 会话态**整体删除**（由 order 表取代），相关代码（commitNewGroup 的 pending 分支、rename/remove 里的 pending 清理）同步简化。
- 现有 `groups()`/`renameGroup`/`removeGroup` 改为与 order 表协同（rename 时 UPDATE order 表同名行；remove 时 DELETE 行）。

## 弹窗视图 `QuicklinkGroupOrderView.swift`（新文件，Settings/）
- `List` + `ForEach` + `.onMove`（SwiftUI 原生拖拽排序，无需手写 drag&drop），`ToolbarItem(placement: .cancellationAction)` 关闭按钮。
- 行：📁 + 组名。空列表（无分组）显示提示文案。
- 变更直接 `store.setGroupOrder`（`@Observable store` 驱动设置页即时刷新）。

## 弹窗呈现
设置页 `@State private var showsGroupOrder = false`；"分组排序"按钮 toggle；`.sheet(isPresented:)` 挂 `QuicklinkGroupOrderView`。设置窗无 sheet 先例，但 sheet 是标准 macOS 模态、不违反"禁用 NSAlert/系统 popover"铁律（那是关于提问/报告对话框的）。

## 编辑器 Group 菜单
`coordinator.groups` 改读 `store.groupOrder()`（有成员或 order 表里的组都会出现）。

## 测试（quicklink-test）
- 新增 `groupOrder`：初始空、addGroup 追加到尾、setGroupOrder 重排后 groupOrder() 顺序一致、rename 跟随、remove 清行、未知组名 setGroupOrder 忽略。
- `groupManagement` 相应更新（rename/remove 现在同步 order 表）。

## 文案
"Group Order"（弹窗标题/按钮）、"No groups yet"（空态）、"Drag to reorder"（提示）。sync-strings 后补中文：分组排序 / 暂无分组 / 拖拽调整顺序。

## 执行顺序
Store（表+方法+rename/remove 协同）→ 弹窗视图 → 设置页按钮/sheet/sections 改造 → 编辑器菜单读新序 → 测试 → 文案翻译 → 文档补句 → 全量验证 → 打包安装（不提交 git）。