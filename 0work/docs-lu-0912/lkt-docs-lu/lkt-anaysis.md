# LiveKit Android SDK 源码设计分析

> 本文面向有 C/C++ 经验、但对 Kotlin/Java/Android 不太熟悉的读者，对 LiveKit Android SDK（`client-sdk-android-main`）进行专业详要的架构与实现梳理。涵盖入口、架构、文件作用、数据流图、分层控制流图、模块交互、类图、设计方式，以及完整业务流程（音频/视频）的模块间数据流与控制流，最后总结工程特点并给出 Android SDK 的通用分析思路。

> 代码引用格式为 `相对路径:行号`，可在支持的工具中点击跳转。

---

# 目录

## 一级目录

- 第一部分：架构与业务流（第 0-15 章）
- 第二部分：网络交互、抽象讲解、图集、QoS 优化（第 16-22 章）

## 一级与二级目录

### 第一部分：架构与业务流（第 0-15 章）

- 第 0 章 阅读指南与前置知识（给 C/C++ 背景读者）
  - 0.1 Kotlin 速查
  - 0.2 Java 速查
  - 0.3 Android 速查
  - 0.4 Kotlin ↔ Java 互操作
  - 0.5 Kotlin/Java ↔ C++ 交互（WebRTC native 边界）
- 第 1 章 总览：工程定位、模块组成、入口
  - 1.1 工程定位
  - 1.2 顶层 Gradle 模块组成
  - 1.3 入口与一句话架构
  - 1.4 关键组件速览
- 第 2 章 分层架构与文件组织
  - 2.1 四层架构
  - 2.2 目录与架构映射
  - 2.3 依赖方向
  - 2.4 类图（核心对象关系）
- 第 3 章 依赖注入（Dagger）与对象图
  - 3.1 Dagger 基础概念（给 C++ 读者）
  - 3.2 LiveKitComponent 与模块
  - 3.3 关键对象提供链路
  - 3.4 LiveKitOverrides：扩展点
- 第 4 章 连接生命周期与状态机
  - 4.1 两套状态
  - 4.2 connect 流程时序
  - 4.3 prepareConnection（预连接优化）
  - 4.4 重连机制
  - 4.5 断连与清理
- 第 5 章 信令层 SignalClient
  - 5.1 角色
  - 5.2 连接与握手
  - 5.3 请求/响应队列
  - 5.4 ping/pong 心跳
  - 5.5 SignalResponse 分发
  - 5.6 发送 API
- 第 6 章 媒体传输层 RTCEngine + PeerConnectionTransport
  - 6.1 双 PeerConnection 模型
  - 6.2 PeerConnectionTransport 封装
  - 6.3 SDP 协商流程
  - 6.4 SDP munge（修改 SDP）
  - 6.5 ICE / Trickle
  - 6.6 DataChannel 与可靠消息
  - 6.7 RTC 线程模型
- 第 7 章 参与者模型 Participant
  - 7.1 继承体系
  - 7.2 Participant 基类
  - 7.3 LocalParticipant
  - 7.4 RemoteParticipant
  - 7.5 权限模型
- 第 8 章 轨道模型 Track 体系
  - 8.1 Track 继承体系
  - 8.2 TrackPublication 体系
  - 8.3 本地视频轨道链路
  - 8.4 本地音频轨道链路
  - 8.5 Simulcast / SVC / Dynacast / 备用编解码器
  - 8.6 远端轨道与渲染
- 第 9 章 完整业务流程：音频发布与订阅
  - 9.1 音频发布数据流（本地 → 服务器）
  - 9.2 音频发布控制流
  - 9.3 音频订阅数据流（服务器 → 本地播放）
  - 9.4 音频订阅控制流
  - 9.5 模块/文件夹间依赖关系（音频）
  - 9.6 关键时序：音频发布到首帧上行
- 第 10 章 完整业务流程：视频发布与订阅
  - 10.1 视频发布数据流（本地 → 服务器）
  - 10.2 视频发布控制流
  - 10.3 视频订阅数据流（服务器 → 本地渲染）
  - 10.4 视频订阅控制流
  - 10.5 adaptiveStream / dynacast 控制回路
  - 10.6 模块/文件夹间依赖关系（视频）
  - 10.7 关键时序：视频发布到首帧上行
- 第 11 章 数据通道与数据流（DataChannel / DataStream / RPC）
  - 11.1 DataChannel 基础
  - 11.2 用户数据 publish/receive
  - 11.3 DataStream（文本/字节流）
  - 11.4 RPC 机制
- 第 12 章 事件体系
  - 12.1 BroadcastEventBus
  - 12.2 事件类型层次
  - 12.3 事件传递路径
  - 12.4 @FlowObservable 机制
- 第 13 章 端到端加密 E2EE
  - 13.1 概述
  - 13.2 E2EEManager
  - 13.3 KeyProvider
  - 13.4 集成点
- 第 14 章 音频设备与音频处理子系统
  - 14.1 AudioHandler：音频生命周期入口
  - 14.2 AudioProcessingController：采集/渲染前后处理
  - 14.3 AudioRecordSamplesDispatcher：原始 PCM 分发
  - 14.4 CommunicationWorkaround：通信模式保活
  - 14.5 AudioRecordPrewarmer：采集预热
  - 14.6 PreconnectAudioBuffer：预连接音频缓冲
  - 14.7 音频子系统类图
  - 14.8 音频子系统与 Room/Track 的集成
- 第 15 章 工程特点总结与 Android SDK 分析方法论
  - 15.1 工程特点
  - 15.2 类比 C++ 的整体视角
  - 15.3 通用的 Android SDK 分析思路与方法
  - 15.4 一句话总结

### 第二部分：网络交互、抽象讲解、图集、QoS 优化（第 16-22 章）

- 第 16 章 网络交互深入：信令、媒体与 WebRTC 内部
  - 16.1 两条网络通道总览
  - 16.2 信令交互完整流程（展开）
  - 16.3 媒体流交互完整流程（展开）
  - 16.4 内部 WebRTC 的作用（org.webrtc / libwebrtc）
  - 16.5 一个完整业务的端到端完整流程
- 第 17 章 Kotlin/Java 高级抽象给 C++ 读者（举例展开）
  - 17.1 依赖注入（DI）：从 C++ 手写工厂到 Dagger
  - 17.2 委托（Delegate / by）：组合的语法糖
  - 17.3 注入（Inject）的三种形态
  - 17.4 协程与 Flow 的抽象
  - 17.5 密封类、data class、object、扩展函数
  - 17.6 注解（Annotation）与编译期生成
- 第 18 章 图集：分层图、类图、交互图
  - 18.1 Android 平台分层图（从底到顶）
  - 18.2 SDK 四层架构图（细化，带文件名）
  - 18.3 信令交互分层图
  - 18.4 媒体交互分层图（视频上行）
  - 18.5 加密分层图
  - 18.6 核心类图（全景）
  - 18.7 Track 继承类图
  - 18.8 事件类图
  - 18.9 DI 对象图（Dagger）
- 第 19 章 工程设计评价：特点、优劣
  - 19.1 优点
  - 19.2 缺点 / 局限
  - 19.3 适用场景与不适用场景
  - 19.4 与其他方案对比
  - 19.5 一句话评价
- 第 20 章 工业级 QoS 音视频优化分析
  - 20.1 QoS 目标定义
  - 20.2 可调参数全景表（按层分类）
  - 20.3 SDK 层可调参数（给代码位置）
  - 20.4 必须改 WebRTC AAR / native 的参数
  - 20.5 具体优化方案（分音/视频）
  - 20.6 实验设计
  - 20.7 调参决策树
  - 20.8 风险与回滚
- 第 21 章 Kotlin/Java ↔ C++ 交互方式专题
  - 21.1 JNI 基础（给 C++ 读者）
  - 21.2 org.webrtc 的 JNI 模式
  - 21.3 一帧视频编码的完整跨语言调用栈
  - 21.4 线程跨越：native 线程回调 Java
  - 21.5 修改 native 行为的途径
- 第 22 章 总结与速查
  - 22.1 全文章节索引
  - 22.2 关键文件速查表
  - 22.3 关键参数速查表
  - 22.4 调试技巧

---

## 第 0 章 阅读指南与前置知识（给 C/C++ 背景读者）

本章把阅读本 SDK 所需的 Kotlin/Java/Android 关键概念，用 C/C++ 读者熟悉的视角快速建立起来，并讲清 Kotlin/Java 与 C++（native WebRTC）的交互边界。

### 0.1 Kotlin 速查

- **`val` / `var`**：`val` 是只读引用（类似 C++ 的 `const` 局部/成员，但对象本身可变），`var` 是可变引用。
- **`data class`**：自动生成 `equals/hashCode/toString/copy`，类似 C++ 中带运算符重载的 POD 结构体。如 `data class TrackBitrateInfo(val codec: String, val maxBitrate: Long)`。
- **`sealed class`**：受限继承体系（类似 C++ 的"已知子类集合"），编译器能做穷尽 `when` 检查。本 SDK 大量用于事件与错误类型，如 `sealed class RoomEvent`、`sealed class TrackException`。
- **`object`**：单例对象。`object LiveKit { ... }` 即进程级单例（类似 C++ 中 Meyers 单例）。
- **`companion object`**：类级单例，承载类似 Java `static` 的常量与工厂方法。
- **扩展函数/扩展属性**：在不继承的情况下给已有类加方法，本质是"第一个参数是接收者"的静态函数。如 `livekit-android-sdk/.../RTCEngine.kt:1539` 的 `fun LivekitRtc.ICEServer.toWebrtc()`。
- **`by` 委托**：把属性或接口的实现委托给另一个对象。本 SDK 最核心的 `flowDelegate` 即属性委托（见第 12 章）。
- **`suspend` 函数 / 协程（coroutine）**：可挂起的函数。类比 C++20 协程，但 Kotlin 协程有成熟的库支持。`suspend fun connect(...)` 可在内部 `await` 而不阻塞线程；`CoroutineScope` 是协程的"所有权范围"，`SupervisorJob` 是结构化并发的失败隔离单元（子协程异常不会取消兄弟）。
- **`Flow` / `StateFlow` / `SharedFlow`**：协程版的"可观察流"。`StateFlow` 持有最新值（类似 C++ 中带缓存的可订阅变量），`SharedFlow` 是广播流。`collect` 即订阅。
- **`@JvmInline value class`**：零分配的包装类型（编译期内联为底层类型），用于强类型 ID，如 `value class Sid(val sid: String)`。
- **`inline fun` + `contract`**：内联函数并声明调用契约，让编译器做更聪明的类型推断。如 `Track.kt:198` 的 `withRTCTrack`。

### 0.2 Java 速查

- **`interface`**：Java 接口，Kotlin 也用。本 SDK 中大量 `interface Factory { fun create(...): X }` 用于依赖注入工厂。
- **注解（annotation）**：`@Inject`、`@Singleton`、`@AssistedInject` 等是 Dagger 注解；`@JvmStatic` 让 Kotlin 的 `object` 成员对 Java 调用方表现为静态方法。
- **泛型**：与 C++ 模板不同，Java/Kotlin 泛型是运行期擦除的（erasure）。
- **`@Volatile`**：Kotlin 的 `@Volatile` 对应 Java 的 `volatile`，保证可见性但不保证复合原子性（与 C++ 的 `volatile` 语义不同，更接近 `std::atomic` 的"可见性"部分）。

### 0.3 Android 速查

- **`Context`**：Android 的"环境句柄"，能访问资源、启动服务、获取系统服务。`Application` 是整个进程的 Context，`Activity` 是单个界面。本 SDK 要求传 `appContext`，并警告若不是 `Application` 可能内存泄漏（`LiveKit.kt:87`）。
- **权限**：录音/相机需运行时权限 `RECORD_AUDIO` / `CAMERA`，SDK 在创建 track 时检查（`LocalVideoTrack.kt:478`、`LocalAudioTrack.kt:229`）。
- **`Handler` / `HandlerThread`**：Android 的线程消息队列。`HandlerThread` 是自带 Looper 的工作线程，`Handler` 向其投递任务。`AudioSwitchHandler` 用它保证 AudioSwitch 单线程访问（`AudioSwitchHandler.kt:218`）。
- **`SurfaceView` / `TextureView`**：两种渲染视图。SDK 提供 `SurfaceViewRenderer` / `TextureViewRenderer`，底层是 WebRTC 的 `SurfaceViewRenderer`，通过 EGL 上下文把解码后的视频帧绘制到 Surface。
- **`EglBase`**：WebRTC 对 OpenGL ES 上下文的封装，视频渲染与某些 GPU 编解码需要它。
- **`MediaProjection`**：屏幕录制权限与数据源，`LocalScreencastVideoTrack` 依赖它。
- **`AudioManager`**：音频焦点（audio focus）、音频模式（MODE_IN_COMMUNICATION）、路由（扬声器/听筒/蓝牙）。

### 0.4 Kotlin ↔ Java 互操作

本 SDK 是纯 Kotlin 写的，但对外暴露 Java 友好 API：
- `@JvmStatic`：`LiveKit.kt:40` 的 `var loggingLevel` 加了 `@JvmStatic`，Java 代码可 `LiveKit.setLoggingLevel(...)`。
- `@JvmInline value class`：对 Java 表现为普通类型。
- `null` 平台类型：Kotlin 的可空 `String?` 对 Java 是平台类型，SDK 用 `@Nullable`/`@NonNull` 注解约束。
- `kotlin.reflect`：运行期反射，`FlowDelegate.kt:48` 用 `KProperty0.delegate` 反射拿到属性背后的 `StateFlow`，这是 `@FlowObservable` 机制的关键（见第 12 章）。

### 0.5 Kotlin/Java ↔ C++ 交互（WebRTC native 边界）

这是 C++ 读者最该关注的部分：

- **WebRTC 是 C++ 原生库**：Google 的 libwebrtc 是 C++ 实现，Android 上以 `.so` 形式打包。`org.webrtc` 包是 Java 绑定层，通过 **JNI** 调用 native 代码。
- **`livekit.org.webrtc` 是 LiveKit 的二次封装**：本仓库 `livekit-android-sdk/src/main/java/livekit/org/webrtc/` 下有 `Camera1Helper`、`Camera2Helper` 等，是 LiveKit 对 Google `org.webrtc` 的补充与定制（注意包名是 `livekit.org.webrtc`，用 `livekit.` 前缀避免与官方包冲突）。
- **RTC 线程模型**：libwebrtc 内部有专用线程（信令线程、工作线程、网络线程）。**所有 WebRTC API 调用必须在同一线程**，否则行为未定义。本 SDK 用 `RTCThreadToken` + `executeBlockingOnRTCThread` / `launchBlockingOnRTCThread` 强制线程亲和性（见第 6 章）。这类似 C++ 中"锁住一个专用线程做所有操作"的模式，但用协程封装成"在协程里阻塞投递到 RTC 线程执行"。
- **对象生命周期**：native 对象需显式 `dispose()` 释放，不能依赖 GC（GC 时机不可控且可能不及时释放 native 资源）。`PeerConnectionFactoryManager.kt:33` 的 `dispose()` 甚至校验当前线程名必须是 RTC 线程，否则抛异常——这是 native 资源线程亲和性的强约束。
- **数据流向**：摄像头/麦克风 → Java 层 capturer → native 编码器 → native RTP 栈 → 网络；网络 → native RTP 栈 → native 解码器 → Java 层 sink → 渲染。Java 层主要做"编排"与"回调"，重活在 native。

> **给 C++ 读者的心智模型**：把 `org.webrtc.*` 想象成一组"带引用计数的 C++ 对象的 Java 句柄"，调用其方法等于跨 JNI 调 C++；`dispose()` 等于 `Release()`；`RTCThreadToken` 等于"必须持锁才能操作"的线程锁。

---

## 第 1 章 总览：工程定位、模块组成、入口

### 1.1 工程定位

LiveKit 是一个开源的实时音视频平台（SFU 架构），提供房间、参与者、轨道（track）的抽象。本仓库 `client-sdk-android-main` 是其 **Android 客户端 SDK**，让 Android 应用接入 LiveKit 房间，实现：

- 发布本地麦克风/摄像头/屏幕共享轨道
- 订阅远端参与者的音视频轨道并渲染
- 收发数据消息、数据流、RPC 调用
- 端到端加密（E2EE）
- 连接管理、重连、网络自适应

SDK 对外隐藏 WebRTC 的复杂性，对内通过 LiveKit 服务器做信令协调。

### 1.2 顶层 Gradle 模块组成

仓库根目录的 `settings.gradle` 定义了多个模块，核心是 `livekit-android-sdk`，其余是辅助：

| 模块 | 作用 |
|---|---|
| `livekit-android-sdk` | **核心 SDK**，本文分析对象，包根 `io.livekit.android` |
| `livekit-android-camerax` | CameraX 集成（可选的相机捕获实现） |
| `livekit-android-track-processors` | 视频帧处理器（如虚拟背景，基于 RTCVideoFrameProcessor） |
| `livekit-android-test` | 测试基础设施（mock、MockE2ETest 基类），是 SDK 的 friend 模块可访问 internal |
| `livekit-detekt-rules` / `livekit-lint` | 自定义静态检查规则 |
| `sample-app*` / `examples` | 示例应用 |
| `video-encode-decode-test` | 编解码测试 |
| `protocol` | protobuf 协议定义（生成 `livekit.LivekitModels` / `livekit.LivekitRtc`） |

### 1.3 入口与一句话架构

入口是 `LiveKit` 单例对象（`LiveKit.kt:34`）：

```kotlin
object LiveKit {
    fun create(appContext: Context, options: RoomOptions = RoomOptions(), overrides: LiveKitOverrides = LiveKitOverrides()): Room
}
```

`LiveKit.create()` 做三件事：构建 Dagger 依赖图 → 用工厂创建 `Room` → 应用 `RoomOptions`。

**一句话架构**：
> `Room` 是面向用户的门面（管理连接状态、参与者、轨道、事件），`RTCEngine` 是内部引擎（整合信令与媒体传输），`SignalClient` 负责 WebSocket 信令，`PeerConnectionTransport` 封装 WebRTC `PeerConnection`（媒体传输），`Participant`/`Track` 体系承载业务对象。

核心调用链（从用户视角）：

```
LiveKit.create() → Room
Room.connect(url, token) → RTCEngine.join() → SignalClient.join() (WebSocket)
                      → configure() 创建 publisher/subscriber PeerConnectionTransport
                      → negotiatePublisher() (SDP offer/answer)
                      → onJoinResponse() 回填 Room/LocalParticipant 状态
```

### 1.4 关键组件速览

| 组件 | 文件 | 职责 |
|---|---|---|
| `LiveKit` | `LiveKit.kt` | 进程级入口，创建 Room |
| `Room` | `room/Room.kt` | 主门面，连接/参与者/轨道/事件 |
| `RTCEngine` | `room/RTCEngine.kt` | 整合信令与 PeerConnection |
| `SignalClient` | `room/SignalClient.kt` | WebSocket 信令客户端 |
| `PeerConnectionTransport` | `room/PeerConnectionTransport.kt` | 单个 PeerConnection 封装 |
| `LocalParticipant` / `RemoteParticipant` | `room/participant/` | 参与者模型 |
| `LocalAudioTrack` / `LocalVideoTrack` / `RemoteAudioTrack` / `RemoteVideoTrack` | `room/track/` | 轨道模型 |
| `E2EEManager` | `e2ee/E2EEManager.kt` | 端到端加密 |
| `AudioSwitchHandler` | `audio/AudioSwitchHandler.kt` | 音频设备/焦点管理 |
| `FlowDelegate` | `util/FlowDelegate.kt` | `@FlowObservable` 响应式属性机制 |

---

## 第 2 章 分层架构与文件组织

### 2.1 四层架构

本 SDK 自上而下可分为四层，依赖严格单向向下：

```
┌─────────────────────────────────────────────────────────────┐
│  ① API 层（用户门面）                                         │
│  LiveKit, Room, RoomOptions, ConnectOptions, RoomEvent       │
│  用户只与这一层打交道                                          │
├─────────────────────────────────────────────────────────────┤
│  ② Room 编排层（业务对象与状态机）                              │
│  RTCEngine, Participant(Local/Remote), Track(Local/Remote),  │
│  TrackPublication, DefaultsManager, E2EEManager, events/      │
├─────────────────────────────────────────────────────────────┤
│  ③ 传输层（信令 + 媒体协商）                                   │
│  SignalClient(WebSocket), PeerConnectionTransport,           │
│  Publisher/SubscriberTransportObserver, DataChannelManager    │
├─────────────────────────────────────────────────────────────┤
│  ④ WebRTC 原生层（JNI → C++ libwebrtc）                        │
│  org.webrtc.* / livekit.org.webrtc.*, PeerConnectionFactory,  │
│  EglBase, AudioDeviceModule, RTC 线程                         │
└─────────────────────────────────────────────────────────────┘
```

- **①→②**：`Room` 把用户调用转译为对 `RTCEngine`/`LocalParticipant` 的内部调用，并把内部事件包装成 `RoomEvent` 暴露。
- **②→③**：`RTCEngine` 编排 `SignalClient`（信令）与两个 `PeerConnectionTransport`（publisher/subscriber）。
- **③→④**：`PeerConnectionTransport` 持有一个 native `PeerConnection`，所有调用经 `RTCThreadToken` 投递到 RTC 线程执行。

### 2.2 目录与架构映射

`livekit-android-sdk/src/main/java/io/livekit/android/` 下的目录与层、职责的映射：

| 目录 | 层 | 职责 |
|---|---|---|
| `annotations/` | ① | API 稳定性标注（`@Beta`）、WebRTC 敏感标注 |
| `audio/` | ②/④ | 音频设备管理（`AudioHandler`/`AudioSwitchHandler`）、音频处理、预连接缓冲、通信模式 workaround |
| `coroutines/` | 工具 | 协程工具（`FlowExt`、`ReentrantMutex`） |
| `dagger/` | 横切 | 依赖注入模块与组件 |
| `e2ee/` | ② | 端到端加密（`E2EEManager`、`KeyProvider`、`DataPacketCryptorManager`） |
| `events/` | ② | 事件总线与事件类型（`RoomEvent`/`ParticipantEvent`/`TrackEvent`） |
| `memory/` | 横切 | 资源生命周期（`CloseableManager`） |
| `renderer/` | ① | 视频渲染视图（`SurfaceViewRenderer`/`TextureViewRenderer`） |
| `room/` | ②/③ | 核心：`Room`、`RTCEngine`、`SignalClient`、`PeerConnectionTransport`、`participant/`、`track/`、`network/`、`rpc/`、`datastream/`、`metrics/`、`provisions/`、`util/`、`types/` |
| `rpc/` | ② | RPC 错误类型 |
| `stats/` | 横切 | 客户端/网络统计 |
| `token/` | ① | 鉴权 token 来源（`TokenSource` 体系） |
| `util/` | 横切 | 通用工具（`FlowDelegate`、`LKLog`、`Either`、`MutexEx`、`TTLMap` 等） |
| `webrtc/` | ④ | WebRTC 扩展与定制（编解码器工厂、SDP 工具、DataChannel 管理、RTC 线程工具） |

`room/` 子目录进一步细分：

| 子目录 | 职责 |
|---|---|
| `room/participant/` | `Participant` 基类与 `LocalParticipant`/`RemoteParticipant` |
| `room/track/` | `Track` 体系与各 Local/Remote 音视频轨道、`TrackPublication` |
| `room/track/video/` | 视频捕获/处理辅助（capturer、VideoProcessor、可见性、可伸缩性模式） |
| `room/track/screencapture/` | 屏幕共享轨道与前台服务 |
| `room/network/` | 重连策略、网络回调 |
| `room/rpc/` | 房间级 RPC 管理（client/server manager） |
| `room/datastream/` | 数据流（incoming/outgoing，文本/字节） |
| `room/metrics/` | RTC 指标采集 |
| `room/provisions/` | 内部对象持有（`LKObjects`） |
| `room/util/` | 房间内部工具（SDP observer、编码工具、约束键） |
| `room/types/` | 共享类型（Agent 类型、转录段） |

### 2.3 依赖方向

