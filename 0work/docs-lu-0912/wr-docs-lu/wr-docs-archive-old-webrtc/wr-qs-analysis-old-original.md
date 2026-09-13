# WebRTC QoS 设计分析

> 读者画像：具备 C/C++ 经验，熟悉高级 C++ 用法但需要补充；已有模块认知、架构认知和完整业务流程认知，希望深入理解 QoS 的算法内部原理与参数。
>
> 相关文档：
> - `wr-modules-analysis.md`：模块架构分析
> - `wr-arch-design-analysis.md`：整体架构设计分析
> - `wr-whole-process.md`：完整业务流程分析
> - `wr-qs-design-analysis-plan.md`：本文档的章节规划

---

## 目录

### 概览

| 章节 | 标题 | 摘要 |
|---|---|---|
| 第 0 章 | 导读与全景 | QoS 范畴、全景图、三大控制目标、阅读路径 |
| 第 1 章 | QoS 总体架构 | 发送侧/接收侧闭环、反馈通道、架构图、线程架构总览 |
| 第 2 章 | 拥塞控制核心 GCC | 延迟/丢包/探测三路融合、Trendline、AIMD、探测、ALR、cwnd |
| 第 3 章 | 接收侧拥塞控制与反馈 | Kalman BWE、TWCC、TransportFeedbackAdapter、控制门控 |
| 第 4 章 | Pacing 与码率分配 | 漏桶 Pacing、优先级轮转队列、BitrateAllocator 分配算法 |
| 第 5 章 | 丢包恢复 NACK 与 FEC | NACK 请求策略、RTX 重传、ULP/FlexFEC、保护模式 |
| 第 6 章 | 抖动缓冲与时延控制 | Kalman 抖动估计、FrameBuffer 依赖图、Timing、A/V 同步 |
| 第 7 章 | 视频自适应 | CPU 过载、质量缩放、Resource 适配管线、码率调整器 |
| 第 8 章 | 音频网络适配 | ANA 控制器、码率/帧长/DTX/FEC 动态调整 |
| 第 9 章 | 核心数据结构与单位系统 | DataRate/DataSize/TimeDelta、控制消息结构 |
| 第 10 章 | 线程架构与并发控制 | controller/pacer/decode 队列、跨线程同步 |
| 第 11 章 | 内存与控制架构 | 所有权体系、反馈闭环、分层控制、控制周期 |
| 第 12 章 | 动态网络场景下的算法作用 | 启动爬坡、骤降恢复、高丢包、抖动、CPU 过载等 9 场景 |
| 第 13 章 | 设计模式与设计哲学 | 策略/工厂/观察者/状态机、反馈控制哲学 |
| 第 14 章 | QoS 设计优缺点与最佳实践 | 优缺点、与 TCP/SCReAM/NADA 对比、可复用模式 |

---

### 详细目录

