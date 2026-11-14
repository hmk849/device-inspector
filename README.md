# Device Inspector

原生 Swift + SwiftUI 的 iOS 设备检测工具。仅使用 Apple 公开 API。

## 构建
1. 用 **Xcode 16 或更新版本**（推荐 Xcode 26，可启用 Liquid Glass）打开 `DeviceInspector.xcodeproj`
2. Target → Signing & Capabilities 选择你的 Team，并把 Bundle ID 改成自己的
3. 连接真机运行（部分传感器、摄像头、电池、触感在模拟器上不可用）
最低系统 iOS 17.0。

## Liquid Glass
用 Xcode 26 SDK 编译时，在 iOS 26 上自动使用 `glassEffect`；更低系统或旧 Xcode 回退到 `.ultraThinMaterial`。

## 数据标识
- 绿色：真实检测
- 橙色：估算/推断（型号查表、VPN 启发式、基于参考值的评分、HTTP 往返延迟）
- 灰色：系统限制，无法读取（电池健康度/循环次数/温度、芯片型号、GPU 核心数、SSID、DNS、已安装 App、开发者模式、光线传感器、CPU 频率）

## 网络测试
延迟/速度测试会访问 apple.com 与 speed.cloudflare.com，只传输测试数据，不含个人信息。

## 目录
- Core.swift 公共模型与 UI 组件
- Sys.swift sysctl/mach 辅助 + 基准测试实现
- Info.swift 各项信息采集
- Managers.swift 传感器、定位、相机、音频、网络、健康检测、PDF
- Home.swift / Pages.swift / SensorPages.swift / PerfPages.swift / ReportPage.swift 界面

## 新增（第二版）
- 功率与温度监测：用电量变化速率 × 你填写的电池容量推算瓦数（估算）。iOS 公开 API 不提供电流/电压/摄氏温度。
- DNS 服务器：通过 resolv（libresolv，公开 C 接口，需 Supporting/Bridging-Header.h）读取。
- Wi-Fi 名称：需要 Access WiFi Information 能力。启用方法：把 Supporting/DeviceInspector.entitlements.optional 改名为 DeviceInspector.entitlements，
  在 Build Settings 里设置 CODE_SIGN_ENTITLEMENTS = Supporting/DeviceInspector.entitlements（付费开发者账号才可用）。
- 已安装 App：只探测预设的 30 个 URL Scheme（iOS 限制，最多 50 个）。
- 电池健康度/循环次数：手动录入（来自「设置 → 电池」）。
- 芯片型号：按型号标识符查表（估算）。
- 仍无法读取：电池温度、电流/电压、GPU 核心数、CPU 频率、开发者模式、光线传感器（均无公开 API）。