依赖严格单向向下，横切层（dagger/memory/util/stats）被各层共用。`Room` 不直接持有 `PeerConnection`，而是通过 `RTCEngine` → `PeerConnectionTransport` 间接操作，保证上层不被 WebRTC 细节污染。

### 2.4 类图（核心对象关系）

```
                    ┌──────────┐  creates   ┌──────────────┐
                    │ LiveKit  │──────────▶│     Room     │
                    └──────────┘           └──────┬───────┘
                                                  │ owns/listens
                              ┌───────────────────┼────────────────────┐
                              ▼                   ▼                    ▼
                       ┌─────────────┐    ┌────────────────┐   ┌──────────────────┐
                       │  RTCEngine  │    │LocalParticipant│   │RemoteParticipant │
                       │ (Listener) │    └───────┬────────┘   └────────┬─────────┘
                       └──────┬──────┘            │ owns                │ owns
              ┌──────────────┼───────────┐       ▼                     ▼
              ▼              ▼           ▼  ┌─────────────┐    ┌─────────────────┐
       ┌────────────┐  ┌───────────┐  ┌────┴──────┐ │LocalTrackPub│    │RemoteTrackPub│
       │SignalClient│  │Publisher   │  │Subscriber │ │ + LocalTrack│    │ + RemoteTrack │
       │ (WebSocket)│  │Transport   │  │Transport  │ └─────────────┘    └───────────────┘
       └────────────┘  │(PeerConn)  │  │(PeerConn) │
                       └─────┬───────┘  └─────┬─────┘
                             │                │
                             ▼                ▼
                      ┌──────────────────────────────┐
                      │  PeerConnectionFactory (native)│
                      │  + EglBase + AudioDeviceModule │
                      └──────────────────────────────┘
```

`Room` 同时实现 `RTCEngine.Listener`、`ParticipantListener`、`RpcManager`，是多方回调的汇聚点（`Room.kt:156`）。

---

## 第 3 章 依赖注入（Dagger）与对象图

### 3.1 Dagger 基础概念（给 C++ 读者）

Dagger 是编译期依赖注入框架。C++ 读者可这样类比：
- **`@Module`**：一个"工厂集合"类，里面的 `@Provides` 方法是"构造函数"。
- **`@Inject`（构造器）**：告诉 Dagger 这个类可以用构造器直接创建，Dagger 会自动收集它的依赖。
- **`@AssistedInject`（构造器）**：半自动构造——部分参数由 DI 提供，部分参数由调用方在运行时传入（`@Assisted`）。配合 `@AssistedFactory` 接口生成工厂。类比 C++ 中"工厂方法接受运行时参数 + 其余依赖从容器取"。
- **`@Component`**：依赖图的入口，Dagger 为其生成实现类（`DaggerLiveKitComponent`）。`@Singleton` 控制作用域。
- **`@Named("xxx")`**：限定符，区分同一类型的不同绑定（如多个 `CoroutineDispatcher`）。

### 3.2 LiveKitComponent 与模块

`LiveKitComponent`（`dagger/LiveKitComponent.kt:32`）是顶层 `@Singleton` 组件，包含 8 个模块：

| 模块 | 提供内容 |
|---|---|
| `CoroutinesModule` | 协程调度器（`DISPATCHER_DEFAULT`、`DISPATCHER_IO` 等） |
| `RTCModule` | WebRTC 原生对象：`PeerConnectionFactory`、`EglBase`、`AudioDeviceModule`、编解码器工厂、`RTCThreadToken`、`SdpFactory` |
| `WebModule` | `OkHttpClient`、`WebSocket.Factory`、`Json` |
| `JsonFormatModule` | protobuf/JSON 格式工具 |
| `OverridesModule` | 用户自定义覆盖项（来自 `LiveKitOverrides`） |
| `AudioHandlerModule` | `AudioHandler` 绑定（默认 `AudioSwitchHandler`） |
| `MemoryModule` | `CloseableManager` |
| `InternalBindsModule` | 接口到实现的绑定 |

工厂入口：
```kotlin
DaggerLiveKitComponent.factory().create(ctx, overrides).roomFactory().create(ctx)
```

### 3.3 关键对象提供链路

以 `Room` 的创建为例（`LiveKit.kt:91`）：

```
DaggerLiveKitComponent.create(ctx, OverridesModule(overrides))
   └─ roomFactory(): Room.Factory  (AssistedFactory)
        └─ create(ctx): Room
             @AssistedInject 构造，参数由 DI 提供：
             - engine: RTCEngine          (Singleton, @Inject)
             - eglBase: EglBase            (RTCModule)
             - localParticipantFactory    (AssistedFactory)
             - audioHandler               (AudioHandlerModule/Overrides)
             - audioProcessingController  (RTCModule → CustomAudioProcessingFactory)
             - incomingDataStreamManager, rpcClientManager, rpcServerManager
             - remoteParticipantFactory
             - ... 共 20+ 依赖
```

`RTCEngine`（`RTCEngine.kt:113`）是 `@Singleton @Inject`，持有 `SignalClient`、`PeerConnectionTransport.Factory`、`RTCThreadToken` 等。

`RTCModule`（`dagger/RTCModule.kt:73`）是 WebRTC 原生层的提供者，几个关键点：
- **`libWebrtcInitialization`**（`:102`）：用 `@Named(LIB_WEBRTC_INITIALIZATION)` 标记的"哨兵"依赖。任何依赖 native 库的对象，只要在 `@Provides` 方法签名里加这个参数，Dagger 就会先触发 libwebrtc 初始化。这是用 DI 表达"初始化顺序"的优雅手法。
- **`peerConnectionFactoryManager`**（`:347`）：在 RTC 线程上创建 `PeerConnectionFactory`，并把 `dispose` 注册到 `CloseableManager`（且 dispose 也投递回 RTC 线程）。
- **`audioModule`**（`:154`）：构建 `JavaAudioDeviceModule`，设置 `setSamplesReadyCallback(audioRecordSamplesDispatcher)`——这是本地音频采样回调的注入点，让 `LocalAudioTrack.addSink` 能拿到麦克风原始采样。
- **`rtcThreadToken`**（`:396`）：`RTCThreadTokenImpl` 绑定到 `PeerConnectionFactoryManager`，保证 RTC 线程亲和性。

### 3.4 LiveKitOverrides：扩展点

`LiveKitOverrides`（`LiveKitOverrides.kt:41`）是用户替换内部实现的入口，通过 `OverridesModule` 注入为 `@Named(OVERRIDE_*)` 的可空绑定。各模块在 `@Provides` 中优先使用 override，否则用默认实现。可覆盖项：

- `okHttpClient`：网络客户端
- `videoEncoderFactory` / `videoDecoderFactory`：编解码器工厂
- `audioOptions.audioHandler`：音频处理策略（默认 `AudioSwitchHandler`，可换 `NoAudioHandler`/`AudioFocusHandler`/自定义）
- `audioOptions.audioDeviceModule`：音频设备模块（注意：自定义时不由 SDK 释放，用户负责 `release()`）
- `eglBase`：EGL 上下文
- `peerConnectionFactoryOptions`：PeerConnectionFactory 选项

> **设计要点**：DI + override 模式让 SDK 既"开箱即用"（合理默认），又"可替换关键部件"（高级定制），且替换点是编译期类型安全的。C++ 读者可类比"带默认注入的 IoC 容器 + 抽象接口注册"。

---

## 第 4 章 连接生命周期与状态机

### 4.1 两套状态

SDK 有两套相关但不同的状态：

- **`Room.State`**（`Room.kt:187`）：面向用户的高层状态 `CONNECTING / CONNECTED / DISCONNECTED / RECONNECTING`，通过 `@FlowObservable` 可观察。`Room` 在状态变化时启停音频处理（`:239`）：进入 CONNECTING 启动 `audioHandler`/`communicationWorkaround`，进入 DISCONNECTED 停止。
- **`ConnectionState`**（`room/ConnectionState.kt:19`）：`RTCEngine` 内部更细粒度的状态 `CONNECTING / CONNECTED / DISCONNECTED / RECONNECTING / RESUMING`。多了 `RESUMING`（软重连中）。

`RTCEngine.connectionState` 的变化触发 `Listener` 回调（`RTCEngine.kt:130`）：
- `DISCONNECTED → CONNECTED`：`onEngineConnected()`
- `RECONNECTING → CONNECTED`：`onEngineReconnected()`
- `RESUMING → CONNECTED`：`onEngineResumed()`
- `CONNECTED → DISCONNECTED`：触发 `reconnect()`

`Room` 收到这些回调后更新自己的 `State` 并广播 `RoomEvent`（`Room.kt:1175`）。

### 4.2 connect 流程时序

`Room.connect()`（`Room.kt:461`）是核心入口，流程如下：

```
Room.connect(url, token, options)
  │
  ├─ stateLock 加锁：校验 DISCONNECTED → state=CONNECTING
  │   ├─ 创建 CoroutineScope(defaultDispatcher + SupervisorJob)
  │   ├─ localParticipant.reinitialize(options)
  │   ├─ setupLocalParticipantEventHandling()  // 订阅 participant 事件转 RoomEvent
  │   └─ 若 e2eeOptions!=null：创建 E2EEManager 并 setup
  │
  └─ connectJob (ioDispatcher):
       ├─ (可选) AuthedAudioProcessingController.authenticate(url, token)
       ├─ 若是 LiveKit Cloud：创建/复用 RegionUrlProvider，异步 fetchRegionSettings
       ├─ nextUrl = regionUrl ?: url
       ├─ while (nextUrl != null):  // 区域回退循环
       │    ├─ engine.join(connectUrl, token, options, roomOptions)
       │    └─ 失败 → nextUrl = regionUrlProvider.getNextBestRegionUrl()，重试
       ├─ networkCallbackManager.registerCallback()
       ├─ if options.audio: setMicrophoneEnabled(true)  // 可能先 startPreconnectAudioJob
       ├─ if options.video: setCameraEnabled(true)
       └─ collectMetrics()  // 后台采集 RTC 指标
```

`RTCEngine.join()`（`RTCEngine.kt:235`）→ `joinImpl()`（`:250`）：

```
joinImpl:
  ├─ connectionState = CONNECTING
  ├─ client.join(url, token, options, roomOptions)  // SignalClient WebSocket 握手，等 JoinResponse
  ├─ listener.onJoinResponse(joinResponse)          // Room 回填 sid/name/metadata/本地参与者/已有远端参与者
  ├─ isSubscriberPrimary = joinResponse.subscriberPrimary
  ├─ configure(joinResponse, options)               // 创建 publisher/subscriber PeerConnection + DataChannel
  ├─ if (!subscriberPrimary || fastPublish): negotiatePublisher()  // 发起 SDP 协商
  └─ client.onReadyForResponses()                   // 开始处理 JoinResponse 之后的信令消息
```

`configure()`（`RTCEngine.kt:279`）在 RTC 线程创建两个 `PeerConnectionTransport`，根据 `subscriberPrimary` 决定哪个 PC 的连接状态驱动 `connectionState`，并创建 reliable/lossy DataChannel。

### 4.3 prepareConnection（预连接优化）

`Room.prepareConnection()`（`Room.kt:420`）在页面加载时提前调用，做 DNS 解析、TLS 预热；LiveKit Cloud 还会探测最佳边缘节点（`regionUrlProvider.getNextBestRegionUrl()`），把结果缓存到 `regionUrl`，供后续 `connect` 直接使用，加快首次连接。

### 4.4 重连机制

`RTCEngine.reconnect()`（`RTCEngine.kt:521`）是重连核心，策略由 `ReconnectPolicy`（默认 `DefaultReconnectPolicy`）决定退避。两种重连：

- **软重连（resume）**：WebSocket 断但希望保留 PC 状态。流程：
  - `subscriber.prepareForIceRestart()` → `client.reconnect(url, token, participantSid)`（带 `?reconnect=1&sid=...`）
  - 收到 `ReconnectResponse` 后更新 RTC 配置，`client.onReadyForResponses()`
  - `onSignalConnected(true)` → `sendSyncState()` 把订阅状态同步给服务器
  - 若 `hasPublished`：`negotiatePublisher()`（ICE restart）
  - 等待 publisher/subscriber ICE 连通 → `resendReliableMessagesForResume(lastMessageSeq)` 重放可靠消息 → `onPostReconnect(false)`

- **全量重连（full reconnect）**：`closeResources()` 后重新 `joinImpl()`。`onFullReconnecting()` 通知 Room 清空远端参与者；成功后 `onPostReconnect(true)` 让 `LocalParticipant.republishTracks()` 重新发布所有轨道。

何时全量 vs 软重连由 `ReconnectType` 与重试次数决定（`:579`）：首次尝试软重连，失败后转全量；服务器 `LeaveRequest.action=RECONNECT` 或 `canReconnect` 触发全量。

重连触发源：
- WebSocket `onClose`/`onFailure`（`SignalClient` → `RTCEngine.onClose` → `reconnect()`）
- PeerConnection ICE 断开（`connectionState → DISCONNECTED`）
- 网络回调 `onLost`/`onAvailable`（`Room.kt:1138`）

### 4.5 断连与清理

`Room.disconnect()`（`Room.kt:609`）：发 `sendLeave()` → `handleDisconnect(CLIENT_INITIATED)`。
`handleDisconnect()`（`:999`）：在 `stateLock` 内 `state=DISCONNECTED` → `cleanupRoom()`（清参与者/轨道/e2ee）→ `engine.close()` → `localParticipant.dispose()` → 广播 `RoomEvent.Disconnected` → 取消协程作用域。

`RTCEngine.close()`（`:448`）：取消重连 job、关闭协程作用域、`closeResources()`（RTC 线程上关闭两个 PC 与 DataChannel）、`client.close()`、清理可靠消息缓冲。

---

## 第 5 章 信令层 SignalClient

### 5.1 角色

`SignalClient`（`room/SignalClient.kt:75`）是与 LiveKit 服务器的 WebSocket 信令客户端，`@Singleton`。职责：
- 建立/维护 WebSocket 连接
- 用 protobuf 编解码 `SignalRequest`/`SignalResponse`
- 实现 join/reconnect 握手
- ping/pong 心跳与超时
- 把服务器消息分发给 `RTCEngine`（通过 `Listener`）

### 5.2 连接与握手

`connect()`（`SignalClient.kt:167`）：
- URL 构造：`{ws|wss}://host/rtc?protocol=..&auto_subscribe=..&adaptive_stream=..&sdk=android&version=..&...&client_protocol=..`（`createConnectionParams` `:207`）
- 请求头带 `Authorization: Bearer <token>`
- `websocketFactory.newWebSocket(request, this)`（OkHttp WebSocket）
- `suspendCancellableCoroutine` 等待 `JoinResponse`，带 10s 超时（`SIGNAL_CONNECT_TIMEOUT`）

`onMessage`（`:305`）：只处理二进制 protobuf（JSON 已不支持）。`LivekitRtc.SignalResponse.parseFrom` 后 `handleSignalResponse`。

握手状态机（`handleSignalResponse` `:668`）：
- 未连接时收到 `Join` → `isConnected=true`，启动请求队列与 ping，`resumeWith(ConnectResult.Join)`
- 未连接时收到 `Leave` → 当作连接失败
- 重连中收到任意消息 → 视为信令重连成功，`resumeWith(Reconnect/OtherResponse)`
- 已连接 → `responseFlow.tryEmit` 交给 `onReadyForResponses` 启动的收集器处理

### 5.3 请求/响应队列

`SignalClient` 用两个 `MutableSharedFlow` 做消息队列，保证顺序与背压：

- **`requestFlow`**（`:108`）：发送队列。`sendRequest()`（`:644`）对非跳过类型 `tryEmit` 入队，`startRequestQueue` 启动的协程顺序 `sendRequestImpl` 经 WebSocket 发出。跳过队列的类型（`skipQueueTypes` `:1006`：SYNC_STATE/TRICKLE/OFFER/ANSWER/SIMULATE/LEAVE）直接发送，避免被排队阻塞。
- **`responseFlow`**（`:115`）：接收队列。`onReadyForResponses()`（`:254`）后才启动收集器 `handleSignalResponseImpl` 处理，确保 JoinResponse 之后的消息在 Room 准备好后才消费。

> **设计要点**：用 SharedFlow 做消息队列而非直接处理，解耦了"网络接收"与"业务处理"，且 `resetReplayCache` 防止重放旧消息。C++ 读者可类比"生产者-消费者消息队列 + 顺序处理"。

### 5.4 ping/pong 心跳

`startPingJob()`（`:887`）按 `pingInterval` 周期发 `ping` 与 `pingReq`（带 rtt 与时间戳）。`startPingTimeout`（`:899`）等 `pingTimeout`，超时则 `close(CLOSE_REASON_PING_TIMEOUT)`。收到 `Pong`/`PongResp` 时 `resetPingTimeout` 并计算 rtt。

### 5.5 SignalResponse 分发

`handleSignalResponseImpl`（`:743`）按 `messageCase` 分发到 `Listener`：

| SignalResponse | Listener 回调 | 最终去向 |
|---|---|---|
| ANSWER | `onServerAnswer` | publisher.setRemoteDescription |
| OFFER | `onServerOffer` | subscriber.setRemoteDescription + createAnswer |
| TRICKLE | `onTrickle` | publisher/subscriber.addIceCandidate |
| UPDATE | `onParticipantUpdate` | Room.onUpdateParticipants |
| TRACK_PUBLISHED | `onLocalTrackPublished` | 唤醒 pendingTrackResolvers |
| TRACK_SUBSCRIBED | `onLocalTrackSubscribed` | Room 事件 |
| SPEAKERS_CHANGED | `onSpeakersChanged` | Room 更新活跃说话者 |
| LEAVE | `onLeave` | RTCEngine 决定 resume/reconnect/断连 |
| MUTE | `onRemoteMuteChanged` | LocalParticipant 同步 mute |
| ROOM_UPDATE | `onRoomUpdate` | Room 更新元数据/录制状态 |
| CONNECTION_QUALITY | `onConnectionQuality` | Room 更新连接质量 |
| STREAM_STATE_UPDATE | `onStreamStateUpdate` | 更新轨道流状态 |
| SUBSCRIBED_QUALITY_UPDATE | `onSubscribedQualityUpdate` | dynacast 调整发布层 |
| SUBSCRIPTION_PERMISSION_UPDATE | `onSubscriptionPermissionUpdate` | 订阅权限变更 |
| REFRESH_TOKEN | `onRefreshToken` | 更新 sessionToken |
| TRACK_UNPUBLISHED | `onLocalTrackUnpublished` | LocalParticipant 取消发布 |
| PONG/PONG_RESP | 重置心跳超时 | — |

### 5.6 发送 API

`SignalClient` 提供一组 `sendXxx` 方法封装 `SignalRequest`：`sendOffer`/`sendAnswer`/`sendCandidate`/`sendMuteTrack`/`sendAddTrack`/`sendUpdateTrackSettings`/`sendUpdateSubscription`/`sendUpdateSubscriptionPermissions`/`sendUpdateLocalMetadata`/`sendSyncState`/`sendLeave`/`sendPing`/`sendUpdateLocalAudioTrack`。这些是 `RTCEngine` 与 `LocalParticipant` 操作服务器的底层通道。

---

## 第 6 章 媒体传输层 RTCEngine + PeerConnectionTransport

### 6.1 双 PeerConnection 模型

LiveKit 用 SFU（选择性转发单元）架构，客户端与服务器之间有两条 PeerConnection（`RTCEngine.kt:187`）：

- **publisher**：本地→服务器，承载本地发布的音视频轨道与上行 DataChannel。
- **subscriber**：服务器→本地，承载远端音视频轨道与下行 DataChannel。

`subscriberPrimary`（来自 `JoinResponse`）决定谁主导：
- **subscriber primary**（常见）：服务器在 subscriber 上主动开 DataChannel；publisher 的连接状态变化只在断开时触发重连，subscriber 的连接状态驱动 `connectionState`。
- **非 subscriber primary**：publisher 的连接状态驱动 `connectionState`，连接后立即 `negotiatePublisher()`。

两个 `PeerConnectionTransport` 各配一个 `TransportObserver`（`PublisherTransportObserver`/`SubscriberTransportObserver`），它们实现 `PeerConnection.Observer`，把 native 回调转译为对 `RTCEngine`/`SignalClient` 的调用。

### 6.2 PeerConnectionTransport 封装

`PeerConnectionTransport`（`room/PeerConnectionTransport.kt:70`）是单个 `PeerConnection` 的封装，`internal` 类，构造时即在 RTC 线程创建 native `PeerConnection`（`:85`）。关键职责：

- **ICE 候选管理**（`:105`）：`addIceCandidate` 在有 remoteDescription 且非 ICE restart 时直接加，否则缓存到 `pendingCandidates`，等 `setRemoteDescription` 成功后批量补加。
- **SDP 协商**（`negotiate` `:146`）：`debounce(20ms)` 防抖的"创建并发送 offer"。`createAndSendOffer`（`:155`）在 `offerLock` 内、RTC 线程上：处理 ICE restart、生成 offer、**SDP munge**、setLocalDescription、通过 `listener.onOffer` 回调发给 `SignalClient.sendOffer`。
- **offerId 去重**（`:99` `latestOfferId`）：用递增的 offerId 拒绝过期的 answer，避免竞态。
- **状态查询**（`isConnected`/`iceConnectionState`/`signalingState`）：都经 `launchRTCIfNotClosed` 投递到 RTC 线程执行。
- **关闭**（`close`/`closeBlocking`）：RTC 线程上 `peerConnection.dispose()` 并取消协程作用域。

### 6.3 SDP 协商流程

发布侧（publisher）协商由 `onRenegotiationNeeded` 触发（`PublisherTransportObserver.kt:56` → `engine.negotiatePublisher()`）：

```
native PC 需要重协商
  → PublisherTransportObserver.onRenegotiationNeeded()
  → RTCEngine.negotiatePublisher()  (negotiatePublisherMutex 加锁)
  → publisher.negotiate(constraints)  (debounce 20ms)
  → createAndSendOffer:
       ├─ createOffer(constraints)   [native]
       ├─ SDP munge: ensureVideoDDExtensionForSVC + ensureCodecBitrates
       ├─ setLocalDescription(munged) [native]
       └─ listener.onOffer(sd, offerId)
  → SignalClient.sendOffer(sd, offerId)  [WebSocket 发给服务器]
```

服务器应答：
```
SignalClient 收到 ANSWER
  → RTCEngine.onServerAnswer(sd, offerId)
  → publisher.setRemoteDescription(sd, offerId)
       ├─ offerId 校验（拒绝旧 offer）
       ├─ peerConnection.setRemoteDescription [native]
       └─ 补加 pendingCandidates
```

订阅侧（subscriber）协商由服务器主动发 offer：
```
SignalClient 收到 OFFER
  → RTCEngine.onServerOffer(sd, offerId)
  → subscriber.setRemoteDescription(sd, offerId)
  → subscriber.withPeerConnection { createAnswer() }
  → subscriber.setLocalDescription(answer)
  → SignalClient.sendAnswer(answer, offerId)
```

### 6.4 SDP munge（修改 SDP）

`createAndSendOffer` 在 setLocalDescription 前对 SDP 做"munge"（`PeerConnectionTransport.kt:206`）：

- **`ensureVideoDDExtensionForSVC`**（`:405`）：对 SVC 编解码器（AV1/VP9）手动添加 dependency descriptor RTP 头扩展（若 SDP 中缺失），保证 SVC 正常工作。
- **`ensureCodecBitrates`**（`:452`）：对 SVC 编解码器注入 `x-google-start-bitrate`（目标码率的 70%）与 `x-google-max-bitrate`，避免 SVC 启动码率过低导致前几秒模糊。

> **给 C++ 读者**：SDP munge 是 WebRTC 客户端的常见技巧——在 native 层生成 SDP 后、设置前，用文本解析（这里是 `javax.sdp`）修改某些字段，绕过 native API 不暴露的配置。类似 C++ 中"序列化后改字符串再反序列化"。

### 6.5 ICE / Trickle

