# WebRTC 架构设计分析计划-第一版

## 目标
分析 WebRTC 原生库的代码架构与架构设计，深入讲解其设计模式、并发模型、优缺点，由浅入深展开分析，配合图示说明。

## 读者画像
- 具备 C/C++ 经验，熟悉高级 C++ 用法但需要补充
- 已有 `wr-modules-analysis.md` 的模块认知和 `wr-whole-process.md` 的流程认知
- 没有太多架构经验，需要从基础概念讲起，逐步深入到落地细节

## 章节大纲

### 第 1 章：架构设计基础概念
- 1.1 什么是架构设计？为什么需要架构？
- 1.2 WebRTC 的工程挑战（150 万行 C++、跨平台、实时性、多线程）
- 1.3 架构设计的核心目标：解耦、可测试、可扩展、可维护
- 1.4 WebRTC 架构全景图（从模块分析到流程分析的串联）
- 1.5 C++ 大型项目架构的常见模式

### 第 2 章：WebRTC 分层架构详解
- 2.1 五层架构回顾与深化
- 2.2 每层的"接口契约"与"实现自由"
- 2.3 层间依赖方向：单向依赖原则
- 2.4 架构图：从简单到细致（3 级粒度）
  - 简单图：5 层总览
  - 中等图：层内模块关系
  - 细致图：关键路径的跨层调用链

### 第 3 章：并发架构 —— 线程亲和模型（核心设计）
- 3.1 为什么 WebRTC 选择线程亲和而非锁？
- 3.2 四大线程角色：signaling / worker / network / call
- 3.3 Proxy 模式深度解析（核心中的核心）
  - 3.3.1 Proxy 模板类源码分析
  - 3.3.2 Wrap/Unwrap 设计哲学
  - 3.3.3 跨线程调用完整流程（从信号到执行）
  - 3.3.4 Proxy 的生命周期管理
- 3.4 sigslot 信号槽：同线程事件通知
- 3.5 scoped_refptr：引用计数 + 创建线程销毁
- 3.6 并发架构的优缺点分析

### 第 4 章：设计模式全景
- 4.1 工厂模式（Factory）：PeerConnectionFactory、CallFactory
- 4.2 桥接模式（Bridge）：MediaEngine 桥接 pc/call 层与 modules 层
- 4.3 外观模式（Facade）：PeerConnection 作为统一入口
- 4.4 观察者模式（Observer）：广泛使用的回调接口
- 4.5 状态机模式（State Machine）：ICE 状态、PeerConnection 状态
- 4.6 装饰器模式（Decorator）：JsepTransport 包装多层传输
- 4.7 策略模式（Strategy）：编解码器协商、BWE 算法
- 4.8 组合模式（Composite）：CompositeRtpTransport
- 4.9 RAII 资源管理：unique_ptr + scoped_refptr 的所有权体系
- 4.10 依赖注入（DI）：通过 Dependencies 结构体注入

### 第 5 章：传输架构 —— 协议栈设计
- 5.1 JsepTransportController 的传输抽象
- 5.2 JsepTransport 的多层包装结构
- 5.3 RTP/DTLS/ICE 的层次关系
- 5.4 BUNDLE 复用机制的架构设计
- 5.5 Datagram Transport 的架构扩展点
- 5.6 架构图：传输栈的层层包装

### 第 6 章：媒体管道架构 —— 数据流设计
- 6.1 音频管道：Mic → ADM → APE → 编码 → RTP → 网络
- 6.2 视频管道：采集 → VPM → 编码 → NACK/FEC → RTP → 网络
- 6.3 管道中的 Zero-Copy 设计
- 6.4 Simulcast 的架构支持
- 6.5 拥塞控制闭环的架构位置
- 6.6 架构图：完整媒体管道的对象协作

### 第 7 章：架构的优缺点分析
- 7.1 优点
  - 7.1.1 线程亲和 + Proxy：零锁高性能
  - 7.1.2 分层清晰：每层职责单一
  - 7.1.3 接口抽象：实现可替换
  - 7.1.4 可测试性：Proxy 支持测试注入
- 7.2 缺点
  - 7.2.1 Proxy 模式增加代码复杂度
  - 7.2.2 线程亲和导致 API 使用门槛高
  - 7.2.3 过度抽象：接口层级过深
  - 7.2.4 学习曲线陡峭
  - 7.2.5 调试困难：跨线程调用链追踪
- 7.3 与其他 WebRTC 实现对比（libwebrtc vs pion vs mediasoup）

### 第 8 章：架构设计原则与最佳实践
- 8.1 单一职责原则（SRP）在 WebRTC 中的体现
- 8.2 依赖倒置原则（DIP）：接口而非实现
- 8.3 开闭原则（OCP）：扩展而不修改
- 8.4 里氏替换原则（LSP）：继承体系的安全性
- 8.5 接口隔离原则（ISP）：最小接口契约
- 8.6 组合优于继承：WebRTC 的偏好
- 8.7 从 WebRTC 学到的架构设计经验

