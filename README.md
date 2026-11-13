# Device Inspector

原生 SwiftUI iOS 工程，最低部署版本 iOS 17.0。

## 打开方式
1. 使用 Mac 上的 Xcode 打开 `DeviceInspector.xcodeproj`。
2. 在 Signing & Capabilities 中选择你的开发团队（真机安装需要签名）。
3. 选择 iPhone/iPad 目标设备并运行。

## 已实现
- 设备型号标识、系统版本、内核版本、CPU 架构/逻辑核心数、Metal GPU 名称、屏幕分辨率/刷新率、物理内存、可见存储容量。
- 电量/充电状态、生物识别能力、相机/麦克风授权状态、运动传感器能力、气压计与定位服务状态。
- 网络接口状态、HTTPS 往返延迟测试。
- CPU 本地数学微基准、系统热状态、低电量模式。
- 实时加速度/角速度/气压采样。
- 检测结果汇总与 PDF 分享。

## iOS 平台限制
普通 App 无法枚举所有已安装 App、读取电池健康度/温度/循环次数、全局 RAM 使用量、精确蜂窝信号、环境光读数、开发者模式状态、其他 App 帧率或进行底层硬件自检。对应项目明确标注系统限制，不会伪造数据。
评分只按可读取项目的状态比例计算，不是 Apple 官方诊断，也不代表硬件寿命或维修结论。

## 注意
当前版本不请求相机、麦克风或定位权限；仅显示权限状态和设备能力。传感器页面需用户主动开始采样。

## GitHub Actions 云端编译
仓库包含 `.github/workflows/ios-build.yml`。推送到 GitHub 后可在 Actions 页面手动运行，当前工作流用于 iOS Simulator 无签名编译验证，不会生成可直接安装的真机 IPA。真机 IPA 仍需有效签名配置。

## 扩展：Mach 内存诊断
参考研究了 `matthewmyrick/ios-monitor` 对 iOS 沙盒边界的说明，并自行实现了 `MemoryDiagnostics.swift`：
- 使用 Mach VM 页计数展示设备级 wired / active / inactive / compressed / free 汇总。
- 使用 `TASK_VM_INFO` 读取本 App 自身 footprint。
- 不枚举其他 App 进程，也不读取其他 App 的内存。

上游参考项目： https://github.com/matthewmyrick/ios-monitor
该上游仓库 README 未声明明确开源许可证，因此本工程没有复制其源代码；这里只参考公开技术说明并独立实现对应功能。Mach 统计接口的可用性及 App Store 审核结果仍需在目标 iOS/Xcode 版本和真机上验证。

## 本次扩展
- Metal GPU 向量计算微基准。
- 临时目录 8 MiB 存储读写测试，自动删除测试文件。
- 用户主动触发的 Cloudflare 网络下载/上传测速（约 1.25 MB 流量）。
- Face ID / Touch ID / Optic ID 能力区分、音频输出路由、屏幕亮度、系统区域/时区、运行时长。
- 测试均非 Apple 官方诊断，不用于推断硬件损坏；网络测速会连接第三方测速服务。