ICE 候选用 trickle ICE：native `onIceCandidate` 回调（`PublisherTransportObserver.kt:48`）→ `SignalClient.sendCandidate` → 服务器转发。服务器侧候选通过 `SignalResponse.TRICKLE` → `RTCEngine.onTrickle`（`RTCEngine.kt:1152`）按 target 分发到 publisher/subscriber 的 `addIceCandidate`。ICE restart 通过 SDP 里的 `ICE_RESTART` 约束触发（`getPublisherOfferConstraints` `:916`），用于重连。

### 6.6 DataChannel 与可靠消息

`RTCEngine` 维护两条 DataChannel（`RTCEngine.kt:190`）：
- **reliable**（`_reliable`）：有序、可靠，用于需要保证送达的数据（RPC、数据流）。
- **lossy**（`_lossy`）：无序、最多 0 次重传，用于可丢弃的数据（说话者状态、低优先级消息）。

`DataChannelManager`（`webrtc/DataChannelManager.kt`）封装 DataChannel 的 observer 与缓冲状态。

**可靠消息重放**（`RTCEngine.kt:733` `sendData` / `:820` `resendReliableMessagesForResume`）：
- 每条可靠消息带递增 `sequence`，发送后入 `reliableMessageBuffer`（按 bufferedAmount 上限修剪）。
- 软重连成功后，服务器返回 `lastMessageSeq`，客户端 `popToSequence(lastMessageSeq)` 后重放缓冲中 sequence 之后的消息，保证 resume 不丢消息。
- 接收侧用 `reliableReceivedState`（TTLMap）去重，丢弃重复或乱序的可靠包（`:1300`）。

### 6.7 RTC 线程模型

WebRTC native API 非线程安全，必须单线程访问。SDK 用专用 RTC 线程（`webrtc/peerconnection/RTCThreadUtils.kt`）：

- **单线程执行器**（`:49`）：`Executors.newSingleThreadExecutor`，线程名前缀 `LK_RTC_THREAD_`。
- **`executeOnRTCThread`**（`:71`）：若已在 RTC 线程则直接执行，否则 `executor.submit`。非阻塞。
- **`executeBlockingOnRTCThread`**（`:96`）：同步阻塞提交并 `get()`，返回结果。
- **`launchBlockingOnRTCThread`**（`:119`）：协程版，用 `async(rtcDispatcher).await()` 在协程里阻塞投递。
- **`RTCThreadToken`**（`:144`）：绑定到 `PeerConnectionFactoryManager` 的生命周期令牌，`isDisposed` 时所有 RTC 调用短路返回 null，避免在 PCF 释放后访问 native 对象。

`PeerConnectionTransport` 的所有 native 操作都经 `launchRTCIfNotClosed`/`executeRTCIfNotClosed`（`PeerConnectionTransport.kt:360`）走 RTC 线程并检查 closed 状态。

> **给 C++ 读者**：这是"单线程化"并发模型——把所有对非线程安全资源的访问串行化到一个线程，用 future/协程等待结果，避免锁。比加细粒度锁更简单且无死锁。`RTCThreadToken` 类似"弱引用令牌"，资源释放后调用自动 no-op。

---

## 第 7 章 参与者模型 Participant

### 7.1 继承体系

```
Participant (open class)
├── LocalParticipant   (本地，可发布/订阅/RPC)
└── RemoteParticipant  (远端，只能订阅)
```

`Participant`（`room/participant/Participant.kt:54`）是基类，承载所有参与者共有状态。

### 7.2 Participant 基类

`Participant` 持有大量 `@FlowObservable` 状态（可观察，见第 12 章）：
- `sid` / `identity`：参与者标识（`value class`，强类型）
- `name` / `metadata` / `attributes` / `agentAttributes`：元数据
- `state`：`JOINING/JOINED/ACTIVE/DISCONNECTED/UNKNOWN`
- `kind`：`AGENT/STANDARD/INGRESS/EGRESS/SIP/CONNECTOR/BRIDGE/UNKNOWN`（区分普通用户与 AI agent 等）
- `audioLevel` / `isSpeaking` / `lastSpokeAt`：说话状态
- `connectionQuality`：连接质量
- `permissions`：`ParticipantPermission`（canPublish/canSubscribe/canPublishData/hidden/recorder/canPublishSources/canUpdateMetadata/canSubscribeMetrics）
- `trackPublications`：sid → TrackPublication 的映射
- `clientProtocol`：对端通告的客户端协议版本（用于 RPC v2 协商）

派生的只读 Flow（`Participant.kt:325`）：
- `audioTrackPublications` / `videoTrackPublications`：按类型过滤的发布列表
- `isMicrophoneEnabled` / `isCameraEnabled` / `isScreenShareEnabled`：从对应轨道的 muted 状态派生

事件：每个 `Participant` 有自己的 `events`（`BroadcastEventBus<ParticipantEvent>`），状态变化时通过 `flowDelegate` 的 `onSetValue` 回调发事件（如 `isSpeaking` 变化发 `SpeakingChanged`，`:136`）。

`updateFromInfo`（`:438`）：从服务器 `ParticipantInfo` protobuf 同步所有字段。

### 7.3 LocalParticipant

`LocalParticipant`（`room/participant/LocalParticipant.kt:94`）扩展了发布能力：

- **创建轨道**：`createAudioTrack` / `createVideoTrack`（相机）/ `createScreencastTrack`（屏幕共享），通过各自的 `Factory`（`@AssistedFactory`）创建。
- **便捷开关**：`setMicrophoneEnabled` / `setCameraEnabled` / `setScreenShareEnabled`（`:306`/`:290`/`:329`），内部 `setTrackEnabled(source)`（`:340`）用 `sourcePubLocks`（每个 source 一把 `Mutex`）串行化，避免并发创建多个相同 source 的 capturer（相机死锁问题）。
- **发布轨道**：`publishAudioTrack` / `publishVideoTrack`（`:449`/`:506`）→ `publishTrackImpl`（`:631`）：
  1. 权限校验 `hasPermissionsToPublish`
  2. 构造 `AddTrackRequest`（含 layers、simulcastCodecs、source 等）
  3. `negotiate()`：在 publisher PC 上 `addTransceiver`（SEND_ONLY），设置 codec 偏好、degradationPreference
  4. `requestAddTrack()`：`engine.addTrack`（suspend，等服务器 `TrackPublishedResponse`）
  5. 创建 `LocalTrackPublication`，加入 `trackPublications`，发事件
- **数据发布**：`publishData` / `publishDtmf`（`:1004`/`:1046`）→ `engine.sendData`（DataChannel）。
- **RPC**：实现 `RpcManager`，委托 `rpcClientManager`/`rpcServerManager`。
- **取消发布**：`unpublishTrack`（`:955`）：移除 sender、停止 transceiver（视频）、发事件。
- **重连恢复**：`prepareForFullReconnect`（`:1286`）保存待重发列表，`republishTracks`（`:1302`）在全量重连后重新发布。
- **dynacast**：`handleSubscribedQualityUpdate`（`:1177`）根据服务器反馈调整发布层/codec。

### 7.4 RemoteParticipant

`RemoteParticipant` 由 `remoteParticipantFactory.create(info)` 创建（`Room.kt:833`），主要承载订阅侧状态：`addSubscribedMediaTrack`（由 `Room.onAddTrack` 调用）把 native 收到的 `MediaStreamTrack` 包装成 `RemoteAudioTrack`/`RemoteVideoTrack` 并加入发布。其事件被 `Room` 收集转发为 `RoomEvent`（`Room.kt:837`）。

### 7.5 权限模型

发布前 `LocalParticipant.hasPermissionsToPublish`（`:607`）校验 `permissions.canPublish` 与 `canPublishSources`。订阅权限通过 `setTrackSubscriptionPermissions`（`:943`）→ `engine.updateSubscriptionPermissions` → 服务器，控制谁能订阅本端轨道。

---

## 第 8 章 轨道模型 Track 体系

### 8.1 Track 继承体系

```
Track (abstract)
├── AudioTrack (abstract)
│   ├── LocalAudioTrack
│   └── RemoteAudioTrack
└── VideoTrack (abstract)
    ├── LocalVideoTrack
    └── RemoteVideoTrack
        └── LocalScreencastVideoTrack (extends LocalVideoTrack)
```

`Track`（`room/track/Track.kt:35`）是基类，持有 `name`/`kind`/`sid`/`streamState`/`enabled`/`statsGetter`/`rtcThreadToken`。`enabled` 的 getter/setter 都经 `withRTCTrack` 在 RTC 线程操作 native track（`:57`）。`isDisposed` 直接查 native `rtcTrack.isDisposed`。

### 8.2 TrackPublication 体系

```
TrackPublication (open)
├── LocalTrackPublication
└── RemoteTrackPublication
```

`TrackPublication`（`room/track/TrackPublication.kt:28`）是"轨道发布信息"的抽象，持有 `track`（可空，订阅后才填充）、`sid`/`name`/`kind`/`muted`/`source`/`simulcasted`/`dimensions`/`mimeType`/`encryptionType`，以及 `participant` 的 `WeakReference`（防内存泄漏）。`muted` 与 `track` 都是 `@FlowObservable`。`updateFromInfo` 从 `TrackInfo` 同步。

### 8.3 本地视频轨道链路

`LocalVideoTrack`（`room/track/LocalVideoTrack.kt:65`）的创建链路（`createTrack` `:498`）：

```
LocalVideoTrack.createTrack
  ├─ peerConnectionFactory.createVideoSource(isScreencast)   [native]
  ├─ (可选) ScaleCropVideoProcessor 包裹用户 VideoProcessor
  ├─ source.setVideoProcessor(finalVideoProcessor)
  ├─ SurfaceTextureHelper.create("VideoCaptureThread", eglContext)  // 采集线程
  ├─ (可选) CaptureDispatchObserver 拦截原始帧给本地预览
  ├─ capturer.initialize(surfaceTextureHelper, context, capturerObserver)
  ├─ peerConnectionFactory.createVideoTrack(uuid, source)   [native]
  └─ trackFactory.create(...)  // @AssistedFactory 构造 LocalVideoTrack
```

数据流（采集→发布）：
```
Camera/MediaProjection
  → VideoCapturer (Camera2Capturer / ScreenCapturerAndroid)
  → SurfaceTextureHelper (专用采集线程，EGL 渲染)
  → VideoSource.capturerObserver
  → (VideoProcessor 链：ScaleCrop → 用户 Processor)
  → native VideoSource → native 编码器 → RTP
  → publisher PeerConnection → 服务器
```

关键能力：
- **`switchCamera`**（`:184`）：切换前后摄像头，等首帧确认后更新 options。
- **`restartTrack`**（`:267`）：用新 options 重建 capturer/source/rtcTrack，迁移 sinks。
- **`setPublishingLayers`**（`:321`）：dynacast——根据服务器反馈启用/禁用 simulcast 各层或 SVC 层级。
- **`setPublishingCodecs`**（`:388`）：处理服务器请求的 codec 切换，必要时触发备用 codec 发布。
- **Simulcast/SVC**：`simulcastCodecs` 映射 `VideoCodec → SimulcastTrackInfo`，`addSimulcastTrack`/`clearSimulcastCodecs` 管理多 codec 发布。

### 8.4 本地音频轨道链路

`LocalAudioTrack`（`room/track/LocalAudioTrack.kt:62`）创建链路（`createTrack` `:222`）：

```
LocalAudioTrack.createTrack
  ├─ MediaConstraints (echoCancellation/autoGainControl/noiseSuppression/...)
  ├─ factory.createAudioSource(constraints)   [native]
  ├─ factory.createAudioTrack(uuid, source)   [native]
  └─ audioTrackFactory.create(...)  // @AssistedFactory
```

数据流（采集→发布）：
```
麦克风 (AudioRecord, VOICE_COMMUNICATION 源)
  → JavaAudioDeviceModule (setSamplesReadyCallback → AudioRecordSamplesDispatcher)
  → native AudioSource → native 音频处理(AEC/NS/AGC + CustomAudioProcessingFactory)
  → native 编码器 → RTP
  → publisher PeerConnection → 服务器
```

关键能力：
- **`addSink`**（`:120`）：注册 `AudioTrackSink` 拿到麦克风原始 PCM（经 `AudioRecordSamplesDispatcher` 派发，依赖 `JavaAudioDeviceModule.setSamplesReadyCallback`）。
- **`setAudioBufferCallback`**（`:140`）：混入自定义音频。
- **`applyOptions`**（`:155`）：运行时更新音频处理选项（AEC/NS/AGC），通过 native `setAudioProcessingOptions`。
- **`features`**（`:180`）：派生 Flow，组合 options 特性与 `AudioProcessingController` 的后处理器（如 Krisp 降噪），上报给服务器。
- **`prewarm`**（`:104`）：通过 `AudioRecordPrewarmer` 预热录音栈，加快首次发布。

### 8.5 Simulcast / SVC / Dynacast / 备用编解码器

- **Simulcast**（多分辨率同发）：`computeVideoEncodings`（`LocalParticipant.kt:818`）按 capture 分辨率生成 h/m/l 三层 encoding（rid），从大到小排序。服务器按订阅者能力转发对应层。
- **SVC**（可伸缩编码，VP9/AV1）：单 encoding 带 `scalabilityMode`（如 `L3T3_KEY`），用 `setPublishingLayers` 切换层级而非多 encoding。SVC 强制开启 dynacast。
- **Dynacast**：`Room.dynacast` 开启后，服务器通过 `SUBSCRIBED_QUALITY_UPDATE` 反馈订阅者需要的质量，`LocalParticipant.handleSubscribedQualityUpdate` 调 `track.setPublishingLayers` 启停层，节省上行带宽/CPU。
- **备用编解码器**（`backupCodec`）：SVC codec（VP9/AV1）可能不被某些订阅者支持，服务器请求时 `publishAdditionalCodecForTrack`（`:1203`）额外发布一个 VP8/H264 编码的 simulcast track。

### 8.6 远端轨道与渲染

- **`RemoteVideoTrack`**（`room/track/RemoteVideoTrack.kt:40`）：订阅后由 `Room.onAddTrack` 创建。`addRenderer` 把 `VideoSink` 加到 native track。
- **adaptiveStream**（`autoManageVideo`）：开启后，`addRenderer` 传 `View` 时自动用 `ViewVisibility` 跟踪可见性与尺寸。`recalculateVisibility`（`:146`）在可见性/尺寸变化时发 `TrackEvent.VisibilityChanged`/`VideoDimensionsChanged`，上层据此通过 `sendUpdateTrackSettings` 让服务器只发需要的分辨率，不可见时暂停接收。
- **渲染视图**：`SurfaceViewRenderer`/`TextureViewRenderer`（`renderer/`），需先 `Room.initVideoRenderer` 用 `EglBase` 初始化。

---

## 第 9 章 完整业务流程：音频发布与订阅

本章把前面各层串起来，讲清音频从采集到对端播放的完整模块间数据流与控制流。

### 9.1 音频发布数据流（本地 → 服务器）

```
┌──────────────┐   PCM 16-bit   ┌──────────────────────────────┐
│ 麦克风硬件    │──────────────▶│ JavaAudioDeviceModule          │
│ (AudioRecord │                │  setSamplesReadyCallback       │
│  VOICE_COMM) │                │  → AudioRecordSamplesDispatcher │
└──────────────┘                └──────────────┬───────────────┘
                                               │ audio samples
                                               ▼
                                 ┌──────────────────────────────┐
                                 │ native AudioSource            │
                                 │ + CustomAudioProcessingFactory│
                                 │   (AEC/NS/AGC + 用户 Processor)│
                                 └──────────────┬───────────────┘
                                                │ processed PCM
                                                ▼
                                 ┌──────────────────────────────┐
                                 │ native 音频编码器 (Opus等)      │
                                 │ + DTX/RED (由 features 控制)   │
                                 └──────────────┬───────────────┘
                                                │ RTP packets
                                                ▼
                                 ┌──────────────────────────────┐
                                 │ publisher PeerConnection      │
                                 │  (RtpSender ← LocalAudioTrack │
                                 │   .transceiver)               │
                                 └──────────────┬───────────────┘
                                                │ SRTP/DTLS
                                                ▼
                                 ┌──────────────────────────────┐
                                 │ LiveKit SFU 服务器             │
                                 └──────────────────────────────┘
```

### 9.2 音频发布控制流

```
应用调用 room.connect(audio=true)
  → Room.connect → localParticipant.setMicrophoneEnabled(true)
  → LocalParticipant.setTrackEnabled(MICROPHONE)
  → getOrCreateDefaultAudioTrack() → LocalAudioTrack.createTrack
       (createAudioSource + createAudioTrack, native)
  → track.prewarm() / track.start()
  → publishAudioTrack(track)
  → publishTrackImpl:
       ├─ hasPermissionsToPublish 校验
       ├─ engine.addTrack(cid, name, AUDIO, ...)  [suspend, 等 TrackPublishedResponse]
       │    └─ SignalClient.sendAddTrack → 服务器 → TrackPublishedResponse
       │       └─ RTCEngine.onLocalTrackPublished → resume continuation
       ├─ engine.createSenderTransceiver(track.rtcTrack, SEND_ONLY)  [publisher PC]
       ├─ transceiver.sortVideoCodecPreferences / 设 degradationPreference
       └─ 创建 LocalTrackPublication, addTrackPublication, 发 TrackPublished 事件
  → (PublisherTransportObserver.onRenegotiationNeeded 自动触发)
  → engine.negotiatePublisher() → publisher.negotiate → createAndSendOffer
  → SignalClient.sendOffer → 服务器 → SignalClient.onServerAnswer
  → publisher.setRemoteDescription  [SDP 协商完成, 音频 RTP 开始上行]
  → 启动 features flow: track::features.flow.collect → engine.updateLocalAudioTrack
```

### 9.3 音频订阅数据流（服务器 → 本地播放）

```
┌──────────────────────────────┐
│ LiveKit SFU 服务器             │
└──────────────┬───────────────┘
               │ SRTP/DTLS (subscriber PC)
               ▼
┌──────────────────────────────┐
│ subscriber PeerConnection     │
│  (RtpReceiver → RemoteAudioTrack│
│   .receiver)                   │
└──────────────┬───────────────┘
               │ RTP packets
               ▼
┌──────────────────────────────┐
│ native 音频解码器 (Opus等)      │
└──────────────┬───────────────┘
               │ PCM
               ▼
┌──────────────────────────────┐
│ native AudioTrack → AudioTrack │
│  (JavaAudioDeviceModule 播放)  │
│  → 扬声器/听筒/蓝牙 (AudioSwitch)│
└──────────────────────────────┘
```

### 9.4 音频订阅控制流

```
服务器通知有远端音频轨道
  → (subscriber primary) 服务器在 subscriber PC 上发 offer
  → SignalClient.onServerOffer → RTCEngine.onServerOffer
  → subscriber.setRemoteDescription → createAnswer → setLocalDescription → sendAnswer
  → native onAddTrack(receiver, track, streams)
  → RTCEngine.onAddTrack → Room.onAddTrack
  → participant.addSubscribedMediaTrack(track, trackSid, ...)
  → 创建 RemoteAudioTrack (持 receiver)
  → RemoteTrackPublication.track = remoteAudioTrack
  → Room.onTrackSubscribed → RoomEvent.TrackSubscribed
  → (E2EE 若开启) E2EEManager.addSubscribedTrack 给 RtpReceiver 加 FrameCryptor
  → 应用可 remoteAudioTrack.addSink 拿 PCM，或直接由 native 播放
```

### 9.5 模块/文件夹间依赖关系（音频）

```
audio/                    提供 AudioHandler(AudioSwitchHandler)、AudioProcessingController、
                          AudioRecordPrewarmer、PreconnectAudioBuffer、ScreenAudioCapturer
   ↑ 被依赖
room/track/LocalAudioTrack  持有 audioProcessingController、audioRecordPrewarmer、dispatchers
   ↑ 被依赖
room/participant/LocalParticipant  创建/发布 LocalAudioTrack
   ↑ 被依赖
room/Room  编排，state 变化时启停 audioHandler
   ↑ 被依赖
room/RTCEngine  提供 addTrack/createSenderTransceiver/negotiatePublisher
   ↑ 被依赖
room/SignalClient  sendAddTrack/sendOffer/sendAnswer
   ↑ 被依赖
webrtc/ (native)  PeerConnectionFactory.createAudioSource/Track, AudioDeviceModule
```

### 9.6 关键时序：音频发布到首帧上行

```
T0  setMicrophoneEnabled(true)
T1  createAudioTrack (native source+track)
T2  engine.addTrack (sendAddTrack via WS)
T3  ← TrackPublishedResponse (服务器分配 sid)
T4  addTransceiver (publisher PC, SEND_ONLY)
T5  onRenegotiationNeeded → negotiatePublisher (debounce 20ms)
T6  createOffer → SDP munge → setLocalDescription
T7  sendOffer (WS)
T8  ← onServerAnswer → setRemoteDescription
T9  ICE 连通 → 音频 RTP 开始上行
T10 服务器转发给订阅者
```

---

## 第 10 章 完整业务流程：视频发布与订阅

### 10.1 视频发布数据流（本地 → 服务器）

```
┌───────────────┐  YUV frames  ┌──────────────────────────────┐
│ Camera2 /     │────────────▶│ VideoCapturer                 │
│ MediaProjection│             │ (Camera2Capturer/ScreenCapturer)│
└───────────────┘             └──────────────┬───────────────┘
                                              │
                                              ▼
                              ┌──────────────────────────────┐
                              │ SurfaceTextureHelper           │
                              │  (专用采集线程 + EGL)           │
                              └──────────────┬───────────────┘
                                              │ VideoFrame
                                              ▼
                              ┌──────────────────────────────┐
                              │ VideoSource.capturerObserver   │
                              │  + VideoProcessor 链            │
                              │   (ScaleCrop → 用户 Processor)  │
                              └──────────────┬───────────────┘
                                              │ processed VideoFrame
                                              ▼
                              ┌──────────────────────────────┐
                              │ native VideoSource             │
                              └──────────────┬───────────────┘
                                              │
                                              ▼
                              ┌──────────────────────────────┐
                              │ native 视频编码器               │
                              │  (VP8/H264/VP9/AV1)            │
                              │  Simulcast: 多层 / SVC: 多层级  │
                              └──────────────┬───────────────┘
                                              │ RTP packets (多层)
                                              ▼
                              ┌──────────────────────────────┐
                              │ publisher PeerConnection      │
                              │  (RtpSender ← LocalVideoTrack  │
                              │   .transceiver + simulcast)    │
                              └──────────────┬───────────────┘
                                              │ SRTP/DTLS
                                              ▼
                              ┌──────────────────────────────┐
                              │ LiveKit SFU 服务器             │
                              └──────────────────────────────┘
```

### 10.2 视频发布控制流

```
应用调用 room.connect(video=true) 或 setCameraEnabled(true)
  → LocalParticipant.setTrackEnabled(CAMERA)
  → getOrCreateDefaultVideoTrack() → LocalVideoTrack.createCameraTrack
       (权限检查 → CameraCapturerUtils.createCameraCapturer → createTrack)
  → track.start() / track.startCapture()
  → publishVideoTrack(track)
  → publishTrackImpl:
       ├─ 校验 enabledPublishVideoCodecs (服务器允许的 codec)
       ├─ isSVC 判断 → 强制 dynacast + backupCodec + scalabilityMode
       ├─ computeVideoEncodings (simulcast/SVC encodings)
       ├─ (若服务器支持多 codec) 并发: negotiate() || requestAddTrack()
       │   否则串行: requestAddTrack() → 回填 codec → negotiate()
       ├─ negotiate: addTransceiver(SEND_ONLY, encodings)
       │             sortVideoCodecPreferences
       │             set degradationPreference
       ├─ engine.addTrack (sendAddTrack, 含 layers + simulcastCodecs)
       ├─ 创建 LocalTrackPublication, 发 TrackPublished 事件
       └─ (onRenegotiationNeeded → negotiatePublisher → SDP 协商)
```

### 10.3 视频订阅数据流（服务器 → 本地渲染）

