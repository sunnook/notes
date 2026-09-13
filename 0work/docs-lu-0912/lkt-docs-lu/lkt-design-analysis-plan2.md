# LiveKit Android SDK 设计分析 — 补充章节撰写规划（第二轮）

> 本文档是 `docs-lu/lkt-anaysis.md` 的**补充章节**大纲。原则：**不删现有内容，只追加**。在原文末尾新增第 16-22 章，并补充若干分层图/类图到合适位置。

## 读者画像（不变）
- 有 C/C++ 经验，对 Kotlin/Java/Android 高级抽象（依赖注入、委托、注入等）不熟
- 需要更多**图**（分层图、类图、时序图、数据流图）来直观理解
- 关心**网络相关**（信令、媒体、WebRTC 内部）的完整流程
- 想做**工业级 QoS 音视频优化**，需要知道调参空间、是否要改 WebRTC AAR、如何设计实验

## 补充章节大纲（追加到 lkt-anaysis.md 末尾）

### 第 16 章 网络交互深入：信令、媒体与 WebRTC 内部
**目标：把"涉及网络"的部分彻底展开。**
- 16.1 两条网络通道总览：信令通道（WebSocket）vs 媒体通道（SRTP over ICE/DTLS）
  - 一张"双通道分层图"：App → SDK → org.webrtc → libwebrtc(C++) → OS 网络栈
- 16.2 信令交互完整流程（展开）
  - WebSocket 建立：URL 构造（`/rtc?protocol=&auto_subscribe=&...`）、Bearer token、`SignalClient.connect`
  - Join 握手：`SignalRequest.join` → `SignalResponse.join` → `onJoinResponse`
  - 消息分发：`requestFlow`/`responseFlow` SharedFlow 队列、`handleSignalResponseImpl`
  - 心跳：ping/pong 机制、超时
  - 重连信令：`reconnect` 参数、`resume` vs `full`
  - 一张"信令消息时序图"（join/track publish/subscribed quality/leave）
- 16.3 媒体流交互完整流程（展开）
  - publisher PC：本地编码 → RTP → SRTP → ICE → SFU
  - subscriber PC：SFU → SRTP → ICE → RTP → 解码 → 渲染
  - SDP 协商完整链路：`negotiatePublisher` → `createAndSendOffer` → SDP munge → `setLocalDescription` → `sendOffer` → 服务器 `answer` → `setRemoteDescription`
  - ICE 完整链路：`onIceCandidate` → `sendCandidate` → 服务器中转 → `addIceCandidate`（pending 队列）
  - DTLS/SRTP 握手（native 完成，Java 不参与）
  - 一张"媒体建立与传输时序图"
- 16.4 内部 WebRTC 的作用（org.webrtc / libwebrtc）
  - `org.webrtc` 包是什么：Google libwebrtc 的 Java JNI 绑定
  - `livekit.org.webrtc`：LiveKit 的二次封装（加了 SimulcastVideoEncoderFactory、CustomVideoEncoderFactory 等）
  - native 层做了什么：采集调度、编码、RTP 打包、FEC/NACK/带宽估计、Jitter buffer、解码、渲染
  - Java 层做了什么：封装 PeerConnection、SDP 操作、线程投递、事件回调
  - 一张"Java↔JNI↔C++ 调用栈图"（以 encode 一帧为例）
- 16.5 一个完整业务的端到端完整流程（综合）
  - 从 `LiveKit.create` → `room.connect` → 发布音频+视频 → 订阅对端 → 通话 → 断开
  - 一张超长"端到端时序图"（跨所有层）
  - 每一步标注：所在层、所在文件、所在线程

### 第 17 章 Kotlin/Java 高级抽象给 C++ 读者（举例展开）
**目标：用 C++ 对照讲清"依赖、委托、注入"等抽象。**
- 17.1 依赖注入（DI）是什么——从 C++ 手写工厂到 Dagger
  - C++ 例子：`Engine* makeEngine(Config* c) { return new Engine(c); }`
  - Kotlin 例子：`@Inject constructor` + `@Module` + `@Provides` + `@Component`
  - 用 Room 的构造为例，画出"对象图"
- 17.2 委托（Delegate / by）是什么
  - 接口委托：`class Room : RpcManager by localParticipant` —— C++ 对照：组合 + 转发
  - 属性委托：`by flowDelegate()` —— C++ 对照：重载 operator=
  - 代码对照表
- 17.3 注入（Inject）的三种形态
  - 构造注入、字段注入、方法注入，各自 C++ 等价物
- 17.4 协程与 Flow 的抽象
  - `suspend` ≈ 可暂停函数，C++20 协程对照
  - `Flow` ≈ 异步序列，C++ 对照：ranges + 协程
  - `StateFlow`/`SharedFlow` ≈ 热信号，C++ 对照：observable subject
- 17.5 密封类、data class、object、扩展函数
  - sealed class ≈ C++ 的 tagged union / std::variant
  - data class ≈ C++ 的 struct + 自动 ==/hash/copy
  - object ≈ 单例
  - 扩展函数 ≈ C++ 的自由函数（非成员函数）
- 17.6 注解（Annotation）与编译期生成
  - Dagger 用注解生成工厂代码，C++ 对照：代码生成器/X-macro

