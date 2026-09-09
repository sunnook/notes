# LiveKit Android SDK — 项目概览与初始化流程

> 目标读者：有 C/C++ 经验但对 Android/Kotlin 不熟悉的开发者。
> 基于实际代码阅读，用 C++ 类比解释 Kotlin 特有语法和 SDK 架构。

---

## 目录结构

```
client-sdk-android-main/
├── livekit-android-sdk/          # ★ 核心 SDK 模块
│   └── src/main/java/io/livekit/android/
│       ├── LiveKit.kt            # 入口单例，create() 创建 Room
│       ├── Room.kt               # 核心类，管理连接/参与者/Track/事件
│       ├── RTCEngine.kt          # 信令通信 + WebRTC PeerConnection 传输
│       ├── ConnectOptions.kt     # 连接参数
│       ├── RoomOptions.kt        # Room 配置
│       ├── audio/                # 音频处理（AudioHandler/AudioSwitch/AudioProcessing）
│       ├── dagger/               # Dagger 2 依赖注入组件
│       ├── e2ee/                 # 端到端加密
│       ├── events/               # 事件系统（RoomEvent/ParticipantEvent/TrackEvent）
│       ├── room/
│       │   ├── participant/      # LocalParticipant / RemoteParticipant
│       │   ├── track/            # Track 定义（音频/视频/数据）
│       │   ├── rpc/              # RPC 客户端/服务端管理
│       │   ├── datastream/       # 数据流收发
│       │   ├── network/          # 网络回调 + 重连策略
│       │   └── metrics/          # RTC 指标收集
│       ├── token/                # 认证 token 管理
│       ├── webrtc/               # WebRTC 封装（PeerConnection/DataChannel）
│       └── util/                 # 工具类（Flow扩展/协程/日志等）
│
├── livekit-android-camerax/      # CameraX 摄像头采集集成
├── livekit-android-track-processors/  # 帧处理插件（虚拟背景 OpenGL）
├── livekit-android-test/         # 测试辅助库
├── livekit-lint/                 # 自定义 Lint 规则
├── livekit-detekt-rules/         # 自定义 Detekt 代码风格检查
├── sample-app/                   # 完整示例应用
├── sample-app-compose/           # Compose UI 示例
├── sample-app-basic/             # 简化示例
├── sample-app-record-local/      # 本地录制示例
├── examples/
│   ├── screenshare-audio/        # 屏幕共享音频示例
│   └── virtual-background/       # 虚拟背景示例
└── docs/
    └── client-sdk-android-design-analysis.md  # 中文设计文档(1992行)
```

---

## 录制与播放机制

### 核心结论：底层是 WebRTC，不是 FFmpeg

该 SDK **完全依赖 WebRTC 原生能力**，没有集成 FFmpeg。

### 录制

SDK **本身不提供内置录制器**。录制是应用层实现，位于 `sample-app-record-local`：

- 通过 `JavaAudioDeviceModule` 的 `setSamplesReadyCallback` 获取**原始 PCM 音频样本**
- 通过 `LocalVideoTrack.addRenderer()` 附加 `VideoFileRenderer` 获取视频帧
- `VideoFileRenderer` 内部使用 Android 原生 `MediaCodec`（H.264 编码）+ `MediaMuxer`（MP4 封装）

```kotlin
// 录制流程
val videoFileRenderer = VideoFileRenderer(
    file.absolutePath,
    EglBase.create().eglBaseContext,
    true
)
val track = localParticipant.getTrackPublication(Track.Source.CAMERA)?.track as LocalVideoTrack
track.addRenderer(videoFileRenderer)
```

SDK 的角色只是**提供视频帧**，不负责编码和复用。

### 播放

- 视频：`SurfaceViewRenderer` / `TextureViewRenderer` 直接渲染 WebRTC 的 `VideoFrame`，GPU 加速
- 音频：`AudioDeviceModule` + `AudioTrack` 播放

---

## 从按钮点击到房间创建

完整的调用链：

```
用户点击 Connect 按钮 (MainActivity)
  → 启动 CallActivity，传入 url 和 token
  → CallActivity.onCreate()
    → 创建 CallViewModel(url, token, ...)
      → CallViewModel 构造函数内: LiveKit.create()  ← 创建 Room 对象
  → CallActivity 注册按钮点击事件: "Join Room"
    → 用户点击 "Join Room"
      → lifecycleScope.launch { connectToRoom() }  ← 协程启动
        → room.connect(url, token)  ← 进入 SDK
```