```
┌──────────────────────────────┐
│ LiveKit SFU 服务器             │
│  (按订阅者能力转发对应 simulcast 层)│
└──────────────┬───────────────┘
               │ SRTP/DTLS (subscriber PC)
               ▼
┌──────────────────────────────┐
│ subscriber PeerConnection     │
│  (RtpReceiver → RemoteVideoTrack│
│   .receiver)                   │
└──────────────┬───────────────┘
               │ RTP packets
               ▼
┌──────────────────────────────┐
│ native 视频解码器              │
│  (按 codec 选 hardware/software)│
└──────────────┬───────────────┘
               │ VideoFrame (I420/texture)
               ▼
┌──────────────────────────────┐
│ native VideoTrack             │
│  → 已 addSink 的 VideoSink 们  │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ SurfaceViewRenderer /          │
│ TextureViewRenderer (EGL 绘制) │
│  ← Room.initVideoRenderer 初始化│
└──────────────────────────────┘
```

### 10.4 视频订阅控制流

```
服务器通知远端视频轨道
  → (subscriber primary) 服务器发 offer
  → RTCEngine.onServerOffer → subscriber.setRemoteDescription → createAnswer → sendAnswer
  → native onAddTrack → Room.onAddTrack
  → participant.addSubscribedMediaTrack(track, trackSid, autoManageVideo=adaptiveStream)
  → 创建 RemoteVideoTrack (持 receiver, autoManageVideo 标志)
  → Room.onTrackSubscribed → RoomEvent.TrackSubscribed
  → (E2EE) E2EEManager.addSubscribedTrack 给 RtpReceiver 加 FrameCryptor
  → 应用: remoteVideoTrack.addRenderer(surfaceViewRenderer)
       └─ 若 autoManageVideo: 用 ViewVisibility 跟踪可见性
            → recalculateVisibility → TrackEvent.VisibilityChanged/VideoDimensionsChanged
            → 上层 sendUpdateTrackSettings (按尺寸选分辨率, 不可见则暂停)
```

### 10.5 adaptiveStream / dynacast 控制回路

这是 SDK 的带宽自适应核心，两条回路：

**adaptiveStream（订阅侧驱动）**：
```
RemoteVideoTrack 的 renderer 可见性/尺寸变化
  → recalculateVisibility → TrackEvent
  → (上层/SDK) sendUpdateTrackSettings(sid, disabled, dimensions, quality)
  → 服务器只发对应分辨率的层；不可见时暂停
```

**dynacast（发布侧驱动）**：
```
服务器根据所有订阅者的需求汇总
  → SignalResponse.SUBSCRIBED_QUALITY_UPDATE
  → RTCEngine.onSubscribedQualityUpdate → LocalParticipant.handleSubscribedQualityUpdate
  → (dynacast 开启) track.setPublishingLayers(qualities)
       ├─ SVC: 调 encoding.active 启停整个 SVC 层级
       └─ Simulcast: 按 rid 启停各层 encoding
  → native 编码器相应启停层，节省上行带宽/CPU
```

### 10.6 模块/文件夹间依赖关系（视频）

```
room/track/video/          CameraCapturerUtils, VideoProcessor 链, CaptureDispatchObserver,
                          ScaleCropVideoProcessor, VideoSinkVisibility, ScalabilityMode
room/track/screencapture/  ScreenCaptureService (前台服务), ScreenCaptureConnection
   ↑ 被依赖
room/track/LocalVideoTrack / LocalScreencastVideoTrack
   ↑ 被依赖
room/participant/LocalParticipant  computeVideoEncodings, publishVideoTrack
   ↑ 被依赖
room/Room  adaptiveStream 标志传递, initVideoRenderer
   ↑ 被依赖
room/RTCEngine  createSenderTransceiver, registerTrackBitrateInfo, negotiatePublisher
   ↑ 被依赖
room/SignalClient  sendAddTrack, sendUpdateTrackSettings
   ↑ 被依赖
webrtc/  CustomVideoEncoderFactory/DecoderFactory, SimulcastVideoEncoderFactoryWrapper,
        PeerConnectionExt, RtpTransceiverExt, SdpExt
renderer/  SurfaceViewRenderer, TextureViewRenderer (EGL)
```

### 10.7 关键时序：视频发布到首帧上行

```
T0  setCameraEnabled(true)
T1  createCameraTrack (权限检查 → capturer → source → rtcTrack)
T2  startCapture (Camera2 开始出帧)
T3  engine.addTrack (sendAddTrack, 含 layers + simulcastCodecs)
T4  ← TrackPublishedResponse
T5  addTransceiver (publisher PC, SEND_ONLY, encodings)
T6  sortVideoCodecPreferences (按 videoCodec 排序)
T7  onRenegotiationNeeded → negotiatePublisher (debounce 20ms)
T8  createOffer → SDP munge (DD ext + bitrate) → setLocalDescription
T9  sendOffer → ← onServerAnswer → setRemoteDescription
T10 ICE 连通 → 视频 RTP 多层开始上行
T11 服务器转发 → 订阅者解码 → 渲染首帧
```

---

## 第 11 章 数据通道与数据流（DataChannel / DataStream / RPC）

### 11.1 DataChannel 基础

`RTCEngine` 在 publisher PC 上创建两条 DataChannel（`RTCEngine.kt:345`/`:371`）：
- `_reliable`：有序可靠，用于 RPC、数据流。
- `_lossy`：无序无重传，用于可丢弃消息。

发送：`engine.sendData(dataPacket)`（`:733`）→ 选 channel → `channel.send(Buffer)`。可靠消息带 sequence 并入重放缓冲。接收：`DataChannelObserver.onMessage`（`:1293`）→ 解析 `DataPacket` → 按 `valueCase` 分发（SPEAKER/USER/TRANSCRIPTION/RPC_*/STREAM_*）。

### 11.2 用户数据 publish/receive

发布：`LocalParticipant.publishData`（`LocalParticipant.kt:1004`）构造 `UserPacket`（payload/topic/destinationIdentities）→ `engine.sendData`。
接收：`RTCEngine.onMessage` 的 `USER` 分支 → `Room.onUserPacket`（`Room.kt:1326`）→ `RoomEvent.DataReceived`。

### 11.3 DataStream（文本/字节流）

DataStream 支持大块数据的流式传输（突破单包 15KB 限制），分 incoming/outgoing：

**incoming**（`room/datastream/incoming/`）：
- `IncomingDataStreamManager`（`:91`）按 topic 注册 `TextStreamHandler`/`ByteStreamHandler`。
- 收到 `STREAM_HEADER` → `openStream` 创建 `Channel<ByteArray>` 并调用对应 handler（`TextStreamReceiver`/`ByteStreamReceiver` 从 channel 读）。
- 收到 `STREAM_CHUNK` → `channel.trySend`；`STREAM_TRAILER` → `channel.close`（成功/异常）。
- `Room` 在 init 时为 RPC v2 注册了 `lk.rpc_request`/`lk.rpc_response` 两个保留 topic（`Room.kt:167`）。

**outgoing**（`room/datastream/outgoing/`）：
- `OutgoingDataStreamManager`（`LocalParticipant` 通过 by 委托继承）提供 `sendText`/`sendBytes`，把数据切成 chunk 通过 `engine.sendData` 发 `STREAM_HEADER`/`STREAM_CHUNK`/`STREAM_TRAILER`。

### 11.4 RPC 机制

RPC 让一个参与者调用另一个参与者上注册的方法，分 v1/v2：

- **`RpcManager`**（`room/rpc/RpcManager.kt`）：接口，`registerRpcMethod`/`unregisterRpcMethod`/`performRpc`。`Room` 与 `LocalParticipant` 都实现它，`Room` 委托给 `LocalParticipant`。
- **调用方**（`RpcClientManager`）：`performRpc` 构造 `RpcRequest` → `engine.sendData`，等 `RpcResponse`/`RpcAck`（带超时）。
- **被调方**（`RpcServerManager`）：收到 `RpcRequest` → 查注册的 `RpcHandler`（`suspend (RpcInvocationData) -> String`）→ 返回结果或 `RpcError`。
- **v1**：请求与响应内联在 `DataPacket` 中，payload 限 15KB。
- **v2**：请求与成功响应用 text data stream 传输（topic `lk.rpc_request`/`lk.rpc_response`），突破 15KB 限制。由 `ClientProtocolVersion.DATA_STREAM_RPC` 协商，`Room` 在 init 时根据对端 `clientProtocol` 决定走 v1 还是 v2（`Room.kt:179` 的 `getRemoteClientProtocol`）。

`LocalParticipant.handleDataPacket`（`:1075`）区分 `rpcRequest`/`rpcResponse`/`rpcAck` 分别交给 server/client manager。

---

## 第 12 章 事件体系

### 12.1 BroadcastEventBus

`events/BroadcastEventBus.kt` 是事件总线基础，基于 `MutableSharedFlow`（`extraBufferCapacity = Int.MAX_VALUE`，不丢事件）。提供 `postEvent`（suspend）/`tryPostEvent`/`postEvent(scope)`（异步）。`EventListenable` 暴露只读 `events: SharedFlow<T>`，用户用 `room.events.collect { ... }` 订阅。

### 12.2 事件类型层次

```
Event (base)
├── RoomEvent (sealed, room.events)
│   ├── Connected / Reconnecting / Reconnected / Disconnected / FailedToConnect
│   ├── ParticipantConnected / ParticipantDisconnected
│   ├── ParticipantMetadataChanged / ParticipantAttributesChanged / ParticipantNameChanged / ParticipantStateChanged
│   ├── ParticipantPermissionsChanged
│   ├── TrackPublished / TrackPublicationFailed / TrackUnpublished
│   ├── TrackSubscribed / TrackSubscriptionFailed / TrackUnsubscribed
│   ├── TrackMuted / TrackUnmuted / TrackStreamStateChanged / TrackSubscriptionPermissionChanged
│   ├── TrackE2EEStateEvent / LocalTrackSubscribed
│   ├── DataReceived / ConnectionQualityChanged / ActiveSpeakersChanged
│   ├── RoomMetadataChanged / RecordingStatusChanged / TranscriptionReceived
├── ParticipantEvent (sealed)   // participant 内部事件，Room 转译为 RoomEvent
├── TrackEvent (sealed)          // track 内部事件
└── TrackPublicationEvent (sealed)
```

### 12.3 事件传递路径

事件从底层到上层的典型路径：

```
native / 服务器消息
  → RTCEngine (SignalClient.Listener) 收到信号
  → Room (RTCEngine.Listener) 处理
  → 更新 Participant/Track 状态 (flowDelegate 触发)
  → eventBus.postEvent(RoomEvent)
  → room.events (SharedFlow) → 应用 collect
```

例：服务器发 `SPEAKERS_CHANGED`：
```
SignalClient.onSpeakersChanged → RTCEngine.onSpeakersChanged
  → Room.onSpeakersChanged → handleSpeakersChanged
  → 更新 participant.audioLevel/isSpeaking (flowDelegate)
  → eventBus.postEvent(RoomEvent.ActiveSpeakersChanged)
  → room.events.collect
```

`Participant` 的状态变化事件（`ParticipantEvent`）由 `Room.setupLocalParticipantEventHandling`（`Room.kt:700`）和 `getOrCreateRemoteParticipant`（`:837`）收集，转译为对应 `RoomEvent`。

### 12.4 @FlowObservable 机制

`util/FlowDelegate.kt` 是 SDK 响应式状态的核心。用法：

```kotlin
@FlowObservable
@get:FlowObservable
var identity: Identity? by flowDelegate(identity)
```

`flowDelegate` 返回 `MutableStateFlowDelegate`，它：
- 包装一个 `MutableStateFlow<T>`，`getValue` 返回 `flow.value`，`setValue` 更新 flow 并触发 `onSetValue` 回调。
- 通过 `DelegateAccess` 的 `ThreadLocal` 技巧：当用 `participant::identity.flow` 访问时，`KProperty0.delegate` 扩展（`:48`）触发一次 `get()`，期间 `MutableStateFlowDelegate.getValue` 把自身塞进 `DelegateAccess.delegate`，从而拿到底层 `StateFlow`。

这样同一个属性既能当普通变量用（`participant.identity`），又能当 Flow 观察（`participant::identity.flow.collectAsState()`），对 Compose 友好。

`onSetValue` 回调用于发事件：如 `Participant.isSpeaking` 变化时发 `SpeakingChanged`（`Participant.kt:136`），`Room.state` 变化时启停音频（`Room.kt:239`）。

> **给 C++ 读者**：`@FlowObservable` 类似"可观察属性 + 信号槽"。`flowDelegate` 是属性委托，等价于 C++ 中"用代理对象封装一个带订阅者的变量"。`DelegateAccess` 的 ThreadLocal 反射技巧是为了让 `::prop.flow` 这种"属性引用"能拿到内部的 StateFlow，因为 Kotlin 反射不直接暴露委托实例。

---

## 第 13 章 端到端加密 E2EE

### 13.1 概述

E2EE 确保只有持有密钥的参与者能解密媒体/数据，服务器（SFU）无法解密。本 SDK 的 E2EE 分两条线：媒体帧加密（`FrameCryptor`）与数据包加密（`DataPacketCryptorManager`）。

### 13.2 E2EEManager

`e2ee/E2EEManager.kt:43` 是 E2EE 入口，`@AssistedInject` 构造，需 `KeyProvider`。

**媒体帧加密**（per-track）：
- `addPublishedTrack`（`:140`）：对本地 track 的 `RtpSender` 创建 `FrameCryptor`（`FrameCryptorFactory.createFrameCryptorForRtpSender`），native 层在编码后/发送前加密每帧。
- `addSubscribedTrack`（`:106`）：对远端 track 的 `RtpReceiver` 创建 `FrameCryptor`，接收后/解码前解密。
- `setObserver` 监听加密状态变化 → `RoomEvent.TrackE2EEStateEvent`（OK/MISSING_KEY/ENCRYPTION_FAILED 等）。
- `enabled` 切换时批量启停所有 `frameCryptor`。

**数据包加密**（DataChannel）：
- `DataPacketCryptorManager`（`e2ee/DataPacketCryptorManager.kt`）用 `KeyProvider` 的密钥做 AES-GCM 加解密。
- `RTCEngine.sendData`（`:748`）：若 `dataChannelEncryptionEnabled`，把 `DataPacket` 的 payload 包装成 `EncryptedPacketPayload` → `e2EEManager.encrypt` → 替换为 `EncryptedPacket`。
- `RTCEngine.onMessage`（`:1313`）：收到 `EncryptedPacket` → `dataPacketCryptor.decrypt` → 还原 payload。

### 13.3 KeyProvider

`e2ee/KeyProvider.kt` 管理密钥：`rtcKeyProvider`（给 `FrameCryptor` 用）、`getLatestKeyIndex`、`ratchetSharedKey`（密钥轮换）、`setSifTrailer`（服务器下发的 SIF trailer，用于密钥派生）。

### 13.4 集成点

- `Room.connect` 时若 `e2eeOptions != null`：创建 `E2EEManager`，`setup(room)` 遍历已有 track 注册，并赋给 `engine.e2EEManager`（`Room.kt:488`）。
- `Room.onJoinResponse`：设置 `sifTrailer`（`Room.kt:677`）。
- `Room.onTrackPublished`/`onTrackSubscribed`：注册对应 `FrameCryptor`（`Room.kt:1544`/`:1562`）。
- `Room.onTrackUnpublished`/`onTrackUnsubscribed`：移除。
- `cleanupRoom` 时 `e2eeManager.dispose()`。

---

## 第 14 章 音频设备与音频处理子系统

`audio/` 目录负责 Android 音频设备管理、音频焦点、采集前后处理、以及若干设备/系统兼容性 workaround。它不直接做编解码（编解码在 WebRTC native 层），而是为 WebRTC 的 `JavaAudioDeviceModule`（ADM）准备环境、注入处理逻辑。

### 14.1 AudioHandler：音频生命周期入口

`AudioHandler`（`audio/AudioHandler.kt`）是极简接口：`start()` / `stop()`。`Room` 在连接建立/断开时调用它（`Room.kt` 的 `startAudio`/`stopAudio`）。有三个实现，通过 `LiveKitOverrides` 或 `RoomOptions.audioTrackPublishDefaults` 选择：

- **`AudioSwitchHandler`**（`audio/AudioSwitchHandler.kt`，363 行）：默认实现，基于 Twilio 的 AudioSwitch 库。内部用 `HandlerThread` 跑设备监听，维护 `preferredDeviceList`，在设备插拔时 `selectDevice` 自动切换到最优设备（扬声器/听筒/蓝牙耳机/有线耳机）。`start()` 注册 `AudioManager.AudioDeviceCallback` 并激活音频路由；`stop()` 还原。
- **`AudioFocusHandler`**（`audio/AudioFocusHandler.kt`）：只管音频焦点（`AudioManager.requestAudioFocus` / `abandonAudioFocus`），不管设备路由。`focusMode` 默认 `AUDIOFOCUS_GAIN`，Android O+ 用 `AudioFocusRequest`，低版本用旧 API。适合不希望 SDK 接管设备切换、只想要焦点的场景。
- **`NoAudioHandler`**：空实现，SDK 完全不碰音频设备/焦点，由应用自行管理。

> **给 C++ 读者**：Android 音频是"系统级共享资源"。`AudioManager` 管路由（哪个设备出声）和焦点（谁能发声）。焦点类似"互斥锁"——电话来了会抢走焦点，你的播放要暂停或降音量。AudioSwitch 解决的是"插入蓝牙耳机后声音要不要切过去"这类路由问题。

### 14.2 AudioProcessingController：采集/渲染前后处理

`AudioProcessingController`（`audio/AudioProcessingController.kt`）暴露两个注入点：
- `capturePostProcessor`：采集后、编码前处理（如自定义降噪）。
- `renderPreProcessor`：解码后、播放前处理。
- `bypassCapturePostProcessing` / `bypassRenderPreProcessing`：运行时旁路开关。

全部用 `@FlowObservable` 声明，意味着应用可以 `controller::capturePostProcessor.flow.collect` 观察变化。`AudioProcessorInterface` 是处理接口（`processAudio` 收发 PCM）。实现通过 `RTCModule` 注入到 WebRTC ADM 的 audio processing 链路。

`AuthedAudioProcessingController` 扩展接口加 `authenticate(url, token)`，用于需要鉴权的云端音频处理（如 LiveKit 的 noise cancellation cloud 服务）。

### 14.3 AudioRecordSamplesDispatcher：原始 PCM 分发

`AudioRecordSamplesDispatcher`（`audio/AudioRecordSamplesDispatcher.kt`）实现 WebRTC 的 `SamplesReadyCallback`。WebRTC ADM 在采集到 10ms PCM 帧时回调 `onWebRtcAudioRecordSamplesReady`，它把 `AudioSamples` 转成 `AudioTrackSink.onData` 格式分发给所有注册的 sink。`RTCModule`（`:154`）创建 ADM 时 `setSamplesReadyCallback(this)` 注入它。

`LocalAudioTrack.addSink`（`LocalAudioTrack.kt`）把 sink 注册到这个 dispatcher，从而让外部能拿到原始采集 PCM——这是 `PreconnectAudioBuffer` 能缓冲语音的前提。

### 14.4 CommunicationWorkaround：通信模式保活