### 第 18 章 图集：分层图、类图、交互图
**目标：用大量图替代文字，直观。**
- 18.1 Android 平台分层图（从底到顶）
  - Linux Kernel → HAL → Android Framework 服务（AudioManager/AudioFlinger/CameraService/SurfaceFlinger/ConnectivityManager）→ libwebrtc(.so) → org.webrtc(JNI) → LiveKit SDK → App
  - 标注每层职责、数据怎么穿过
- 18.2 SDK 四层架构图（细化版，带文件名）
- 18.3 信令交互分层图（App→Room→RTCEngine→SignalClient→OkHttp WebSocket→OS）
- 18.4 媒体交互分层图（Camera→SurfaceTexture→VideoSource→Encoder→RtpSender→PC→ICE→SRTP→网络）
- 18.5 加密分层图（明文帧→FrameCryptor→加密RTP→网络；DataPacket→DataPacketCryptor→DataChannel）
- 18.6 核心类图（Room/RTCEngine/SignalClient/PeerConnectionTransport/Participant/Track 全景）
- 18.7 Track 继承类图
- 18.8 事件类图
- 18.9 DI 对象图（Component→Module→提供的方法→对象）

### 第 19 章 工程设计评价：特点、优劣
**目标：客观评价这个工程设计。**
- 19.1 优点（分层清晰、协程化、DI 可扩展、native 边界清晰、防御式容错、override 扩展点）
- 19.2 缺点/局限
  - WebRTC 强线程亲和，调试困难
  - SDP munge 脆弱（依赖 SDP 文本格式）
  - Dagger 编译慢、错误信息差
  - 部分 workaround 是对抗 Android 系统行为，版本碎片化风险
  - native 层不可见，深度 QoS 优化受限
  - 双 PC + subscriber primary 对新手不直观
- 19.3 适用场景与不适用场景
- 19.4 与其他方案对比（WebRTC 原生 SDK、Janus、mediasoup 客户端）
- 19.5 一句话评价

### 第 20 章 工业级 QoS 音视频优化分析
**目标：专业展开 QoS 优化空间、参数、是否要改 AAR、如何设计实验。**
- 20.1 QoS 目标定义（低延迟、抗丢包、带宽自适应、音质/画质、稳定性）
- 20.2 可调参数全景表（按层分类）
  - 采集层：分辨率、帧率、Camera API
  - 编码层：codec、maxBitrate、maxFps、scalabilityMode、关键帧间隔、QP 范围
  - Simulcast/SVC 层：层数、比例、dynacast
  - 传输层（native）：FEC、NACK、带宽估计算法（GCC）、拥塞控制、jitter buffer
  - 音频层：AEC/NS/AGC 开关、采样率、声道、opus bitrate、DTX、RED
  - 信令层：重连策略、ping 间隔
- 20.3 哪些在 SDK 层可调（给代码位置）
  - `LocalVideoTrackOptions` / `VideoTrackPublishOptions` / `RoomOptions`
  - `LocalAudioTrackOptions` / `AudioProcessorOptions`
  - `DefaultReconnectPolicy`
  - `LiveKitOverrides`（videoEncoderFactory、audioHandler 等）
- 20.4 哪些必须改 WebRTC AAR / native
  - GCC 参数、FEC 强度、NACK 策略、jitter buffer 上限、opus in-band FEC/DTX、编码器QP范围
  - 说明 `livekit.org.webrtc` 包是 LiveKit 自己 fork 的 libwebrtc，可改
  - 改 AAR 的方法：替换 .so / 修改 Java 绑定 / 重新编译 libwebrtc
- 20.5 具体优化方案（分音/视频）
  - 视频：Simulcast + SVC 联合、dynacast 调优、backup codec、编码器选择（H264 硬编 vs VP9 软编 vs AV1）
  - 音频：opus in-band FEC、DTX、RED（冗余）、AEC3 调参、AGC 目标电平、网络抖动缓冲
- 20.6 实验设计
  - 指标体系：MOS 分、PESQ/Visqol、端到端延迟、丢包率、码率利用率、CPU/温度
  - 网络仿真：ATC / Clumsy / Network Link Conditioner，构造丢包/抖动/带宽受限
  - A/B 框架：对照组 vs 实验组，样本量
  - 自动化：CI 跑 webrtc 的 `video_quality_loopback_test`、`audio_quality_loopback_test`
  - 真机矩阵：低端机/高端机、不同 Android 版本、不同网络
- 20.7 调参决策树（什么场景调什么）
- 20.8 风险与回滚

### 第 21 章 Kotlin/Java ↔ C++ 交互方式专题
**目标：把 JNI 边界讲透。**
- 21.1 JNI 基础（给 C++ 读者）
- 21.2 org.webrtc 的 JNI 模式：Java 持有 native 指针（long），native 回调 Java
- 21.3 一帧视频编码的完整跨语言调用栈
- 21.4 线程跨越：native 线程回调 Java（AttachCurrentThread）
- 21.5 修改 native 行为的途径

### 第 22 章 总结与速查
- 22.1 全文章节索引
- 22.2 关键文件速查表
- 22.3 关键参数速查表
- 22.4 调试技巧（开 WebRTC 日志、抓包、看 SDP）

## 撰写执行策略
1. 按章节顺序逐章写入 `docs-lu/lkt-anaysis.md`（追加到末尾）
2. 每章完成后 `wc -l` 确认持久化
3. 每章之间读取已写内容确认完整性
4. 长章节分多次写入
5. 顺序执行，不创建过多任务对象