### 第 9 章：落地指南 —— 如何设计一个 WebRTC 风格的系统
- 9.1 场景 1：设计一个实时消息系统
- 9.2 场景 2：设计一个音视频处理插件框架
- 9.3 场景 3：设计一个跨线程的监控采集系统
- 9.4 从 WebRTC 架构中提取可复用的模式
- 9.5 架构演进的教训：什么该抽象、什么不该抽象





# WebRTC 架构设计分析计划-第二版

## 目标
分析 WebRTC 的**整体架构**和**各核心模块的架构设计**，深入讲解设计模式、并发模型、优缺点，由浅入深展开分析，配合图示说明。

## 读者画像
- 具备 C/C++ 经验，熟悉高级 C++ 用法但需要补充
- 已有 `wr-modules-analysis.md` 的模块认知和 `wr-whole-process.md` 的流程认知
- 没有太多架构经验，需要从基础概念讲起，逐步深入到落地细节

---

## 章节大纲

### 第 1 章：架构设计基础概念
- 1.1 什么是架构设计？为什么需要架构？
- 1.2 WebRTC 的工程挑战（150 万行 C++、跨平台、实时性、多线程）
- 1.3 架构设计的核心目标：解耦、可测试、可扩展、可维护
- 1.4 WebRTC 架构全景图（从模块分析到流程分析的串联）
- 1.5 C++ 大型项目架构的常见模式

### 第 2 章：WebRTC 整体架构 —— 分层与协作
- 2.1 五层架构回顾与深化
- 2.2 每层的"接口契约"与"实现自由"
- 2.3 层间依赖方向：单向依赖原则
- 2.4 架构图：从简单到细致（3 级粒度）
- 2.5 整体并发模型：四大线程 + Proxy 模式
- 2.6 整体设计哲学：线程亲和 > 锁、接口抽象 > 具体实现

### 第 3 章：rtc_base 模块架构 —— 基础设施的架构
- 3.1 模块定位：所有上层模块的基石
- 3.2 线程架构：Thread / MessageHandler / MessageLoop
  - 架构特点：基于消息的线程模型，而非回调链
  - 架构图：消息分发流程
- 3.3 Socket 抽象层：PacketSocket / AsyncSocket / UDPSocket
  - 架构特点：统一异步 Socket API，屏蔽平台差异
  - 与上层网络模块的关系
- 3.4 SSL 传输架构：SSLStreamAdapter / SSLSocket
  - 架构特点：装饰器模式包装 Socket
- 3.5 sigslot 信号槽架构
  - 架构特点：编译期绑定、零开销、头库分离
  - 与 Observer 模式的对比
- 3.6 scoped_refptr 引用计数架构
  - 架构特点：引用计数 + 创建线程销毁（线程安全的关键）
- 3.7 rtc_base 架构优缺点
  - 优：极简、高效、头库分离降低编译依赖
  - 缺：消息模型对新手不直观

### 第 4 章：pc/ 模块架构 —— 信令与媒体控制的架构
- 4.1 模块定位：信令与媒体的"总控中心"
- 4.2 PeerConnection 架构：Facade 模式
  - 架构特点：统一入口，内部协调多个子模块
  - 架构图：PeerConnection 内部对象关系
- 4.3 JsepTransportController 架构：传输抽象
  - 架构特点：SDP 与传输解耦，按 m= section 管理传输
  - BUNDLE 机制的架构设计
- 4.4 ChannelManager 架构：媒体通道管理
  - 架构特点：跨线程桥接（signaling → worker → network）
  - VoiceChannel / VideoChannel 的继承体系
- 4.5 BaseChannel 架构：媒体通道的通用设计
  - 架构特点：_s / _w / _n 方法后缀 = 线程亲和的可视化
  - 架构图：三线程调用链
- 4.6 DataChannel 架构：SCTP over DTLS
  - 架构特点：SCTP 传输层 + DTLS 安全层 + 应用层分离
- 4.7 pc/ 模块架构优缺点
  - 优：Facade + Proxy 组合让复杂逻辑对外简洁
  - 缺：线程切换频繁，调试链路过长

### 第 5 章：call/ 模块架构 —— 媒体流的调度中心
- 5.1 模块定位：Call 是"媒体流的工厂+调度器"
- 5.2 Call 类架构：工厂模式 + 统一生命周期管理
  - CreateAudioSendStream / CreateVideoSendStream / ...
  - 架构图：Call 内部对象关系
- 5.3 AudioSendStream 架构：音频发送管线
  - 架构特点：配置驱动（AudioSendStream::Config）
  - 内部模块协作：编码 → APM → RTP 封包 → pacing