`CommunicationWorkaround`（`audio/CommunicationWorkaround.kt`）针对 Android 11+ 的 bug（[issuetracker 209493718](https://issuetracker.google.com/issues/209493718)）：通信模式（`USAGE_VOICE_COMMUNICATION`）下若 6 秒无播放/采集，系统会重置音频模式导致后续播放异常。

`CommunicationWorkaroundImpl` 的解法：用一个静音的 `AudioTrack`（`MODE_STATIC` + 循环空 buffer）在"已启动但播放停止"期间持续播放静音帧，骗系统保持通信模式不重置。状态机由 `started` + `playoutStopped` 两个 `MutableStateFlow` 驱动，`combine` + `collectLatest` 响应变化。`NoopCommunicationWorkaround` 是低版本/禁用时的空实现。

> **给 C++ 读者**：这是典型的"对抗系统行为"的 workaround。等价于在 C++ 里开一个静音线程持续写音频设备，防止设备进入低功耗休眠。`AtomicBoolean` + `synchronized` 保证 AudioTrack 操作线程安全。

### 14.5 AudioRecordPrewarmer：采集预热

`AudioRecordPrewarmer`（`audio/AudioRecordPrewarmer.kt`）解决首次采集的冷启动延迟。`JavaAudioRecordPrewarmer.prewarm` 调用 `audioDeviceModule.prewarmRecording(AudioProcessingOptions)`，提前初始化录音链路（AEC/NS/AGC/HPF 配置）。`LocalAudioTrack.prewarm`（`:104`）触发它，配合 `PreconnectAudioBuffer` 在真正发布前就启动采集。

### 14.6 PreconnectAudioBuffer：预连接音频缓冲

`PreconnectAudioBuffer`（`audio/PreconnectAudioBuffer.kt`）是 LiveKit Agents 场景的优化：用户连进房间前就开始说话，把语音缓冲下来；当 Agent（远端参与者）连入并订阅了本地音频，就把缓冲的语音通过 DataStream（`streamBytes`）发给 Agent，让 Agent "提前听到"用户开头的话，降低感知延迟。

机制：
- 实现 `AudioTrackSink`，`onData` 把 PCM 写入 `ByteArrayOutputStream`，限时 `TIMEOUT`（10s）。
- `startPreconnectAudioJob` 监听 `RoomEvent`：`LocalTrackSubscribed`（Agent 订阅了本地音频）→ 停止录制；`ParticipantConnected`/`ParticipantStateChanged` 且对方是 `Kind.AGENT` 且 `ACTIVE` → 用 `localParticipant.streamBytes` 把缓冲字节流发给该 Agent。
- `withPreconnectAudio` 是给应用用的顶层封装（已 `@Deprecated`，推荐用 `RoomOptions.audioTrackPublishDefaults.preconnect`）。

> **给 C++ 读者**：这是"用空间换时间"——把用户开口的最初几秒音频先存内存，等对端就绪再补发。DataStream 的 `streamBytes` 把大块 PCM 切成 chunk 走可靠 DataChannel 传输。`engine::connectionState.flow.takeWhile { it != CONNECTED }.collect()` 是协程写法，等价于"阻塞等到连接成功"。

### 14.7 音频子系统类图

```
                    AudioHandler (interface)
                    /       |        \
        AudioSwitchHandler  AudioFocusHandler  NoAudioHandler
        (Twilio AudioSwitch,  (AudioManager      (空)
         设备路由切换)         焦点)

   AudioProcessingController (interface, @FlowObservable)
   ├── capturePostProcessor : AudioProcessorInterface?
   ├── renderPreProcessor   : AudioProcessorInterface?
   └── bypass* : Boolean
        │
   AuthedAudioProcessingController (+authenticate)

   AudioRecordSamplesDispatcher ──implements──> SamplesReadyCallback (WebRTC ADM)
        │ onWebRtcAudioRecordSamplesReady
        └── 分发到 AudioTrackSink 集合
                ↑
   PreconnectAudioBuffer ──implements──> AudioTrackSink
        │ onData 缓冲 PCM
        └── sendAudioData → localParticipant.streamBytes (DataStream)

   CommunicationWorkaround (interface)
   ├── NoopCommunicationWorkaround
   └── CommunicationWorkaroundImpl (Android 11+, 静音 AudioTrack 保活)

   AudioRecordPrewarmer (interface)
   ├── NoAudioRecordPrewarmer
   └── JavaAudioRecordPrewarmer (audioDeviceModule.prewarmRecording)
```

### 14.8 音频子系统与 Room/Track 的集成

```
Room.connect
  → audioHandler.start()              // AudioSwitch 接管设备路由
  → (若 preconnect) startPreconnectAudioJob
       → getOrCreateDefaultAudioTrack
       → audioTrack.addSink(PreconnectAudioBuffer)
       → audioTrack.prewarm()         // AudioRecordPrewarmer 预热

LocalAudioTrack.createTrack
  → PeerConnectionFactory.createAudioSource
  → ADM (JavaAudioDeviceModule, RTCModule 提供)
       ├── setSamplesReadyCallback(AudioRecordSamplesDispatcher)
       └── audioProcessing ← AudioProcessingController 的 processor

Room.disconnect / cleanupRoom
  → audioHandler.stop()
  → communicationWorkaround.stop()
  → preconnectAudioBuffer.clear()
```

---

## 第 15 章 工程特点总结与 Android SDK 分析方法论

### 15.1 工程特点

#### 15.1.1 全协程化（Coroutine-first）

整个 SDK 以 Kotlin 协程为并发骨架，几乎不用裸线程/回调：
- `Room`、`RTCEngine` 持有 `CloseableCoroutineScope`（`SupervisorJob` + 指定 dispatcher），子协程失败不传染父级。
- `suspend` 函数贯穿连接、发布、订阅、RPC 全链路，调用方可用同步写法写异步逻辑。
- `Flow` / `StateFlow` / `SharedFlow` 用于状态暴露与事件流：`connectionState`、`events`、`@FlowObservable` 属性。
- `Mutex`（如 `LocalParticipant.sourcePubLock`）替代 `synchronized` 做协程友好的互斥。

> **C++ 对照**：协程 ≈ C++20 协程 + 一个运行时调度器。`suspend fun` ≈ 返回 `co_await` 的函数，`Flow` ≈ 可订阅的异步序列（类似 Rx 但语言级）。优势是异步代码线性化、无回调地狱；代价是要理解 dispatcher（协程跑在哪个线程/线程池）。

#### 15.1.2 响应式属性 @FlowObservable

SDK 自研的 `flowDelegate` 让普通属性同时具备"变量读写"和"Flow 订阅"两种语义，对 Compose 尤其友好（`collectAsState` 直接驱动 UI 重组）。`DelegateAccess` 的 ThreadLocal 反射技巧是点睛之笔——绕过 Kotlin 反射不暴露委托实例的限制。

#### 15.1.3 Dagger 2 依赖注入

- 全 SDK 用 Dagger 2 管理对象图，`@Singleton` 控制生命周期，`@Named` 区分多实例（如多个 dispatcher）。
- `@AssistedInject` + `@AssistedFactory` 处理"运行时参数 + 依赖注入"混合构造（`Room` 需要 `ctx` 又需要注入 `RTCEngine`）。
- `LiveKitOverrides` 提供扩展点：应用可替换 `okHttpClient`、`videoEncoderFactory`、`audioHandler`、`eglBase` 等关键实现，无需改 SDK 源码。

> **C++ 对照**：Dagger ≈ 编译期生成工厂代码的 IoC 容器。相比手写工厂，它集中管理依赖图、自动解析顺序、支持作用域。代价是注解处理器（kapt/ksp）增加编译时间，错误信息晦涩。

#### 15.1.4 RTC 线程安全模型

WebRTC 对线程亲和性要求严格（同 PeerConnection 的操作必须在同一线程）。SDK 用 `RTCThreadUtils`（`webrtc/peerconnection/RTCThreadUtils.kt`）封装：
- `LK_RTC_THREAD_` 单线程 executor 作为 RTC 线程。
- `executeOnRTCThread` / `executeBlockingOnRTCThread` / `launchBlockingOnRTCThread` 把操作投递到该线程。
- `RTCThreadToken` 接口标记"必须在 RTC 线程调用"的对象（如 `PeerConnectionFactoryManager.dispose`）。

> **C++ 对照**：等价于"所有 libwebrtc 调用都 Post 到一个 `std::thread` 的任务队列"。这避免了多线程同时操作 PC 导致的 native 崩溃。

#### 15.1.5 防御式错误处理

- 重连：`ReconnectPolicy` 指数退避，区分 soft resume（信令重连，复用 PC）与 full reconnect（重建一切）。
- 可靠消息重放：`DataPacketBuffer` + `reliableReceivedState`（TTLMap 去重），resume 时 `resendReliableMessagesForResume` 重发未确认消息。
- SDP munge：在协商失败/需要微调时不重新协商，直接改 SDP 文本（加 DD extension、改 codec bitrate）。
- ICE restart：连通失败时触发 ICE restart 重新收集候选。
- 处处 `try/catch` + `LKLog`，单个 track/参与者失败不影响整体。

#### 15.1.6 可测试性与可观测性

- 接口先行：`AudioHandler`、`RpcManager`、`IncomingDataStreamManager`、`CommunicationWorkaround` 都是接口，便于 mock。
- `@VisibleForTesting` 标注内部可测入口。
- `LKLog` 统一日志（`util/LKLog.kt`），带 lambda 懒求值，可按级别过滤。
- `OverridesModule` 让测试可注入假实现。

#### 15.1.7 native 边界清晰

- `org.webrtc` / `livekit.org.webrtc` 包是 Java 绑定层，JNI 到 C++ libwebrtc。
- SDK 不直接写 JNI，而是通过 Google 提供的 Java API（`PeerConnectionFactory`、`VideoCapturer`、`AudioDeviceModule`）操作 native。
- `PeerConnectionFactoryManager` 集中管理 native 工厂生命周期，`dispose()` 必须在 RTC 线程。
- `FrameCryptor` / `DataPacketCryptor` 是少数需要触及 native 帧加密的地方。

### 15.2 类比 C++ 的整体视角

| 维度 | C++ 习惯 | 本 SDK (Kotlin/Android) |
|------|---------|----------------------|
| 并发 | `std::thread` + mutex + condition_variable | 协程 + `Mutex` + `Flow` |
| 资源管理 | RAII 析构 | `CloseableCoroutineScope`、`dispose()`、`use{}` |
| 事件 | 信号槽/回调 | `SharedFlow.collect` |
| 可观察属性 | getter + observer 列表 | `@FlowObservable` + `flowDelegate` |
| 对象创建 | 工厂/手写 new | Dagger DI |
| 线程亲和 | `PostTask` 到单线程 | `executeOnRTCThread` |
| 跨语言 | — | Kotlin→Java→JNI→C++(libwebrtc) |
| 错误 | 异常/返回码 | `try/catch` + `Result` + `rethrowIfCancellationSignal` |

### 15.3 通用的 Android SDK 分析思路与方法

分析一个陌生 Android SDK，可按以下步骤系统展开：

**第一步：找入口**
- 找 `object` / `class` 上的 `@JvmStatic` 方法、`Application.onCreate` 钩子、`ContentProvider` 自动初始化、Manifest 中的 `meta-data`。
- 本例：`LiveKit.create()` 是唯一入口。入口往往揭示"对象图怎么建"。

**第二步：画依赖图（DI）**
- 若用 Dagger/Hilt：从 `@Component` → `@Module` → `@Provides` 顺藤摸瓜，理出"谁创建谁、谁是单例"。
- 若无 DI：从构造函数参数倒推。
- 这一步定下"骨架对象"（本例：Room、RTCEngine、SignalClient、PeerConnectionFactory）。

**第三步：分层**
- 把文件按"API 门面 / 编排 / 传输 / 平台 native"分层，看依赖是否单向向下。本例四层清晰。
- 看目录命名：`room/`、`audio/`、`e2ee/`、`dagger/`、`webrtc/`、`events/`、`util/` 已暗示职责。

**第四步：抓状态机**
- 找 `enum class State`、`sealed class`、`when(state)`。本例 `Room.State`、`ConnectionState` 是连接生命周期的核心。
- 画状态转移图：什么事件触发什么迁移。

**第五步：抓线程模型**
- 搜 `CoroutineDispatcher`、`HandlerThread`、`Executor`、`Thread`。
- 厘清"哪类操作跑在哪个线程/线程池"。本例：RTC 单线程、IO dispatcher、主线程 UI。
- 特别注意 native 库的线程亲和要求（WebRTC 必须单线程）。

**第六步：抓事件流**
- 找 `Flow`/`LiveData`/`BroadcastReceiver`/回调注册。
- 从底层 native/网络事件追到顶层 API 事件，画"事件传递路径"。本例：SignalClient→RTCEngine→Room→eventBus→应用。

**第七步：抓 native 边界**
- 搜 `external fun`、`System.loadLibrary`、JNI 包名（`org.webrtc`）。
- 厘清"哪些功能是 Java/Kotlin 实现，哪些是 C++ 实现"。本例编解码、网络传输、媒体加密都在 native。

**第八步：抓关键业务流程**
- 选 1-2 个端到端业务（本例音频、视频），从用户 API 调用追到 native 再回来，画数据流 + 控制流时序图。
- 这一步验证前七步的理解是否正确。

**第九步：看工程化**
- 测试目录结构、`build.gradle` 的依赖与插件、CI 配置、lint/detekt 规则、`@VisibleForTesting`/`@Deprecated` 的使用。
- 评估可测试性、可扩展性（override 点）、可观测性（日志/指标）。

**第十步：读 README / samples / changelog**
- 官方文档和示例代码揭示"设计意图"——为什么这么设计，典型用法是什么。
- `samples/` 目录的调用顺序往往就是推荐用法。

**通用工具**：
- `grep -r "关键字" --include=*.kt` 定位实现。
- 画图工具（mermaid/PlantUML）把类图、时序图、状态机可视化。
- 对 native 部分，用 `nm`/`objdump` 看 `.so` 符号，或读 WebRTC 源码对应模块。

### 15.4 一句话总结

LiveKit Android SDK 是一个**协程化、响应式、Dagger 注入、RTC 单线程**的 SFU 客户端：`Room` 是门面，`RTCEngine` 是内核，`SignalClient` + `PeerConnectionTransport` 是传输，`org.webrtc` 是 native 底座；通过 `@FlowObservable` 把状态变事件，通过双 PC + subscriber primary 适配 SFU 模型，通过重放缓冲与重连策略保证可靠性，通过 `LiveKitOverrides` 开放扩展。理解它，就是理解"Kotlin 协程 + WebRTC JNI + SFU 信令"三者如何在一个 Android 工程里编排起来。

---

> 全文完。共 15 章（第 0-15 章），覆盖前置知识、架构、DI、连接生命周期、信令、媒体传输、参与者、轨道、音频/视频业务流、数据通道、事件、E2EE、音频子系统、工程总结与分析方法论。

---

# 第二部分：网络交互、抽象讲解、图集、QoS 优化（第 16-22 章）

> 以下为补充章节，不改动前 15 章内容，只追加。

---

## 第 16 章 网络交互深入：信令、媒体与 WebRTC 内部

> 本章把"涉及网络"的部分彻底展开。网络是实时音视频的命脉，信令负责"约"，媒体负责"传"，WebRTC native 负责把"传"做到工业级。

### 16.1 两条网络通道总览

LiveKit 客户端同时维护**两条独立的网络通道**，职责完全不同：

| 通道 | 协议 | 作用 | 谁建立 | 频率 |
|------|------|------|--------|------|
| 信令通道 | WebSocket（wss） | 交换 SDP/ICE、房间状态、订阅控制 | `SignalClient` | 长连接，低频 |
| 媒体通道 | SRTP over UDP（ICE+DTLS） | 传音视频 RTP、DataChannel | `PeerConnectionTransport`（native） | 长连接，高频 |

**双通道分层图**：

```
┌─────────────────────────────────────────────────────────┐
│  App（你的代码）                                          │
└──────────────────────────┬──────────────────────────────┘
                           │ room.connect / publish / subscribe
┌──────────────────────────▼──────────────────────────────┐
│  LiveKit SDK（Kotlin/Java）                              │
│  ┌──────────────┐         ┌──────────────────────────┐  │
│  │ SignalClient │         │ RTCEngine /              │  │
│  │ (信令)        │         │ PeerConnectionTransport   │  │
│  │  OkHttp WS    │         │  (媒体控制)               │  │
│  └──────┬───────┘         └────────────┬─────────────┘  │
└─────────┼──────────────────────────────┼─────────────────┘
          │ wss 文本帧                    │ SDP/ICE 指令
┌─────────▼──────────────────────────────▼─────────────────┐
│  org.webrtc / livekit.org.webrtc（Java JNI 绑定层）        │
│  PeerConnection.createOffer/setLocalDescription/...        │
└─────────┬──────────────────────────────┬─────────────────┘
          │                              │ RTP/SRTP 收发
┌─────────▼──────────────────────────────▼─────────────────┐
│  libwebrtc.so（C++ native，JNI 之下）                      │
│  编码器/解码器、RTP 打包、FEC/NACK、GCC 带宽估计、          │
│  Jitter buffer、ICE/DTLS/SRTP、socket                     │
└─────────┬──────────────────────────────┬─────────────────┘
          │ WebSocket(OkHttp)             │ UDP socket
┌─────────▼──────────────────────────────▼─────────────────┐
│  Android OS 网络栈（Linux 内核 netfilter/socket）          │
│  WiFi/蜂窝/以太网 → 互联网 → LiveKit SFU                    │
└───────────────────────────────────────────────────────────┘

信令通道：App → SignalClient → OkHttp WebSocket → OS socket → SFU 的 /rtc 端点
媒体通道：Camera/Mic → 编码 → libwebrtc → UDP → ICE → SRTP → SFU 的媒体端口
```

**关键点**：信令走 WebSocket（可靠、有序、文本），媒体走 UDP（低延迟、可丢）。两者完全解耦——信令断了媒体可能还在传（soft resume 场景），媒体断了信令可能还在（触发 ICE restart）。

### 16.2 信令交互完整流程（展开）

#### 16.2.1 WebSocket 建立

`SignalClient.connect`（`SignalClient.kt:167`）构造 WebSocket URL：

```
wss://<url>/rtc?protocol=<n>&auto_subscribe=<0|1>&adaptive_stream=<0|1>
           &sdk=android&version=<v>&device_model=<m>&os=android&os_version=<v>
           &network=<wifi|cellular|ethernet|...>&client_protocol=<n>
           [&reconnect=1&participant_sid=<sid>]    // 仅重连时
```

请求头带 `Authorization: Bearer <token>`（JWT，含房间名/参与者身份/权限）。用 OkHttp 的 `WebSocket.newWebSocket(request, listener)` 建连，`joinContinuation` 挂起协程等 `SignalResponse.join` 回来（`withDeadline(SIGNAL_CONNECT_TIMEOUT)` 超时保护）。

> **C++ 对照**：等价于 `connect()` 一个 TLS WebSocket，然后用 `condition_variable` 等握手完成。OkHttp 的 `WebSocketListener` ≈ C++ 的回调对象。

#### 16.2.2 Join 握手

```
Client                          SFU
  │                              │
  │── WS connect (wss + token) ─►│
  │                              │
  │◄── SignalResponse.Join ──────│  (房间信息、参与者列表、已发布 track、iceServers)
  │                              │
  │   onJoinResponse:            │
  │   - 保存 iceServers          │
  │   - 配置 publisher/subscriber PC │
  │   - 设置 sifTrailer(E2EE)    │
  │   - 添加已有远端参与者         │
  │   - onReadyForResponses()    │
  │                              │
  │── SignalRequest.Configure ──►│  (subscriberPrimary, 视频编解码偏好)
  │                              │
  │◄── Answer (subscriber SDP) ──│
  │   ... ICE 交换 ...            │
  │   媒体通道建立                 │
```

`onJoinResponse`（`Room.kt:666`）是连接流程的核心枢纽：拿到 `iceServers`（TURN/STUN 列表）才能配置 PeerConnection，拿到已有参与者/track 才能补建订阅。

#### 16.2.3 消息分发：requestFlow / responseFlow

`SignalClient` 用两个 `SharedFlow` 做消息队列：
- `requestFlow`：应用/引擎要发的 `SignalRequest`，`sendRequest` 投递，WebSocket `send` 出去。
- `responseFlow`：WebSocket `onMessage` 收到的 `SignalResponse`，`handleSignalResponseImpl`（`:743`）按 `messageCase` 分发到 `RTCEngine` 的各回调（`onJoinResponse`/`onAnswer`/`onTrickle`/`onTrackPublished`/...）。

`onReadyForResponses`（`:254`）是"闸门"——在 join 处理完之前，收到的响应先缓冲，避免乱序。

#### 16.2.4 心跳 ping/pong

`SignalClient` 周期发 `SignalRequest.ping`，服务器回 `pong`（`:887`）。超时未回判定信令断开，触发重连。这是 WebSocket 层之上的应用心跳（WebSocket 自己也有 ping，但应用层心跳更可控）。

#### 16.2.5 重连信令

两种重连：
- **soft resume**（`reconnect=1`）：WebSocket 断了但 SFU 还保留着会话，重连后用原 `participant_sid` resume，复用已有 PC，只重发未确认的可靠消息（`resendReliableMessagesForResume`，`RTCEngine.kt:820`）。
- **full reconnect**：会话已失效，重建一切。

`DefaultReconnectPolicy`（`room/network/DefaultReconnectPolicy.kt`）定义重试延迟序列：`[100,300,300,500,500,500,1200,2700,4800,5000×8]` 毫秒，总超时 60 秒。前几次激进重试（WiFi→LTE 切换可能很快恢复），之后指数退避。

#### 16.2.6 信令消息时序图

```
App            Room         RTCEngine     SignalClient    SFU
 │              │              │              │             │
 │─connect─────►│              │              │             │
 │              │─connect─────►│              │             │
 │              │              │─connect─────►│             │
 │              │              │              │──wss connect►
 │              │              │              │◄──Join──────│
 │              │              │◄─onJoinResponse             │
 │              │◄─onJoinResponse             │             │
 │              │─configure──►│─configure────►│──Configure─►│
 │              │              │              │◄──Answer─────│
 │              │              │◄─onAnswer                    │
 │              │              │              │              │
 │─publishTrack│              │              │             │
 │              │─addTrack───►│              │             │
 │              │              │─negotiatePublisher          │
 │              │              │  createOffer→munge→setLocal │
 │              │              │─sendOffer───►│──Offer──────►│
 │              │              │              │◄──Answer─────│
 │              │              │◄─onAnswer (publisher)       │
 │              │              │  setRemoteDescription       │
 │              │              │              │              │
 │              │              │  ICE candidates 双向交换     │
 │              │              │◄─onTrickle───│◄──Trickle────│
 │              │              │─sendCandidate│──Trickle───►│
 │              │              │              │              │
 │              │              │  媒体开始上行 (SRTP)        │
 │              │◄─onTrackPublished             │             │
 │◄─events(TrackPublished)     │              │             │
 │              │              │              │              │
 │   ... 通话中 SubscribedQuality 闭环 ...                  │
 │              │              │◄─onSubscribedQualityUpdate │
 │              │              │  setPublishingLayers(dynacast)│
```

### 16.3 媒体流交互完整流程（展开）

#### 16.3.1 publisher PC（上行）

```
Camera(Mic) → Android CameraService → Camera2 API
  → VideoCapturer(Java) → SurfaceTextureHelper(Java, EGL 线程)
  → VideoSource(Java/native) → VideoProcessor(可选, ScaleCrop/NoDrop/Chain)
  → VideoEncoder(native: H264/VP8/VP9/AV1 硬编或软编)
  → RTP 打包(native) → SRTP 加密(native, DTLS 协商的密钥)
  → ICE Agent(native, 选最优 path) → UDP socket(native)
  → 互联网 → SFU
```

音频类似：`AudioRecord → JavaAudioDeviceModule → AudioProcessing(AEC/NS/AGC) → Opus 编码 → RTP → SRTP → ICE → UDP`。

#### 16.3.2 subscriber PC（下行）

```
SFU → 互联网 → UDP → ICE Agent → SRTP 解密 → RTP 解包
  → Jitter buffer(native, 去抖动、乱序重排)
  → VideoDecoder(native) → I420/NV12 帧
  → VideoSink(Java) → SurfaceView/TextureView(渲染到屏幕)
```

#### 16.3.3 SDP 协商完整链路

`negotiatePublisher`（`RTCEngine.kt:716`）→ `PeerConnectionTransport.negotiate`（debounce 20ms，`PeerConnectionTransport.kt:146`）→ `createAndSendOffer`（`:155`）：

```
1. createOffer(constraints)          native 生成 SDP offer
2. SDP munge:                         Java 改 SDP 文本
   - ensureVideoDDExtensionForSVC     给 SVC 加 dependency descriptor 扩展
   - ensureCodecBitrates              按 trackBitrates 改 a=fmtp bitrate
3. setLocalDescription(mungedOffer)   native 接受
4. sendOffer → SignalClient → SFU
5. SFU 回 Answer
6. onAnswer → setRemoteDescription    native 接受
7. ICE 候选交换（trickle）
8. DTLS 握手（native 自动）
9. SRTP 就绪，媒体开始流动
```

**SDP munge 是关键**：LiveKit 不重新协商就改 SDP 文本（加 DD extension、改 bitrate），因为重新协商成本高。这是 WebRTC 的"灰色用法"——依赖 SDP 文本格式，脆弱但高效。

> **C++ 对照**：SDP 是文本协议，类似 HTTP header。munge ≈ 在发 HTTP 前手动改 header 字符串。正规做法是改参数重新生成，munge 是"直接改字符串"的捷径。

#### 16.3.4 ICE 完整链路

```
native ICE Agent 发现候选(host/srflx/relay)
  → PeerConnection.Observer.onIceCandidate (Java 回调)
  → PublisherTransportObserver.onIceCandidate
  → RTCEngine → SignalClient.sendCandidate → SFU
  → SFU 转发对端候选
  → SignalClient.onTrickle → RTCEngine.onIceCandidate
  → PeerConnectionTransport.addIceCandidate
     (若正在 setLocal/RemoteDescription 则入 pending 队列，完成后 flush)
  → native ICE Agent 配对、连通性检查
  → 选最优 path，媒体走该 path
```

ICE restart：连通失败时，`createOffer` 带 `ICE_RESTART` 约束，强制重新收集候选（`PeerConnectionTransport.kt:166`）。

#### 16.3.5 媒体建立与传输时序图

```
App        Room      RTCEngine   PeerConnTransport   native PC    SFU
 │          │          │              │                 │           │
 │publishTrack         │              │                 │           │
 │────────►│addTrack   │              │                 │           │
 │          │─────────►│addTrack      │                 │           │
 │          │          │─createSenderTransceiver        │           │
 │          │          │  addTrack(native)              │           │
 │          │          │─negotiatePublisher             │           │
 │          │          │  negotiate(debounce 20ms)      │           │
 │          │          │              │─createAndSendOffer           │
 │          │          │              │  createOffer    │           │
 │          │          │              │  ◄─SDP offer    │           │
 │          │          │              │  SDP munge      │           │
 │          │          │              │  setLocalDesc   │           │
 │          │          │─sendOffer────►│                 │──Offer──►│
 │          │          │              │                 │           │
 │          │          │              │                 │◄──Answer──│
 │          │          │◄─onAnswer───│                 │           │
 │          │          │  setRemoteDescription         │           │
 │          │          │              │                 │           │
 │          │          │  ICE 候选双向交换 (trickle)    │           │
 │          │          │◄─onIceCandidate────────────────│◄──Trickle─│
 │          │          │─sendCandidate────────────────►│──Trickle─►│
 │          │          │              │  addIceCandidate│           │
 │          │          │              │                 │  连通性检查│
 │          │          │              │                 │  DTLS握手 │
 │          │          │              │                 │  SRTP就绪 │
 │          │          │              │                 │           │
 │          │          │  编码帧 → RTP → SRTP → UDP ──────────────►│ (媒体上行)
 │          │          │              │                 │           │
 │          │◄─onTrackPublished       │                 │           │
 │◄─RoomEvent.TrackPublished          │                 │           │
```

### 16.4 内部 WebRTC 的作用（org.webrtc / libwebrtc）

#### 16.4.1 org.webrtc 包是什么

`org.webrtc` 是 **Google libwebrtc 的 Java JNI 绑定层**。它把 C++ 的 `PeerConnection`、`MediaStreamTrack`、`VideoCapturer`、`VideoEncoder` 等类用 Java 重新声明一遍，每个 Java 对象内部持有一个 `long nativeHandle`（C++ 指针），方法调用通过 JNI 转发到 C++。

`livekit.org.webrtc` 是 **LiveKit 自己 fork 的二次封装包**（改了包名避免冲突），加了：
- `SimulcastVideoEncoderFactoryWrapper`：解决 libwebrtc 的 H264+simulcast 崩溃 bug（`SimulcastVideoEncoderFactoryWrapper.kt:80` 的 `FallbackFactory`）。
- `CustomVideoEncoderFactory` / `CustomVideoDecoderFactory`：可注入自定义编解码器。
- `StreamEncoderWrapper`：每个流编码用独立单线程 + 尺度适配。
- native 库名改为 `lkjingle_peerconnection_so`（`RTCModule.kt:110`）。

#### 16.4.2 native 层做了什么（Java 看不见的）

| 功能 | native 实现 | Java 是否参与 |
|------|------------|--------------|
| 采集调度 | `VideoCapturer` 调 Camera2，回调到 `SurfaceTextureHelper` | Java 触发，native 调度 |
| 编码 | `VideoEncoder`（硬编 MediaCodec / 软编 libvpx） | Java 转发，native 干活 |
| RTP 打包 | native `RtpSender` | 不参与 |
| FEC/NACK | native `RtpPacketSender` | 不参与 |
| 带宽估计（GCC） | native `GoogCcNetworkController` | 不参与 |
| 拥塞控制 | native，根据 GCC 调编码 bitrate | 不参与 |
| Jitter buffer | native `VideoReceiveStream` | 不参与 |
| 解码 | `VideoDecoder`（硬解 MediaCodec / 软解 libvpx） | Java 转发 |
| ICE | native `P2PTransportChannel` | Java 收候选转发 |
| DTLS/SRTP | native `DtlsTransport` | 不参与 |
| socket 收发 | native `AsyncPacketSocket` | 不参与 |

**结论**：所有"网络传输"和"QoS"核心逻辑都在 native，Java 只是编排和回调。

#### 16.4.3 Java 层做了什么

- 封装 `PeerConnection` 生命周期（create/setSDP、addIceCandidate、close）。
- SDP 文本操作（munge、解析）。
- 线程投递：把所有 native 操作投到 RTC 单线程（`RTCThreadUtils`）。
- 事件回调：native Observer → Java 回调 → SDK 业务逻辑。
- 资源管理：`PeerConnectionFactoryManager` dispose。

#### 16.4.4 Java↔JNI↔C++ 调用栈图（以编码一帧为例）

```
[Java 层]                          [JNI 边界]              [C++ native 层]
VideoCapturer.onFrameCaptured
  → SurfaceTextureHelper
    → VideoSource.capturerObserver
      → native OnFrame
        ───────────────────────►  JavaVideoSource::OnFrame
                                    → VideoTrackSource::OnFrame
                                      → VideoBroadcaster::OnFrame
                                        → VideoStreamEncoder::OnFrame
                                          → EncoderStreamFactory
                                            → SimulcastEncoderAdapter::Encode
                                              → 子编码器 Encode
                                                → MediaCodecVideoEncoder::Encode
                                                  → MediaCodec (硬件)
        ◄───────────────────────  编码完成回调
VideoEncoder.Callback.onEncodedFrame
  → native OnEncodedImage
    ─────────────────────────────►  VideoSendStream::OnEncodedImage
                                    → RtpSenderVideo::SendVideo
                                      → RTP 打包
                                      → FEC/NACK 处理
                                      → SRTP 加密
                                      → PacedSender → socket
                                        → UDP 发往 SFU
```

> **C++ 对照**：Java 层就像 C++ 里的"外壳类"，真正的实现在 `.cpp` 里。JNI ≈ C++ 的 `extern "C"` 接口 + 跨语言对象生命周期管理。`long nativeHandle` ≈ C++ 的 `void*`，Java 不直接用，只传回给 native。

### 16.5 一个完整业务的端到端完整流程

把前面所有层串起来，一个最简完整通话（A 加入房间、发布音视频、订阅 B、通话、断开）：

```
阶段0: 初始化
  App.onCreate
    → LiveKit.create(ctx, options)          [API 层]
    → DaggerLiveKitComponent.factory().create  [DI 层]
      → RTCModule: libWebrtcInitialization   [native 初始化]
      → 创建 PeerConnectionFactory(单线程)
    → room = component.roomFactory().create(ctx)

阶段1: 连接
  room.connect(url, token)                   [Room.kt:461]
    → signalClient.connect(wss://.../rtc)    [SignalClient.kt:167]
      → OkHttp WebSocket 握手
      → ◄ Join 响应 (iceServers, participants, tracks)
    → onJoinResponse                         [Room.kt:666]
      → engine.configure(iceServers)        [RTCEngine.kt:279]
        → 创建 publisher PC + subscriber PC    [PeerConnectionTransport]
      → 添加已有远端参与者
    → engine.sendConfigure(subscriberPrimary) [RTCEngine]
      → ◄ subscriber Answer
      → setRemoteDescription
    → ICE/DTLS/SRTP 建立
    → Room.state = CONNECTED
    → eventBus.postEvent(Connected)

阶段2: 发布本地音视频
  room.localParticipant.setMicrophoneEnabled(true)
  room.localParticipant.setCameraEnabled(true)
    → getOrCreateDefaultAudioTrack / VideoTrack
      → AudioTrack.createTrack               [LocalAudioTrack.kt:222]
        → ADM(JavaAudioDeviceModule) + AudioProcessing
      → VideoTrack.createTrack               [LocalVideoTrack.kt:498]
        → CameraCapturer → SurfaceTextureHelper → VideoSource → rtcTrack
    → publishTrackImpl(track, options)       [LocalParticipant.kt:631]
      → computeVideoEncodings (Simulcast 层)  [:818]
      → engine.addTrack(AddTrackRequest)     [RTCEngine]
      → negotiatePublisher                   [:716]
        → createAndSendOffer → SDP munge → setLocal → sendOffer
        → ◄ Answer → setRemote
        → ICE 交换 → 媒体上行开始
      → ◄ onTrackPublished
      → eventBus.postEvent(TrackPublished)

阶段3: 订阅远端
  (B 加入并发布，服务器推送 TrackSubscribed)
    → ◄ onSubscribedTrack                   [RTCEngine]
    → Room.onSubscribedTrack                 [Room.kt]
      → getOrCreateRemoteParticipant
      → engine.addRemoteTrack → subscriber PC
      → negotiateSubscriber (服务器主动 offer)
      → ◄ Offer → setRemoteDescription → createAnswer → sendAnswer
      → ICE → 媒体下行
      → RemoteVideoTrack.addRenderer(surfaceView)  [RemoteVideoTrack]
      → eventBus.postEvent(TrackSubscribed)

阶段4: 通话中（动态调节）
  - adaptiveStream: RemoteVideoTrack 根据可见性调订阅分辨率
  - dynacast: 服务器发 SubscribedQualityUpdate → setPublishingLayers
  - 带宽变化: native GCC 调编码 bitrate（Java 不感知）
  - 网络抖动: native jitter buffer + FEC/NACK
  - 心跳: SignalClient ping/pong

阶段5: 断开
  room.disconnect() / 网络断 / 服务器踢
    → handleDisconnect                       [Room.kt:999]
      → 判断 soft resume / full reconnect
      → 若重连: ReconnectPolicy 重试
      → 若彻底断: cleanupRoom
        → engine.close → publisher/subscriber PC close
        → signalClient.close → WebSocket close
        → audioHandler.stop
        → e2eeManager.dispose
        → Room.state = DISCONNECTED
        → eventBus.postEvent(Disconnected)
```

**每一步的层/文件/线程**：
- API 层（`LiveKit`/`Room`）：主线程或调用方线程。
- DI 层（`RTCModule`）：RTC 单线程（`executeBlockingOnRTCThread`）。
- 信令（`SignalClient`）：IO dispatcher（`SupervisorJob + ioDispatcher`）。
- 媒体控制（`RTCEngine`/`PeerConnectionTransport`）：RTC 单线程（`launchRTCIfNotClosed`）。
- 媒体数据（编码/传输/解码）：native 专用线程（编码线程、RTP 线程、解码线程），Java 不参与。
- 渲染：`SurfaceTextureHelper` 的 EGL 线程 + UI 线程。
- 事件：`eventBus`（SharedFlow）→ 应用 `collect` 所在的协程。

---

## 第 17 章 Kotlin/Java 高级抽象给 C++ 读者（举例展开）

> 你说"猛得不理解依赖、委托、注入"——这些是 Java/Kotlin 工程化赖以生存的抽象。本章用 C++ 对照讲透，每个概念都给"本 SDK里的真实例子"。

### 17.1 依赖注入（DI）：从 C++ 手写工厂到 Dagger

#### 问题：谁负责 new 对象？

C++ 里你大概这么写：
```cpp
// C++ 手写工厂
RTCEngine* makeEngine(SignalClient* client, PeerConnectionFactory* pcf) {
    return new RTCEngine(client, pcf);
}
Room* makeRoom(Context* ctx, RTCEngine* engine) {
    return new Room(ctx, engine);
}
// 调用方要自己管 new 的顺序和生命周期
auto client = new SignalClient(...);
auto pcf = createPeerConnectionFactory(...);
auto engine = makeEngine(client, pcf);
auto room = makeRoom(ctx, engine);
```

痛点：依赖关系一复杂，`make` 的顺序、参数、单例/多例、谁负责 delete，全是手写、易错。

#### Kotlin + Dagger 的做法

Dagger 是**编译期**生成工厂代码的框架（不是运行时反射）。你用注解声明"我需要什么"，Dagger 生成代码替你 new：

```kotlin
// 1. 声明"我需要这些依赖"——构造注入
@Singleton
class RTCEngine @Inject constructor(
    private val client: SignalClient,        // 我需要 SignalClient
    private val factory: PeerConnectionFactory, // 我需要 PCF
) { ... }

// 2. 声明"我能提供这些依赖"——Module
@Module
object RTCModule {
    @Provides @Singleton
    fun peerConnectionFactory(...): PeerConnectionFactory { ... }  // 我知道怎么造 PCF
}

// 3. 把 Module 组装成"对象图"——Component
@Singleton @Component(modules = [RTCModule::class, ...])
interface LiveKitComponent {
    fun roomFactory(): Room.Factory   // 入口：给我一个 Room 工厂
}
```

Dagger 在编译时生成 `DaggerLiveKitComponent`，它内部就是上面那段 C++ 手写工厂的等价物——**自动解析依赖顺序、自动管单例**。运行时 `component.roomFactory()` 拿到的就是依赖全部注入好的对象。

#### 本 SDK 真实例子：Room 的构造

`Room` 用 `@AssistedInject`（比 `@Inject` 多了"运行时参数"）：
```kotlin
class Room @AssistedInject constructor(
    // 运行时参数（@Assisted）
    @Assisted context: Context,
    // 注入的依赖（自动解析）
    private val engine: RTCEngine,
    private val factory: RoomFactory,
    ...
) { ... }

// 配套工厂（因为混了运行时参数，要手写工厂接口）
@AssistedFactory
interface Factory {
    fun create(context: Context): Room
}
```

**DI 对象图**（简化）：
```
DaggerLiveKitComponent
  ├─ RTCModule ──► PeerConnectionFactory (Singleton)
  │             ──► AudioDeviceModule (Singleton)
  │             ──► SimulcastVideoEncoderFactoryWrapper
  ├─ SignalModule ──► SignalClient (Singleton)
  ├─ RoomModule ──► Room.Factory (@AssistedFactory)
  └─ OverridesModule ──► (可被应用替换的实现)
        │
        ▼
  roomFactory.create(ctx) ──► Room
        │ 注入
        ├─ RTCEngine (注入 SignalClient + PeerConnectionFactory)
        ├─ SignalClient (注入 OkHttp + 协程)
        └─ ...
```

> **C++ 一句话**：Dagger = 编译期生成工厂代码的 IoC 容器。你声明依赖，它生成 `makeXxx()` 并自动排序、管单例。省去手写工厂，代价是注解处理器增加编译时间。

### 17.2 委托（Delegate / by）：组合的语法糖

Kotlin 的 `by` 关键字做两件事：**接口委托**和**属性委托**。

#### 17.2.1 接口委托（≈ C++ 的组合 + 转发）

C++ 里要让 `Room` "表现得像 RpcManager"，你会组合一个成员并转发：
```cpp
class Room : public RpcManager {
    LocalParticipant* local;  // 持有真正干活的
public:
    void registerRpcMethod(string m, RpcHandler h) override {
        local->registerRpcMethod(m, h);  // 手动转发
    }
    string performRpc(...) override { return local->performRpc(...); }
};
```

Kotlin 一行搞定：
```kotlin
class Room(...) : RpcManager by localParticipant {
    // Room 自动获得 RpcManager 的所有方法，全部转发给 localParticipant
}
```
`by localParticipant` = "把 RpcManager 的方法实现委托给 localParticipant 这个对象"。编译器自动生成转发代码。

#### 17.2.2 属性委托（≈ C++ 重载 operator= / 自定义 getter setter）

C++ 里要让一个变量"赋值时触发回调"，你会包装成类：
```cpp
class ObservableString {
    string val_;
    function<void(string)> onChange;
public:
    operator string() const { return val_; }
    ObservableString& operator=(const string& v) { val_ = v; onChange(v); return *this; }
};
```

Kotlin 用 `by`：
```kotlin
var identity: String? by flowDelegate(initial)  // 委托给 flowDelegate 返回的对象
```
`flowDelegate` 返回一个对象，实现 `getValue`/`setValue`。读 `identity` 调 `getValue`，写 `identity` 调 `setValue`（内部更新 StateFlow 并触发回调）。这就是 `@FlowObservable` 的底层机制（见第 12.4 节）。

**对照表**：

| Kotlin | C++ 等价 |
|--------|---------|
| `class A : I by b` | `class A : I { B* b; /* 转发 */ }` |
| `var x by delegate` | `class X { get/set 重载 }; X x;` |
| `val x by lazy { ... }` | `std::call_once` + 静态局部 |
| `val x by Delegates.observable(init) { ... }` | 赋值回调包装类 |

### 17.3 注入（Inject）的三种形态

"注入"就是"把依赖送进来"，区别于"自己 new"。

```kotlin
// 1. 构造注入（最推荐，本 SDK 主流）
class RTCEngine @Inject constructor(client: SignalClient) { ... }
// C++ 等价: RTCEngine(SignalClient* client) : client_(client) {}

// 2. 字段注入（Dagger 直接写字段）
@Inject lateinit var client: SignalClient
// C++ 等价: SignalClient* client_; 由容器外部赋值

// 3. 方法注入
@Inject fun setup(client: SignalClient) { ... }
// C++ 等价: void setClient(SignalClient*) 
```

构造注入最好——依赖在构造时就齐了，对象一出生就是完整的。本 SDK 几乎全用构造注入。

### 17.4 协程与 Flow 的抽象

#### suspend 函数

```kotlin
suspend fun connect(): Room { ... }   // 可暂停的函数
```
C++20 协程对照：
```cpp
Task<Room> connect() { co_return ...; }
```
`suspend` 函数可在"等待网络/IO"时**挂起当前协程而不阻塞线程**，线程去干别的，等结果回来再恢复。这是 SDK 能用同步写法写异步的根本。

#### Flow（冷异步序列）

```kotlin
fun requests(): Flow<SignalRequest> = flow { emit(req1); emit(req2) }
```
C++ 对照 ≈ `ranges + 协程`：一个惰性序列，`collect` 时才逐个产出。

#### StateFlow / SharedFlow（热信号）

```kotlin
val connectionState = MutableStateFlow(ConnectionState.DISCONNECTED)
// 任何时候 .value 拿当前值；collect 持续观察变化
```
C++ 对照 ≈ "observable subject"：持有一个值，变化时通知所有订阅者。`StateFlow` 总有当前值（类似 `BehaviorSubject`），`SharedFlow` 是广播（类似 `PublishSubject`）。

本 SDK 的 `events: SharedFlow<RoomEvent>` 是热信号——你不 collect 也在发，collect 从当前开始收。

### 17.5 密封类、data class、object、扩展函数

#### sealed class（≈ C++ 的 tagged union / std::variant）

```kotlin
sealed class RoomEvent {
    data class Connected(val room: Room) : RoomEvent()
    data class Disconnected(val reason: DisconnectReason) : RoomEvent()
    object Reconnecting : RoomEvent()  // 无数据用 object
}
// when 分支必须穷尽，编译器检查
when (event) {
    is Connected -> ...
    is Disconnected -> ...
    Reconnecting -> ...
}
```
C++ 对照：
```cpp
struct RoomEvent { 
    enum {Connected, Disconnected, Reconnecting} tag;
    struct { Room* room; } connected;
    struct { DisconnectReason reason; } disconnected;
};
// 或 std::variant<Connected, Disconnected, Reconnecting> + std::visit
```
sealed class 的好处：`when` 穷尽检查，新增子类编译器报所有未覆盖处。本 SDK 全部事件都是 sealed class。

#### data class（≈ C++ 的 struct + 自动 ==/hash/copy）

```kotlin
data class VideoEncoding(val maxBitrate: Int, val maxFps: Int)
// 自动生成 equals, hashCode, copy, toString, component1/2(解构)
```
C++ 里你要手写 `operator==`、`hash`、`copy ctor`。Kotlin 一行搞定。

#### object（单例）

```kotlin
object LiveKit { fun create(...) = ... }
```
C++ 对照 ≈ `LiveKit& instance() { static LiveKit i; return i; }`，但 Kotlin 的 `object` 是语言级单例，线程安全。

#### 扩展函数（≈ C++ 自由函数）

```kotlin
fun Participant.identityFlow() = this::identity.flow   // 给 Participant 加方法
```
C++ 里你写自由函数 `identityFlow(Participant& p)`。Kotlin 扩展函数就是自由函数的语法糖，但看起来像成员方法。本 SDK 大量用扩展（如 `util/flow` 扩展）。

### 17.6 注解（Annotation）与编译期生成

Dagger 的 `@Inject`/`@Module`/`@Provides` 是注解，编译期由 `kapt`/`ksp` 处理器读取，生成工厂代码。C++ 没有等价物（最接近的是 X-macro 或代码生成器）。

```kotlin
@Inject          // → 生成 Factory<RTCEngine> 代码
@Singleton       // → 生成的 Factory 返回单例
@Module          // → 生成 Module 代码
@Provides        // → 标记这是提供方法
```

注解是 Java/Kotlin 工程化的"声明式编程"——你声明意图，工具生成代码。代价是调试时看不到生成代码，报错信息晦涩。

> **C++ 读者总结**：这些抽象的本质都是"把样板代码交给工具生成"。DI 生成工厂、委托生成转发、data class 生成运算符、注解生成一切。理解了这一点，读 SDK 时看到 `@Inject` 就想"这里有自动工厂"，看到 `by` 就想"这里有自动转发/包装"，看到 `sealed` 就想"这是个带标签的 union"。

---

## 第 18 章 图集：分层图、类图、交互图

> 本章纯图，尽量少字。所有图都是 ASCII，方便在终端看。

### 18.1 Android 平台分层图（从底到顶）

```
┌──────────────────────────────────────────────────────────────────┐
│ ① Linux Kernel                                                   │
│   网卡驱动 / ALSA(音频) / V4L2(摄像头) / Binder IPC / socket      │
└──────────────────────────────────────────────────────────────────┘
                                ▲
┌───────────────────────────────┴──────────────────────────────────┐
│ ② HAL（硬件抽象层）                                              │
│   audio HAL / camera HAL / display HAL                           │
└──────────────────────────────────────────────────────────────────┘
                                ▲
┌───────────────────────────────┴──────────────────────────────────┐
│ ③ Android Framework 系统服务（C++/Java，跑在系统进程）           │
│   AudioFlinger(混音)  CameraService  SurfaceFlinger(合成显示)    │
│   ConnectivityManager(网络)  AudioManager(音频路由/焦点)          │
│   MediaCodec(硬编硬解)  WindowManager  ActivityManager           │
└──────────────────────────────────────────────────────────────────┘
                                ▲  (Binder IPC / JNI)
┌───────────────────────────────┴──────────────────────────────────┐
│ ④ libwebrtc.so（C++，本进程内）                                   │
│   采集调度 编解码 RTP打包 FEC/NACK GCC带宽估计 JitterBuffer      │
│   ICE DTLS SRTP PacedSender socket                               │
│   ↑ 通过 JNI 被 ⑤ 调用                                           │
└──────────────────────────────────────────────────────────────────┘
                                ▲  JNI
┌───────────────────────────────┴──────────────────────────────────┐
│ ⑤ org.webrtc / livekit.org.webrtc（Java JNI 绑定层）              │
│   PeerConnection MediaStreamTrack VideoCapturer VideoEncoder      │
│   持有 long nativeHandle，方法转发到 ④                            │
└──────────────────────────────────────────────────────────────────┘
                                ▲
┌───────────────────────────────┴──────────────────────────────────┐
│ ⑥ LiveKit SDK（Kotlin，本仓库）                                  │
│   Room RTCEngine SignalClient Participant Track AudioHandler     │
│   Dagger DI 协程 Flow 事件总线 E2EE                              │
└──────────────────────────────────────────────────────────────────┘
                                ▲
┌───────────────────────────────┴──────────────────────────────────┐
│ ⑦ App（你的代码）                                                │
│   Activity / Service / Compose UI                                │
└──────────────────────────────────────────────────────────────────┘

数据流（视频上行）：
  ③CameraService → ④libwebrtc采集 → ④编码 → ④RTP/SRTP → ④socket → 互联网
  ③AudioFlinger → ④libwebrtc音频采集 → ④AEC/NS/AGC → ④Opus → ④RTP → ...
数据流（视频下行）：
  互联网 → ④socket → ④SRTP解密 → ④JitterBuffer → ④解码 → ⑤VideoSink
  → ⑥RemoteVideoTrack → ⑦SurfaceView → ③SurfaceFlinger → 屏幕
```

### 18.2 SDK 四层架构图（细化，带文件名）

```
┌─────────────────────────────────────────────────────────────────┐
│ API 层                                                           │
│   LiveKit.kt (create)  Room.kt (门面)  RoomOptions.kt            │
│   ConnectOptions.kt                                              │
└──────────────────────────────┬──────────────────────────────────┘
                               │ 调用
┌──────────────────────────────▼──────────────────────────────────┐
│ Room 编排层                                                      │
│   RTCEngine.kt          (引擎，协调信令+媒体)                     │
│   SignalClient.kt       (信令客户端)                             │
│   PeerConnectionTransport.kt (PC 封装)                          │
│   participant/          (Participant/LocalParticipant/Remote)   │
│   track/               (Track 体系)                              │
│   datastream/ rpc/     (数据流/RPC)                              │
│   network/             (ReconnectPolicy/NetworkCallback)        │
└──────────────────────────────┬──────────────────────────────────┘
                               │ 委托 native
┌──────────────────────────────▼──────────────────────────────────┐
│ 传输层（Java 绑定）                                              │
│   dagger/RTCModule.kt   (PeerConnectionFactory/AudioModule)      │
│   webrtc/              (SimulcastVideoEncoderFactoryWrapper 等)  │
│   webrtc/peerconnection/RTCThreadUtils.kt (线程模型)             │
│   PeerConnectionFactoryManager.kt                                │
└──────────────────────────────┬──────────────────────────────────┘
                               │ JNI
┌──────────────────────────────▼──────────────────────────────────┐
│ WebRTC 原生层（C++ libwebrtc.so）                                │
│   编解码 RTP/RTCP ICE/DTLS/SRTP GCC JitterBuffer                │
│   (不可见，通过 org.webrtc 包暴露)                                │
└─────────────────────────────────────────────────────────────────┘
依赖方向：单向向下。上层依赖下层，下层不知道上层。
```

### 18.3 信令交互分层图

```
App: room.connect(url, token)
  │
  ▼
Room.kt:461 connect()
  │
  ▼
RTCEngine.kt: connect → signalClient.connect
  │
  ▼
SignalClient.kt:167 connect()
  │  构造 wss URL + Bearer token
  ▼
OkHttp WebSocket.newWebSocket(request, listener)
  │
  ▼
Android OS socket 层 → TLS → WebSocket 帧编解码
  │
  ▼
互联网 → SFU /rtc 端点

返回路径（收消息）:
SFU → WebSocket → OkHttp onMessage(ByteString)
  → SignalClient.handleSignalResponseImpl (protobuf 解析)
  → responseFlow.emit(SignalResponse)
  → RTCEngine 的各 onXxx 回调
  → Room 的处理
  → eventBus.postEvent
  → App collect
```

### 18.4 媒体交互分层图（视频上行）

```
Camera 硬件
  │ Camera2 API
  ▼
Android CameraService ③
  │
  ▼
VideoCapturer (Java, ⑤)  ← Camera1Capturer/Camera2Capturer
  │
  ▼
SurfaceTextureHelper (Java, EGL 线程) ⑤
  │  生成 VideoFrame(I420/NV12)
  ▼
VideoSource (Java→native) ⑤→④
  │  可插入 VideoProcessor (ScaleCrop/NoDrop/Chain)
  ▼
VideoTrack (⑥) → RtpSender (⑤)
  │
  ▼
VideoEncoder (native ④): H264/VP8/VP9/AV1 (硬编 MediaCodec / 软编 libvpx)
  │
  ▼
RTP 打包 (native ④)
  │
  ▼
FEC/NACK 处理 (native ④)
  │
  ▼
PacedSender → SRTP 加密 (native ④, DTLS 协商密钥)
  │
  ▼
ICE Agent (native ④) → 选 path
  │
  ▼
UDP socket (native ④) → OS 网络栈 ① → 互联网 → SFU
```

### 18.5 加密分层图

```
媒体加密（FrameCryptor）:
  VideoEncoder 编码出明文帧
    │
    ▼
  FrameCryptor (native, per RtpSender/RtpReceiver)
    │  用 KeyProvider 的密钥加密帧
    ▼
  SRTP (native, 传输层加密)
    │
    ▼
  UDP → SFU (SFU 解 SRTP，但解不了 FrameCryptor → 看不到内容)

数据加密（DataPacketCryptorManager）:
  DataPacket (protobuf)
    │
    ▼
  DataPacketCryptorManager.encrypt (Java, AES-GCM)
    │  → EncryptedPacket
    ▼
  DataChannel (native ④)
    │
    ▼
  DTLS → UDP → SFU (SFU 看不到明文)

两层加密：FrameCryptor/数据加密是端到端（SFU 不可见），SRTP/DTLS 是跳到跳（SFU 可见）。
```

### 18.6 核心类图（全景）

```
┌──────────────┐    creates    ┌──────────────┐
│  LiveKit     │─────────────►│  Room        │
│  (object)    │  (via Dagger)│  (门面)       │
└──────────────┘              └──────┬───────┘
                                     │ owns/listens
                    ┌────────────────┼────────────────┐
                    ▼                ▼                ▼
              ┌──────────┐    ┌──────────────┐  ┌──────────────┐
              │RTCEngine │    │LocalParticipant│ │RemoteParticipant│
              │(engine)  │    │              │  │              │
              └────┬─────┘    └──────┬───────┘  └──────┬───────┘
                   │                 │                 │
        ┌──────────┴────────┐       │ publishes       │ subscribes
        ▼                   ▼       ▼                 ▼
  ┌────────────┐    ┌──────────────┐  ┌──────────────────────┐
  │SignalClient│    │PeerConnTrans │  │TrackPublication      │
  │(信令)       │    │(publisher/   │  │ (Local/Remote)      │
  └─────┬──────┘    │subscriber)   │  └──────────┬───────────┘
        │           └──────┬───────┘             │
        │                  │ wraps               │ has
        │                  ▼                      ▼
        │           ┌─────────────┐      ┌──────────────┐
        │           │PeerConnection│     │ Track        │
        │           │(org.webrtc)  │     │ (Audio/Video)│
        │           └──────┬──────┘     └──────┬───────┘
        │                  │ JNI               │
        │                  ▼                   ▼
        │           ┌─────────────┐      ┌──────────────┐
        │           │libwebrtc.so │      │LocalVideo/Audio│
        │           │(C++)        │      │RemoteVideo/Audio│
        │           └─────────────┘      └──────────────┘
        │
        ▼
  ┌──────────┐    ┌──────────────┐
  │OkHttp WS │    │BroadcastEventBus│──► events (SharedFlow)
  └──────────┘    └──────────────┘
```

### 18.7 Track 继承类图

```
              Track (abstract)
              /           \
        AudioTrack        VideoTrack        (abstract, 持有 rtcTrack)
        (abstract)        (abstract)
        /      \          /        \
LocalAudio  RemoteAudio LocalVideo RemoteVideo
  Track     Track       Track      Track
  │                     │
  │ createTrack         │ createTrack
  │ (ADM+AudioProc)     │ (Camera+STH+Source+Encoder)
  │                     │
  ▼                     ▼
LocalAudioTrack.kt    LocalVideoTrack.kt     LocalScreencastVideoTrack
  - addSink            - setPublishingLayers   (屏幕共享)
  - applyOptions       - setPublishingCodecs
  - prewarm            - switchCamera/restartTrack

TrackPublication (abstract)
  ├── LocalTrackPublication  (本地发布)
  └── RemoteTrackPublication (远端订阅)
  字段: track, muted, @FlowObservable
```

### 18.8 事件类图

```
EventListenable<T> (interface)
  └─ events: SharedFlow<T>
        ▲
        │ implements
  BroadcastEventBus<T> (MutableSharedFlow, extraBuffer=MAX)
        ▲
        │ owned by Room
  ┌─────┴──────────────────────────────────────────┐
  │ Room.events : SharedFlow<RoomEvent>             │
  └────────────────────────────────────────────────┘

RoomEvent (sealed)
  ├── 连接类: Connected/Reconnecting/Reconnected/Disconnected/FailedToConnect
  ├── 参与者类: ParticipantConnected/Disconnected/MetadataChanged/...
  ├── 轨道类: TrackPublished/Subscribed/Muted/Unmuted/StreamStateChanged/...
  ├── 数据类: DataReceived
  └── 其他: ConnectionQualityChanged/ActiveSpeakersChanged/...

ParticipantEvent (sealed)  ──Room 转译──► RoomEvent
TrackEvent (sealed)         ──Room 转译──► RoomEvent
TrackPublicationEvent      ──Room 转译──► RoomEvent
```

### 18.9 DI 对象图（Dagger）

```
LiveKit.create()
  → DaggerLiveKitComponent.factory().create(ctx, overrides)
        │
        ├── @Component LiveKitComponent (Singleton)
        │     │
        │     ├── modules
        │     │   ├── RTCModule ──────► PeerConnectionFactory (Singleton)
        │     │   │                 ──► AudioDeviceModule (Singleton)
        │     │   │                 ──► VideoEncoderFactory (SimulcastVideoEncoderFactoryWrapper)
        │     │   │                 ──► VideoDecoderFactory
        │     │   │                 ──► AudioProcessingFactory (CustomAudioProcessing)
        │     │   │                 ──► RTCThreadToken
        │     │   ├── SignalModule ─► SignalClient (Singleton)
        │     │   ├── RoomModule ───► Room.Factory (@AssistedFactory)
        │     │   ├── AudioModule ─► AudioHandler (AudioSwitchHandler)
        │     │   ├── E2EEModule ──► E2EEManager.Factory
        │     │   └── OverridesModule ─► (应用可替换: okHttpClient/videoEncoderFactory/...)
        │     │
        │     └── roomFactory() : Room.Factory
        │
        ▼
  Room.Factory.create(ctx)
        │ @AssistedInject
        ├── ctx (运行时参数)
        ├── RTCEngine (注入: SignalClient + PeerConnectionFactory)
        ├── SignalClient (注入)
        ├── AudioHandler (注入)
        └── ...
        │
        ▼
  Room 实例 (依赖全部就绪)
```

---

## 第 19 章 工程设计评价：特点、优劣

> 客观评价这个 SDK 的工程设计，给 C++ 视角。

### 19.1 优点

1. **分层清晰，职责单一**：API/编排/传输/native 四层，依赖单向向下。`Room` 只做门面，`RTCEngine` 只做协调，`SignalClient` 只做信令，`PeerConnectionTransport` 只封装 PC。改一层不牵连其他层。

2. **协程化彻底**：全 SDK 用 Kotlin 协程，没有回调地狱。`suspend` 函数让异步代码线性化，`Flow` 让状态/事件统一处理。`SupervisorJob` + `CloseableCoroutineScope` 保证协程可取消、不泄漏。

3. **DI 可扩展**：Dagger 让对象图显式、可测、可替换。`LiveKitOverrides` 是精心设计的扩展点——应用可替换 `okHttpClient`、`videoEncoderFactory`、`audioHandler`、`eglBase`、`audioDeviceModule` 等关键实现，无需 fork SDK。

4. **native 边界清晰**：所有 native 操作集中在 `org.webrtc` 包，通过 `RTCThreadUtils` 强制单线程。`PeerConnectionFactoryManager` 统一生命周期。Java 层不直接碰 native 指针，降低崩溃风险。

5. **防御式容错**：重连策略（soft resume/full reconnect）、可靠消息重放缓冲、SDP munge（避免重新协商）、ICE restart、处处 try/catch + LKLog。单个 track 失败不影响整体。

6. **响应式状态**：`@FlowObservable` 让属性同时具备变量和 Flow 两种语义，对 Compose 友好。`DelegateAccess` 反射技巧虽黑但实用。

7. **可测试性**：接口先行（`AudioHandler`/`RpcManager`/`IncomingDataStreamManager`），`@VisibleForTesting` 标注，`OverridesModule` 注入假实现。

### 19.2 缺点 / 局限

1. **WebRTC 强线程亲和，调试困难**：所有 PC 操作必须在 RTC 单线程，跨线程调用直接崩。调试时栈可能跳 Java/native/协程多个边界，定位难。`executeBlockingOnRTCThread` 死锁风险（在 RTC 线程上又调阻塞 RTC 线程）。

2. **SDP munge 脆弱**：直接改 SDP 文本（加 DD extension、改 bitrate）依赖 SDP 格式不变。libwebrtc 升级若改 SDP 格式，munge 代码可能失效。这是 WebRTC 的"灰色用法"，非官方保证。

3. **Dagger 编译慢、错误信息差**：`kapt` 注解处理器显著增加编译时间（全量编译多 30s+）。依赖图错误时报错晦涩（如循环依赖、缺少 `@Provides`），新手难定位。

4. **对抗系统行为的 workaround**：`CommunicationWorkaround`（Android 11+ 通信模式 6 秒重置）、`NetworkCallbackManager`（Android 8.0 请求泄漏）都是对抗系统 bug。Android 版本碎片化下，新版本可能引入新 bug，workaround 需持续维护。

5. **native 层不可见，深度优化受限**：GCC 带宽估计、FEC 强度、NACK 策略、jitter buffer 上限、opus DTX/FEC 等核心 QoS 参数都在 native，SDK 层无法调（见第 20 章）。要改必须动 `livekit.org.webrtc` 或重新编译 libwebrtc。

6. **双 PC + subscriber primary 不直观**：SFU 模型下 publisher/subscriber 分两个 PC，且 subscriber 主动协商（与普通 WebRTC P2P 相反）。新手理解成本高。

7. **部分抽象过度**：`flowDelegate` 的 `DelegateAccess` ThreadLocal 反射技巧很巧妙但难懂；`@FlowObservable` 注解处理器增加心智负担。

8. **错误处理不一致**：有的用 `Result<T>`（`sendData`），有的抛异常（`connect`），有的返回 null（`createSenderTransceiver`）。没有统一错误模型。

### 19.3 适用场景与不适用场景

**适用**：
- 需要 SFU 架构的多方实时音视频（会议、直播、语音房间）。
- 需要 Android 原生集成（不用 Flutter/React Native）。
- 需要 E2EE、DataChannel、RPC、DataStream 等高级功能。
- 团队能接受 Kotlin + Dagger + 协程栈。

**不适用**：
- 纯 P2P 通话（WebRTC P2P 更简单，不需要 SFU）。
- 极致低延迟（<50ms）场景（SFU 多一跳，且 libwebrtc jitter buffer 不可调）。
- 非 Android 平台（这是 Android 专属 SDK）。
- 需要深度定制编解码/QoS（native 不可见，改造成本高）。
- 团队只用 C++/Java 不愿学 Kotlin 协程。

### 19.4 与其他方案对比

| 方案 | 架构 | 客户端复杂度 | QoS 可调性 | 适用 |
|------|------|------------|-----------|------|
| **LiveKit Android SDK** | SFU + 双 PC | 中（Kotlin+Dagger） | 中（SDK 层有限，native 深度需改 AAR） | 多方会议/直播 |
| WebRTC 原生 SDK | P2P/SFU 可选 | 高（纯 Java/C++） | 高（直接调 native API） | 需要深度定制 |
| mediasoup 客户端 | SFU | 低（薄客户端） | 高（客户端薄，服务端可控） | 服务端可控的场景 |
| Janus + 自研客户端 | SFU | 高（自研） | 高 | 学术/定制 |
| Agora/声网 | SFU（闭源） | 低（黑盒） | 低（参数有限） | 快速上线 |

LiveKit 的定位：**开源 SFU + 工业级客户端 SDK**，介于"WebRTC 原生"（太底层）和"Agora"（太黑盒）之间。

### 19.5 一句话评价

这是一个**设计成熟、工程化程度高、扩展性好**的 SFU 客户端 SDK：分层与 DI 让它可维护，协程与 Flow 让它现代，override 点让它可扩展，native 边界让它安全；但 WebRTC 线程亲和、SDP munge 脆弱、native QoS 不可调是它的固有代价。对"用 LiveKit 做产品"是优秀选择，对"深度研究 QoS"则需穿透到 native 层。

---

## 第 20 章 工业级 QoS 音视频优化分析

> 本章专业展开：要做工业级 QoS 优化，哪些参数能调、在哪调、怎么调、是否要改 WebRTC AAR、如何设计实验。这是面向"真要在生产环境调优"的读者。

### 20.1 QoS 目标定义

实时音视频 QoS（Quality of Service）的五大目标：

| 目标 | 含义 | 衡量指标 |
|------|------|---------|
| **低延迟** | 端到端延迟小 | 采集→渲染时延（目标 <150ms 交互级） |
| **抗丢包** | 丢包时仍可听/看 | 丢包率 5%/10%/20% 下的 MOS 分 |
| **带宽自适应** | 带宽变化时平滑降级 | 码率跟随带宽的响应时间、超调 |
| **音质/画质** | 正常条件下质量高 | PESQ/Visqol（音频）、PSNR/VMAF（视频） |
| **稳定性** | 长时间不崩不卡 | 卡顿率、CPU/温度、内存 |

工业级 = 在**弱网（丢包 5-20%、抖动 50-200ms、带宽波动）**下仍保持可用，而非只看理想网络。

### 20.2 可调参数全景表（按层分类）

```
┌─────────────┬──────────────────────────────────┬──────────────┐
│ 层          │ 可调参数                          │ 在哪调        │
├─────────────┼──────────────────────────────────┼──────────────┤
│ 采集层      │ 分辨率、帧率、Camera API           │ SDK (Java)   │
│ 编码层      │ codec、maxBitrate、maxFps、        │ SDK (Java)   │
│             │ scalabilityMode、关键帧间隔、QP范围 │ + native     │
│ Simulcast   │ 层数、比例、dynacast 开关          │ SDK (Java)   │
│ 传输层      │ FEC、NACK、GCC、拥塞控制、         │ native (AAR) │
│             │ jitter buffer                     │              │
│ 音频处理    │ AEC/NS/AGC、采样率、opus bitrate、 │ SDK + native │
│             │ DTX、RED                          │              │
│ 信令层      │ 重连策略、ping 间隔                │ SDK (Java)   │
└─────────────┴──────────────────────────────────┴──────────────┘
```

### 20.3 SDK 层可调参数（给代码位置）

以下参数在 **Java/Kotlin 层**就能调，无需改 native：

#### 20.3.1 视频（`LocalVideoTrackOptions.kt` / `VideoTrackPublishOptions`）

```kotlin
// 采集参数
LocalVideoTrackOptions(
    captureParams = VideoCaptureParameter(width, height, maxFps),  // 分辨率+帧率
    position = CameraPosition.FRONT,
)

// 编码参数（VideoEncoding）
VideoEncoding(maxBitrate = 1_700_000, maxFps = 30)  // 码率+帧率上限

// 预设（已定义好，见 LocalVideoTrackOptions.kt:124）
VideoPreset169.H720  → 1280x720@30, 1.7Mbps
VideoPreset169.H360  → 640x360@30,  450Kbps
ScreenSharePresets.H1080_FPS30 → 1920x1080@30, 5Mbps

// 发布选项（VideoTrackPublishOptions）
videoEncoding, simulcast, scalabilityMode, simulcastLayers, videoCodec
```

**关键参数**：
- `maxBitrate`：决定画质上限。太低糊，太高占带宽。
- `maxFps`：帧率。视频会议 30 够，游戏/运动需 60。
- `simulcast`：开多层（low/mid/high），服务器按订阅者带宽转发对应层。
- `scalabilityMode`：SVC（单编码多层），比 simulcast 省编码器资源。
- `videoCodec`：H264（硬编兼容性好）/VP8（软编可 simulcast）/VP9（SVC 原生）/AV1（新，SVC+高效）/H265。

#### 20.3.2 Simulcast 编码层计算（`LocalParticipant.kt:818` computeVideoEncodings）

```kotlin
// SDK 自动按分辨率算 simulcast 层：
// size >= 480 → 加 low 层
// size >= 960 → 加 mid 层
// + high 层（原始）
// 每层 scaleDownBy = 当前尺寸 / 目标尺寸
```
可调：`simulcastLayers` 自定义每层 preset；`EncodingUtils.defaultSimulcastLayers` 改默认。

#### 20.3.3 dynacast（动态发布层开关）

```kotlin
RoomOptions(dynacast = true)  // 开启动态码率
// 服务器发 SubscribedQualityUpdate → setPublishingLayers
// 没人订阅 high 层就关掉 high，省带宽/CPU
```
代码：`LocalParticipant.handleSubscribedQualityUpdate`（`:1177`）、`LocalVideoTrack.setPublishingLayers`（`:321`）。

#### 20.3.4 adaptiveStream（订阅端自适应）

```kotlin
RoomOptions(adaptiveStream = true)
// RemoteVideoTrack 根据可见性/分辨率需求调订阅层
// 不可见的 track 降为最低层甚至停
```
代码：`RemoteVideoTrack.recalculateVisibility`（`:146`）。

#### 20.3.5 音频（`LocalAudioTrackOptions.kt`）

```kotlin
LocalAudioTrackOptions(
    noiseSuppression = true,   // NS
    echoCancellation = true,   // AEC
    autoGainControl = true,    // AGC
    highPassFilter = true,     // HPF
    typingNoiseDetection = true,
)
```
这些是 WebRTC native APM 的开关，SDK 层只能开/关，**不能调参数细节**（如 AGC 目标电平、AEC3 延迟估计范围）。

#### 20.3.6 重连（`DefaultReconnectPolicy.kt`）

```kotlin
DefaultReconnectPolicy(
    retryDelays = listOf(100.ms, 300.ms, ...),  // 可自定义重试间隔
    maxReconnectionTimeout = 60.seconds,        // 总超时
)
RoomOptions(reconnectPolicy = myPolicy)
```

#### 20.3.7 override 扩展点（`LiveKitOverrides`）

```kotlin
LiveKit.create(ctx, options, overrides = LiveKitOverrides(
    videoEncoderFactory = myCustomFactory,   // 自定义编码器工厂
    videoDecoderFactory = myCustomFactory,
    audioOptions = AudioOptions(audioHandler = myHandler),
    eglBase = myEglBase,
    okHttpClient = myClient,
))
```
这是 SDK 层最深的扩展点——可注入完全自定义的编解码器（如自研 H265 编码器）。

### 20.4 必须改 WebRTC AAR / native 的参数

以下参数 **SDK 层调不了**，因为它们在 libwebrtc C++ 里硬编码或由 native 配置控制：

| 参数 | 作用 | 默认 | 在哪改 |
|------|------|------|-------|
| GCC 带宽估计算法参数 | 控制码率跟随带宽的激进/保守 | GoogCc 默认 | native `GoogCcConfig` |
| FEC 强度（视频） | 前向纠错冗余比例 | 按码率自适应 | native `RtpSenderVideo` |
| NACK 重传次数/间隔 | 丢包重传策略 | native 默认 | native `RtpPacketSender` |
| Jitter buffer 上限 | 缓冲深度（延迟 vs 平滑） | 自适应 | native `VideoReceiveStream` |
| Opus in-band FEC | 音频抗丢包冗余 | 关/低 | native `AudioSendStream` |
| Opus DTX | 静音时停传省带宽 | 关 | native |
| Opus RED（冗余编码） | 音频抗丢包 | 关 | native |
| AEC3 参数 | 回声消除延迟/非线性 | 默认 | native `EchoCanceller3` |
| AGC 目标电平 | 目标音量 | -3dBFS | native `GainController` |
| 编码器 QP 范围 | 画质 vs 码率 | 自适应 | native `VideoEncoder` |
| 关键帧间隔 | I 帧频率 | 自适应 | native |

#### 20.4.1 livekit.org.webrtc 是可改的

关键事实：`livekit.org.webrtc` 是 **LiveKit 自己 fork 的 libwebrtc 封装**，native 库名 `lkjingle_peerconnection_so`（`RTCModule.kt:110`）。这意味着：

1. LiveKit 对 libwebrtc 有**源码级控制**（不像用 Google 官方 AAR 那样黑盒）。
2. 你可以**替换这个 AAR** 为自己编译的版本，改 native 参数。
3. 或通过 **Java 绑定层**注入参数（部分参数有 Java API 暴露）。

#### 20.4.2 改 AAR 的三种方法

**方法 A：替换 .so（最轻）**
- 拿 LiveKit 的 libwebrtc 源码（或 Google 的），改 C++ 参数，重新编译 `liblkjingle_peerconnection_so.so`。
- 替换 AAR 里的 `jniLibs/arm64-v8a/liblkjingle_peerconnection_so.so`。
- 适合：只改 native 常量、算法参数。

**方法 B：修改 Java 绑定（中）**
- `livekit.org.webrtc` 包是 Java 代码，可 fork 改。
- 部分参数有 Java API：`PeerConnectionFactory.Options`、`AudioProcessingFactory`、`VideoEncoder.setRates`。
- 通过 `LiveKitOverrides` 注入自定义工厂。
- 适合：改编码器选择、注入自定义处理。

**方法 C：重新编译 libwebrtc（重）**
- clone libwebrtc 源码，改 `GoogCcConfig`/`FecConfig`/`OpusConfig`，编译。
- 生成新 AAR，替换 LiveKit 的依赖。
- 适合：深度 QoS 定制（改算法本身）。
- 成本：libwebrtc 编译耗时（几小时）、版本对齐复杂。

#### 20.4.3 哪些参数有 Java 暴露（不用改 AAR）

- `PeerConnectionFactory.Options`（`RTCModule.kt:354` 可 override）：`networkIgnoreMask`、`disableEncryption`、`disableNetworkMonitor`。
- `VideoEncoder.setRateAllocation`/`setRates`：运行时调码率/帧率（`SimulcastVideoEncoderFactoryWrapper` 已包装）。
- `AudioProcessingFactory`（`RTCModule.kt:307` `CustomAudioProcessingFactory`）：可注入自定义音频处理。
- `AudioAttributes`（播放属性）：`RTCModule` 提供，可改 usage/content type。

### 20.5 具体优化方案（分音/视频）

#### 20.5.1 视频优化方案

**(1) Simulcast + SVC 联合**
- Simulcast（多编码）：兼容性好（所有 codec），但编码开销大（编 3 次）。
- SVC（单编码多层）：省编码资源，但需 VP9/AV1/H264-SVC 支持。
- **推荐**：能用 SVC 就用 SVC（`scalabilityMode = "L3T3_KEY"`），Android 硬件 VP9/AV1 支持度看机型；不支持退回 simulcast。
- 代码：`computeVideoEncodings`（`:839`）按 `isSVCCodec` 分支。

**(2) dynacast 调优**
- 开 `dynacast = true`，让服务器按订阅者需求开关层。
- 风险：层开关有延迟（信令往返），快速变化时可能抖动。
- 调优：`setPublishingLayers` 的 debounce 可调（目前无参数，需改代码）。

**(3) backup codec（备用编码）**
- 主 codec（如 VP9）不通时自动发 H264 备用。
- 代码：`publishAdditionalCodecForTrack`（`LocalParticipant.kt:1203`）、`isBackupCodec`。
- 适合：跨机型兼容性保障。

**(4) 编码器选择**
- H264：硬编兼容性最好，但不支持 SVC（只能 simulcast）。
- VP8：软编可 simulcast，但耗 CPU。
- VP9：SVC 原生，软编为主，高端机有硬编。
- AV1：最新，SVC + 高效，但 Android 硬编支持少（仅新机型）。
- **推荐**：会议场景 VP9（SVC）优先，退回 H264；直播场景 H264（硬编省电）。
- 调法：`VideoTrackPublishOptions.videoCodec`，或 `sortVideoCodecPreferences`。

**(5) 码率/帧率**
- 弱网降码率优先于降帧率（保持流畅）。
- 静态场景（PPT 共享）降帧率（3-5fps）保清晰。
- 代码：`ScreenSharePresets.H360_FPS3`（3fps）就是为屏幕共享设计。

#### 20.5.2 音频优化方案

**(1) Opus in-band FEC**（抗丢包关键）
- 编码时加冗余，丢包可恢复。SDK 层无开关，**必须改 native**。
- 改法：`AudioSendStream::Config` 的 `opus.fec_enabled = true`。
- 代价：+20-30% 码率，值得。

**(2) Opus DTX**（静音省带宽）
- 不说话时停传，省 60%+ 带宽。
- 改法：`opus.dtx_enabled = true`。
- 代价：恢复有几十 ms 延迟，会议可接受。

**(3) Opus RED**（冗余编码，抗丢包更强）
- 把前一帧附在当前帧，丢一帧仍可恢复。
- 改法：`opus.red_enabled = true`（需 opus 1.12+）。
- 代价：+50% 码率，弱网值得。

**(4) AEC3 调参**
- WebRTC 的 AEC3 默认对手机扬声器回声处理一般。
- 改法：调 `EchoCanceller3Config` 的 `delay.delay_headroom_samples`、`suppress_nonlinear_mode`。
- 需改 native。

**(5) AGC 目标电平**
- 默认 -3dBFS 可能偏高（削波）或偏低（听不清）。
- 改法：`GainController.target_level_dbfs`，会议建议 -9 ~ -6。

**(6) 采样率/声道**
- Opus 默认 48kHz 单声道，足够。
- 音乐场景可立体声 + 64kbps，但带宽翻倍。

**(7) AudioProcessor 注入**
- `AudioProcessingController.capturePostProcessor`（`AudioProcessingController.kt:30`）可注入自定义降噪（如 RNNoise 深度学习）。
- 这是 SDK 层能做的音频增强，不改 native。

### 20.6 实验设计

工业级调优不能拍脑袋，要**量化实验**。

#### 20.6.1 指标体系

| 维度 | 指标 | 工具 |
|------|------|------|
| 音质 | MOS 分（1-5）、PESQ、ViSQOL | ITU-T P.862/P.863，开源 visqol |
| 画质 | PSNR、SSIM、VMAF | ffmpeg, libvmaf |
| 延迟 | 端到端延迟（采集→渲染） | 打时间戳日志 |
| 抗丢包 | 丢包率下的 MOS 退化曲线 | 网络仿真器 |
| 流畅度 | 卡顿率、帧率稳定性 | 统计 RTP 到达间隔 |
| 资源 | CPU%、温度、内存、电量 | Android Profiler, battery historian |
| 带宽 | 实际码率 vs 目标、GCC 响应时间 | WebRTC getStats() |

#### 20.6.2 网络仿真

构造受控弱网环境：
- **ATC（Android Traffic Control）**：root 后用 `tc netem` 加丢包/延迟/抖动。
- **Clumsy（Windows）/ Network Link Conditioner（Mac）**：图形化。
- **Linux tc**：`tc qdisc add dev eth0 root netem loss 10% delay 100ms jitter 20ms`。

典型测试矩阵：
```
网络档位：
  优：0% 丢包, 20ms 延迟, 10Mbps
  中：2% 丢包, 50ms 延迟, 2Mbps
  差：5% 丢包, 100ms 延迟, 1Mbps
  极差：10-20% 丢包, 200ms 延迟, 500Kbps, 抖动 50ms
  切换：带宽突变（10M→500K→10M）
```

#### 20.6.3 A/B 测试框架

- **对照组**：默认参数。
- **实验组**：调参后。
- 样本量：每档网络至少 10 次跑 5 分钟，取均值+方差。
- 真机 vs 模拟器：**必须真机**（模拟器无真实硬编/网络）。

#### 20.6.4 自动化

- WebRTC 自带 `video_quality_loopback_test` / `audio_quality_loopback_test`（在 native 测试套件）。
- 可集成到 CI：每次改 native 跑一遍，对比基线。
- 输出：MOS/PSNR/延迟报告，回归告警。

#### 20.6.5 真机矩阵

- 低端机（骁龙 4 系/联发科 P 系）：验 CPU/温度。
- 高端机（骁龙 8 系）：验画质上限。
- Android 版本：8.0/10/12/14（覆盖 workaround 边界）。
- 网络：WiFi/4G/5G/弱 WiFi。

### 20.7 调参决策树

```
场景: 视频会议（多人, 交互）
├─ 编码: VP9 + SVC(L3T3) → 退回 VP8 simulcast → 退回 H264
├─ dynacast: 开
├─ adaptiveStream: 开
├─ 码率: 360p 450K, 720p 1.7M
└─ 弱网: 降码率保帧率(15fps), 关 high 层

场景: 直播（1对多, 单向）
├─ 编码: H264 硬编(省电) + simulcast
├─ dynacast: 按需
├─ 码率: 1080p 3M
└─ 弱网: 降分辨率

场景: 屏幕共享(PPT)
├─ 编码: VP8/VP9(文字清晰) 
├─ 帧率: 3-5fps(静态)
├─ 码率: 2-5M(高清晰度)
└─ ScreenSharePresets.H1080_FPS15

场景: 语音通话(纯音频)
├─ Opus FEC: 开(改 native)
├─ Opus DTX: 开
├─ Opus RED: 弱网开
├─ AEC/NS/AGC: 全开
└─ 码率: 32-64kbps

场景: 弱网(丢包10%+)
├─ 视频: 降 360p, 关 simulcast high, FEC 开
├─ 音频: FEC+RED, 降 16kbps
├─ 重连: 激进重试(短间隔)
└─ jitter: 增大 buffer(改 native)
```

### 20.8 风险与回滚

1. **改 native 的风险**：libwebrtc 改错可能导致崩溃/泄漏，需充分回归。
2. **机型碎片化**：某参数在 A 机好、B 机差，需按机型下发（按 `Build.MODEL` 分组）。
3. **A/B 灰度**：新参数先灰度 5% 用户，观察 MOS/卡顿率，再全量。
4. **回滚机制**：参数通过服务端下发（而非写死客户端），可随时回滚。
5. **监控**：线上采集 MOS/卡顿率/延迟分布，异常告警。

> **C++ 读者总结**：QoS 优化分两层——SDK 层（Java）调采集/编码/Simulcast/重连参数，够用 80%；深度优化（FEC/GCC/jitter/opus）必须穿透到 `livekit.org.webrtc` 的 native 层，通过改 AAR 或重编译 libwebrtc。工业级做法是"参数服务端下发 + 网络仿真实验 + 真机矩阵 + A/B 灰度 + 线上监控"闭环。

---

## 第 21 章 Kotlin/Java ↔ C++ 交互方式专题

> 你有 C/C++ 经验，这章把"Java/Kotlin 怎么调到 C++"讲透。本 SDK 的所有音视频核心都在 C++（libwebrtc），理解 JNI 边界是深度优化的前提。

### 21.1 JNI 基础（给 C++ 读者）

JNI（Java Native Interface）是 Java 调 C/C++ 的标准桥梁。核心模式：

```java
// Java 侧
public class PeerConnection {
    private long nativePtr;  // 持有 C++ 对象指针（cast 成 long）
    
    public native void createOffer();  // native 方法
}
```

```cpp
// C++ 侧（JNI 实现）
JNIEXPORT void JNICALL Java_org_webrtc_PeerConnection_createOffer(JNIEnv* env, jobject thiz) {
    jlong ptr = env->GetLongField(thiz, nativePtrField);
    auto* pc = reinterpret_cast<webrtc::PeerConnectionInterface*>(ptr);  // long 还原指针
    pc->CreateOffer(...);  // 调真正的 C++ 对象
}
```

**三个关键点**：
1. **`long nativePtr`**：Java 用 long 存 C++ 指针（64 位够存任意指针）。这是 Java 持有 C++ 对象的唯一方式。
2. **`native` 方法**：声明了但不实现，由 JVM 在 `.so` 里找 `Java_包名_方法名` 符号。
3. **`JNIEnv`**：每次 native 调用都传入，用于 Java↔C++ 类型转换、调 Java 方法。

> **C++ 对照**：JNI ≈ C++ 里用 `void*` 持有不透明对象 + 一组 `extern "C"` 接口操作它。`long nativePtr` ≈ `void*`。

### 21.2 org.webrtc 的 JNI 模式

WebRTC 的 Java 绑定遵循固定模式：

```
Java 对象                      C++ 对象
┌──────────────┐               ┌──────────────────┐
│PeerConnection│──nativePtr──►│PeerConnectionInterface│
│ (Java)       │              │ (C++)             │
└──────────────┘              └──────────────────┘
   │ 方法调用                       │
   ▼                              │
JNI 入口函数                       │
   │                              │
   ▼                              │
GetLongField(nativePtr)──────────►│
   │                              │
   ▼                              ▼
reinterpret_cast<CppObj*>(ptr)->method()
```

**生命周期**：
- Java 对象构造时，native 层 `new` C++ 对象，指针存进 `nativePtr`。
- Java 对象 `dispose()` 时，native 层 `delete` C++ 对象，置 `nativePtr = 0`。
- Java GC 不直接管 C++ 对象——**必须手动 dispose**，否则内存泄漏。这就是 `PeerConnectionFactoryManager.dispose()` 必须在 RTC 线程调的原因（`RTCModule.kt:373`）。

**回调（C++ → Java）**：
```cpp
// C++ 触发回调
void OnIceCandidate(const IceCandidateInterface* candidate) {
    JNIEnv* env = AttachCurrentThread();  // native 线程要 attach 到 JVM
    jobject java_observer = ...;  // 预先保存的 Java Observer 引用
    env->CallVoidMethod(java_observer, onIceCandidateMethod, ...);
}
```
native 线程调 Java 方法必须先 `AttachCurrentThread`（把 native 线程挂到 JVM）。这就是为什么 WebRTC 回调可能来自任意 native 线程——SDK 用 `RTCThreadUtils` 把回调投递回 RTC 线程处理。

### 21.3 一帧视频编码的完整跨语言调用栈

从 Camera 采集到 UDP 发出，跨语言边界多次：

```
① 采集（Java 触发 → native 回调）
  Camera2 API (Java ⑤)
    → onImageAvailable
    → SurfaceTextureHelper (Java ⑤, EGL 线程)
    → VideoCapturer.onFrameCaptured (Java)
    → native OnFrame  ─────[JNI 上行]─────►  JavaVideoSource::OnFrame (C++ ④)

② 处理（native 内部）
  VideoTrackSource::OnFrame (C++)
    → VideoBroadcaster::OnFrame
    → VideoStreamEncoder::OnFrame
    → (可选) VideoProcessor (Java, 通过 JNI 回调)
    → EncoderStreamFactory 选编码器

③ 编码（Java 转发 → native 执行）
  SimulcastEncoderAdapter::Encode (C++)
    → 子编码器 Encode
    → MediaCodecVideoEncoder::Encode (C++)
      ─────[JNI 下行]─────►  Java MediaCodec 封装 (⑤)
        → MediaCodec.queueInputBuffer (Android API)
      ◄────[返回]────
    → MediaCodec 输出编码帧
    → VideoEncoder.Callback.onEncodedFrame ──[JNI 上行]──►  Java 回调 (⑤)

④ RTP 打包发送（native 内部，Java 不参与）
  VideoSendStream::OnEncodedImage (C++)
    → RtpSenderVideo::SendVideo
    → RTP 打包 + FEC + NACK
    → SRTP 加密
    → PacedSender → AsyncPacketSocket → UDP
```

**跨语言边界**（JNI 调用）发生在：
- ① 采集帧从 Java 传到 native（`OnFrame`）
- ③ 编码时 native 调 Java 的 MediaCodec（硬编走 Android API）
- ③ 编码完成回调从 native 到 Java（`onEncodedFrame`）
- 渲染时 native 解码帧传到 Java VideoSink

软编（libvpx）全程在 native，不跨 JNI；硬编（MediaCodec）必须跨 JNI 调 Android API。

### 21.4 线程跨越：native 线程回调 Java

WebRTC 内部有多个 native 线程（编码线程、RTP 线程、解码线程、网络线程）。当它们回调 Java 时：

```cpp
// native 线程
void OnFrameFromDecoder(const VideoFrame& frame) {
    JNIEnv* env = AttachCurrentThread();  // ① attach
    // ② 构造 Java VideoFrame 对象（nativeHandle 指向 C++ frame）
    jobject java_frame = CreateJavaVideoFrame(env, frame);
    // ③ 调 Java VideoSink.onFrame
    env->CallVoidMethod(java_sink, onFrameMethod, java_frame);
    // ④ Detach（或保持 attach 供后续复用）
}
```

**问题**：native 线程 attach 到 JVM 后，回调可能在**任意线程**执行。如果 Java 侧直接操作 UI 或 PC，会崩。所以 SDK 的 `PeerConnectionTransport` 用 `launchRTCIfNotClosed`（`PeerConnectionTransport.kt:360`）把所有 native 回调投递回 **RTC 单线程**处理，保证线程安全。

```
native 编码线程 ──JNI──► Java 回调 ──投递──► RTC 单线程 ──► 业务逻辑
native 解码线程 ──JNI──► Java VideoSink ──投递──► 渲染线程
native 网络线程 ──JNI──► Java Observer ──投递──► RTC 单线程
```

> **C++ 对照**：这就像 C++ 里多个工作线程 `post` 任务到主线程执行。`AttachCurrentThread` ≈ 把 `std::thread` 注册到某个运行时。SDK 的 RTC 单线程 ≈ 单线程的 `asio::io_context`。

### 21.5 修改 native 行为的途径

| 途径 | 难度 | 能改什么 | 本 SDK 适用 |
|------|------|---------|-----------|
| Java 绑定层参数 | 低 | 有 Java API 暴露的参数 | `PeerConnectionFactory.Options`、`setRates` |
| `LiveKitOverrides` | 低 | 注入自定义工厂/处理器 | 编码器/解码器/音频处理/ADM |
| 自定义 `VideoProcessor` | 中 | 采集后编码前处理帧 | `ScaleCrop`/`NoDrop`/自研 |
| 自定义 `AudioProcessorInterface` | 中 | 采集后/播放前处理 PCM | 降噪/增益 |
| 改 `livekit.org.webrtc` Java | 中 | 改 Java 绑定逻辑 | 编码器选择、回调路由 |
| 替换 `.so` | 高 | 改 native 常量/算法参数 | GCC/FEC/opus 配置 |
| 重编译 libwebrtc | 很高 | 改算法本身 | 自研带宽估计/抗丢包 |

**最常用的深度途径**：替换 `.so`。因为 `livekit.org.webrtc` 是 LiveKit fork 的，native 库 `lkjingle_peerconnection_so` 可被替换。流程：
1. 拿 libwebrtc 源码（LiveKit 的 fork 或 Google 的）。
2. 改 C++ 配置（如 `audio_send_stream_config.opus.fec_enabled = true`）。
3. 编译生成 `liblkjingle_peerconnection_so.so`。
4. 替换 AAR 的 `jniLibs/<abi>/` 下对应文件。
5. Java 绑定层不变（API 兼容）。

> **C++ 读者总结**：本 SDK 的 C++ 交互全在 `org.webrtc` 包，模式是"`long nativePtr` + `native` 方法 + `AttachCurrentThread` 回调"。SDK 层只管编排，真正的音视频处理在 native。要深度优化（QoS 算法参数），要么用 `LiveKitOverrides` 注入自定义实现，要么替换 `livekit.org.webrtc` 的 `.so`。Java 层永远看不到 native 内部状态，只能通过回调感知。

---

## 第 22 章 总结与速查

### 22.1 全文章节索引

**第一部分（第 0-15 章）**：
- 第 0 章 阅读指南与前置知识（Kotlin/Java/Android 给 C++ 读者）
- 第 1 章 总览：工程定位、模块组成、入口
- 第 2 章 分层架构与文件组织
- 第 3 章 依赖注入（Dagger）与对象图
- 第 4 章 连接生命周期与状态机
- 第 5 章 信令层 SignalClient
- 第 6 章 媒体传输层 RTCEngine + PeerConnectionTransport
- 第 7 章 参与者模型 Participant
- 第 8 章 轨道模型 Track 体系
- 第 9 章 完整业务流程：音频发布与订阅
- 第 10 章 完整业务流程：视频发布与订阅
- 第 11 章 数据通道与数据流（DataChannel/DataStream/RPC）
- 第 12 章 事件体系
- 第 13 章 端到端加密 E2EE
- 第 14 章 音频设备与音频处理子系统
- 第 15 章 工程特点总结与 Android SDK 分析方法论

**第二部分（第 16-22 章）**：
- 第 16 章 网络交互深入：信令、媒体与 WebRTC 内部
- 第 17 章 Kotlin/Java 高级抽象给 C++ 读者（举例展开）
- 第 18 章 图集：分层图、类图、交互图
- 第 19 章 工程设计评价：特点、优劣
- 第 20 章 工业级 QoS 音视频优化分析
- 第 21 章 Kotlin/Java ↔ C++ 交互方式专题
- 第 22 章 总结与速查

### 22.2 关键文件速查表

| 文件 | 作用 | 关键行 |
|------|------|-------|
| `LiveKit.kt` | 入口 | `create()` |
| `room/Room.kt` | 主门面 | connect:461, onJoinResponse:666, handleDisconnect:999 |
| `room/RTCEngine.kt` | 引擎 | configure:279, negotiatePublisher:716, sendData:733, reconnect:521 |
| `room/SignalClient.kt` | 信令 | connect:167, handleSignalResponseImpl:743, ping:887 |
| `room/PeerConnectionTransport.kt` | PC 封装 | negotiate:146, createAndSendOffer:155, addIceCandidate:105 |
| `room/participant/Participant.kt` | 基类 | updateFromInfo:438 |
| `room/participant/LocalParticipant.kt` | 本地参与者 | publishTrackImpl:631, computeVideoEncodings:818, handleSubscribedQualityUpdate:1177 |
| `room/track/LocalVideoTrack.kt` | 本地视频 | createTrack:498, setPublishingLayers:321 |
| `room/track/LocalAudioTrack.kt` | 本地音频 | createTrack:222, prewarm:104 |
| `room/track/RemoteVideoTrack.kt` | 远端视频 | recalculateVisibility:146 |
| `room/track/LocalVideoTrackOptions.kt` | 视频参数/预设 | VideoPreset169:124 |
| `room/track/LocalAudioTrackOptions.kt` | 音频参数 | AEC/NS/AGC 开关 |
| `util/FlowDelegate.kt` | @FlowObservable 机制 | flowDelegate, DelegateAccess |
| `dagger/LiveKitComponent.kt` | DI 组件 | roomFactory() |
| `dagger/RTCModule.kt` | native 初始化 | libWebrtcInitialization:102, audioModule:154, peerConnectionFactoryManager:347 |
| `webrtc/SimulcastVideoEncoderFactoryWrapper.kt` | 编码器工厂 | FallbackFactory:80, StreamEncoderWrapper:110 |
| `webrtc/peerconnection/RTCThreadUtils.kt` | RTC 线程 | executeOnRTCThread |
| `audio/AudioSwitchHandler.kt` | 音频路由 | start/stop, selectDevice |
| `audio/CommunicationWorkaround.kt` | 通信模式保活 | onStateChanged:139 |
| `audio/PreconnectAudioBuffer.kt` | 预连接音频 | sendAudioData:130 |
| `e2ee/E2EEManager.kt` | E2EE 入口 | addPublishedTrack:140, addSubscribedTrack:106 |
| `events/BroadcastEventBus.kt` | 事件总线 | MutableSharedFlow |
| `events/RoomEvent.kt` | 事件类型 | sealed class |
| `room/network/DefaultReconnectPolicy.kt` | 重连策略 | DEFAULT_RETRY_DELAYS:57 |
| `RoomOptions.kt` | 房间配置 | adaptiveStream, dynacast, reconnectPolicy |

### 22.3 关键参数速查表

| 参数 | 位置 | 默认 | 作用 |
|------|------|------|------|
| `adaptiveStream` | RoomOptions | false | 订阅端自适应分辨率 |
| `dynacast` | RoomOptions | false | 动态发布层开关 |
| `reconnectPolicy` | RoomOptions | DefaultReconnectPolicy | 重连重试间隔 |
| `maxBitrate` | VideoEncoding | 按预设 | 视频码率上限 |
| `maxFps` | VideoEncoding | 按预设 | 视频帧率上限 |
| `simulcast` | VideoTrackPublishOptions | 按场景 | 多编码层 |
| `scalabilityMode` | VideoTrackPublishOptions | null | SVC 模式 |
| `videoCodec` | VideoTrackPublishOptions | 按场景 | H264/VP8/VP9/AV1 |
| `echoCancellation` | LocalAudioTrackOptions | true | 回声消除 |
| `noiseSuppression` | LocalAudioTrackOptions | true | 降噪 |
| `autoGainControl` | LocalAudioTrackOptions | true | 自动增益 |
| `captureParams` | LocalVideoTrackOptions | H720 | 采集分辨率/帧率 |
| `retryDelays` | DefaultReconnectPolicy | [100,300,...] | 重连延迟序列 |
| `maxReconnectionTimeout` | DefaultReconnectPolicy | 60s | 重连总超时 |

### 22.4 调试技巧

**开 WebRTC native 日志**：
```kotlin
LiveKit.enableWebRTCLogging = true  // 开 libwebrtc 详细日志
// RTCModule.kt:111 的 setInjectableLogger 会把 native 日志转 LKLog
```

**开 SDK 日志**：
```kotlin
// LKLog 默认按级别输出，设环境变量或调 LoggingLevel
```

**抓包看 SDP/RTP**：
- 用 Wireshark 抓 UDP（媒体）+ WebSocket（信令）。
- 信令是 protobuf，用 `protoc --decode` 解析。
- SDP 在 `SignalRequest.offer/answer` 里，看协商结果。
- RTP 流可看 SSRC/PT/序列号/时间戳，验证 FEC/NACK。

**看 SDP**：
- 在 `PeerConnectionTransport.createAndSendOffer`（`:155`）打断点，看 munge 前后 SDP。
- 或在 `LKLog` 里打 `sdpOffer.description`。

**看线程**：
- `Thread.currentThread().name` 打日志，确认是否在 RTC 线程（`LK_RTC_THREAD_`）。
- native 回调的线程名通常是 `Thread-<n>` 或 libwebrtc 命名（`EncoderThread`/`DecodingThread`）。

**性能分析**：
- Android Studio Profiler 看 CPU/内存/网络。
- `peerConnection.getStats()` 拿 RTC 统计（码率/丢包/RTT/jitter）。
- `room.events.collect { ... }` 监听 `ConnectionQualityChanged`。

**常见崩溃定位**：
- `IllegalStateException: ... on wrong thread` → RTC 线程违规，用 `executeOnRTCThread` 包裹。
- native crash（`SIGSEGV`）→ 看 tombstone，多为 PC 操作跨线程或 dispose 后访问。
- `OutOfMemoryError` → 检查 track 是否泄漏（未 dispose）、SurfaceTexture 未释放。

---

> 全文完。共 22 章（第 0-22 章），分两部分：第一部分（0-15）覆盖架构与业务流，第二部分（16-22）覆盖网络深入、抽象讲解、图集、工程评价、QoS 优化、JNI 交互、速查。









