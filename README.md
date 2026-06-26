# FLOW / 流动

AI 驱动聊天 App 的 **iOS 前端原型**（SwiftUI），1:1 还原设计稿的羊皮纸 + 手绘速写风格。
本阶段**仅前端 UI + Mock 数据**，不含任何网络 / 后端 / AI。

## 已实现页面

- **聊天 (Chats)** — `我的聊天` 列表 + 写信入口，点进 **聊天详情**（消息气泡、图片消息、语音波形、输入栏）
- **群组 (Groups)** — 群组列表 + **创建新群组**（选成员、起名）
- **发现 (Discover)** — `精英服务` 卡片（全球人脉圈 / 专家咨询小组 + JOIN）
- **设置 (Settings)** — 开关 / 滑块 / 配色，含 **中英语言切换**
- **我 (Profile)** — 联系人资料卡（陈亚历山大）
- 自定义底部 TabBar + 设计稿底部状态条；中英双语实时切换

## 运行（需 macOS + Xcode 15+）

本工程用 [XcodeGen](https://github.com/yonyz/XcodeGen) 管理工程文件：

```bash
brew install xcodegen      # 若未安装
xcodegen generate          # 生成 FLOW.xcodeproj
open FLOW.xcodeproj
```

在 Xcode 选 **iPhone 15 Pro** 模拟器，`Cmd+R` 运行。

> 若不想用 XcodeGen：在 Xcode 新建一个 iOS App 工程，把 `FlowApp/Sources` 拖入源码、
> `FlowApp/Resources/Assets.xcassets` 设为资源目录即可。

## 结构

```
FlowApp/
  Sources/
    App/            入口 + RootView（TabBar / 状态条）
    DesignSystem/   FlowTheme（配色/字体）、组件、纸纹背景
    Features/       Chats / Groups / Discover / Settings / Profile
    Models/         数据模型 + MockData
    Localization/   中英双语
  Resources/
    Assets.xcassets 手绘背景/插画（从设计系统图裁切）
```

## 配色（取自设计系统图）

`#2F3E46` 墨岩 · `#4A7C81` 主青 · `#84A98C` 苔绿 · `#F5F1EA` 羊皮纸 · `#E6E2D8` 米褐 · `#8C8F93` 灰

## 后续（不在本阶段）

Matrix 后端联网、真实消息收发、账号/加密/推送、端侧本地 AI 层、安卓版。