- 5.4 VideoSendStream 架构：视频发送管线
  - 架构特点：Simulcast 支持（多编码器并行）
  - 内部模块协作：编码 → NACK/FEC → RTP 封包 → BWE 反馈
- 5.5 RtpTransportControllerSend 架构：发送侧拥塞控制
  - 架构特点：BWE → GCC → Pacing → 码率调整的闭环
  - 架构图：拥塞控制数据流
- 5.6 call/ 模块架构优缺点
  - 优：工厂模式 + 配置驱动，新增流类型只需加接口
  - 缺：Config 结构体膨胀（AudioSendConfig 50+ 字段）

### 第 6 章：modules/ 模块架构 —— 核心处理模块的架构
#### 6.1 模块总览
- 6.1.1 模块分组：音频 / 视频 / 网络 / 工具
- 6.1.2 模块间依赖关系图

#### 6.2 音频处理模块架构（audio_processing/）
- 6.2.1 AudioProcessing 架构：模块化处理链
  - 架构特点：Module 注册机制，每个子系统独立可替换
  - AEC / NS / AGC / VAD / HighPassFilter 的协作
  - 架构图：AudioProcessing 内部处理链
- 6.2.2 AEC 架构（submodule）
  - 架构特点：参考信号设计、频域处理
  - EchoControlMobile vs EchoControlSoftware
- 6.2.3 APM 架构优缺点
  - 优：模块化设计，每个子系统独立开发和测试
  - 缺：模块间参数耦合（AGC 增益受 VAD 影响）

#### 6.3 视频处理模块架构（video_coding/ + video_processing/）
- 6.3.1 VideoCoding 架构：编码器工厂 + JitterBuffer
  - 架构特点：编码器抽象接口 + 具体编码器实现分离
  - 架构图：VideoCoding 内部对象关系
- 6.3.2 VP8/VP9/H264 编码器架构
  - 架构特点：外部编码器接口（VideoEncoder::Config/State/EncodedImage）
  - SimulcastEncoderAdapter 的装饰器设计
- 6.3.3 VideoProcessing 架构：帧处理管线
  - 架构特点：I420Frame 统一帧格式，操作链式组合
- 6.3.4 视频模块架构优缺点
  - 优：编码器接口统一，新增编码器只需实现接口
  - 缺：帧格式转换存在性能损耗

#### 6.4 拥塞控制模块架构（congestion_controller/）
- 6.4.1 GCC（Google Congestion Control）架构
  - 架构特点：Sender/Receiver 分离，RTCP 反馈闭环
  - RemoteBitrateEstimator + BWE + RateControl 的三层设计
  - 架构图：GCC 数据流
- 6.4.2 DelayBasedBwe 架构
  - 架构特点：基于往返时间变化的带宽估计
  - 与 PacketLossBasedBwe 的并行与融合
- 6.4.3 Pacing 架构（pacing/）
  - 架构特点：令牌桶算法，平滑发送速率
  - 与 BWE 的协作：BWE 输出目标码率 → Pacing 控制发送节奏
- 6.4.4 拥塞控制架构优缺点
  - 优：Sender/Receiver 分离，可独立优化
  - 缺：算法复杂度高，参数调优困难

#### 6.5 RTP/RTCP 模块架构（rtp_rtcp/）
- 6.5.1 RtpRtcp 架构：RTP 封包 + RTCP 报告的统一管理
  - 架构特点：Module 接口 + 具体实现
  - RR / XR / REMB / TMMBR 等 RTCP 反馈消息的处理
- 6.5.2 RTP 扩展头架构
  - 架构特点：动态注册机制，支持自定义扩展
- 6.5.3 架构优缺点
  - 优：RTCP 消息类型扩展方便
  - 缺：RTCP 处理逻辑分散在多处

#### 6.6 音频编解码模块架构（audio_coding/）
- 6.6.1 AudioCoding 架构：编解码器抽象
  - 架构特点：AudioEncoder/AudioDecoder 统一接口
  - Opus / G722 / iSAC / iLBC 的多编解码器支持
- 6.6.2 架构优缺点
  - 优：编解码器接口统一，新增编解码器只需实现接口
  - 缺：不同编解码器参数差异大，接口难以完全统一

### 第 7 章：p2p/ 模块架构 —— 网络与 ICE 的架构
- 7.1 模块定位：P2P 连接的网络基石
- 7.2 PortAllocator 架构：候选收集的统一入口
  - 架构特点：工厂模式创建不同类型的 Port
  - 架构图：PortAllocator → Port → Candidate 的层级
- 7.3 P2PTransportChannel 架构：ICE 连接管理
  - 架构特点：Candidate Pair 管理 + Connection Check 状态机
  - ICE Controller 抽象：支持未来扩展新的 ICE 策略