---

## LiveKit.create() — 工厂模式

```kotlin
fun create(
    appContext: Context,
    options: RoomOptions = RoomOptions(),
    overrides: LiveKitOverrides = LiveKitOverrides(),
): Room {
    val ctx = appContext.applicationContext

    if (ctx !is Application) {
        LKLog.w { "Application context was not found, this may cause memory leaks." }
    }

    val component = DaggerLiveKitComponent.factory().create(ctx, overrides)
    val room = component.roomFactory().create(ctx)
    room.setRoomOptions(options)

    return room
}
```

### Kotlin 语法解析（C++ 类比）

| Kotlin 代码 | C++ 类比 | 说明 |
|---|---|---|
| `ctx !is Application` | `dynamic_cast<Application*>(ctx) == nullptr` | 类型检查 + 智能转换。过了这行后，编译器自动把 `Context` 提升为 `Application` |
| `DaggerLiveKitComponent.factory()` | 编译期生成的工厂类 | Dagger 在编译期生成依赖注入代码，保证全局单例 |
| `roomFactory().create(ctx)` | `Room::factory()->create(ctx)` | Room 构造函数需要运行时参数 (context) + DI 参数，用工厂模式 |
| `RoomOptions()` | `RoomOptions{}` | Kotlin 默认参数，无参调用省略 `()` |

**Dagger 做的事情：** 通过 `@Singleton`、`@Module`、`@Inject` 等注解，在编译期生成代码管理所有依赖的生命周期。不需要手动 new `PeerConnectionFactory`、`EglBase` 等重型对象。

**`Room` 的构造函数（`@AssistedInject`）：**

```kotlin
class Room @AssistedInject constructor(
    @Assisted private val context: Context,      // 运行时传，DI 无法注入
    internal val engine: RTCEngine,               // Dagger 注入
    private val eglBase: EglBase,                 // Dagger 注入
    localParticipantFactory: LocalParticipant.Factory,
    ...
)
```

---

## Room.connect() — 逐行详解

```kotlin
suspend fun connect(url: String, token: String, ...) = coroutineScope {
    // 第1步：快速状态检查（无锁）
    if (state != State.DISCONNECTED) throw IllegalStateException(...)
    
    // 加锁，保护临界区
    stateLock.withLock {
        // 双重检查（防竞态条件）
        if (state != State.DISCONNECTED) throw IllegalStateException(...)
        
        // 如果有旧协程，先取消并等待它结束
        if (::coroutineScope.isInitialized) {
            coroutineScope.cancel()
            job.join()
        }
        
        state = State.CONNECTING
        connectOptions = options
        
        // 创建新的协程作用域（SupervisorJob: 子协程A失败不影响B）
        coroutineScope = CoroutineScope(defaultDispatcher + SupervisorJob())
        
        roomOptions = getCurrentRoomOptions()
        
        // 初始化本地参与者（发布麦克风/相机的人）
        localParticipant.reinitialize(options)
        setupLocalParticipantEventHandling()
        
        // 如果开启了端到端加密，创建 E2EEManager
        if (roomOptions.e2eeOptions != null) {
            e2eeManager = e2EEManagerFactory.create(keyProvider).apply {
                setup(this@Room) { event ->
                    coroutineScope.launch { emitWhenConnected(event) }
                }
            }
            engine.e2EEManager = e2eeManager
        }
    }  // 锁释放
    
    // 锁外面启动真正的连接任务（IO 线程）
    val connectJob = coroutineScope.launch(ioDispatcher) {
        engine.join(url, token, options, roomOptions)
        // 配置网络回调、自动开启麦克风/相机、启动遥测采集
    }
    
    connectJob.join()  // 挂起等待连接完成
    
    // 如果连接失败，抛出异常
    error?.let { throw it }
}
```

### Kotlin 关键语法对照表