#### 第 0 章：导读与全景
- [0.1 什么是 QoS](#01-什么是-qos)
- [0.2 QoS 全景图](#02-qos-全景图)
- [0.3 三大控制目标](#03-三大控制目标)
- [0.4 文档组织与阅读路径](#04-文档组织与阅读路径)

#### 第 1 章：QoS 总体架构
- [1.1 QoS 在五层架构中的位置](#11-qos-在五层架构中的位置)
- [1.2 发送侧 QoS 架构](#12-发送侧-qos-架构)
- [1.3 接收侧 QoS 架构](#13-接收侧-qos-架构)
- [1.4 反馈通道](#14-反馈通道)
- [1.5 总体架构图](#15-总体架构图)
- [1.6 控制流 vs 数据流 vs 反馈流](#16-控制流-vs-数据流-vs-反馈流)
- [1.7 线程架构总览](#17-线程架构总览)

#### 第 2 章：拥塞控制核心 GCC
- [2.1 GCC 设计哲学](#21-gcc-设计哲学)
- [2.2 入口与控制 API](#22-入口与控制-api)
- [2.3 工厂与实例化](#23-工厂与实例化)
- [2.4 类图与组件组合](#24-类图与组件组合)
- [2.5 延迟估计 TrendlineEstimator](#25-延迟估计-trendlineestimator)
- [2.6 延迟 BWE 与 AIMD](#26-延迟-bwe-与-aimd)
- [2.7 丢包 BWE](#27-丢包-bwe)
- [2.8 探测 BWE](#28-探测-bwe)
- [2.9 ALR 检测](#29-alr-检测)
- [2.10 确认码率](#210-确认码率)
- [2.11 拥塞窗口与回退](#211-拥塞窗口与回退)
- [2.12 输出 NetworkControlUpdate](#212-输出-networkcontrolupdate)
- [2.13 GCC 完整数据流图](#213-gcc-完整数据流图)
- [2.14 GCC 线程模型](#214-gcc-线程模型)

#### 第 3 章：接收侧拥塞控制与反馈
- [3.1 接收侧 CC 入口](#31-接收侧-cc-入口)
- [3.2 双路径分发](#32-双路径分发)
- [3.3 接收侧 BWE Kalman 滤波](#33-接收侧-bwe-kalman-滤波)
- [3.4 TWCC 反馈 RemoteEstimatorProxy](#34-twcc-反馈-remoteestimatorproxy)
- [3.5 发送侧 TWCC 消费](#35-发送侧-twcc-消费)
- [3.6 反馈解复用与控制门控](#36-反馈解复用与控制门控)
- [3.7 AbsSendTime vs TWCC](#37-abssendtime-vs-twcc)
- [3.8 完整反馈环数据流图](#38-完整反馈环数据流图)
- [3.9 线程模型](#39-线程模型)

#### 第 4 章：Pacing 与码率分配
- [4.1 Pacing 入口与接口](#41-pacing-入口与接口)
- [4.2 两种 Pacer 实现](#42-两种-pacer-实现)
- [4.3 PacingController 核心算法](#43-pacingcontroller-核心算法)
- [4.4 RoundRobinPacketQueue](#44-roundrobinpacketqueue)
- [4.5 BitrateProber](#45-bitrateprober)
- [4.6 PacketRouter](#46-packetrouter)
- [4.7 BitrateAllocator 分配算法](#47-bitrateallocator-分配算法)
- [4.8 RtpBitrateConfigurator](#48-rtpbitrateconfigurator)
- [4.9 完整控制闭环](#49-完整控制闭环)
- [4.10 线程模型](#410-线程模型)

#### 第 5 章：丢包恢复 NACK 与 FEC
- [5.1 丢包恢复总览](#51-丢包恢复总览)
- [5.2 NACK 模块](#52-nack-模块)
- [5.3 LossNotificationController](#53-lossnotificationcontroller)
- [5.4 发送侧重传响应](#54-发送侧重传响应)
- [5.5 ULP FEC](#55-ulp-fec)
- [5.6 FlexFEC](#56-flexfec)
- [5.7 FecControllerDefault](#57-feccontrollerdefault)
- [5.8 保护模式](#58-保护模式knack--knackfec--kfec)
- [5.9 NACK 与 FEC 协同策略](#59-nack-与-fec-协同策略)
- [5.10 线程模型](#510-线程模型)

#### 第 6 章：抖动缓冲与时延控制
- [6.1 接收路径总览](#61-接收路径总览)
- [6.2 抖动估计 VCMJitterEstimator](#62-抖动估计-vcmjitterestimator)
- [6.3 FrameBuffer 依赖图](#63-framebuffer-依赖图)
- [6.4 VCMJitterBuffer legacy](#64-vcmjitterbuffer-legacy)
- [6.5 VCMTiming 渲染时间](#65-vcmtiming-渲染时间)
- [6.6 TimestampExtrapolator](#66-timestampextrapolator)
- [6.7 VCMRttFilter](#67-vcmttfilter)
- [6.8 VCMCodecTimer](#68-vmcodectimer)
- [6.9 A/V 同步](#69-av-同步)
- [6.10 抖动反馈闭环](#610-抖动反馈闭环)
- [6.11 线程模型](#611-线程模型)

#### 第 7 章：视频自适应
- [7.1 视频自适应总览](#71-视频自适应总览)
- [7.2 Resource 抽象与 Processor](#72-resource-抽象与-processor)
- [7.3 CPU 过载检测](#73-cpu-过载检测)
- [7.4 质量缩放](#74-质量缩放)
- [7.5 VideoStreamEncoderResourceManager](#75-videostreamencoderresourcemanager)
- [7.6 VideoStreamAdapter](#76-videostreamadapter)
- [7.7 自适应决策管线](#77-自适应决策管线)
- [7.8 EncoderBitrateAdjuster](#78-encoderbitrateadjuster)
- [7.9 EncoderOvershootDetector](#79-encoderovershootdetector)
- [7.10 QualityLimitationReasonTracker](#710-qualitylimitationreasontracker)
- [7.11 三路信号优先级与合并](#711-三路信号优先级与合并)
- [7.12 参数表](#712-参数表)
- [7.13 线程模型](#713-线程模型)

#### 第 8 章：音频网络适配
- [8.1 音频适配总览](#81-音频适配总览)
- [8.2 AudioNetworkAdaptor 与 Controller 管理器](#82-audionetworkadaptor-与-controller-管理器)
- [8.3 各 Controller](#83-各-controller)
- [8.4 ControllerManager 控制器选择](#84-controllermanager控制器选择)
- [8.5 配置 proto 与 debug dump](#85-配置-proto-与-debug-dump)
- [8.6 与 ANA 的集成入口](#86-与-ana-的集成入口)
- [8.7 线程模型](#87-线程模型)
- [8.8 参数表](#88-参数表)

#### 第 9 章：核心数据结构与单位系统
- [9.1 单位类型](#91-单位类型)
- [9.2 控制消息结构](#92-控制消息结构)
- [9.3 BWE 结构](#93-bwe-结构)
- [9.4 Pacing 结构](#94-pacing-结构)
- [9.5 分配结构](#95-分配结构)
- [9.6 抖动结构](#96-抖动结构)
- [9.7 数据结构设计哲学](#97-数据结构设计哲学)

#### 第 10 章：线程架构与并发控制
- [10.1 线程/队列全景](#101-线程队列全景)
- [10.2 controller task queue](#102-controller-task-queue)
- [10.3 pacer task queue](#103-pacer-task-queue)
- [10.4 decode queue](#104-decode-queue)
- [10.5 module process thread](#105-module-process-thread)
- [10.6 network 与 worker thread](#106-network-与-worker-thread)
- [10.7 跨线程同步](#107-跨线程同步)
- [10.8 线程亲和 vs 锁](#108-线程亲和-vs-锁)

#### 第 11 章：内存与控制架构
- [11.1 所有权体系](#111-所有权体系)
- [11.2 反馈控制闭环](#112-反馈控制闭环)
- [11.3 分层控制](#113-分层控制)
- [11.4 控制周期](#114-控制周期)
- [11.5 状态机驱动](#115-状态机驱动)
- [11.6 参数化与 field trial](#116-参数化与-field-trial)

#### 第 12 章：动态网络场景下的算法作用
- [12.1 链路启动与爬坡](#121-链路启动与爬坡)
- [12.2 带宽骤降](#122-带宽骤降)
- [12.3 带宽恢复](#123-带宽恢复)
- [12.4 高丢包](#124-高丢包)
- [12.5 网络抖动增大](#125-网络抖动增大)
- [12.6 CPU 过载](#126-cpu-过载)
- [12.7 网络切换/路由变化](#127-网络切换路由变化)
- [12.8 应用限流 ALR](#128-应用限流-alr)
- [12.9 低码率屏幕共享](#129-低码率屏幕共享)
- [12.10 各场景时序图](#1210-各场景时序图)

#### 第 13 章：设计模式与设计哲学
- [13.1 策略模式](#131-策略模式bwe-算法可替换)
- [13.2 工厂模式](#132-工厂模式networkcontrollerfactoryinterface)
- [13.3 观察者模式](#133-观察者模式targettransferrateobserver--bitrateallocatorobserver)
- [13.4 状态机模式](#134-状态机模式aimd--探测--自适应)
- [13.5 组合模式](#135-组合模式googccnetworkcontroller-组合子组件)
- [13.6 接口隔离](#136-接口隔离networkcontrollerinterface-抽象控制契约)
- [13.7 适配器模式](#137-适配器模式transportfeedbackadapter)
- [13.8 外观模式](#138-外观模式receivesidecongestioncontroller)
- [13.9 反馈控制哲学](#139-反馈控制哲学闭环负反馈稳定性优先)
- [13.10 保守下降激进探测](#1310-保守下降激进探测的设计取向)
- [13.11 参数化与可调性](#1311-参数化与可调性)
- [13.12 分层解耦哲学](#1312-分层解耦哲学)

#### 第 14 章：QoS 设计优缺点与最佳实践
- [14.1 优点](#141-优点)
- [14.2 缺点](#142-缺点)
- [14.3 与其他实现对比](#143-与其他实现对比)
- [14.4 可复用的 QoS 设计模式](#144-可复用的-qos-设计模式)
- [14.5 总结](#145-总结)

---

## 第 0 章：导读与全景

### 0.1 什么是 QoS

QoS（Quality of Service，服务质量）在 WebRTC 中指**在变化的网络条件下，维持实时音视频通信质量的一整套机制**。它不是单一模块，而是一个横跨发送侧、接收侧、反馈通道的闭环控制系统。

WebRTC 的 QoS 要解决的核心矛盾是：**实时性要求低延迟，而网络是有限、波动、会丢包的**。如果只管尽量发送，网络拥塞时延迟暴涨、丢包堆积，通话就卡死；如果只管保守发送，带宽利用不足，画质低。QoS 的任务就是在两者间动态寻优。

WebRTC QoS 涵盖以下子系统（对应代码位置）：

| 子系统 | 代码位置 | 核心职责 |
|---|---|---|
| 拥塞控制 GCC | `modules/congestion_controller/goog_cc/` | 估计可用带宽，产出目标码率 |
| 接收侧 CC + TWCC | `modules/congestion_controller/`、`modules/remote_bitrate_estimator/` | 接收侧 BWE、反馈生成 |
| Pacing | `modules/pacing/` | 平滑发送，避免突发 |
| 码率分配 | `call/bitrate_allocator.*` | 多流间分配目标码率 |
| 丢包恢复 NACK | `modules/video_coding/nack_module.*` | 检测丢包，请求重传 |
| 丢包恢复 FEC | `modules/rtp_rtcp/source/*fec*` | 前向纠错，无需重传 |
| 抖动缓冲 | `modules/video_coding/jitter_*`、`frame_buffer2.*` | 消除网络抖动，平滑播放 |
| 时延控制 | `modules/video_coding/timing.*` | 计算渲染时间，A/V 同步 |
| 视频自适应 | `video/adaptation/`、`call/adaptation/` | CPU/质量降级 |
| 音频网络适配 | `modules/audio_coding/audio_network_adaptor/` | 音频参数动态调整 |

### 0.2 QoS 全景图

下图展示 WebRTC QoS 的完整闭环。**发送侧**估计带宽并控制发送，**接收侧**测量网络状态并通过反馈通道告知发送侧，形成闭环。

```
                            ┌──────────────── 发送侧 QoS 闭环 ────────────────┐
                            │                                                  │
   ┌──────────┐   编码帧    │  ┌──────────┐  RTP   ┌─────────┐  按速率   ┌─────┐ │
   │ Encoder  │────────────▶│  │RtpVideo  │───────▶│  Pacer  │─────────▶│Socket│─┼─────▶ 网络
   │ (SetRates)│            │  │ Sender   │       │(漏桶+   │          │     │ │
   └────▲─────┘            │  └────▲─────┘       │ 探测)   │          └─────┘ │
        │ target_bitrate    │       │              └────▲────┘                  │
        │                   │       │ packet           │ pacing_rate            │
   ┌────┴─────┐  分配        │  ┌────┴─────┐          │                         │
   │VideoStream│◀───────────│  │Bitrate   │          │                         │
   │Encoder   │  OnBitrate  │  │Allocator│◀─target─┐│                         │
   │(自适应)  │  Updated    │  └────▲─────┘         ││                         │
   └────▲─────┘            │       │                ││                         │
        │ cwnd_reduce       │       │                ││                         │
   ┌────┴─────┐            │  ┌────┴────────────────┐││                         │
   │Congestion│            │  │ RtpTransportController│││                         │
   │Window    │            │  │ Send                  │││                         │
   │Pushback  │            │  └────▲────────────────┘││                         │
   └────▲─────┘            │       │                  ││                         │
        │                   │       │ NetworkControlUpdate                         │
   ┌────┴───────────────────┴───────┴────────────────┐││                         │
   │           GCC (GoogCcNetworkController)         │││                         │
   │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌─────┐│││                         │
   │  │DelayBased│ │SendSide  │ │Probe     │ │ALR  ││││                         │
   │  │BWE       │ │Bandwidth │ │Controller│ │Det. ││││                         │
   │  │(Trendline│ │Estimation│ │          │ │     ││││                         │
   │  │ +AIMD)   │ │(loss)    │ │          │ │     ││││                         │
   │  └──────────┘ └──────────┘ └──────────┘ └─────┘│││                         │
   └────▲───────────────────────────────────────────┘││                         │
        │ TransportPacketsFeedback (TWCC)             ││                         │
        │ OnSentPacket / OnProcessInterval            ││                         │
        │                                             ││                         │
        │                  ┌──────────────────────────┘│                         │
        │                  │ TWCC RTCP (per-packet acks)│                         │
        │                  ▼                            ▼                         │
   ┌────┴──────────────────┴────────────────────────────────────────────────────┴──▶
   │                                  网络                                          │
   └─────────────────────────────────────────────────────────────────────────────────
        │                                            ▲
        │ RTP (media)                                │ RTCP NACK / RTCP Loss
        ▼                                            │
┌───────────────────── 接收侧 QoS 闭环 ──────────────┴────────────────────────────┐
│                                                                                  │
│  ┌─────────┐  RTP   ┌───────────┐  组帧   ┌───────────┐  解码   ┌────────┐ 渲染  │
│  │ Socket  │───────▶│RtpVideo   │────────▶│FrameBuffer│────────▶│Decoder │──────▶│
│  │         │       │Receiver   │         │(依赖图+   │         │        │       │
│  └─────────┘       │           │         │ jitter)   │         └────────┘       │
│       │           └─────┬─────┘         └─────┬─────┘              │             │
│       │                 │                     │                    │             │
│       │           ┌─────┴─────┐         ┌─────┴─────┐        ┌─────┴────┐        │
│       │           │NackModule │         │VCMTiming  │        │Jitter    │        │
│       │           │(丢包检测) │         │(渲染时间) │        │Estimator │        │
│       │           └─────┬─────┘         │(A/V sync)│        │(Kalman)  │        │
│       │                 │ RTCP NACK     └──────────┘        └──────────┘        │
│       │                 ▼                                                      │
│  ┌────┴──────────────────────┐                                                  │
│  │ReceiveSideCongestionCtrl  │── TWCC RTCP ─────────────────────────────────────▶│
│  │(RemoteEstimatorProxy)    │                                                  │
│  └──────────────────────────┘                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 0.3 三大控制目标

WebRTC QoS 围绕三个相互制约的控制目标展开：

1. **码率控制（Rate Control）**：让发送码率匹配可用带宽。码率过高→拥塞→延迟暴涨；码率过低→画质差。由 GCC + Pacing + BitrateAllocator + Encoder SetRates 协同完成。

2. **丢包恢复（Loss Recovery）**：网络丢包时恢复数据。实时通信对延迟敏感，不能像 TCP 那样靠重传超时驱动，因此采用 **NACK（主动重传请求）+ FEC（前向纠错）** 的组合，在延迟与冗余间权衡。

3. **时延控制（Delay Control）**：消除网络抖动，保证平滑播放与音视频同步。由 JitterBuffer + VCMTiming + A/V Sync 协同完成。时延越大越平滑，但实时性越差。

三者关系：码率控制影响丢包恢复（码率高→拥塞→丢包多），丢包恢复影响时延（重传增加延迟），时延控制影响码率（jitter 估计影响缓冲，间接影响可用带宽判断）。WebRTC 通过**反馈闭环**让它们协同收敛。

### 0.4 文档组织与阅读路径

- **想理解整体**：读第 1 章（总体架构），看全景图。
- **想理解带宽怎么估出来的**：读第 2 章（GCC）、第 3 章（接收侧反馈）。
- **想理解发送怎么被控制**：读第 4 章（Pacing 与码率分配）。
- **想理解丢包怎么办**：读第 5 章（NACK 与 FEC）。
- **想理解接收怎么平滑**：读第 6 章（抖动缓冲与时延）。
- **想理解画质怎么降级**：读第 7 章（视频自适应）。
- **想理解音频怎么适配**：读第 8 章（音频网络适配）。
- **想理解工程实现**：读第 9-11 章（数据结构、线程、内存控制）。
- **想理解具体场景下算法怎么动**：读第 12 章（动态网络场景）。
- **想提炼设计经验**：读第 13-14 章（设计模式与优缺点）。


---

## 第 1 章：QoS 总体架构

### 1.1 QoS 在五层架构中的位置

回顾 WebRTC 的五层架构（详见 `wr-arch-design-analysis.md`）：

```
┌─────────────────────────────────────────────┐
│  PeerConnection 层 (pc/)  —— 信令/协商/控制     │
├─────────────────────────────────────────────┤
│  Call 层 (call/)        —— 媒体流调度中心       │  ◀── QoS 控制中心
├─────────────────────────────────────────────┤
│  Media/Engine 层        —— 编解码桥接           │
├─────────────────────────────────────────────┤
│  Modules 层 (modules/)  —— 核心处理算法         │  ◀── QoS 算法实现
├─────────────────────────────────────────────┤
│  rtc_base 层            —— 基础设施/线程/网络    │
└─────────────────────────────────────────────┘
```

QoS 横跨三层：
- **Call 层**：`RtpTransportControllerSend` 是发送侧 QoS 的组装中心，`Call` 创建 `BitrateAllocator`、`ReceiveSideCongestionController`。
- **Modules 层**：GCC、Pacing、NACK、FEC、JitterBuffer 等算法实现都在此。
- **rtc_base 层**：提供 TaskQueue、RateStatistics、TimestampExtrapolator 等基础设施。

### 1.2 发送侧 QoS 架构

发送侧 QoS 的核心是一条**码率控制闭环**，从网络反馈到编码器码率设置：

```
网络反馈 (TWCC/RTCP)
      │
      ▼
RtpTransportControllerSend  (call/rtp_transport_controller_send.cc)
   ├── TransportFeedbackAdapter   将 TWCC 反馈转为 TransportPacketsFeedback
   ├── controller_ (GoogCcNetworkController)  产出 NetworkControlUpdate
   ├── control_handler_ (CongestionControlHandler)  门控/紧急停止
   ├── pacer_ (TaskQueuePacedSender)  设置 pacing rate / cwnd / 探测簇
   └── observer_ (Call)  接收 TargetTransferRate
          │
          ▼
Call::OnTargetTransferRate  (call/call.cc:1080)
   │
   ▼
BitrateAllocator::OnNetworkEstimateChanged  (call/bitrate_allocator.cc)
   │  AllocateBitrates() 多流分配
   ▼
VideoSendStreamImpl::OnBitrateUpdated  (video/video_send_stream_impl.cc)
   │  rtp_video_sender_->OnBitrateUpdated  扣除 FEC/overhead
   ▼
VideoStreamEncoder::OnBitrateUpdated  (video/video_stream_encoder.cc:1634)
   │  EncoderBitrateAdjuster 防过冲
   ▼
encoder_->SetRates()  实际编码器码率设置
```

关键点：**GCC 只产出"目标码率"，不直接控制编码器**。中间经过 BitrateAllocator（多流分配）、VideoSendStreamImpl（扣除保护开销）、VideoStreamEncoder（防过冲调整），最后才到编码器。这种分层让多流、FEC、编码器特性都能在各自层级处理。

### 1.3 接收侧 QoS 架构

接收侧 QoS 同时承担**测量网络状态**（反馈给发送侧）和**保证平滑播放**两个职责：

```
RTP 包到达 (network thread)
      │
      ├──▶ ReceiveSideCongestionController::OnReceivedPacket
      │       ├── RemoteEstimatorProxy::IncomingPacket  记录到达时间 → TWCC 反馈
      │       └── (无 TWCC 时) RemoteBitrateEstimator  接收侧 BWE → REMB
      │
      ├──▶ RtpVideoStreamReceiver::OnRtpPacket
      │       ├── PacketBuffer  组帧
      │       ├── NackModule  丢包检测 → RTCP NACK
      │       └── FrameBuffer  依赖图 + 抖动估计
      │              │
      │              ▼
      │         VCMTiming  计算渲染时间
      │              │
      │              ▼
      │         Decoder → Render
      │
      └──▶ RtpStreamsSynchronizer  A/V 同步 (周期 1000ms)
```

### 1.4 反馈通道

QoS 闭环依赖四条反馈通道：

| 反馈类型 | 方向 | 携带信息 | 代码位置 | 用途 |
|---|---|---|---|---|
| **TWCC** (Transport-wide CC) | 接收→发送 | 每包到达时间 | `remote_estimator_proxy.cc` + `transport_feedback_adapter.cc` | 发送侧延迟 BWE（主流） |
| **REMB** | 接收→发送 | 接收侧估计的带宽 | `remote_bitrate_estimator_*.cc` | 接收侧 BWE（无 TWCC 时） |
| **RTCP NACK** | 接收→发送 | 丢失包序号 | `nack_module.cc` + `rtcp_receiver/sender.cc` | 请求重传 |
| **RTCP Loss/RR** | 接收→发送 | 累计丢包数 | `rtcp_receiver.cc` → `SendSideBandwidthEstimation` | 丢包 BWE |

TWCC 是现代 WebRTC 的主流反馈（精确到每包），REMB 是旧路径（仅传一个带宽值）。`ReceiveSideCongestionController::OnReceivedPacket` 的分发逻辑决定了走哪条：有 transport sequence number → TWCC 路径；否则 → 接收侧 BWE + REMB。

### 1.5 总体架构图

#### 1.5.1 总览图（QoS 三闭环）

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         发送侧码率控制闭环                                  │
│   反馈 ──▶ GCC ──▶ target_rate ──▶ BitrateAllocator ──▶ Encoder SetRates  │
│                                          └──▶ Pacer (pacing_rate)         │
└──────────────────────────────────────────────────────────────────────────┘
                                    ▲
                          TWCC / REMB / RTCP
                                    │
┌──────────────────────────────────────────────────────────────────────────┐
│                         接收侧测量与播放闭环                                │
│   RTP ──▶ PacketBuffer ──▶ FrameBuffer ──▶ Decoder ──▶ Render              │
│           │                │ (jitter估计)     │                              │
│           │                ▼                 │                              │
│           │           VCMTiming ◀── A/V Sync  │                              │
│           │                                  │                              │
│           └──▶ NackModule ──▶ RTCP NACK ──────┘                              │
│           └──▶ RemoteEstimatorProxy ──▶ TWCC ─────────────────────────────▶│
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│                         丢包恢复闭环（横跨两侧）                            │
│   丢包 ──▶ NACK(重传) + FEC(前向纠错)，按保护模式选择                       │
│   发送侧: UlpfecGenerator/FlexfecSender 生成 FEC + RTX 重传               │
│   接收侧: UlpfecReceiverImpl/FlexfecReceiver 恢复 + NackModule 请求       │
└──────────────────────────────────────────────────────────────────────────┘
```

#### 1.5.2 模块关系图（发送侧细致）

```
Call
 │ owns
 ├── BitrateAllocator ──────────────┐
 │                                  │ OnBitrateUpdated
 │ owns                             │
 ├── ReceiveSideCongestionController │
 │   ├── RemoteEstimatorProxy       │
 │   └── WrappingBitrateEstimator   │
 │                                  │
 └── RtpTransportControllerSend      │
       owns                         │
       ├── PacketRouter             │
       ├── Pacer (TaskQueuePaced)   │ ◀── SetPacingRates
       │     └── PacingController   │
       │           └── RoundRobinPacketQueue
       ├── RtpBitrateConfigurator   │
       ├── CongestionControlHandler │ ◀── SetTargetRate (门控)
       └── controller_ (GoogCC)     │ ◀── NetworkControlUpdate
             ├── DelayBasedBwe      │
             ├── SendSideBandwidthEstimation
             ├── ProbeController    │
             ├── AlrDetector        │
             ├── AcknowledgedBitrateEstimator
             └── CongestionWindowPushbackController
                                          │
                              target_rate │
                                          ▼
                              Call::OnTargetTransferRate ──▶ BitrateAllocator
```

#### 1.5.3 关键路径跨层调用链（一次反馈的处理）

```
[网络线程] RTCP TWCC 到达
  └─ RtpTransportControllerSend::OnTransportFeedback (rtp_transport_controller_send.cc:536)
       └─ PostTask ──────────────────────────────────────────┐
[controller task queue]                                      ▼
  └─ transport_feedback_adapter_.ProcessTransportFeedback
       └─ controller_->OnTransportPacketsFeedback (GoogCC)
            ├─ acknowledged_bitrate_estimator_ → 确认码率
            ├─ probe_bitrate_estimator_ → 探测码率
            ├─ delay_based_bwe_ → 延迟 BWE (Trendline + AIMD)
            ├─ bandwidth_estimation_ → 丢包 BWE + 融合
            └─ MaybeTriggerOnNetworkChanged
                 └─ PostUpdates
                      ├─ pacer_->SetPacingRates / SetCongestionWindow / CreateProbeCluster
                      └─ control_handler_->SetTargetRate → UpdateControlState
                           └─ observer_->OnTargetTransferRate (Call)
[网络队列] ────────────────────────────────────────────────────▶
  └─ Call::OnTargetTransferRate (call.cc:1080)
       └─ bitrate_allocator_->OnNetworkEstimateChanged
            └─ AllocateBitrates → 各 VideoSendStreamImpl::OnBitrateUpdated
                 └─ VideoStreamEncoder::OnBitrateUpdated (post 到 encoder queue)
[encoder queue] ──────────────────────────────────────────────▶
  └─ EncoderBitrateAdjuster → encoder_->SetRates
```

### 1.6 控制流 vs 数据流 vs 反馈流

WebRTC QoS 严格分离三类流：

- **数据流（Data Flow）**：媒体包从编码器→Pacer→Socket→网络→接收→解码→渲染。**单向，追求低延迟**。
- **反馈流（Feedback Flow）**：TWCC/REMB/NACK/Loss 从接收侧→发送侧。**反向，周期性**。
- **控制流（Control Flow）**：目标码率从 GCC→BitrateAllocator→Encoder，pacing rate 从 GCC→Pacer。**发送侧内部，事件驱动 + 周期混合**。

三者解耦的关键：数据流不被控制流阻塞（Pacer 用 debt/credit 机制平滑，而非停顿），反馈流不被数据流影响（TWCC 独立 RTCP）。

### 1.7 线程架构总览

QoS 涉及的线程/队列（详见第 10 章）：

| 线程/队列 | 名称 | 运行的 QoS 组件 |
|---|---|---|
| network thread | (socket 收发) | 包收发、RTCP 接收 |
| worker thread | (Call/Stream 管理) | Call、VideoSendStreamImpl |
| controller task queue | `"rtp_send_controller"` | GCC、CongestionControlHandler、TransportFeedbackAdapter |
| pacer task queue | `"TaskQueuePacedSender"` | PacingController、RoundRobinPacketQueue、BitrateProber |
| encoder queue | `"EncoderQueue"` | VideoStreamEncoder、OveruseFrameDetector、QualityScaler |
| resource adaptation queue | `"ResourceAdaptationQueue"` | ResourceAdaptationProcessor、VideoStreamAdapter |
| decode queue | (VideoReceiveStream2) | FrameBuffer 回调、解码 |
| module process thread | (Module 调度) | ReceiveSideCongestionController、RemoteEstimatorProxy |

设计要点：**GCC、Pacer、Adaptation 各自独立 task queue**，避免相互阻塞；跨队列用 PostTask 投递，队列内用 SequenceChecker 保证单线程访问。这是"线程亲和 + 消息传递"模式在 QoS 的体现。

---

## 第 2 章：拥塞控制核心 —— GCC（Google Congestion Control）

GCC 是 WebRTC 拥塞控制的核心算法，运行在发送侧，负责估计可用带宽并产出目标码率。它是整个 QoS 闭环的"大脑"。

### 2.1 GCC 设计哲学

GCC 的核心思想是**三路融合估计**：

1. **延迟路（Delay-based）**：通过观察包的到达延迟梯度，判断网络队列是否在增长。队列增长→拥塞→降码率。这是 GCC 区别于 TCP 的关键——TCP 靠丢包判断拥塞，而低延迟链路丢包前先排队，延迟比丢包更早暴露拥塞。

2. **丢包路（Loss-based）**：通过 RTCP 报告的丢包率，在丢包严重时降码率。作为延迟路的补充与兜底。

3. **探测路（Probe-based）**：主动以高于当前估计的码率发送探测包簇，观察是否被网络"吃下"，从而快速发现可用带宽。这是 GCC 能快速爬坡的关键。

三路独立估计，最终在 `SendSideBandwidthEstimation` 中**取最小值融合**：`target = min(delay_limit, receiver_limit, loss_limit, max_configured)`。保守取向——任一路说"降"就降，三路都说"能升"才升。

### 2.2 入口与控制 API

GCC 实现 `NetworkControllerInterface`（`api/transport/network_control.h:59`），这是一个纯虚接口，每个方法接收一个消息结构体，返回 `NetworkControlUpdate`，且标注 `ABSL_MUST_USE_RESULT`。接口明确声明**非线程安全，必须串行调用**。

12 个回调方法（`network_control.h:64-99`）：

| 方法 | 输入 | 触发时机 |
|---|---|---|
| `OnProcessInterval` | `ProcessInterval` | 每 25ms 周期触发 |
| `OnSentPacket` | `SentPacket` | 每个包发送后 |
| `OnTransportPacketsFeedback` | `TransportPacketsFeedback` | 收到 TWCC 反馈（主数据路径） |
| `OnNetworkAvailability` | `NetworkAvailability` | 网络可用性变化 |
| `OnNetworkRouteChange` | `NetworkRouteChange` | 路由变化（ICE 切换） |
| `OnRemoteBitrateReport` | `RemoteBitrateReport` | 收到 REMB |
| `OnRoundTripTimeUpdate` | `RoundTripTimeUpdate` | RTT 更新 |
| `OnStreamsConfig` | `StreamsConfig` | 流配置变化（pacing_factor 等） |
| `OnTargetRateConstraints` | `TargetRateConstraints` | 码率约束变化（min/max/start） |
| `OnTransportLossReport` | `TransportLossReport` | RTCP 丢包报告 |
| `OnReceivedPacket` | `ReceivedPacket` | 收到包（接收侧 GCC 用） |
| `OnNetworkStateEstimate` | `NetworkStateEstimate` | 网络状态估计（实验性） |

设计要点：**输入输出都是值语义的结构体**，方法无副作用返回（返回值必须使用）。这让控制器像纯函数，便于测试与替换。

### 2.3 工厂与实例化

GCC 通过工厂创建（`api/transport/goog_cc_factory.h`）：

```cpp
class GoogCcNetworkControllerFactory : public NetworkControllerFactoryInterface {
  std::unique_ptr<NetworkControllerInterface> Create(NetworkControllerConfig) override;
  TimeDelta GetProcessInterval() const override;  // 返回 25ms
};
```

`GoogCcNetworkControllerFactory::Create`（`goog_cc_factory.cc:33`）构建 `GoogCcConfig`（含可选的 `NetworkStateEstimator`/`NetworkStatePredictor`），然后 `std::make_unique<GoogCcNetworkController>(config, std::move(goog_cc_config))`。

生产环境由 `RtpTransportControllerSend`（`call/rtp_transport_controller_send.cc:73`）组装：
- `controller_factory_override_`：外部注入的工厂（可空）。
- `controller_factory_fallback_`：默认 `GoogCcNetworkControllerFactory`。
- `process_interval_` = 25ms（来自 `GetProcessInterval()`）。
- `controller_` 实例在 task queue 上延迟创建（`MaybeCreateControllers`）。

`GoogCcFactoryConfig` 支持 `feedback_only` 模式：忽略 REMB/RTT/RTCP loss，仅依赖 TWCC。这是纯反馈模式的精简版。

### 2.4 类图与组件组合

`GoogCcNetworkController`（`goog_cc_network_control.h:47`）是**组合器**，自身不做 BWE 数学，而是编排 8 个子组件：

```
GoogCcNetworkController  (implements NetworkControllerInterface)
 │ owns (std::unique_ptr)
 ├── bandwidth_estimation_      SendSideBandwidthEstimation   丢包BWE+融合
 ├── delay_based_bwe_            DelayBasedBwe                 延迟BWE
 │     ├── video_delay_detector_ TrendlineEstimator            趋势线检测
 │     ├── audio_delay_detector_ TrendlineEstimator            (音频独立)
 │     ├── video_inter_arrival_  InterArrival                  时间戳分组
 │     └── rate_control_         AimdRateControl               AIMD状态机
 ├── probe_controller_           ProbeController               探测调度
 ├── probe_bitrate_estimator_    ProbeBitrateEstimator         探测码率估计
 ├── alr_detector_               AlrDetector                   ALR检测
 ├── acknowledged_bitrate_estimator_  AcknowledgedBitrateEstimator  确认码率
 │     └── (或 RobustThroughputEstimator)
 ├── congestion_window_pushback_controller_  CongestionWindowPushbackController  cwnd回退
 ├── network_estimator_          NetworkStateEstimator         (可选,实验)
 └── network_state_predictor_    NetworkStatePredictor         (可选,ML)
```

类图关系（核心继承与组合）：

```
              NetworkControllerInterface  <<abstract>>
                       ▲
                       │ implements
              GoogCcNetworkController ──────── owns ──────▶ SendSideBandwidthEstimation
                       │                                    ├─ RttBasedBackoff (内嵌)
                       │                                    ├─ LinkCapacityTracker (内嵌)
                       │                                    └─ LossBasedBandwidthEstimation (内嵌)
                       │
                       │ owns
                       ▼
                 DelayBasedBwe ── owns ──▶ TrendlineEstimator (implements DelayIncreaseDetectorInterface)
                       │                ├─ InterArrival
                       │                └─ AimdRateControl ── owns ──▶ LinkCapacityEstimator
                       │
              DelayIncreaseDetectorInterface <<abstract>>
                       ▲
                       │
                TrendlineEstimator
```

设计模式：**组合模式**——`GoogCcNetworkController` 把多个单一职责的子组件组合起来，每个子组件可独立测试与替换。这是 GCC 可演进的关键（如 `RobustThroughputEstimator` 可替换 `AcknowledgedBitrateEstimator`）。

### 2.5 延迟估计 TrendlineEstimator

延迟路的核心是 `TrendlineEstimator`（`trendline_estimator.cc`），它替代了旧的 Kalman 滤波器（接收侧仍用 Kalman，见第 3 章）。算法分四步：

#### 2.5.1 InterArrival 时间戳分组

`InterArrival`（`modules/remote_bitrate_estimator/inter_arrival.cc`）把包按时间戳分组（每 5ms 一组），计算相邻组三个 delta：
- `ts_delta`：发送时间差
- `t_delta`：到达时间差
- `size_delta`：大小差

关键：`d_delta = t_delta - ts_delta` 即"一-way delay 变化"——若网络队列增长，到达比发送慢，`d_delta > 0`。

#### 2.5.2 累积延迟 + 指数平滑 + 滑动窗口最小二乘

`TrendlineEstimator::UpdateTrendline`（`trendline_estimator.cc:194`）：

```
1. accumulated_delay_ += delta_ms           // 累积延迟
2. smoothed_delay_ = 0.9 * smoothed_delay_ + 0.1 * accumulated_delay_   // 指数平滑 (smoothing_coef=0.9)
3. delay_hist_.push_back({arrival_time_ms, smoothed_delay_, accumulated_delay_})
4. if delay_hist_.size() > window_size(20): pop_front
5. 满窗时线性回归求斜率:
   slope = Σ((x_i - x_avg)(y_i - y_avg)) / Σ((x_i - x_avg)²)   // x=arrival_time, y=smoothed_delay
```

斜率 `trend` 反映延迟随时间的变化趋势：`trend > 0` → 延迟在增长 → 拥塞；`trend ≈ 0` → 稳定；`trend < 0` → 队列在排空。

#### 2.5.3 检测状态机（Normal/Overusing/Underusing）

`TrendlineEstimator::Detect`（`trendline_estimator.cc:272`）：

```
modified_trend = min(num_of_deltas, 60) * trend * threshold_gain(4.0)

if modified_trend > threshold_(12.5):
    time_over_using_ += ts_delta
    overuse_counter_++
    if time_over_using_ > 10ms AND overuse_counter_ > 1 AND trend >= prev_trend_:
        hypothesis = kBwOverusing       // 持续过用且趋势加剧 → 过用
elif modified_trend < -threshold_:
    hypothesis = kBwUnderusing          // 队列排空
else:
    hypothesis = kBwNormal
```

三个状态（`api/network_state_predictor.h`）：`kBwNormal`/`kBwUnderusing`/`kBwOverusing`。过用判定有**持续性要求**（`time_over_using_ > 10ms` 且 `overuse_counter_ > 1`），避免单次抖动误判。

#### 2.5.4 自适应阈值

`UpdateThreshold`（`trendline_estimator.cc:313`）——阈值会随信号强度自适应，避免固定阈值在不同网络下失效：

```
if |modified_trend| > threshold_ + 15: 跳过(避免尖峰干扰)
k = |modified_trend| < threshold_ ? k_down_(0.039) : k_up_(0.0087)   // 下降快、上升慢
threshold_ += k * (|modified_trend| - threshold_) * time_delta
threshold_ = clamp(threshold_, 6, 600)
```

`k_down_ > k_up_`：信号低于阈值时阈值快速下降（更敏感），高于阈值时缓慢上升（更保守）。

**Trendline 参数表**：

| 参数 | 默认值 | 含义 | 位置 |
|---|---|---|---|
| `window_size` | 20 包 | 回归窗口 | `trendline_estimator.h:31` |
| `smoothing_coef_` | 0.9 | 指数平滑系数 | `trendline_estimator.cc:32` |
| `threshold_gain_` | 4.0 | 趋势放大增益 | `trendline_estimator.cc:33` |
| `threshold_` (初始) | 12.5 | 过用阈值 | `trendline_estimator.cc:176` |
| `k_up_` | 0.0087 | 阈值上升率 | `trendline_estimator.cc:173` |
| `k_down_` | 0.039 | 阈值下降率 | `trendline_estimator.cc:174` |
| `overusing_time_threshold_` | 10ms | 过用持续时间门槛 | `trendline_estimator.cc:109` |

### 2.6 延迟 BWE 与 AIMD

`DelayBasedBwe`（`delay_based_bwe.cc`）接收 `TrendlineEstimator` 的状态，驱动 `AimdRateControl` 产出延迟码率。

#### 2.6.1 AIMD 状态机

`AimdRateControl`（`modules/remote_bitrate_estimator/aimd_rate_control.cc`）三个状态（`bwe_defines.h:42`）：

```
状态转换 (ChangeState, aimd_rate_control.cc:402):
  kBwNormal  + kRcHold    → kRcIncrease
  kBwNormal  + kRcIncrease → kRcIncrease (保持)
  kBwOverusing + any       → kRcDecrease
  kBwUnderusing + any      → kRcHold
```

#### 2.6.2 增加/减少策略

**增加**（`ChangeBitrate`, `aimd_rate_control.cc:286`）：
- 若已有链路容量估计（接近容量）→ **加性增加**：`rate += avg_packet_size / (rtt + 100ms) * elapsed`，最小 4000 bps/s。
- 若无链路容量估计（远离容量）→ **乘性增加**：`alpha = 1.08^min(elapsed_s, 1.0)`，`rate += max(rate*(alpha-1), 1000)`。
- 上限：`1.5 * estimated_throughput + 10kbps`。

**减少**（`aimd_rate_control.cc:319`）：
- `decreased = estimated_throughput * beta_(0.85)` —— **乘性减少，因子 0.85**。
- 仅当 `decreased < current` 时才减（避免过用反而升码率）。
- 记录 `last_decrease_`，转入 `kRcHold`（排空队列）。

`beta_ = 0.85` 是关键参数（`aimd_rate_control.cc:35`，可通过 `WebRTC-BweBackOffFactor` 调）。比 TCP 的 0.5 温和——实时通信不希望码率大起大落。

`DelayBasedBwe.MaybeUpdateEstimate`（`delay_based_bwe.cc:264`）的决策：
- 过用 + 有确认码率 + `TimeToReduceFurther` → AIMD 减少。
- 过用 + 无确认码率但有估计 + `InitialTimeToReduceFurther` → 估计减半。
- 非过用 + 有探测码率 → 直接设为探测码率（快速采纳探测结果）。
- 非过用 + 无探测 → AIMD 增加/保持。

`Result` 结构（`delay_based_bwe.h:67`）：`{updated, probe, target_bitrate, recovered_from_overuse, backoff_in_alr}`。`recovered_from_overuse` 会触发 `ProbeController::RequestProbe`（过用恢复后主动探测）。

### 2.7 丢包 BWE

丢包 BWE 在 `SendSideBandwidthEstimation`（`send_side_bandwidth_estimation.cc`）中实现，有两套：经典版（默认）和新版 `LossBasedBandwidthEstimation`（field trial `WebRTC-Bwe-LossBasedControl`）。

#### 2.7.1 经典丢包算法

基于三个丢包阈值（`send_side_bandwidth_estimation.cc:42-44`）：

```
low_loss_threshold_  = 0.02   (2%)
high_loss_threshold_ = 0.10   (10%)
bitrate_threshold_   = 0

loss = last_fraction_loss_ / 256.0   // Q8 转浮点

if current < bitrate_threshold_ OR loss <= 2%:
    增加: new = min_bitrate_history.front() * 1.08 + 1000   // 8% 爬坡 + 1kbps
elif loss <= 10%:
    保持 (hold)
else:  // loss > 10%
    减少(每 300ms + rtt 一次):
    new = current * (512 - last_fraction_loss_) / 512
        = current * (1 - 0.5 * loss)   // 按丢包率减半
```

`min_bitrate_history_`（`send_side_bandwidth_estimation.cc:549`）是 1 秒滑动窗口的最小码率，让爬坡基于近期低点，更快恢复。

#### 2.7.2 新版 loss-to-bitrate 函数

`LossBasedBandwidthEstimation`（`loss_based_bandwidth_estimation.cc`）用幂函数建模 loss↔bitrate 关系：

```
LossFromBitrate(bitrate, balance, exponent) = (balance / bitrate)^exponent
BitrateFromLoss(loss, balance, exponent)    = balance * loss^(-1/exponent)

增加: loss_increase_threshold = LossFromBitrate(rate, 0.5kbps, 0.5)
      new = min_bitrate * GetIncreaseFactor(rtt) + 1kbps   // RTT 200-800ms 线性插值 1.02~1.08
      cap = BitrateFromLoss(loss_estimate, 0.5kbps, 0.5)
减少: loss_decrease_threshold = LossFromBitrate(rate, 4kbps, 0.5)
      new = max(0.99 * acked_max, BitrateFromLoss(loss, 4kbps, 0.5))
```

比经典版更精细：增加/减少用不同的 `balance`（0.5/4 kbps），减少更保守（0.99 因子）。

#### 2.7.3 RTT 回退

`RttBasedBackoff`（`send_side_bandwidth_estimation.h:55`）：当 RTT 超过 `rtt_limit_`（3s，疑似缓冲膨胀）时，每秒降 `drop_fraction_`（0.8），下限 `bandwidth_floor_`（5kbps）。field trial `WebRTC-Bwe-MaxRttLimit`。

#### 2.7.4 融合

`GetUpperLimit`（`send_side_bandwidth_estimation.cc:582`）：

```
upper_limit = min(delay_based_limit_, receiver_limit_, max_bitrate_configured_)
if loss_based_bandwidth_estimation_.Enabled() and loss_based_bitrate_ > 0:
    upper_limit = min(upper_limit, loss_based_bitrate_)
```

`current_target_ = min(computed, upper_limit)`，下限 `min_bitrate_configured_`（5kbps）。**取最小值 = 保守**。

### 2.8 探测 BWE

探测是 GCC 快速发现带宽的关键。由 `ProbeController`（调度）+ `ProbeBitrateEstimator`（估计）+ Pacer 的 `BitrateProber`（发送）协同。

#### 2.8.1 探测状态机

`ProbeController`（`probe_controller.cc`）三状态：`kInit` → `kWaitingForProbingResult` → `kProbingComplete`。

**初始指数探测**（`InitiateExponentialProbing`, `probe_controller.cc:248`）：网络可用后，以 `first_exponential_probe_scale`(3x) 和 `second_exponential_probe_scale`(6x) 的 start_bitrate 发探测。

**指数延续**（`SetEstimatedBitrate`, `probe_controller.cc:265`）：若探测结果 `> min_bitrate_to_probe_further`（= 上次探测 × 0.7），以 `further_exponential_probe_scale`(2x) 继续探测。

**ALR 周期探测**（`Process`, `probe_controller.cc:372`）：ALR 时每 `alr_probing_interval`(5s) 以 `alr_probe_scale`(2x) 探测。

**分配探测**（`OnMaxTotalAllocatedBitrate`）：ALR 时以 1x、2x 的分配码率探测。

**跌落探测**（`RequestProbe`, `probe_controller.cc:315`）：码率跌至 `0.66 * estimated` 以下，且在/刚离开 ALR，以 `0.85 * bitrate_before_drop` 探测。

#### 2.8.2 探测码率估计

`ProbeBitrateEstimator`（`probe_bitrate_estimator.cc:62`）对每个探测簇累积反馈：

```
需满足: 收到包数 >= min_probes*0.8 且 收到字节 >= min_bytes*0.8
send_rate    = (size_total - size_last_send)  / (last_send - first_send)
receive_rate = (size_total - size_first_recv) / (last_recv - first_recv)

if receive_rate / send_rate > 2.0: 无效(反馈错误)
if receive_rate < 0.9 * send_rate: 链路饱和, res = 0.95 * receive_rate  // 略退避
else: res = min(send_rate, receive_rate)
```

取 send/receive 的小值，饱和时再退 5%，避免立即过用。

**探测参数表**：

| 参数 | 默认值 | 含义 |
|---|---|---|
| `first_exponential_probe_scale` | 3.0 | 首次探测倍率 |
| `second_exponential_probe_scale` | 6.0 | 二次探测倍率 |
| `further_exponential_probe_scale` | 2.0 | 延续探测倍率 |
| `further_probe_threshold` | 0.7 | 延续探测阈值 |
| `alr_probing_interval` | 5s | ALR 周期探测间隔 |
| `alr_probe_scale` | 2.0 | ALR 探测倍率 |
| `kMinProbePacketsSent` | 5 | 最小探测包数 |
| `kMinProbeDurationMs` | 15ms | 最小探测时长 |
| `kMaxWaitingTimeForProbingResultMs` | 1000ms | 探测超时 |
| `kBitrateDropThreshold` | 0.66 | 跌落探测阈值 |
| `kProbeFractionAfterDrop` | 0.85 | 跌落探测倍率 |

### 2.9 ALR 检测

`AlrDetector`（`alr_detector.cc`）判断发送方是否"应用受限"——即发送量不足以探测链路。用 `IntervalBudget` 跟踪：

```
目标发送率 = estimated_bitrate * bandwidth_usage_ratio(0.65)   // 期望只用 65%
budget_ratio = alr_budget_.budget_ratio()

if budget_ratio > 0.80 and not in ALR: 进入 ALR   // 实际发送远低于期望
if budget_ratio < 0.50 and in ALR:      退出 ALR
```

ALR 的意义：应用限流时无法通过正常流量判断带宽，需靠**周期探测**补充；且 ALR 期间过用回退要谨慎（`alr_limited_backoff_enabled_`）。

**ALR 参数**：`bandwidth_usage_ratio=0.65`，`start_budget_level_ratio=0.80`，`stop_budget_level_ratio=0.50`（`alr_detector.h:34-36`，field trial `WebRTC-AlrDetectorParameters`）。

### 2.10 确认码率

`AcknowledgedBitrateEstimator`（`acknowledged_bitrate_estimator.cc`）估计"已被确认收到"的吞吐量，作为 AIMD 的 `estimated_throughput`。两种实现（工厂 `acknowledged_bitrate_estimator_interface.cc:65` 选择）：

- **`AcknowledgedBitrateEstimator`**（默认）：包装 `BitrateEstimator`，贝叶斯滑动窗口估计（初始窗口 500ms，非初始 150ms）。ALR 退出时 `ExpectFastRateChange()` 快速适应。
- **`RobustThroughputEstimator`**（field trial `WebRTC-Bwe-RobustThroughputEstimatorSettings`）：移除最大到达时间间隔，对延迟尖峰更鲁棒。

### 2.11 拥塞窗口与回退

`CongestionWindowPushbackController`（`congestion_window_pushback_controller.cc`）在 cwnd 填满时直接降编码码率（不走完整 BWE 闭环，快速响应）。

cwnd 计算（`goog_cc_network_control.cc:385`）：

```
time_window = min_feedback_rtt + additional_time
data_window = last_loss_based_target_rate * time_window   // BDP
data_window = max(3000 bytes, (data_window + old) / 2)    // 平滑, 最小 2 MTU
```

回退（`UpdateTargetBitrate`, `congestion_window_pushback_controller.cc:51`）：

```
fill_ratio = (outstanding + pacing_queue) / cwnd
if fill_ratio > 1.5: encoding_ratio *= 0.9    // 激进回退
if fill_ratio > 1.0: encoding_ratio *= 0.95    // 温和回退
if fill_ratio < 0.1: encoding_ratio = 1.0     // 完全恢复
else:               encoding_ratio *= 1.05 (<=1.0)  // 渐进恢复
adjusted = bitrate * encoding_ratio   // 下限 min_pushback_target
```

### 2.12 输出 NetworkControlUpdate

GCC 每次回调返回 `NetworkControlUpdate`（`network_types.h:231`）：

```cpp
struct NetworkControlUpdate {
  absl::optional<DataSize> congestion_window;            // cwnd
  absl::optional<PacerConfig> pacer_config;               // pacing/padding rate
  std::vector<ProbeClusterConfig> probe_cluster_configs;  // 探测簇
  absl::optional<TargetTransferRate> target_rate;          // 目标码率+估计
};
```

`GetPacingRates`（`goog_cc_network_control.cc:693`）：

```
pacing_rate = max(min_total_allocated, last_loss_based_target) * pacing_factor_(2.5)
padding_rate = min(max_padding_rate, last_pushback_target)
```

注意：**pacing 基于丢包路目标（pushback 前）**，避免 pushback 期间 pacer 队列堆积。

`TargetTransferRate`（`network_types.h:219`）含 `target_rate`、`stable_target_rate`（链路容量估计，用于稳定码率分配）、`network_estimate`（RTT/loss/bwe_period）、`cwnd_reduce_ratio`。

### 2.13 GCC 完整数据流图

`OnTransportPacketsFeedback`（`goog_cc_network_control.cc:405`）是主数据路径：

```
TransportPacketsFeedback (TWCC 反馈)
  │
  ├─▶ congestion_window_pushback_controller_->UpdateOutstandingData
  │
  ├─▶ RTT 计算: feedback_rtt = feedback_time - send_time
  │             propagation_rtt = feedback_rtt - (recv - max_recv)
  │             feedback_max_rtts_ 滚动窗口(32) → 用于 cwnd
  │
  ├─▶ (feedback_only) 丢包统计 → bandwidth_estimation_->UpdatePacketsLost
  │
  ├─▶ ALR 边沿检测 → acknowledged_bitrate_estimator_->SetAlrEndedTime
  │                   probe_controller_->SetAlrEndedTimeMs
  │
  ├─▶ acknowledged_bitrate_estimator_->IncomingPacketFeedbackVector
  │     └─▶ bitrate() → bandwidth_estimation_->SetAcknowledgedRate
  │
  ├─▶ probe_bitrate_estimator_->HandleProbeAndEstimateBitrate (每包)
  │     └─▶ FetchAndResetLastEstimatedBitrate → probe_bitrate
  │           (可选: 忽略低于网络估计/吞吐估计的探测)
  │
  ├─▶ delay_based_bwe_->IncomingPacketFeedbackVector
  │     ├─▶ InterArrival::ComputeDeltas (分组)
  │     ├─▶ TrendlineEstimator::Update (趋势线 → Normal/Overusing/Underusing)
  │     ├─▶ AimdRateControl::Update (AIMD → delay_based_bitrate)
  │     └─▶ Result{target_bitrate, probe, recovered_from_overuse}
  │           │
  │           ├─▶ bandwidth_estimation_->UpdateDelayBasedEstimate
  │           └─▶ MaybeTriggerOnNetworkChanged
  │
  ├─▶ (recovered_from_overuse) probe_controller_->RequestProbe
  │
  └─▶ UpdateCongestionWindowSize → cwnd
       │
       ▼
  MaybeTriggerOnNetworkChanged (goog_cc_network_control.cc:614)
  │
  ├─▶ fraction_loss, rtt, loss_based_target = bandwidth_estimation_
  ├─▶ pushback_target = congestion_window_pushback_controller_->UpdateTargetBitrate
  ├─▶ stable_target = bandwidth_estimation_->GetEstimatedLinkCapacity
  ├─▶ alr_detector_->SetEstimatedBitrate(loss_based_target)
  ├─▶ probe_controller_->SetEstimatedBitrate  (可能触发延续探测)
  ├─▶ update->pacer_config = GetPacingRates
  └─▶ update->target_rate = {pushback_target, stable_target, network_estimate}
       │
       ▼
  NetworkControlUpdate → PostUpdates → Pacer/Call
```

### 2.14 GCC 线程模型

GCC 运行在 `RtpTransportControllerSend::task_queue_`（`"rtp_send_controller"`，`rtp_transport_controller_send.cc:117`）。所有 `controller_` 调用通过 `PostTask` 投递到此队列，`RTC_DCHECK_RUN_ON(&task_queue_)` 保证串行。

- **周期处理**：`RepeatingTaskHandle` 每 25ms 调 `OnProcessInterval`（`rtp_transport_controller_send.cc:601`）。
- **pacer 队列监控**：独立 25ms 周期任务读 `pacer()->ExpectedQueueTime()` 喂给 pushback controller。
- **串行保证**：`DelayBasedBwe` 额外有 `rtc::RaceChecker network_race_`（`delay_based_bwe.h:116`），即使 task queue 允许并发也保证反馈处理串行。

`NetworkControllerInterface` 契约明确"非线程安全，必须串行调用"——这是把并发控制责任交给调度者（task queue），而非每个方法加锁，减少开销。

---

## 第 3 章 接收侧拥塞控制与反馈

GCC 是发送侧算法，但它依赖接收侧反馈的两类信号：**TWCC**（到达时间反馈）和**接收侧 BWE**（REMB，legacy）。本章分析接收侧如何产生这些反馈，以及发送侧如何消费。

### 3.1 接收侧 CC 入口

`ReceiveSideCongestionController`（`modules/congestion_controller/rtp/include/receive_side_cc.h`）是接收侧 CC 的外观类，组合两个反馈源：

```cpp
class ReceiveSideCongestionController {
  RemoteEstimatorProxy remote_estimator_proxy_;    // TWCC 反馈发送
  WrappingBitrateEstimator remote_bitrate_estimator_;  // 接收侧 BWE (REMB)
  TransportFeedbackDemuxer feedback_demuxer_;       // 反馈解复用
  RtpPacketReceiver* packet_router_;                // 包路由
};
```

入口 `OnRtpReceivedPacket`（`receive_side_cc.cc:46`）：
1. `packet_router_->OnReceivePacket(packet)` — 分配 transport seq（若 TWCC 启用）
2. `remote_estimator_proxy_.IncomingPacket(arrival_time, send_time, ssrc)` — 记录到达时间
3. `remote_bitrate_estimator_.IncomingPacket(arrival_time, payload_size, ssrc)` — 喂给接收侧 BWE

`OnRtcpPacket` / `OnTransportFeedback`：把收到的 TWCC 反馈解复用给订阅者（发送侧 BWE）。

### 3.2 双路径分发

接收侧对每个 RTP 包做**双路分发**——同一包同时喂给 TWCC 路径和接收侧 BWE 路径。用哪个取决于 SDP 协商的反馈机制：

- **TWCC 启用**（`transport-cc` RTP 扩展）：`RemoteEstimatorProxy` 记录到达时间，周期发 TWCC RTCP。**接收侧 BWE 不再发 REMB**（`WrappingBitrateEstimator` 仍运行但不输出，或被禁用）。GCC 在发送侧用 TWCC 做延迟估计。
- **TWCC 未启用**（legacy）：`WrappingBitrateEstimator` 运行 Kalman BWE，通过 REMB RTCP 把估计发回发送侧。发送侧用 REMB 作为 `receiver_limit_`。

`WrappingBitrateEstimator`（`modules/remote_bitrate_estimator/wrapping_bitrate_estimator.{h,cc}`）是个包装器，按 field trial 选择 `RemoteBitrateEstimatorSingleStream` 或 `RemoteBitrateEstimatorAbsSendTime`。

### 3.3 接收侧 BWE（Kalman 滤波）

接收侧 BWE 是 GCC 的前身，基于 Kalman 滤波估计过用。管线（`remote_bitrate_estimator_abs_send_time.cc`）：

```
RTP 包 (abs-send-time 扩展)
  │
  ├─▶ InterArrival::ComputeDeltas        // 按到达时间戳分组, 算 Δts/Δarrival/Δsize
  │
  ├─▶ OveruseEstimator::Update           // Kalman 滤波估计延迟梯度 slope
  │     状态: [slope, offset], 残差 = Δarrival - slope*Δts - offset
  │     增益 K = P·Hᵀ / (H·P·Hᵀ + σ_noise)
  │     更新: slope += K[0]·residual, offset += K[1]·residual
  │
  ├─▶ OveruseDetector::Detect            // 阈值检测 → Normal/Overusing/Underusing
  │     threshold = 10 + 25·min(slope/|slope|, 1)   // 自适应
  │     if slope > threshold and duration > overuse_time: Overusing
  │
  └─▶ AimdRateControl::Update            // AIMD 调整码率 → REMB
        (与发送侧 AIMD 同构, beta=0.85)
```

#### 3.3.1 OveruseEstimator Kalman 方程

`overuse_estimator.cc` 的 Kalman 模型（一阶）：

```
状态向量 x = [slope, offset]ᵀ          // 延迟斜率 + 偏移
状态转移 F = I (随机游走)
观测 H = [Δts, 1]
预测: x̂ = F·x̂, P = F·P·Fᵀ + Q
残差: y = Δarrival - H·x̂
新息: K = P·Hᵀ / (H·P·Hᵀ + R)
更新: x̂ += K·y, P = (I - K·H)·P
```

测量噪声 `R = 25·var_noise`（`overuse_estimator.cc:40`），`var_noise` 用 EWMA 跟踪残差方差。过程噪声 Q 对 slope/offset 不同（`overuse_estimator.cc:33-35`）。`num_deltas`（样本计数）影响 Q 的衰减。

#### 3.3.2 OveruseDetector 自适应阈值

`overuse_detector.cc` 的阈值随时间自适应（`ModifyThreshold`）：

```
if time_over_using > 10ms and slope > prev_slope:
    threshold = min(threshold + slope * kUp(0.25), max_threshold)
elif slope < -prev_slope:
    threshold = max(threshold + slope * kDown(-0.05), min_threshold)
```

`kUp=0.25`（升得快），`kDown=0.05`（降得慢）——**阈值上升快、下降慢**，避免震荡。

#### 3.3.3 两种实现

- **`RemoteBitrateEstimatorSingleStream`**：按 SSRC 分组，每个流独立估计。legacy。
- **`RemoteBitrateEstimatorAbsSendTime`**：用 abs-send-time 扩展，跨流聚合（`PickEstimator`），更准。默认。

### 3.4 TWCC 反馈：RemoteEstimatorProxy

`RemoteEstimatorProxy`（`modules/remote_bitrate_estimator/remote_estimator_proxy.{h,cc}`）收集到达时间，周期发 TWCC RTCP。

#### 3.4.1 到达时间记录

`IncomingPacket`（`remote_estimator_proxy.cc:69`）把每个包的 `(seq, arrival_time)` 存入 `packet_arrival_history_`（`WindowedPacketArrivalHistory`，窗口 `packet_window_ms`=500ms）。只记录 transport seq 包。

#### 3.4.2 周期反馈

`MaybeSendFeedback`（`remote_estimator_proxy.cc:142`）按 `send_interval` 周期触发：

```
send_interval = max(min_interval, min(max_interval, 5% · bps_window / packet_size))
// 动态: 5% 带宽, 限制 [min=50ms, max=250ms] (默认)
// 高带宽 → 短间隔, 低带宽 → 长间隔
```

`SendFeedback`（`remote_estimator_proxy.cc:155`）构建 TWCC 报文：
1. 取窗口内所有包，按 seq 排序
2. base_seq = 最小 seq, base_time = 最早到达时间（64→32bit 缩放）
3. 构建状态块：`RunLengthChunk`（连续收到/丢失）或 `StatusVectorChunk`（位图）
4. 附加到达时间 delta（250μs 精度，1字节有符号）
5. 发送 `rtcp::TransportFeedback`

#### 3.4.3 TWCC RTCP 报文结构

```
TWCC Feedback RTCP:
  基础 RTCP 头 (PT=205, PT for TWCC=15)
  Sender SSRC, Media Source SSRC
  Base Sequence Number (16bit)
  Packet Status Count (16bit)        // 反馈的包数
  Reference Time (24bit)             // 基准到达时间 (64ms 精度)
  Feedback Packet Count (8bit)       // 反馈包序号(检测丢反馈)
  ── Padding ──
  Packet Status Chunks (变长):
    RunLengthChunk: 0|symbol(2bit)|run(13bit)       // 连续相同状态
    StatusVectorChunk: 1|symbol_size(1bit)|symbols(14bit)  // 位图
  Receive Delta (变长, 每"收到"包一个 1 或 2 字节):
    小 delta: 1字节, ±125μs 精度
    大 delta: 2字节, ±32ms 精度
```

丢失包无 delta（状态标记为 lost）。

### 3.5 发送侧 TWCC 消费：TransportFeedbackAdapter

发送侧用 `TransportFeedbackAdapter`（`modules/congestion_controller/rtp/transport_feedback_adapter.{h,cc}`）把 TWCC RTCP 转成 `TransportPacketsFeedback`（GCC 的输入）。

`ProcessTransportFeedback`（`transport_feedback_adapter.cc:90`）：
1. 对每个反馈的 seq，查 `SendPacketMap` 得到 `PacketResult`（含 send_time、size、transport_seq）
2. 未反馈的包标记为 lost
3. 设置 `receive_time = base_time + sum(deltas)`
4. 输出 `TransportPacketsFeedback{feedback_time, packet_results, ...}`

`SendPacketMap`（`packet_feedback_provider.{h,cc}`）维护已发包历史，TTL `kSendPacketHistoryTimeoutMs`=60s。

### 3.6 反馈解复用：TransportFeedbackDemuxer

`TransportFeedbackDemuxer`（`modules/congestion_controller/rtp/transport_feedback_demuxer.{h,cc}`）把 TWCC 反馈按 SSRC 分发给多个订阅者（多流 BUNDLE 场景）。

`AddOwningSender` 注册发送方，`OnTransportFeedback` 按 feedback 的 sender_ssrc 路由到对应的 `StreamFeedbackProvider`。

### 3.7 CongestionControlHandler

`CongestionControlHandler`（`call/call.cc` 内，或 `rtp_transport_controller_send`）是目标码率的门控层：

- 聚合 GCC 输出的 `TargetTransferRate`、应用层 `max_bitrate`、encoder target
- **紧急停止**：`pacer()->QueueLength() > threshold` 或 `SetPacerRunning(false)` 时，把目标码率降到 0
- 派发 `BitrateAllocationUpdate` 给 `BitrateAllocator`

### 3.8 AbsSendTime vs TWCC 对比与演进

| 维度 | AbsSendTime + REMB | TWCC |
|---|---|---|
| 反馈方向 | 接收→发送（REMB） | 接收→发送（TWCC RTCP） |
| 估计位置 | **接收侧** Kalman | **发送侧** Trendline |
| 粒度 | 每流估计，聚合 | 每包 ack，全精度 |
| 反馈开销 | REMB ~16B/200ms | TWCC ~100B/50-250ms |
| 丢包信息 | 无 | 有（status chunks） |
| 演进 | legacy，逐步弃用 | 默认，RFC 8888 前身 |

TWCC 的优势：发送侧有完整发送时间+大小信息，能做更精确的延迟梯度；接收侧只反馈到达时间，负载轻。GCC（Trendline）取代接收侧 Kalman 是因为趋势线对突发更鲁棒。

### 3.9 完整反馈环数据流图

```
【TWCC 路径 - 默认】
发送侧发包(transport_seq) ──网络──▶ 接收侧
                                      │
                ReceiveSideCongestionController::OnRtpReceivedPacket
                   ├─▶ RemoteEstimatorProxy::IncomingPacket (记录到达)
                   └─▶ (TWCC启用, BWE 不输出)
                                      │
                RemoteEstimatorProxy::MaybeSendFeedback (周期 50-250ms)
                                      │
                TWCC RTCP ◀──网络─────┘
                                      │
发送侧 RTCPReceiver::OnTwccFeedback
  └─▶ TransportFeedbackDemuxer::OnTransportFeedback
        └─▶ TransportFeedbackAdapter::ProcessTransportFeedback
              └─▶ TransportPacketsFeedback
                    └─▶ GoogCcNetworkController::OnTransportPacketsFeedback
                          └─▶ NetworkControlUpdate (target_rate)

【REMB 路径 - legacy】
发送侧发包(abs-send-time) ──网络──▶ 接收侧
                                      │
                ReceiveSideCongestionController::OnRtpReceivedPacket
                   ├─▶ (TWCC未启用)
                   └─▶ WrappingBitrateEstimator::IncomingPacket
                         └─▶ InterArrival→OveruseEstimator→OveruseDetector→AimdRateControl
                               └─▶ REMB 估计
                                      │
                RemoteBitrateEstimator::MaybeSendRtcp (周期 ~200ms)
                                      │
                REMB RTCP ◀──网络──────┘
                                      │
发送侧 RTCPReceiver::OnRemb
  └─▶ SendSideBandwidthEstimation::UpdateReceiverEstimate
        └─▶ receiver_limit_ = remb  (融合取 min)
```

### 3.10 线程模型

- **`ReceiveSideCongestionController`**：运行在 **network/worker 线程**（接收 RTP 的线程）。`OnRtpReceivedPacket` 在包接收路径，高频。`SequenceChecker` 保证单线程。
- **`RemoteEstimatorProxy`**：到达记录在 network 线程；反馈发送通过 `sender_feedback_`（`RtcpRtpFeedback`）投递到 RTCP 发送路径。`send_interval` 周期由 `Module::Process` 或 task 驱动。
- **`WrappingBitrateEstimator`**：network 线程。REMB 发送通过 `RtcpBandwidthObserver`。
- **`TransportFeedbackAdapter`**：发送侧，运行在 **controller task queue**（`rtp_send_controller`），与 GCC 同队列，保证反馈处理串行。
- **`TransportFeedbackDemuxer`**：运行在 controller task queue。

接收侧 CC 的并发模型：**单线程（network 线程）+ Module 周期处理**，无锁。TWCC 反馈发送可能跨线程，通过 `absl::Mutex` 保护 `packet_arrival_history_`。

---

## 第 4 章 Pacing 与码率分配

GCC 输出 `TargetTransferRate` 后，需要两步落地：**Pacing**（控制发送节奏，避免突发）和**码率分配**（多流间分配总码率）。本章分析这两个子系统。

### 4.1 Pacing 入口与接口

Pacing 的抽象接口是 `RtpPacketSender`（`modules/rtp_rtcp/include/rtp_packet_sender.h`）和 `RtpPacketPacer`（`modules/pacing/packet_router.h`）：

```cpp
class RtpPacketSender {
  virtual void EnqueuePackets(std::vector<std::unique_ptr<RtpPacketToSend>> packets) = 0;
  virtual void RemovePackets(uint32_t ssrc, ... ) = 0;
  virtual bool SendPacket(RtpPacketToSend* packet, ...) = 0;
};
```

`PacedSender`（`modules/pacing/paced_sender.h`）实现 `RtpPacketSender` + `Module`（周期处理）+ `RtpPacketPacer`。

### 4.2 两种实现

- **`PacedSender`**（legacy）：继承 `Module`，由 **module process thread** 每 5ms 调 `Process()`。简单但精度受 process thread 调度影响。
- **`TaskQueuePacedSender`**（`modules/pacing/task_queue_paced_sender.{h,cc}`）：用 **独立 TaskQueue**（`"pacer"`），动态调度——发完一批包立即算下次发送时间，PostDelayedTask 精确唤醒。默认实现，精度更高。

两者都包装同一个核心 `PacingController`（`modules/pacing/pacing_controller.{h,cc}`）——算法与调度分离。

### 4.3 PacingController 核心算法：漏桶 + 债务/信用

`PacingController` 用**漏桶**模型控制发送速率，核心是 `media_debt_`（媒体债务）和 `padding_debt_`（填充债务），单位 bytes。

#### 4.3.1 周期模式 vs 动态模式

- **周期模式**（`PacedSender`）：每 5ms 调 `ProcessPackets()`，每次发 `pacing_rate · 5ms` 的量。
- **动态模式**（`TaskQueuePacedSender`）：`ProcessPackets()` 发完一批后，算下次发送时间 `next_send_time = now + debt / pacing_rate`，PostDelayedTask 唤醒。无固定周期，更精确。

#### 4.3.2 发送速率与队列排空加速

`UpdateBudgetWithSentData`（`pacing_controller.cc:325`）：

```
pacing_rate = max(target_rate, min_total_allocated) * pacing_factor_(2.5)
// pacing_factor=2.5: 发送速率是目标码率的 2.5 倍
// 目的: 允许排空队列, 但不超过 2.5x 避免引发拥塞

if ExpectedQueueTimeMs() > kMaxQueueLengthMs(500):
    pacing_rate = min(pacing_rate * queue_time_factor, max_pacing_rate)
// 队列过长时加速排空, 但有上限 max_pacing_rate
```

`media_debt_` 更新（`pacing_controller.cc:302`）：
```
// 时间推进 Δt:
media_debt_ += pacing_rate * Δt          // 信用累积(可发的预算)
media_debt_ -= sent_bytes                 // 发送消耗预算
media_debt_ = max(0, media_debt_ - ...)    // 不允许透支
```

发送条件：`media_debt_ >= packet_size`。债务 < 包大小则等待。

#### 4.3.3 padding 与 keepalive

- **padding**：队列空但有 `padding_debt_` 时，发 padding 包维持码率（`SendPadding`）。padding_rate = min(max_padding_rate, last_pushback_target)。
- **keepalive**：长时间无媒体（`packet_queue_.LastSentPacketTime()` 超过 `kPausedProcessIntervalMs`=500ms）时发 keepalive 包，维持 NAT/连接。

### 4.4 RoundRobinPacketQueue：优先级 + 流间公平

`RoundRobinPacketQueue`（`modules/pacing/round_robin_packet_queue.{h,cc}`）是 PacingController 的包队列，实现**优先级 + 轮转公平**。

#### 4.4.1 优先级分级

```
优先级 (低数字=高优先级):
  kHighPriority = 0    // 音频
  kNormalPriority = 1  // RTX 重传
  kLowPriority = 2     // 视频
  kLowestPriority = 3  // padding
```

`Enqueue`（`round_robin_packet_queue.cc:108`）按优先级入队，高优先级先发。

#### 4.4.2 StreamPrioKey 公平性

队列内同一优先级的多个流按 `StreamPrioKey`（`round_robin_packet_queue.h:90`）排序：

```cpp
struct StreamPrioKey {
  int priority;            // 优先级
  uint64_t size_bytes;      // 该流已入队的累积字节数
  bool operator<(...) { return priority < o.priority || (priority==o.priority && size_bytes < o.size_bytes); }
};
```

**累积字节数小的流优先**——轮转公平：发一个包后该流 `size_bytes` 增大，排到后面，让其他流先发。这保证同优先级流近似按比例共享带宽。

#### 4.4.3 kMaxLeadingSize 公平性上限

`kMaxLeadingSize`（`round_robin_packet_queue.cc:38`）限制领先流的累积优势：当某流累积字节数远超其他流时，即使它优先级高也会被降级，防止"大流饿死小流"。

### 4.5 BitrateProber：探测簇生命周期

`BitrateProber`（`modules/pacing/bitrate_prober.{h,cc}`）管理探测簇，配合 GCC 的 `ProbeController`。

探测簇生命周期：
```
ProbeController 调度 → Pacer::CreateProbeCluster(config)
  │ config = {target_rate, target_duration, min_probes, min_bytes}
  ▼
BitrateProber::CreateProbeCluster → 加入 clusters_ 队列
  │
  ▼ (有媒体包到达)
BitrateProber::OnIncomingPacket(size) → 若 clusters_ 非空且非 probing: 进入 probing
  │
  ▼
PacingController::ProcessPackets → 探测期间忽略 pacing 限制, 按 probe_rate 发包
  │ 每包: BitrateProber::CurrentCluster().pace_time = cluster_size / probe_rate
  │       发够 min_probes 或 min_bytes → 簇结束
  ▼
BitrateProber::ProbingDone → 簇出队
```

探测期间**绕过漏桶**（`pacing_controller.cc:428`），以 `probe_rate` 全速发包，精确测量链路容量。`RecommendedProbeRate` 限制单簇最大速率，避免过激。

### 4.6 PacketRouter：按 SSRC 路由 + transport seq 分配

`PacketRouter`（`modules/pacing/packet_router.{h,cc}`）是 Pacer 与多个 RtpRtcp 模块的中介：

- `SendPacket`：按 SSRC 查 `send_modules_map_` 找到对应 `RtpRtcp`，调 `SendPacket`。
- **transport seq 分配**：`GeneratePadding` / `SendPacket` 时分配全局递增 `transport_sequence_number`（`packet_router.cc:200`），用于 TWCC。
- `OnRembReceived` / `OnTransportFeedback`：把反馈路由回对应流。

### 4.7 BitrateAllocator：多流码率分配

`BitrateAllocator`（`call/bitrate_allocator.{h,cc}`）把 GCC 的总目标码率分配给多个流（音频/视频/simulcast）。核心是 `AllocateBitrates`。

#### 4.7.1 三种分配模式

`DistributeBitrates`（`bitrate_allocator.cc:208`）按总码率与各流需求的关系分三种模式：

```
total_bitrate = 目标总码率
sum_min = Σ min_bitrate(各流)
sum_max = Σ max_bitrate(各流)

if total_bitrate < sum_min:
    【LowRate 模式】 按比例分配, 但都低于 min → 优先级高的流先满足 min
    // 按 min_bitrate 比例缩放, 保证高优先级(音频)尽量够
elif total_bitrate > sum_max:
    【Max 模式】 各流给 max, 剩余按优先级/比例分给允许超配的流
else:
    【Normal 模式】 各流 min + (total - sum_min) 按比例分配
```

#### 4.7.2 优先级码率 + 比例分配 + 滞回

- **优先级**：`MediaStreamAllocationConfig::bitrate_priority`（音频高，视频低）。LowRate 模式下高优先级流优先满足 min。
- **比例分配**：Normal 模式按 `max_bitrate - min_bitrate` 的比例分剩余。
- **滞回**：`BitrateAllocatorObserver::OnBitrateUpdated` 的 `hysteresis`——码率变化小于 `hysteresis` 不下发，避免频繁通知编码器（`bitrate_allocator.cc:400`，`GetAllocation` 的 `hysteresis_left`）。

#### 4.7.3 AddObserver/OnBitrateUpdated 流程

```
BitrateAllocator::AddObserver(observer, config)  // 流注册
  └─▶ 记录到 allocatable_tracks_
  └─▶ RecomputeAllocation: 重算 sum_min/sum_max, 触发再分配

BitrateAllocator::OnNetworkChanged(total_bitrate, ...)  // GCC 输出
  └─▶ DistributeBitrates(total_bitrate)
        └─▶ 各流 observer->OnBitrateUpdated(allocated, stable, ...)
              └─▶ VideoSendStream: 设编码器目标码率
              └─▶ AudioSendStream: 设音频编码器码率
```

### 4.8 RtpBitrateConfigurator：三源码率约束合并

`RtpBitrateConfigurator`（`call/rtp_bitrate_configurator.{h,cc}`）合并三个来源的码率约束：

```
max_bitrate = min(
    config_.max_bitrate_bps,        // SDP/应用配置
    relay_.max_bitrate_bps,          // relay 限制
    rtp_.max_bitrate_bps             // RTP 层限制
)
min_bitrate = max(config_.min_bitrate_bps, ...)
start_bitrate = config_.start_bitrate_bps
```

`GetBitrateConfig` 输出合并后的 `BitrateConstraints`，喂给 GCC 作为 `max_bitrate_configured_`/`min_bitrate_configured_`/`start_bitrate`。

### 4.9 完整控制闭环

```
GCC: NetworkControlUpdate
  ├─▶ target_rate (TargetTransferRate)
  │     └─▶ BitrateAllocator::OnNetworkChanged(target_rate.bps)
  │           └─▶ DistributeBitrates → 各流 OnBitrateUpdated
  │                 ├─▶ VideoSendStream: EncoderBitrateAdjuster → 编码器
  │                 └─▶ AudioSendStream: 音频编码器码率
  │
  ├─▶ pacer_config (PacerConfig)
  │     └─▶ PacedSender::SetPacingRates(pacing_rate, padding_rate)
  │           └─▶ PacingController::UpdateBudget → 漏桶
  │
  └─▶ probe_cluster_configs
        └─▶ PacedSender::CreateProbeCluster → BitrateProber

编码器产出 RTP 包
  └─▶ PacedSender::EnqueuePackets → RoundRobinPacketQueue
        └─▶ PacingController::ProcessPackets (周期5ms/动态)
              ├─▶ BitrateProber 探测? → 全速发
              └─▶ 漏桶: media_debt >= packet_size? → PacketRouter::SendPacket
                    └─▶ RtpRtcp::SendPacket (分配 transport_seq)
                          └─▶ 网络
```

### 4.10 线程模型

- **`TaskQueuePacedSender`**：独立 TaskQueue `"pacer"`。`EnqueuePackets`/`CreateProbeCluster`/`SetPacingRates` 都 PostTask 到此队列，`RTC_DCHECK_RUN_ON(task_queue_)`。`ProcessPackets` 在此队列运行。**单线程，无锁**。
- **`PacedSender`**（legacy）：module process thread（5ms 周期）。`crit_` 保护队列。
- **`BitrateAllocator`**：运行在 **controller task queue**（`rtp_send_controller`），与 GCC 同队列。`AddObserver`/`OnNetworkChanged` 串行。
- **`PacketRouter`**：运行在 pacer task queue。`crit_` 保护 `send_modules_map_`（注册/注销流时）。
- **`RtpBitrateConfigurator`**：controller task queue。

Pacing 的并发模型：**独立 TaskQueue + 串行**。Pacer 是发送路径的关键瓶颈点，独立队列避免被 GCC/编码器阻塞，保证发送节奏精确。

---

## 第 5 章 丢包恢复 —— NACK 与 FEC

丢包恢复是 QoS 的第二大控制目标。WebRTC 用两种机制：**NACK**（负确认重传，适合低 RTT、随机丢包）和 **FEC**（前向纠错，适合高 RTT、突发丢包）。两者可协同。

### 5.1 丢包恢复总览

| 维度 | NACK | FEC |
|---|---|---|
| 机制 | 检测丢失 → 请求重传 | 发冗余包 → 接收端 XOR 恢复 |
| 恢复时延 | ≥ 1 RTT | 0（无需往返） |
| 带宽开销 | 仅丢失时 | 始终（保护因子） |
| 适用 | 低 RTT、随机丢包 | 高 RTT、突发丢包 |
| 实现 | `NackModule`（接收侧）+ RTX（发送侧） | `UlpfecGenerator`/`FlexfecSender`（发送）+ `*Receiver`（接收） |

保护模式由 `FecControllerDefault::SetProtectionMethod` 选择：`kNack` / `kFec` / `kNackFec`（混合）。

### 5.2 NACK 模块：NackModule

`NackModule`（`modules/video_coding/nack_module2.{h,cc}`）在接收侧检测丢包、生成 RTCP NACK、带指数退避和关键帧回退。

#### 5.2.1 丢包检测与 nack list 管理

`OnReceivedPacket`（`nack_module2.cc:113`）是入口，每个收到的 RTP 包都经过它：

```
OnReceivedPacket(seq, is_keyframe, is_recovered):
  if 未初始化: newest_seq = seq, return
  if seq == newest_seq: 重复包, return 0
  if AheadOf(newest_seq, seq):  // 乱序到达(比最新包旧)
      if seq in nack_list_: erase(seq)  // 之前以为丢了, 现在到了
      更新乱序直方图
      return
  if is_recovered:  // FEC/RTX 恢复的包
      recovered_list_.insert(seq)
      return  // 不对恢复包前后的空隙发 NACK
  AddPacketsToNack(newest_seq+1, seq)  // 把空隙加入 nack_list_
  newest_seq = seq
  GetNackBatch(kSeqNumOnly)  // 立即发一批 NACK
```

`AddPacketsToNack`（`nack_module2.cc:257`）：
1. 清除比 `seq_end - kMaxPacketAge(10000)` 更老的条目
2. 若 `nack_list_.size() + 新增 > kMaxNackPackets(1000)`：尝试 `RemovePacketsUntilKeyFrame`，仍超限则 `clear()` + 请求关键帧
3. 对 `[start, end)` 每个 seq：跳过 `recovered_list_` 中的，创建 `NackInfo{seq, send_at_seq = seq + WaitNumberOfPackets(0.5), now}`

`WaitNumberOfPackets(0.5)`（`nack_module2.cc:285`）：基于乱序直方图的逆 CDF，返回"以 ≥0.5 概率等到该包"需等待的包数——**乱序容忍**，避免对会迟到的包误发 NACK。

#### 5.2.2 请求策略

`GetNackBatch`（`nack_module2.cc:292`）分两种批次：
- **kSeqNumOnly**（包到达时触发）：首次请求，当 `newest_seq >= send_at_seq_num` 时发
- **kTimeOnly**（`Process()` 周期触发）：重传请求，当 `now - sent_at_time >= resend_delay` 时发

```
resend_delay 计算:
  默认: resend_delay = rtt_ms_   // 一个 RTT 后重请
  指数退避(field trial WebRTC-ExponentialNackBackoff):
    resend_delay = max(rtt_ms, min_retry_interval)
    if retries > 1:
        exponential_backoff = min(rtt, max_rtt) * base^(retries-1)
        resend_delay = max(resend_delay, exponential_backoff)
```

发送时 `retries++`，`sent_at_time = now`。`retries >= kMaxNackRetries(10)` 则移除。

#### 5.2.3 关键帧请求回退

当 `nack_list_` 超 1000 且无法裁剪到关键帧边界时（`nack_module2.cc:266`）：
```
nack_list_.clear()
keyframe_request_sender_->RequestKeyFrame()  // 请求关键帧
```
丢包太严重时放弃重传，直接要关键帧重新同步。

#### 5.2.4 参数表

| 参数 | 值 | 含义 |
|---|---|---|
| `kMaxPacketAge` | 10000 | NACK 条目最大年龄 |
| `kMaxNackPackets` | 1000 | nack_list 最大长度（超则请求关键帧） |
| `kDefaultRttMs` | 100 | 初始 RTT 估计 |
| `kMaxNackRetries` | 10 | 单包最大 NACK 次数 |
| `kProcessFrequency` | 50Hz（20ms） | Process 周期 |
| `kMaxReorderedPackets` | 128 | 乱序直方图最大 |
| `kNumReorderingBuckets` | 10 | 乱序分桶数 |
| `kDefaultSendNackDelayMs` | 0 | 首次 NACK 延迟（可配 0-20ms） |
| 退避 `min_retry_interval` | 5ms | 指数退避最小间隔 |
| 退避 `max_rtt` | 160ms | 退避 RTT 上限 |
| 退避 `base` | 1.25 | 退避基数 |

### 5.3 LossNotificationController

`LossNotificationController`（`modules/video_coding/loss_notification_controller.{h,cc}`）实现 RTCP Loss Notification（RFC 8888 风格），作为 NACK 的补充/优化。它跟踪帧的可解码性，发带 decodability flag 的丢包通知。

`OnReceivedPacket`（`loss_notification_controller.cc:50`）：检测序号空隙 + 帧依赖可解码性。若丢包且当前帧依赖不可解码 → `HandleLoss`。

`HandleLoss`（`loss_notification_controller.cc:159`）：
- 若存在可解码的非丢弃参考帧：发 `SendLossNotification(last_decodable_seq, last_recv_seq, decodability_flag)`，让发送方知道哪些帧可救
- 否则：`RequestKeyFrame()`

decodability_flag = 所有依赖可解码 AND 帧未丢失前部。比纯 NACK 更智能——告诉发送方"这个帧还能救"还是"没救了，给关键帧"。

### 5.4 发送侧重传响应：RTX 路径

接收侧发 RTCP NACK → 发送侧重传的完整路径：

```
接收侧 NackModule::SendNack
  └─▶ RtcpFeedbackBuffer::SendNack (合并 RTCP)
        └─▶ ModuleRtpRtcpImpl::SendNack
              └─▶ RTCPSender::BuildNACK → RTCP NACK 发出
                    │
                    ▼ 网络
发送侧 RTCPReceiver::HandleNack (rtcp_receiver.cc:672)
  └─▶ packet_information.nack_sequence_numbers
        └─▶ TriggerCallbacksFromRtcpPacket
              └─▶ ModuleRtpRtcpImpl::OnReceivedNack (rtp_rtcp_impl.cc:722)
                    └─▶ RTPSender::OnReceivedNack(nacks, rtt) (rtp_sender.cc:364)
                          ├─▶ packet_history_->SetRtt(5 + avg_rtt)
                          └─▶ for each seq: ReSendPacket(seq)
                                └─▶ BuildRtxPacket (rtp_sender.cc:745)
                                      // 新 RTX SSRC, 新 seq, 原 payload 前缀原 seq(2字节)
                                      // packet_type = kRetransmission
                                      └─▶ paced_sender_->EnqueuePackets
```

`BuildRtxPacket`（`rtp_sender.cc:745`）：创建新包，用 RTX SSRC、新序号、RTX payload type，复制原头部/扩展，**在 payload 前插入原始 2 字节序号**（`kRtxHeaderSize`），接收端据此还原原序号。

`RtpPacketHistory`（`rtp_packet_history.{h,cc}`）保存已发包用于重传，TTL 由 RTT 决定。`SetRtt(5 + avg_rtt)` 调整保留时间。

### 5.5 ULP FEC：XOR 保护 + 掩码表

ULPFEC（RFC 5109）+ RED（RFC 2198）封装。核心是 `ForwardErrorCorrection`（`modules/rtp_rtcp/source/forward_error_correction.{h,cc}`）的 XOR 编解码。

#### 5.5.1 编码

`EncodeFec`（`forward_error_correction.cc:107`）：
1. `num_fec_packets = NumFecPackets(num_media, protection_factor)`
   ```
   num_fec = (num_media * protection_factor + 128) >> 8   // round(num_media * fec_rate/255)
   if fec_rate > 0 and num_fec == 0: num_fec = 1           // 至少 1 个
   ```
   protection_factor 255 = 100% 开销（每媒体包一个 FEC 包）
2. `GeneratePacketMasks`：按掩码表选 mask（bursty vs random）
3. `InsertZerosInPacketMasks`：若媒体包序号有间隙，在 mask 插零列（间隙无保护）
4. `GenerateFecPayloads`：每个 FEC 包 = 受保护媒体包的 XOR
   - 首个受保护包：copy 头部 + payload
   - 后续：`XorHeaders` + `XorPayloads`
5. `FinalizeFecHeaders`：写 SSRC、base seq、mask、L bit

#### 5.5.2 掩码表：bursty vs random

两套预计算表（`fec_private_tables_{bursty,random}.h`）：

- **`kPacketMaskBurstyTbl`**：防突发连续丢包，最多 **12 媒体包**。性质：≤m 的连续丢包全可恢复。
- **`kPacketMaskRandomTbl`**：防随机丢包，最多 **48 媒体包**。

`PickTable`（`forward_error_correction_internal.cc:218`）：
```
if fec_mask_type == kFecMaskBursty and num_media <= 12:
    return bursty table
return random table   // >12 包或默认用 random
```

默认 `kFecMaskRandom`（`fec_controller_default.cc:140`）。>12 包时用运行时生成的交织 mask。

#### 5.5.3 RED 封装

`GetFecPackets`（`ulpfec_generator.cc:202`）：FEC 包封装在 RED 里——1 字节 RED 头（F=0, PT=ulpfec_PT）+ FEC payload。RTP 头从 `last_media_packet_` 复制。

#### 5.5.4 接收端恢复

`DecodeFec` → `AttemptRecovery`（`forward_error_correction.cc:742`）：
```
for each FEC packet:
    missing = NumCoveredPacketsMissing(fec_packet)
    if missing == 1:    // 恰好缺 1 个, 可恢复
        RecoverPacket: recovered = FEC XOR (所有已收的受保护包)
        加入 recovered_packets_, 重扫(恢复可能解锁更多)
    elif missing == 0:  // 全收到, FEC 包无用
        丢弃
    else:               // 缺 >1, 暂无法恢复
        留待后续包
```

`RecoverPacket`（`forward_error_correction.cc:645`）：用 FEC 头初始化恢复包，XOR 所有已收受保护包，恢复 length/seq/SSRC。

### 5.6 FlexFEC

FlexFEC（RFC 8627）是 ULPFEC 的演进，由 `FlexfecSender`（发送）+ `FlexfecReceiver`（接收）实现。核心 XOR 逻辑共享 `ForwardErrorCorrection`。

与 ULPFEC 的区别：

| 维度 | ULPFEC | FlexFEC |
|---|---|---|
| 封装 | RED 封装 | 独立 SSRC 的 RTP 包 |
| 头部 | L bit 定 mask 长度{2,6}字节 | K-bit 定{2,6,14}字节，最多 112 媒体包 |
| 多流 | 单流 | 设计支持多流（当前实现单流） |
| 接收 | 返回所有媒体+恢复 | **只返回恢复包**（媒体路径解耦） |
| 解复用 | RED PT | 按 SSRC 区分 FEC/媒体 |

`FlexfecSender`（`flexfec_sender.{h,cc}`）内部用 `UlpfecGenerator` + `ForwardErrorCorrection::CreateFlexfec`。`GetFecPackets` 写 FlexFEC RTP 头（20-32 字节，K-bit 分隔的 mask）。

`FlexfecReceiver::OnRtpPacket`（`flexfec_receiver.cc:100`）：按 SSRC 解复用媒体/FEC，喂 `DecodeFec`，恢复包通过 `RecoveredPacketReceiver` 回调。

FlexFEC 头结构（`flexfec_header_reader_writer.h:21`）：
```
0                   1                   2                   3
0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|R|F|P|X|  CC |M| PT recovery |    length recovery             |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                       TS recovery                             |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
| SSRCCount |                   reserved                        |
+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
|                            SSRC_i                             |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|   SN base_i  |k|          Mask [0-14]                         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```
K-bit（mask 字节 0/2/6 的 bit 128）指示 mask 长度：2/6/14 字节，覆盖 16/48/112 媒体包。

### 5.7 FecControllerDefault：FEC 开销决策

`FecControllerDefault`（`modules/video_coding/fec_controller_default.{h,cc}`）根据网络条件算 FEC 保护因子。核心 `UpdateFecRates`（`fec_controller_default.cc:82`）：

```
UpdateFecRates(target_bitrate, framerate, rtt, loss):
  1. loss_prot_logic_.UpdateBitRate/Rtt/FrameRate
  2. FilteredLoss: 10s 最大窗口滤波丢包率
  3. if 保护类型 == kNone: return target_bitrate (无保护)
  4. UpdateMethod → VCMProtectionMethod::UpdateParameters
     → RequiredProtectionFactorK()/D()  // 关键帧/增量帧 FEC 因子
  5. max_fec_frames = MaxFramesFec()
  6. ProtectionRequest → fec_generator->SetProtectionParameters(delta, key)
  7. protection_overhead = (nack_rate + fec_rate) / total_rate, cap 0.5
  8. return target_bitrate * (1 - protection_overhead)  // 扣除开销后的编码码率
```

#### 5.7.1 FEC 码率表查找

`VCMFecMethod::ProtectionFactor`（`media_opt_util.cc:286`）用 6450 字节静态表 `kFecRateTable`：

```
spatialSizeToRef = (W*H) / (704*576)          // 相对 4CIF 的分辨率因子
resolnFac = 1 / pow(spatialSizeToRef, 0.3)   // 分辨率越高, FEC 需求越低
bitRatePerFrame = BitsPerFrame(...)           // 考虑时域层
effRateFecTable = resolnFac * bitRatePerFrame
rateIndex = clamp((effRateFecTable - 5)/5, 0, 49)
lossIndex = clamp(loss, 0, 128)
codeRateDelta = kFecRateTable[rateIndex * 129 + lossIndex]   // 查表
// 关键帧加 boost: codeRateKey = max(scaleProtKey*codeRateDelta, ...)
// 转换到源码率域: ConvertFECRate(r) = 255*r/(255-r)
```

#### 5.7.2 MaxFramesFec

`VCMNackFecMethod::ComputeMaxFramesFec`（`media_opt_util.cc:138`）：
```
if numLayers > 2: return 1   // 基础层帧间隔大
else: max_frames = max(2 * base_framerate * rtt/1000 + 0.5, 1), cap 6
// FEC 距离: 平均一个完整帧在一个 RTT 内到达
```

#### 5.7.3 BitRateTooLowForFec

`media_opt_util.cc:169`：码率太低关 FEC：
```
if bytes_per_frame < threshold(400/700/1000 by 分辨率) and numLayers < 3 and rtt < 200ms:
    FEC 关闭 (K/D 因子都置 0)
```

### 5.8 保护模式：kNack / kNackFec / kFec

`SetProtectionMethod`（`fec_controller_default.cc:168`）：
```
if enable_fec and enable_nack: kNackFec
elif enable_nack: kNack
elif enable_fec: kFec
```

### 5.9 NACK 与 FEC 协同策略

混合模式 `kNackFec`（`VCMNackFecMethod::ProtectionFactor`，`media_opt_util.cc:100`）按 RTT 分三档：

| RTT | 策略 | 原因 |
|---|---|---|
| < 20ms (`kLowRttNackMs`) | **NACK only**（FEC delta 因子=0） | NACK 够快，FEC 开销不值 |
| 20ms ~ high_rtt | **混合**：FEC 保护 + NACK 补 FEC 残余 | FEC 防突发，NACK 补漏 |
| ≥ high_rtt | **FEC only** | NACK 太慢，靠 FEC |

设计哲学：**低 RTT 重传，高 RTT 前向纠错**——RTT 决定重传是否来得及。

### 5.10 线程模型

| 组件 | 线程 | 同步 |
|---|---|---|
| `NackModule::OnReceivedPacket` | network/worker（收包） | `crit_` |
| `NackModule::Process` | module process thread（20ms） | `crit_` |
| `LossNotificationController` | worker（单线程） | `sequence_checker_` |
| `UlpfecGenerator::AddPacketAndGenerateFec` | pacer task queue（发包） | `race_checker_` |
| `UlpfecGenerator::SetProtectionParameters` | encoder/congestion 线程 | `crit_` + `pending_params_` 无锁交接 |
| `FlexfecSender` | 与 RTP 发送同线程 | 外部锁（PayloadRouter） |
| `FlexfecReceiver` | network（单线程） | `sequence_checker_` |
| `UlpfecReceiverImpl` | network（收包） | `crit_sect_` |
| `FecControllerDefault` | congestion 线程 + encoder 线程 | `crit_sect_` |
| `RtpVideoSender::OnPacketFeedbackVector` | transport feedback 线程 | `crit_`（loss_mask） |

NACK 的并发：收包线程（`OnReceivedPacket`）与 process 线程（`Process`）并发访问 `nack_list_`，用 `crit_` 保护。`Process` 发 NACK 时临时释放锁避免重入。

FEC 的并发：参数设置（congestion 线程）与 FEC 生成（pacer 线程）跨线程，用 `pending_params_` 无锁交接——设置线程写 pending，生成线程在下次 `AddPacketAndGenerateFec` 时原子读取并交换，避免锁竞争发包路径。

---

## 第 6 章 抖动缓冲与时延控制

前两章解决"码率"和"丢包"，本章解决第三个控制目标——**时延**。接收侧通过抖动估计 + 帧依赖图 + 渲染时间计算，在"延迟 vs 卡顿"间权衡。

### 6.1 接收路径总览

```
网络 RTP 包
  │
  ▼
RtpVideoStreamReceiver::OnRtpPacket  (video/rtp_video_stream_receiver.cc)
  ├─▶ NackModule::OnReceivedPacket          // 丢包检测
  ├─▶ FlexfecReceiver/UlpfecReceiver        // FEC 恢复
  └─▶ PacketBuffer::InsertPacket            // 按序号入包缓冲
        │
        ▼
      PacketBuffer::FindFrames              // 找连续的帧边界(marker bit)
        │
        ▼
      FrameBuffer::InsertFrame              // 按帧依赖入帧缓冲
        ├─▶ 连续性检查(Continuous)
        ├─▶ 可解码性传播(PropagateDecodability)
        └─▶ FrameBuffer::NextFrame          // 等待可解码帧
              │
              ▼
            VideoReceiveStream2::Decode     // 解码队列
              └─▶ Decoder::Decode
                    └─▶ VCMTiming::RenderTimeMs  // 算渲染时间
                          └─▶ VideoRender → 显示
```

### 6.2 抖动估计：VCMJitterEstimator

`VCMJitterEstimator`（`modules/video_coding/jitter_estimator.{h,cc}`）用 **Kalman 滤波**估计网络抖动。模型：帧延迟 = 传输大小变化引起的延迟 + 随机噪声。

#### 6.2.1 模型

```
frameDelay = θ₀ · Δsize + θ₁ + noise
  Δsize = 当前帧大小 - 平均帧大小
  θ₀: 每字节延迟斜率(排队延迟系数)
  θ₁: 固定延迟偏移
  noise: 随机抖动
```

#### 6.2.2 Kalman 更新方程

`UpdateEstimate`（`jitter_estimator.cc:130`）：

```
// 预测
theta_ = theta_ (随机游走, F=I)
// 残差
residual = frameDelay - (theta_[0]*deltaSize + theta_[1])
// 测量噪声 R 随残差自适应
if |residual| < 3*sqrt(varNoise_):  // 非异常
    varNoise_ = alpha*varNoise_ + (1-alpha)*residual²   // EWMA
// 增益
K = theta_cov_ · Hᵀ / (H·theta_cov_·Hᵀ + R)
  H = [deltaSize, 1]
  R = max(maxNoiseQuantile * varNoise_, 1)   // 测量噪声方差
// 更新
theta_ += K · residual
theta_cov_ = (I - K·H) · theta_cov_
```

过程噪声 Q 随帧计数衰减（`jitter_estimator.cc:90`）：早期样本噪声大，Q 大，Kalman 更快适应。

#### 6.2.3 随机抖动估计

`varNoise_`（`jitter_estimator.cc:147`）用 EWMA 跟踪残差方差：
```
varNoise_ = alpha_ * varNoise_ + (1 - alpha_) * residual²
alpha_ = pow(0.01, frameDelay/10000)   // 时间常数, 长间隔衰减慢
```

#### 6.2.4 最终抖动

`GetJitterEstimate`（`jitter_estimator.cc:275`）：
```
jitter = θ₀ · (maxFrameSize - avgFrameSize) + NoiseThreshold
  NoiseThreshold = sqrt(varNoise_) * maxNoiseQuantile(3)
  // 大帧比平均多出的部分乘以延迟斜率 + 噪声阈值
return max(jitter, 0) + nack_retransmit_rtt_term  // 加 NACK 重传项
```

#### 6.2.5 NACK 重传项与 FPS 缩放

- **NACK 重传项**：若启 NACK，抖动加 `rtt/2`（`jitter_estimator.cc:300`），为重传预留时间
- **FPS 缩放**：`jitter = jitter / frameRate`（`jitter_estimator.cc:310`），把每帧抖动转成时间比例

#### 6.2.6 参数表

| 参数 | 值 | 含义 |
|---|---|---|
| `maxNoiseQuantile` | 3.0 | 噪声阈值分位数 |
| `thetaLow` | 0.000001 | θ₀ 下限 |
| `nackLimit` | 3 | NACK 重传项生效次数 |
| `payloadSizeMs` | - | 用于 size→time 转换 |
| `fpsThreshold` | 15 | FPS 缩放阈值 |
| `timeConstant` | 0.01 | varNoise EWMA 时间常数 |

### 6.3 FrameBuffer：依赖图模型

`FrameBuffer`（`modules/video_coding/frame_buffer2.{h,cc}`）是现代帧缓冲，用**依赖图**管理帧的可解码性，支持 SVC（多层）。

#### 6.3.1 帧标识

`VideoLayerFrameId`（`frame_buffer2.h:43`）：`(picture_id, spatial_layer)`，唯一标识一个帧的某层。

#### 6.3.2 FrameInfo 结构

`FrameInfo`（`frame_buffer2.h:52`）：
```cpp
struct FrameInfo {
  VideoLayerFrameId id;
  size_t frame_size;
  std::vector<VideoLayerFrameId> frame_dependencies;  // 依赖的帧
  bool continuous = false;        // 依赖是否都到齐
  bool decodable = false;         // 是否可解码
  int temporal_layer;
  int spatial_layer;
  ...
};
```

#### 6.3.3 连续性与可解码性传播

`InsertFrame`（`frame_buffer2.cc:179`）：
1. 检查帧依赖是否都"continuous"——即其依赖帧都已到齐且 continuous
2. 若 continuous，标记本帧 continuous，**传播**：依赖本帧的其他帧重新检查 continuous
3. 可解码性类似传播：帧的所有依赖 decodable → 本帧 decodable

`NextFrame`（`frame_buffer2.cc:417`）：等待最早的可解码帧，超时则返回当前最佳。

#### 6.3.4 丢帧处理

若帧的依赖永远不到（丢包未恢复），`FrameBuffer` 会跳过该帧，等下一个关键帧或可独立解码的帧。`DropNextDecodable` 处理无法解码的帧。

### 6.4 VCMJitterBuffer（legacy）

`VCMJitterBuffer`（`modules/video_coding/jitter_buffer.{h,cc}`）是旧实现，用**三链表**（`decodable_frames_`、`incomplete_frames_`、`free_frames_`）管理。连续性检查 + NACK 触发。已被 `FrameBuffer` 取代，但代码仍在。

### 6.5 VCMTiming：渲染时间计算

`VCMTiming`（`modules/video_coding/timing.{h,cc}`）计算每帧的渲染时间，在"延迟 vs 卡顿"间权衡。

#### 6.5.1 目标延迟

`TargetVideoDelay`（`timing.cc:131`）：
```
TargetDelay = max(min_playout_delay, jitter_delay + decode_time + render_delay)
  jitter_delay = JitterEstimator 估计
  decode_time = CodecTimer 95 百分位
  render_delay = 10ms (固定)
  min_playout_delay = 应用/A/V 同步设定
```

#### 6.5.2 渲染时间

`RenderTimeMs`（`timing.cc:73`）：
```
RenderTime = extrapolated_local_time + current_delay
  extrapolated_local_time: 由 TimestampExtrapolator 把 RTP 时间戳映射到本地时钟
  current_delay: 速率限制地逼近 TargetDelay
```

#### 6.5.3 速率限制延迟调整

`UpdateCurrentDelay`（`timing.cc:96`）：
```
// current_delay 以 100ms/s 的速率逼近 TargetDelay, 避免突变
diff = TargetDelay - current_delay
if |diff| > 0:
    current_delay += clamp(diff, -max_step, max_step)   // 每帧最多变 max_step
```
**延迟只能缓慢变**——避免抖动估计尖峰导致渲染时间跳变、画面卡顿。

### 6.6 TimestampExtrapolator：RTP→本地时间映射

`TimestampExtrapolator`（`modules/video_coding/timestamp_extrapolator.{h,cc}`）用 **Kalman 滤波**把 RTP 时间戳（90kHz）映射到本地接收时间。

```
状态: [local_time_estimate, drift_rate]
预测: predicted_local = w[0]*rtp_ts + w[1]
残差: residual = actual_arrival - predicted
Kalman 更新 w 和协方差
```

处理 RTP 时间戳回绕（`timestamp_extrapolator.cc:60`）。新流启动时用到达时间直接外推。

### 6.7 VCMRttFilter：RTT 滤波

`VCMRttFilter`（`modules/video_coding/rtt_filter.{h,cc}`）滤波 RTT，检测跳变/漂移：

```
EWMA: rtt = α*rtt + (1-α)*new_rtt
跳变检测: |new_rtt - rtt| > max_rtt * jump_factor → 重置
漂移检测: 累积偏差超阈值 → 重置
```

输出平滑 RTT 给 JitterEstimator（NACK 重传项）和 VCMTiming。

### 6.8 VCMCodecTimer：95 百分位解码时间

`VCMCodecTimer`（`modules/video_coding/codec_timer.{h,cc}`）跟踪解码时间，取 **95 百分位**（非平均）——避免偶发慢解码拉高延迟，但容忍尖峰。

### 6.9 A/V 同步：RtpStreamsSynchronizer + StreamSynchronization

`RtpStreamsSynchronizer`（`video/rtp_streams_synchronizer.{h,cc}`）+ `StreamSynchronization`（`video/stream_synchronization.{h,cc}`）实现音视频同步。

```
音频作为主时钟(基准), 视频对齐音频:
  1. 测量音频/视频的相对延迟
  2. StreamSynchronization::ComputeRelativeDelay
     audio_delay = audio_jitter + audio_decode + playout
     video_delay = video_jitter + video_decode + render
     relative_delay = video_delay - audio_delay
  3. 若 relative_delay > threshold: 调整视频 min_playout_delay
     // 视频慢了→增大视频延迟等音频; 视频快了→减小
  4. 限制调整速率(避免视频卡顿)
```

### 6.10 抖动反馈闭环

```
JitterEstimator 估计 jitter
  └─▶ VCMTiming::SetJitterDelay(jitter)
        └─▶ TargetDelay = jitter + decode + render
              └─▶ current_delay 速率限制逼近 TargetDelay
                    └─▶ RenderTime = extrapolated + current_delay
                          └─▶ 解码后等待到 RenderTime 才渲染
                                └─▶ 实际渲染延迟反馈 → 微调
```

闭环：抖动大 → TargetDelay 大 → current_delay 缓慢增大 → 渲染等待久 → 抗卡顿但延迟高。抖动小则反向。**速率限制**保证平滑。

### 6.11 线程模型

| 组件 | 线程 | 说明 |
|---|---|---|
| `PacketBuffer` | network（收包） | `crit_` 保护 |
| `FrameBuffer::InsertFrame` | network（收包） | `crit_` 保护 frames_ |
| `FrameBuffer::NextFrame` | **decode queue** | 等待可解码帧，`crit_` + `frame_event_` |
| `VCMJitterEstimator` | network + decode | `crit_` |
| `VCMTiming` | decode + worker | `crit_` |
| `TimestampExtrapolator` | network | 无锁(单线程) |
| `RtpStreamsSynchronizer` | worker | 周期任务 |

`FrameBuffer` 的关键并发：**生产者（network 线程 InsertFrame）+ 消费者（decode queue NextFrame）**。用 `crit_` 保护 `frames_`，用 `frame_event_`（ConditionVar）唤醒消费者。`NextFrame` 带超时等待，避免空转。

解码在独立 **decode queue**（`VideoReceiveStream2::decode_queue_`），与收包分离，避免解码阻塞收包。

---

## 第 7 章 视频自适应

前几章解决网络层的码率/丢包/时延。本章解决"编码器跟不上"的问题——当 CPU 过载或码率不足时，主动降级视频质量（分辨率/帧率/层），避免编码器过冲导致雪崩。

### 7.1 视频自适应总览：三路降级

WebRTC 视频自适应有三路独立信号：

| 信号源 | 触发 | 降级动作 | 组件 |
|---|---|---|---|
| **CPU 过载** | 编码时间 > 帧间隔 | 降分辨率/帧率 | `OveruseFrameDetector` |
| **质量(QP)** | 编码 QP 超阈值 | 降分辨率/帧率 | `QualityScaler` |
| **码率** | BWE 不足 | 降码率（编码器内部） | `EncoderBitrateAdjuster` |

三路信号通过 `VideoStreamEncoderResourceManager` 聚合，由 `ResourceAdaptationProcessor` 统一决策。

### 7.2 Resource 抽象与 ResourceAdaptationProcessor

现代自适应用 **Resource 抽象**（`video/adaptation/`）重构：

```cpp
class Resource {  // 抽象资源(CPU/带宽/质量)
  virtual ResourceListener* listener();
  virtual void SetUsageState(ResourceUsageState);  // kOveruse/kUnderuse/kStable
};

class ResourceAdaptationProcessor {  // 处理资源信号
  // 收到 overuse → 调 VideoStreamAdapter 降级
  // 收到 underuse → 升级
};
```

`Resource` 是统一抽象：CPU 是 `CpuOveruseResource`，质量是 `QualityScalerResource`。它们 emit `kOveruse`/`kUnderuse`，Processor 消费。

### 7.3 CPU 过载检测：OveruseFrameDetector

`OveruseFrameDetector`（`video/adaptation/overuse_frame_detector.{h,cc}`）检测编码器是否过载。

#### 7.3.1 模型

```
encode_time_ratio = encode_time / frame_interval   // 编码占帧间隔比例
// 持续跟踪 encode_time_ratio 的均值/方差
```

`OnEncodedFrame`（`overuse_frame_detector.cc:118`）：每编码完一帧记录耗时。

#### 7.3.2 自适应阈值

```
// 滑动窗口统计 encode_time_ratio
mean = EWMA(ratios)
variance = EWMA((ratio - mean)²)
threshold = initial_(1.2)  // 初始过用阈值

if mean > threshold and duration > kOveruseTime(2s):
    emit kOveruse   // 过载
elif mean < threshold * underuse_factor(0.5):
    emit kUnderuse  // 空闲
else:
    kStable
```

阈值自适应：过用后阈值上调（避免震荡），空闲后下调。

#### 7.3.3 参数

| 参数 | 默认 | 含义 |
|---|---|---|
| `kOveruseThreshold` | 1.2 | encode_ratio 过用阈值 |
| `kUnderuseThreshold` | 0.5 | encode_ratio 空闲阈值 |
| `kOveruseTimeThresholdMs` | 2000 | 持续过用时长 |
| `kSampleWindowMs` | 1000 | 采样窗口 |
| `kMaxFrameIntervalMs` | 1500 | 帧间隔上限 |

### 7.4 质量缩放：QualityScaler + QualityThreshold

`QualityScaler`（`modules/video_coding/utility/quality_scaler.{h,cc}`）基于编码器输出的 **QP（量化参数）** 判断质量。

#### 7.4.1 QP 阈值

`QualityThreshold`（`quality_scaler.cc`）双阈值：
```
high_threshold = codec.QpHigh()   // QP 过高 → 降级
low_threshold  = codec.QpLow()    // QP 低 → 升级
```

不同编码器阈值不同（VP8/VP9/H264 各有 `QpHigh`/`QpLow`）。

#### 7.4.2 算法

```
OnEncodedFrame(qp):
  if qp > high_threshold:  high_qps_++
  if qp < low_threshold:   low_qps_++

  // 窗口内统计
  if high_qps_ > kHighQpThreshold(样本数):
      emit kOveruse  // 质量差, 降级
  if low_qps_ > kLowQpThreshold:
      emit kUnderuse  // 质量好, 可升级
```

`QualityScalerResource` 把 QP 过用/空闲转成 Resource 信号。

### 7.5 VideoStreamEncoderResourceManager：资源信号聚合

`VideoStreamEncoderResourceManager`（`video/video_stream_encoder_resource_manager.{h,cc}`）是资源信号的聚合点：

```
注册的资源:
  CpuOveruseResource (CPU)
  QualityScalerResource (QP)
  (可选) BandwidthResource

OnResourceUsageStateMeasured(resource, state):
  └─▶ 转发给 ResourceAdaptationProcessor
```

它还管理**降级计数器**（`adaptation_counters_`：已降几次分辨率/帧率），限制最大降级次数，防止无限降级。

### 7.6 VideoStreamAdapter：VideoSourceRestrictions 计算

`VideoStreamAdapter`（`video/adaptation/video_stream_adapter.{h,cc}`）把"降级"转成具体的 `VideoSourceRestrictions`：

```cpp
struct VideoSourceRestrictions {
  size_t target_pixels_per_frame;    // 目标分辨率
  absl::optional<size_t> max_pixels_per_frame;
  absl::optional<double> max_frame_rate;  // 目标帧率
};
```

`GetAdaptationDown`（`video_stream_adapter.cc`）：按降级策略算下一个 restrictions：
- **降分辨率**：`target_pixels = current * (5/6)`（步长 5/6）
- **降帧率**：`max_frame_rate = current * (2/3)`（步长 2/3）

策略由 `AdaptationStep` 决定，受 `encoder_settings_`（编码器能力）约束。

### 7.7 自适应决策管线

```
Resource(CPU/QP) emit kOveruse
  └─▶ VideoStreamEncoderResourceManager::OnResourceUsageStateMeasured
        └─▶ ResourceAdaptationProcessor::OnResourceUsageStateMeasured
              ├─▶ 检查是否还能降(adaptation_counters_ < max)
              └─▶ VideoStreamAdapter::GetAdaptationDown
                    └─▶ VideoSourceRestrictions{pixels, fps}
                          └─▶ VideoStreamEncoder::SetSourceRestrictions
                                └─▶ VideoSource::AddOrUpdateSink(restrictions)
                                      └─▶ 采集源按 restrictions 降分辨率/帧率
                                            └─▶ 编码器收到更小/更少帧
```

升级（`kUnderuse`）反向：`GetAdaptationUp` 提高 pixels/fps。

### 7.8 EncoderBitrateAdjuster：码率平滑与防过冲

`EncoderBitrateAdjuster`（`video/encoder_bitrate_adjuster.{h,cc}`）平滑编码器目标码率，防过冲：

```
// 编码器实际产出 vs 目标, 动态调整
adjusted_target = target * correction_factor
  correction_factor 基于 实际/目标 比率 EWMA
  if 实际 > 目标: 降 correction_factor (编码器过冲, 压低目标)
  if 实际 < 目标: 升 correction_factor
```

防止编码器因目标码率突变而过冲（产出远超目标，引发拥塞）。

### 7.9 EncoderOvershootDetector：编码器过冲检测

`EncoderOvershootDetector`（`video/encoder_overshoot_detector.{h,cc}`）监控编码器是否持续产出超目标码率：

```
// 滑动窗口统计实际码率 vs 目标
if actual/target > overshoot_rate_threshold(1.2) for sustained period:
    触发降级(通过 Resource)
```

### 7.10 QualityLimitationReasonTracker

`QualityLimitationReasonTracker`（`video/quality_limitation_reason_tracker.{h,cc}`）追踪当前质量限制的原因（CPU/带宽/质量/无），用于统计/调试。

### 7.11 三路信号优先级与合并

三路信号的**优先级与合并**逻辑（`ResourceAdaptationProcessor`）：

```
降级时:
  1. 先降帧率(若 CPU 过载, 降帧率最有效)
  2. 再降分辨率(若 QP 高, 降分辨率提质量)
  3. 受 max_adaptations 限制

升级时(反向):
  1. 先升分辨率
  2. 再升帧率
```

实际策略受 `DegradationPreference`（应用配置）影响：
- `MAINTAIN_FRAMERATE`：只降分辨率
- `MAINTAIN_RESOLUTION`：只降帧率
- `BALANCED`：两者都降（默认）

### 7.12 参数表

| 参数 | 默认 | 含义 |
|---|---|---|
| QP 高阈值 | codec.QpHigh() (VP8=56) | 降级触发 |
| QP 低阈值 | codec.QpLow() (VP8=24) | 升级触发 |
| 分辨率步长 | 5/6 | 每次降 1/6 |
| 帧率步长 | 2/3 | 每次降 1/3 |
| 最大降级次数 | 3-5 | 防无限降级 |
| CPU 过用阈值 | 1.2 | encode_ratio |
| CPU 空闲阈值 | 0.5 | encode_ratio |
| 过冲阈值 | 1.2 | actual/target |

### 7.13 线程模型

| 组件 | 线程 | 说明 |
|---|---|---|
| `OveruseFrameDetector` | encoder thread | 编码回调路径 |
| `QualityScaler` | encoder thread | 编码回调路径 |
| `VideoStreamEncoderResourceManager` | encoder thread + worker | `SequenceChecker` |
| `ResourceAdaptationProcessor` | encoder thread | 单线程 |
| `VideoStreamAdapter` | encoder thread | 单线程 |
| `EncoderBitrateAdjuster` | encoder thread | 单线程 |
| `VideoStreamEncoder` | encoder task queue | `"EncoderQueue"` |

视频自适应主要在 **encoder task queue**（`VideoStreamEncoder::encoder_queue_`）串行，避免编码器状态竞争。资源信号从编码回调产生，在同一队列处理。

---

## 第 8 章 音频网络适配（audio_network_adaptor）

音频相比视频带宽占用小，但仍有适配空间。`audio_network_adaptor`（ANA）根据网络条件动态调整音频编码参数：**码率、帧长、DTX、FEC、通道数**，在"音质 vs 鲁棒性"间权衡。

### 8.1 音频适配总览

| 参数 | 调整方向 | 作用 |
|---|---|---|
| 码率 | 随带宽升降 | 带宽不足降码率保音质 |
| 帧长 | 带宽低→长帧(60ms) | 长帧降低包头开销占比 |
| DTX | 带宽低→开 | 静音时不发包，省带宽 |
| FEC | 丢包高→开 | 前向纠错提升鲁棒性 |
| 通道数 | 带宽高→立体声 | 带宽够升立体声 |

### 8.2 AudioNetworkAdaptor 与 Controller 管理器

`AudioNetworkAdaptor`（`include/audio_network_adaptor.h`）是抽象接口，实现 `AudioNetworkAdaptorImpl`（`audio_network_adaptor_impl.{h,cc}`）：

```cpp
class AudioNetworkAdaptorImpl {
  std::unique_ptr<ControllerManager> controller_manager_;
  // GetEncoderRuntimeConfig: 遍历 controllers, 聚合各 controller 的决策
};
```

类层次：
```
AudioNetworkAdaptor (接口)
  └─ AudioNetworkAdaptorImpl
       └─ ControllerManager (接口)
            └─ ControllerManagerImpl
                 └─ Controller (抽象基类)
                      ├─ BitrateController
                      ├─ FrameLengthController
                      ├─ DtxController
                      ├─ FecControllerPlrBased
                      └─ ChannelController
```

### 8.3 各 Controller

每个 Controller 实现 `MakeDecision(NetworkMetrics, AudioEncoderRuntimeConfig*)`，根据网络指标修改 config。

#### 8.3.1 BitrateController

`bitrate_controller.cc:52`：从目标音频码率扣除开销，算实际编码码率。

```
MakeDecision(config):
  if target_audio_bitrate and overhead_bytes_per_packet:
    frame_length = config.frame_length_ms
    offset = config.last_fl_change_increase ? fl_increase_offset : fl_decrease_offset
    overhead_rate = (overhead + offset) * 8 * 1000 / frame_length
    bitrate = max(0, target_audio_bitrate - overhead_rate)
    config.bitrate_bps = bitrate
```

帧长变化时用不同 offset 补偿开销变化（`WebRTC-SendSideBwe-WithOverhead` 启用）。

#### 8.3.2 FrameLengthController

`frame_length_controller.cc:99`：在 20/40/60/120ms 间切换帧长。

**增长帧长**（`FrameLengthIncreasingDecision`，`frame_length_controller.cc:99`）：
```
// 防过用: 带宽极紧时长帧(降开销)
if uplink_bandwidth <= min_encoder_bitrate(6000) + 5000 + OverheadRate(current_fl):
    switch to longer frame_length; return true
// 带宽+丢包阈值
if uplink_bandwidth <= increase_threshold(fl_changing_bandwidths) and
   packet_loss <= fl_increasing_packet_loss_fraction:
    switch to longer; return true
```

**缩短帧长**（`FrameLengthDecreasingDecision`，`frame_length_controller.cc:155`）：
```
// 防过用: 短帧若仍过用则不降
if uplink_bandwidth <= min_bitrate + 5000 + OverheadRate(shorter_fl):
    return false  // 短帧开销更大, 带宽不够别降
// 带宽够或丢包高则降帧长
if uplink_bandwidth >= decrease_threshold or packet_loss >= fl_decreasing_packet_loss_fraction:
    switch to shorter; return true
```

带宽阈值由 proto 配置（如 `fl_20ms_to_60ms_bandwidth_bps`）。帧长越长包头开销占比越低，但延迟越大。

#### 8.3.3 DtxController

`dtx_controller.cc:35`：基于带宽开关 DTX。

```
MakeDecision(config):
  if uplink_bandwidth:
    if dtx_enabled and bandwidth >= dtx_disabling_bandwidth:
        dtx_enabled = false    // 带宽够, 关 DTX
    elif not dtx_enabled and bandwidth <= dtx_enabling_bandwidth:
        dtx_enabled = true     // 带宽紧, 开 DTX
  config.enable_dtx = dtx_enabled
```

带滞回（enabling < disabling），避免边界震荡。

#### 8.3.4 FecControllerPlrBased

`fec_controller_plr_based.cc:77`：基于丢包率开关 FEC，用**滞回阈值曲线**。

```
ThresholdCurve: 由 (low_bw, high_loss) 和 (high_bw, low_loss) 两点定义的下倾曲线

MakeDecision(config):
  packet_loss = smoother_->GetAverage()   // 指数平滑丢包率
  if fec_enabled:
      fec_enabled = NOT FecDisablingDecision(loss)   // 已开则除非低于关曲线才关
  else:
      fec_enabled = FecEnablingDecision(loss)         // 未开则高于开曲线才开

FecEnablingDecision: NOT enabling_threshold.IsBelowCurve({bw, loss})
FecDisablingDecision: disabling_threshold.IsBelowCurve({bw, loss})
```

两条曲线（enabling 在 disabling 上方）形成滞回区，避免震荡。低带宽高丢包更易开 FEC。

#### 8.3.5 ChannelController

`channel_controller.cc:45`：单声道↔立体声切换。

```
MakeDecision(config):
  if uplink_bandwidth:
    if channels == 2 and bandwidth <= channel_2_to_1_bandwidth:
        channels = 1    // 带宽紧, 降单声道
    elif channels == 1 and bandwidth >= channel_1_to_2_bandwidth:
        channels = min(2, num_encoder_channels)  // 带宽够, 升立体声
  config.num_channels = channels
```

### 8.4 ControllerManager：控制器选择

`ControllerManagerImpl`（`controller_manager.cc:340`）决定 controller 执行顺序，用**评分点距离**动态重排。

#### 8.4.1 评分机制

每个 controller 可配 `ScoringPoint{uplink_bandwidth, uplink_packet_loss}`。`GetSortedControllers`：

```
if 无 scoring_point: return proto 默认顺序
if 距上次重排 < min_reordering_time_ms: return 缓存  // 冷却
if 当前网络点距上次评分点 < min_reordering_squared_distance: return 缓存  // 移动不够

// 按距离排序: 各 controller 的 scoring_point 到当前网络点的平方距离
sorted = stable_sort(controllers, by SquaredDistanceTo(current_point))
更新缓存, last_reordering_time, last_scoring_point
```

`SquaredDistanceTo`（`controller_manager.cc:425`）：
```
norm_bw = bw / 120000          // 归一化 [0,1]
norm_loss = min(loss * 3.333, 1)
dist = (Δnorm_bw)² + (Δnorm_loss)²
```

离当前网络状态近的 controller 先执行——让最相关的 controller 先决策，影响后续。

#### 8.4.2 帧长变化与开销

`FrameLengthController` 决定帧长后，`last_fl_change_increase` 标志传给 `BitrateController`，后者用对应 offset 补偿开销。`kPreventOveruseMarginBps=5000`（`frame_length_controller.cc:22`）是防过用余量。

### 8.5 配置 proto 与 debug dump

配置用 protobuf（`config.proto`）：

```protobuf
message ControllerManager {
  repeated Controller controllers = 1;        // 各 controller 及其参数
  optional int32 min_reordering_time_ms = 2;  // 重排冷却
  optional float min_reordering_squared_distance = 3;  // 重排最小距离
}
message Controller {
  optional ScoringPoint scoring_point = 1;    // 评分点
  oneof controller {
    FecController fec_controller = 21;
    FrameLengthController frame_length_controller = 22;
    ChannelController channel_controller = 23;
    DtxController dtx_controller = 24;
    BitrateController bitrate_controller = 25;
  }
}
// 每个 controller 的参数(阈值、带宽边界等)
```

配置通过 `MediaConstraints::kAudioNetworkAdaptorConfig`（SDP 约束）传入，`AudioEncoderOpus::EnableAudioNetworkAdaptor(config)` 解析。

`DebugDumpWriter`（`debug_dump_writer.{h,cc}`）把 `NETWORK_METRICS`、`ENCODER_RUNTIME_CONFIG`、`CONTROLLER_MANAGER_CONFIG` 事件写文件，用于离线分析。

### 8.6 与 ANA 的集成入口

```
AudioSendStream::Reconfigure (audio_send_stream.cc:636)
  └─▶ encoder->EnableAudioNetworkAdaptor(config, event_log)
        └─▶ AudioEncoderOpus::EnableAudioNetworkAdaptor (audio_encoder_opus.cc:530)
              └─▶ DefaultAudioNetworkAdaptorCreator
                    └─▶ ControllerManagerImpl::Create(config, ...)

网络反馈到达:
  AudioEncoderOpus::OnReceivedUplinkBandwidth/PacketLossFraction/Rtt/Overhead
    └─▶ audio_network_adaptor_->SetNetworkMetrics(...)
          └─▶ ApplyAudioNetworkAdaptor()
                └─▶ GetEncoderRuntimeConfig()  // 遍历 controllers
                      └─▶ 应用: bitrate/frame_length/fec/dtx/channels
```

### 8.7 线程模型

ANA 运行在**编码线程**（`AudioEncoderOpus::EncodeImpl` 的调用线程）：
- `OnReceivedUplinkBandwidth` 等网络回调在编码线程
- `GetEncoderRuntimeConfig` 在编码时调用
- `ControllerManagerImpl::GetSortedControllers` 用 `rtc::TimeMillis`，无显式锁，**单线程假设**

ANA 是单线程的，因为音频编码本身在单线程，参数调整与编码同线程避免竞争。

### 8.8 参数表

| 参数 | 默认 | 含义 |
|---|---|---|
| `kMinBitrateBps` | 6000 | Opus 最低码率 |
| `kMaxBitrateBps` | 510000 | Opus 最高码率 |
| `kDefaultFrameSizeMs` | 20 | 默认帧长 |
| `kANASupportedFrameLengths` | {20,40,60} 或 {20,40,60,120} | 支持的帧长 |
| `kAlphaForPacketLossFractionSmoother` | 0.9999 | 丢包率平滑系数 |
| `kPreventOveruseMarginBps` | 5000 | 防过用余量 |
| `kMaxUplinkBandwidthBps` | 120000 | 评分归一化上限 |
| `kEventLogMinBitrateChangeBps` | 5000 | 事件日志码率变化阈值 |
| `kEventLogMinBitrateChangeFraction` | 0.25 | 事件日志码率变化比例 |
| `kEventLogMinPacketLossChangeFraction` | 0.5 | 事件日志丢包变化比例 |

**Field trials**：
- `WebRTC-SendSideBwe-WithOverhead`：启用开销扣除（BitrateController）
- `WebRTC-Audio-StableTargetAdaptation`：用稳定目标码率
- `WebRTC-AdjustOpusBandwidth`：Opus 带宽自动调整
- `UseTwccPlrForAna`：用 TWCC 丢包率（无平滑）

---

## 第 9 章 核心数据结构与单位系统

WebRTC QoS 用一套强类型单位系统和精心设计的控制消息结构，保证类型安全与接口清晰。

### 9.1 单位类型：api/units

`api/units/`（`data_rate.h`、`data_size.h``time_delta.h`、`timestamp.h`）提供强类型单位，避免"这个 int 是 bps 还是 kbps"的混淆。

```cpp
class DataRate {   // 比特率, bps
  int64_t bps_;
  static constexpr DataRate KilobitsPerSec(int64_t);
  static constexpr DataRate BitsPerSec(int64_t);
  constexpr bool IsFinite() const;
};
class DataSize {   // 数据量, bytes
  int64_t bytes_;
  static constexpr DataSize Bytes(int64_t);
};
class TimeDelta {  // 时间差, us
  int64_t us_;
  static constexpr TimeDelta Millis(int64_t);
  static constexpr TimeDelta Micros(int64_t);
  static constexpr TimeDelta Seconds(int64_t);
};
class Timestamp {  // 时间戳, us
  int64_t us_;
  static constexpr Timestamp PlusInfinity();
  constexpr TimeDelta operator-(Timestamp) const;
};
```

设计哲学：**编译期类型安全 + 零运行时开销**（constexpr + 单一 int64_t 成员）。运算符重载保证 `DataRate = DataSize / TimeDelta` 等关系正确。

### 9.2 控制消息结构

`api/transport/network_types.h` 定义 GCC 的控制契约：

#### 9.2.1 NetworkControlUpdate

```cpp
struct NetworkControlUpdate {           // GCC 输出
  absl::optional<DataSize> congestion_window;
  absl::optional<PacerConfig> pacer_config;
  std::vector<ProbeClusterConfig> probe_cluster_configs;
  absl::optional<TargetTransferRate> target_rate;
};
```

#### 9.2.2 TransportPacketsFeedback

```cpp
struct TransportPacketsFeedback {       // GCC 输入(TWCC 反馈)
  Timestamp feedback_time;
  std::vector<PacketResult> packet_feedbacks;
  Timestamp first_send_time;
  absl::optional<DataSize> prior_in_flight;
  // ...
};
```

#### 9.2.3 SentPacket / PacketResult

```cpp
struct SentPacket {                     // 发送侧记录
  Timestamp send_time;
  DataSize size;
  // ...
};
struct PacketResult {                   // 反馈结果
  SentPacket sent_packet;
  absl::optional<Timestamp> receive_time;
  bool IsReceived() const { return receive_time.has_value(); }
};
```

#### 9.2.4 TargetTransferRate / PacerConfig / ProbeClusterConfig

```cpp
struct TargetTransferRate {            // 目标码率
  Timestamp at_time;
  DataRate target_rate;
  DataRate stable_target_rate;         // 链路容量估计
  NetworkStateEstimate network_estimate;
};
struct PacerConfig {                    // Pacer 配置
  DataRate data_rate;                  // pacing rate
  DataRate padding_rate;
  DataSize data_window;                // cwnd
};
struct ProbeClusterConfig {            // 探测簇
  int id;
  DataRate target_bitrate;
  TimeDelta target_duration;
  int min_probes;
  int min_bytes;
};
```

### 9.3 BWE 结构

```cpp
enum class BandwidthUsage { kNormal, kOverusing, kUnderusing };  // 过用状态

struct RateControlInput {              // AIMD 输入
  BandwidthUsage bw_state;
  absl::optional<DataRate> estimated_throughput;
  Timestamp at_time;
};
```

### 9.4 Pacing 结构

```cpp
struct StreamPrioKey {                 // 优先级键
  int priority;
  uint64_t size_bytes;                 // 累积字节数(公平性)
  bool operator<(const StreamPrioKey&) const;
};

struct ProbeCluster {                  // 探测簇
  int id;
  DataRate target_bitrate;
  Timestamp created_at;
  int min_probes;
  int min_bytes;
  int sent_probes;
  int sent_bytes;
  // ...
};

class IntervalBudget {                 // 区间预算(ALR/探测)
  int64_t target_rate_kbps_;
  int64_t bytes_remaining_;
  bool can_build_up_underuse_;
  void UpdateBudget(int64_t delta_time_ms);
};
```

### 9.5 分配结构

```cpp
struct MediaStreamAllocationConfig {   // 流分配配置
  uint32_t min_bitrate_bps;
  uint32_t max_bitrate_bps;
  uint32_t max_padding_bitrate_bps;
  double bitrate_priority;             // 优先级
  bool enforce_min_bitrate;
  int track_id;
};

struct BitrateAllocationLimits {        // 分配上限
  DataRate min_total_allocated;
  DataRate max_total_allocated;
  DataRate max_padding_rate;
};

struct BitrateAllocationUpdate {       // 分配更新(给流)
  DataRate target_bitrate;
  DataRate stable_target_bitrate;
  DataRate bwe_period;
  uint32_t packet_loss_ratio;
  int64_t rtt_ms;
};
```

### 9.6 抖动结构

```cpp
struct FrameInfo {                     // 帧信息(FrameBuffer)
  VideoLayerFrameId id;
  size_t frame_size;
  std::vector<VideoLayerFrameId> frame_dependencies;
  bool continuous;
  bool decodable;
  int temporal_layer;
  int spatial_layer;
};

struct VideoLayerFrameId {             // 帧标识
  int64_t picture_id;
  int spatial_layer;
  bool operator==(const VideoLayerFrameId&) const;
};

struct TimestampGroup {                // 到达时间组(InterArrival)
  Timestamp first_send_time;
  Timestamp first_arrival_time;
  Timestamp last_send_time;
  Timestamp last_arrival_time;
  DataSize size;
  int64_t first_sequence_number;
};
```

### 9.7 数据结构设计哲学

1. **值语义 + 不可变单位**：`DataRate`/`Timestamp` 等是值类型，拷贝便宜，无共享状态。
2. **`absl::optional` 表"可能无值"**：所有控制消息字段用 optional，明确区分"0"和"未设置"——如 `target_rate = nullopt` 表示不更新，`= 0` 表示降到 0。
3. **单位类型防混淆**：编译期保证 `bps` 不会被当 `bytes` 用，消除单位错误。
4. **POD-like 控制消息**：`NetworkControlUpdate` 等是简单聚合，无继承、无虚函数，序列化/拷贝高效。
5. **接口契约清晰**：`NetworkControllerInterface` 的 12 回调用这些结构作为参数/返回，形成"输入结构 → 算法 → 输出结构"的纯函数式契约。

---

## 第 10 章 线程架构与并发控制

WebRTC QoS 跨多个线程/队列协作。理解线程模型是理解 QoS 并发安全的关键。

### 10.1 QoS 涉及的线程/队列全景

```
┌─────────────────────────────────────────────────────────────────┐
│  signaling thread   (pc/ 信令, SDP 协商, 不参与 QoS 数据面)        │
├─────────────────────────────────────────────────────────────────┤
│  worker thread      (Call/流管理, 资源协调)                        │
│    └─ VideoStreamEncoder, VideoReceiveStream2 管理               │
├─────────────────────────────────────────────────────────────────┤
│  network thread     (RTP/RTCP 收发, ICE)                          │
│    └─ RtpVideoStreamReceiver, RTCPReceiver                       │
├─────────────────────────────────────────────────────────────────┤
│  controller task queue  ("rtp_send_controller")                  │
│    └─ GCC (GoogCcNetworkController), BitrateAllocator            │
│       TransportFeedbackAdapter                                    │
├─────────────────────────────────────────────────────────────────┤
│  pacer task queue      ("pacer")                                  │
│    └─ PacingController, RoundRobinPacketQueue, BitrateProber     │
│       PacketRouter                                                │
├─────────────────────────────────────────────────────────────────┤
│  encoder task queue    ("EncoderQueue")                           │
│    └─ VideoStreamEncoder, OveruseFrameDetector, QualityScaler    │
│       ResourceAdaptationProcessor, EncoderBitrateAdjuster        │
├─────────────────────────────────────────────────────────────────┤
│  decode queue          (VideoReceiveStream2::decode_queue_)      │
│    └─ FrameBuffer::NextFrame, Decoder, VCMTiming                 │
├─────────────────────────────────────────────────────────────────┤
│  module process thread (NackModule::Process, RTCP 周期发送)      │
│    └─ 20ms/5ms 周期                                               │
└─────────────────────────────────────────────────────────────────┘
```

### 10.2 controller task queue（GCC 运行）

`RtpTransportControllerSend::task_queue_`（`"rtp_send_controller"`，`rtp_transport_controller_send.cc:117`）。

- **运行**：`GoogCcNetworkController` 全部逻辑、`BitrateAllocator`、`TransportFeedbackAdapter`
- **驱动**：
  - `RepeatingTaskHandle` 每 25ms 调 `OnProcessInterval`（周期处理）
  - TWCC 反馈到达 → `PostTask(OnTransportPacketsFeedback)`
  - pacer 队列监控独立 25ms 周期
- **保证**：`RTC_DCHECK_RUN_ON(&task_queue_)`，所有 `controller_` 调用串行

设计：**单队列串行**，把并发控制交给调度者，而非每方法加锁。GCC 算法有状态（AIMD、趋势线窗口），串行避免状态竞争。

### 10.3 pacer task queue（PacingController 运行）

`TaskQueuePacedSender::task_queue_`（`"pacer"`）。

- **运行**：`PacingController`、`RoundRobinPacketQueue`、`BitrateProber`
- **驱动**：
  - `EnqueuePackets`/`SetPacingRates` → `PostTask`
  - `ProcessPackets` 动态调度：发完一批算 `next_send_time`，`PostDelayedTask` 唤醒
- **保证**：`RTC_DCHECK_RUN_ON(task_queue_)`

设计：**独立队列**，发送路径不被 GCC/编码器阻塞。Pacer 是发送关键路径，精确节奏要求高，独立队列保证 5ms 级精度。

### 10.4 decode queue（FrameBuffer/解码）

`VideoReceiveStream2::decode_queue_`。

- **运行**：`FrameBuffer::NextFrame`（等待可解码帧）、`Decoder::Decode`、`VCMTiming`
- **驱动**：`PostTask` 投递解码任务
- **并发**：与 network 线程（`FrameBuffer::InsertFrame`）通过 `crit_` + `frame_event_`（ConditionVar）协作

设计：**生产者-消费者**。network 线程生产帧，decode queue 消费。分离避免解码阻塞收包。

### 10.5 module process thread（接收侧 CC / RemoteEstimatorProxy）

`ProcessThread`（`modules/include/module.h`）。

- **运行**：`NackModule::Process`（20ms）、`RemoteEstimatorProxy` 周期反馈、RTCP 周期发送
- **驱动**：`Module::TimeUntilNextProcess` + `Process` 循环
- **legacy**：现代代码逐步用 TaskQueue 取代 ProcessThread，但 NACK 等仍在用

### 10.6 network thread 与 worker thread

- **network thread**：RTP/RTCP 收发。`RtpVideoStreamReceiver::OnRtpPacket`、`RTCPReceiver`、`NackModule::OnReceivedPacket`、`FlexfecReceiver::OnRtpPacket`
- **worker thread**：`Call`/流管理。`VideoStreamEncoder` 生命周期、`RtpStreamsSynchronizer`（A/V 同步）

### 10.7 跨线程同步机制

| 机制 | 用途 | 例子 |
|---|---|---|
| **CriticalSection (`crit_`)** | 粗粒度互斥 | `NackModule::nack_list_`、`FrameBuffer::frames_` |
| **RaceChecker** | 同线程串行(非严格线程亲和) | `UlpfecGenerator` FEC 生成、`DelayBasedBwe` |
| **SequenceChecker** | 单线程断言(调试) | `FlexfecReceiver`、`LossNotificationController` |
| **TaskQueue 投递** | 跨线程无锁通信 | GCC→Pacer `PostTask`、编码器→pacer |
| **`pending_params_` 无锁交接** | 生产者-消费者参数 | `UlpfecGenerator` 参数设置→生成 |
| **ConditionVar (`frame_event_`)** | 等待/唤醒 | `FrameBuffer::NextFrame` 等待可解码帧 |
| **`absl::Mutex`** | 细粒度互斥 | `RemoteEstimatorProxy::packet_arrival_history_` |

### 10.8 线程亲和 vs 锁的取舍

WebRTC 偏好**线程亲和**（thread affinity）而非锁：

- **优点**：无锁竞争，高性能；状态访问天然串行，避免数据竞争
- **实现**：`RTC_DCHECK_RUN_ON(queue_)` 断言某方法必须在某队列运行；跨线程调用必须 `PostTask`
- **代价**：API 使用门槛高（必须知道在哪个队列调用）；调试链路长

**锁的适用场景**：
- legacy 组件（`NackModule` 用 `crit_`，因收包线程与 process 线程并发）
- 简单参数交接（`pending_params_`）
- ConditionVar 等待（`FrameBuffer`）

**演进趋势**：新代码用 TaskQueue + SequenceChecker，老代码用 CriticalSection。GCC/Pacer/Adaptation 等核心 QoS 路径已迁移到 TaskQueue 模型。

---

## 第 11 章 内存与控制架构

本章从**所有权体系**和**控制理论**两个视角分析 QoS 的架构设计。

### 11.1 所有权体系：unique_ptr 子组件组合 / scoped_refptr 共享

WebRTC QoS 用两种所有权模式：

#### 11.1.1 unique_ptr 独占组合

`GoogCcNetworkController`（`goog_cc_network_control.h`）用 `std::unique_ptr` 拥有 8 个子组件：

```cpp
class GoogCcNetworkController {
  const std::unique_ptr<SendSideBandwidthEstimation> bandwidth_estimation_;
  const std::unique_ptr<DelayBasedBwe> delay_based_bwe_;
  const std::unique_ptr<ProbeController> probe_controller_;
  const std::unique_ptr<AlrDetector> alr_detector_;
  const std::unique_ptr<ProbeBitrateEstimator> probe_bitrate_estimator_;
  const std::unique_ptr<AcknowledgedBitrateEstimator> acknowledged_bitrate_estimator_;
  const std::unique_ptr<CongestionWindowPushbackController> congestion_window_pushback_controller_;
  // ...
};
```

**设计**：组合模式，父独占子，生命周期绑定。子组件不可共享，避免多父竞争。析构顺序确定（成员逆序析构）。

#### 11.1.2 scoped_refptr 共享

跨模块共享的对象用 `scoped_refptr`（引用计数）：
- `RtpTransportControllerSend` 被 `Call` 和多个 `VideoSendStream` 共享
- `Pacer` 被多个 `RtpRtcp` 模块共享

`scoped_refptr` 的线程安全：引用计数原子操作，但**对象本身在创建线程销毁**（`scoped_refptr` 设计哲学）。

#### 11.1.3 所有权图

```
Call (拥有)
  ├─ unique_ptr<RtpTransportControllerSend>
  │     ├─ unique_ptr<GoogCcNetworkController> (GCC)
  │     │     ├─ unique_ptr<SendSideBandwidthEstimation>
  │     │     ├─ unique_ptr<DelayBasedBwe>
  │     │     │     ├─ unique_ptr<TrendlineEstimator>
  │     │     │     ├─ unique_ptr<AimdRateControl>
  │     │     │     └─ unique_ptr<InterArrival>
  │     │     ├─ unique_ptr<ProbeController>
  │     │     └─ ... (8 子组件)
  │     ├─ unique_ptr<BitrateAllocator>
  │     └─ scoped_refptr<TaskQueuePacedSender> (Pacer)
  │           └─ unique_ptr<PacingController>
  │                 └─ unique_ptr<RoundRobinPacketQueue>
  ├─ unique_ptr<VideoSendStream> (每流)
  │     └─ unique_ptr<VideoStreamEncoder>
  │           └─ unique_ptr<ResourceAdaptationProcessor>
  └─ unique_ptr<VideoReceiveStream2> (每流)
        └─ unique_ptr<FrameBuffer>
        └─ unique_ptr<NackModule>
```

### 11.2 控制架构：反馈控制闭环

QoS 本质是**反馈控制系统**（闭环控制）。从控制理论视角：

```
          ┌─────────── 反馈通道 (TWCC/REMB/NACK) ──────────┐
          ▼                                                │
  ┌──────────────┐  控制量  ┌──────────────┐  输出  ┌──────────────┐
  │  控制器 GCC  │ ───────▶ │  执行器 Pacer │ ─────▶ │  被控对象 网络 │ ──▶
  │  (AIMD/探测) │           │  + Encoder   │        │  + 接收端      │
  └──────────────┘           └──────────────┘        └──────────────┘
          ▲                                                │
          └──────────── 测量量 (延迟梯度/丢包/吞吐) ◀────────┘
```

#### 11.2.1 闭环特性

- **负反馈**：过用 → 降码率 → 缓解过用；空闲 → 升码率。目标是稳定。
- **闭环增益**：AIMD 的增加/减少因子（1.08/0.85）决定增益。增益过大震荡，过小响应慢。
- **闭环时延**：反馈周期（TWCC 50-250ms + RTT）决定响应速度。时延大 → 稳定性差。
- **稳定性优先**：GCC 保守下降（beta=0.85，降得快）、激进探测（3x/6x，升得谨慎），偏向稳定。

#### 11.2.2 多闭环嵌套

QoS 是**多闭环嵌套**系统：

```
外环 (慢): GCC 码率控制 (周期 25ms + 反馈 100ms)
  └─ 中环: Pacer 队列控制 (周期 5ms)
       └─ 内环 (快): 编码器码率/分辨率 (帧级, 33ms)
            └─ 最内: FEC/NACK (包级, 即时)
```

外环慢、内环快。外环设定目标，内环快速响应局部变化。分层避免快慢耦合震荡。

### 11.3 分层控制：网络层 → 流层 → 媒体层

```
网络层 (Network Layer)
  └─ GCC: 估计链路带宽, 输出 TargetTransferRate
       │ 约束: 链路容量, 丢包, 延迟
       ▼
流层 (Stream Layer)
  └─ BitrateAllocator: 多流分配总码率
       │ 约束: 各流 min/max, 优先级
       ▼
媒体层 (Media Layer)
  ├─ Video: Encoder 码率/分辨率/帧率 (EncoderBitrateAdjuster, Adaptation)
  └─ Audio: ANA 码率/帧长/DTX/FEC/通道
       │ 约束: 编码器能力, CPU, QP
       ▼
  RTP/Pacing 发送
```

每层有自己的控制目标与约束，上层输出是下层输入。层间解耦：GCC 不关心几个流，BitrateAllocator 不关心编码器类型。

### 11.4 控制周期

| 控制器 | 周期 | 目的 |
|---|---|---|
| GCC `OnProcessInterval` | 25ms | 周期触发 BWE 计算 |
| Pacer `ProcessPackets` | 5ms（动态） | 发送节奏控制 |
| TWCC 反馈 | 50-250ms（动态） | 到达时间反馈 |
| NackModule `Process` | 20ms | NACK 重传请求 |
| A/V 同步 | 1000ms | 音视频对齐 |
| Jitter 估计 | 帧级（~33ms） | 抖动更新 |
| 视频自适应 | 帧级 | 资源信号处理 |

周期选择权衡：**短周期响应快但开销大、易震荡；长周期稳定但响应慢**。GCC 25ms 是 BWE 精度与开销的平衡。Pacer 5ms 是发送平滑度与 CPU 的平衡。

### 11.5 状态机驱动的控制

多个 QoS 组件用**状态机**驱动控制：

- **AIMD**（`AimdRateControl`）：Hold → Increase → Decrease，状态决定增/减/保持
- **探测**（`ProbeController`）：kInit → kWaitingForProbingResult → kProbingComplete
- **Trendline 检测**：Normal → Overusing → Underusing
- **FEC 保护模式**：kNack / kFec / kNackFec（按 RTT 切换）

状态机的优势：**行为确定、可分析、防震荡**。状态转换有明确条件，避免控制逻辑混乱。

### 11.6 参数化与 field trial 机制

大量 QoS 参数通过 **field trial**（`field_trial.h`）动态配置，无需重编译：

```cpp
// 例子: 读取 field trial 参数
FieldTrialBasedConfig config;
auto param = config.Lookup("WebRTC-Bwe-LossBasedControl");
// 或用 WebRtcKeyValueConfig 接口
```

关键 field trials：
- `WebRTC-Bwe-LossBasedControl`：新版丢包 BWE
- `WebRTC-Bwe-MaxRttLimit`：RTT 回退
- `WebRTC-ExponentialNackBackoff`：NACK 指数退避
- `WebRTC-SendSideBwe-WithOverhead`：音频开销扣除
- `WebRTC-AlrDetectorParameters`：ALR 参数
- `WebRTC-Pacer-...`：Pacer 参数
- `WebRTC-UseEarlyLossDetection`：早期丢包检测

设计：**默认值 + field trial 覆盖**。生产环境用 field trial 调参，实验新算法。这是 WebRTC 灵活调优的关键机制。

---

## 第 12 章 动态网络场景下的算法作用

本章是前面所有章节的综合应用——分析在**各种动态网络变化**下，各 QoS 模块如何交互、算法如何响应。每个场景给出模块交互时序与算法作用过程。

### 12.1 场景一：链路启动与爬坡

**场景**：通话刚建立，初始带宽未知，需快速探测到可用带宽。

**初始状态**：`start_bitrate`（如 300kbps），`GoogCcNetworkController` 刚实例化。

**算法作用过程**：

```
1. 初始探测 (ProbeController::InitiateExponentialProbing)
   ┌─ ProbeController 状态: kInit → kWaitingForProbingResult
   ├─ 生成 ProbeClusterConfig:
   │    簇1: target = 3 × start_bitrate (900kbps), min_probes=5, min_bytes
   │    簇2: target = 6 × start_bitrate (1800kbps)
   └─ NetworkControlUpdate.probe_cluster_configs → Pacer

2. Pacer 发探测 (BitrateProber)
   ┌─ BitrateProber::CreateProbeCluster → clusters_ 入队
   ├─ 媒体包到达 → 进入 probing, 绕过漏桶, 按 probe_rate 全速发
   └─ 发够 min_probes/min_bytes → 簇结束

3. 接收侧反馈 (RemoteEstimatorProxy)
   ┌─ 记录探测包到达时间
   └─ 周期发 TWCC RTCP (50-250ms)

4. 发送侧估计探测码率 (ProbeBitrateEstimator)
   ┌─ HandleProbeAndEstimateBitrate: 算 send_rate/receive_rate
   ├─ 若 receive/send > 0.9: 链路未饱和, res = min(send, recv)
   ├─ 若 receive/send < 0.9: 链路饱和, res = 0.95 × receive
   └─ probe_bitrate = 900kbps (假设未饱和)

5. 延迟 BWE (DelayBasedBwe)
   ┌─ TrendlineEstimator: 探测期间延迟梯度小 → Normal
   └─ delay_based_bitrate = probe_bitrate (采纳探测结果)

6. 指数延续探测 (ProbeController::SetEstimatedBitrate)
   ┌─ 若 probe_bitrate(900) > min_bitrate_to_probe_further(300×0.7=210): 继续
   ├─ 生成新簇: target = 2 × 900 = 1800kbps (further_exponential_probe_scale)
   └─ 重复 2-5, 直到 receive/send < 0.9 (饱和) 或达 max_bitrate

7. AIMD 稳定 (AimdRateControl)
   ┌─ 探测结束, 进入 AdditiveIncrease
   └─ 每周期: bitrate *= 1.08 (8% 爬坡) + 加性增加

8. 输出 (NetworkControlUpdate)
   ┌─ target_rate = 当前估计
   ├─ pacer_config: pacing_rate = target × 2.5
   └─ BitrateAllocator → 各流 OnBitrateUpdated → 编码器
```

**关键模块交互**：`ProbeController`（调度）→ `BitrateProber`（发送）→ `RemoteEstimatorProxy`（反馈）→ `ProbeBitrateEstimator`（估计）→ `DelayBasedBwe`（采纳）→ `AimdRateControl`（稳定）→ `BitrateAllocator`（分配）。

**参数作用**：`first_exponential_probe_scale=3`（首探倍率）、`further_exponential_probe_scale=2`（延续倍率）、`further_probe_threshold=0.7`（是否继续）、`pacing_factor=2.5`（pacing 倍率）。

### 12.2 场景二：带宽骤降（网络拥塞）

**场景**：链路带宽突然下降（如 WiFi 降级、基站拥塞），延迟梯度上升、队列堆积。

**算法作用过程**：

```
1. 延迟梯度上升 (TrendlineEstimator)
   ┌─ 到达时间间隔增大, 累积延迟上升
   ├─ 滑动窗口最小二乘: trendline slope 变正且增大
   ├─ slope > threshold(12.5ms) + hysteresis → Overusing
   └─ 持续 overuse → 触发过用信号

2. AIMD 乘性减少 (AimdRateControl)
   ┌─ 收到 Overusing + estimated_throughput
   ├─ state: Hold → Decrease
   ├─ new_rate = beta(0.85) × min(estimated_throughput, current)
   │            = 0.85 × (下降后的吞吐)
   └─ 乘性减少, 快速降码率缓解拥塞

3. 丢包可能伴随 (SendSideBandwidthEstimation)
   ┌─ 若丢包 > 10%: loss BWE 也减少
   │    new = current × (1 - 0.5 × loss)
   └─ 融合: target = min(delay_based, loss_based, receiver_limit)

4. Pacer 队列堆积 (PacingController)
   ┌─ pacing_rate 随 target 下降
   ├─ 队列可能堆积: ExpectedQueueTime > 500ms
   ├─ 加速排空: pacing_rate × queue_time_factor (有上限)
   └─ CongestionWindowPushbackController: fill_ratio > 1 → 编码码率 × 0.95

5. 编码器降码率 (BitrateAllocator → Encoder)
   ┌─ BitrateAllocator::OnNetworkChanged(降后的 target)
   ├─ DistributeBitrates → 各流降码率
   └─ VideoSendStream: EncoderBitrateAdjuster 平滑降码率

6. 视频自适应可能触发
   ┌─ 若码率降太多, QP 上升 → QualityScaler emit kOveruse
   └─ ResourceAdaptationProcessor: 降分辨率/帧率

7. 恢复 (探测)
   ┌─ 码率稳定后, ProbeController 可能 RequestProbe
   │    (若跌至 0.66 × 之前, 以 0.85 × before_drop 探测)
   └─ 跌落探测确认是真降还是假降
```

**关键模块交互**：`TrendlineEstimator`（检测）→ `AimdRateControl`（减少）→ `SendSideBandwidthEstimation`（融合）→ `PacingController`（排空）→ `CongestionWindowPushbackController`（回退）→ `BitrateAllocator`（分配）→ `QualityScaler`（可能降级）。

**参数作用**：`beta=0.85`（降得快）、`threshold=12.5ms`（过用阈值）、`kBitrateDropThreshold=0.66`（跌落探测）、`kProbeFractionAfterDrop=0.85`（跌落探测倍率）。

### 12.3 场景三：带宽恢复

**场景**：拥塞缓解后，链路带宽恢复，需逐步爬升。

**算法作用过程**：

```
1. 延迟梯度下降 (TrendlineEstimator)
   ┌─ 队列排空, 到达间隔减小
   ├─ trendline slope 变负或近 0
   └─ → Underusing 或 Normal

2. AIMD 加性增加 (AimdRateControl)
   ┌─ 收到 Normal/Underusing
   ├─ state: Decrease/Hold → Increase
   ├─ AdditiveIncrease: bitrate += response_time × estimated_throughput × additive_factor
   │    (线性增长, 慢)
   └─ 或 MultiplicativeIncrease: bitrate × 1.08 (8%, 若刚从过用恢复)

3. ALR 检测 (AlrDetector)
   ┌─ 若应用发送量 < 65% 估计带宽 → 进入 ALR
   ├─ ALR 期间无法靠正常流量判断带宽
   └─ ProbeController: 每 5s 以 2x 周期探测

4. ALR 周期探测 (ProbeController::Process)
   ┌─ alr_probing_interval(5s) 到期
   ├─ 生成簇: target = 2 × current (alr_probe_scale)
   ├─ BitrateProber 发探测
   └─ 若探测结果 > current: 升码率

5. 指数爬坡
   ┌─ 探测成功 → SetEstimatedBitrate → 可能 further_exponential(2x)
   └─ 反复探测直到饱和
```

**关键模块交互**：`TrendlineEstimator`（检测恢复）→ `AimdRateControl`（增加）→ `AlrDetector`（检测限流）→ `ProbeController`（周期探测）→ `BitrateProber`（发送）→ `ProbeBitrateEstimator`（估计）。

**参数作用**：`additive_factor`（加性增长步长）、`1.08`（乘性增长）、`alr_probing_interval=5s`（ALR 探测周期）、`alr_probe_scale=2`（ALR 探测倍率）、`bandwidth_usage_ratio=0.65`（ALR 阈值）。

### 12.4 场景四：高丢包（随机/突发）

**场景**：网络丢包率高（无线弱信号、拥塞丢包），需丢包恢复 + 码率调整。

**算法作用过程**：

```
1. NACK 检测与重传 (NackModule)
   ┌─ 接收侧 OnReceivedPacket 发现空隙 → AddPacketsToNack
   ├─ send_at_seq = seq + WaitNumberOfPackets(0.5) (乱序容忍)
   ├─ GetNackBatch(kSeqNumOnly) → SendNack → RTCP NACK
   ├─ 发送侧 OnReceivedNack → ReSendPacket → BuildRtxPacket → Pacer
   └─ RTX 重传包发出, 1 RTT 后到达

2. 丢包 BWE 减少 (SendSideBandwidthEstimation)
   ┌─ TWCC 反馈显示丢包, last_fraction_loss_ 更新
   ├─ loss = fraction / 256
   ├─ if loss > 10%: new = current × (1 - 0.5 × loss)
   ├─ 每 (300ms + rtt) 减一次
   └─ target = min(delay_based, loss_based)

3. FEC 自适应 (FecControllerDefault)
   ┌─ UpdateFecRates: 丢包率上升
   ├─ VCMFecMethod::ProtectionFactor 查表 → FEC 因子增大
   ├─ ProtectionRequest → fec_generator->SetProtectionParameters
   ├─ UlpfecGenerator/FlexfecSender 增加冗余包
   └─ protection_overhead 增大, 编码码率相应降

4. 保护模式切换
   ┌─ 若 RTT < 20ms: NACK 为主, FEC delta=0
   ├─ 若 RTT 20ms~: NACK + FEC 混合
   └─ 若 RTT 很高: FEC 为主

5. 关键帧回退 (若丢包极严重)
   ┌─ nack_list > 1000 且无法裁剪 → NackModule 请求关键帧
   └─ LossNotificationController: 依赖不可解码 → RequestKeyFrame

6. 接收端 FEC 恢复
   ┌─ FlexfecReceiver/UlpfecReceiver: DecodeFec → AttemptRecovery
   ├─ 若缺 1 包: XOR 恢复
   └─ 恢复包标记 is_recovered, 不触发 NACK
```

**关键模块交互**：`NackModule`（检测）→ RTX（重传）+ `SendSideBandwidthEstimation`（降码率）+ `FecControllerDefault`（增 FEC）+ `ForwardErrorCorrection`（恢复）。

**参数作用**：`low_loss_threshold=2%`、`high_loss_threshold=10%`、`kLowRttNackMs=20ms`（NACK/FEC 切换）、`kMaxNackPackets=1000`（关键帧回退）、FEC 掩码表（bursty/random）。

### 12.5 场景五：网络抖动增大

**场景**：网络延迟方差增大（路由波动、队列抖动），接收端需增大缓冲延迟抗卡顿。

**算法作用过程**：

```
1. 抖动估计上升 (VCMJitterEstimator)
   ┌─ 帧到达时间方差增大
   ├─ Kalman: varNoise_ EWMA 上升
   ├─ residual 增大 → 测量噪声 R 增大
   └─ jitter = θ₀×(maxSize−avgSize) + sqrt(varNoise_)×3 上升

2. 目标延迟增大 (VCMTiming)
   ┌─ SetJitterDelay(jitter)
   ├─ TargetDelay = jitter + decode_time + render_delay 上升
   └─ current_delay 速率限制逼近 TargetDelay (100ms/s)

3. 渲染时间推迟 (VCMTiming::RenderTimeMs)
   ┌─ RenderTime = extrapolated + current_delay
   └─ 渲染等待时间增大, 抗卡顿但延迟高

4. A/V 同步调整 (RtpStreamsSynchronizer)
   ┌─ 视频延迟变化 → ComputeRelativeDelay
   ├─ 若视频相对音频延迟变化 > 阈值
   └─ 调整视频 min_playout_delay 对齐音频

5. GCC 可能受影响
   ┌─ 抖动可能伴随延迟梯度上升 → TrendlineEstimator 可能 Overusing
   └─ 若持续: AIMD 降码率 (减少队列堆积)
```

**关键模块交互**：`VCMJitterEstimator`（估计）→ `VCMTiming`（目标延迟）→ `TimestampExtrapolator`（时间映射）→ `RtpStreamsSynchronizer`（A/V 同步）→ 可能 `TrendlineEstimator`（若伴随延迟梯度）。

**参数作用**：`maxNoiseQuantile=3`（噪声阈值）、速率限制 `100ms/s`（延迟调整步长）、`render_delay=10ms`。

### 12.6 场景六：CPU 过载

**场景**：设备 CPU 紧张，编码耗时超过帧间隔，编码器跟不上。

**算法作用过程**：

```
1. CPU 过载检测 (OveruseFrameDetector)
   ┌─ 每帧记录 encode_time
   ├─ encode_time_ratio = encode_time / frame_interval
   ├─ 滑动窗口统计 mean
   ├─ if mean > 1.2 and duration > 2s: emit kOveruse
   └─ CpuOveruseResource 传播信号

2. 视频降级 (ResourceAdaptationProcessor)
   ┌─ 收到 kOveruse
   ├─ VideoStreamAdapter::GetAdaptationDown
   ├─ 按 DegradationPreference:
   │    BALANCED: 先降帧率(2/3) 再降分辨率(5/6)
   │    MAINTAIN_FRAMERATE: 只降分辨率
   │    MAINTAIN_RESOLUTION: 只降帧率
   ├─ VideoSourceRestrictions{pixels, fps}
   └─ VideoSource::AddOrUpdateSink → 采集源降分辨率/帧率

3. 编码器收到更小/更少帧
   ┌─ 编码耗时下降
   ├─ encode_time_ratio 下降
   └─ 若 < 0.5: emit kUnderuse → 升级

4. 码率可能调整
   ┌─ 降分辨率/帧率后, 实际码率需求下降
   └─ EncoderBitrateAdjuster 平滑调整
```

**关键模块交互**：`OveruseFrameDetector`（检测）→ `CpuOveruseResource`（信号）→ `ResourceAdaptationProcessor`（决策）→ `VideoStreamAdapter`（算 restrictions）→ `VideoStreamEncoder`（应用）→ 采集源。

**参数作用**：`kOveruseThreshold=1.2`、`kUnderuseThreshold=0.5`、`kOveruseTimeThresholdMs=2000`、分辨率步长 `5/6`、帧率步长 `2/3`。

### 12.7 场景七：网络切换/路由变化

**场景**：网络切换（WiFi→4G）或路由变化，RTT/带宽突变。

**算法作用过程**：

```
1. RTT 突变检测
   ┌─ TWCC 反馈 RTT 突变
   ├─ feedback_max_rtts_ 滚动窗口捕获新 RTT
   └─ VCMRttFilter 检测跳变 → 重置

2. BWE 可能重置
   ┌─ 若 RTT 突变伴随丢包/延迟突变
   ├─ TrendlineEstimator: 延迟梯度突变 → Overusing
   ├─ AIMD 乘性减少
   └─ 若极端: ProbeController RequestProbe (跌落探测)

3. RTT 回退 (RttBasedBackoff)
   ┌─ 若 RTT > 3s (rtt_limit_): 疑似缓冲膨胀
   ├─ 每秒降 0.8 (drop_fraction), 下限 5kbps
   └─ 快速降码率避免缓冲膨胀

4. FEC/NACK 策略调整
   ┌─ RTT 变化 → FecControllerDefault 重新评估
   ├─ 若 RTT 升高: 倾向 FEC (NACK 来不及)
   └─ MaxFramesFec 随 RTT 调整

5. 探测恢复
   ┌─ 网络稳定后, 指数探测爬坡 (同场景三)
   └─ ALR 周期探测补充
```

**关键模块交互**：`RTT 估计` → `TrendlineEstimator`（延迟）+ `RttBasedBackoff`（RTT 回退）+ `ProbeController`（跌落探测）+ `FecControllerDefault`（FEC 调整）。

**参数作用**：`rtt_limit_=3s`、`drop_fraction=0.8`、`bandwidth_floor=5kbps`、`kBitrateDropThreshold=0.66`。

### 12.8 场景八：应用限流 ALR

**场景**：应用发送量不足（如屏幕共享静止、低帧率），无法靠正常流量探测带宽。

**算法作用过程**：

```
1. ALR 检测 (AlrDetector)
   ┌─ IntervalBudget: 实际发送 < 65% 估计带宽
   ├─ budget_ratio > 0.80 → 进入 ALR
   └─ budget_ratio < 0.50 → 退出 ALR

2. ALR 期间 GCC 行为
   ┌─ 正常流量不足以触发延迟梯度
   ├─ DelayBasedBwe: 可能 Underusing (无足够样本)
   └─ AIMD: 可能缓慢 AdditiveIncrease

3. ALR 周期探测 (ProbeController)
   ┌─ 每 5s (alr_probing_interval) 触发
   ├─ target = 2 × current (alr_probe_scale)
   ├─ BitrateProber 发探测包
   └─ ProbeBitrateEstimator 估计

4. ALR 结束处理
   ┌─ 发送量恢复 > 50% → 退出 ALR
   ├─ acknowledged_bitrate_estimator: ExpectFastRateChange (快速适应)
   └─ ProbeController: SetAlrEndedTime (可能触发额外探测)

5. ALR 期间过用回退
   ┌─ alr_limited_backoff_enabled_: ALR 期间过用回退更谨慎
   └─ 避免应用限流误判为拥塞
```

**关键模块交互**：`AlrDetector`（检测）→ `ProbeController`（周期探测）→ `BitrateProber`（发送）→ `AcknowledgedBitrateEstimator`（退出时快速适应）。

**参数作用**：`bandwidth_usage_ratio=0.65`、`start_budget_level_ratio=0.80`、`stop_budget_level_ratio=0.50`、`alr_probing_interval=5s`、`alr_probe_scale=2`。

### 12.9 场景九：低码率屏幕共享

**场景**：屏幕共享，帧率低、内容静止，码率需求低但偶发突变（翻页）。

**算法作用过程**：

```
1. 低码率特性
   ┌─ 屏幕静止: 码率极低, 进入 ALR
   ├─ 翻页: 突发大帧, 码率瞬时飙升
   └─ 帧率低(如 5fps): 帧间隔大

2. ALR 与探测
   ┌─ 静止期: ALR, 周期探测维持带宽估计
   └─ 翻页期: 突发流量, 可能触发延迟梯度 → AIMD 调整

3. 抖动估计 FPS 缩放
   ┌─ VCMJitterEstimator: jitter / frameRate
   ├─ 低帧率(5fps): 抖动估计放大
   └─ VCMTiming: TargetDelay 可能偏大

4. SVC 丢非基础层
   ┌─ 若用 SVC: 低码率时丢非基础层(temporal/spatial)
   ├─ FrameBuffer: 非基础层帧依赖基础层
   └─ 带宽不足时只保留基础层

5. FEC 策略
   ┌─ BitRateTooLowForFec: 码率太低关 FEC
   └─ 依赖 NACK (若 RTT 低)
```

**关键模块交互**：`AlrDetector` + `ProbeController`（ALR 探测）+ `VCMJitterEstimator`（FPS 缩放）+ `FrameBuffer`（SVC 依赖）+ `FecControllerDefault`（低码率关 FEC）。

### 12.10 各场景模块交互时序总结

| 场景 | 主导模块 | 辅助模块 | 关键算法 |
|---|---|---|---|
| 启动爬坡 | ProbeController, BitrateProber | ProbeBitrateEstimator, AIMD | 指数探测 3x/6x/2x |
| 带宽骤降 | TrendlineEstimator, AIMD | PacingController, Pushback | 乘性减少 beta=0.85 |
| 带宽恢复 | AIMD, AlrDetector | ProbeController | 加性增加 + ALR 探测 |
| 高丢包 | NackModule, SendSideBWE | FecController, RTX | NACK 重传 + FEC + 降码率 |
| 抖动增大 | VCMJitterEstimator | VCMTiming, A/V sync | Kalman 抖动 + 速率限制 |
| CPU 过载 | OveruseFrameDetector | AdaptationProcessor | 降分辨率/帧率 |
| 网络切换 | RTT 估计, RttBasedBackoff | ProbeController | RTT 回退 + 跌落探测 |
| ALR 限流 | AlrDetector | ProbeController | 周期探测 2x |
| 屏幕共享 | AlrDetector | JitterEstimator, SVC | ALR + FPS 缩放 + SVC 丢层 |

**共性规律**：
1. **检测**（Trendline/Nack/Overuse/Jitter）→ **决策**（AIMD/ProbeController/Adaptation）→ **执行**（Pacer/Encoder/FEC/RTX）→ **反馈**（TWCC/RTCP）闭环
2. **保守下降、激进探测**贯穿所有场景——降得快、升得谨慎
3. **多机制协同**：码率控制 + 丢包恢复 + 时延控制 + 自适应，单一机制不足以应对所有场景
4. **参数自适应**：阈值、倍率、周期都可根据网络状态调整，非固定值

---

## 第 13 章 设计模式与设计哲学

WebRTC QoS 子系统运用了大量设计模式，体现了清晰的工程哲学。本章总结这些模式与哲学。

### 13.1 策略模式：BWE 算法可替换

`NetworkControllerFactoryInterface`（`api/transport/network_control.h`）定义 BWE 算法的工厂接口：

```cpp
class NetworkControllerFactoryInterface {
  virtual std::unique_ptr<NetworkControllerInterface> Create(NetworkControllerConfig) = 0;
};
```

实现可替换：
- `GoogCcNetworkControllerFactory` → `GoogCcNetworkController`（默认，GCC）
- `PccNetworkControllerFactory` → `PccNetworkController`（PCC 算法）
- 自定义工厂 → 自定义 BWE

`RtpTransportControllerSend` 持有 `std::unique_ptr<NetworkControllerFactoryInterface>`，通过依赖注入选择算法。**算法可替换而不改调用方**。

### 13.2 工厂模式：NetworkControllerFactoryInterface

工厂模式创建控制器实例。`GoogCcNetworkControllerFactory`（`api/transport/goog_cc_factory.{h,cc}`）：

```cpp
class GoogCcNetworkControllerFactory : public NetworkControllerFactoryInterface {
  std::unique_ptr<NetworkControllerInterface> Create(NetworkControllerConfig config) override {
    return std::make_unique<GoogCcNetworkController>(config, ...);
  }
};
```

工厂封装创建细节（field trial 参数、子组件初始化），调用方只需 `factory->Create(config)`。

### 13.3 观察者模式：TargetTransferRateObserver / BitrateAllocatorObserver

QoS 大量用观察者模式做异步通知：

```cpp
class TargetTransferRateObserver {  // GCC 输出观察者
  virtual void OnTargetTransferRate(TargetTransferRate) = 0;
};
class BitrateAllocatorObserver {  // 码率分配观察者
  virtual void OnBitrateUpdated(BitrateAllocationUpdate) = 0;
};
```

`CongestionControlHandler` 注册为 `TargetTransferRateObserver`，GCC 输出时通知它。`VideoSendStream`/`AudioSendStream` 注册为 `BitrateAllocatorObserver`，分配时通知。

**解耦**：GCC 不知道谁消费码率，BitrateAllocator 不知道谁用码率。观察者模式实现单向依赖。

### 13.4 状态机模式：AIMD / 探测 / 自适应

多个组件用状态机驱动：

- **`AimdRateControl`**：Hold/Increase/Decrease 三态，状态转换由 `BandwidthUsage` 驱动
- **`ProbeController`**：kInit/kWaitingForProbingResult/kProbingComplete 三态
- **`TrendlineEstimator`**：Normal/Overusing/Underusing 三态
- **`OveruseFrameDetector`**：kStable/kOveruse/kUnderuse

状态机模式优势：**行为确定、转换条件明确、防震荡**。每个状态有明确的进入/退出条件，控制逻辑清晰。

### 13.5 组合模式：GoogCcNetworkController 组合子组件

`GoogCcNetworkController` 用组合（非继承）聚合 8 个子组件：

```cpp
class GoogCcNetworkController : public NetworkControllerInterface {
  std::unique_ptr<SendSideBandwidthEstimation> bandwidth_estimation_;
  std::unique_ptr<DelayBasedBwe> delay_based_bwe_;
  std::unique_ptr<ProbeController> probe_controller_;
  // ... 8 个子组件
};
```

`OnTransportPacketsFeedback` 协调子组件调用顺序。**组合优于继承**：每个子组件独立可测、可替换，GoogCcNetworkController 是协调者而非巨型类。

### 13.6 接口隔离：NetworkControllerInterface 抽象控制契约

`NetworkControllerInterface`（`api/transport/network_control.h`）定义 12 个回调，抽象"网络控制器"契约：

```cpp
class NetworkControllerInterface {
  virtual NetworkControlUpdate OnNetworkAvailability(NetworkAvailability) = 0;
  virtual NetworkControlUpdate OnNetworkRouteChange(NetworkRouteChange) = 0;
  virtual NetworkControlUpdate OnProcessInterval(ProcessInterval) = 0;
  virtual NetworkControlUpdate OnRemoteBitrateReport(RemoteBitrateReport) = 0;
  virtual NetworkControlUpdate OnRoundTripTimeUpdate(RoundTripTimeUpdate) = 0;
  virtual NetworkControlUpdate OnSentPacket(SentPacket) = 0;
  virtual NetworkControlUpdate OnReceivedPacket(ReceivedPacket) = 0;
  virtual NetworkControlUpdate OnStreamsConfig(StreamsConfig) = 0;
  virtual NetworkControlUpdate OnTargetRateConstraints(TargetRateConstraints) = 0;
  virtual NetworkControlUpdate OnTransportPacketsFeedback(TransportPacketsFeedback) = 0;
  virtual NetworkControlUpdate OnNetworkStateEstimate(NetworkStateEstimate) = 0;
  virtual NetworkControlUpdate OnTransportLossReport(TransportLossReport) = 0;
};
```

**接口隔离**：调用方只依赖抽象接口，不依赖 GCC 具体实现。算法替换（策略模式）依赖此接口。输入/输出用 `NetworkControlUpdate` 统一，形成"纯函数式"契约——输入结构 → 算法 → 输出结构。

### 13.7 适配器模式：TransportFeedbackAdapter

`TransportFeedbackAdapter`（`modules/congestion_controller/rtp/transport_feedback_adapter.{h,cc}`）把 TWCC RTCP 反馈**适配**成 GCC 能消费的 `TransportPacketsFeedback`：

```
TWCC RTCP (接收侧格式) → TransportFeedbackAdapter → TransportPacketsFeedback (GCC 格式)
```

适配器模式：转换两个不兼容接口。TWCC RTCP 是协议层格式，`TransportPacketsFeedback` 是算法层输入，适配器桥接。

### 13.8 外观模式：ReceiveSideCongestionController

`ReceiveSideCongestionController` 是接收侧 CC 的外观：

```cpp
class ReceiveSideCongestionController {  // 外观
  RemoteEstimatorProxy remote_estimator_proxy_;
  WrappingBitrateEstimator remote_bitrate_estimator_;
  TransportFeedbackDemuxer feedback_demuxer_;
  // 对外暴露 OnRtpReceivedPacket/OnTransportFeedback, 内部协调子组件
};
```

外观模式：简化复杂子系统接口。调用方只需 `OnRtpReceivedPacket`，不需知道 TWCC/BWE/解复用的协作。

### 13.9 反馈控制哲学：闭环、负反馈、稳定性优先

QoS 的核心哲学是**反馈控制**：

1. **闭环**：检测→决策→执行→反馈，循环往复
2. **负反馈**：过用→降，空闲→升，目标是稳定（非追踪）
3. **稳定性优先**：保守下降（beta=0.85，降得快）、激进探测（3x/6x，升得谨慎但探测大胆）
4. **多闭环嵌套**：外环慢（GCC）、内环快（Pacer/编码器），分层避免震荡
5. **时延感知**：反馈时延影响稳定性，TWCC 短周期（50-250ms）降低闭环时延

### 13.10 保守下降、激进探测的设计取向

这是 GCC 的核心设计取向：

- **保守下降**：过用立即乘性减少（×0.85），快速缓解拥塞。降码率比升码率快——因为拥塞代价（丢包/延迟）比带宽未用代价高。
- **激进探测**：初始 3x/6x 指数探测，大胆试探链路上限。探测失败（饱和）只退 5%，代价小。
- **不对称设计**：下降保守（快速降）、上升激进（大胆探测但谨慎采纳）。这种不对称保证"宁可低估带宽，不可高估引发拥塞"。

### 13.11 参数化与可调性

几乎所有 QoS 参数可通过 field trial 调整，体现**可调性哲学**：
- 算法骨架固定，参数可配
- 默认值保守，field trial 实验激进值
- 生产环境按场景调参，无需重编译

这是 WebRTC 能适应从移动网络到千兆宽带各种场景的关键。

### 13.12 分层解耦哲学

QoS 的分层解耦：
- **网络层**（GCC）不关心媒体类型（音/视频）
- **流层**（BitrateAllocator）不关心编码器
- **媒体层**（Encoder/ANA）不关心网络算法
- **传输层**（Pacer/RTP）不关心拥塞控制算法

层间通过接口（`NetworkControllerInterface`、`BitrateAllocatorObserver`）解耦，每层可独立演进。

---

## 第 14 章 QoS 设计优缺点与最佳实践

本章总结 WebRTC QoS 设计的优缺点，与其他实现对比，并提取可复用的设计模式。

### 14.1 优点

#### 14.1.1 分层清晰，职责单一

- **网络层（GCC）/ 流层（BitrateAllocator）/ 媒体层（Encoder/ANA）/ 传输层（Pacer）** 各司其职
- 每层接口清晰（`NetworkControllerInterface`、`BitrateAllocatorObserver`），层间单向依赖
- 新增流类型或编码器不影响 GCC；更换 BWE 算法不影响 Pacer

#### 14.1.2 算法可替换

- `NetworkControllerFactoryInterface` 让 BWE 算法（GCC/PCC/自定义）可插拔
- `FecController` 接口让 FEC 决策可替换
- 编码器接口统一，新增编码器只需实现接口

#### 14.1.3 闭环稳健

- 多闭环嵌套（GCC 25ms + Pacer 5ms + 编码器帧级），快慢分离避免震荡
- 负反馈 + 保守下降 + 激进探测，稳定性强
- 状态机驱动（AIMD/探测/检测），行为确定

#### 14.1.4 参数可调

- 几乎所有参数通过 field trial 动态配置
- 默认值保守，可按场景调优
- 无需重编译即可实验新参数

#### 14.1.5 多机制协同

- 码率控制（GCC）+ 丢包恢复（NACK/FEC）+ 时延控制（JitterBuffer）+ 自适应（Adaptation）四管齐下
- 单一机制不足以应对所有场景，协同覆盖
- NACK/FEC 按 RTT 智能切换，兼顾效率与鲁棒性

#### 14.1.6 强类型单位系统

- `DataRate`/`DataSize`/`TimeDelta`/`Timestamp` 编译期类型安全
- 消除单位混淆（bps vs kbps vs bytes）
- 零运行时开销（constexpr）

### 14.2 缺点

#### 14.2.1 参数繁多，调优困难

- GCC 有数十个参数（阈值、倍率、周期、窗口），相互耦合
- Trendline 的 `window_size`/`smoothing`/`gain`/`threshold` 相互影响
- 无系统化调优方法论，依赖经验与实验
- field trial 参数分散，难追踪全貌

#### 14.2.2 调试困难

- 跨多个线程/队列（controller/pacer/encoder/decode/network），调用链长
- 状态分散在多个组件（Trendline/AIMD/ProbeController/Pushback），难追踪整体状态
- 反馈环路复杂，因果难定位（码率降是延迟过用还是丢包？）
- 缺乏统一的 QoS 状态可视化（虽有 RtcEventLog，但分析门槛高）

#### 14.2.3 多反馈源冲突

- 延迟 BWE、丢包 BWE、探测 BWE、REMB 四个源，融合取 min 可能过于保守
- TWCC 与 REMB 双路径并存（legacy 兼容），增加复杂度
- cwnd pushback 与 AIMD 两个降码率机制，可能叠加过降

#### 14.2.4 legacy 双路径并存

- `NackModule2` vs `NackModule`、`FrameBuffer` vs `VCMJitterBuffer`、`PacedSender` vs `TaskQueuePacedSender`、接收侧 Kalman BWE vs 发送侧 Trendline
- 新旧实现并存，代码膨胀，初学者困惑
- 迁移渐进，但 legacy 代码仍需维护

#### 14.2.5 接口层级深

- `NetworkControllerInterface` 12 回调，`GoogCcNetworkController` 组合 8 子组件，每个子组件又有内部结构
- 新手需理解 Trendline→AIMD→ProbeController→Pushback 的协作，学习曲线陡
- 文档分散在代码注释，缺乏系统化架构文档（本文档旨在弥补）

#### 14.2.6 过度保守

- 融合取 min（delay/loss/receiver/max）可能过于保守，带宽利用不充分
- 探测失败退避 5%、AIMD 加性增加慢，恢复期长
- 对高带宽低延迟链路，可能低估带宽

### 14.3 与其他实现对比

| 维度 | WebRTC GCC | TCP Reno/Cubic | SCReAM | NADA |
|---|---|---|---|---|
| 位置 | 发送侧（TWCC） | 传输层 | 发送侧 | 接收侧 |
| 信号 | 延迟梯度+丢包+探测 | 丢包（Reno）/窗口（Cubic） | 延迟+丢包 | 延迟+丢包 |
| 增长 | AIMD（1.08+加性） | AIMD（1 MSS） | AIMD | AIMD |
| 减少 | 乘性 0.85 | 乘性 0.5（Reno）/0.8（Cubic） | 乘性 | 乘性 |
| 探测 | 指数 3x/6x/2x | 无（靠 cwnd 增长） | 无 | 无 |
| 实时性 | 强（50-250ms 反馈） | 弱（RTT 级） | 强 | 强 |
| 媒体感知 | 是（pacing+编码器） | 否 | 是 | 是 |

**GCC 特点**：
- vs TCP：GCC 用延迟梯度（非仅丢包），更早检测拥塞；媒体感知（pacing+编码器协同）
- vs SCReAM/NADA：GCC 探测机制更激进（指数探测），恢复更快；但参数更多

### 14.4 可复用的 QoS 设计模式

从 WebRTC QoS 可提取的通用设计模式：

#### 14.4.1 反馈控制闭环模式

适用于任何需要"根据反馈调整输出"的系统：
- 检测（传感器）→ 决策（控制器）→ 执行（执行器）→ 反馈（测量）闭环
- 保守下降、激进试探
- 多闭环嵌套（快慢分离）

#### 14.4.2 算法可替换模式

适用于算法可能演进的系统：
- 抽象接口（`NetworkControllerInterface`）+ 工厂（`FactoryInterface`）
- 依赖注入选择实现
- 输入/输出结构统一，算法是"纯函数"

#### 14.4.3 多机制协同模式

适用于单一机制不足的场景：
- 多机制并行（NACK/FEC、码率/分辨率/帧率）
- 按条件切换（RTT 决定 NACK/FEC 比例）
- 融合策略明确（取 min/叠加/优先级）

#### 14.4.4 状态机驱动控制模式

适用于需要确定行为的控制：
- 状态枚举 + 转换条件明确
- 滞回阈值防震荡
- 状态决定动作（Hold/Increase/Decrease）

#### 14.4.5 分层解耦模式

适用于复杂系统：
- 按职责分层（网络/流/媒体/传输）
- 层间接口单向依赖
- 每层独立演进

#### 14.4.6 参数化可调模式

适用于需适应多场景的系统：
- 算法骨架固定，参数可配
- 默认保守，实验激进
- 运行时配置（field trial 机制）

#### 14.4.7 强类型单位模式

适用于数值密集系统：
- 强类型单位（DataRate/TimeDelta）防混淆
- 编译期安全，零开销
- 运算符重载保证量纲正确

### 14.5 总结

WebRTC QoS 是一个**工程成熟、设计精巧**的实时媒体 QoS 系统。其核心价值在于：

1. **分层清晰**：网络/流/媒体/传输四层解耦，各层可独立演进
2. **算法可替换**：BWE/FEC/编码器通过接口抽象，支持实验与替换
3. **闭环稳健**：多闭环嵌套 + 负反馈 + 保守下降，稳定性强
4. **多机制协同**：码率/丢包/时延/自适应四管齐下，覆盖全场景
5. **参数可调**：field trial 机制支持运行时调优，适应多场景

其代价是**复杂度高、参数繁多、调试困难**。但作为实时媒体 QoS 的工业级参考实现，其设计模式与工程哲学值得任何实时系统借鉴。

---

> **文档完**
>
> 本文档分析了 WebRTC QoS 子系统的完整架构：从 GCC 拥塞控制的核心算法（Trendline 延迟估计、AIMD 状态机、指数探测、丢包融合），到接收侧反馈（TWCC/REMB）、Pacing 与码率分配、丢包恢复（NACK/FEC）、抖动缓冲与时延控制、视频自适应、音频网络适配，再到核心数据结构、线程架构、内存/控制架构、动态网络场景、设计模式与优缺点。所有分析结合具体文件与代码，包含算法内部原理、参数配置、模块交互时序，旨在为深入理解 WebRTC QoS 提供系统化参考。
