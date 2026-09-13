# WebRTC 架构设计分析

> **版本备注**：本文已按 **WebRTC M144 源码树**（`/data1/luhonghao/codes/adrtc/wr-m144_release`）核对并修订，核对日期 2026-09-11。文中所有 `file:line` 均相对该源码树。M144 相比老资料（M96 及更早）有多处结构性变化，本文已按源码更正；凡"与老版本差异较大"处，均以 **⚠️ M144 变更** 引用块显式标注（块内保留旧名仅作对照）。主要变更：pc/ 层 ChannelManager 类已删除（通道由 RtpTransceiver 直接持有、SDP 协商拆到 SdpOfferAnswerHandler）、modules/ 层 Module/ProcessThread 周期调度已删除（统一 TaskQueue）、RtpRtcp 拆为 RtpRtcpInterface + ModuleRtpRtcpImpl2、MediaChannel 拆分 Send/Receive 接口、proxy.h 位于 pc/ 而非 api/。读老版本源码/资料时请留意这些差异。

> 读者画像：具备 C/C++ 经验，熟悉高级 C++ 用法但需要补充；已有模块认知和流程认知，希望深入理解架构设计。
>
> 相关文档：
> - `wr-modules-analysis.md`：模块架构分析
> - `wr-whole-process.md`：完整业务流程分析

---

## 目录

### 概览

| 章节 | 标题 | 摘要 |
|---|---|---|
| 第 1 章 | 架构设计基础概念 | 什么是架构、为什么需要、WebRTC 的工程挑战、核心目标 |
| 第 2 章 | WebRTC 整体架构 | 五层架构、接口契约、层间依赖、并发模型 |
| 第 3 章 | 并发架构 —— 线程亲和模型 | Proxy 模式深度解析、sigslot、scoped_refptr |
| 第 4 章 | rtc_base 模块架构 | 线程/消息系统、Socket 抽象、sigslot、scoped_refptr |
| 第 5 章 | pc/ 模块架构 | PeerConnection Facade、JsepTransportController、RtpTransceiver/RtpTransmissionManager |
| 第 6 章 | call/ 模块架构 | Call 工厂、音视频 Stream、拥塞控制闭环 |
| 第 7 章 | 传输架构 —— 协议栈设计 | JsepTransport 多层包装、RTP/DTLS/ICE、BUNDLE |
| 第 8 章 | 媒体管道架构 —— 数据流设计 | 音视频管道、Zero-Copy、Simulcast、BWE 闭环 |
| 第 9 章 | modules/ 模块架构 | 音频处理、视频编码、拥塞控制、RTP/RTCP、音频编解码 |
| 第 10 章 | p2p/ 模块架构 | PortAllocator、P2PTransportChannel、Port 继承体系 |
| 第 11 章 | media/engine/ 模块架构 | 桥接层设计哲学、资源管理、编解码器桥接 |
| 第 12 章 | 设计模式全景 | 10 种设计模式在 WebRTC 中的应用 |
| 第 13 章 | 架构优缺点深度分析 | 优点、缺点、与其他实现对比 |
| 第 14 章 | 架构设计原则与最佳实践 | SOLID 原则在 WebRTC 中的体现 |
| 第 15 章 | 落地指南 | 从 WebRTC 提取的可复用模式 |

---

### 详细目录

