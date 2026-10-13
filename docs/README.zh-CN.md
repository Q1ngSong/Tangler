<p align="center">
  <img src="assets/banner.svg" alt="Tangler — Your windows. In place." width="100%">
</p>

<p align="center">
  <a href="../LICENSE"><img src="assets/badge-license.svg" alt="License: PolyForm Noncommercial" height="26"></a>
  <a href="#从源码构建"><img src="assets/badge-macos.svg" alt="macOS 26 or later" height="26"></a>
  <a href="#从源码构建"><img src="assets/badge-swift.svg" alt="Swift 6.2 or later" height="26"></a>
</p>

<p align="center"><a href="../README.md">English</a> | 简体中文</p>

<p align="center">原生 macOS 窗口管理器，支持键盘布局、跨应用标签组和保存工作空间。<br>使用 Swift、AppKit 与 SwiftUI，提供液态玻璃和经典两种外观。</p>

<p align="center">
  <a href="https://q1ngsong.github.io/Tangler/"><img src="assets/badge-website.svg" alt="Website" height="26"></a>
  <a href="https://github.com/Q1ngSong/Tangler/releases/latest"><img src="assets/badge-download.svg" alt="Download" height="26"></a>
  <a href="https://github.com/Q1ngSong/Tangler/releases"><img src="assets/badge-releases.svg" alt="All releases" height="26"></a>
  <a href="#快速开始"><img src="assets/badge-quick-start.svg" alt="Quick start" height="26"></a>
  <a href="COMMANDS.md"><img src="assets/badge-commands.svg" alt="Command reference" height="26"></a>
</p>

## 快速开始

1. 将 `Tangler.app` 放入“应用程序”并打开。
2. 在**设置 → 诊断 → 权限**中开启**辅助功能**，用于控制窗口与全局输入；开启**屏幕录制**以显示窗口缩略图。首次缺少辅助功能权限时，Tangler 会自动打开诊断页面。
3. 聚焦一个窗口，按住**右 Command**，再按 **←**，将窗口放到左半屏。输入按键序列时保持按住总入口键。
4. 在**设置 → 快捷键**中选择总入口键，搜索或筛选命令，录制自定义快捷键。点击**录制**预览输入，**保存**后生效；未保存时按 **Esc** 取消。

下文使用默认按键，你保存的快捷键优先。**⌘ Tab** 等独立快捷键不需要先按总入口键。

在**设置 → 通用 → 语言**中选择**跟随系统**、**简体中文**或 **English**，更改立即生效。命令搜索支持中英文名称，也支持拼音。

## 用键盘摆放窗口

![按住总入口键并按左方向键，窗口移动到桌面左半屏的动画示意。](assets/layout-demo.svg)

*动画是操作示意，不是实际录屏。窗口内容与材质取决于应用及系统外观；开启“减少动态效果”时显示静态画面。*

拖动窗口吸附到区域，使用 Option 网格，或直接输入布局命令。还可以在显示器和桌面之间移动窗口。

| 按住总入口键后输入 | 功能 |
| --- | --- |
| **← / → / ↑ / ↓** | 将当前窗口放到对应半屏 |
| **U / I / J / K** | 放到对应角落 |
| **F** | 最大化 |
| **Z** | 恢复之前的位置 |
| **Space** | 打开命令搜索 |

完整按键见[命令参考](COMMANDS.md)；系统集成和限制见 [macOS 行为说明](COMMANDS.macos.md)。

## 把相关应用放进同一个标签组

![点击标签，标签组从浏览器窗口切换到笔记窗口的动画示意。](assets/tabs-demo.svg)

将同一区域的窗口组合为标签，点击标签就能置前对应窗口。窗口可以来自不同应用。

按住总入口键，依次输入 **T、T** 合并同一区域窗口，或 **T、A** 选择要加入的窗口。**[** 和 **]** 切换标签；**T、U** 解散标签组。在**设置 → 标签组**中调整标签栏高度和行为。

[查看所有标签组命令](COMMANDS.md) →

## 回到保存的工作空间

![打开保存的工作空间，恢复窗口布局和标签组的动画示意。](assets/workspace-demo.svg)

保存桌面的窗口布局和标签组，随后重新打开或恢复。在**设置 → 工作空间**中选中一个工作空间，点击布局预览中的窗口或标签，即可指定打开后需要聚焦的窗口。

按住总入口键，依次输入 **W、S** 保存检查点，**W、R** 恢复检查点，**W、数字** 打开对应工作空间。齿轮按钮中设置自动保存；垃圾桶按钮切换到已删除的工作空间。

目前一个工作空间对应单个显示器上的一个桌面，保存应用窗口和 Tangler 标签组，不记录浏览器内部标签页。恢复效果取决于相关应用。

[学习工作空间命令](COMMANDS.md) →

## 找到需要的窗口

- **窗口切换器：** **⌘ Tab** 切换所有应用的窗口，**⌘ `** 切换同一应用的窗口。
- **Dock 预览：** 从应用的 Dock 图标查看窗口缩略图。
- **命令搜索：** 按住总入口键并按 **Space**，按名称寻找命令。

## 使用指南

| 文档 | 内容 |
| --- | --- |
| [命令参考（英文）](COMMANDS.md) | 全部命令、默认入口序列、独立快捷键和命令作用对象；学习键盘操作从这里开始。 |
| [macOS 行为说明（英文）](COMMANDS.macos.md) | 布局、桌面、窗口切换和 Dock 预览与系统功能的关系，以及已知限制。 |

## 从源码构建

需要 macOS 26+、**Swift 6.2+** 及对应 macOS SDK。在仓库根目录运行：

```sh
scripts/build-app.sh          # 构建到 build/Tangler.app
scripts/install-app.sh        # 构建、替换 /Applications/Tangler.app 并启动
```

未配置本机签名身份时使用临时签名，无需 Apple 开发者账号。当前构建未经过 Apple 公证；如果 macOS 阻止打开下载的应用，请先确认来源，再按 [Apple 的说明](https://support.apple.com/en-us/102445)操作。

安装包和更新说明见 [GitHub Releases](https://github.com/Q1ngSong/Tangler/releases)。在**设置 → 诊断 → 软件更新**中检查新版本，并选择手动检查、自动检查并提醒，或自动下载与安装。默认每 6 小时检查一次，由你确认安装；开启自动安装后，通常在退出时完成。应用内更新使用 Sparkle，需要配置生产更新公钥并发布更新源。


## 许可证

[PolyForm Noncommercial 1.0.0](../LICENSE)，允许许可证范围内的非商业使用、修改和再分发。**商业使用不获授权，包括营利性公司的内部业务使用。** 项目以非商业许可证提供源码。

完整条款见 [LICENSE](../LICENSE)，第三方许可见 [NOTICE](../NOTICE)。
