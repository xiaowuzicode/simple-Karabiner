# Simple Karabiner — DJI Mic Mini 语音编程助手

用 DJI Mic Mini 的硬件按钮实现三段式语音编程工作流：**一键听写、一键确认、一键发送**。

适用于 Claude Code、Cursor、VS Code、iTerm2、微信、飞书等任何接受文字输入的 macOS 应用。

## 工作流程

```
第 1 次按  →  启动语音听写（开始说话）
第 2 次按  →  停止听写 + 提示音 + 进入就绪状态
第 3 次按  →  发送 Enter 到当前 App（触发 AI 响应 / 发送消息）
4 秒不按   →  静默重置，无副作用
```

这个三段式设计让你可以：
- 用语音输入代码指令或对话内容
- 听完后有时间检查转写结果
- 确认无误再发送，不怕误触

## 前置条件

| 需求 | 说明 |
|------|------|
| macOS | 已在 macOS Sequoia 上验证 |
| [Karabiner-Elements](https://karabiner-elements.pqrs.org/) | `brew install --cask karabiner-elements` |
| DJI Mic Mini | USB 接收器连接；vendor_id: 11427, product_id: 16401 |
| 语音转文字工具 | 任意支持 right_command 触发的语音输入工具 |

## 安装

### 1. 安装 Karabiner-Elements

```bash
brew install --cask karabiner-elements
```

打开后按提示授权：
- 系统设置 → 隐私与安全 → 输入监控 → 勾选 Karabiner 相关项
- 系统设置 → 通用 → 登录项与扩展 → 驱动程序扩展 → 开启

### 2. 复制脚本

```bash
mkdir -p ~/.config/karabiner/scripts
cp scripts/dictation-enter.sh ~/.config/karabiner/scripts/
chmod +x ~/.config/karabiner/scripts/dictation-enter.sh
```

### 3. 导入 Karabiner 规则

将 `karabiner/dji-mic-mini.json` 中的规则合并到你的 Karabiner 配置中。

最简单的方式 — 直接替换配置（如果你没有其他 Karabiner 规则）：

```bash
cp karabiner/karabiner-example.json ~/.config/karabiner/karabiner.json
```

或者手动将 `dji-mic-mini.json` 中的 rules 和 devices 部分合并到你现有的 `~/.config/karabiner/karabiner.json`。

### 4. 插上 DJI Mic Mini USB 接收器

确保使用 USB 接收器（不是蓝牙），Karabiner 需要 HID 设备协议。

## 文件结构

```
simple-Karabiner/
├── README.md                          # 本文档
├── scripts/
│   └── dictation-enter.sh            # 主脚本（状态管理 + 发送 Enter）
└── karabiner/
    ├── dji-mic-mini.json             # Karabiner 规则模板
    └── karabiner-example.json        # 完整配置示例（可直接使用）
```

## 自定义

### 修改确认超时时间

编辑 `scripts/dictation-enter.sh`，修改 `CONFIRM_WINDOW` 的值（默认 4 秒）：

```bash
CONFIRM_WINDOW="${CONFIRM_WINDOW:-4}"
```

### 修改触发键

默认使用 `right_command` 触发语音工具。如果你的语音工具使用其他快捷键，修改 `karabiner/dji-mic-mini.json` 中的 `"key_code": "right_command"` 为对应的键。

### 用其他硬件设备

查你设备的 vendor_id 和 product_id：

```bash
'/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli' --list-connected-devices
```

然后更新 `dji-mic-mini.json` 中所有 `vendor_id` 和 `product_id` 的值。

## 问题排查

查看调试日志：

```bash
cat /tmp/dji-dictation/debug.log
```

| 现象 | 可能原因 | 解决方法 |
|------|---------|---------|
| 按钮没反应 | Karabiner 缺少输入监控权限 | 系统设置 → 隐私与安全 → 输入监控 |
| 按钮只调音量 | DJI 设备未被 Karabiner 抓取 | 检查 karabiner.json devices 中 `ignore: false` |
| 听写正常但 Enter 没发出去 | 缺少辅助功能权限 | 系统设置 → 隐私与安全 → 辅助功能，授权终端 App |
| 驱动扩展未启用 | VirtualHIDDevice 未批准 | 系统设置 → 通用 → 登录项与扩展 → 驱动程序扩展 |

## 权限清单

系统设置 → 隐私与安全：

- **输入监控**：Karabiner-Elements、karabiner_grabber
- **辅助功能**：Karabiner-Elements、你的终端 App（iTerm2 / Terminal.app）

## 致谢

基于 [dji-mic-dictation](https://github.com/Johnixr/dji-mic-dictation) 项目简化而来，去除了 Typeless 依赖，适配自定义语音转文字工具。

## 许可

MIT