#### 第 1 章：架构设计基础概念
- [1.1 什么是架构设计](#11-什么是架构设计)
- [1.2 WebRTC 的工程挑战](#12-webrtc-的工程挑战)
- [1.3 架构设计的核心目标](#13-架构设计的核心目标)
- [1.4 WebRTC 架构全景图](#14-webrtc-架构全景图)
- [1.5 C++ 大型项目架构的常见模式](#15-c-大型项目架构的常见模式)

#### 第 2 章：WebRTC 整体架构 —— 分层与协作
- [2.1 五层架构](#21-五层架构)
- [2.2 每层的"接口契约"与"实现自由"](#22-每层的接口契约与实现自由)
- [2.3 层间依赖方向：单向依赖](#23-层间依赖方向单向依赖)
- [2.4 架构图：从简单到细致](#24-架构图从简单到细致)
- [2.5 整体并发模型](#25-整体并发模型)
- [2.6 整体设计哲学](#26-整体设计哲学)

#### 第 3 章：并发架构 —— 线程亲和模型（核心设计）
- [3.1 为什么 WebRTC 选择线程亲和而非锁](#31-为什么-webrtc-选择线程亲和而非锁)
- [3.2 四大线程角色](#32-四大线程角色)
- [3.3 Proxy 模式深度解析（核心中的核心）](#33-proxy-模式深度解析核心中的核心)
  - [3.3.1 Proxy 模板类源码分析](#331-proxy-模板类源码分析)
  - [3.3.2 Wrap/Unwrap 设计哲学](#332-wrapunwrap-设计哲学)
  - [3.3.3 跨线程调用完整流程](#333-跨线程调用完整流程)
  - [3.3.4 Proxy 的生命周期管理](#334-proxy-的生命周期管理)
- [3.4 sigslot 信号槽：同线程事件通知](#34-sigslot-信号槽同线程事件通知)
- [3.5 scoped_refptr：引用计数 + 创建线程销毁](#35-scoped_refptr引用计数--创建线程销毁)
- [3.6 并发架构的优缺点分析](#36-并发架构的优缺点分析)

#### 第 4 章：rtc_base 模块架构 —— 基础设施的架构
- [4.1 模块定位](#41-模块定位)
- [4.2 线程架构：基于消息的线程模型](#42-线程架构基于消息的线程模型)
- [4.3 Socket 抽象层](#43-socket-抽象层)
- [4.4 sigslot 信号槽架构](#44-sigslot-信号槽架构)
- [4.5 scoped_refptr 引用计数架构](#45-scoped_refptr-引用计数架构)
- [4.6 rtc_base 架构优缺点](#46-rtc_base-架构优缺点)

#### 第 5 章：pc/ 模块架构 —— 信令与媒体控制的架构
- [5.1 模块定位](#51-模块定位)
- [5.2 PeerConnection 架构：Facade 模式](#52-peerconnection-架构facade-模式)
- [5.3 JsepTransportController 架构：传输抽象](#53-jseptransportcontroller-架构传输抽象)
- [5.4 RtpTransceiver/RtpTransmissionManager 架构：通道的归属与跨线程桥接](#54-rtptransceiverrtptransmissionmanager-架构通道的归属与跨线程桥接)
- [5.5 BaseChannel 架构：媒体通道的通用设计](#55-basechannel-架构媒体通道的通用设计)
- [5.6 DataChannel 架构：SCTP over DTLS](#56-datachannel-架构sctp-over-dtls)
- [5.7 pc/ 模块架构优缺点](#57-pc-模块架构优缺点)

#### 第 6 章：call/ 模块架构 —— 媒体流的调度中心
- [6.1 模块定位](#61-模块定位)
- [6.2 Call 类架构：工厂模式 + 统一生命周期管理](#62-call-类架构工厂模式--统一生命周期管理)
- [6.3 AudioSendStream 架构：音频发送管线](#63-audiosendstream-架构音频发送管线)
- [6.4 VideoSendStream 架构：视频发送管线](#64-videosendstream-架构视频发送管线)
- [6.5 RtpTransportControllerSend 架构：发送侧拥塞控制](#65-rtptransportcontrollersend-架构发送侧拥塞控制)
- [6.6 call/ 模块架构优缺点](#66-call-模块架构优缺点)

#### 第 7 章：传输架构 —— 协议栈设计
- [7.1 JsepTransportController 的传输抽象](#71-jseptransportcontroller-的传输抽象)
- [7.2 JsepTransport 的多层包装结构](#72-jseptransport-的多层包装结构)
- [7.3 RTP/DTLS/ICE 的层次关系](#73-rptdtlsice-的层次关系)
- [7.4 BUNDLE 复用机制的架构设计](#74-bundle-复用机制的架构设计)
- [7.5 Datagram Transport 的架构扩展点](#75-datagram-transport-的架构扩展点)
- [7.6 传输栈的层层包装架构图](#76-传输栈的层层包装架构图)

#### 第 8 章：媒体管道架构 —— 数据流设计
- [8.1 音频管道：Mic → ADM → APE → 编码 → RTP → 网络](#81-音频管道mic--adm--ape--编码--rtp--网络)
- [8.2 视频管道：采集 → 适配降级 → 编码 → NACK/FEC → RTP → 网络](#82-视频管道采集--适配降级--编码--nackfec--rtp--网络)
- [8.3 管道中的 Zero-Copy 设计](#83-管道中的-zero-copy-设计)
- [8.4 Simulcast 的架构支持](#84-simulcast-的架构支持)
- [8.5 拥塞控制闭环的架构位置](#85-拥塞控制闭环的架构位置)
- [8.6 完整媒体管道的对象协作图](#86-完整媒体管道的对象协作图)

#### 第 9 章：modules/ 模块架构 —— 核心处理模块的架构
- [9.1 模块总览](#91-模块总览)
  - [9.1.1 模块分组](#911-模块分组)
  - [9.1.2 模块间依赖关系图](#912-模块间依赖关系图)
  - [9.1.3 调度接口架构：TaskQueue 取代 Module/ProcessThread](#913-调度接口架构taskqueue-取代-moduleprocessthread)
- [9.2 音频处理模块架构（audio_processing/）](#92-音频处理模块架构audio_processing)
  - [9.2.1 AudioProcessing 架构：模块化处理链](#921-audioprocessing-架构模块化处理链)
  - [9.2.2 AEC 架构（EchoCancellation submodule）](#922-aec-架构echocancellation-submodule)
  - [9.2.3 APM 架构优缺点](#923-apm-架构优缺点)
- [9.3 视频处理模块架构（video_coding/ + video_processing/）](#93-视频处理模块架构video_coding--video_processing)
  - [9.3.1 VideoCoding 架构：接收缓冲链 + 丢包恢复](#931-videocoding-架构接收缓冲链--丢包恢复)
  - [9.3.2 VP8/VP9/H264 编码器架构](#932-vp8vp9h264-编码器架构)
  - [9.3.3 VideoProcessing 架构：帧处理管线](#933-videoprocessing-架构帧处理管线)
  - [9.3.4 视频模块架构优缺点](#934-视频模块架构优缺点)
- [9.4 拥塞控制模块架构（congestion_controller/）](#94-拥塞控制模块架构congestion_controller)
  - [9.4.1 GCC（Google Congestion Control）架构](#941-gccgoogle-congestion-control-架构)
  - [9.4.2 DelayBasedBwe 架构](#942-delaybasedbwe-架构)
  - [9.4.3 Pacing 架构（pacing/）](#943-pacing-架构pacing)
  - [9.4.4 拥塞控制架构优缺点](#944-拥塞控制架构优缺点)
- [9.5 RTP/RTCP 模块架构（rtp_rtcp/）](#95-rpttcp-模块架构rtp_rtcp)
  - [9.5.1 RtpRtcp 架构：RTP 封包 + RTCP 报告的统一管理](#951-rptrtcp-架构rtp-封包--rtcp-报告的统一管理)
  - [9.5.2 RTP 扩展头架构](#952-rtp-扩展头架构)
  - [9.5.3 架构优缺点](#953-架构优缺点)
- [9.6 音频编解码模块架构（audio_coding/）](#96-音频编解码模块架构audio_coding)
  - [9.6.1 AudioCoding 架构：编解码器抽象](#961-audiocoding-架构编解码器抽象)
  - [9.6.2 架构优缺点](#962-架构优缺点)
- [9.7 modules/ 模块架构总结](#97-modules-模块架构总结)

#### 第 10 章：p2p/ 模块架构 —— 网络与 ICE 的架构
- [10.1 模块定位](#101-模块定位)
- [10.2 PortAllocator 架构：候选收集的统一入口](#102-portallocator-架构候选收集的统一入口)
- [10.3 P2PTransportChannel 架构：ICE 连接管理](#103-p2ptransportchannel-架构ice-连接管理)
- [10.4 Port 架构：不同网络类型的统一抽象](#104-port-架构不同网络类型的统一抽象)
- [10.5 STUN 协议架构](#105-stun-协议架构)
- [10.6 p2p/ 模块架构优缺点](#106-p2p-模块架构优缺点)

#### 第 11 章：media/engine/ 模块架构 —— 桥接层的架构智慧
- [11.1 模块定位](#111-模块定位)
- [11.2 WebRTCMediaEngine 架构：统一资源管理](#112-webrtcmediaengine-架构统一资源管理)
  - [11.3 WebRtcVoiceEngine 架构](#113-webrtcvoiceengine-架构)
  - [11.4 WebRtcVideoEngine 架构](#114-webrtcvideoengine-架构)
- [11.5 MediaEngineInterface 架构设计哲学](#115-mediaengineinterface-架构设计哲学)
- [11.6 桥接层架构优缺点](#116-桥接层架构优缺点)

#### 第 12 章：设计模式全景 —— WebRTC 用了哪些设计模式
- [12.1 工厂模式（Factory）](#121-工厂模式factory)
- [12.2 桥接模式（Bridge）](#122-桥接模式bridge)
- [12.3 外观模式（Facade）](#123-外观模式facade)
- [12.4 观察者模式（Observer）](#124-观察者模式observer)
- [12.5 状态机模式（State Machine）](#125-状态机模式state-machine)
- [12.6 装饰器模式（Decorator）](#126-装饰器模式decorator)
- [12.7 策略模式（Strategy）](#127-策略模式strategy)
- [12.8 组合模式（Composite）](#128-组合模式composite)
- [12.9 RAII 资源管理](#129-raii-资源管理)
- [12.10 依赖注入（DI）](#1210-依赖注入di)
- [12.11 设计模式使用频率统计](#1211-设计模式使用频率统计)

#### 第 13 章：架构的优缺点深度分析
- [13.1 优点](#131-优点)
  - [13.1.1 线程亲和 + Proxy：零锁高性能](#1311-线程亲和--proxy零锁高性能)
  - [13.1.2 分层清晰：每层职责单一](#1312-分层清晰每层职责单一)
  - [13.1.3 接口抽象：实现可替换](#1313-接口抽象实现可替换)
  - [13.1.4 可测试性](#1314-可测试性)
- [13.2 缺点](#132-缺点)
  - [13.2.1 Proxy 模式增加代码复杂度](#1321-proxy-模式增加代码复杂度)
  - [13.2.2 线程亲和导致 API 使用门槛高](#1322-线程亲和导致-api-使用门槛高)
  - [13.2.3 过度抽象：接口层级过深](#1323-过度抽象接口层级过深)
  - [13.2.4 学习曲线陡峭](#1324-学习曲线陡峭)
  - [13.2.5 调试困难](#1325-调试困难)
  - [13.2.6 Config 结构体膨胀](#1326-config-结构体膨胀)
  - [13.2.7 桥接层代码冗余](#1327-桥接层代码冗余)
- [13.3 与其他 WebRTC 实现对比](#133-与其他-webrtc-实现对比)
  - [13.3.1 libwebrtc vs pion (Go) vs mediasoup (Node.js)](#1331-libwebrtc-vs-pion-go-vs-mediasoup-nodejs)
- [13.4 架构取舍总结](#134-架构取舍总结)

#### 第 14 章：架构设计原则与最佳实践
- [14.1 单一职责原则（SRP）在 WebRTC 中的体现](#141-单一职责原则srp在-webrtc-中的体现)
- [14.2 依赖倒置原则（DIP）：接口而非实现](#142-依赖倒置原则dip接口而非实现)
- [14.3 开闭原则（OCP）：扩展而不修改](#143-开闭原则ocp扩展而不修改)
- [14.4 里氏替换原则（LSP）：继承体系的安全性](#144-里氏替换原则lsp继承体系的安全性)
- [14.5 接口隔离原则（ISP）：最小接口契约](#145-接口隔离原则isp最小接口契约)
- [14.6 组合优于继承：WebRTC 的偏好](#146-组合优于继承webrtc-的偏好)
- [14.7 从 WebRTC 学到的架构设计经验](#147-从-webrtc-学到的架构设计经验)

#### 第 15 章：落地指南 —— 如何设计一个 WebRTC 风格的系统
- [15.1 场景 1：设计一个实时消息系统](#151-场景-1设计一个实时消息系统)
- [15.2 场景 2：设计一个音视频处理插件框架](#152-场景-2设计一个音视频处理插件框架)
- [15.3 场景 3：设计一个跨线程的监控采集系统](#153-场景-3设计一个跨线程的监控采集系统)
- [15.4 从 WebRTC 架构中提取的可复用模式](#154-从-webrtc-架构中提取的可复用模式)
- [15.5 架构演进的教训：什么该抽象、什么不该抽象](#155-架构演进的教训什么该抽象什么不该抽象)

---

## 第 1 章：架构设计基础概念

### 1.1 什么是架构设计

**架构设计**回答的是"系统由哪些部分组成、各部分之间如何协作、为什么这样分"的问题。它不是具体代码实现，而是代码的**组织原则**。

类比：如果代码是一栋建筑，架构就是建筑的设计蓝图——哪里是承重墙、哪里是通道、水电管线怎么走。

架构设计的核心产出：
- **分层**：哪些功能属于同一层级
- **接口**：层与层之间如何通信
- **并发模型**：多线程如何协作
- **生命周期管理**：对象何时创建、何时销毁

### 1.2 WebRTC 的工程挑战

WebRTC 原生库约 150 万行 C++ 代码，面临以下挑战：

```
挑战矩阵
┌─────────────┬──────────────────────────────────────────┐
│ 代码规模     │ 150 万行 C++，约 8000+ 文件              │
│ 实时性       │ 端到端延迟 < 150ms，不能容忍 GC 停顿       │
│ 跨平台       │ Windows/macOS/Linux/iOS/Android/嵌入式    │
│ 多线程       │ 每个 PeerConnection 4+ 线程               │
│ 网络不确定    │ NAT/防火墙/丢包/抖动/带宽波动              │
│ 安全要求     │ DTLS/SRTP 加密，密钥管理                  │
│ 兼容性       │ 浏览器端、移动端、嵌入式端互操作           │
└─────────────┴──────────────────────────────────────────┘
```

这些挑战直接决定了架构设计方向：
- **实时性** → 不能 GC → 手动内存管理（scoped_refptr）
- **多线程** → 不能共享锁（性能差）→ 线程亲和 + Proxy
- **网络不确定** → 拥塞控制必须独立模块
- **跨平台** → 硬件抽象层（ADM、VideoCaptureModule）

### 1.3 架构设计的核心目标

```
架构目标优先级（WebRTC 视角）：

实时性 > 正确性 > 可测试性 > 可扩展性 > 可维护性
```

- **实时性**：RTT 150ms 以内，不能因为架构设计引入额外延迟
- **正确性**：音视频不能丢帧、不能崩溃
- **可测试性**：每个模块能独立测试
- **可扩展性**：新增编解码器、新协议不需要改核心代码
- **可维护性**：150 万行代码，多人协作不能互相冲突

### 1.4 WebRTC 架构全景图

```
之前文档的关系：

wr-modules-analysis.md  → "系统有哪些零件"
wr-whole-process.md    → "零件怎么协作跑完一个呼叫"
wr-arch-design-analysis.md → "为什么这样设计零件？为什么这样组装？"

三者互补，层层深入：
模块认知 → 流程认知 → 架构认知
```

### 1.5 C++ 大型项目架构的常见模式

| 模式 | 适用场景 | WebRTC 中的应用 |
|---|---|---|
| 分层架构 | 系统职责清晰，层间依赖单向 | 5 层架构 |
| 插件架构 | 功能可插拔 | MediaEngine 桥接 |
| 管道架构 | 数据流处理 | 音视频处理管线 |
| 事件驱动 | 异步事件处理 | sigslot 信号槽 |
| 反应器模式 | 网络 I/O 多路复用 | AsyncSocket |

WebRTC 是**混合架构**：分层 + 插件 + 管道 + 事件驱动。

---

## 第 2 章：WebRTC 整体架构 —— 分层与协作

### 2.1 五层架构

```
┌─────────────────────────────────────────────────────────────────┐
│  第 5 层：应用层 (examples/, sdk/)                               │
│  示例应用、Android JNI、Objective-C 桥接                         │
├─────────────────────────────────────────────────────────────────┤
│  第 4 层：标准 API 层 (api/, pc/)                                 │
│  PeerConnectionInterface (W3C API)、SDP 协商、ICE 状态机         │
├─────────────────────────────────────────────────────────────────┤
│  第 3 层：呼叫管理层 (call/)                                      │
│  Call 类 — 音视频流的统一调度中心                                 │
├─────────────────────────────────────────────────────────────────┤
│  第 2 层：核心处理层 (modules/, video/, common_*/ )              │
│  编解码、音频处理、视频处理、拥塞控制、RTP/RTCP                   │
├─────────────────────────────────────────────────────────────────┤
│  第 1 层：基础设施层 (rtc_base/, p2p/, logging/)                 │
│  线程、消息、Socket、SSL、日志、同步原语                          │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 每层的"接口契约"与"实现自由"

```
第 4 层（pc/）定义接口：
  ┌─────────────────────────────────────┐
  │  MediaEngineInterface                │  ← 接口（第 4 层定义）
  │    virtual int Encode(...) = 0;      │
  │    virtual int Decode(...) = 0;      │
  └─────────────────────────────────────┘
           ↑ 实现
  ┌─────────────────────────────┐
  │  WebRtcVideoEngine           │  ← 实现（第 2 层 modules/）
  │    int Encode(...) { ... }   │
  │    int Decode(...) { ... }   │
  └─────────────────────────────┘
```

> 说明：Encode/Decode 为示意——M144 中 MediaEngineInterface（media/base/media_engine.h）的真实方法是 `voice()`/`video()` 引擎入口，编解码走 `VideoEncoder`/`AudioEncoder` 工厂；接口在高层定义、实现在低层提供这一依赖倒置关系不变。

**接口契约**一旦定义，不能随意修改（影响所有上层调用者）。
**实现自由**意味着第 2 层可以完全替换（比如 VP8 换成 H.264），只要接口不变。

### 2.3 层间依赖方向：单向依赖

```
正确的依赖方向（箭头指向被依赖方）：

应用层 ──→ API 层 ──→ 呼叫层 ──→ 处理层 ──→ 基础设施层
  ↑          ↑          ↑          ↑          ↑
  └──────────┴──────────┴──────────┴──────────┘
         所有依赖都是单向的，没有反向依赖
```

**违反单向依赖的后果**：如果基础设施层依赖了呼叫层，会导致：
- 编译循环依赖
- 测试时必须初始化整个呼叫系统
- 模块无法独立复用

### 2.4 架构图：从简单到细致

```
【粒度 1：5 层总览】

应用层 → API 层 → 呼叫层 → 处理层 → 基础设施层

【粒度 2：层内模块关系（以处理层为例）】

modules/
├── audio_processing/  ←── AudioSendStream 调用
├── audio_coding/      ←── AudioSendStream 调用
├── video_coding/      ←── VideoSendStream 调用
├── congestion_controller/ ←── Call 层调用
├── pacing/            ←── RtpTransportControllerSend 调用
└── rtp_rtcp/          ←── 所有 Stream 调用

【粒度 3：关键路径跨层调用链（音频发送）】

pc/PeerConnection (signaling 线程)
  └─ sdp_handler_ / RtpTransceiver (SdpOfferAnswerHandler 应用描述)
       └─ RtpTransceiver::CreateChannel → BaseChannel (worker 线程)
            └─ VoiceMediaSendChannelInterface 实现 (worker 线程)
                 └─ AudioSendStream (call 层 TaskQueue)
                      ├─ AudioEncoder (编码)
                      ├─ AudioProcessing (采集端, ADM 线程驱动)
                      └─ RTPSender (rtp_sender.h)
                           └─ RtpTransport (network 线程)
```

> 源码对照：`RtpTransceiver::CreateChannel`（`pc/rtp_transceiver.cc:204`）；`channel_` 成员（`pc/rtp_transceiver.h:121`）；`SdpOfferAnswerHandler`（`pc/sdp_offer_answer.h:78`，PeerConnection 持有 `sdp_handler_`）。M144 已无 ChannelManager——通道创建/管理归属见 5.4。

### 2.5 整体并发模型

```
线程分工（M144 无独立"call 线程"与 ProcessThread——call 层逻辑跑在 worker 的 TaskQueue 上）：

signaling 线程                          worker 线程
┌─────────────────┐                    ┌──────────────────────┐
│ PeerConnection   │  Proxy/直接调用    │ SdpOfferAnswerHandler │
│ RtpTransmission  │ ──────────────→    │ RtpTransceiver       │
│ Manager(轨道管理)│  同步阻塞调用       │ BaseChannel + media   │
│ SDP 状态机       │                    │ channel 实现          │
└─────────────────┘                    └──────────────────────┘
        ↑                                       ↑
        │          network 线程                 │
        └──────────┼────────────────────────────┘
                   │
        ┌─────────────────┐
        │ P2PTransportChan │
        │ DTLS Transport   │
        │ UDPSocket        │
        │ STUN 定时器      │
        └─────────────────┘
                   ↑
        ┌─────────────────────────────┐
        │ worker 线程上的 Call          │
        │ AudioSendStream/VideoSendStream│
        │ GoogCc 拥塞控制(25ms 周期任务)  │
        │ TaskQueuePacedSender(pacing)  │
        └─────────────────────────────┘
```

**关键设计决策**：
- 每个线程只访问自己线程上的对象（线程亲和）
- 跨线程必须通过 Proxy（不允许直接访问）
- 线程间通过消息队列通信（不允许共享内存）

### 2.6 整体设计哲学

```
WebRTC 的三条设计哲学：

1. 线程亲和 > 锁
   - 锁会导致线程等待，破坏实时性
   - 线程亲和 = 每个对象只在一个线程上访问 = 零锁

2. 接口抽象 > 具体实现
   - 所有模块通过接口交互
   - 实现可完全替换（VP8 → H.264，iSAC → Opus）

3. 配置驱动 > 硬编码
   - 编解码器选择、Bundle Policy、ICE 配置都通过 Config 对象传入
   - 运行时可动态调整
```

---

## 第 3 章：并发架构 —— 线程亲和模型（核心设计）

### 3.1 为什么 WebRTC 选择线程亲和而非锁

```
传统锁方案：

  线程 A ──→ [锁] ──→ 共享数据 ──→ [锁] ←── 线程 B
                    ↑
              锁竞争 = 线程等待 = 延迟增加

  问题：
  - 锁竞争导致不可预测的延迟（实时场景大忌）
  - 优先级反转（低优先级线程持有锁，高优先级线程等待）
  - 死锁风险（多个锁的获取顺序错误）
  - 缓存失效（锁保护的数据在多线程间切换，CPU 缓存失效）

WebRTC 线程亲和：

  线程 A ──→ [对象 A]    [对象 B] ←── 线程 B
                  ↑ Proxy 跨线程消息
              无锁竞争 = 零等待

  优势：
  - 无锁竞争，不会因一个慢线程阻塞其他线程
  - CPU 缓存局部性好（数据不跨线程迁移）
  - 延迟可预测（消息投递 ~100ns）
  - 无死锁风险（没有共享数据）
```

**代价**：
- 代码复杂度大幅增加（Proxy 模式、线程切换）
- API 使用门槛高（必须理解线程归属）
- 调试困难（跨线程调用链追踪）

### 3.2 线程角色

```
signaling 线程                          worker 线程
┌─────────────────┐                    ┌──────────────────────┐
│ 职责：信令与SDP  │                    │ 职责：媒体管理        │
├─────────────────┤                    ├──────────────────────┤
│ PeerConnection   │                    │ SdpOfferAnswerHandler│
│ RtpTransmission  │                    │ RtpTransceiver       │
│ Manager(轨道管理)│                    │ BaseChannel          │
│ SDP 状态机       │                    │ MediaEngine          │
│ DTLS 角色协商    │                    │ 编解码器配置          │
└─────────────────┘                    └──────────────────────┘
        ↑                                       ↑
        │          network 线程                 │
        └──────────┼────────────────────────────┘
                   │
        ┌─────────────────┐
        │ 职责：网络 I/O   │
        ├─────────────────┤
        │ P2PTransportChan │
        │ DTLS 握手        │
        │ UDPSocket 收发   │
        │ ICE Ping 定时器  │
        └─────────────────┘
                   ↑
                   │  (Call 与 Stream 也运行在 worker 的 TaskQueue 上)
        ┌─────────────────────────┐
        │ 职责：媒体处理            │
        ├─────────────────────────┤
        │ Call                   │
        │ AudioSendStream        │
        │ VideoSendStream        │
        │ GoogCc 拥塞控制         │
        │ TaskQueuePacedSender   │
        └─────────────────────────┘
```

**线程关系**：
- signaling → worker：同步 Proxy 调用（PeerConnection 委托 sdp_handler_ 应用描述，再经 transceiver/channel 投递到 worker）
- worker → network：同步 Proxy 调用（BaseChannel 通过 Proxy 调用 network 线程方法）
- call 层 ↔ network：RTP 包通过回调传递（Call 的 PacketReceiver 注册到 network 线程）

> ⚠️ **M144 变更**：老版有独立 "call 线程" 与 ProcessThread（模块线程）。M144 已全部删除，Call/Stream/拥塞控制/pacing 都运行在 worker 线程的 TaskQueue 上，调度统一为 `TaskQueueBase`（`api/task_queue/task_queue_base.h:27`）。

### 3.3 Proxy 模式深度解析（核心中的核心）

#### 3.3.1 Proxy 模板类源码分析

```
Proxy 的源码结构（pc/proxy.h）：

Proxy 不是传统意义上的"代理类"，而是一个**基于宏的代码生成框架**。

核心思路：
  1. 定义接口（纯虚类）
  2. 定义实现（实现接口）
  3. 用宏自动生成 Proxy 类（转发所有方法调用到目标线程）

示例：
  // 步骤 1：定义接口
  class TestInterface {
   public:
    virtual std::string FooA() = 0;
    virtual std::string FooB(bool arg1) const = 0;
    virtual std::string FooC(int arg1, int arg2) = 0;
  };

  // 步骤 2：定义实现
  class Test : public TestInterface { ... };

  // 步骤 3：用宏生成 Proxy
  BEGIN_PROXY_MAP(Test)                       // pc/proxy.h:282
    PROXY_PRIMARY_THREAD_DESTRUCTOR()
    PROXY_METHOD0(std::string, FooA)          // → primary 线程 (pc/proxy.h:324)
    PROXY_CONSTMETHOD1(std::string, FooB, arg1)
    PROXY_METHOD2(std::string, FooC, arg1, arg2)
  END_PROXY_MAP()

  // 宏展开后自动生成：
  // class TestProxyWithInternal<TestInterface> : public TestInterface {
  //   std::string FooA() override {
  //     MethodCall<TestInterface, std::string> call(c(), &TestInterface::FooA);
  //     return call.Marshal(primary_thread_);
  //   }
  //   ...
  // };
```

> ⚠️ **M144 变更**：proxy.h 位于 **pc/proxy.h**（老资料常写 api/proxy.h，api/ 下无此文件）。宏命名也有变化：老版 `PROXY_SIGNALING_THREAD_DESTRUCTOR` → `PROXY_PRIMARY_THREAD_DESTRUCTOR` / `PROXY_SECONDARY_THREAD_DESTRUCTOR`（`pc/proxy.h:302`）；老版 worker 专属方法宏（`PROXY_WORKER_METHOD2` 等）已统一为 `PROXY_METHODN`（转发到 primary 线程）与 `PROXY_SECONDARY_METHODN`。

**关键组件**：

```
MethodCall<C, R, Args...>（pc/proxy.h:101）：

  template <typename C, typename R, typename... Args>
  class MethodCall {
   public:
    typedef R (C::*Method)(Args...);
    // 构造时保存：对象指针 c_、方法指针 m_、参数（forward_as_tuple，move 语义零拷贝）
    MethodCall(C* c, Method m, Args&&... args)
        : c_(c), m_(m),
          args_(std::forward_as_tuple(std::forward<Args>(args)...)) {}

    // Marshal：投递到目标线程执行（pc/proxy.h:109）
    R Marshal(Thread* t) {
      if (t->IsCurrent()) {
        Invoke(std::index_sequence_for<Args...>());   // 已在目标线程：直接执行
      } else {
        t->PostTask([this] {                          // 投递 lambda 到目标线程
          Invoke(std::index_sequence_for<Args...>());
          event_.Set();                               // 执行完通知调用方
        });
        event_.Wait(Event::kForever);                 // 阻塞等待结果
      }
      return r_.moved_result();
    }

   private:
    template <size_t... Is>
    void Invoke(std::index_sequence<Is...>) {
      // (c_->*m_)(std::move(arg1), std::move(arg2), ...)
      r_.Invoke(c_, m_, std::move(std::get<Is>(args_))...);
    }

    C* c_;              // 目标对象的指针
    Method m_;          // 要调用的方法指针
    ReturnType<R> r_;   // 存储返回值
    std::tuple<Args&&...> args_;  // 参数（move 语义，零拷贝）
    Event event_;       // 同步事件（跨线程等待）
  };
```

> ⚠️ **M144 变更**：老版经 `SynchronousMethodCall` 类中转（Post 自身到目标线程再 `rtc::Event` 等待）；M144 已删除该类，`Marshal` 直接 `PostTask` 一个 lambda 并 `event_.Wait()`，且 `IsCurrent()` 时零开销直通。const 方法走平行的 `ConstMethodCall`（`pc/proxy.h:136`）。

**完整调用流程**：

```
调用方（signaling 线程）              目标方（worker 线程）
┌─────────────────────────┐         ┌─────────────────────────┐
│ TestProxy::FooC(1, 2)   │         │                         │
│                         │         │  线程消息/任务循环：     │
│ 1. 构造 MethodCall      │         │                         │
│    (c_, &FooC, 1, 2)    │         │                         │
│                         │         │                         │
│ 2. call.Marshal(worker) │         │                         │
│    IsCurrent()? 否      │         │                         │
│                         │         │                         │
│ 3. PostTask(lambda) ──┼──→     │  执行 lambda：           │
│                         │         │     Invoke(...)         │
│                         │         │     (c_->*m_)(1, 2)     │
│                         │         │     执行 Test::FooC     │
│                         │         │     结果存入 r_         │
│                         │         │                         │
│ 4. event_.Wait() 阻塞   │         │  event_.Set() 通知 ──┼──┐
│                         │ ←──────┼────────────────────────┘ │
│ 5. Wait() 返回           │         │                         │
│    r_.moved_result()    │         │                         │
│    = "result"           │         │                         │
│    返回给调用方          │         │                         │
└─────────────────────────┘         └─────────────────────────┘
```

#### 3.3.2 Wrap/Unwrap 设计哲学

```
Wrap/Unwrap 的核心思想：

  接口（Interface） = 对外可见的"代理"
  实现（Internal）  = 实际工作的"本体"

  BEGIN_PROXY_MAP(Test)
    // 生成的 Proxy 类：TestProxyWithInternal<TestInterface>
    // 继承自 TestInterface（对外接口）
    // 内部持有 TestInterface* c_（指向实际实现）

  为什么 Proxy 继承的是 Interface 而不是 Internal？
  - Interface 是"精简版"，只暴露上层需要的虚方法
  - Internal 可能有很多内部方法，不应该被上层看到
  - Interface 和 Internal 可以有完全不同的方法集

  典型用法：
    // 创建：Proxy 持有 Internal 的 scoped_refptr
    auto proxy = TestProxy::Create(signaling_thread, worker_thread, internal);
    // proxy 的类型是 scoped_refptr<TestProxyWithInternal<TestInterface>>
    // 但对外表现为 TestInterface*

    // 调用：Proxy 拦截所有方法调用，转发到目标线程
    std::string result = proxy->FooC(1, 2);  // 实际在 worker 线程执行
```

**设计哲学**：
- **透明代理**：调用者不知道自己在调用 Proxy，以为在调用真实对象
- **线程隔离**：Proxy 保证方法在正确的线程执行
- **接口精简**：Interface 只暴露必要方法，Internal 可以有大量内部方法

#### 3.3.3 跨线程调用完整流程

```
从 PeerConnection 到 VoiceChannel 的完整跨线程调用链（以应用本地 SDP 为例）：

PeerConnection::SetLocalDescription() (signaling 线程)
  │
  │ 委托内部 sdp_handler_
  ▼
SdpOfferAnswerHandler::ApplyLocalDescription() (signaling 线程, sdp_offer_answer.cc:1801)
  │
  │ 找到每个 m-line 对应的 transceiver → 其 channel（worker 投递）
  │ context_->worker_thread()->BlockingCall(...) (sdp_offer_answer.cc:5169)
  ▼
BaseChannel::SetLocalContent() (worker 线程, channel.cc:320)
  │
  │ 类内部直接调 _w 方法（同线程）
  ▼
VoiceChannel::SetLocalContent_w() (worker 线程, channel.cc:943)
  │
  │ 直接在 worker 线程执行（不需要再跨线程）
  ▼
VoiceMediaSendChannelInterface::SetSenderParameters() (worker 线程, media_channel.h:894)
  │
  │ 回调到 AudioSendStream
  ▼
AudioSendStream 更新编码参数 (worker 的 call TaskQueue)
  │
  │ 通过 Transport 回调
  ▼
RtpTransport::SendRtp() (network 线程)
  │
  ▼ UDPSocket::Send()

整个调用链跨越 4 层、3 个线程
signaling → worker 的跨界点由 BlockingCall 完成（效果同 Proxy，代码内联）
```

> ⚠️ **M144 变更**：老版链路是 `Proxy<ChannelManager> → ChannelManager::SetLocalContent_w → Proxy<BaseChannel>`。M144 的 ChannelManager 已删除（见 5.4）：SDP 应用由 `SdpOfferAnswerHandler`（`pc/sdp_offer_answer.h:78`）驱动，channel 直接挂在 `RtpTransceiver`（`pc/rtp_transceiver.h:121`）上，跨线程点就是 sdp_offer_answer.cc:5169 的 `worker_thread()->BlockingCall`。

#### 3.3.4 Proxy 的生命周期管理

```
Proxy 的生命周期 = scoped_refptr + 跨线程销毁

创建：
  auto proxy = TestProxy::Create(signaling_thread, worker_thread, internal);
  // 内部：new rtc::RefCountedObject<TestProxyWithInternal>(...)
  // ref_count = 1

传递到其他线程：
  PostTask(..., [proxy] { proxy->DoSomething(); });
  // lambda 捕获 proxy → ref_count++
  // ref_count = 2

在目标线程使用：
  proxy->DoSomething();  // ref_count 不变（已经是 scoped_refptr）

离开作用域：
  }  // proxy 离开 signaling 线程作用域
    // ref_count-- = 1

最后一个 scoped_refptr 离开：
  }  // ref_count-- = 0
    // → 调用 Proxy 的析构函数
    // → Proxy 析构函数 Post 一个 DestroyInternal 消息到 destructor_thread
    // → 在 destructor_thread 上执行：delete c_（销毁内部对象）
```

**关键设计**：
- 析构函数是**保护的**（protected），只能通过 scoped_refptr 销毁
- 销毁操作 Post 到 destructor_thread（通常是 signaling 线程）
- 使用 `scoped_refptr<INTERNAL_CLASS> c_` 而不是 `unique_ptr`，防止重入回调导致悬空指针

### 3.4 sigslot 信号槽：同线程事件通知

```
sigslot 架构（编译期绑定）：

class Connection : public sigslot::has_slots<> {
 public:
  void OnConnected(bool success) { ... }  // "槽"
};

class PeerConnection : public sigslot::has_slots<> {
 public:
  sigslot::signal1<bool> SignalConnected;  // "信号"
};

// 连接信号和槽：
pc.SignalConnected.connect(&conn, &Connection::OnConnected);

// 发射信号（同线程内调用所有槽）：
pc.SignalConnected(true);  // → 自动调用 conn.OnConnected(true)
```

**架构特点**：
- **头库分离**：纯头库，无编译依赖
- **编译期绑定**：类型安全，无运行时反射开销
- **同线程**：信号发射时同步调用所有槽函数
- **自动断开**：槽对象析构时自动断开连接（无悬空指针）

**与 Observer 模式对比**：

```
传统 Observer：Observer 析构后 Subject 仍持有悬空指针 → crash
sigslot：槽对象析构自动断开连接 → 安全
```

### 3.5 scoped_refptr：引用计数 + 创建线程销毁

```
scoped_refptr<T> = 智能指针 + 线程安全引用计数 + 创建线程销毁

核心设计：
1. 引用计数存储在对象内部（RefCountedObject::ref_count_）
2. AddRef()/Release() 是原子操作（线程安全）
3. 销毁在创建线程上进行（不是引用计数归零的线程）

为什么销毁要在创建线程？
- 创建线程拥有该对象的所有资源（Socket、文件描述符等）
- 其他线程可能没有权限访问这些资源
- 避免跨线程析构导致的资源泄漏

RefCountedObject 的关键代码（rtc_base/ref_counted_object.h:38-43）：

  virtual RefCountReleaseStatus Release() const {
    const auto status = ref_count_.DecRef();
    if (status == RefCountReleaseStatus::kDroppedLastRef) {
      delete this;  // 在调用 Release() 的线程上销毁！
    }
    return status;
  }

注意：RefCountedObject::Release() 是在调用 Release() 的线程上销毁对象。
Proxy 模式通过额外一层间接解决了这个问题：Proxy 的析构函数 Post
DestroyInternal 到 destructor_thread，确保对象在正确的线程销毁。
```

### 3.6 并发架构的优缺点分析

**优点**：
- **零锁高性能**：无锁竞争，延迟可预测
- **缓存友好**：数据不跨线程迁移，CPU 缓存命中率高
- **线程安全内置**：不需要开发者手动加锁
- **可测试性**：测试时可以让所有线程变成同一个线程

**缺点**：
- **代码复杂度**：Proxy 模式增加大量模板代码
- **使用门槛高**：开发者必须理解线程归属
- **调试困难**：跨线程调用链追踪困难
- **栈溢出风险**：同步 Proxy 调用链过长可能导致栈溢出

---

## 第 4 章：rtc_base 模块架构 —— 基础设施的架构

### 4.1 模块定位

rtc_base 是所有上层模块的**基石**。它不依赖任何其他 WebRTC 模块（除了极少数系统封装），提供了：

```
rtc_base 提供的核心能力：

线程系统          Thread / MessageHandler / 消息循环
任务队列          Thread 同时实现 TaskQueueBase 接口
Socket 抽象       AsyncSocket / UDPSocket / SSLStreamAdapter
信号槽            sigslot
引用计数          scoped_refptr
同步原语          CriticalSection / Event
日志              LogMessage
字符串工具        StringBuilder / StringTokenizer
```

> ⚠️ **M144 变更**：`Clock` 已不在 rtc_base，位于 `system_wrappers/include/clock.h:32`（`Timestamp`/`TimeDelta` 等时间类型在 `api/units/`）。另外 rtc_base 现在只提供"消息循环"这一种调度形态还不够——M144 统一调度原语是 **TaskQueueBase**（`api/task_queue/task_queue_base.h:27`）：`rtc::Thread` 实现了 `TaskQueueBase` 接口（`Thread::PostTask`/`PostDelayedTask`），周期任务用 `RepeatingTaskHandle`（`rtc_base/task_utils/repeating_task.h`）。老的 `ProcessThread`（模块线程）已从 rtc_base 删除，见 9.1.3。

### 4.2 线程架构：基于消息的线程模型

```
Thread 架构的核心设计：

每个 Thread 对象 = 一个 OS 线程 + 一个消息队列

┌──────────────────────────────────────────────────┐
│  Thread                                            │
│  ┌────────────────────────────────────────────┐  │
│  │ OS Thread (独立线程)                         │  │
│  │  ┌──────────────────────────────────────┐  │  │
│  │  │ MessageLoop() 循环：                    │  │  │
│  │  │   1. 处理定时器事件                     │  │  │
│  │  │   2. 处理消息队列中的 Message           │  │  │
│  │  │   3. 处理 Socket 可读/可写事件          │  │  │
│  │  │   4. 处理 PostTask                      │  │  │
│  │  └──────────────────────────────────────┘  │  │
│  │                                              │  │
│  │ 消息队列：                                    │  │
│  │  ┌──────┐ ┌──────┐ ┌──────┐                 │  │
│  │  │Msg1  │→│Msg2  │→│Msg3  │→ ...            │  │
│  │  └──────┘ └──────┘ └──────┘                 │  │
│  └────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

**架构特点**：
- 每个 Thread 绑定一个 OS 线程
- `PostMessage()` 将消息放入队列，不阻塞调用者
- `Run()` 进入消息循环，阻塞处理消息
- `ProcessAllMessages()` 同步处理所有消息（测试用）

**与回调链模型对比**：

```
回调链模型（Node.js 风格）：
  A → callback → B → callback → C
  问题：回调地狱，错误处理复杂

WebRTC 的消息模型：
  A → PostMessage(B) → B 的 MessageLoop 处理
  优势：每个消息独立处理，错误可在消息处理器中捕获
```

### 4.3 Socket 抽象层

```
AsyncSocket 继承体系：

                    AsyncSocket (纯虚基类)
                   /        |        \
                  /         |         \
         UDPSocket    TCPSocket  DTLSSocket
            |           |           |
            |      SSLSocketAdapter（装饰器）
            |
        Platform-specific:
        - Windows: Win32 Socket
        - POSIX: epoll/kqueue
```

**架构特点**：
- `AsyncSocket` 统一异步 Socket API（`Send()`/`Receive()`/`Connect()`）
- 所有 Socket 操作异步完成，通过 `OnConnect()`/`OnRead()`/`OnWritable()` 回调通知
- `SSLStreamAdapter` 用**装饰器模式**包装 Socket，透明添加 SSL/TLS

### 4.4 sigslot 信号槽架构

```
sigslot 架构（编译期绑定）：

class Connection : public sigslot::has_slots<> {
 public:
  void OnConnected(bool success) { ... }  // "槽"
};

class PeerConnection : public sigslot::has_slots<> {
 public:
  sigslot::signal1<bool> SignalConnected;  // "信号"
};

pc.SignalConnected.connect(&conn, &Connection::OnConnected);
pc.SignalConnected(true);  // → 自动调用 conn.OnConnected(true)
```

**架构特点**：
- **头库分离**：纯头库，无编译依赖
- **编译期绑定**：类型安全，无运行时反射开销
- **同线程**：信号发射时同步调用所有槽函数
- **自动断开**：槽对象析构时自动断开连接

### 4.5 scoped_refptr 引用计数架构

```
scoped_refptr 架构设计：

scoped_refptr<T> = 智能指针 + 线程安全引用计数 + 创建线程销毁

关键设计：
1. 引用计数存储在对象内部（RefCountedObject::ref_count_）
2. AddRef()/Release() 是原子操作（线程安全）
3. 销毁在创建线程上进行（Proxy 模式通过 DestroyInternal 实现）

RefCountedObject 的关键代码（rtc_base/ref_counted_object.h:38-43）：

  virtual RefCountReleaseStatus Release() const {
    const auto status = ref_count_.DecRef();
    if (status == RefCountReleaseStatus::kDroppedLastRef) {
      delete this;
    }
    return status;
  }
```

### 4.6 rtc_base 架构优缺点

**优点**：
- **极简高效**：消息模型开销极小
- **头库分离**：sigslot、scoped_refptr 都是头库
- **跨平台**：Thread 封装了 Windows/POSIX 线程差异

**缺点**：
- **消息模型不直观**：新手难以理解 PostMessage 的异步语义
- **调试困难**：消息在队列中排队，断点调试时难以追踪
- **线程绑定严格**：对象必须在创建线程销毁

---

## 第 5 章：pc/ 模块架构 —— 信令与媒体控制的架构

### 5.1 模块定位

pc/ 是 WebRTC 的**总控中心**，负责：
- SDP 协商（Offer/Answer/BYE/Rollback）
- ICE 状态管理（候选收集、连接检查、ICE Restart）
- DTLS 握手与密钥管理
- 媒体通道管理（VoiceChannel/VideoChannel/RtpDataChannel）
- DataChannel 协商（SCTP over DTLS）

### 5.2 PeerConnection 架构：Facade 模式

```
PeerConnection 作为 Facade（外观）：

                    PeerConnection
                    （统一入口）
                         │
            ┌────────────┼────────────┐
            │            │            │
     JsepTransportCtrl  ChannelMgr   MediaSession
     （传输控制）       （媒体通道）   （会话状态）
            │            │            │
     ┌──────┴──────┐  VoiceChannel   会话描述
     │            │  VideoChannel    SDP 状态
  ICE      DTLS    │            DataChannel
  状态机   握手    │
                 RtpTransceiver
```

**架构特点**：
- **Facade 模式**：上层只需调用 `CreateOffer()`，内部自动协调多个子模块
- **内部协调**：PeerConnection 不直接实现 ICE/DTLS/SDP，而是委托给子模块
- **对外简洁**：对外 API 与 W3C WebRTC API 对齐

### 5.3 JsepTransportController 架构：传输抽象

```
JsepTransportController 的传输管理：

  JsepTransportController
  ┌──────────────────────────────────────┐
  │  mid="0"  ─→ JsepTransport            │
  │           ├─ ICE Transport            │
  │           ├─ DTLS Transport (RTP)     │
  │           ├─ DTLS Transport (RTCP)    │
  │           ├─ SRTP Transport (RTP)     │
  │           └─ SCTP Transport           │
  │                                        │
  │  mid="1"  ─→ JsepTransport (BUNDLED)  │
  │           └─ 复用 mid="0" 的 ICE/DTLS  │
  │                                        │
  │  mid="2"  ─→ JsepTransport (Data)     │
  │           └─ 复用 mid="0" 的 ICE/DTLS  │
  └──────────────────────────────────────┘

  BUNDLE 机制：所有 m= section 复用同一个 ICE/DTLS 传输
  优势：减少连接数（1 个 UDP 连接代替 N 个），降低 NAT 穿透难度
```

### 5.4 RtpTransceiver/RtpTransmissionManager 架构：通道的归属与跨线程桥接

> ⚠️ **M144 变更**：老版的 `ChannelManager`（pc/channel_manager.h，集中创建/持有全部 VoiceChannel/VideoChannel 的管理类）**已删除**，pc/ 下无此文件。M144 中通道的"归属权"下放到 **RtpTransceiver**——每个 transceiver 直接持有自己的 channel；transceiver 列表由 **RtpTransmissionManager**（`pc/rtp_transmission_manager.h:73`，PeerConnection 的成员，同时管理 RtpSender/RtpReceiver）维护；SDP 协商则拆给 **SdpOfferAnswerHandler**（`pc/sdp_offer_answer.h:78`，PeerConnection 持 `sdp_handler_`，见 `pc/peer_connection.h:739`）。

```
M144 的通道归属与创建链（RtpTransceiver::CreateChannel, pc/rtp_transceiver.cc:204）：

RtpTransmissionManager (signaling 线程)
  │  维护 transceivers_ 列表, AddTrack/RemoveTrack 入口 (rtp_transmission_manager.h:95)
  ▼
RtpTransceiver (signaling/worker 双亲和)
  │  持 std::unique_ptr<ChannelInterface> channel_ (rtp_transceiver.h:121/366)
  │  CreateChannel() 内 worker_thread()->BlockingCall([...]):
  ▼
worker 线程上：
  media_engine()->voice().CreateSendChannel(...)     → VoiceMediaSendChannelInterface
  media_engine()->voice().CreateReceiveChannel(...) → VoiceMediaReceiveChannelInterface
  std::make_unique<VoiceChannel>(send, receive, ...) → BaseChannel 持两个 media channel
  (视频路径同理: video().CreateSendChannel/CreateReceiveChannel → VideoChannel)

支撑设施：
  MediaFactory (pc/media_factory.h:39) —— 创建 Call 与 MediaEngine 的接口
    └ 由 ConnectionContext 持有 (pc/connection_context.h:105/166)
       依赖经 PeerConnectionFactoryDependencies 注入 (api/peer_connection_interface.h:1428)

三线程桥接（语义不变，桥接点换了位置）：
signaling 线程                    worker 线程                    network 线程
┌──────────────┐              ┌──────────────────┐           ┌──────────────┐
│ PeerConnection│              │RtpTransceiver     │           │ BaseChannel  │
│ sdp_handler_  │ ─BlockingCall→ │ channel_         │ ─Proxy─→  │ _n 方法      │
│ 应用描述      │              │ BaseChannel+media │  跨线程    │ (网络操作)   │
│              │ ←─同步返回──── │ channel 实现      │ ←Proxy─   │              │
└──────────────┘              └──────────────────┘           └──────────────┘
```

> 源码对照：`RtpTransceiver::CreateChannel`（`pc/rtp_transceiver.cc:204-270`）；`channel_` 成员（`pc/rtp_transceiver.h:121`，`:366` 注释）；`RtpTransmissionManager`（`pc/rtp_transmission_manager.h:73`）；`SdpOfferAnswerHandler`（`pc/sdp_offer_answer.h:78`）；`MediaFactory`（`pc/media_factory.h:39`）；`ConnectionContext` 持有（`pc/connection_context.h:105/166`）。

### 5.5 BaseChannel 架构：媒体通道的通用设计

```
BaseChannel 的线程亲和标注（pc/channel.h:70）：

class BaseChannel : public ... {
 public:
  bool SetLocalContent(...) {
    return InvokeOnWorker(..., &BaseChannel::SetLocalContent_w);   // channel.cc:320
  }
  // _w: worker 线程  _n: network 线程
  bool SetLocalContent_w(...) { ... }   // VoiceChannel 实现: channel.cc:943
  bool SetLocalContent_n(...) { ... }
};
```

> M144 中 BaseChannel 同时持有两个 media channel 接口指针：`media_send_channel_` / `media_receive_channel_`（CreateChannel 时由 MediaEngine 分别创建，`pc/rtp_transceiver.cc:232-252`）；发送/接收参数设置走对应接口（`VoiceMediaSendChannelInterface::SetSenderParameters`，`media/base/media_channel.h:894`）。

### 5.6 DataChannel 架构：SCTP over DTLS

```
DataChannel 的传输栈：

应用层数据
    │
    ▼
┌─────────────────────┐  ← 应用接口（RTCDataChannel）
│  DataChannel         │
│  ├─ ReliabilityMode  │
│  └─ Ordered/Unordered│
    │
    ▼
┌─────────────────────┐  ← SCTP 协议层
│  SctpTransport       │
│  ├─ Stream 管理      │
│  ├─ 分段/重组        │
│  └─ 重传机制         │
    │
    ▼
┌─────────────────────┐  ← DTLS 加密层
│  DtlsTransport       │
│  ├─ 密钥管理         │
│  └─ SRTP 密钥派生    │
    │
    ▼
┌─────────────────────┐  ← ICE/传输层
│  P2PTransportChannel │
│  ├─ 候选管理         │
│  └─ Connection Check │
    │
    ▼
┌─────────────────────┐  ← 网络层
│  UDPSocket           │
└─────────────────────┘
```

### 5.7 pc/ 模块架构优缺点

**优点**：
- **Facade + Proxy 组合**：对外简洁，对内灵活
- **BUNDLE 设计**：通过 MID 头扩展实现传输复用
- **线程亲和标注**：方法后缀让线程归属一目了然

**缺点**：
- **线程切换频繁**：一次 SDP 协商涉及多次跨线程调用
- **调试链路过长**：从 PeerConnection 到 UDPSocket 跨越 4 层、3 个线程
- **所有权分散**：channel 由各 RtpTransceiver 持有 unique_ptr，销毁时序依赖 transceiver 生命周期管理（M144 已无集中式 ChannelManager 统一销毁）

---

## 第 6 章：call/ 模块架构 —— 媒体流的调度中心

### 6.1 模块定位

call/ 是 WebRTC 的**媒体流工厂 + 调度中心**。它不处理 SDP/ICE/DTLS，只负责：
- 创建和销毁音视频 Send/Receive Stream
- 管理发送侧拥塞控制（GCC/BWE/Pacing）
- 接收 RTP 包并分发到对应的 Receive Stream
- 提供统一的 Stats 接口

### 6.2 Call 类架构：工厂模式 + 统一生命周期管理

```
Call 类的工厂模式：

                    Call (抽象基类)
                   /    \
                  /      \
         CallImpl (实际实现)
         ┌──────────────────────────────────────┐
         │  工厂方法（创建）     销毁方法         │
         │  CreateAudioSendStream()   Destroy... │
         │  CreateVideoSendStream()   Destroy... │
         │                                      │
         │  内部对象：                            │
         │  AudioSendStream[0..N]                │
         │  VideoSendStream[0..N]                │
         │  RtpTransportControllerSend           │
         │  PacketReceiver (RTP 分发器)          │
         └──────────────────────────────────────┘
```

### 6.3 AudioSendStream 架构：音频发送管线

```
AudioSendStream 内部处理链：

麦克风 PCM 数据
    │
    ▼
┌─────────────────────┐
│ AudioProcessing     │  ← AEC3 / NS / AGC / HPF (api/audio/audio_processing.h:121)
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ AudioEncoder        │  ← Opus / G722 / RED 编码 (acm2 栈, modules/audio_coding/)
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ RTPSender           │  ← RTP 封包 (modules/rtp_rtcp/source/rtp_sender.h:45)
│ + RTCPSender         │    + RTCP 报告 (rtcp_sender.h:50)
└─────────────────────┘    (SRTP 加密在 Transport 层做, pc/srtp_transport.h:38)
    │
    ▼
RtpTransportControllerSend → TaskQueuePacedSender → UDPSocket → 网络
```

> ⚠️ **M144 变更**：老版音频管线写 `AudioCodingModule`（ACM）+ `RtpBuilder`。M144 发送侧 AudioSendStream 直接持有 `AudioEncoder`（编解码栈在 `modules/audio_coding/acm2/`，ACM 类已无）；RTP 封包是独立的 `RTPSender`/`RTCPSender`（拆自老 RtpRtcp），无 "RtpBuilder" 类。

### 6.4 VideoSendStream 架构：视频发送管线

```
VideoSendStream 内部处理链（单路）：

原始视频帧 (I420)
    │
    ▼
┌─────────────────────┐
│ 视频源适配           │  ← 分辨率/帧率适配 (video/adaptation/, VideoStreamEncoder 内)
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ VideoEncoder        │  ← VP8 / VP9 / H264 / AV1 编码 (Simulcast/SVC)
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ RTPSender           │  ← RTP 封包; 重传响应 + ULPFEC/FlexFEC 冗余生成
│ + RTCPSender         │    (fec: modules/rtp_rtcp/source/ulpfec_generator.h:38)
└─────────────────────┘    (SRTP 加密在 pc/srtp_transport.h:38 的 Transport 层)
    │
    ▼
RtpTransportControllerSend → TaskQueuePacedSender → 网络
```

> ⚠️ **M144 变更**：老版管线的 `VideoProcessing`（VPM）与 `RtpBuilder` 类均不存在（modules/ 无 video_processing/ 目录）。视频裁剪/旋转/缩放等轻量处理并入 `VideoStreamEncoder` 的适配管线（`video/adaptation/`）；NACK 在发送侧是"响应重传请求"（重传请求由**接收端** `NackRequester` 发出，见 9.3）。

**Simulcast 架构**（多路编码）：

```
原始视频帧 (I420, 640x480)
    │
    ├──→ VP8 Encoder (q30) → 144x90, ~100kbps  ──┐
    ├──→ VP8 Encoder (q20) → 320x180, ~300kbps  ├─→ BWE 选择最优路
    └──→ VP8 Encoder (q10) → 640x360, ~900kbps  ──┘
```

### 6.5 RtpTransportControllerSend 架构：发送侧拥塞控制

```
拥塞控制闭环（RtpTransportControllerSend, call/rtp_transport_controller_send.h:64）：

  ┌─────────────────────────────────────────────────────────┐
  │   ┌──────────────┐   码率建议    ┌───────────────────┐   │
  │   │ GoogCc       │ ──────────→  │ TaskQueuePaced    │   │
  │   │ NetworkCtrl  │              │ Sender (pacing)   │   │
  │   │ + BitrateAllo│              │ cation (call/)    │   │
  │   └────┬─────────┘              └────┬──────────────┘   │
  │        │                             │                  │
  │        │  发送 RTP 包                 │                  │
  │        └─────────────────────────────┘                  │
  │                             │                          │
  │                    网络传输 (丢包/排队)                   │
  │                             │                          │
  │              接收端生成 transport-cc 反馈                │
  │              (TransportSequenceNumberFeedbackGenenerator │
  │               / CongestionControlFeedbackGenerator       │
  │               modules/remote_bitrate_estimator/)         │
  │                             │                          │
  │                    ┌────────┴────────┐                  │
  │                    │ 反馈进入          │                  │
  │                    │ GoogCcNetwork    │                  │
  │                    │ Controller      │                  │
  │                    └────────┬────────┘                  │
  │                             │                          │
  │                    更新带宽估计 (NetworkControlUpdate)   │
  │                    └───────────────────────────────────┘
  └─────────────────────────────────────────────────────────┘
```

> ⚠️ **M144 变更**：老版图中接收端 `RemoteBitrateEstimator` + REMB 是主反馈路径。M144 主路径是 **transport-cc**（接收端 `TransportSequenceNumberFeedbackGenenerator` 生成逐包到达反馈，源码即此拼写）或 **RFC 8888**（`CongestionControlFeedbackGenerator`，L4S 场景）；REMB 仅作兼容回退保留（`SendSideBandwidthEstimation` 内，`remb_throttler`）。"GCC" 实现为 `GoogCcNetworkController`（`modules/congestion_controller/goog_cc/goog_cc_network_control.h:46`）。

### 6.6 call/ 模块架构优缺点

**优点**：
- **工厂模式 + 配置驱动**：新增流类型只需加接口
- **拥塞控制闭环完整**：BWE → Pacing → 网络 → RTCP → BWE
- **Simulcast 原生支持**：多编码器并行

**缺点**：
- **Config 结构体膨胀**：AudioSendStream::Config 30+ 字段，VideoSendStream::Config 40+ 字段
- **Stream 间共享 BWE**：所有 Stream 共享一个 RtpTransportControllerSend

---

## 第 7 章：传输架构 —— 协议栈设计

### 7.1 JsepTransportController 的传输抽象

```
JsepTransportController 是传输层的"总控"：

                    JsepTransportController
                           │
            ┌──────────────┼──────────────┐
            │              │              │
     SetLocal      SetRemote       GetRtpTransport
     Description    Description     (by mid)
            │              │              │
            ▼              ▼              ▼
     创建/更新/      创建/更新/      返回 JsepTransport*
     销毁 Jsep       销毁 Jsep       （可能多个 mid
     Transport       Transport        指向同一对象）
```

**架构特点**：
- **按 m= section 管理传输**：每个 SDP m= section 对应一个 JsepTransport
- **BUNDLE 复用**：所有媒体传输复用同一个 ICE/DTLS，通过 MID 头扩展区分
- **SDP 与传输解耦**：SetLocalDescription/SetRemoteDescription 触发传输的创建/更新/销毁

### 7.2 JsepTransport 的多层包装结构

```
JsepTransport 的层层包装（从内到外）：

                    JsepTransport
                    （最外层：SDP 相关操作）
                           │
            ┌──────────────┼──────────────┐
            │              │              │
     ICE      DTLS        SRTP          SCTP
     Transport Transport  Transport     Transport
            │              │              │
            │         ┌────┴────┐        │
            │         │         │        │
         UDP Socket  DTLS     SRTP      Multi-stream
         (网络层)   加密层    加密层     (SCTP)
                    │         │
                    ▼         ▼
              密钥协商   媒体加密
```

**每一层的职责**：
- **ICE Transport**：候选管理、Connection Check、连通性维护
- **DTLS Transport**：证书管理、密钥协商、握手状态机
- **SRTP Transport**：基于 DTLS 密钥的 RTP/RTCP 加密
- **SCTP Transport**：DataChannel 的多流传输

### 7.3 RTP/DTLS/ICE 的层次关系

```
协议栈层次（从下到上）：

┌─────────────────────────────────────┐
│  RTP / RTCP（媒体传输协议）           │  ← 应用层
├─────────────────────────────────────┤
│  SRTP（RTP 加密）                    │  ← 安全层
├─────────────────────────────────────┤
│  DTLS（密钥协商）                    │  ← 安全层
├─────────────────────────────────────┤
│  ICE / STUN（NAT 穿透）             │  ← 网络层
├─────────────────────────────────────┤
│  UDP / TCP（传输层）                 │  ← 传输层
├─────────────────────────────────────┤
│  IP（网络层）                        │  ← 网络层
└─────────────────────────────────────┘
```

**关键设计**：
- DTLS 不仅用于加密，还用于**密钥协商**（生成 SRTP 密钥）
- ICE 在 DTLS 之前，确保两端能互相找到网络地址
- SRTP 的密钥来自 DTLS 握手，不需要单独的密钥分发

### 7.4 BUNDLE 复用机制的架构设计

```
BUNDLE 机制（无 BUNDLE）：

  m=audio  → ICE1 + DTLS1 + SRTP1  (UDP port 1)
  m=video  → ICE2 + DTLS2 + SRTP2  (UDP port 2)
  m=data   → ICE3 + DTLS3 + SCTP3  (UDP port 3)
  共 3 个 UDP 连接，3 套 DTLS 握手

BUNDLE 机制（有 BUNDLE）：

  m=audio  ─┐
  m=video  ─┼→  ICE1 + DTLS1 + SRTP1 (UDP port 1, MID 区分)
  m=data   ─┘
  共 1 个 UDP 连接，1 套 DTLS 握手

架构优势：
- NAT 穿透成功率更高（1 个连接代替 N 个）
- 防火墙友好（减少端口开放数量）
- DTLS 握手开销减少 N-1 倍
```

### 7.5 Datagram Transport 的架构扩展点

```
Datagram Transport（实验性功能）：

  传统路径：RTP → DTLS → ICE → UDP
       │
       ▼
  新路径：RTP → DatagramTransport → ICE → UDP/DCCP

  架构设计：
  - DatagramTransport 接口与 RTP Transport 并行存在
  - 通过 a=x-mt SDP 属性协商是否启用
  - 可以复用 ICE 候选，但使用不同的传输协议（如 DCCP）

  扩展点：
  - JsepTransport 中 datagram_transport_ 成员
  - CompositeRtpTransport 选择 RTP 或 Datagram 传输
  - 未来可扩展 QUIC 等新型传输协议
```

### 7.6 传输栈的层层包装架构图

```
完整传输栈（一个 RTP 包的旅程）：

┌─────────────────────────────────────────────────────┐
│  RTP Packet (音视频数据 + RTP 头)                    │
│  ↑                                                   │
│  ┌─────────────────────────────────────────────────┐│
│  │ JsepTransport (SDP 相关操作)                     ││
│  │  - MID 头扩展标记 (BUNDLE)                       ││
│  │  - RTCP mux 判断                                 ││
│  │  ┌─────────────────────────────────────────────┐││
│  │  │ DtlsSrtpTransport (SRTP 加密)                │││
│  │  │  - 基于 DTLS 密钥加密 RTP                    │││
│  │  │  ┌─────────────────────────────────────────┐│││
│  │  │  │ DtlsTransport (DTLS 握手 + 密钥管理)     ││││
│  │  │  │  - 证书管理                              ││││
│  │  │  │  - 握手状态机                            ││││
│  │  │  │  ┌─────────────────────────────────────┐││││
│  │  │  │  │ P2PTransportChannel (ICE 连接管理)   │││││
│  │  │  │  │  - Candidate Pair 管理               │││││
│  │  │  │  │  - Connection Check 状态机            │││││
│  │  │  │  │  ┌─────────────────────────────────┐│││││
│  │  │  │  │  │ Port (Host/Stun/Turn)            ││││││
│  │  │  │  │  │  - UDP Socket                    ││││││
│  │  │  │  │  └─────────────────────────────────┘│││││
│  │  │  │  └─────────────────────────────────────┘││││
│  │  │  └─────────────────────────────────────────┘│││
│  │  └─────────────────────────────────────────────┘││
│  └─────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────┘
```

> 源码对照：`JsepTransport`（`pc/jsep_transport.h`）持有 `RtpTransport`（`pc/rtp_transport.h`，负责 MID/BUNDLE 路由与 RTCP mux 判断）与 `SctpTransport`；加密层为 `SrtpTransport`（`pc/srtp_transport.h:38`）→ `DtlsSrtpTransport`（`pc/dtls_srtp_transport.h:32`，DTLS 协商出的密钥写回 SRTP）；其下 `DtlsTransport`（`pc/dtls_transport.h:33`）；ICE 层 `P2PTransportChannel`（`p2p/base/p2p_transport_channel.h:98`）；端口层基类 `Port`（`p2p/base/port.h`），其中 UDPPort 定义在 `p2p/base/stun_port.h:49`（无独立 udp_port.h），另有 `StunPort`（stun_port.h:254）、`TurnPort`（turn_port.h:55）、`TcpPort`（tcp_port.h）。

---

## 第 8 章：媒体管道架构 —— 数据流设计

### 8.1 音频管道：Mic → ADM → APE → 编码 → RTP → 网络

```
完整音频发送管道（M144）：

┌─────────────────────────────────────────────────────────────┐
│  signaling 线程                     worker 线程               │
│  ┌──────────────┐               ┌──────────────┐            │
│  │ PeerConnection│               │RtpTransceiver │            │
│  │ AddTrack()    │ ─Proxy─→     │CreateChannel()│            │
│  │ SetLocalDesc()│               │(BlockingCall) │            │
│  │  ↓sdp_handler_│               └──────┬───────┘            │
│  │ SdpOfferAnswer│                      │                    │
│  │ Handler       │                      ▼                    │
│  │ ApplyLocalDesc│─BlockingCall─→ ┌──────────────────┐      │
│  └──────────────┘                │ VoiceChannel      │      │
│                                  │ (BaseChannel,     │      │
│                                  │  worker 线程)     │      │
│                                  └────────┬─────────┘      │
│                                           │                  │
│                                           ▼                  │
│                                  ┌──────────────────┐      │
│                                  │ VoiceMediaSend-   │      │
│                                  │ ChannelInterface  │      │
│                                  │ (worker 线程)     │      │
│                                  └────────┬─────────┘      │
│                                           │                  │
│                                           ▼                  │
│  Call (worker TaskQueue)        ┌──────────────────┐      │
│  ┌──────────────┐ ←─持有────── │ AudioSendStream   │      │
│  │ CreateAudio  │               │ (worker 线程)     │      │
│  │ SendStream() │               └────────┬─────────┘      │
│  └──────────────┘                        │                  │
│                                          ▼                  │
│  Mic → ADM 采集回调               ┌──────────────────┐      │
│  ┌──────────────┐               │ AudioProcessing   │      │
│  │ ADM          │ ─APM 捕获──→  │ (AEC3/NS/AGC2/   │      │
│  │ RecordedData │   管线         │  HPF)             │      │
│  └──────────────┘               └────────┬─────────┘      │
│                                          ▼                  │
│                                 ┌──────────────────┐       │
│                                 │ AudioEncoder      │       │
│                                 │ (acm2: Opus/     │       │
│                                 │  G722/PCM16b)    │       │
│                                 └────────┬─────────┘       │
│                                          ▼                  │
│                                 ┌──────────────────┐       │
│                                 │ RTPSender +      │       │
│                                 │ RTCPSender       │       │
│                                 │ (RTP 封包/RTCP)  │       │
│                                 └────────┬─────────┘       │
│                                          ▼                  │
│  network 线程              ┌──────────────────┐           │
│  ┌──────────────┐         │ RtpTransport-    │           │
│  │ P2PTransport │ ←────── │ ControllerSend   │           │
│  │ Channel      │         │ (TaskQueuePaced- │           │
│  │ UDPSocket     │         │  Sender + SRTP)  │           │
│  └──────────────┘         └────────┬─────────┘           │
│                                    ▼                      │
│                                 网络发送                    │
└─────────────────────────────────────────────────────────────┘
```

> 源码对照：`RtpTransmissionManager::AddTrack`（pc/rtp_transmission_manager.h:95）在 signaling 线程创建 `RtpTransceiver`；SDP 应用链 `SdpOfferAnswerHandler::ApplyLocalDescription`（pc/sdp_offer_answer.cc:1801）→ `worker_thread()->BlockingCall`（:5169）→ `RtpTransceiver`/channel 内容应用；`RtpTransceiver::CreateChannel`（pc/rtp_transceiver.cc:204）经 `MediaFactory` 的 `CreateSendChannel/CreateReceiveChannel` 造出 `VoiceChannel`；发送接口 `VoiceMediaSendChannelInterface`（media/base/media_channel.h:894）实现为 `WebRtcVoiceSendChannel`（pc/webrtc_voice_engine.h:188）；`AudioSendStream`（audio/audio_send_stream.h）归 `Call` 管（call/call.h:71）；APM 管线见 api/audio/audio_processing.h:121；编码经 acm2（modules/audio_coding/）；封包 `RTPSender`（rtp_sender.h:45）+ `RTCPSender`（rtcp_sender.h:50），SRTP 加密在 `SrtpTransport`（pc/srtp_transport.h:38）层。

> ⚠️ M144 变更：老版图中 `ChannelManager::CreateVoice` 与独立 "call 线程" 已不存在——channel 归 RtpTransceiver 持有，call 层逻辑跑在 worker 的 TaskQueue 上；`ACM`/`RtpBuilder` 类名已删，编码由 AudioEncoder（acm2）承担、封包由 RTPSender 承担。

### 8.2 视频管道：采集 → 适配降级 → 编码 → NACK/FEC → RTP → 网络

```
完整视频发送管道（M144）：

视频采集设备 (Camera/Desktop)
    │
    │ VideoFrame (scoped_refptr, 引用计数共享)
    ▼
┌──────────────────────┐
│ VideoTrackSource     │  ← AdaptedVideoTrackSource
│ (裁剪/旋转/缩放适配)  │    (media/base/adapted_video_track_source.h:37)
└──────────┬───────────┘   + video/adaptation/ 降级决策
           │
           │ VideoFrame (适配后的分辨率)
           ▼
┌──────────────────────┐
│ VideoEncoder         │  ← VP8/VP9/H264/AV1
│ (编码)                │
└──────────┬───────────┘
           │
           │ EncodedImage (已编码)
           ▼
┌──────────────────────┐
│ RTPSender + FEC/NACK │  ← UlpfecGenerator (ulpfec_generator.h:38)
│ (RTP 封包 + 保护策略) │    RTX 重传 (NACK 响应)
└──────────┬───────────┘
           │
           │ RTP Packet
           ▼
┌──────────────────────┐
│ RtpTransportControllerSend│  ← TaskQueuePacedSender 整形发送
│ (Pacing + SRTP)      │    SRTP 加密在 SrtpTransport 层
└──────────┬───────────┘
           │
           ▼
        网络发送
```

> 源码对照：采集源适配基类 `AdaptedVideoTrackSource`（media/base/adapted_video_track_source.h:37），降级决策在 `video/adaptation/`（Resource 状态机 + VideoStreamBufferController）；保护策略 `UlpfecGenerator`（modules/rtp_rtcp/source/ulpfec_generator.h:38）、重传由 `RTPSender`（rtp_sender.h:45）的 RTX 逻辑承担；Pacing `TaskQueuePacedSender`（modules/pacing/task_queue_paced_sender.h:39）。

> ⚠️ M144 变更：老版图中的 `VideoProcessThread`/`VideoProcessingModule (VPM)` 已不存在——M144 没有 modules/video_processing/，帧的裁剪/旋转/缩放在采集源适配层完成；`RtpBuilder` 类已删，封包归 RTPSender。

### 8.3 管道中的 Zero-Copy 设计

```
Zero-Copy 设计：

传统方式（有拷贝）：
  采集帧 (I420, 1.5MB @ 1080p)
    │
    ▼
  memcpy → 编码输入缓冲 (1.5MB)  ← 一次拷贝
    │
    ▼
  memcpy → RTP 包缓冲 (可变)     ← 二次拷贝

WebRTC 方式（零拷贝）：
  采集帧 (scoped_refptr<VideoFrame>)
    │
    │ 传递指针，不拷贝数据
    ▼
  VideoTrackSource 适配 (直接操作 I420 数据)
    │
    │ 传递指针，不拷贝数据
    ▼
  VideoEncoder (直接读取 I420 数据)
    │
    ▼
  EncodedImage (编码后才有新数据，必须分配)

关键类：
- scoped_refptr<VideoFrame>：引用计数的视频帧
- I420Buffer：I420 帧缓冲池（对象复用）
- EncodedImage：编码输出，必须分配新内存（编码数据不可预测大小）
```

### 8.4 Simulcast 的架构支持

```
Simulcast 的架构设计：

                    SimulcastEncoderAdapter
                    （装饰器模式）
                           │
            ┌──────────────┼──────────────┐
            │              │              │
     VP8Encoder    VP8Encoder    VP8Encoder
     (high)        (mid)         (low)
     640x360       320x180       144x90
     ~900kbps      ~300kbps      ~100kbps

架构特点：
- 装饰器模式：SimulcastEncoderAdapter 实现 VideoEncoder 接口
- 内部包装多个编码器，每个编码器处理不同分辨率
- 上层调用 Encode() 时，自动将同一帧分发到所有编码器
- BWE 根据带宽动态选择发送哪路（RateAllocator）

RateAllocator 的选择逻辑：
  带宽 > 900kbps → 发送 high 路
  300kbps < 带宽 < 900kbps → 发送 mid 路
  带宽 < 300kbps → 发送 low 路
```

> 源码对照：`SimulcastEncoderAdapter`（media/engine/simulcast_encoder_adapter.h:47）实现 `VideoEncoder` 装饰器模式，内部持有多路编码器实例；各层码率分配见 `modules/video_coding/utility/simulcast_rate_allocator.cc`。

### 8.5 拥塞控制闭环的架构位置

```
BWE 在媒体管道中的位置：

  发送方向：
    VideoSendStream ──→ RtpTransportControllerSend ──→ Pacing
          │                        │
          │ 码率回调               │ 目标码率
          ▼                        ▼
    VideoBitrateAllocator      TokenBucket
          │
          ▼
    调整编码分辨率/码率/帧率

  接收方向：
    RTCP Receiver ──→ TransportSequenceNumberFeedbackGenenerator ──→ 发送方 GoogCC
          │                        │
          │ transport-cc 反馈包     │ (REMB 仅兼容回退)
          ▼                        ▼
    TransportFeedback              目标带宽
                                   反馈给发送方
```

### 8.6 完整媒体管道的对象协作图

```
音频发送管道的对象协作（完整，M144）：

  PeerConnection (signaling)
    │ Proxy
    ▼
  RtpTransmissionManager (signaling)
    │ 持有 RtpTransceiver
    ▼
  RtpTransceiver (signaling 持有, channel 操作 BlockingCall 到 worker)
    │ channel_ (unique_ptr)
    ▼
  VoiceChannel (worker)
    │ 持有
    ▼
  VoiceMediaSendChannel (worker)
    │ 持有
    ▼
  AudioSendStream (worker)
    ├── 持有 ──→ AudioProcessing (APM 管线)
    ├── 持有 ──→ AudioEncoder (acm2)
    ├── 持有 ──→ RTPSender / RTCPSender
    └── 回调 ──→ RtpTransportControllerSend (worker/network)
                    │
                    ▼
                 UDPSocket (network)

  对象数量：8 个核心对象，跨越 3 个线程
  调用方式：Proxy + worker BlockingCall + 回调
```

> 源码对照：`RtpTransmissionManager`（pc/rtp_transmission_manager.h:73）持 transceiver 列表；`RtpTransceiver::channel_`（pc/rtp_transceiver.h:121）；`VoiceMediaSendChannel` 实现 `VoiceMediaSendChannelInterface`（media/base/media_channel.h:894）；`AudioSendStream`（audio/audio_send_stream.h）持有的发送组件；`RtpTransportControllerSend`（call/rtp_transport_controller_send.h:64）。

> ⚠️ M144 变更：老版协作链是 `ChannelManager → VoiceChannel → VoiceMediaChannel → AudioSendStream(ACM/RtpBuilder, call 线程)`。M144 无 ChannelManager 与独立 call 线程，链头改为 RtpTransmissionManager/RtpTransceiver；ACM/RtpBuilder 由 AudioEncoder(acm2)/RTPSender 替代。

---

## 第 9 章：modules/ 模块架构 —— 核心处理模块的架构

### 9.1 模块总览

`modules/` 是 WebRTC 的"核心处理引擎"，包含了音视频处理、网络传输、拥塞控制等所有媒体处理逻辑。

#### 9.1.1 模块分组

```
modules/
├── audio/                    # 音频子系统
│   ├── audio_device/         # 音频设备抽象（ADM）
│   ├── audio_processing/     # 音频处理引擎（APM）
│   └── audio_coding/         # 音频编解码（acm2 + NetEq）
├── video_coding/             # 视频编码管理 + 接收缓冲
├── video/                    # 视频管线 + 适配降级（video/adaptation/）
├── congestion_controller/    # 拥塞控制（GoogCC）
├── pacing/                   # 速率整形（Pacing）
├── rtp_rtcp/                 # RTP/RTCP 协议栈
├── remote_bitrate_estimator/ # AIMD 码率控制
├── utility/                  # 工具模块
└── video_capture/           # 视频采集
```

#### 9.1.2 模块间依赖关系图

```
                    ┌─────────────────────┐
                    │   PeerConnection     │
                    └────┬──────────┬─────┘
                         │          │
              ┌──────────▼──┐  ┌────▼──────────┐
              │   call/      │  │   pc/          │
              │  Call/Stream  │  │ RtpTrans-     │
              │              │  │ missionManager│
              │              │  │ +SdpOffer-    │
              │              │  │ AnswerHandler │
              └────┬─────────┘  └────┬──────────┘
                   │                 │
         ┌─────────▼────────────────▼──────────┐
         │        modules/ 核心处理层           │
         │                                      │
         │  ┌──────────┐  ┌──────────┐         │
         │  │  Audio   │  │  Video   │         │
         │  │ Processing│  │ Coding   │         │
         │  └────┬─────┘  └────┬─────┘         │
         │       │             │               │
         │  ┌────▼─────────────▼─────┐         │
         │  │   RTP/RTCP + Pacing    │         │
         │  └────────────┬───────────┘         │
         │               │                      │
         │  ┌────────────▼───────────┐         │
         │  │ Congestion Controller  │         │
         │  └────────────────────────┘         │
         └────────────────────────────────────┘
                   │
         ┌─────────▼──────────┐
         │  rtc_base/         │
         │  (Socket/Thread)   │
         └────────────────────┘
```

#### 9.1.3 调度接口架构：TaskQueue 取代 Module/ProcessThread

M144 已删除 `Module`/`ProcessThread`——modules/ 层不再有"统一的周期处理接口"，取而代之的是 **TaskQueueBase** + 各模块自持的定时机制：

```cpp
// api/task_queue/task_queue_base.h:27
class TaskQueueBase {
 public:
  virtual void PostTask(std::unique_ptr<QueuedTask> task) = 0;
  virtual void PostDelayedTask(std::unique_ptr<QueuedTask> task,
                               uint32_t milliseconds) = 0;
  // DeleteShortly / Current / IsCurrent ...
};

// rtc_base/task_utils/repeating_task.h —— 周期任务的统一形态
RepeatingTaskHandle handle =
    RepeatingTaskHandle::StartDelaying(task_queue,
                                       []() {
                                         DoPeriodicWork();
                                         return TimeDelta::Seconds(1);  // 下次间隔
                                       });
```

**架构特点：**
- **任务队列驱动**：`rtc::Thread` 本身实现了 `TaskQueueBase` 接口，周期任务用 `RepeatingTaskHandle`（任务自己返回下次延迟）
- **定时职责分散**：老 `Module::Process()` 的各路定时逻辑，M144 分散到各模块自己的任务里——`RTCPSender`（RTCP 报告定时）、`TaskQueuePacedSender`（pacing tick）、GoogCC 的 25ms 周期任务（`GoogCcState` 里注册）、`NackRequester`（重传定时）
- **无模块线程**：不再有专门跑 Module 的 ProcessThread，这些任务跑在 worker/网络线程的 TaskQueue 上
- **非实时**：与 RTCP 的实时性要求不同，周期任务是"尽快+间隔上限"而非"严格实时"

> ⚠️ M144 变更：老版所有核心模块实现统一 `Module` 接口（`TimeUntilNextProcess()`/`Process()`/`ProcessThreadAttached()`，modules/include/module.h），由 `ProcessThread` 周期轮询调度。M144 中 `modules/include/` 下已无 module.h，该接口与调度模型整体删除；modules/include/ 里只剩 module_common_types 等纯数据定义。

---

### 9.2 音频处理模块架构（audio_processing/）

#### 9.2.1 AudioProcessing 架构：模块化处理链

`AudioProcessing`（APM，api/audio/audio_processing.h:121）是 WebRTC 音频处理的核心引擎，内部由多个独立子系统组成：

```
AudioProcessing (APM)
├── EchoControl (接口)           // 回声消除
│   ├── EchoCanceller3 (AEC3)    // 默认实现，modules/audio_processing/aec3/
│   │   └── EchoController       // 逐子带自适应 + 抑制决策
│   └── EchoDetector             // 通话回声检测（检测有无回声，不消除）
├── NoiseSuppressor (NS)         // 噪声抑制，modules/audio_processing/ns/
│   ├── QuantileNoiseEstimator   // 分位数噪声估计 (0.95)
│   └── WienerFilter             // 维纳滤波增益
├── GainController1 (AGC1)      // 模拟增益 + 自适应数字模式
├── GainController2 (AGC2)       // 自适应数字增益
│   ├── RnnVad                   // RNN 语音检测
│   ├── SpeechLevelEstimator     // 语音电平估计
│   ├── AdaptiveDigitalGainController // 增益决策
│   └── Limiter                  // 限幅器
└── HighPassFilter (HPF)         // 高通滤波
```

**架构特点：模块化注册机制**

每个子系统通过 `AudioProcessing::Config`（`apm->ApplyConfig(config)`）统一配置，互不影响：

```cpp
// 每个子系统独立可配置
config.echo_canceller.enabled = true;
config.noise_suppression.level = AudioProcessing::Config::NoiseSuppression::kHigh;
config.gain_controller1.enabled = true;
config.gain_controller2.mode = AudioProcessing::Config::GainController2::kAdaptiveDigital;
apm->ApplyConfig(config);   // 一次调用原子生效
```

**处理链顺序（捕获侧，关键！）**：

```
输入 PCM
  │
  ▼
HighPassFilter (高通滤波，去除低频噪声)
  │
  ▼
EchoCanceller3 (AEC3：消除远端回声)
  │
  ▼
NoiseSuppressor (NS：抑制背景噪声)
  │
  ▼
GainController1 / GainController2 (AGC：自动增益调整)
  │
  ▼
输出 PCM
```

**架构图：AudioProcessing 内部处理链**

```
┌─────────────────────────────────────────────────────────────┐
│                   AudioProcessing (APM)                     │
│                                                             │
│  输入 (16kHz/48kHz PCM)                                     │
│    │                                                        │
│    ▼                                                        │
│  ┌──────────────┐                                          │
│  │ HighPassFilter│  高通滤波，去除低频环境噪声               │
│  └──────┬───────┘                                          │
│         ▼                                                  │
│  ┌──────────────┐                                          │
│  │ EchoCancel-  │ 频域自适应滤波：远端参考信号 + 近端音频    │
│  │   ler3       │ 混频/线性滤波 + 抑制 (suppressor)          │
│  └──────┬───────┘                                          │
│         ▼                                                  │
│  ┌──────────────┐                                          │
│  │ Noise       │ 维纳滤波：分位数噪声估计 + 谱减             │
│  │ Suppressor   │ 4 个等级：Low/Medium/High/VeryHigh         │
│  └──────┬───────┘                                          │
│         ▼                                                  │
│  ┌──────────────┐                                          │
│  │ GainControl- │ AGC1（模拟+自适应数字）或 AGC2            │
│  │ ler1/2        │ AGC2：RNN VAD → 电平估计 → 增益 → 限幅    │
│  └──────┬───────┘                                          │
│         ▼                                                  │
│  输出 PCM → 送入编码器                                     │
│                                                             │
│  每个 Module 可独立开关（Config enabled 标志，处理链跳过）    │
└─────────────────────────────────────────────────────────────┘
```

> 源码对照：`AudioProcessing` 接口（api/audio/audio_processing.h:121，`ApplyConfig` 也在该文件）；AEC3 主体 `EchoCanceller3`（modules/audio_processing/aec3/echo_canceller3.h，内部 `EchoController` 等）；NS `NoiseSuppressor`（modules/audio_processing/ns/noise_suppressor.h:33）；AGC1 `GainController1`（agc/legacy/gain_control.h）；AGC2 `GainController2`（modules/audio_processing/gain_controller2.h:37）。

> ⚠️ M144 变更：老版列出的 `VoiceDetectionModule`/`LevelEchoControl`/`GainControlAdapter` 等类不存在；VAD 不再是 APM 管线里的独立"标记帧"子模块（AGC2 内部自带 RnnVad，ns/ 内的 VAD 概率只服务于自身增益估计）；配置方式也从逐子模块 getter（`apm_->echo_cancellation()->Enable(true)`）改为统一的 `AudioProcessing::Config` + `ApplyConfig`。

#### 9.2.2 AEC 架构（EchoCancellation submodule）

**架构特点：参考信号设计**

AEC 的核心思想是"有参考才能消除"：

```
远端音频 (Play Reference) ──→ AEC 参考输入
                                  │
近端麦克风 (Mic Input) ──→ AEC 处理 ──→ 消除回声后的音频
```

**关键设计决策：**
- **频域处理**：将时域信号 FFT → 频域 → 自适应滤波 → IFFT 还原
- **分块自适应滤波**：捕获延迟对齐 + 线性滤波器逐块更新（AEC3 的 `EchoCanceller3` 分块处理）
- **抑制器 (Suppressor)**：线性滤波后残余回声的多帧行为决策抑制（对应老资料里的"非线性处理 NLP"角色）
- **远端采样率偏移补偿**：自动校正播放器与采集器的时钟偏差

> ⚠️ M144 变更：老版有 `EchoControlMobile`（AECM，移动端回声模型），M144 已删除——回声消除统一走 `EchoCanceller3`（modules/audio_processing/aec3/），移动端低算力场景靠 AEC3 的移动配置（`EchoCanceller3Config::mobile` 一档）解决。

#### 9.2.3 APM 架构优缺点

**优：**
- **模块化设计**：每个子系统独立开发和测试，互不影响
- **零开销开关**：未启用的模块在编译期优化掉，不影响处理链
- **可独立配置**：每个子系统有独立的配置接口

**缺：**
- **模块间参数耦合**：AGC 增益受 VAD 影响（VAD 误判时 AGC 可能错误提升噪声电平）
- **处理链顺序固定**：无法自定义处理顺序（如某些场景需要先 NS 再 AEC）
- **配置复杂**：每个子模块有多个参数，调优需要深入理解

---

### 9.3 视频处理模块架构（video_coding/ + video/）

#### 9.3.1 VideoCoding 架构：接收缓冲链 + 丢包恢复

```
接收侧视频管线 (VideoReceiveStream2, video/video_receive_stream2.h:101)
├── VideoDecoder (接口)
│   ├── VP8Decoder
│   ├── VP9Decoder
│   └── H264Decoder
├── PacketBuffer (乱序重组: modules/video_coding/packet_buffer.cc)
├── FrameBuffer (帧级缓冲: api/video/frame_buffer.h:32, temporal unit 模型)
├── VideoStreamBufferController (解码调度核心: video/video_stream_buffer_controller.h:80)
│   ├── JitterEstimator (modules/video_coding/timing/)
│   ├── FrameDecodeScheduler (TaskQueueFrameDecodeScheduler)
│   └── VCMReceiveStatisticsHelper
└── NackRequester (丢包重传请求: modules/video_coding/nack_requester.h:70)
    └── kMaxNackRetries = 100 (nack_requester.cc:39)
```
```

**架构特点：编码器抽象接口 + 具体实现分离**

```cpp
// modules/video_coding/include/video_codec_interface.h
class VideoEncoder {
 public:
  struct Config { ... };          // 编码器配置（分辨率、码率、FPS）
  struct State { ... };           // 编码器状态（SSRC、Codec 类型、SRS）
  
  virtual int Init(const Config& config) = 0;
  virtual int Encode(
      VideoFrame* input_image,
      const std::vector<VideoEncoder::FrameType>* frame_types = nullptr) = 0;
  virtual int Release() = 0;
  
  virtual void SetRates(SetRateParameters) = 0;  // 动态码率调整
};
```

**架构图：VideoCoding 内部对象关系**

```
┌──────────────────────────────────────────────────────┐
│           video_coding/ + video/ (M144)               │
│                                                      │
│  发送侧（VideoStreamEncoder, video/）:                │
│  ┌──────────┐    ┌───────────┐    ┌──────────────┐  │
│  │ VideoFrame│───→│  Video    │───→│ EncodedImage │  │
│  │ (适配后)  │    │ Encoder   │    │ → RTPSender  │  │
│  └──────────┘    │ (VP8/VP9/ │    └──────────────┘  │
│                  │  H264/AV1) │                       │
│                  └───────────┘                        │
│                                                      │
│  接收侧（VideoReceiveStream2, video/video_receive_stream2.h:101）:│
│  ┌──────────┐    ┌─────────────────┐  ┌──────────┐  │
│  │ Incoming │───→│ PacketBuffer →   │─→│ Decoder  │  │
│  │ Packets  │    │ FrameBuffer +   │  │ → Render │  │
│  │          │    │ VideoStream-    │  │ Callback │  │
│  └──────────┘    │ BufferController│  └──────────┘  │
│                  │ + NackRequester  │                │
│                  └─────────────────┘                │
└──────────────────────────────────────────────────────┘
```

#### 9.3.2 VP8/VP9/H264 编码器架构

**架构特点：外部编码器接口**

WebRTC 不自己实现 VP8/VP9 编码算法，而是通过外部库（libvpx）调用：

```cpp
// 编码器接口设计
class VideoEncoder {
  // 编码配置
  struct Config {
    size_t max_payload_size;
    size_t number_of_cores;
    VideoCodecType codecType;
    // ... 分辨率、码率、FPS 等
  };
  
  // 编码状态
  struct State {
    VideoCodecType codecType;
    bool reConfig;
    unsigned int activeCodecPayloadType;
    unsigned int numberOfResolutionsAdjusted;
    // Simulcast/MVC SSRC 信息
    std::vector<unsigned int> reencodedResolutionChange;
  };
  
  // 编码输出
  struct EncodedImage {
    rtc::ScopedVector<uint8_t> payload;
    rtc::scoped_refptr<webrtc::YuvPlaneData> yuv_data;
    VideoFrameType frame_type;
  };
};
```

**SimulcastEncoderAdapter 的装饰器设计：**

```
原始视频帧 (1280x720)
    │
    ▼
┌──────────────────────────┐
│  SimulcastEncoderAdapter │  ← 装饰器：将单路视频分发到多路编码器
│                          │
│  ┌────────┐ ┌────────┐  │
│  │Encoder1│ │Encoder2│  │  ← 不同分辨率/码率
│  │(高)    │ │(中)    │  │
│  └────────┘ └────────┘  │
│            ┌────────┐   │
│            │Encoder3│   │  ← 低分辨率档
│            │(低)    │   │
│            └────────┘   │
└──────────────────────────┘
    │       │       │
    ▼       ▼       ▼
  3 路 RTP 流（不同质量）
```

#### 9.3.3 VideoProcessing 架构：帧处理管线

**架构特点：I420Frame 统一帧格式，操作链式组合**

```
输入帧 (任意格式)
    │
    ▼
┌──────────────┐
│  Format      │  转换为 I420 (YUV420) 统一格式
│  Converter   │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  Crop        │  裁剪
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  Rotate      │  旋转 (0/90/180/270)
└──────┬─────┬─┘
       │     │
       ▼     ▼
┌──────────┐ ┌────────────┐
│  Scale   │ │  Framerate │
│          │ │  Controller│  ← 帧率控制
└──────────┘ └────────────┘
       │
       ▼
┌──────────────┐
│  Image       │  图像增强 (对比度、饱和度、亮度)
│  Process     │
└──────┬───────┘
       │
       ▼
输出 I420 Frame → 送入编码器
```

#### 9.3.4 视频模块架构优缺点

**优：**
- **编码器接口统一**：新增编码器只需实现 `VideoEncoder` 接口
- **外部编码器复用**：利用成熟的 libvpx、x264 等库
- **接收缓冲链独立**：PacketBuffer/FrameBuffer 与编解码解耦，丢包恢复（NackRequester）可独立演进

**缺：**
- **帧格式转换存在性能损耗**：所有视频帧统一转换为 I420，再在编码器内部可能转换为 NV12/NV21，存在二次转换
- **适配层与编码器耦合**：video/adaptation 的降级决策需要感知编码器能力（并集约束），配置重叠

---

### 9.4 拥塞控制模块架构（congestion_controller/）

#### 9.4.1 GCC（Google Congestion Control）架构

GCC 是 WebRTC 的核心拥塞控制算法，M144 采用 **发送端单点决策** 的设计（transport-cc 反馈把接收端的观察送到发送端）：

```
发送端 (RtpTransportControllerSend, call/rtp_transport_controller_send.h:64)：
┌─────────────────────────────────────────────────┐
│  GoogCcNetworkController                         │
│  (goog_cc/goog_cc_network_control.h:46)          │
│  —— 每批 transport-cc 反馈驱动一次                  │
│     OnTransportPacketsFeedback 决策               │
│                                                  │
│  ┌──────────────────┐  ┌──────────────────┐     │
│  │ DelayBasedBwe    │  │ LossBasedBweV2   │     │
│  │ (delay_based_    │  │ (loss_based_     │     │
│  │  bwe.h:53)       │  │  bwe_v2.h:41)    │     │
│  │ ┌──────────────┐ │  │                  │     │
│  │ │TrendlineEst- │ │  │ 基于丢包率，      │     │
│  │ │imator        │ │  │ 给出码率上下边界  │     │
│  │ │(trendline_   │ │  │                  │     │
│  │ │estimator.h:51)│ │  │                  │     │
│  │ │→ 延迟梯度趋势 │ │  │                  │     │
│  │ │→ AimdRate-   │ │  │                  │     │
│  │ │  Control     │ │  └────────┬─────────┘     │
│  │ └──────────────┘ │           │               │
│  └────────┬─────────┘           │               │
│           │   ┌──────────────────▼───────────┐   │
│           └──→│ SendSideBandwidthEstimation │   │
│               │ (send_side_bandwidth_       │   │
│               │  estimation.h:60)          │   │
│               │ 综合延迟/丢包两路信号        │   │
│               └────────────┬───────────────┘   │
│                            │ 输出目标码率      │
│                            ▼                  │
│  ┌──────────────────────────────────────┐    │
│  │ Pacing (TaskQueuePacedSender)         │    │
│  │ + BitrateAllocator (码率分配到各流)    │    │
│  └──────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘

接收端：
┌─────────────────────────────────────────────────┐
│ TransportSequenceNumberFeedbackGenenerator      │
│ (transport_sequence_number_feedback_generator.h:39 │
│  —— 源码拼写即 "Genenerator")                   │
│ / CongestionControlFeedbackGenerator             │
│ (RFC-8888, congestion_control_feedback_generator.h:53)│
│                                                  │
│ 记录每个 RTP 包的到达时间/序列号 → 组成            │
│ transport-cc 反馈包 → RTCP 回发发送端              │
└─────────────────────────────────────────────────┘

闭环：
发送端 Pacing → 网络 → 接收端反馈生成 → RTCP transport-cc →
  发送端 GoogCc 决策 → 调整 Pacing 码率
```

**架构特点：发送端单点决策，transport-cc 反馈闭环**

- **DelayBasedBwe**：基于包到达时间增量（延迟梯度）判断拥塞，TrendlineEstimator 做趋势检测，AimdRateControl 调码率
- **LossBasedBweV2**：基于丢包率，对当前码率给出上下边界
- **SendSideBandwidthEstimation**：综合延迟/丢包两路信号，输出最终目标码率
- **AIMD 公式**（M144）：增率 = avg_packet_size/(2×(rtt+100ms))，下限 4kbps；降 = throughput×0.85 再 −5kbps

> 源码对照：`GoogCcNetworkController`（modules/congestion_controller/goog_cc/goog_cc_network_control.h:46）、`DelayBasedBwe`（goog_cc/delay_based_bwe.h:53）、`TrendlineEstimator`（trendline_estimator.h:51）、`AimdRateControl`（modules/remote_bitrate_estimator/aimd_rate_control.h:33）、`LossBasedBweV2`（loss_based_bwe_v2.h:41）、`SendSideBandwidthEstimation`（send_side_bandwidth_estimation.h:60）。

> ⚠️ M144 变更：老版图里的接收端 `RemoteBitrateEstimator (BBR)` 已删除——M144 主反馈路径是 **transport-cc**（接收端只"记录到达时间"，带宽估计全部在发送端做），REMB 仅作兼容回退保留（remb_throttler）。另外 DelayBasedBwe 判断的是**单向延迟梯度**（包到达间隔趋势），不是老图写的"基于 RTT 变化"。

#### 9.4.2 DelayBasedBwe 架构

**架构特点：基于延迟梯度的带宽估计**

核心思想：当发送速率超过可用带宽时，数据包在网络上排队，**包的到达时间间隔逐渐拉大**（延迟梯度上升），据此在丢包发生之前就检测到拥塞。

```
发送速率增加 → 队列堆积 → 包到达间隔增大（延迟梯度上升）→ 检测到拥塞 → 降低速率
发送速率降低 → 队列排空 → 延迟梯度回落 → 检测到带宽余量 → 增加速率
```

**信号链（M144）**：transport-cc 反馈给出每个包的发送/到达时间差 → `ArrivalTimeFilter`（卡尔曼滤波）平滑 → `TrendlineEstimator`（累计趋势回归，kUp=0.0087/kDown=0.039）→ `RateControlState` 增/降决策（`AimdRateControl`）→ 产出的 BandwidthUsage（overuse/normal/underuse，api/transport/bandwidth_usage.h:16）交给 `SendSideBandwidthEstimation`。

**与 LossBasedBweV2 的并行与融合：**

```
DelayBasedBwe:   关注延迟梯度 (早期拥塞信号，丢包前就降速)
     │
     ▼
┌─────────────────┐    ┌──────────────┐
│ SendSideBandwidth│───→│  目标码率     │
│ Estimation 综合   │    │              │
LossBasedBweV2:   关注丢包率 (拥塞确认信号，给出上下边界)
```

> ⚠️ M144 变更：老版 9.4.2 写 DelayBasedBwe"基于 RTT 变化"并配 `PacketLossBasedBwe`（老类名）——M144 判断的是**单向延迟梯度**（不需要 RTT），丢包侧类名是 `LossBasedBweV2`（loss_based_bwe_v2.h:41）。

#### 9.4.3 Pacing 架构（pacing/）

**架构特点：间隔预算 + 优先级队列，平滑发送速率**

M144 的 Pacing 由三件套组成：**PacingController**（决策核心，`pacing_controller.h:44`）+ **TaskQueuePacedSender**（宿主，`task_queue_paced_sender.h:39`，用 TaskQueue 定时器驱动）+ **PrioritizedPacketQueue**（优先级队列，`prioritized_packet_queue.h:39`）。

```
┌───────────────────────────────────────────────────┐
│  TaskQueuePacedSender                              │
│  ┌─────────────────────────────────────────────┐ │
│  │ PacingController                             │ │
│  │  - IntervalBudget（间隔预算：按目标码率算      │ │
│  │    每个发送间隔可发的字节数，非令牌桶）         │ │
│  │  - 队列长度上限 kMaxExpectedQueueLength       │ │
│  │    = 2000ms 对应目标码率的量 (pacing_controller.h:92)│ │
│  └──────────────┬──────────────────────────────┘ │
└─────────────────┼─────────────────────────────────┘
                  │ 按优先级+时序取包
┌─────────────────▼─────────────────────────────────┐
│ PrioritizedPacketQueue                             │
│ 优先级（prioritized_packet_queue.cc:34-63）：      │
│   0 = 音频                                        │
│   1 = 音频重传 (RTX)                               │
│   2 = 视频重传 (RTX)                               │
│   3 = 视频 + FEC (kForwardErrorCorrection)        │
│   4 = padding                                     │
└─────────────────┬─────────────────────────────────┘
                  ▼
              网络发送
```

**与 BWE 的协作：**

```
GoogCc 输出：目标码率（随每批 transport-cc 反馈更新）
    │
    ▼
PacingController：按目标码率（+ padding 余量）控制发送节奏；
  拥塞回压时 CongestionWindowPushbackController
  (goog_cc/congestion_window_pushback_controller.h:28)
  依据 RTT/队列长度进一步压低实际发送量
```

> ⚠️ M144 变更：老版叙述的"令牌桶"与 `PacedSender`/`RoundRobinPacketQueue` 类均已删除。M144 用 IntervalBudget 预算模型 + PrioritizedPacketQueue 五级优先级；宿主从 ProcessThread 模块线程换成 TaskQueuePacedSender（TaskQueue 定时器，定时精度随目标码率动态调整）。
#### 9.4.4 拥塞控制架构优缺点

**优：**
- **Sender/Receiver 分离**：接收端收集网络统计，发送端做决策，符合网络观测与控制的分离原则
- **多算法融合**：基于 RTT 和基于丢包两种估计并行，互补优势
- **Pacing 独立**：拥塞控制与发送速率控制解耦

**缺：**
- **算法复杂度高**：GCC 有数十个可调参数（`kDelayMinAlpha`、`kLossMinAlpha` 等）
- **参数调优困难**：不同网络环境（WiFi/4G/光纤）需要不同参数
- **调试困难**：拥塞控制是"看不见的"，需要依赖 RTCP 反馈数据间接分析

---

### 9.5 RTP/RTCP 模块架构（rtp_rtcp/）

#### 9.5.1 RtpRtcp 架构：接口与实现的拆分

M144 把老的 `RtpRtcp` 模块拆成了 **RtpRtcpInterface**（接口，`modules/rtp_rtcp/include/rtp_rtcp_interface.h:50`）+ **ModuleRtpRtcpImpl2**（实现，`rtp_rtcp_impl2.h:56`），内部再组合 `RTPSender`（`rtp_sender.h:45`）与 `RTCPSender`（`rtcp_sender.h:50`）两个独立组件：

```cpp
// modules/rtp_rtcp/include/rtp_rtcp_interface.h:50 —— 接口层
class RtpRtcpInterface : public RtcpFeedbackSenderInterface {
 public:
  virtual void SetMediaChannel(...) = 0;          // 绑定媒体通道
  virtual void SetExtRtpHeadersId(...) = 0;
  virtual uint32_t StartTimestamp() const = 0;
  virtual void RegisterSendPayloadFrequency(...) = 0;
  // RTP/RTCP 收发入口
  virtual void OnReceivedNack(...) = 0;
  virtual void SendRTCP(RTCPPacketType type) = 0;  // PLI/FIR 等关键帧请求
  virtual int32_t SendNACK(...) = 0;
};

// modules/rtp_rtcp/source/rtp_rtcp_impl2.h:56 —— 实现层
class ModuleRtpRtcpImpl2 : public RtpRtcpInterface {
  std::unique_ptr<RTPSender>  rtp_sender_;    // RTP 封包/发送
  std::unique_ptr<RTCPSender> rtcp_sender_;   // RTCP 报告生成
  RTCPSender::RtcpContext rtcp_context_;
  // 周期任务（RTCP 报告定时等）由内部 RepeatingTaskHandle 驱动
};
```

**架构特点：接口与实现拆分 + 发送组件独立**

- `RTPSender`：RTP 封包、序列号管理、扩展头写入、重传（RTX）与 FEC 包发送
- `RTCPSender`：RR/SR/PLI/NACK/REMB/transport-cc 等所有 RTCP 报文的定时生成
- 定时职责不再走 Module::Process()，而是实现内部的任务队列定时器

**RTCP 反馈消息处理：**

```
到达 RTCP 包 (RtpReceiver 侧/RTCPReceiver)
    │
    ▼
┌──────────────┐
│ RTCPReceiver │  解析 RTCP 包类型
└──────┬───────┘
       │ 按类型分发
       ▼
┌────────────────────────────────┐
│ 各自的观察者/回调               │
└──┬──────┬──────┬──────┬───────┘
   │      │      │      │
   ▼      ▼      ▼      ▼
  RR/SR  SR-RRO  REMB   TransportFeedback
 (码率统计)(丢包/RTT) (兼容回退) (→ GoogCc 决策)
   │      │      │      │
   ▼      ▼      ▼      ▼
  NACK  TMMBR/TMMBN PLI/FIR → 关键帧请求
```

> ⚠️ M144 变更：老版写"`class RtpRtcp : public Module`，一个对象同时处理收发两侧、`Process()` 在 ProcessThread 上轮询"。M144 无 Module 基类；类拆为 `RtpRtcpInterface`（接口）+ `ModuleRtpRtcpImpl2`（实现），发送侧拆出独立的 `RTPSender`/`RTCPSender`；接收侧的 RTCP 解析在 `RTCPReceiver`，与发送实现解耦。老代码块中的 `ReceiveRtp/ReceiveRtcp` 入口在 M144 接口中不存在。
#### 9.5.2 RTP 扩展头架构

**架构特点：动态注册机制，支持自定义扩展**

```cpp
// M144 实际支持的 RTP 扩展头（URI 定义在 api/rtp_parameters.h:374-433）
kAudioLevelUri              // 音频电平 (RFC 6464)
kVideoRotationUri           // 视频旋转 (urn:3gpp:video-orientation)
kVideoContentTypeUri        // 视频内容类型 (静态屏/动态屏)
kDependencyDescriptorUri    // SVC/依赖描述（关键帧结构传递）
kVideoLayersAllocationUri   // 视频层码率分配 (simulcast/SVC)
kTransportSequenceNumberUri // transport-cc 序列号（拥塞控制反馈）
kTransportSequenceNumberV2Uri // transport-cc v2（含丢包原因）
kPlayoutDelayUri            // 播放延迟提示（接收端缓冲调优）
kColorSpaceUri              // 色彩空间
```

**动态注册机制：**

```
发送端：
  RTPSender::SetExtRtpHeadersId / RegisterRtpPacketHeaderExtension
    → 协商出的扩展按 URN 映射到头位置（RtpExtension::FindIdByUri）
  视频码率分配：VideoSendStream → RTPSender
    ::SetVideoLayersAllocation → kVideoLayersAllocation 扩展头

接收端：
  RTP 包头解析（RtpPacket::GetExtension）
    → 交给对应的观察者（如 transport-cc → 反馈生成器）
```

> ⚠️ M144 变更：老版列表里的 `kTimestampOffset`/`kPlcGain`/`kTimedMetadata` 均不是 M144 扩展头；`kTransportSequenceNumber` 的用途注释也错了——它是**拥塞控制反馈（transport-cc）**用的，与 NACK/FEC 无关。
#### 9.5.3 架构优缺点

**优：**
- **接口与实现拆分**：RtpRtcpInterface 让 mock/自定义实现容易（测试友好）
- **发送组件独立**：RTPSender/RTCPSender 各自单一职责，可独立演进
- **RTCP 消息类型扩展方便**：通过回调接口添加新的 RTCP 处理逻辑

**缺：**
- **RTCP 处理逻辑分散**：RR、XR、REMB、transport-cc 等处理分散在 RTCPReceiver 的多个观察者
- **Impl2 聚合职责仍重**：ModuleRtpRtcpImpl2 同时编排 RTP/RTCP/重传/FEC 多条线，内部状态机较复杂

---

### 9.6 音频编解码模块架构（audio_coding/）

#### 9.6.1 编解码架构：AudioEncoder/AudioDecoder + NetEq

M144 无 AudioCodingModule（ACM）类——发送侧是 `AudioSendStream` 直接持有 `AudioEncoder`，接收侧统一走 **NetEq**：

```
发送侧 (acm2, modules/audio_coding/)
├── AudioEncoder (接口, api/audio_codecs/audio_encoder.h)
│   ├── AudioEncoderOpus
│   ├── AudioEncoderG722
│   ├── AudioEncoderIlbc
│   └── AudioEncoderPcm16B / PCM16A 等净荷族
└── AudioEncoderCng (DTX/舒适噪声封装，装饰在上述编码器外)

接收侧 (neteq, modules/audio_coding/neteq/)
├── NetEq (接口, api/neteq/neteq.h)
│   └── NetEqImpl (neteq_impl.h:64)
│       ├── PacketBuffer (乱序缓冲)
│       ├── DecisionLogic (decision_logic.h:31, NetEqController)
│       ├── Accelerate / PreemptiveExpand (时间伸缩)
│       ├── Expand (PLC 丢包隐藏)
│       ├── Normal (正常解码)
│       └── UnderrunOptimizer + ReorderOptimizer (延迟估计/重排)
└── AudioDecoder (接口, api/audio_codecs/audio_decoder.h)
```

**统一编解码接口：**

```cpp
// api/audio_codecs/audio_encoder.h —— 编码器接口（M144 实形态）
class AudioEncoder {
 public:
  virtual int SampleRateHz() const = 0;
  virtual size_t NumChannels() const = 0;
  virtual int RtpTimestampRateHz() const = 0;
  virtual size_t Num10MsFramesInNextPacket() const = 0;
  // 编码一帧：输入 AudioFrame（interleaved int16），输出 EncodedInfo
  virtual EncodedInfo Encode(uint32_t rtp_timestamp,
                             rtc::ArrayView<const int16_t> audio,
                             rtc::Buffer* encoded) = 0;
};

// api/audio_codecs/audio_decoder.h —— 解码器接口
class AudioDecoder {
  virtual void Reset() = 0;
  // NetEq 调用：解码 + 丢包隐藏 (speech_type: kSpeech/kComfortNoise/kErrorCode)
  virtual int Decode(const uint8_t* encoded, size_t encoded_len,
                     int sample_rate_hz, size_t max_decoded_bytes,
                     int16_t* decoded, SpeechType* speech_type) = 0;
};
```

> ⚠️ M144 变更：老版的 `AudioCodingModule (ACM)` 中央管理类已删除（iSAC 也已移除）；编解码器工厂（`AudioEncoderFactory`/`AudioDecoderFactory`）+ SDP 协商选定具体 codec；接收侧的"错误隐藏"不在解码器里，而由 NetEq 的 DecisionLogic 统一调度（Expand/Accelerate/PreemptiveExpand/Normal 四种 Operation，见 wr-alg-analysis.md 第 3 章）。

#### 9.6.2 架构优缺点

**优：**
- **编解码器接口统一**：新增编解码器只需实现 `AudioEncoder`/`AudioDecoder` 接口
- **工厂 + 协商自动管理**：`AudioEncoderFactory` 按协商结果创建/销毁编码器实例
- **动态编解码器切换**：协商过程中可动态切换编解码器
- **NetEq 集中抗丢包**：延迟估计/时间伸缩/丢包隐藏集中在 NetEq，解码器保持纯粹

**缺：**
- **不同编解码器参数差异大**：Opus 支持 20-120ms 帧长与 DTX，G722 固定 20ms，接口难以完全统一
- **NetEq 复杂度高**：DecisionLogic + 时间伸缩 + 优化器多组件协作，调优需要深入理解

---

### 9.7 modules/ 模块架构总结

```
┌─────────────────────────────────────────────────────────────────┐
│                    modules/ 架构全景图 (M144)                     │
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐  │
│  │  Audio Processing│  │  Video Coding   │  │ Congestion   │  │
│  │  (APM)          │  │  + video/       │  │ Controller   │  │
│  │  AEC3/NS/AGC1/2 │  │  FrameBuffer +  │  │  GoogCC:      │  │
│  │  /HPF           │  │  VideoStream-   │  │  DelayBased + │  │
│  │                 │  │  BufferController│  │  LossBasedV2  │  │
│  └────────┬────────┘  └────────┬────────┘  └──────┬───────┘  │
│           │                    │                    │          │
│  ┌────────▼────────────────────▼────────────────────▼──────┐  │
│  │      TaskQueue 调度 (TaskQueueBase + RepeatingTaskHandle) │  │
│  └────────────────────────┬────────────────────────────────┘  │
│                           │                                   │
│  ┌────────────────────────▼────────────────────────────────┐  │
│  │              RTP/RTCP (rtp_rtcp/)                       │  │
│  │  RTPSender/RTCPSender + NACK + FEC + transport-cc       │  │
│  │  Pacing: PacingController + TaskQueuePacedSender         │  │
│  └────────────────────────┬────────────────────────────────┘  │
│                           │                                   │
│  ┌────────────────────────▼────────────────────────────────┐  │
│  │              rtc_base (Socket/Thread/TaskQueue)          │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                 │
```

---

## 第 10 章：p2p/ 模块架构 —— 网络与 ICE 的架构

### 10.1 模块定位

`p2p/` 是 WebRTC 的网络基石，负责：
- **ICE 候选收集**：发现本机所有可用的网络连接方式
- **ICE 连接检查**：在两端候选之间建立连接
- **NAT 穿透**：通过 STUN/TURN 穿越 NAT 防火墙
- **STUN/DTLS 协议栈**：提供网络层之上的安全传输

### 10.2 PortAllocator 架构：候选收集的统一入口

`PortAllocator` 是 ICE 候选收集的工厂和协调器：

```
PeerConnection
    │
    ▼
PortAllocator (工厂)
    │
    ├── 创建 ──→ UdpPort (Host 候选)
    ├── 创建 ──→ StunPort (Server-Reflexive 候选)
    ├── 创建 ──→ TurnPort (Relay 候选)
    └── 创建 ──→ TcpPort (TCP Host/Relay 候选)
```

**架构特点：工厂模式创建不同类型的 Port**

```cpp
// p2p/base/port_allocator.h
```cpp
// p2p/base/port_allocator.h:409
class RTC_EXPORT PortAllocator {
 public:
  virtual void Initialize();          // 构造配置完后必须调用
  // 设置 STUN/TURN 服务器与候选池大小（JSEP candidate pool）
  bool SetConfiguration(const ServerAddresses& stun_servers,
                        const std::vector<RelayServerConfig>& turn_servers,
                        int candidate_pool_size, ...);
  virtual PortAllocatorSession* CreateSession(...) = 0;  // 工厂入口
};

// p2p/base/port_allocator.h:192 —— 每个 ICE transport 一次会话
class RTC_EXPORT PortAllocatorSession {
  // BasicPortAllocatorSession (p2p/client/basic_port_allocator.cc)
  // 按 Network 逐个创建 Port，候选经 SignalCandidateReady 回调上报
};

// 默认实现：BasicPortAllocator (p2p/client/basic_port_allocator.h)
```

**架构图：PortAllocator → Port → Candidate 的层级**

```
┌─────────────────────────────────────────────────────────┐
│                  PortAllocatorSession                     │
│                                                         │
│  为每个网络接口 (Network) 创建一个 Port                   │
│                                                         │
│  Network: eth0 (192.168.1.100)                           │
│    │                                                     │
│    ▼                                                   │
│  ┌─────────────────────────────────────────┐            │
│  │  UDPPort (type="host")                  │            │
│  │    │                                   │            │
│  │    ▼                                   │            │
│  │  Candidate: 192.168.1.100:50000 udp    │            │
│  │           type-priority: host           │            │
│  └─────────────────────────────────────────┘            │
│                                                         │
│  Network: eth0 (192.168.1.100) + STUN Server             │
│    │                                                     │
│    ▼                                                   │
│  ┌─────────────────────────────────────────┐            │
│  │  StunPort (type="stun")                 │            │
│  │    │                                   │            │
│  │    ▼ (STUN Binding Request → Server)   │            │
│  │  Candidate: 203.0.113.1:50000 srflx    │            │
│  │           type-priority: srflx          │            │
│  └─────────────────────────────────────────┘            │
│                                                         │
│  TURN Server                                             │
│    │                                                     │
│    ▼                                                   │
│  ┌─────────────────────────────────────────┐            │
│  │  TurnPort (type="relay")                │            │
│  │    │                                   │            │
│  │    ▼ (TURN Allocate → Relay Address)   │            │
│  │  Candidate: 198.51.100.1:50000 relay   │            │
│  │           type-priority: relay          │            │
│  └─────────────────────────────────────────┘            │
│                                                         │
│  信号: SignalCandidateReady 每发现一个候选就发出           │
└─────────────────────────────────────────────────────────┘
```

### 10.3 P2PTransportChannel 架构：ICE 连接管理

`P2PTransportChannel` 是 ICE 连接管理的核心：

```
P2PTransportChannel (worker 线程)
├── Port* ports_                    // 所有 Port 对象
├── Connection* connections_        // 所有候选对连接
├── IceControllerInterface*         // ICE 策略控制器

```

**架构特点：Candidate Pair 管理 + Connection Check 状态机**

```
ICE Connection Check 状态机：

┌──────────┐    Send Binding Request    ┌──────────┐
│  Waiting │───────────────────────────→│  InFlight │
│          │                            │          │
└────┬─────┘                            └────┬─────┘
     │                                       │
     │ 收到 Binding Response                  │ 超时
     ▼                                       ▼
┌──────────┐                         ┌──────────┐
│  Frozen  │←────────────────────────│  Waiting │
│          │   其他 pair 先成功       └──────────┘
└──────────┘

候选对优先级排序：
1. 计算 foundation (相同网络类型的候选对共享 foundation)
2. 按 ICE 优先级排序 (host > srflx > relay)
3. 优先检查高质量候选对 (同局域网)
```

**ICE Controller 抽象：支持未来扩展新的 ICE 策略**

```cpp
```cpp
// p2p/base/ice_controller_interface.h:65 —— 纯策略接口，非 Module
class IceControllerInterface {
 public:
  struct SwitchResult {                 // SelectConnection/切换结果
    std::optional<const Connection*> connection;
    std::optional<IceRecheckEvent> recheck_event;
    std::vector<const Connection*> connections_to_forget_state_on;
  };
  struct PingResult { ... };           // 下一个该 ping 的连接 + 复查延迟
  virtual PingResult SelectConnectionToPing() = 0;
  virtual SwitchResult HandleSwitchRequest(...) = 0;   // 候选对排序/切换决策
  virtual bool ShouldPrune(...) / GetPingableConnections() ...
};
// 实现类：IceController (p2p/base/ice_controller.cc)，
// P2PTransportChannel 每个 transport 一个实例
```

> ⚠️ M144 变更：`IceControllerInterface` 不是 `Module` 的派生类（M144 已无 Module 基类），也不叫 `ConnectionSelector`——连接选择策略统一在 `IceController`（p2p/base/ice_controller_interface.h:65 定义接口，ice_controller.cc 实现）。

### 10.4 Port 架构：不同网络类型的统一抽象

**架构特点：Port 继承体系（UDPPort 是 STUN/TURN 的 UDP 基座）**

```
PortInterface (纯接口)
    │
    ▼
Port (基类，p2p/base/port.h:152：通用逻辑)
├── thread_           // 执行 I/O 的线程
├── type_             // 端口类型 (LOCAL/STUN/RELAY)
├── candidates_       // 该 Port 产生的所有 Candidate
├── connections_      // 该 Port 上的所有 Connection
├── SignalCandidateReady  // 候选发现信号
└── SignalPortComplete    // Port 创建完成信号
    │
    ├── UDPPort      // UDP Host Port (p2p/base/stun_port.h:49 —— 注意定义在 stun_port.h，
    │   │              // 没有 udp_port.h)
    │   ├── StunPort  // STUN Port (stun_port.h:254，继承 UDPPort：通过 STUN 发现公网地址)
    │   └── (UDPPort 也承担 srflx 候选：共享 socket 模式下直接在 UDPPort 上发 STUN 请求)
    ├── TurnPort     // TURN Port (p2p/base/turn_port.h:55，通过 TURN 服务器获取转发地址)
    └── TCPPort      // TCP Port (p2p/base/tcp_port.h:50，主动/被动/simultaneous-open)
```

**各 Port 类型的职责分离：**

| Port 类型 | 职责 | 产生的候选类型 | 定义位置 |
|-----------|------|---------------|----------|
| UDPPort | 监听本地 UDP 端口，收发数据 | host | p2p/base/stun_port.h:49 |
| StunPort | 发送 STUN Binding 请求，发现公网地址 | srflx | p2p/base/stun_port.h:254 |
| TurnPort | 建立 TURN 通道，获取中继地址 | relay | p2p/base/turn_port.h:55 |
| TCPPort | TCP 连接，支持主动/被动模式 | host/tcp | p2p/base/tcp_port.h:50 |

> ⚠️ M144 变更：老图写的 `UdpPort`(小写 p)/`TcpPort`/`RelayedPort` 类名有误；且不存在独立的 `udp_port.h`——`UDPPort` 就定义在 `stun_port.h:49`，`StunPort` 直接继承 `UDPPort`。"RelayedPort" 不是类名，relay 候选由 `TurnPort` 产生。


### 10.5 STUN 协议架构

**架构特点：MessageBuilder / MessageParser 分离**

```
STUN 消息结构：
┌─────────────────────────────────────────────┐
│  STUN Header (20 bytes)                     │
│  ├─ Message Type (Binding Request/Response) │
│  ├─ Transaction ID (96 bits)                │
│  └─ Magic Cookie + Transaction ID 关联       │
├─────────────────────────────────────────────┤
│  STUN Attributes (变长)                      │
│  ├─ MAPPED-ADDRESS / MAPPED-ADDRESSv6       │
│  ├─ USERNAME (username_fragment)             │
│  ├─ PASSWORD                                 │
│  ├─ RESPONSE-ADDRESS                         │
│  ├─ REFLECTED-FROM                           │
│  └─ FINGERPRINT (CRC32-C，用于完整性校验)     │
└─────────────────────────────────────────────┘

MessageBuilder:  构建 STUN 消息 (类型 + Attributes)
MessageParser:   解析 STUN 消息 (验证类型 + 提取 Attributes)
```

**与 Socket 层的解耦：**

```
Port::OnReadPacket (收到原始 UDP 数据)
    │
    ▼
Port::GetStunMessage (解析是否为 STUN 消息)
    │
    ▼
MessageParser → 验证 STUN 消息格式
    │
    ▼
根据 Message Type 分发到不同处理函数：
  - Binding Request → SendBindingResponse
  - Binding Response → OnBindingResponse
  - Allocate Request → OnAllocateRequest (TurnPort)
```

### 10.6 p2p/ 模块架构优缺点

**优：**
- **Port 抽象让不同候选类型共享同一套连接管理逻辑**：Connection 类不关心底层是 UDP/TCP/TURN
- **工厂模式创建 Port**：PortAllocator 统一创建和管理不同类型的 Port
- **信号槽解耦**：候选发现通过 `SignalCandidateReady` 通知上层，不耦合具体实现

**缺：**
- **ICE 状态机复杂**：Connection Check 涉及 Waiting/InFlight/Frozen 等状态，代码量大
- **Candidate Pair 管理代码量大**：每对候选都需要维护独立的 Connection 对象和状态机
- **NAT 穿透成功率依赖外部 STUN/TURN 服务器**：模块本身无法保证穿透成功


## 第 11 章：media/engine/ 模块架构 —— 桥接层的架构智慧

### 11.1 模块定位

`media/engine/` 是 WebRTC 架构中最精妙的"翻译官"层，连接三层：

```
┌─────────────────────────────────────────────────────────┐
│                    上层 (pc/)                            │
│  RtpTransceiver::CreateChannel (pc/rtp_transceiver.cc:204)│
│    → MediaFactory (pc/media_factory.h:39)                │
│    → voice().CreateSendChannel / CreateReceiveChannel     │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│              media/engine/ (桥接层)                       │
│                                                         │
│  CompositeMediaEngine (media/base/media_engine.h:217)   │
│    │                                                    │
│    ├── VoiceEngineInterface                             │
│    │     └── WebRtcVoiceEngine (webrtc_voice_engine.h:79)│
│    │        ├── 桥接: VoiceMediaSendChannel ↔ AudioSendStream│
│    │        ├── 桥接: 编解码器工厂 ↔ AudioEncoderFactory  │
│    │        └── 桥接: 音频设备 ↔ ADM / APM               │
│    │                                                    │
│    └── VideoEngineInterface                             │
│          └── WebRtcVideoEngine (webrtc_video_engine.h:95)│
│               ├── 桥接: VideoMediaSendChannel ↔ VideoSendStream│
│               ├── 桥接: 编码器工厂 ↔ VideoEncoderFactory │
│               └── 桥接: Simulcast/SVC 配置              │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│                 下层 (call/modules/)                      │
│  Call → AudioSendStream / VideoSendStream /              │
│         AudioReceiveStream / VideoReceiveStream2         │
│  Modules → APM / acm2+NetEq / VideoEncoder / FrameBuffer │
└─────────────────────────────────────────────────────────┘
```

> ⚠️ M144 变更：老图上层入口写 `PeerConnection::CreateVoiceMediaChannel`，且含 `DataEngineInterface/WebRTCDataEngine`。M144 的入口是 `RtpTransceiver::CreateChannel` 经 `MediaFactory` 走 `CreateSendChannel/CreateReceiveChannel`（发送/接收拆分）；数据通道（SCTP）不经过 MediaEngine，由 pc 层 SctpTransport 直连。`APE/ACM/VCM/VPM` 缩写对应的类在 M144 均不存在。

### 11.2 CompositeMediaEngine 架构：统一资源管理

`CompositeMediaEngine` 是桥接层的统一入口，组合语音/视频两个引擎实现：

```cpp
// media/base/media_engine.h
class MediaEngineInterface {
 public:
  virtual ~MediaEngineInterface() {}
  virtual VoiceEngineInterface& voice() = 0;  // 语音引擎入口
  virtual VideoEngineInterface& video() = 0;  // 视频引擎入口
  virtual const VoiceEngineInterface& voice() const = 0;
  virtual const VideoEngineInterface& video() const = 0;
};

// media/base/media_engine.h:217 —— 组合实现
template <typename Voice, typename Video>
class CompositeMediaEngine : public MediaEngineInterface {
  Voice voice_;    // 实际类型 WebRtcVoiceEngine
  Video video_;    // 实际类型 WebRtcVideoEngine
};
```

**架构特点：组合两个引擎，工厂注入**

```
┌──────────────────────────────────────────┐
│      CompositeMediaEngine                │
│      (media/base/media_engine.h:217)     │
│                                          │
│  voice_ ──→ WebRtcVoiceEngine            │
│    │    (pc/webrtc_voice_engine.h:79)    │
│    ├── adm_ ──→ AudioDeviceModule (平台) │
│    ├── apm_ ──→ AudioProcessing (APM)   │
│    └── encoder_factory_/decoder_factory_ │
│                                          │
│  video_ ──→ WebRtcVideoEngine            │
│    │    (pc/webrtc_video_engine.h:95)    │
│    ├── encoder_factory_ ──→ VideoEncoderFactory │
│    └── decoder_factory_ ──→ VideoDecoderFactory │
└──────────────────────────────────────────┘
（编解码器不在此处"注册"——协商结果驱动工厂按需创建实例）
```

> ⚠️ M144 变更：老版图里的 `audio_coding_ (ACM)`、`video_coding_ (VCM)`、`video_processing_ (VPM)` 成员均不存在；编解码器也非"初始化时统一注册"，而是工厂持有能力列表，SDP 协商后按 codec 实例化。类名是 `WebRtcVoiceEngine`/`WebRtcVideoEngine`（小写 rtc），不是 `WebRTCVoiceEngine`。

### 11.3 WebRtcVoiceEngine 架构

**架构特点：Send/Receive 接口拆分，通道桥接 Call 层**

```
VoiceEngineInterface
    │
    ▼
WebRtcVoiceEngine (pc/webrtc_voice_engine.h:79)
├── adm_ (AudioDeviceModule)          ← 音频设备
├── apm_ (AudioProcessing)           ← 音频处理
├── encoder_factory_ / decoder_factory_ ← 编解码工厂
└── CreateSendChannel / CreateReceiveChannel   ← 通道工厂入口

发送通道: WebRtcVoiceSendChannel (webrtc_voice_engine.h:188)
  实现 VoiceMediaSendChannelInterface (media/base/media_channel.h:894)
├── call_ (Call*)                    ← 回调到 Call 层
├── send_stream_ (AudioSendStream*)  ← 发送流（Call::CreateAudioSendStream 创建）
└── send_codec_                      ← 当前发送编解码器

接收通道: WebRtcVoiceReceiveChannel
  实现 VoiceMediaReceiveChannelInterface (media_channel.h:914)
├── call_ (Call*)
├── recv_stream_ (AudioReceiveStream*) ← 接收流（内部跑 NetEq）
└── recv_codec_                      ← 当前接收编解码器
```

**编解码器协商的桥接逻辑：**

```
信令层 (pc/) 协商结果：
  "双方都支持 Opus 48kHz"
       │
       ▼
RtpTransceiver::CreateChannel (协商完成后, pc/rtp_transceiver.cc:204)
       │
       ├── 1. media_factory->voice().CreateSendChannel(...)
       │      → WebRtcVoiceSendChannel
       │
       ├── 2. SetSenderParameters (media_channel.h:894)
       │      → call_->CreateAudioSendStream(Config{encoder_factory→Opus 实例})
       │
       └── 3. CreateReceiveChannel → WebRtcVoiceReceiveChannel
              → SetReceiverParameters → call_->CreateAudioReceiveStream
                （AudioReceiveStream 内部装配 NetEq）
```

> ⚠️ M144 变更：M144 的 `VoiceMediaSendChannelInterface`/`VoiceMediaReceiveChannelInterface`（media_channel.h:894/914）把老 `VoiceMediaChannel` 拆成了发送/接收两个接口、两个实现类；协商后的参数应用分别是 `SetSenderParameters`/`SetReceiverParameters`。通道创建入口不再是 `WebRTCVoiceEngine::CreateMediaChannel`。

### 11.4 WebRtcVideoEngine 架构

**架构特点：VideoMediaChannel ↔ VideoSendStream 的映射**

```
VideoEngineInterface
    │
    ▼
WebRtcVideoEngine (pc/webrtc_video_engine.h:95)
├── encoder_factory_ / decoder_factory_ ← 编解码工厂
└── CreateSendChannel / CreateReceiveChannel

发送通道: WebRtcVideoSendChannel (webrtc_video_engine.h:162)
  实现 VideoMediaSendChannelInterface
├── call_ (Call*)
├── send_streams_ (map<..., VideoSendStream*>)
└── simulcast_config 由 VideoSendStream 内部
    SimulcastEncoderAdapter 处理

接收通道: WebRtcVideoReceiveChannel
  实现 VideoMediaReceiveChannelInterface
├── call_ (Call*)
└── recv_streams_ (map<..., VideoReceiveStream2*>)
    （VideoReceiveStream2: video/video_receive_stream2.h:101，
      内部含 FrameBuffer + VideoStreamBufferController + NackRequester）
```

**Simulcast 配置的桥接：**

```
信令层协商：
  Simulcast 参数 (3 档: 高/中/低)
       │
       ▼
WebRtcVideoSendChannel::AddSendStream
       │
       ├── 1. 解析 Simulcast 配置（SpatialLayer 配置列表）
       │
       └── 2. call_->CreateVideoSendStream(Config)
              → VideoSendStreamEncoder 内部按层创建
                SimulcastEncoderAdapter（多编码器实例）
```

### 11.5 MediaEngineInterface 架构设计哲学

**架构特点：接口与实现分离，实现可完全替换**

```
依赖倒置原则的完美体现：

  pc 层 (RtpTransceiver / MediaFactory)
    │  通过接口调用
    ▼
  MediaEngineInterface  ← 抽象接口 (media/base/)
    │
    │  具体实现
    ▼
  CompositeMediaEngine + WebRtcVoiceEngine/WebRtcVideoEngine
    ← 具体实现 (media/base/ + pc/)

关键：pc 层不知道具体实现是 WebRtc 的还是其他实现
     只要实现 MediaEngineInterface 即可替换
```

**依赖注入：MediaFactory 由 ConnectionContext 持有**

```cpp
// pc/connection_context.h:105 —— ConnectionContext 持有 MediaFactory
class ConnectionContext final {
  std::unique_ptr<MediaFactory> media_factory_;   // :166
  // PeerConnectionFactoryDependencies 创建时注入具体实现
};

// pc/rtp_transceiver.cc:204 —— 创建通道时通过接口拿引擎
std::unique_ptr<ChannelInterface> RtpTransceiver::CreateChannel(...) {
  // worker 线程 BlockingCall 内:
  auto send_channel = media_factory->voice().CreateSendChannel(...);
  auto recv_channel = media_factory->voice().CreateReceiveChannel(...);
  return std::make_unique<VoiceChannel>(...);
}
```


### 11.6 桥接层架构优缺点

**优：**
- **完美的依赖倒置**：上层 (pc/call) 不依赖下层 (modules) 的具体实现
- **实现可替换**：可以完全替换 APM、编码器、音频设备等，只需实现接口
- **资源统一管理**：一个入口管理所有媒体资源，生命周期清晰
- **配置集中**：编解码器协商、Simulcast 配置在桥接层统一处理

**缺：**
- **桥接层代码量较大**：每新增一个模块（音频处理、视频编码、数据采集）都要写桥接代码
- **接口膨胀**：`MediaEngineInterface` 和 `VoiceEngineInterface`/`VideoEngineInterface` 接口方法较多
- **调试链路长**：从 PeerConnection 到最终编码器，经过 4-5 层桥接


---

## 第 12 章：设计模式全景 —— WebRTC 用了哪些设计模式

### 12.1 工厂模式（Factory）

**应用场景**：
- `PeerConnectionFactory::CreatePeerConnection()` → 创建 PeerConnection
- `Call::Create()` → 创建 Call 实例
- `Call::CreateAudioSendStream()` → 创建音频发送流
- `PortAllocator` → 创建不同类型的 Port

**架构价值**：
- 统一创建入口，隐藏创建细节
- 创建逻辑集中管理，便于测试注入

### 12.2 桥接模式（Bridge）

**应用场景**：
- `MediaEngineInterface` 桥接 pc/call 层与 modules 层
- `AudioProcessing` 桥接 AEC 算法与上层调用

**架构价值**：
- 依赖倒置的完美体现
- 上层不依赖下层实现

### 12.3 外观模式（Facade）

**应用场景**：
- `PeerConnection` 作为统一入口，内部协调 JsepTransportController + RtpTransmissionManager/SdpOfferAnswerHandler + MediaSession
- `AudioProcessing` 作为音频处理的统一入口

**架构价值**：
- 对外简洁，对内复杂
- 上层只需调用一个方法，内部自动协调多个子模块

### 12.4 观察者模式（Observer）

**应用场景**：
- `sigslot::signal1<T>` 信号槽机制
- `PeerConnectionObserver` 回调接口
- `EncodedImageCallback` / `FrameTypeCallback`

**架构价值**：
- 事件驱动，解耦发送方和接收方
- 同线程内同步通知，无异步回调地狱

### 12.5 状态机模式（State Machine）

**应用场景**：
- ICE 连接状态：New → Gathering → Connecting → Connected → Completed
- PeerConnection 状态：New → Connecting → Connected → Disconnected → Failed
- DTLS 状态：Handshake → Established → Closed

**架构价值**：
- 状态转换显式化，便于理解和调试
- 非法状态转换被阻止（如 Directly 从 New 到 Connected）

### 12.6 装饰器模式（Decorator）

**应用场景**：
- `SSLStreamAdapter` 装饰 `AsyncSocket`，透明添加 SSL/TLS
- `SimulcastEncoderAdapter` 装饰多个 `VideoEncoder`，统一输出
- `CompositeRtpTransport` 装饰多个 RTP Transport

**架构价值**：
- 功能可叠加，不修改原有类
- 运行时动态组合功能

### 12.7 策略模式（Strategy）

**应用场景**：
- 编解码器协商：根据 SDP 选择具体编码器
- BWE 算法：DelayBasedBWE vs PacketLossBasedBWE
- Bundle Policy：kBundlePolicyBalanced vs kBundlePolicyAllMedia vs kBundlePolicyMaxBundle

**架构价值**：
- 算法可替换，不影响调用方
- 运行时选择策略

### 12.8 组合模式（Composite）

**应用场景**：
- `CompositeRtpTransport`：组合多个 RTP Transport
- `CompositeDataChannelTransport`：组合 SCTP + Datagram

**架构价值**：
- 统一接口处理单个对象和组合对象
- 透明地组合多个传输

### 12.9 RAII 资源管理

**应用场景**：
- `unique_ptr` 管理模块所有权（RtpTransceiver 持有 channel_，pc/rtp_transceiver.h:121）
- `scoped_refptr` 管理引用计数对象
- `RTCCertificate` 通过 unique_ptr 管理

**架构价值**：
- 自动生命周期管理，避免内存泄漏
- 所有权语义清晰

### 12.10 依赖注入（DI）

**应用场景**：
- `PeerConnectionFactoryDependencies`：注入线程、编码器工厂、事件日志
- `MediaEngineDependencies`：注入音频设备、音频处理、音频编码
- `Call::Config`（call/call_config.h:33）：注入 `Environment env`（:48，含 Clock/TaskQueue 工厂等）与 network_task_queue

**架构价值**：
- 松耦合，实现可替换
- 测试时注入 Mock 对象

### 12.11 设计模式使用频率统计

```
WebRTC 设计模式使用频率：

  工厂模式      ████████████████████  极高（创建入口）
  观察者模式    ████████████████████  极高（事件通知）
  装饰器模式    ██████████████████    高（功能叠加）
  依赖注入      ████████████████      高（配置注入）
  外观模式      ██████████████        中高（统一入口）
  状态机模式    ████████████          中（ICE/DTLS 状态）
  策略模式      ██████████            中（算法选择）
  桥接模式      ████████              中（层间桥接）
  组合模式      ██████                低（组合传输）
  RAII         ████████████████████  极高（资源管理）
```

---

## 第 13 章：架构的优缺点深度分析

### 13.1 优点

#### 13.1.1 线程亲和 + Proxy：零锁高性能

```
为什么零锁重要？

传统锁方案：
  线程 A ──→ [锁] ──→ 共享数据 ──→ [锁] ←── 线程 B
                    ↑
              锁竞争 = 线程等待 = 延迟增加

WebRTC 线程亲和：
  线程 A ──→ [对象 A]    [对象 B] ←── 线程 B
                  ↑ Proxy 跨线程消息
              无锁竞争 = 零等待

性能差异：
  锁方案：每次访问 ~10-100ns（锁竞争时 ~us 级）
  线程亲和：消息投递 ~100ns（队列 push）
  但跨线程调用本身是异步的，所以延迟模型不同
```

**核心优势**：
- 没有锁竞争，不会因一个慢线程阻塞其他线程
- 每个线程独立处理消息，CPU 缓存局部性好
- 实时场景下延迟可预测

#### 13.1.2 分层清晰：每层职责单一

```
分层的好处：

  修改编码器：只改 modules/video_coding/，不影响 pc/ 和 call/
  修改 SDP：只改 pc/，不影响 modules/
  修改拥塞控制：只改 modules/congestion_controller/，不影响其他层

如果分层混乱：
  改编码器 → 需要改 pc/ 的 SDP 解析 → 需要改 call/ 的 Stream 管理
  → 回归测试范围扩大 10 倍
  → 引入 bug 的概率增加 10 倍
```

#### 13.1.3 接口抽象：实现可替换

```
接口抽象的实际价值：

  场景 1：Android 硬件编码器
    上层：VideoSendStream
    下层：VideoEncoder 接口
    实现：WebRtcVideoEncoderVP8（软件）或 MediaCodec（硬件）
    → 换实现不改上层

  场景 2：测试
    上层：AudioSendStream
    下层：AudioProcessing 接口
    实现：真实的 APM 或 MockAPM
    → 测试不依赖真实硬件
```

#### 13.1.4 可测试性

```
Proxy 模式对测试的帮助：

  生产代码：
    PeerConnection (signaling 线程)
      └─ Proxy → PeerConnection 内部组件 (worker 线程)

  测试代码：
    PeerConnection (测试线程 = signaling 线程)
      └─ Proxy → 内部组件 (测试线程 = worker 线程)

    优势：测试时可以让 signaling 线程和 worker 线程是同一个线程
    → 不需要多线程就能测试，简化测试复杂度
```

### 13.2 缺点

#### 13.2.1 Proxy 模式增加代码复杂度

```
Proxy 模式的代码膨胀：

  简单场景（无 Proxy）：
    class Channel {
      void Process() { data_++; }
      int data_;
    };
    // 4 行代码

  Proxy 场景：
    // 1. 接口定义
    class ChannelInterface {
      virtual void Process() = 0;
    };

    // 2. 实际实现
    class Channel : public ChannelInterface {
      void Process() override { data_++; }
      int data_;
    };

    // 3. Wrap/Unwrap 注册
    // 4. Proxy<Channel> 模板实例
    // 5. 跨线程调用
    proxy_->call(&Channel::Process);

    // 至少 20 行代码，功能相同
```


#### 13.2.2 线程亲和导致 API 使用门槛高


```
新手使用 WebRTC API 的常见错误：

  // 错误：在 UI 线程（非 signaling 线程）调用
  void OnUiButtonClicked() {
    peer_connection_->CreateOffer(...);  // CRASH!
  }

  // 正确：Post 到 signaling 线程
  void OnUiButtonClicked() {
    signaling_thread_->Post(
        RTC_FROM_HERE,
        new std::function<void()>([pc = peer_connection_] {
          pc->CreateOffer(...);
        }),
        nullptr);
  }
```

**问题根源**：
- API 设计假设用户理解线程亲和模型
- 实际用户（尤其是移动端开发者）往往不理解
- 错误使用导致难以调试的 crash

#### 13.2.3 过度抽象：接口层级过深

```
一次 SetLocalDescription 应用 channel 参数的调用深度（M144）：

  第 1 层：PeerConnection::SetLocalDescription()
    │
  第 2 层：SdpOfferAnswerHandler::ApplyLocalDescription (sdp_offer_answer.cc:1801)
    │
  第 3 层：worker_thread()->BlockingCall (sdp_offer_answer.cc:5169) —— 跨线程点
    │
  第 4 层：RtpTransceiver::SetLocalContent / channel 应用参数
    │
  第 5 层：VoiceChannel::SetLocalContent_w (channel.cc:320)
    │
  第 6 层：VoiceMediaSendChannelInterface::SetSenderParameters (media_channel.h:894)
    │
  第 7 层：AudioSendStream::Reconfigure
    │
  第 8 层：AudioEncoder 重新创建（工厂按新 codec 实例化）

8 层调用深度，每层都有类型转换，第 3 层还有一次线程切换
```

#### 13.2.4 学习曲线陡峭

```
学习 WebRTC 架构的时间线：

  第 1 周：理解模块划分（wr-modules-analysis.md）
  第 2 周：理解业务流程（wr-whole-process.md）
  第 3 周：理解线程模型和 Proxy 模式
  第 4 周：理解 SDP 协商和 ICE 流程
  第 5 周：理解拥塞控制和码率调整
  第 6 周+：理解编解码器细节和算法

正常需要 1-2 个月才能完全理解架构
```

#### 13.2.5 调试困难

```
跨线程调试的挑战：

  问题：音频有杂音
  调用链：PeerConnection → VoiceChannel → AudioSendStream → APM → AudioEncoder

  传统调试：
    在 AudioSendStream 设断点 → 但它在 worker 线程的 TaskQueue 上
    当前在 signaling 线程 → 需要切换线程上下文
    切换后断点可能失效 → 需要重新设断点

  WebRTC 的调试工具：
    - rtc::LogMessage::SetMinLoggingLevel(0) 开启详细日志
    - .webrtc 文件 dump 所有交互
    - Chromium 的 about://webrtc-internals
    - 但仍然比单线程调试难 5-10 倍
```

#### 13.2.6 Config 结构体膨胀

```
AudioSendStream::Config 字段数：30+
VideoSendStream::Config 字段数：40+

原因：
  - 每个 modules 子模块都需要自己的配置参数
  - 配置通过 Call 层传递给 modules 层
  - 无法进一步抽象（不同编解码器参数差异大）

后果：
  - 创建 Stream 的代码冗长
  - 新增配置字段需要修改所有调用处
  - 参数校验逻辑分散
```

#### 13.2.7 桥接层代码冗余

```
media/engine/ 的代码量：

  WebRTCMediaEngine：~500 行
  WebRtcVoiceEngine：~800 行（含 Send/Receive 两通道实现）
  WebRtcVideoEngine：~1200 行（含 Send/Receive 两通道实现）

  总计 ~2500 行桥接代码，占整个 modules/ 的 10%+

原因：
  - 每个 modules 子模块都需要桥接
  - 线程转换在桥接层完成
  - 编解码器协商逻辑在桥接层实现
```

### 13.3 与其他 WebRTC 实现对比

#### 13.3.1 libwebrtc vs pion (Go) vs mediasoup (Node.js)

```
┌─────────────────────────────────────────────────────────────────┐
│  特性          │ libwebrtc       │ pion          │ mediasoup     │
├─────────────────────────────────────────────────────────────────┤
│ 语言           │ C++             │ Go            │ Node.js       │
│ 架构           │ 5 层 + Proxy    │ 纯 Go goroutine │ 事件驱动      │
│ 并发模型       │ 线程亲和         │ channel       │ event loop    │
│ 性能           │ 极高（零拷贝）    │ 高            │ 中            │
│ 可定制性       │ 高（源码修改）    │ 中            │ 高（JS 层）   │
│ 学习曲线       │ 陡峭            │ 平缓          │ 平缓          │
│ 调试难度       │ 高              │ 中            │ 低            │
│ 适用场景       │ 原生应用        │ Go 后端       │ Node.js 服务器│
├─────────────────────────────────────────────────────────────────┤
│ 架构取舍       │                                                  │
│ libwebrtc      │ 性能优先，架构复杂                               │
│ pion           │ 开发效率优先，架构简洁                           │
│ mediasoup      │ 易用性优先，事件驱动架构                         │
└─────────────────────────────────────────────────────────────────┘
```

**关键架构取舍**：

| 维度 | libwebrtc | pion | mediasoup |
|---|---|---|---|
| 并发 | 线程亲和 + Proxy | goroutine | event loop |
| 内存 | 手动 + 引用计数 | GC | V8 内存管理 |
| 编解码 | 内置 + 硬件加速 | 调用外部 | 调用外部 |
| 部署 | 编译原生库 | go get | npm install |
| 内存 | 手动 + 引用计数 | GC | V8 内存管理 |
| 编解码 | 内置 + 硬件加速 | 调用外部 | 调用外部 |
| 部署 | 编译原生库 | go get | npm install |

### 13.4 架构取舍总结

```
WebRTC 架构的核心取舍：

  性能 ────┬──── 简洁
           │
           ├── 选择性能（libwebrtc）
           │   代价：架构复杂、学习曲线陡、调试困难
           │
           ├── 选择简洁（pion）
           │   代价：GC 停顿、性能略低、硬件加速难
           │
           └── 选择易用（mediasoup）
               代价：Node.js 性能瓶颈、并发能力有限

WebRTC 选择了第一条路：性能优先
原因：实时通信对延迟和抖动极度敏感
```
WebRTC 选择了第一条路：性能优先
原因：实时通信对延迟和抖动极度敏感


---

## 第 14 章：架构设计原则与最佳实践

### 14.1 单一职责原则（SRP）在 WebRTC 中的体现

**SRP**：一个类只有一个引起它变化的原因。

WebRTC 中的体现：

```
VoiceChannel 违反 SRP 吗？

  VoiceChannel 的职责：
  1. SDP 内容协商（SetLocalContent/SetRemoteContent）
  2. 媒体发送（SendPacket）
  3. 媒体接收（OnRtpPacket）
  4. DTLS/SRTP 状态管理
  5. 可写状态通知

  看起来有多个职责？不——所有职责都围绕"一个媒体通道"
  如果拆分：
    VoiceChannelSdpHandler → 只处理 SDP
    VoiceChannelMediaSender → 只处理发送
    VoiceChannelMediaReceiver → 只处理接收

  问题：这三个类之间需要共享大量状态（enabled_、local_streams_、rtp_transport_）
  → 拆分后状态管理更复杂，且职责边界模糊

结论：VoiceChannel 的多个职责是"自然聚合"，不是"不合理耦合"
SRP 不是"一个类只做一个方法"，而是"一个类只对一个变化原因负责"

VoiceChannel 的变化原因只有一个：媒体通道的行为变化
```

### 14.2 依赖倒置原则（DIP）：接口而非实现

**DIP**：高层模块不应依赖低层模块，两者都应依赖抽象。

WebRTC 中的经典体现：

```
错误做法（违反 DIP）：
  class AudioSendStream {
    WebRtcVoiceEngine* voice_engine_;  // 直接依赖实现
  };
  问题：换 VoiceEngine 实现需要改 AudioSendStream

正确做法（遵循 DIP）：
  class MediaEngineInterface {  // 抽象
    virtual std::unique_ptr<AudioSendStream> CreateAudioSendStream(...) = 0;
  };
  class Call {
    MediaEngineInterface* media_engine_;  // 依赖抽象
  };
  优势：换实现不改 Call 层代码
```

### 14.3 开闭原则（OCP）：扩展而不修改

**OCP**：对扩展开放，对修改关闭。

WebRTC 中的体现：

```
新增编解码器 H264：
  - 不改 AudioSendStream 代码 ✓
  - 不改 VoiceChannel 代码 ✓
  - 不改 PeerConnection 代码 ✓
  - 只需：实现 VideoEncoder 接口 + 注册到 VideoEncoderFactory

新增拥塞控制算法：
  - 不改 RtpTransportControllerSend 代码 ✓
  - 只需：实现 BandwidthEstimator 接口 + 注入到 GCC

这就是 OCP：通过扩展（新类）而不是修改（改旧类）来增加功能
```

### 14.4 里氏替换原则（LSP）：继承体系的安全性

**LSP**：子类必须能够替换父类而不破坏程序。

WebRTC 中的体现：

```
VideoEncoder 继承体系：

  class VideoEncoder {
    virtual WebRtcVideoEncoder::EncodeResult Encode(
        const EncodedImage& image,
        const VideoEncoder::FrameType* frame_types,
        const std::vector<VideoCodecType>* codec_types) = 0;
  };

  WebRtcVideoEncoderVP8 替换 WebRtcVideoEncoderVP9：
  - Encode() 签名相同 ✓
  - 返回值语义相同 ✓
  - 错误处理相同 ✓
  → LSP 满足

如果 VP8 的 Encode() 返回成功但实际没编码（VP9 会返回错误）：
  → LSP 违反，调用方会误以为编码成功
```

### 14.5 接口隔离原则（ISP）：最小接口契约

**ISP**：不应强迫客户端依赖它不需要的方法。

WebRTC 中的体现：

```
MediaEngineInterface 的 ISP 设计：

  class MediaEngineInterface {
    // 音频相关
    virtual int RegisterAudioCodec(...) = 0;
    virtual std::unique_ptr<AudioSendStream> CreateAudioSendStream(...) = 0;

    // 视频相关
    virtual int RegisterVideoCodec(...) = 0;
    virtual std::unique_ptr<VideoSendStream> CreateVideoSendStream(...) = 0;

    // 每个 Stream 类型有独立的 Create/Dispose 方法
    // 而不是一个通用的 CreateStream(MediaKind) 方法
  };

  优势：
  - 实现类不需要实现不关心的方法
  - 接口方法按功能分组，职责清晰
  - 新增 Stream 类型只需加接口，不影响现有实现
```

### 14.6 组合优于继承：WebRTC 的偏好

WebRTC 倾向于**组合**而非**继承**：

```
继承方式（不推荐）：
  class BaseChannel { ... };
  class VoiceChannel : public BaseChannel { ... };
  class VideoChannel : public BaseChannel { ... };

  问题：
  - 继承层次深（BaseChannel → VoiceChannel → SpecialVoiceChannel）
  - 方法重写可能破坏父类不变量
  - 多重继承在 C++ 中更复杂

组合方式（WebRTC 偏好）：
  class AudioSendStream {
    std::unique_ptr<AudioEncoder> encoder_;       // 组合
    std::unique_ptr<AudioProcessing> apm_;         // 组合
    std::unique_ptr<RTPSender> rtp_sender_;       // 组合
  };

  优势：
  - 运行时可替换组件
  - 无继承层次问题
  - 组件可独立测试
```

### 14.7 从 WebRTC 学到的架构设计经验

```
经验 1：线程亲和不是银弹
  Proxy 模式解决了并发问题，但增加了代码复杂度
  评估：你的项目是否需要零锁高性能？
  如果不需要，简单的锁可能更合适

经验 2：接口越多，实现越痛苦
  MediaEngineInterface 有 20+ 纯虚方法
  实现一个 Mock 需要写 20+ 方法
  评估：接口数量应该平衡"灵活性"和"实现成本"

经验 3：Config 结构体是必要的恶
  30+ 字段的 Config 不美观，但比 30 个构造函数参数好
  评估：使用 Builder 模式改善体验
  （WebRTC 的 AudioProcessing 就用 Builder）

经验 4：分层不是越多越好
  5 层架构清晰，但每次调用跨越 8 层
  评估：热点路径可以打破分层（如 RTP 封包直接调用）

经验 5：架构决策要匹配业务需求
  WebRTC 选择性能优先 → 接受架构复杂度
  如果你的项目是 CRUD → 选简单架构
```


---

## 第 15 章：落地指南 —— 如何设计一个 WebRTC 风格的系统

### 15.1 场景 1：设计一个实时消息系统

**需求**：设计一个跨平台的实时消息推送系统，要求低延迟、高并发。

**从 WebRTC 提取的模式**：

```
模式 1：线程亲和 + 消息队列

  你的系统：
    网络线程（接收消息）
       │
       │ PostMessage
       ▼
    业务线程（处理消息）
       │
       │ PostMessage
       ▼
    存储线程（持久化）

  WebRTC 的做法：
    network 线程 → PostTask → worker 线程（TaskQueue）→ PostTask → 各周期任务

  你的简化版：
    不需要 Proxy 模式（消息系统不需要跨线程对象访问）
    只需要消息队列 + 线程池
```

**可复用架构**：
- rtc_base 的 Thread/MessageHandler → 你的消息分发系统
- sigslot → 你的事件通知系统
- 不需要 scoped_refptr（消息系统有 GC 或智能指针）

### 15.2 场景 2：设计一个音视频处理插件框架

**需求**：设计一个音视频处理插件框架，允许第三方开发者编写插件。

**从 WebRTC 提取的模式**：

```
模式 2：接口抽象 + 依赖注入

  你的框架：
    ┌─────────────────────┐
    │  ProcessingPipeline  │  ← 处理管线（框架核心）
    │                     │
    │  filter_chain_      │
    │  ├── IFilter*       │
    │  ├── IFilter*       │
    │  └── IFilter*       │
    └─────────────────────┘
              │
              │ 注入
              ▼
    ┌─────────────────────┐
    │  IFilter (接口)      │
    │  virtual Frame      │
    │    Process(Frame) = 0│
    └─────────────────────┘
              │
       ┌──────┼──────┐
       │      │      │
    ┌──┴──┐ ┌┴──┐ ┌──┴──┐
    │BGRG │ │H26│ │HDR │  ← 第三方插件
    │ToI4 │ │4To│ │Effect│
    └─────┘ └───┘ └─────┘

  WebRTC 的做法：
    MediaEngineInterface → WebRtcVoiceEngine/WebRtcVideoEngine
    VideoEncoder → VP8/VP9/H264 实现

  你的简化版：
    IFilter 接口 + 插件加载器（动态库）
```

**可复用架构**：
- `TaskQueueBase` + `RepeatingTaskHandle`（周期任务）→ 你的插件调度接口
- `MediaEngineInterface` → 你的插件管理器接口
- 配置驱动 → 你的插件配置系统

### 15.3 场景 3：设计一个跨线程的监控采集系统

**需求**：设计一个系统，从多个硬件设备采集数据，在另一个线程分析，在第三个线程存储。

**从 WebRTC 提取的模式**：

```
模式 3：三线程链式处理

  你的系统：
    采集线程 ──→ 分析线程 ──→ 存储线程
       │             │             │
       ▼             ▼             ▼
    硬件驱动      算法引擎      数据库/缓存

    线程间通信：
    - 采集 → 分析：scoped_refptr<DataBuffer>（零拷贝）
    - 分析 → 存储：PostTask（消息队列）

  WebRTC 的做法：
    network 线程 → worker 线程（TaskQueue 上的 media/call 逻辑）
    - RTP 包：scoped_refptr<VideoFrame>（零拷贝）
    - 配置：PostTask + lambda

  你的简化版：
    不需要 Proxy 模式（采集数据是拷贝而非对象访问）
    但 scoped_refptr + 零拷贝 模式可复用
```

### 15.4 从 WebRTC 架构中提取的可复用模式

```
可直接复用的模式清单：

  1. 线程亲和 + 消息队列
     适用：任何多线程系统
     复杂度：中
     收益：高（避免锁竞争）

  2. sigslot 信号槽
     适用：同线程事件通知
     复杂度：低（纯头库）
     收益：高（解耦发送/接收方）

  3. scoped_refptr + 创建线程销毁
     适用：C++ 多线程对象的内存管理
     复杂度：中
     收益：高（避免内存泄漏 + 线程安全）

  4. 接口抽象 + 依赖注入
     适用：需要可替换实现的系统
     复杂度：低
     收益：高（测试 + 扩展）

  5. 配置驱动
     适用：参数多、变化多的系统
     复杂度：低
     收益：中（避免硬编码）

  6. TaskQueue + RepeatingTaskHandle（周期任务）
     适用：周期性处理的模块（RTCPSender/TaskQueuePacedSender 都这样跑）
     复杂度：低
     收益：中（统一调度）

  7. Facade 模式
     适用：复杂子系统需要简化入口
     复杂度：低
     收益：高（降低使用门槛）
```

### 15.5 架构演进的教训：什么该抽象、什么不该抽象

```
该抽象的：
  ✓ 编解码器（VP8/VP9/H264 差异大，需要抽象）
  ✓ 音频设备（麦克风 API 跨平台差异大）
  ✓ 网络传输（Socket API 跨平台）
  ✓ 拥塞控制算法（BWE 可能替换）

不该抽象的：
  ✗ UDP 发送（直接 sendto() 即可，不需要抽象层）
  ✗ 日志系统（LogMessage 已经够简单）
  ✗ 字符串处理（std::string 够用）
  ✗ 容器（std::vector 够用）

判断标准：
  如果差异只在实现细节 → 不该抽象
  如果差异在接口/行为/参数 → 该抽象
  如果未来可能替换 → 该抽象
  如果只是一次性使用 → 不该抽象

WebRTC 的教训：
  - APM 的 Config 过度抽象（每个子系统独立 Config → 合并为 ProcessingConfig）
  - AudioSendStream::Config 不够抽象（30+ 字段 → 应该分组）
  - 但 VideoEncoder 接口抽象得恰到好处（VP8/VP9/H264 顺利替换）

---

## 总结

WebRTC 的架构设计可以用一句话概括：

> **以性能为第一目标，通过分层 + 接口抽象 + 线程亲和，在 150 万行代码中维持可管理的复杂度。**

其架构的核心特征：

1. **五层分层**：应用 → API → 呼叫 → 处理 → 基础设施，单向依赖
2. **线程亲和**：四大线程 + Proxy 模式，零锁高性能
3. **接口抽象**：MediaEngineInterface 等接口实现依赖倒置
4. **模块化**：各 modules 子模块独立开发和测试
5. **配置驱动**：所有参数通过 Config 对象传入
6. **RAII 管理**：unique_ptr + scoped_refptr 自动生命周期

架构的代价：
- 代码复杂度高（Proxy 模式、线程切换）
- 学习曲线陡峭（1-2 个月才能完全理解）
- 调试困难（跨线程调用链追踪）
- Config 结构体膨胀（30-40+ 字段）

对于新项目，建议：
- 如果不需要零锁高性能 → 不要照搬 Proxy 模式
- 如果需要可替换实现 → 学习接口抽象 + 依赖注入
- 如果需要多线程 → 学习 TaskQueue/消息模型 + 信号槽
- 如果需要模块化 → 学习 TaskQueueBase + RepeatingTaskHandle 的任务调度模型