- 7.4 Port 架构：不同网络类型的统一抽象
  - 架构特点：HostPort / StunPort / RelayedPort 继承体系
  - 各 Port 类型的职责分离
- 7.5 STUN 协议架构
  - 架构特点：MessageBuilder / MessageParser 分离
  - 与 Socket 层的解耦
- 7.6 p2p/ 模块架构优缺点
  - 优：Port 抽象让不同候选类型共享同一套连接管理逻辑
  - 缺：ICE 状态机复杂，Candidate Pair 管理代码量大

### 第 8 章：media/engine/ 模块架构 —— 桥接层的架构智慧
- 8.1 模块定位：连接 pc/call 层与 modules 层的"翻译官"
- 8.2 WebRTCMediaEngine 架构：统一资源管理
  - 架构特点：一个入口管理所有媒体资源
  - 架构图：MediaEngine 内部对象关系
- 8.3 WebRTCVoiceEngine 架构
  - 架构特点：VoiceChannel ↔ AudioSendStream 的映射
  - 编解码器协商的桥接逻辑
- 8.4 WebRTCVideoEngine 架构
  - 架构特点：VideoChannel ↔ VideoSendStream 的映射
  - Simulcast 配置的桥接
- 8.5 MediaEngineInterface 架构设计哲学
  - 架构特点：接口与实现分离，实现可完全替换
  - 依赖注入：Call 层通过接口调用，不知道具体实现
- 8.6 桥接层架构优缺点
  - 优：完美的依赖倒置，上层不依赖下层实现
  - 缺：桥接层代码量较大，每新增一个模块都要写桥接

### 第 9 章：设计模式全景 —— WebRTC 用了哪些设计模式
- 9.1 工厂模式（Factory）
  - PeerConnectionFactory、CallFactory、编码器工厂
- 9.2 桥接模式（Bridge）
  - MediaEngine 桥接 pc/call 层与 modules 层
- 9.3 外观模式（Facade）
  - PeerConnection 作为统一入口
- 9.4 观察者模式（Observer）
  - 广泛使用的回调接口（SignalXXX、Observer）
- 9.5 状态机模式（State Machine）
  - ICE 状态、PeerConnection 状态、DTLS 状态
- 9.6 装饰器模式（Decorator）
  - SSLStreamAdapter 包装 Socket、JsepTransport 多层包装
- 9.7 策略模式（Strategy）
  - 编解码器协商、BWE 算法、Bundle Policy
- 9.8 组合模式（Composite）
  - CompositeRtpTransport、CompositeDataChannelTransport
- 9.9 RAII 资源管理
  - unique_ptr + scoped_refptr 的所有权体系
- 9.10 依赖注入（DI）
  - Dependencies 结构体注入、接口抽象
- 9.11 设计模式使用频率统计与总结

### 第 10 章：架构的优缺点深度分析
- 10.1 优点
  - 10.1.1 线程亲和 + Proxy：零锁高性能
  - 10.1.2 分层清晰：每层职责单一
  - 10.1.3 接口抽象：实现可替换
  - 10.1.4 可测试性：Proxy 支持测试注入
  - 10.1.5 模块化设计：各模块独立开发和测试
- 10.2 缺点
  - 10.2.1 Proxy 模式增加代码复杂度
  - 10.2.2 线程亲和导致 API 使用门槛高
  - 10.2.3 过度抽象：接口层级过深
  - 10.2.4 学习曲线陡峭
  - 10.2.5 调试困难：跨线程调用链追踪
  - 10.2.6 Config 结构体膨胀
  - 10.2.7 桥接层代码冗余
- 10.3 与其他 WebRTC 实现对比
  - 10.3.1 libwebrtc（本项目）vs pion（Go）vs mediasoup（Node.js）
  - 10.3.2 不同语言/平台下的架构取舍

### 第 11 章：架构设计原则与最佳实践
- 11.1 单一职责原则（SRP）在 WebRTC 中的体现
- 11.2 依赖倒置原则（DIP）：接口而非实现
- 11.3 开闭原则（OCP）：扩展而不修改
- 11.4 里氏替换原则（LSP）：继承体系的安全性
- 11.5 接口隔离原则（ISP）：最小接口契约
- 11.6 组合优于继承：WebRTC 的偏好
- 11.7 从 WebRTC 学到的架构设计经验

### 第 12 章：落地指南 —— 如何设计一个 WebRTC 风格的系统
- 12.1 场景 1：设计一个实时消息系统
  - 如何应用线程亲和 + Proxy 模式
- 12.2 场景 2：设计一个音视频处理插件框架
  - 如何应用模块化 + 接口抽象
- 12.3 场景 3：设计一个跨线程的监控采集系统
  - 如何应用消息模型 + 信号槽
- 12.4 从 WebRTC 架构中提取可复用的模式
- 12.5 架构演进的教训：什么该抽象、什么不该抽象