| Kotlin | C++ 类比 | 说明 |
|---|---|---|
| `suspend fun` | C++20 `co_await` 的 Kotlin 版 | 可挂起函数，调用者需用协程包裹 |
| `= coroutineScope { }` | RAII 作用域块，等价于启动子线程并 `join()` | 挂起直到所有内部 `launch` 的子协程完成 |
| `stateLock.withLock { }` | `std::unique_lock<std::mutex> lock(stateLock)` | 互斥锁，Kotlin 扩展函数实现 |
| `::coroutineScope.isInitialized` | `coroutineScope.has_value()` (`std::optional`) | 检查 `lateinit var` 是否已赋值 |
| `lateinit var coroutineScope: CoroutineScope` | `std::optional<CoroutineScope> coroutineScope` | 延迟初始化，不立即赋值 |
| `SupervisorJob()` | 独立子线程组，子线程A失败不kill B | 普通 Job 会级联 cancel，Supervisor 不会 |
| `defaultDispatcher` | 单线程/少量线程池 | 用于轻量同步任务 |
| `ioDispatcher` | 线程池（默认线程数 = CPU核数） | 用于 IO 密集型任务（网络、文件） |

### 状态机

```
DISCONNECTED → CONNECTING → CONNECTED / RECONNECTING → DISCONNECTED
```

- `DISCONNECTED`：初始状态，或连接失败后
- `CONNECTING`：正在握手
- `CONNECTED`：已成功加入房间
- `RECONNECTING`：网络断开，正在尝试恢复

---

## 进入房间发起通话的完整流程

```
[入口] LiveKit.create(context, options, overrides)
   ↓
[Dagger] DaggerLiveKitComponent.create()
   → 初始化 WebRTC 底层 (PeerConnectionFactory, EglBase, AudioDeviceModule)
   → 注入所有依赖
   ↓
[创建] component.roomFactory().create(context)
   → 创建 Room 实例，注册事件处理器
   ↓
[用户操作] room.connect(url, token)

=== Room.connect() ===
state = CONNECTING
coroutineScope = new SupervisorJob()
localParticipant.reinitialize(options)
   ↓
engine.join(url, token, options, roomOptions)  // 核心

=== RTCEngine.join() ===
client.join() — 建立 WebSocket 信令连接
  → 发送 JoinRequest
  → 收到 JoinResponse
   ↓
configure(joinResponse) — 创建两个 PeerConnection：
  → Publisher PeerConnection（发送端）
  → Subscriber PeerConnection（接收端）
  → 配置 ICE、SDP 等
   ↓
negotiatePublisher() — 发起 Offer → 服务器 Answer → SDP 交换
   ↓
Room 状态变为 CONNECTED
   ↓
localParticipant.setMicrophoneEnabled(true)  // 自动开启
localParticipant.setCameraEnabled(true)
```

---

## 关键文件索引

| 文件 | 作用 | 阅读建议 |
|------|------|----------|
| `LiveKit.kt` | 入口单例，`create()` | ★ 先读，100行 |
| `Room.kt:461` | `connect()` 方法 | ★ 连接流程总调度 |
| `RTCEngine.kt:235` | `join()` 方法 | ★ 信令握手 + PeerConnection 创建 |
| `RTCEngine.kt:279` | `configure()` 方法 | 创建 Publisher/Subscriber |
| `SignalClient.kt` | WebSocket 信令客户端 | 了解信令协议细节 |
| `LocalParticipant.kt` | 本地发布 Track | 麦克风/相机控制 |
| `CallViewModel.kt:97` | 示例中创建 Room | 实际使用示例 |
| `CallViewModel.kt:258` | `connectToRoom()` | 实际连接流程 |
| `VideoFileRenderer.java` | 录制实现 | MediaCodec + MediaMuxer |

---

## Kotlin 快速入门（C++ 开发者视角）

### 数据类

```kotlin
data class Person(var name: String, var age: Int)
// 自动生成 equals, hashCode, toString, copy
// C++ 类比：struct + 自动生成工具函数
```

### 密封类

```kotlin
sealed class Result {
    object Success : Result()
    data class Error(val msg: String) : Result()
}
// C++ 类比：enum 的广义版，可携带数据，编译期穷举检查
```

### 挂起函数

```kotlin
suspend fun connect(url: String, token: String) = coroutineScope {
    engine.join(url, token)  // 可挂起，不阻塞线程
}
// C++ 类比：C++20 co_await / generator
```

### 属性委托

```kotlin
var state: State by flowDelegate(State.DISCONNECTED) { new, old ->
    // 值变化时回调
}
// C++ 类比：property getter/setter hook
```

### 扩展函数

```kotlin
fun Lock.withLock(body: () -> Unit) {
    lock()
    try { body() } finally { unlock() }
}
// C++ 类比：RAII scope guard（如 gsl::finally）
```
