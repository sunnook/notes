# WebRTC QoS 设计分析（M144 版）

> ✅ **【M144 修订版】** 本文档已逐章节对照 WebRTC M144 源码树（`/data1/luhonghao/codes/adrtc/wr-m144_release`）核对修正（2026-09-10），代码路径、类名均以 M144 为准。
> 原老版本文档（基于约 M105–M125）已归档至 `wr-docs-archive-old-webrtc/wr-qs-analysis.md`。
>
> 读者画像：具备 C/C++ 经验，熟悉高级 C++ 用法但需要补充；已有模块认知、架构认知和完整业务流程认知，希望深入理解 QoS 的算法内部原理与参数。
>
> 相关文档：
> - `wr-modules-analysis.md`：模块架构分析
> - `wr-arch-design-analysis.md`：整体架构设计分析
> - `wr-whole-process.md`：完整业务流程分析
> - `wr-qs-design-analysis-plan.md`：本文档的章节规划

---

## ⚠️ 与老版本（≈M105–M125）的差异总览

本文档以 **M144** 为准改写。正文各处标 `⚠️ 版本差异` 处即**老版实现**的描述/遗留，非 M144 本体——那些内容按约定可保留不核对（老版源码已不在树中），但要与 M144 区隔阅读。下面是逐章核对中发现的主要新老差异，供按章对比：

| 章节 | 老版本（≈M105–M125） | M144（本文档为准） |
|---|---|---|
| 2 | `LossBasedBandwidthEstimation`（幂函数 loss↔bitrate 建模） | 该实现**已删除**，换成新的 **`LossBasedBweV2`**（`goog_cc/loss_based_bwe_v2.{cc,h}`） |
| 2/3/11 | 加性增加步长 `avg_packet_size/(rtt+100ms)` | **`avg_packet_size/(2×(rtt+100ms))`**（`aimd_rate_control.cc:199-204`），response_time 翻倍 |
| 3 | `RemoteEstimatorProxy` + `WrappingBitrateEstimator` + `TransportFeedbackDemuxer` 组合 | 已删除；TWCC 生成移入 **`TransportSequenceNumberFeedbackGenenerator`**，另新增 RFC8888 `CongestionControlFeedbackGenerator`、`RembThrottler` |
| 3 | Kalman 残差用 `Δarrival`，噪声 `R=25·var_noise` | 残差用 **`t_ts_delta = t_delta − ts_delta`**（`overuse_estimator.cc:37,60`），`R=var_noise_`（无 ×25），3σ 门限滤迟到帧 |
| 3 | 过用自适应 `kUp=0.25/kDown=0.05`（升快降慢） | **`kUp=0.0087/kDown=0.039`**（升慢降快），阈值更新式不同（`overuse_detector.cc:23-27,79-96`） |
| 4 | `PacedSender`（继承 Module，process thread 每 5ms `Process()`） | **已删除 `PacedSender`/`paced_sender.h`**，只留 `TaskQueuePacedSender`+`PacingController` 动态模式 |
| 4 | `RoundRobinPacketQueue` + `StreamPrioKey`/`kMaxLeadingSize` | 已删除，替换为 **`PrioritizedPacketQueue`**（固定 5 级：`0=音频,1=音频重传,2=视频重传,3=视频/FEC,4=padding`）+ 每级内 StreamQueue 轮转 |
| 5 | `NackModule`（`nack_module2.{h,cc}`）、指数退避 field trial `WebRTC-ExponentialNackBackoff`、`kMaxNackRetries=10` | 更名 **`NackRequester`**，退避 trial 已删除、纯 RTT 周期，`kMaxNackRetries=100`，周期处理改 `NackPeriodicProcessor`（`RepeatingTaskHandle`，20ms） |
| 5 | `RtcpFeedbackBuffer`、`ModuleRtpRtcpImpl`、`rtcp_receiver/` 子目录 | 前两者删除/更名 `ModuleRtpRtcpImpl2`，`rtcp_receiver` 移回 `modules/rtp_rtcp/source/` |
| 6 | `FrameBuffer`（`frame_buffer2.{h,cc}`，`crit_`/`frame_event_` 阻塞 `NextFrame`、逐帧 `decodable`） | **重写为时间单元模型**（`api/video/frame_buffer.{h,cc}`，2021），无锁、按 frame ID 排序/按时间戳分组、只跟踪 `continuous`；调度外移到 `video_stream_buffer_controller`+`frame_decode_scheduler`+`frame_decode_timing` |
| 6 | `VCMJitterEstimator`/`VCMRttFilter`/`VCMCodecTimer` | → **`JitterEstimator`**（Kalman 抽出 `FrameDelayVariationKalmanFilter`）/ **`RttFilter`** → **`DecodeTimePercentileFilter`**（95 百分位），全在 `timing/` |
| 6/7 | 旧 `jitter_buffer`/`frame_buffer` | 主链路不用，已移 `modules/video_coding/deprecated/` |
| 8 | `WebRTC-SendSideBwe-WithOverhead`、`WebRTC-Audio-StableTargetAdaptation`、`UseTwccPlrForAna` trial | M144 已**删除**；ANA 开销扣除为**默认行为**，勿再引用 trial |
| 10 | `ProcessThread`（`modules/include/module.h`）周期驱动 | **已完全删除**（全树无 `class ProcessThread`），改为各对象自身的 TaskQueue/`RepeatingTaskHandle`；`RtpVideoStreamReceiver2` 等文件名带 `2` |
| 10/11 | `RtpTransportControllerSend::task_queue_` 名为 `"rtp_send_controller"` | **无此命名队列**，控制器跑在 `TaskQueueBase::Current()` 构造线程/network 线程 |
| 14 | 三套长期并存（`NackModule`/`NackRequester`、`PacedSender`/`TaskQueuePacedSender`、`ProcessThread`/TaskQueue） | M144 完成大清理，只保留新版 |

> 说明：表中"老版本"一列因老版源码不再存在于 `wr-m144_release` 树中，直接沿用原文档描述、未经逐条源码核对，仅作差异位置提示；**数值/结构一律以右侧"M144"列为准**。

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
- [3.3 接收侧 BWE（Kalman 滤波）](#33-接收侧-bwekalman-滤波)
- [3.4 TWCC 反馈生成](#34-twcc-反馈生成)
- [3.5 发送侧 TWCC 消费：TransportFeedbackAdapter](#35-发送侧-twcc-消费transportfeedbackadapter)
- [3.6 反馈解复用：TransportFeedbackDemuxer](#36-反馈解复用transportfeedbackdemuxer)
- [3.7 CongestionControlHandler](#37-congestioncontrolhandler)
- [3.8 AbsSendTime vs TWCC 对比与演进](#38-abssendtime-vs-twcc-对比与演进)
- [3.9 完整反馈环数据流图](#39-完整反馈环数据流图)

#### 第 4 章：Pacing 与码率分配
- [4.1 Pacing 入口与接口](#41-pacing-入口与接口)
- [4.2 唯一实现：TaskQueuePacedSender](#42-唯一实现taskqueuepacedsender)
- [4.3 PacingController 核心算法：漏桶 + 债务/信用](#43-pacingcontroller-核心算法漏桶-债务信用)
- [4.4 PrioritizedPacketQueue：优先级 + 流间公平](#44-prioritizedpacketqueue优先级-流间公平)
- [4.5 BitrateProber：探测簇生命周期](#45-bitrateprober探测簇生命周期)
- [4.6 PacketRouter：按 SSRC 路由 + transport seq 分配](#46-packetrouter按-ssrc-路由-transport-seq-分配)
- [4.7 BitrateAllocator：多流码率分配](#47-bitrateallocator多流码率分配)
- [4.8 RtpBitrateConfigurator：三源码率约束合并](#48-rtpbitrateconfigurator三源码率约束合并)
- [4.9 完整控制闭环](#49-完整控制闭环)
- [4.10 线程模型](#410-线程模型)

#### 第 5 章：丢包恢复 NACK 与 FEC
- [5.1 丢包恢复总览](#51-丢包恢复总览)
- [5.2 NACK 模块：NackRequester](#52-nack-模块nackrequester)
- [5.3 LossNotificationController](#53-lossnotificationcontroller)
- [5.4 发送侧重传响应：RTX 路径](#54-发送侧重传响应rtx-路径)
- [5.5 ULP FEC：XOR 保护 + 掩码表](#55-ulp-fecxor-保护-掩码表)
- [5.6 FlexFEC](#56-flexfec)
- [5.7 FecControllerDefault：FEC 开销决策](#57-feccontrollerdefaultfec-开销决策)
- [5.8 保护模式：kNack / kNackFec / kFec](#58-保护模式knack-knackfec-kfec)
- [5.9 NACK 与 FEC 协同策略](#59-nack-与-fec-协同策略)
- [5.10 线程模型](#510-线程模型)

#### 第 6 章：抖动缓冲与时延控制
- [6.1 接收路径总览](#61-接收路径总览)
- [6.2 抖动估计：JitterEstimator](#62-抖动估计jitterestimator)
- [6.3 FrameBuffer：时间单元依赖图模型](#63-framebuffer时间单元依赖图模型)
- [6.4 VCMJitterBuffer / 老 FrameBuffer（deprecated）](#64-vcmjitterbuffer-老-framebufferdeprecated)
- [6.5 VCMTiming：渲染时间计算](#65-vcmtiming渲染时间计算)
- [6.6 TimestampExtrapolator：RTP→本地时间映射](#66-timestampextrapolatorrtp本地时间映射)
- [6.7 RttFilter：RTT 滤波](#67-rttfilterrtt-滤波)
- [6.8 DecodeTimePercentileFilter：95 百分位解码时间](#68-decodetimepercentilefilter95-百分位解码时间)
- [6.9 A/V 同步：RtpStreamsSynchronizer + StreamSynchronization](#69-av-同步rtpstreamssynchronizer-streamsynchronization)
- [6.10 抖动反馈闭环](#610-抖动反馈闭环)
- [6.11 线程模型](#611-线程模型)

#### 第 7 章：视频自适应
- [7.1 视频自适应总览：三路降级](#71-视频自适应总览三路降级)
- [7.2 Resource 抽象与 ResourceAdaptationProcessor](#72-resource-抽象与-resourceadaptationprocessor)
- [7.3 CPU 过载检测：OveruseFrameDetector](#73-cpu-过载检测overuseframedetector)
- [7.4 质量缩放：QualityScaler + QualityThreshold](#74-质量缩放qualityscaler-qualitythreshold)
- [7.5 VideoStreamEncoderResourceManager：资源信号聚合](#75-videostreamencoderresourcemanager资源信号聚合)
- [7.6 VideoStreamAdapter：VideoSourceRestrictions 计算](#76-videostreamadaptervideosourcerestrictions-计算)
- [7.7 自适应决策管线](#77-自适应决策管线)
- [7.8 EncoderBitrateAdjuster：码率平滑与防过冲](#78-encoderbitrateadjuster码率平滑与防过冲)
- [7.9 EncoderOvershootDetector：编码器过冲检测](#79-encoderovershootdetector编码器过冲检测)
- [7.10 QualityLimitationReasonTracker](#710-qualitylimitationreasontracker)
- [7.11 三路信号优先级与合并](#711-三路信号优先级与合并)
- [7.12 参数表](#712-参数表)
- [7.13 线程模型](#713-线程模型)

#### 第 8 章：音频网络适配
- [8.1 音频适配总览](#81-音频适配总览)
- [8.2 AudioNetworkAdaptor 与 Controller 管理器](#82-audionetworkadaptor-与-controller-管理器)
- [8.3 各 Controller](#83-各-controller)
- [8.4 ControllerManager：控制器选择](#84-controllermanager控制器选择)
- [8.5 配置 proto 与 debug dump](#85-配置-proto-与-debug-dump)
- [8.6 与 ANA 的集成入口](#86-与-ana-的集成入口)
- [8.7 线程模型](#87-线程模型)
- [8.8 参数表](#88-参数表)

#### 第 9 章：核心数据结构与单位系统
- [9.1 单位类型：api/units](#91-单位类型apiunits)
- [9.2 控制消息结构](#92-控制消息结构)
- [9.3 BWE 结构](#93-bwe-结构)
- [9.4 Pacing 结构](#94-pacing-结构)
- [9.5 分配结构](#95-分配结构)
- [9.6 抖动结构](#96-抖动结构)
- [9.7 数据结构设计哲学](#97-数据结构设计哲学)

#### 第 10 章：线程架构与并发控制
- [10.1 QoS 涉及的线程/队列全景](#101-qos-涉及的线程队列全景)
- [10.2 controller task queue（GCC 运行）](#102-controller-task-queuegcc-运行)
- [10.3 pacer task queue（PacingController 运行）](#103-pacer-task-queuepacingcontroller-运行)
- [10.4 decode queue（FrameBuffer/解码）](#104-decode-queueframebuffer解码)
- [10.5 接收侧 CC 周期驱动（⚠️ ProcessThread 已删除）](#105-接收侧-cc-周期驱动-processthread-已删除)
- [10.6 network thread 与 worker thread](#106-network-thread-与-worker-thread)
- [10.7 跨线程同步机制](#107-跨线程同步机制)
- [10.8 线程亲和 vs 锁的取舍](#108-线程亲和-vs-锁的取舍)

#### 第 11 章：内存与控制架构
- [11.1 所有权体系：unique_ptr 子组件组合 / scoped_refptr 共享](#111-所有权体系unique_ptr-子组件组合-scoped_refptr-共享)
- [11.2 控制架构：反馈控制闭环](#112-控制架构反馈控制闭环)
- [11.3 分层控制：网络层 → 流层 → 媒体层](#113-分层控制网络层-流层-媒体层)
- [11.4 控制周期](#114-控制周期)
- [11.5 状态机驱动的控制](#115-状态机驱动的控制)
- [11.6 参数化与 field trial 机制](#116-参数化与-field-trial-机制)

#### 第 12 章：动态网络场景下的算法作用
- [12.1 场景一：链路启动与爬坡](#121-场景一链路启动与爬坡)
- [12.2 场景二：带宽骤降（网络拥塞）](#122-场景二带宽骤降网络拥塞)
- [12.3 场景三：带宽恢复](#123-场景三带宽恢复)
- [12.4 场景四：高丢包（随机/突发）](#124-场景四高丢包随机突发)
- [12.5 场景五：网络抖动增大](#125-场景五网络抖动增大)
- [12.6 场景六：CPU 过载](#126-场景六cpu-过载)
- [12.7 场景七：网络切换/路由变化](#127-场景七网络切换路由变化)
- [12.8 场景八：应用限流 ALR](#128-场景八应用限流-alr)
- [12.9 场景九：低码率屏幕共享](#129-场景九低码率屏幕共享)
- [12.10 各场景模块交互时序总结](#1210-各场景模块交互时序总结)

#### 第 13 章：设计模式与设计哲学
- [13.1 策略模式：BWE 算法可替换](#131-策略模式bwe-算法可替换)
- [13.2 工厂模式：NetworkControllerFactoryInterface](#132-工厂模式networkcontrollerfactoryinterface)
- [13.3 观察者模式：TargetTransferRateObserver / BitrateAllocatorObserver](#133-观察者模式targettransferrateobserver-bitrateallocatorobserver)
- [13.4 状态机模式：AIMD / 探测 / 自适应](#134-状态机模式aimd-探测-自适应)
- [13.5 组合模式：GoogCcNetworkController 组合子组件](#135-组合模式googccnetworkcontroller-组合子组件)
- [13.6 接口隔离：NetworkControllerInterface 抽象控制契约](#136-接口隔离networkcontrollerinterface-抽象控制契约)
- [13.7 适配器模式：TransportFeedbackAdapter](#137-适配器模式transportfeedbackadapter)
- [13.8 外观模式：ReceiveSideCongestionController](#138-外观模式receivesidecongestioncontroller)
- [13.9 反馈控制哲学：闭环、负反馈、稳定性优先](#139-反馈控制哲学闭环负反馈稳定性优先)
- [13.10 保守下降、激进探测的设计取向](#1310-保守下降激进探测的设计取向)
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
| 抖动缓冲 | `modules/video_coding/timing/*`、`api/video/frame_buffer.*` | 消除网络抖动，平滑播放 |
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
│       │           │NackRequester│      │VCMTiming  │        │Jitter    │        │
│       │           │(丢包检测) │         │(渲染时间) │        │Estimator │        │
│       │           └─────┬─────┘         │(A/V sync)│        │(Kalman)  │        │
│       │                 │ RTCP NACK     └──────────┘        └──────────┘        │
│       │                 ▼                                                      │
│  ┌────┴──────────────────────┐                                                  │
│  │ReceiveSideCongestionCtrl  │── TWCC RTCP ─────────────────────────────────────▶│
│  │(TransportSeqNumFeedbackGen)│                                               │
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
      │       ├── TransportSequenceNumberFeedbackGenenerator::OnReceivedPacket  记录到达时间 → TWCC 反馈
      │       └── (无 TWCC 时) RemoteBitrateEstimator  接收侧 BWE → REMB
      │
      ├──▶ RtpVideoStreamReceiver::OnRtpPacket
      │       ├── PacketBuffer  组帧
      │       ├── NackRequester  丢包检测 → RTCP NACK
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
| **RTCP NACK** | 接收→发送 | 丢失包序号 | `nack_requester.cc` + `rtp_rtcp_impl2.cc` | 请求重传 |
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
│           └──▶ NackRequester ──▶ RTCP NACK ──────────┘                    │
│           └──▶ TransportSeqNumFeedbackGen ──▶ TWCC ────────────────────────▶│
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│                         丢包恢复闭环（横跨两侧）                            │
│   丢包 ──▶ NACK(重传) + FEC(前向纠错)，按保护模式选择                       │
│   发送侧: UlpfecGenerator/FlexfecSender 生成 FEC + RTX 重传               │
│   接收侧: UlpfecReceiver/FlexfecReceiver 恢复 + NackRequester 请求   │
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
 │   ├── TransportSequenceNumberFeedbackGenenerator │
 │   └── RemoteBitrateEstimator (PickEstimator) │
 │                                  │
 └── RtpTransportControllerSend      │
       owns                         │
       ├── PacketRouter             │
       ├── Pacer (TaskQueuePaced)   │ ◀── SetPacingRates
       │     └── PacingController   │
       │           └── PrioritizedPacketQueue
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
| controller task queue | （无名，`TaskQueueBase::Current()`，已核实） | GCC、CongestionControlHandler、TransportFeedbackAdapter |
| pacer task queue | `"pacer"` | PacingController、PrioritizedPacketQueue、BitrateProber |
| encoder queue | `"EncoderQueue"` | VideoStreamEncoder、OveruseFrameDetector、QualityScaler |
| resource adaptation queue | `"ResourceAdaptationQueue"` | ResourceAdaptationProcessor、VideoStreamAdapter |
| decode queue | (VideoReceiveStream2) | FrameBuffer 回调、解码 |
| worker thread 周期任务 | (RepeatingTaskHandle) | ReceiveSideCongestionController::MaybeProcess（ProcessThread 已删除） |

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

GCC 实现 `NetworkControllerInterface`（`api/transport/network_control.h:63`），这是一个纯虚接口，每个方法接收一个消息结构体，返回 `NetworkControlUpdate`，且标注 `ABSL_MUST_USE_RESULT`。接口明确声明**非线程安全，必须串行调用**。

12 个回调方法（`network_control.h:68-102`）：

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
 ├── bandwidth_estimation_      SendSideBandwidthEstimation   丢包BWE+融合（内嵌 LossBasedBweV2 + RttBasedBackoff）
 ├── delay_based_bwe_            DelayBasedBwe                 延迟BWE
 │     ├── video_inter_arrival_delta_  InterArrivalDelta            时间戳分组
 │     ├── audio_inter_arrival_delta_  InterArrivalDelta            (音频独立)
 │     └── rate_control_         AimdRateControl               AIMD状态机（内嵌 LinkCapacityEstimator）
 ├── probe_controller_           ProbeController               探测调度
 ├── probe_bitrate_estimator_    ProbeBitrateEstimator         探测码率估计
 ├── alr_detector_               AlrDetector                   ALR检测
 ├── acknowledged_bitrate_estimator_  AcknowledgedBitrateEstimatorInterface  确认码率
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
                       │                                    └─ LossBasedBweV2 (内嵌, loss_based_bwe_v2.{cc,h})
                       │
                       │ owns
                       ▼
                 DelayBasedBwe ── owns ──▶ TrendlineEstimator (implements DelayIncreaseDetectorInterface)
                       │                ├─ InterArrivalDelta (goog_cc/inter_arrival_delta.{cc,h})
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

#### 2.5.1 InterArrivalDelta 时间戳分组

`InterArrivalDelta`（`modules/congestion_controller/goog_cc/inter_arrival_delta.{cc,h}`，`DelayBasedBwe` 持有 video/audio 两个实例，`delay_based_bwe.cc:150-153`）把包按时间戳分组（每 5ms 一组），计算相邻组三个 delta：
- `send_time_delta`：发送时间差
- `arrival_time_delta`：到达时间差
- `packet_size_delta`：大小差

关键：`d_delta = arrival_time_delta - send_time_delta` 即"one-way delay 变化"——若网络队列增长，到达比发送慢，`d_delta > 0`。

> 注：接收侧 REMB 遗留路径仍保留老的 `InterArrival`（`modules/remote_bitrate_estimator/inter_arrival.{cc,h}`），GCC 发送侧延迟路在 M144 用的是 goog_cc 自己的 `InterArrivalDelta`。

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

`TrendlineEstimator::Detect`（`trendline_estimator.cc:267`，私有方法，由 `UpdateTrendline` `:244` 内部调用；对外状态经 `State()` `:263` 返回，若挂了 ML `NetworkStatePredictor` 则返回预测值 `:258-264`）：

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

`UpdateThreshold`（`trendline_estimator.cc:306`）——阈值会随信号强度自适应，避免固定阈值在不同网络下失效：

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
| `window_size` | 20 包 | 回归窗口 | `trendline_estimator.h:46`（`kDefaultTrendlineWindowSize`，可被 field trial `WebRTC-BweWindowSizeInPackets` 覆盖（`trendline_estimator.cc:41-43,45-60`）） |
| `smoothing_coef_` | 0.9 | 指数平滑系数 | `trendline_estimator.h:98` |
| `threshold_gain_` | 4.0 | 趋势放大增益 | `trendline_estimator.h:99` |
| `threshold_` (初始) | 12.5 | 过用阈值 | `trendline_estimator.cc:176` |
| `k_up_` | 0.0087 | 阈值上升率 | `trendline_estimator.h:110` |
| `k_down_` | 0.039 | 阈值下降率 | `trendline_estimator.h:111` |
| `overusing_time_threshold_` | 10ms | 过用持续时间门槛 | `trendline_estimator.cc:175`（`h:112`） |

### 2.6 延迟 BWE 与 AIMD

`DelayBasedBwe`（`delay_based_bwe.cc`）接收 `TrendlineEstimator` 的状态，驱动 `AimdRateControl` 产出延迟码率。

#### 2.6.1 AIMD 状态机

`AimdRateControl`（`modules/remote_bitrate_estimator/aimd_rate_control.cc`）三个状态（`bwe_defines.h:42`）：

```
状态转换 (ChangeState, aimd_rate_control.cc:238 由 ChangeBitrate:223 调用):
  kBwNormal  + kRcHold    → kRcIncrease
  kBwNormal  + kRcIncrease → kRcIncrease (保持)
  kBwOverusing + any       → kRcDecrease
  kBwUnderusing + any      → kRcHold
```

#### 2.6.2 增加/减少策略

**增加**（`ChangeBitrate`, `aimd_rate_control.cc:223`）：
- 若已有链路容量估计（接近容量）→ **加性增加**：`rate += avg_packet_size / (rtt + 100ms) * elapsed`，最小 4000 bps/s。 ⚠️已核实为错(M144 响应时间为 2×(rtt+100ms))

> ✅ **核实结论**：M144 `aimd_rate_control.cc:191-207` `GetNearMaxIncreaseRateBpsPerSecond`：`response_time = rtt_ + 100ms;` 然后 **`response_time = response_time * 2;`**（`:202`），再 `avg_packet_size / response_time`（`:203-204`）；`kMinIncreaseRateBpsPerSecond=4000` 下限（`:205-206`）属实。故加性增加步长是 `avg_packet_size / (2×(rtt+100ms))`，原文漏了 `/2`。

- 若无链路容量估计（远离容量）→ **乘性增加**：`alpha = 1.08^min(elapsed_s, 1.0)`，`rate += max(rate*(alpha-1), 1000)`。 ✅已核实正确（`aimd_rate_control.cc:355-366`，1.08 与 1000bps 下限均属实）
- 上限：`1.5 * estimated_throughput + 10kbps`。 ✅已核实正确（`aimd_rate_control.cc:251-252`）

**减少**（`aimd_rate_control.cc:290`）：
- `decreased = estimated_throughput * beta_(0.85)` —— **乘性减少，因子 0.85**；有链路容量估计时用 `beta_ * link_capacity_.estimate()`（`:300`）。 ⚠️部分错误(漏减 5kbps；且 :300 的回退有前置条件)

> ✅ **核实结论**：M144 `aimd_rate_control.cc:290-293`：`decreased_bitrate = estimated_throughput * beta_;` 后若 `decreased_bitrate > 5kbps` 再 **`-= 5kbps`**，原文省略。`beta_` 默认 `kDefaultBackoffFactor=0.85`（`:35`），可被 `WebRTC-BweBackOffFactor` trial 覆盖。`:300` 的 `beta_ * link_capacity_.estimate()` 回退**有前置条件**——仅当 `decreased_bitrate > current_bitrate_` 时才启用（`:295`），即"乘 0.85 后仍高于当前码率"（链路容量估计滞后于吞吐下降）才用容量估计兜底，非无条件。

- 仅当 `decreased < current` 时才减（避免过用反而升码率）。
- 记录 `last_decrease_`，转入 `kRcHold`（排空队列）。

`beta_ = 0.85` 是关键参数（`kDefaultBackoffFactor`，`aimd_rate_control.cc:35`，可通过 `WebRTC-BweBackOffFactor` 调，`:76-78`）。比 TCP 的 0.5 温和——实时通信不希望码率大起大落。

`DelayBasedBwe.MaybeUpdateEstimate`（`delay_based_bwe.cc:210`）的决策：
- 过用 + 有确认码率 + `TimeToReduceFurther` → AIMD 减少。
- 过用 + 无确认码率但有估计 + `InitialTimeToReduceFurther` → 估计减半。
- 非过用 + 有探测码率 → 直接设为探测码率（快速采纳探测结果）。
- 非过用 + 无探测 → AIMD 增加/保持。

`Result` 结构（`delay_based_bwe.h:55`）：`{updated, probe, target_bitrate, recovered_from_overuse, backoff_in_alr}`。`recovered_from_overuse` 会触发 `ProbeController::RequestProbe`（过用恢复后主动探测）。

### 2.7 丢包 BWE

丢包 BWE 在 `SendSideBandwidthEstimation`（`send_side_bandwidth_estimation.cc`）中实现。M144 有**两套**：经典丢包算法（默认保留）和新版 `LossBasedBweV2`（field trial `WebRTC-Bwe-LossBasedBweV2`，默认 enabled，`loss_based_bwe_v2.cc:408`）。

#### 2.7.1 经典丢包算法

基于三个丢包阈值（`send_side_bandwidth_estimation.cc:181-183`，构造函数初始化）：

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

`min_bitrate_history_` 是 1 秒滑动窗口的最小码率，让爬坡基于近期低点，更快恢复。

#### 2.7.2 新版 LossBasedBweV2（M144 与老版机制完全不同）

⚠️ **版本差异**：M125 及之前是 `LossBasedBandwidthEstimation`（`loss_based_bandwidth_estimation.cc`，幂函数 `LossFromBitrate/BitrateFromLoss` 建模 loss↔bitrate）；**M144 该实现已删除**，换为全新的 **`LossBasedBweV2`**（`modules/congestion_controller/goog_cc/loss_based_bwe_v2.{cc,h}`）。

V2 的机制（`loss_based_bwe_v2.h:41-160`）：
- **观察序列**：`Observation`（`loss_ratio`/`sending_rate` 等，`:137`）由近期 `PacketResult` 累积成 `PartialObservation`（`:149`）。
- **固有丢包模型**：`ChannelParameters`（`inherent_loss`/`loss_limited_bandwidth`，`:83`）描述"信道本身的固有丢包 + 丢包受限带宽"——丢包不全是拥塞造成，先扣除固有部分再判拥塞。
- **带宽平衡点**：`inherent_loss_upper_bound_bandwidth_balance`（`:100`）、`instant_upper_bound_bandwidth_balance`（`:113`）等参数界定候选区。
- **候选码率集**：在多个 `Candidate`（延迟估计、确认码率、瞬时上界等派生）中用 `Derivatives`（`:132`）选优，产出 `Result{bandwidth_estimate, state}`（`:43-48`）。
- **状态机**：`LossBasedState`（`loss_based_bwe_v2.h:31`）——`kDelayBasedEstimate`/`kIncreasing`/`kDecreasing`/`kHold`，`SendSideBandwidthEstimation` 用 `loss_based_state_`（`send_side_bandwidth_estimation.cc:185`）参与融合。
- **爬坡加速**：`bandwidth_rampup_upper_bound_factor`/`rampup_acceleration_max_factor`（`loss_based_bwe_v2.cc:409-417`）控制恢复期激进程度。

与经典版的关系：V2 启用时给出 `loss_based_bitrate` 上界，与延迟路/REMB/configured max 一起取 min 融合。

#### 2.7.3 RTT 回退

`RttBasedBackoff`（`send_side_bandwidth_estimation.h:37` 声明、成员 `:46-51`）：当 RTT 超过 `rtt_limit_`（3s，疑似缓冲膨胀）时，每秒降 `drop_fraction_`（0.8），下限 `bandwidth_floor_`（5kbps）。field trial `WebRTC-Bwe-MaxRttLimit`。实例成员 `rtt_backoff_`（`send_side_bandwidth_estimation.h:146`）。

#### 2.7.4 融合

M144 的融合由 `SendSideBandwidthEstimation` 内部完成（`UpdateEstimate`/`GetUpperLimit` 路径），延迟估计、接收端限制、配置最大码率取 min；V2 启用时再叠加 `loss_based_state_` 的判定（`:185`）：

```
upper_limit = min(delay_based_limit_, receiver_limit_, max_bitrate_configured_)
if loss_based_bandwidth_estimator_v2_.IsEnabled() and loss_based_bitrate > 0:
    upper_limit = min(upper_limit, loss_based_bitrate)
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

GCC 每次回调返回 `NetworkControlUpdate`（`api/transport/network_types.h:280`）：

```cpp
struct NetworkControlUpdate {
  std::optional<DataSize> congestion_window;             // cwnd
  std::optional<PacerConfig> pacer_config;               // pacing/padding rate
  std::vector<ProbeClusterConfig> probe_cluster_configs;  // 探测簇
  std::optional<TargetTransferRate> target_rate;          // 目标码率+估计
};
```

`GetPacingRates`（`goog_cc_network_control.cc:693`）：

```
pacing_rate = max(min_total_allocated, last_loss_based_target) * pacing_factor_(2.5)
padding_rate = min(max_padding_rate, last_pushback_target)
```

注意：**pacing 基于丢包路目标（pushback 前）**，避免 pushback 期间 pacer 队列堆积。

`TargetTransferRate`（`network_types.h:219` ⚠️已核实为错(实为 :269)）含 `target_rate`、`stable_target_rate`（链路容量估计，用于稳定码率分配）⚠️已核实为错(M144 无此字段)、`network_estimate`（RTT/loss/bwe_period）、`cwnd_reduce_ratio`。

> ✅ **核实结论（已对源码复核）**：M144 `TargetTransferRate`（`api/transport/network_types.h:269-274`）字段为 `at_time`、`network_estimate`、`target_rate`、`cwnd_reduce_ratio`，**没有 `stable_target_rate`**（全树 grep=0）。上文修正基本正确，仅一处措辞需更正：`link_capacity_lower(:313)/upper(:315)` 在 **`NetworkStateEstimate`**（`:303`，`NetworkStateEstimate` 是独立于 `NetworkEstimate`(`:223`) 的另一个结构）中，行号无误但结构名应为 NetworkStateEstimate。


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

GCC 运行在 `RtpTransportControllerSend::task_queue_`（`"rtp_send_controller"`，`rtp_transport_controller_send.cc:117`）。 ⚠️已核实为错(无此命名队列, 实为 TaskQueueBase::Current())所有 `controller_` 调用通过 `PostTask` 投递到此队列，`RTC_DCHECK_RUN_ON(&task_queue_)` 保证串行。 ⚠️已核实:串行由 SequenceChecker 保证(见下)

> ✅ **核实结论**：M144 `RtpTransportControllerSend` 构造函数 `task_queue_(TaskQueueBase::Current())`（`rtp_transport_controller_send.cc:105`），全树无 `"rtp_send_controller"` 字符串（grep=0）；控制器实际运行在**构造它的线程/TaskQueue**（network 线程），无专用命名队列。补充核实：串行保证用的是 `RTC_DCHECK_RUN_ON(&sequence_checker_)`（`sequence_checker_`，如 `rtp_transport_controller_send.cc:844/848/859`），非 `task_queue_` 上的 DCHECK；且 pacer 队列监控周期任务 `kPacerQueueUpdateInterval=25ms`（`:71`）与控制器周期任务（`process_interval_`，GoogCC 工厂返回 25ms，`api/transport/goog_cc_factory.cc:52-53`）都投递到同一 `task_queue_`。


- **周期处理**：`RepeatingTaskHandle` 每 25ms 调 `OnProcessInterval`（`rtp_transport_controller_send.cc:601`）。 ✅已核实(25ms 属实, 但行号应为 :855-862 的 `controller_task_`; 周期值来自 `goog_cc_factory.cc:52-53` kUpdateIntervalMs=25)
- **pacer 队列监控**：独立 25ms 周期任务读 `pacer()->ExpectedQueueTime()` 喂给 pushback controller。 ✅已核实正确（`rtp_transport_controller_send.cc:71,846-853`）
- **串行保证**：`DelayBasedBwe` 额外有 `rtc::RaceChecker network_race_`（`delay_based_bwe.h:116`），即使 task queue 允许并发也保证反馈处理串行。 ✅已核实(RaceChecker 属实, 行号实为 `modules/congestion_controller/goog_cc/delay_based_bwe.h:107`)

`NetworkControllerInterface` 契约明确"非线程安全，必须串行调用"——这是把并发控制责任交给调度者（task queue），而非每个方法加锁，减少开销。

---

## 第 3 章 接收侧拥塞控制与反馈

GCC 是发送侧算法，但它依赖接收侧反馈的两类信号：**TWCC**（到达时间反馈）和**接收侧 BWE**（REMB，legacy）。本章分析接收侧如何产生这些反馈，以及发送侧如何消费。

### 3.1 接收侧 CC 入口

`ReceiveSideCongestionController`（`modules/congestion_controller/include/receive_side_congestion_controller.h`，**注意 M144 路径已从老版 `rtp/include/receive_side_cc.h` 迁移**）是接收侧 CC 的外观类，继承 `CallStatsObserver`。M144 的成员组合（`receive_side_congestion_controller.h:88-107`）：

```cpp
class ReceiveSideCongestionController : public CallStatsObserver {
  const Environment env_;
  RembThrottler remb_throttler_;                    // REMB 发送节流
  bool send_rfc8888_congestion_feedback_ = false;    // RFC8888 反馈开关
  TransportSequenceNumberFeedbackGenenerator
      transport_sequence_number_feedback_generator_;  // TWCC 反馈生成
  CongestionControlFeedbackGenerator
      congestion_control_feedback_generator_;       // RFC8888 反馈生成
  std::unique_ptr<RemoteBitrateEstimator> rbe_;      // 接收侧 BWE (REMB)
  bool using_absolute_send_time_;
  uint32_t packets_since_absolute_send_time_;
};
```

⚠️ **版本差异**：老版组合 `RemoteEstimatorProxy` + `WrappingBitrateEstimator` + `TransportFeedbackDemuxer` 的结构在 M144 已重构——TWCC 生成移入 `TransportSequenceNumberFeedbackGenenerator`（`modules/remote_bitrate_estimator/transport_sequence_number_feedback_generator.h`），并新增 **RFC8888**（`CongestionControlFeedbackGenerator`，`congestion_control_feedback_generator.h`）这条新反馈通道；REMB 经 `RembThrottler`（`modules/congestion_controller/remb_throttler.h`）节流。

入口 `OnReceivedPacket(const RtpPacketReceived&, MediaType)`（头文件 `:52`）+ 周期驱动 `MaybeProcess()`（`:83`，返回下次调用的时间间隔）：
1. `PickEstimator(has_absolute_send_time)` — 选择接收侧 BWE 实现（abs-send-time 或单流）
2. `rbe_->IncomingPacket(...)` — 喂给接收侧 BWE
3. 反馈生成器按 RTCP 类型（TWCC 或 RFC8888）打包到达时间反馈

其他接口：`OnRttUpdate`（CallStatsObserver）、`OnBitrateChanged`（控制反馈频率）、`SetMaxDesiredReceiveBitrate`（REMB 上限）、`LatestReceiveSideEstimate()`、`GetCongestionControllerStatsPerSsrc()`（按 SSRC 反馈统计）。`SetPreferredRtcpCcAckType` 可切换 RTCP 反馈类型。

### 3.2 双路径分发

接收侧对每个 RTP 包做**双路分发**——同一包同时喂给 TWCC/RFC8888 反馈路径和接收侧 BWE 路径。用哪个取决于 SDP 协商的反馈机制：

- **TWCC 启用**（`transport-cc` RTP 扩展）：`TransportSequenceNumberFeedbackGenenerator` 记录到达时间，周期发 TWCC RTCP（或 RFC8888，`send_rfc8888_congestion_feedback_`）。**接收侧 BWE 不再发 REMB**（`rbe_` 仍运行但不输出，或被禁用）。GCC 在发送侧用 TWCC 做延迟估计。
- **TWCC 未启用**（legacy）：`rbe_`（`RemoteBitrateEstimator`，`PickEstimator` 按有无 abs-send-time 选 `RemoteBitrateEstimatorAbsSendTime` 或 `RemoteBitrateEstimatorSingleStream`）运行 Kalman BWE，通过 REMB RTCP（经 `RembThrottler` 节流）把估计发回发送侧。发送侧用 REMB 作为 `receiver_limit_`。

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
  │     threshold = 10 + 25·min(slope/|slope|, 1)   // 自适应  ⚠️已核实为错(该公式形态在 M144 任何文件中不存在)
  │     if slope > threshold and duration > overuse_time: Overusing  ⚠️已核实为错
  │     // ✅核实(M144, overuse_detector.cc): T = min(num_of_deltas, kMaxNumDeltas=60)·offset (cc:44);
  │     //  判 T > threshold_; 夹[6,600] (cc:94 SafeClamp);
  │     //  过用需 time_over_using_ > kOverUsingTimeThreshold(10) 且 overuse_counter_>1
  │     //  且 offset >= prev_offset_ (cc:56-61)
  │
  └─▶ AimdRateControl::Update            // AIMD 调整码率 → REMB
        (与发送侧 AIMD 同构, beta=0.85)
```

#### 3.3.1 OveruseEstimator Kalman 方程

`overuse_estimator.cc` 的 Kalman 模型（一阶）：

```
状态向量 x = [slope, offset]ᵀ          // 延迟斜率 + 偏移
状态转移 F = I (随机游走)
观测 H = [Δts, 1]                      ⚠️已核实为错 —— M144 实际 h=[fs_delta, 1](帧大小增量)
预测: x̂ = F·x̂, P = F·P·Fᵀ + Q
残差: y = Δarrival - H·x̂              ⚠️已核实为错 —— 实际用 t_ts_delta=t_delta-ts_delta
新息: K = P·Hᵀ / (H·P·Hᵀ + R)
更新: x̂ += K·y, P = (I - K·H)·P
```

测量噪声 `R = 25·var_noise`（`overuse_estimator.cc:40`）  ⚠️已核实为错(R=var_noise_, 无×25; :40 行号也不对)

> ✅ **核实结论（已对源码逐条复核）**：上文修正块全部属实，行号精确无误：
> - 观测矩阵首分量是**帧大小增量 `fs_delta`**（`h = {fs_delta, 1.0}`，`overuse_estimator.cc:56`），不是 Δts；残差基于**发送补偿后到达间隔 `t_ts_delta = t_delta - ts_delta`**（`cc:37`，残差式 `residual = t_ts_delta - slope_*h[0] - offset_` 在 `cc:60`）。
> - 测量噪声 R 就是 `var_noise_`，**无 ×25 因子**（`cc:74` `denom = var_noise_ + h[0]·Eh[0] + h[1]·Eh[1]`）。
> - 噪声更新用 3σ 门限滤掉非常迟到的帧（`max_residual = 3.0·sqrt(var_noise_)`，`cc:64-72`）。
> - `num_of_deltas_` 封顶 `kDeltaCounterMax=1000`（`cc:25,41-43`）；overuse/underuse 期间 `E_[1][1] += 10·process_noise_[1]`（`cc:46-54`），并非持续衰减 Q。

#### 3.3.2 OveruseDetector 自适应阈值

`overuse_detector.cc` 的阈值随时间自适应（`ModifyThreshold`）：  ⚠️已核实为错(函数实为 UpdateThreshold, cc:79-96)

```
if time_over_using > 10ms and slope > prev_slope:
    threshold = min(threshold + slope * kUp(0.25), max_threshold)   ⚠️已核实为错
elif slope < -prev_slope:
    threshold = max(threshold + slope * kDown(-0.05), min_threshold)  ⚠️已核实为错
```

`kUp=0.25`（升得快），`kDown=0.05`（降得慢）——**阈值上升快、下降慢**，避免震荡。  ⚠️已核实为错(方向完全反了)

> ✅ **核实结论（已对源码逐条复核）**：上文修正块全部属实：
> - `overuse_detector.cc:26-27`：`kUp=0.0087`、`kDown=0.039`。因 kUp<kDown：**阈值慢升(kUp)、快降(kDown)** —— 与原"升快降慢"相反。
> - 更新式（`cc:79-96`）：`k = |offset|<threshold ? kDown : kUp`；`threshold += k·(|offset|−threshold)·time_delta_ms`（time_delta 封顶 kMaxTimeDeltaMs=100，`cc:91-92`），`SafeClamp` 到 [6,600]（`cc:94`）。
> - `|offset| > threshold + kMaxAdaptOffsetMs(15)` 时视为大延迟尖峰、跳过更新（`cc:23,83-88`）。
> - 检测用 `T = min(num_of_deltas, kMaxNumDeltas=60)·offset`（`cc:44-45`）；过用同时满足 `time_over_using_>kOverUsingTimeThreshold(10)`、`overuse_counter_>1`、`offset >= prev_offset_`（`cc:46-62`）。注意比较对象是 **T（=样本数×offset）与 threshold**，不是"斜率与阈值"。
> - 附注：发送侧 trendline 的同构逻辑在 `modules/congestion_controller/goog_cc/trendline_estimator.cc:267-324`，其 `modified_trend = min(num_of_deltas,60)·trend·threshold_gain_(4.0)`，k_up_=0.0087/k_down_=0.039/threshold_初值 12.5（`cc:173-176`），阈值更新式与接收侧相同。

#### 3.3.3 两种实现

- **`RemoteBitrateEstimatorSingleStream`**：按 SSRC 分组，每个流独立估计。legacy。
- **`RemoteBitrateEstimatorAbsSendTime`**：用 abs-send-time 扩展，跨流聚合（`PickEstimator`），更准。默认。

### 3.4 TWCC 反馈生成

⚠️ **版本差异**：老版 `RemoteEstimatorProxy`（`remote_estimator_proxy.{h,cc}`）在 M144 已删除，TWCC 生成移入 **`TransportSequenceNumberFeedbackGenenerator`**（`modules/remote_bitrate_estimator/transport_sequence_number_feedback_generator.{h,cc}`）；另有 RFC8888 格式的 `CongestionControlFeedbackGenerator`（`congestion_control_feedback_generator.{h,cc}`）。

#### 3.4.1 到达时间记录

`OnReceivedPacket`（`transport_sequence_number_feedback_generator.h:46`）把每个带 transport seq 的包到达记录存入到达历史（M144 用 `packet_arrival_map.{h,cc}`，老版 `WindowedPacketArrivalHistory` 已删）。

#### 3.4.2 周期反馈

`Process(Timestamp now)`（`transport_sequence_number_feedback_generator.cc:126`）由 `ReceiveSideCongestionController::MaybeProcess` 周期驱动，到点即 `SendPeriodicFeedbacks()`（`:54`），返回下次间隔：

```
send_interval = clamp(5% · bps / packet_size, min=50ms, max=250ms)
// kMinInterval=50ms / kMaxInterval=250ms (cc:38-39)
// 高带宽 → 短间隔, 低带宽 → 长间隔
```

`MaybeBuildFeedbackPacket`（`h:71`）构建 TWCC 报文：
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

`ProcessTransportFeedback`（`transport_feedback_adapter.cc:185`，声明 `h:80`）：
1. 对每个反馈的 seq，查内部 `history_`（map，`:142` 写入，`AddPacket` `:98`）得到 `PacketFeedback`（含 send_time、size、transport_seq）
2. 未反馈的包标记为 lost
3. 设置 `receive_time = base_time + sum(deltas)`
4. 输出 `TransportPacketsFeedback{feedback_time, packet_results, ...}`

历史清理：`kSendTimeHistoryWindow = 60s`（`:38`），且清理时在飞字节同步从 `in_flight_` 移除（`:126-127`）。

⚠️ **版本差异**：老版独立的 `SendPacketMap`/`packet_feedback_provider.{h,cc}` 已并入 adapter 内部 `history_`。

### 3.6 反馈解复用：TransportFeedbackDemuxer

`TransportFeedbackDemuxer`（`modules/congestion_controller/rtp/transport_feedback_demuxer.{h,cc}`）把 TWCC 反馈按 SSRC 分发给多个订阅者（多流 BUNDLE 场景）。M144 保留此组件。

`AddOwningSender` 注册发送方，`OnTransportFeedback` 按 feedback 的 sender_ssrc 路由到对应的 `StreamFeedbackProvider`。

### 3.7 CongestionControlHandler

`CongestionControlHandler`（`modules/congestion_controller/rtp/control_handler.{h,cc}`，由 `RtpTransportControllerSend::control_handler_`（`rtp_transport_controller_send.h:216`）持有）是目标码率的门控层：

- `SetTargetRate`（`control_handler.cc:25`）：聚合 GCC 输出的 `TargetTransferRate`、网络可用性（`SetNetworkAvailability` `:32`）、pacer 队列（`SetPacerQueue` `:37`）
- **紧急停止**：`pacer 队列超阈值` 时 `pause_encoding`，目标码率降 0（`:64-67`，`encoder_paused_in_last_report_` 变化时上报）
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
                ReceiveSideCongestionController::OnReceivedPacket
                   ├─▶ TransportSequenceNumberFeedbackGenenerator::OnReceivedPacket (记录到达)
                   └─▶ (TWCC启用, BWE 不输出)
                                      │
                ...::Process (周期 50-250ms) → SendPeriodicFeedbacks
                                      │
                TWCC RTCP ◀──网络─────┘
                                      │
发送侧 RTCPReceiver::OnTwccFeedback
  └─▶ TransportFeedbackDemuxer::OnTransportFeedback
        └─▶ TransportFeedbackAdapter::ProcessTransportFeedback
              └─▶ TransportPacketsFeedback
                    └─▶ GoogCcNetworkController::OnTransportPacketsFeedback
                          └─▶ NetworkControlUpdate (target_rate)

【RFC8888 路径 - 新格式】（send_rfc8888_congestion_feedback_ = true）
  接收侧 CongestionControlFeedbackGenerator 生成 RFC8888 RTCP（按 SSRC 报告到达时间）

【REMB 路径 - legacy】
发送侧发包(abs-send-time) ──网络──▶ 接收侧
                                      │
                ReceiveSideCongestionController::OnReceivedPacket
                   ├─▶ (TWCC未启用)
                   └─▶ PickEstimator → rbe_(RemoteBitrateEstimatorAbsSendTime)::IncomingPacket
                         └─▶ InterArrival→OveruseEstimator→OveruseDetector→AimdRateControl
                               └─▶ REMB 估计 (经 RembThrottler 节流)
                                      │
                REMB RTCP ◀──网络──────┘
                                      │
发送侧 RTCPReceiver::OnRemb
  └─▶ SendSideBandwidthEstimation::UpdateReceiverEstimate
        └─▶ receiver_limit_ = remb  (融合取 min)
```

### 3.10 线程模型

- **`ReceiveSideCongestionController`**：运行在 **network/worker 线程**（接收 RTP 的线程）。`OnReceivedPacket` 在包接收路径，高频。M144 用 `SequenceChecker`（`receive_side_congestion_controller.h:96`）+ `MaybeProcess` 周期驱动（头文件注释明确 `OnReceivedPacket`/`MaybeProcess` 可能被外部工程在任意线程调用，故逐步迁移 sequence checker）。
- **反馈生成器**（`TransportSequenceNumberFeedbackGenenerator`/`CongestionControlFeedbackGenerator`）：到达记录随包接收线程；周期反馈经内部 `lock_`/`sequence_checker_` 保护，`Process()` 由 `MaybeProcess` 驱动。
- **接收侧 BWE**（`rbe_`）：network 线程，`RTC_GUARDED_BY(mutex_)`。REMB 发送经 `RembThrottler`。
- **`TransportFeedbackAdapter`**：发送侧，运行在 **controller task queue**（已核实无 `"rtp_send_controller"` 命名队列，即构造 `RtpTransportControllerSend` 的线程/network 线程），与 GCC 同队列，保证反馈处理串行。
- **`TransportFeedbackDemuxer`**：运行在 controller task queue。

接收侧 CC 的并发模型：**包接收线程 + MaybeProcess 周期处理**。TWCC 反馈发送跨线程部分由 `absl::Mutex`（`mutex_`）与生成器内部锁保护。

---

## 第 4 章 Pacing 与码率分配

GCC 输出 `TargetTransferRate` 后，需要两步落地：**Pacing**（控制发送节奏，避免突发）和**码率分配**（多流间分配总码率）。本章分析这两个子系统。

### 4.1 Pacing 入口与接口

Pacing 的抽象接口是 `RtpPacketSender`（`api/rtp_packet_sender.h`——**注意 M144 已从老版 `modules/rtp_rtcp/include/rtp_packet_sender.h` 迁到 api/**）和 `RtpPacketPacer`（`modules/pacing/rtp_packet_pacer.h`）：

```cpp
class RtpPacketSender {
  virtual void EnqueuePackets(
      std::vector<std::unique_ptr<RtpPacketToSend>> packets) = 0;
  virtual void RemovePacketsForSsrc(uint32_t ssrc) {}   // 清除某 SSRC 待发包
};
```

`TaskQueuePacedSender`（`modules/pacing/task_queue_paced_sender.h:39`）实现 `RtpPacketPacer` + `RtpPacketSender`。

### 4.2 唯一实现：TaskQueuePacedSender

⚠️ **版本差异**：老版有 `PacedSender`（继承 `Module`，module process thread 每 5ms 调 `Process()`）与 `TaskQueuePacedSender` 两种实现。**M144 已删除 `PacedSender`/`paced_sender.h`**，只保留：

- **`TaskQueuePacedSender`**（`modules/pacing/task_queue_paced_sender.{h,cc}`）：用 **独立 TaskQueue**（`"pacer"`），动态调度——发完一批包立即算下次发送时间，PostDelayedTask 精确唤醒。接口含 `EnqueuePackets`（`:70`）、`ExpectedQueueTime()`（`:111`）等。

包装同一个核心 `PacingController`（`modules/pacing/pacing_controller.{h,cc}`）——算法与调度分离。

### 4.3 PacingController 核心算法：漏桶 + 债务/信用

`PacingController`（`modules/pacing/pacing_controller.cc`）用**漏桶**模型控制发送速率，核心是 `media_debt_`（媒体债务）和 `padding_debt_`（填充债务），单位 bytes（`cc:78-79`）。⚠️ 老版 `PacedSender` 周期模式已删除，M144 只剩动态模式。

#### 4.3.1 动态模式（唯一模式）

- **动态模式**（`TaskQueuePacedSender` + `PacingController`）：`ProcessPackets()`（`cc:388`）发完一批后，算下次发送时间 `NextSendTime()`（`cc:320`），由 TaskQueue `PostDelayedTask` 唤醒。无固定周期，最小睡眠 `kMinSleepTime=1ms`、hold-back 窗口合并包减少唤醒次数（`task_queue_paced_sender.cc:57`）。

#### 4.3.2 发送速率与队列排空加速

- **基础速率**：`SetPacingRates`（`cc:166`）设置 `pacing_rate_` 与 `padding_rate_`。pacing 倍率 `kDefaultPaceMultiplier = 2.5f`（注意：常量在 `goog_cc_network_control.cc:55`，不是 pacing 模块内；`pacing_factor_` 可被 StreamsConfig 覆盖，`goog_cc_network_control.cc:130,307`）。
- **队列排空加速**：`MaybeUpdateMediaRateDueToLongQueue`（`cc:685`）——队列平均滞留时间超过 `queue_time_limit_` 时，算出 `min_rate_needed = queue_size / avg_time_left`，若大于 `pacing_rate_` 则 `adjusted_media_rate_` 提升到它（有 `drain_large_queues_` 开关）。
- **突发限制**：连续发包的 burst 间隔不超过 `send_burst_interval_` 且单 burst ≤ `kMaxBurstSize`（`cc:353-356`），防止一次唤醒发超大突发冲击链路。

`UpdateBudgetWithSentData`（`pacing_controller.cc:669`）：

```
media_debt_ += sent_bytes                  // 发送消耗信用
media_debt_ = min(media_debt_, adjusted_media_rate_ * kMaxDebtInTime)
// kMaxDebtInTime = 500ms (cc:43)  债务上限, 防透支过多
padding_debt_ += sent_bytes; 同样以 padding_rate_ * kMaxDebtInTime 封顶
```

时间推进的信用累积在 `UpdateBudgetWithElapsedTime`（`cc:663`）：

```
// 时间推进 Δt:
media_debt_ -= min(media_debt_, adjusted_media_rate_ * Δt)   // 债务随时间偿还
padding_debt_ -= min(padding_debt_, padding_rate_ * Δt)
```

发送条件：`media_debt_ + packet_size <= adjusted_media_rate_ * kMaxDebtInTime`，即当前缓冲水位 `CurrentBufferLevel() = max(media_debt_, padding_debt_)`（`cc:280`）允许再发一包。债务超限则等待。

#### 4.3.3 padding 与 keepalive

- **padding**：队列空但 `padding_rate_ > 0` 时，`PaddingToAdd`（`cc:594` 附近）计算需补的字节量，`packet_sender_->GeneratePadding()` 生成 padding 包维持码率；`padding_debt_` 以 `padding_rate_ * kMaxDebtInTime` 为预算约束（`cc:676-677`）。老文档"padding_rate = min(max_padding_rate, last_pushback_target)"的说法 M144 不成立，M144 的 padding_rate 来自 PacerConfig（`SetPacingRates`/`UpdateCongestion` 路径）。
- **keepalive**：长时间无媒体时 `NextSendTime()` 返回 `last_send_time_ + kCongestedPacketInterval`（`cc:345`，`kCongestedPacketInterval = 500ms`，`cc:40`），唤醒后发 1 字节 padding keepalive 包（`ProcessPackets` 开头，`cc:398` 附近）维持 NAT/连接。老文档的 `kPausedProcessIntervalMs` 已不存在。

### 4.4 PrioritizedPacketQueue：优先级 + 流间公平

⚠️ **版本差异**：老版 `RoundRobinPacketQueue`（`round_robin_packet_queue.{h,cc}`）在 M144 已删除，替换为 **`PrioritizedPacketQueue`**（`modules/pacing/prioritized_packet_queue.{h,cc}`）——固定 5 级优先级的 deque 数组 + 每级内 StreamQueue 轮转。

#### 4.4.1 优先级分级

`GetPriorityForType`（`prioritized_packet_queue.cc:36`）按媒体类型映射优先级，`kNumPriorityLevels = 5`（`h:106`）：

```
优先级 (低数字=高优先级):
  0  音频重传      ⚠️已核实为错
  1  视频重传     // 重传先于新媒体  ⚠️已核实为错
  2  音频          ⚠️已核实为错
  3  视频          ⚠️已核实为错(且遗漏 FEC)
  4  padding
```

> ✅ **核实结论（已对源码逐条复核）**：上文修正完全属实（`prioritized_packet_queue.cc:34-63`）：`kAudioPrioLevel=0`（`cc:34`）——**普通音频(kAudio)永远是最高优先级 0**（`cc:41-43`，"Audio is always prioritized over other packet types"）。重传(kRetransmission)依原始来源再分级：音频来源重传 = `0+1=1`（`cc:50`），视频来源重传 = `0+2=2`（`cc:47-48`）。**视频(kVideo)与 FEC(kForwardErrorCorrection)同属 3 级**（`cc:51-56`）。padding = `0+4=4`（`cc:57-60`）。故 M144 真实映射为：`0=音频, 1=音频重传, 2=视频重传, 3=视频/FEC, 4=padding`。原文把"音频重传"装到 0、"音频"装到 2 是对调了，且遗漏了 FEC 与视频同级（3）。`kNumPriorityLevels=5`（`prioritized_packet_queue.h:106`）属实。

`Push`（`h:50`）按优先级入队，高优先级先发。队列还支持**按优先级 TTL**（`PacketQueueTTL`：audio_retransmission/video_retransmission 等，`h:33` 定义、`cc:67-77` 映射），超时丢包防过期数据占用。 ✅已核实(仅 TTL 定义行号应为 h:33, 原文 cc:67-77 的 ToTtlPerPrio 实现在 cc:68 起)

#### 4.4.2 StreamQueue 流间公平

同一优先级的多个流以 `StreamQueue` 组织（`h:119` 类定义；`streams_by_prio_` 每优先级一组，`h:186`），`UpdateAverageQueueTime` 轮转调度：同优先级内各流近似轮流发包，保证流间近似按比例共享带宽。每个 `QueuedPacket` 记录 `enqueue_time`（`h:113`）用于队列时长统计。 ✅已核实(原文 h:184/h:113 两处行号引用基本准确: 类定义实为 h:119, streams_by_prio_ 为 h:186)

#### 4.4.3 公平性要点

老版 `StreamPrioKey`（按累积字节排序）与 `kMaxLeadingSize` 机制已随 RoundRobinPacketQueue 删除；M144 的公平性来自 **优先级固定分级 + 同级 StreamQueue 轮转 + TTL**，防"大流饿死小流"由重传高优先级 + 各级独立队列保证。

### 4.5 BitrateProber：探测簇生命周期

`BitrateProber`（`modules/pacing/bitrate_prober.{h,cc}`）管理探测簇，配合 GCC 的 `ProbeController`。

探测簇生命周期：
```
ProbeController 调度 → Pacer::CreateProbeCluster(config)
  │ config = {target_rate(send_bitrate), min_probes, min_bytes, min_probe_delta}   ⚠️已核实为错(字段名不是 ProbeClusterConfig 成员)
  ▼
BitrateProber::CreateProbeCluster (bitrate_prober.cc:100) → 加入 clusters_ 队列
  │  ProbingState: kDisabled→kInactive→kActive (h:89)
  ▼ (有媒体包到达)
BitrateProber::OnIncomingPacket(size) (cc:96) → 若 clusters_ 非空且非 probing: 进入 kActive
  │
  ▼
PacingController::ProcessPackets → 探测期间 is_probing(), 允许提前 kMaxEarlyProbeProcessing 发包
  │ 每包: BitrateProber::ProbeSent(cc:179) 累计 sent_bytes/sent_probes
  │       next_probe_time_ = CalculateNextProbeTime (按 send_bitrate 均匀排)
  │       发够 min_probes 且 min_bytes → clusters_.pop() (cc:192-194)
  │       clusters_ 空 → probing_state_ = kInactive
  ▼
簇出队, 反馈侧 (TransportFeedbackAdapter) 测得簇区间吞吐 → ProbeController 采纳/否决
```

探测期间以 `send_bitrate`（簇目标速率）发包，不受常规漏桶限制（`pacing_controller.cc:419` 允许提前 `kMaxEarlyProbeProcessing` 处理）。`RecommendedMinProbeSize()`（`bitrate_prober.cc:171`）限制单包最小尺寸，避免小包无法达到探测速率。

> ✅ **核实结论（已对源码逐条复核）**：上文修正属实。`ProbeClusterConfig` 真实字段（`api/transport/network_types.h:258-267`）为 `{at_time, target_data_rate, target_duration(探测时长), min_probe_delta(默认 2ms), target_probe_count, id}`，**没有 `min_probes`/`min_bytes` 字段**。文档列的 `min_probes`/`min_bytes` 是 `BitrateProber::CreateProbeCluster`（`bitrate_prober.cc:112-122`）内部派生的 `probe_cluster_min_probes = target_probe_count`（`cc:114-115`）与 `probe_cluster_min_bytes = target_data_rate × target_duration`（`cc:116-118`），概念对应但字段名不是配置结构成员。另核实 `BitrateProberConfig`：`min_packet_size` 默认 200 字节、`max_probe_delay` 10ms（`bitrate_prober.cc:37-38`，trial `WebRTC-Bwe-ProbingBehavior` 可调）；`kProbeClusterTimeout=5s`、`kMaxPendingProbeClusters=5`（`cc:30-31`）。

### 4.6 PacketRouter：按 SSRC 路由 + transport seq 分配

`PacketRouter`（`modules/pacing/packet_router.{h,cc}`）是 Pacer 与多个 RtpRtcp 模块的中介：

- `SendPacket`（`packet_router.cc:171`）：按 SSRC 查 `send_modules_map_`（`h:106`）找到对应 `RtpRtcpInterface`，调 `rtp_module->SendPacket`（先 `CanSendPacket` 校验 `cc:189`）。
- **transport seq 分配**：`set_transport_seq_` 协商开启或包带 TransportSequenceNumber 扩展时，`packet->set_transport_sequence_number(transport_seq_++)`（`packet_router.cc:204-205`），全局递增，用于 TWCC。`ConfigureForRtcpFeedback`（`h:63`）决定是否全类型分配。
- `SendRemb`（`h:87`）：向各模块分发 REMB。
- 反馈接收在 M144 已不通过 PacketRouter 的 `OnRembReceived/OnTransportFeedback`（老接口已删除），TWCC 反馈经 `RtpTransportControllerSend` → `TransportFeedbackAdapter` 直接进 CC，REMB 经 `ReceiveSideCongestionController` 路径。

### 4.7 BitrateAllocator：多流码率分配

`BitrateAllocator`（`call/bitrate_allocator.{h,cc}`）把 GCC 的总目标码率分配给多个流（音频/视频/simulcast）。核心是 `AllocateBitrates`（`bitrate_allocator.cc:421`）。

#### 4.7.1 三种分配模式

`AllocateBitrates`（`bitrate_allocator.cc:443-456`）按总码率与各流需求的关系分三种模式：

```
total_bitrate = 目标总码率
sum_min = Σ MinBitrateWithHysteresis(各流)   // 含滞回的生效最低码率
sum_max = Σ max_bitrate(各流)

if total_bitrate < sum_min:
    【LowRate 模式】(LowRateAllocation, cc:197)
    // 不是简单缩放: 先保 enforce_min_bitrate 的流和活跃流的滞回最低码率,
    // 再唤醒已暂停的流, 最后把余量在有配额的流间均分 (cc:215-243)
elif total_bitrate <= sum_max:
    【Normal 模式】(NormalRateAllocation, cc:263)
    // 各流 min + 剩余按 bitrate_priority 比例分配 (h:69-71)
    // MaybeApplySurplus 允许超配给可吃 surplus 的流
else:
    【Max 模式】(MaxRateAllocation, cc:303)
    // 各流给 max, surplus 按 bitrate_priority 加权分给未达 max×multiplier 的流
```

#### 4.7.2 优先级码率 + 比例分配 + 滞回

- **优先级**：`MediaStreamAllocationConfig::bitrate_priority`（`bitrate_allocator.h:71`，音频高，视频低）。Normal/Max 模式剩余按 `bitrate_priority / Σbitrate_priority` 分配（`cc:173,189,405`）。
- **滞回**：`AllocatableTrack::MinBitrateWithHysteresis`（`bitrate_allocator.cc:739`）——上次分配为 0（已暂停）的流，其"生效最低码率"抬升为 `min_bitrate + max(kToggleFactor×min, kMinToggleBitrateBps)`（`cc:745-749`），避免带宽临界抖动导致流反复暂停/恢复（"toggling"注释见 `cc:234`）。恢复分配时也要求 `remaining_bitrate >= MinBitrateWithHysteresis` 才唤醒（`cc:235-239`）。

#### 4.7.3 AddObserver/OnBitrateUpdated 流程

```
BitrateAllocator::AddObserver(observer, config)  // 流注册 (cc:549)
  └─▶ 记录到 allocatable_tracks_ (已存在则只更新 config)
  └─▶ RecomputeAllocationIfNeeded (cc:597): 需要时重算并回调

Call 级 OnNetworkChanged 状态到达 (BitrateAllocator 内部处理 TargetTransferRate)
  └─▶ AllocateBitrates(allocatable_tracks_, last_target_bps_, upper_elastic_limit) (cc:504)
        └─▶ 各流 observer->OnBitrateUpdated(update) (cc:515)
              │ update = {target_bitrate, packet_loss_ratio, round_trip_time, bwe_period, cwnd_reduce_ratio}
              └─▶ VideoSendStream: 设编码器目标码率
              └─▶ AudioSendStream: 设音频编码器码率
              └─▶ 返回 protection_bitrate, 更新 track.media_ratio
```

### 4.8 RtpBitrateConfigurator：三源码率约束合并

`RtpBitrateConfigurator`（`call/rtp_bitrate_configurator.{h,cc}`）合并三个来源的码率约束，最终在 `UpdateConstraints`（`rtp_bitrate_configurator.cc:95`）：

```
min_bitrate = max(                                   // cc:98-100
    base_bitrate_config_.min_bitrate_bps,           // SDP x-google-min-bitrate
    bitrate_config_mask_.min_bitrate_bps)            // 应用 API 层掩码 (SetBitrate)

max_bitrate = MinPositive(                           // cc:102-106, 0/−1 视为"未设置"
    base_bitrate_config_.max_bitrate_bps,            // SDP x-google-max-bitrate
    bitrate_config_mask_.max_bitrate_bps,            // 应用 API 层掩码
    max_bitrate_over_relay_)                         // relay cap (UpdateWithRelayCap)

if min > max: min = max                              // cc:110-113, max 优先
start_bitrate 仅在 SDP 明确给出且变化时才重启 BWE (cc:64-73)
```

三个更新入口：`UpdateWithSdpParameters`（`cc:55`，SDP 重协商）、`UpdateWithClientPreferences`（`cc:78`，应用 `RtpParameters::bitrate` 掩码）、`UpdateWithRelayCap`（`cc:86`，relay 限制）。`GetConfig()`（`cc:51`）输出合并后的 `BitrateConstraints`，喂给 GCC 作为 `Constraints` 消息（min/max/start）。

### 4.9 完整控制闭环

```
GCC: NetworkControlUpdate
  ├─▶ target_rate (TargetTransferRate)
  │     └─▶ BitrateAllocator 内部分配 (AllocateBitrates, cc:504)
  │           └─▶ 各流 OnBitrateUpdated
  │                 ├─▶ VideoSendStream: EncoderBitrateAdjuster → 编码器
  │                 └─▶ AudioSendStream: 音频编码器码率
  │
  ├─▶ pacer_config (PacerConfig)
  │     └─▶ TaskQueuePacedSender::SetPacingRates(pacing_rate, padding_rate)
  │           └─▶ PacingController::UpdateBudget → 漏桶
  │
  └─▶ probe_cluster_configs
        └─▶ TaskQueuePacedSender::CreateProbeCluster → BitrateProber

编码器产出 RTP 包
  └─▶ TaskQueuePacedSender::EnqueuePackets → PrioritizedPacketQueue
        └─▶ PacingController::ProcessPackets (动态唤醒)
              ├─▶ BitrateProber 探测? → 按 send_bitrate 全速发
              └─▶ 漏桶: media_debt 允许? → PacketRouter::SendPacket
                    └─▶ RtpRtcp::SendPacket (分配 transport_seq)
                          └─▶ 网络
```

### 4.10 线程模型

- **`TaskQueuePacedSender`**（M144 唯一 pacer）：独立 TaskQueue `"pacer"`。`EnqueuePackets`/`CreateProbeCluster`/`SetPacingRates` 都 PostTask 到此队列，`RTC_DCHECK_RUN_ON(task_queue_)`。`ProcessPackets` 在此队列运行。**单线程，无锁**。老版 `PacedSender`（module process thread 5ms 周期 + `crit_`）已删除。
- **`BitrateAllocator`**：运行在 **controller task queue**（`rtp_transport_controller_send` 的 task queue），与 GCC 同队列。`AddObserver`/`OnBitrateUpdated` 串行，`sequenced_checker_` 保护。
- **`PacketRouter`**：运行在 pacer task queue。`thread_checker_` 保护（注册/注销流经 task queue 串行化，`SendPacket` 路径无锁）。
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
| 实现 | `NackRequester`（接收侧）+ RTX（发送侧） | `UlpfecGenerator`/`FlexfecSender`（发送）+ `*Receiver`（接收） |

保护模式由 `FecControllerDefault::SetProtectionMethod` 选择：`kNack` / `kFec` / `kNackFec`（混合）。

### 5.2 NACK 模块：NackRequester

⚠️ **版本差异**：老版 `NackModule`（`modules/video_coding/nack_module2.{h,cc}`）在 M144 已重命名为 **`NackRequester`**（`modules/video_coding/nack_requester.{h,cc}`），且**指数退避 field trial（WebRTC-ExponentialNackBackoff）已删除**，重试策略简化为纯 RTT 周期；`kMaxNackRetries` 从 10 放宽到 100；周期处理从 module process thread 改为 `NackPeriodicProcessor`（`RepeatingTaskHandle`，默认 20ms）。

`NackRequester`（`modules/video_coding/nack_requester.h:70`，继承 `NackRequesterBase:36`）在接收侧检测丢包、生成 RTCP NACK。

#### 5.2.1 丢包检测与 nack list 管理

`OnReceivedPacket`（`nack_requester.cc:158`，重载 `:153`）是入口，每个收到的 RTP 包都经过它：

```
OnReceivedPacket(seq, is_keyframe, is_recovered):
  if 未初始化: newest_seq = seq, return
  if seq == newest_seq: 重复包, return 0
  if AheadOf(newest_seq, seq):  // 乱序到达(比最新包旧)
      if seq in nack_list_: 记录 retries 并 erase  // 之前以为丢了, 现在到了
      if !is_retransmitted: 更新乱序直方图 (cc:185-186)
      return retries
  if is_recovered:  // FEC/RTX 恢复的包
      recovered_list_.insert(seq)
      清除 seq - kMaxPacketAge 之前的旧恢复记录 (cc:194-196)
      return  // 不对恢复包前后的空隙发 NACK
  AddPacketsToNack(newest_seq+1, seq)  // 把空隙加入 nack_list_
  newest_seq = seq
  GetNackBatch(kSeqNumOnly)  // 立即发一批 NACK (buffering_allowed=true)
```

`AddPacketsToNack`（`nack_requester.cc:233`）：
1. 清除比 `seq_end - kMaxPacketAge(10000)` 更老的条目（`:237-238`）
2. 若 `nack_list_.size() + 新增 > kMaxNackPackets(1000)`：**直接 `clear()` + 请求关键帧**（`:241-247`，老版的 `RemovePacketsUntilKeyFrame` 渐进裁剪已删除）
3. 对 `[start, end)` 每个 seq：跳过 `recovered_list_` 中的，创建 `NackInfo{seq, send_at_seq_num = seq + WaitNumberOfPackets(0.5), created_at_time}`（`:249-257`）

`WaitNumberOfPackets(0.5)`（`nack_requester.cc:300`）：基于乱序直方图（`ReorderingHistogram`）的逆 CDF，返回"以 ≥0.5 概率等到该包"需等待的包数——**乱序容忍**，避免对会迟到的包误发 NACK。

#### 5.2.2 请求策略

`GetNackBatch`（`nack_requester.cc:260`）分两种批次：
- **kSeqNumOnly**（包到达时触发，`cc:206`）：首次请求，条件为 `sent_at_time 为∞ 且 newest_seq >= send_at_seq_num`，且已过 `send_nack_delay_`（field trial `WebRTC-SendNackDelayMs`，0-20ms，默认 0，`cc:44-52`）
- **kTimeOnly**（`ProcessNacks()` 周期触发，20ms）：重传请求，当 `now - sent_at_time >= rtt_` 时重发（`cc:270`）

```
resend 策略 (M144):
  重发间隔 = rtt_ (默认 kDefaultRtt=100ms, UpdateRtt 由 RTT 反馈更新)
  老版的指数退避 (WebRTC-ExponentialNackBackoff: min_retry_interval=5ms,
  max_rtt=160ms, base=1.25) 已删除
```

发送时 `retries++`，`sent_at_time = now`（`cc:277-278`）。`retries >= kMaxNackRetries(100)` 则移除（`cc:279-282`）。

#### 5.2.3 关键帧请求回退

当 `nack_list_` 超 1000（`nack_requester.cc:241-247`）：
```
nack_list_.clear()
RTC_LOG(WARNING) "NACK list full, clearing NACK list and requesting keyframe."
keyframe_request_sender_->RequestKeyFrame()  // 请求关键帧
```
丢包太严重时放弃重传，直接要关键帧重新同步。

#### 5.2.4 周期驱动与线程

M144 不再用 module process thread，改用 `NackPeriodicProcessor`（`nack_requester.h:44`）：
- `NackPeriodicProcessor::kUpdateInterval = 20ms`，`RegisterNackModule` 第一个模块注册时 `RepeatingTaskHandle::DelayedStart` 启动周期任务（`cc:60-70`），最后一个注销时 Stop
- 处理在 **worker thread**（`RTC_DCHECK_RUN_ON(worker_thread_)`），由 `RtpVideoStreamReceiver2` 持有并注入（`video/rtp_video_stream_receiver2.h:112,374`）
- 周期批次的 NACK `buffering_allowed=false`（不与其它反馈合并），包触发批次 `buffering_allowed=true`（`cc:149,210`）

#### 5.2.5 参数表

| 参数 | 值 | 含义 |
|---|---|---|
| `kMaxPacketAge` | 10000 | NACK 条目最大年龄（`cc:34`） |
| `kMaxNackPackets` | 1000 | nack_list 最大长度（超则清空+请求关键帧，`cc:35`） |
| `kDefaultRtt` | 100ms | 初始 RTT 估计（`cc:36`） |
| `kMaxNackRetries` | 100 | 单包最大 NACK 次数（老版为 10；`cc:39`） |
| `NackPeriodicProcessor::kUpdateInterval` | 20ms | 周期处理间隔（`h:44`） |
| `kMaxReorderedPackets` | 128 | 乱序直方图最大（`cc:40`） |
| `kNumReorderingBuckets` | 10 | 乱序分桶数（`cc:41`） |
| `kDefaultSendNackDelay` | 0 | 首次 NACK 延迟（field trial `WebRTC-SendNackDelayMs` 可配 0-20ms，`cc:42,44-52`） |

### 5.3 LossNotificationController

`LossNotificationController`（`modules/video_coding/loss_notification_controller.{h,cc}`）实现 RTCP Loss Notification（RFC 8888 风格），作为 NACK 的补充/优化。它跟踪帧的可解码性，发带 decodability flag 的丢包通知。

`OnReceivedPacket`（`loss_notification_controller.cc:53`）：检测序号空隙 + 帧依赖可解码性。若丢包且当前帧依赖不可解码 → `HandleLoss`（`:99,108`）。

`HandleLoss`（`loss_notification_controller.cc:162`）：
- 若存在可解码的非丢弃参考帧：发 `SendLossNotification(last_decodable_seq, last_recv_seq, decodability_flag)`，让发送方知道哪些帧可救
- 否则：`RequestKeyFrame()`

decodability_flag = 所有依赖可解码 AND 帧未丢失前部。比纯 NACK 更智能——告诉发送方"这个帧还能救"还是"没救了，给关键帧"。

### 5.4 发送侧重传响应：RTX 路径

接收侧发 RTCP NACK → 发送侧重传的完整路径：

```
接收侧 NackRequester → NackSender::SendNack(batch)
  └─▶ ModuleRtpRtcpImpl2::SendNack (rtp_rtcp_impl2.cc:620)
        └─▶ RTCPSender::SendRTCP(GetFeedbackState(), kRtcpNack, seqs) → RTCP NACK 发出
              │
              ▼ 网络
发送侧 RTCPReceiver::HandleNack (rtcp_receiver.cc:704)
  └─▶ packet_information.nack_sequence_numbers (rtcp_receiver.cc:714)
        └─▶ TriggerCallbacksFromRtcpPacket (rtcp_receiver.cc:1072)
              └─▶ rtp_rtcp_->OnReceivedNack(...) (rtcp_receiver.cc:1088 → rtp_rtcp_impl2.cc:693)
                    └─▶ RTPSender::OnReceivedNack(nacks, rtt) (rtp_sender.cc:346)
                          ├─▶ packet_history_->SetRtt(5 + avg_rtt) (rtp_sender.cc:349)
                          └─▶ for each seq: ReSendPacket(seq) (rtp_sender.cc:278)
                                └─▶ BuildRtxPacket (rtp_sender.cc:669)
                                      // 新 RTX SSRC, 新 seq, 原 payload 前缀原 seq(2字节)
                                      // packet_type = kRetransmission
                                      └─▶ paced_sender_->EnqueuePackets (rtp_sender.cc:321)
```

⚠️ **版本差异**：老版 `RtcpFeedbackBuffer`（合并 RTCP 反馈的中间层）在 M144 已删除；`ModuleRtpRtcpImpl` 更名为 `ModuleRtpRtcpImpl2`（`rtp_rtcp_impl2.{h,cc}`）；`rtcp_receiver.{h,cc}` 位置从 `rtcp_receiver/` 子目录移回 `modules/rtp_rtcp/source/`。NackRequester 发 NACK 时的合并在 `NackSender` 实现层（RtpVideoStreamReceiver2 内部经 `RtcpFeedbackBufferProxy`→`ModuleRtpRtcpImpl2`）。

`BuildRtxPacket`（`rtp_sender.cc:669`）：创建新包，用 RTX SSRC、新序号、RTX payload type，复制原头部/扩展，**在 payload 前插入原始 2 字节序号**（`kRtxHeaderSize`，`rtp_sender.cc:717-726`），接收端据此还原原序号。

`RtpPacketHistory`（`rtp_packet_history.{h,cc}`）保存已发包用于重传，TTL 由 RTT 决定。`SetRtt(5 + avg_rtt)`（`rtp_sender.cc:349`）调整保留时间。

### 5.5 ULP FEC：XOR 保护 + 掩码表

ULPFEC（RFC 5109）+ RED（RFC 2198）封装。核心是 `ForwardErrorCorrection`（`modules/rtp_rtcp/source/forward_error_correction.{h,cc}`）的 XOR 编解码。

#### 5.5.1 编码

`EncodeFec`（`forward_error_correction.cc:115`）：
1. `num_fec_packets = NumFecPackets(num_media, protection_factor)`（`:156,197`）
   ```
   num_fec = (num_media * protection_factor + 128) >> 8   // round(num_media * fec_rate/255)
   if fec_rate > 0 and num_fec == 0: num_fec = 1           // 至少 1 个
   ```
   protection_factor 255 = 100% 开销（每媒体包一个 FEC 包）
2. `GeneratePacketMasks`（`:171`）：按掩码表选 mask（bursty vs random）
3. `InsertZerosInPacketMasks`（`:176,258`）：若媒体包序号有间隙，在 mask 插零列（间隙无保护）
4. `GenerateFecPayloads`（`:186,209`）：每个 FEC 包 = 受保护媒体包的 XOR
   - 首个受保护包：copy 头部 + payload
   - 后续：`XorHeaders` + `XorPayloads`
5. `FinalizeFecHeaders`（`:192,331`）：写 SSRC、base seq、mask、L bit

#### 5.5.2 掩码表：bursty vs random

两套预计算表（`fec_private_tables_{bursty,random}.h`）：

- **`kPacketMaskBurstyTbl`**：防突发连续丢包，最多 **12 媒体包**。性质：≤m 的连续丢包全可恢复。
- **`kPacketMaskRandomTbl`**：防随机丢包，最多 **48 媒体包**。⚠️已核实为错(两张表都只到 12 包)

> ✅ **核实结论（已对源码逐条复核）**：上文修正属实。`kPacketMaskRandomTbl` 与 `kPacketMaskBurstyTbl` 两张表**都只覆盖最多 12 媒体包**（`forward_error_correction_internal.cc:398-411`："These tables only cover fec code for up to 12 media packets. Starting from 13 media packets…will be generated at runtime"；表尺寸声明 `kPacketMaskRandomTbl: 12`）。文档误把 **48 = `kUlpfecMaxMediaPackets`**（`forward_error_correction_internal.h:24`，ULPFEC 单 FEC 组总媒体包上限，靠 ≥13 包时运行时生成交织 mask 达到）当成了 random 表的媒体维。random 表的实际尺寸含义是"每个媒体数对应的掩码行数可达 48"（掩码数量维），并非"覆盖 48 媒体包"。

`PickTable`（`forward_error_correction_internal.cc:220`）：
```
if fec_mask_type == kFecMaskBursty and num_media <= 12:
    return bursty table
return random table   // >12 包或默认用 random
```

默认 `kFecMaskRandom`（`fec_controller_default.cc:142-143`）。>12 包时用运行时生成的交织 mask。

#### 5.5.3 RED 封装

`GetFecPackets`（`ulpfec_generator.cc:203`）：FEC 包封装在 RED 里——1 字节 RED 头（F=0, PT=ulpfec_PT）+ FEC payload。RTP 头从 `last_media_packet_` 复制。

#### 5.5.4 接收端恢复

`DecodeFec` → `AttemptRecovery`（`forward_error_correction.cc:681`）：
```
for each FEC packet:
    missing = NumCoveredPacketsMissing(fec_packet)
    if missing == 1:    // 恰好缺 1 个, 可恢复
        RecoverPacket (cc:658): recovered = FEC XOR (所有已收的受保护包)
        加入 recovered_packets_, 重扫(恢复可能解锁更多)
    elif missing == 0:  // 全收到, FEC 包无用
        丢弃
    else:               // 缺 >1, 暂无法恢复
        留待后续包
```

`RecoverPacket`（`forward_error_correction.cc:658`）：用 FEC 头初始化恢复包，XOR 所有已收受保护包，恢复 length/seq/SSRC。

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

`FlexfecSender`（`modules/rtp_rtcp/include/flexfec_sender.h:45`，实现在 `modules/rtp_rtcp/source/flexfec_sender.cc`）内部复用 `UlpfecGenerator`（`flexfec_sender.cc:107`，友元访问内部状态）+ `ForwardErrorCorrection::CreateFlexfec`（`flexfec_sender.cc:109`）。`GetFecPackets`（`flexfec_sender.cc:137`）写 FlexFEC RTP 头（20-32 字节，K-bit 分隔的 mask）。

`FlexfecReceiver::OnRtpPacket`（`flexfec_receiver.cc:68`）：按 SSRC 解复用媒体/FEC，喂 `DecodeFec`，恢复包通过 `RecoveredPacketReceiver` 回调（`include/flexfec_receiver.h:45`）。

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

`FecControllerDefault`（`modules/video_coding/fec_controller_default.{h,cc}`）根据网络条件算 FEC 保护因子。核心 `UpdateFecRates`（`fec_controller_default.cc:84`）：

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

`VCMFecMethod::ProtectionFactor`（`media_opt_util.cc:290`）用静态表 `kFecRateTable`：

```
spatialSizeToRef = (W*H) / (704*576)          // 相对 4CIF 的分辨率因子 (cc:322-324)
resolnFac = 1 / pow(spatialSizeToRef, 0.3f)   // 分辨率越高, FEC 需求越低 (cc:328)
bitRatePerFrame = BitsPerFrame(...)           // 考虑时域层
effRateFecTable = resolnFac * bitRatePerFrame
rateIndex = clamp((effRateFecTable - 5)/5, 0, 49)
lossIndex = clamp(loss, 0, 128)               // kPacketLossMax = 129
codeRateDelta = kFecRateTable[rateIndex * 129 + lossIndex]   // 查表
// 关键帧加 firstPartitionProt(~20%) boost (cc:333-334)  ⚠️已核实为错(行号偏差)

> ✅ **核实结论（已对源码逐条复核）**：上文修正属实。`firstPartitionProt` 定义于 `media_opt_util.cc:305`（`saturated_cast<uint8_t>(255 * 0.20)`，即 ~20%），实际施加于关键帧 `codeRateKey` 的位置是 `media_opt_util.cc:363-364`（文档写的 `:333-334` 偏差约 30 行；`:333-334` 处是 `codeRateDelta` 的查表赋值与 `kPacketLossMax` 相关逻辑）。公式本身正确。
// 转换到源码率域: ConvertFECRate(r) = 255*r/(255-r) (cc:274-277)
```

#### 5.7.2 MaxFramesFec

`VCMNackFecMethod::ComputeMaxFramesFec`（`media_opt_util.cc:143`）：
```
if numLayers > 2: return 1   // 基础层帧间隔大 (cc:146-149)
else: max_frames = max(2 * base_layer_framerate * rtt/1000 + 0.5, 1), cap kUpperLimitFramesFec
// FEC 距离: 平均一个完整帧在一个 RTT 内到达 (base_layer_framerate 已按层数折算, cc:154-156)
```

#### 5.7.3 BitRateTooLowForFec

`media_opt_util.cc:174`：码率太低关 FEC：
```
if bytes_per_frame < threshold(≤352*288: kMaxBytesPerFrameForFecLow / >640*480: High / 中间: 默认)
   and numLayers < 3 and rtt < kMaxRttTurnOffFec(200ms):
    FEC 关闭 (K/D 因子都置 0, cc:212-215)
```

### 5.8 保护模式：kNack / kNackFec / kFec

`SetProtectionMethod`（`fec_controller_default.cc:170`）：
```
if enable_fec and enable_nack: kNackFec
elif enable_nack: kNack
elif enable_fec: kFec
else: kNone
```

### 5.9 NACK 与 FEC 协同策略

混合模式 `kNackFec`（`VCMNackFecMethod::ProtectionFactor`，`media_opt_util.cc:105`）按 RTT 分档（`kLowRttNackMs = 20`，`media_opt_util.h:46`；`_highRttNackMs` 构造时传 -1 即不启用高 RTT 纯 FEC 档，`media_opt_util.cc:535`）：

| RTT | 策略 | 原因 |
|---|---|---|
| < 20ms (`kLowRttNackMs`) | **NACK only**（FEC delta 因子=0，`media_opt_util.cc:119-123`） | NACK 够快，FEC 开销不值 |
| ≥ 20ms | **混合**：FEC 保护 + NACK 补 FEC 残余 | FEC 防突发，NACK 补漏 |
| （`_highRttNackMs=-1`） | 高 RTT 纯 FEC 档**未启用** | M144 默认构造关闭该档 |

设计哲学：**低 RTT 重传，高 RTT 前向纠错**——RTT 决定重传是否来得及。

### 5.10 线程模型

| 组件 | 线程 | 同步 |
|---|---|---|
| `NackRequester::OnReceivedPacket` / `ProcessNacks` | worker thread（`RTC_DCHECK_RUN_ON(worker_thread_)`，`nack_requester.h:124`） | `RTC_GUARDED_BY(worker_thread_)`，无互斥锁 |
| `NackPeriodicProcessor` | `RepeatingTaskHandle` 20ms 周期任务，跑在注册时的 TaskQueue（worker） | `sequence_` checker |
| `LossNotificationController` | network（单线程） | `sequence_checker_`（`loss_notification_controller.h:73-88`） |
| `UlpfecGenerator::AddPacketAndGenerateFec` | pacer/发送 task queue | `race_checker_`（`ulpfec_generator.h:111`） |
| `UlpfecGenerator::SetProtectionParameters` | congestion 线程 | `mutex_` + `pending_params_` 交接（`ulpfec_generator.h:126`） |
| `FlexfecSender` | 与 RTP 发送同队列（`RTC_CHECK_RUNS_SERIALIZED(&ulpfec_generator_.race_checker_)`） | 复用 UlpfecGenerator 的同步 |
| `FlexfecReceiver` | network（单线程） | `sequence_checker_` |
| `FecControllerDefault` | congestion 线程 + encoder 线程 | `mutex_`（`fec_controller_default.h:61`） |
| `RtpVideoSender::OnPacketFeedbackVector`（`call/rtp_video_sender.cc:961`） | transport feedback 线程 | `mutex_` 保护 `loss_mask_vector_`（`rtp_video_sender.h:224`） |

NACK 的并发：M144 已无老版的"收包线程 vs process 线程 + `crit_`"模型——`OnReceivedPacket` 与 `ProcessNacks` 都跑在 worker thread 上，靠 `RTC_DCHECK_RUN_ON(worker_thread_)` 断言串行（跨线程入口由调用方 PostTask 保证）。

FEC 的并发：参数设置（congestion 线程）与 FEC 生成（pacer/发送线程）跨线程，用 `pending_params_` 无锁交接——设置线程在 `mutex_` 下写 pending，生成线程在下次 `AddPacketAndGenerateFec` 时读取并交换，避免锁竞争发包路径。

---

## 第 6 章 抖动缓冲与时延控制

前两章解决"码率"和"丢包"，本章解决第三个控制目标——**时延**。接收侧通过抖动估计 + 帧依赖图 + 渲染时间计算，在"延迟 vs 卡顿"间权衡。

### 6.1 接收路径总览

```
网络 RTP 包
  │
  ▼
RtpVideoStreamReceiver2::OnRtpPacket  (video/rtp_video_stream_receiver2.cc)
  ├─▶ NackRequester::OnReceivedPacket        // 丢包检测
  ├─▶ FlexfecReceiver/UlpfecReceiver        // FEC 恢复
  └─▶ video_coding::PacketBuffer::InsertPacket   // 按序号入包缓冲
        │
        ▼
      PacketBuffer::FindFrames                // 找连续的帧边界(marker bit)
        │
        ▼
      RtpVideoStreamReceiver2 → VideoReceiveStream2
        └─▶ VideoStreamBufferController (video/video_stream_buffer_controller.h:80)
              └─▶ FrameBuffer::InsertFrame (api/video/frame_buffer.h:54)  // 时间单元依赖图
                    ├─▶ 连续性检查(IsContinuous)+传播(PropagateContinuity)
                    └─▶ FrameBuffer::ExtractNextDecodableTemporalUnit (h:58)
                          │
                          ▼
                        VideoReceiveStream2::Decode     // 解码队列 (FrameDecodeScheduler 调度)
                              └─▶ Decoder::Decode
                                    └─▶ VCMTiming::RenderTime  // 算渲染时间
                                          └─▶ VideoRender → 显示
```

⚠️ **版本差异（已核实）**：老版 `FrameBuffer`（`modules/video_coding/frame_buffer2.{h,cc}`，带 `NextFrame` 阻塞等待 + `crit_`/`frame_event_`）在 M144 已被**重写为时间单元（temporal unit）模型**：`api/video/frame_buffer.{h,cc}`（2021 年重写），无锁（thread-unsafe，外部串行化）、按 frame ID 排序、按时间戳分组；等待/调度逻辑外移到 `video/video_stream_buffer_controller.{h,cc}` + `video/frame_decode_scheduler.h` + `video/frame_decode_timing.{h,cc}`。旧 `VCMJitterBuffer`/老 `FrameBuffer` 移到 `modules/video_coding/deprecated/`。

> ✅ **核实结论（已对源码逐条复核）**：上文括号内的存疑标注属实——`video/frame_decode_scheduler.h` **没有同名 .cc**，它是抽象接口；其实现类是 **`TaskQueueFrameDecodeScheduler`**（`video/task_queue_frame_decode_scheduler.{h,cc}`，经 `TaskQueueBase::PostDelayedHighPrecisionTask` 调度 `OnFrameReadyTimeout`）。另核实 `frame_decode_timing.{h,cc}` 存在（`FrameDecodeTiming::ComputeDecodeWaitTime` 用 `max_wait = decode_time + render_delay - frame_decode_scheduler 余量` 的决策逻辑，由 `VideoStreamBufferController` 调用）。

### 6.2 抖动估计：JitterEstimator

⚠️ **版本差异**：`VCMJitterEstimator` → **`JitterEstimator`**（`modules/video_coding/timing/jitter_estimator.{h,cc}`），Kalman 滤波器抽出为独立类 **`FrameDelayVariationKalmanFilter`**（`timing/frame_delay_variation_kalman_filter.{h,cc}`），RTT 滤波抽为 `timing/rtt_filter`，帧间延迟计算抽为 `timing/inter_frame_delay_variation_calculator`，解码时间抽为 `timing/decode_time_percentile_filter`。参数可经 field trial `WebRTC-JitterEstimatorConfig`（`jitter_estimator.h:40` 附近）覆盖。

模型：帧延迟 = 传输大小变化引起的延迟 + 随机噪声。

#### 6.2.1 模型

```
frameDelay = θ₀ · Δsize + θ₁ + noise
  Δsize = 当前帧大小 - 平均帧大小
  θ₀: 每字节延迟斜率(排队延迟系数), 下限 kMaxBandwidth=0.000001 (kalman_filter.cc:21)
  θ₁: 固定延迟偏移
  noise: 随机抖动
```

#### 6.2.2 Kalman 更新方程

`FrameDelayVariationKalmanFilter::PredictAndUpdate`（`frame_delay_variation_kalman_filter.cc:55` 起），入口 `JitterEstimator::UpdateEstimate`（`jitter_estimator.cc:186`）：

```
// 1) 预测: F=I (状态即 theta), 协方差 += 过程噪声 (P += Q, 对角)
// 2) 残差(innovation): y = frameDelay - (theta_[0]*deltaSize + theta_[1])
// 3) 观测噪声: R 随 |deltaSize| 相对 max_frame_size 指数衰减
//    stddev = (300*exp(-|deltaSize|/max_frame_size) + 1) * sqrt(varNoise), 下限 1.0
// 4) 增益: K = P·Hᵀ / s,  H = [deltaSize, 1],  s = H·P·Hᵀ + R
// 5) 更新: theta_ += K·y;  theta_[0] 钳到 ≥ kMaxBandwidth
// 6) 协方差更新: P = (I - K·H)·P
```

样本前置过滤（`jitter_estimator.cc:257` 附近）：`num_stddev_delay_outlier = 15.0`（`:53`）——残差超 15σ 视为离群，不进 Kalman，只更新噪声估计；`frame_delay` 先按噪声钳幅（clamp）。

#### 6.2.3 随机抖动估计

`EstimateRandomJitter`（`jitter_estimator.cc:341`）用 EWMA 跟踪残差方差 `var_noise_ms2_`：
```
varNoise_ = alpha_ * varNoise_ + (1 - alpha_) * residual²
alpha_ 随样本数增长: 前 kFrameProcessingStartupCount(30, cc:35) 个样本内线性增大 (cc:367-369)
```

#### 6.2.4 最终抖动

`GetJitterEstimate`（`jitter_estimator.cc:435`）：
```
jitter = CalculateEstimate() + OPERATING_SYSTEM_JITTER  (cc:438)
  CalculateEstimate (cc:398): θ₀·(maxFrameSize-avgFrameSize) + NoiseThreshold
  NoiseThreshold = kNoiseStdDevs(2.33, cc:62)·sqrt(varNoise_) - kNoiseStdDevOffset(30ms, cc:64)
jitter = max(jitter, filter_jitter_estimate_)           // 平滑上限
if nack_count_ >= kNackLimit(3, cc:79):
    jitter += min(rtt * rtt_multiplier, rtt_mult_add_cap)   // NACK 重传项 (cc:448-455)
// FPS 缩放 (cc:458-474): fps<5Hz → 0; 5~10Hz → 线性插值缩放; ≥10Hz → 原值
return max(jitter, 0)
```

#### 6.2.5 NACK 重传项与 FPS 缩放

- **NACK 重传项**：`nack_count_ >= kNackLimit(3)` 时加 `rtt × rtt_multiplier`（调用方传 0.5 即 rtt/2，可带 `rtt_mult_add_cap` 封顶）；`FrameNacked()` 累计（`cc:323-327`），60s 无 NACK 清零（`kNackCountTimeout`，`cc:76`）。
- **FPS 缩放**：低帧率流抖动按帧率缩放（5-10Hz 线性插值，<5Hz 归零），不是老版的简单 `/frameRate`。

#### 6.2.6 参数表

| 参数 | 值 | 含义 |
|---|---|---|
| `kNoiseStdDevs` | 2.33 | 噪声阈值分位数（`cc:62`） |
| `kMaxBandwidth`（theta 下限） | 0.000001 | θ₀ 下限（`frame_delay_variation_kalman_filter.cc:21`） |
| `kNackLimit` | 3 | NACK 重传项生效次数（`cc:79`） |
| `kNackCountTimeout` | 60s | NACK 计数超时清零（`cc:76`） |
| `kNumStdDevDelayOutlier` | 15.0 | 离群样本判定（`cc:53`） |
| `kFrameProcessingStartupCount` | 30 | 启动期样本数（`cc:35`） |
| `kDefaultMaxFrameSizePercentile` | 0.95 | max frame size 分位（`cc:48`） |
| `kPhi`（avg size EWMA） | 0.97 | 帧大小均值平滑（`cc:44`） |
| `kJitterScaleLowThreshold` | 5Hz | FPS 缩放下阈（`cc:459`） |
| `kJitterScaleHighThreshold` | 10Hz | FPS 缩放上阈（`cc:462`） |

### 6.3 FrameBuffer：时间单元依赖图模型

⚠️ **版本差异**：老版 `FrameBuffer`（`frame_buffer2.{h,cc}`，`VideoLayerFrameId` + 逐帧可解码性传播 + `NextFrame` 阻塞）在 M144 已重写（`api/video/frame_buffer.{h,cc}`，2021 年）：**按 frame ID 排序、按 RTP 时间戳分组为时间单元（temporal unit）**、只跟踪连续性（`continuous`）不再跟踪 per-frame `decodable`、无锁。

#### 6.3.1 帧组织

帧按 `int64_t` frame ID 存入 `FrameMap = std::map<int64_t, FrameInfo>`（`api/video/frame_buffer.h:78`），同 RTP 时间戳的多层帧（SVC）构成一个 `TemporalUnit`（`h:81-85`）。类头注释（`h:26-31`）：时间单元在所有引用的外部帧解码后即可解码；连续 = 引用帧都直接或间接可解码。

#### 6.3.2 FrameInfo 结构

`FrameInfo`（`frame_buffer.h:73`）：
```cpp
struct FrameInfo {
  std::unique_ptr<EncodedFrame> encoded_frame;   // 依赖关系在 EncodedFrame 内
  bool continuous = false;                        // 依赖是否都到齐
};
```
帧依赖列表在 `EncodedFrame`（`api/video/encoded_frame.h`）里；解码历史由 `video_coding::DecodedFramesHistory`（`h:99`）跟踪。

#### 6.3.3 连续性传播与时间单元提取

`InsertFrame`（`frame_buffer.cc`）：
1. `IsContinuous`：检查引用帧都已解码或在缓冲中且 continuous（`h:87`）
2. 若 continuous，`PropagateContinuity` 传播：依赖本帧的其他帧重新检查（`h:88`）
3. `FindNextAndLastDecodableTemporalUnit` 维护 `next_decodable_temporal_unit_`（`h:89`）

`ExtractNextDecodableTemporalUnit`（`h:58`）：把下一个可解码时间单元的全部帧标记为已解码并返回；`DropNextDecodableTemporalUnit`（`h:62`）丢弃它。

#### 6.3.4 丢帧处理

依赖永远不到（丢包未恢复）时，由上层 `VideoStreamBufferController`（`video/video_stream_buffer_controller.{h,cc}`）负责：等待超时后 `DropNextDecodableTemporalUnit` 跳帧，或在关键帧请求后清空重来。帧缓冲本身不阻塞——调度/超时/等待在 `video/frame_decode_scheduler.h`（接口；实现 `task_queue_frame_decode_scheduler.{h,cc}`，已核实无同名 .cc）+ `video/frame_decode_timing.{h,cc}`。

### 6.4 VCMJitterBuffer / 老 FrameBuffer（deprecated）

⚠️ **版本差异**：旧实现已移到 `modules/video_coding/deprecated/`（`jitter_buffer.{h,cc}` 三链表 `decodable_frames_`/`incomplete_frames_`/`free_frames_`、老 `frame_buffer.{h,cc}`），M144 主链路完全不使用。不要在新代码阅读中把它们当作活路径。

### 6.5 VCMTiming：渲染时间计算

`VCMTiming`（`modules/video_coding/timing/timing.{h,cc}`，M144 已搬到 `timing/` 子目录）计算每帧的渲染时间，在"延迟 vs 卡顿"间权衡。

#### 6.5.1 目标延迟

`TargetDelayInternal`（`timing.cc:264`）：
```
TargetDelay = max(min_playout_delay, jitter_delay_ + EstimatedMaxDecodeTime() + render_delay_)
  jitter_delay_ = SetJitterDelay 设置 (timing.cc:113), 来自 JitterEstimator
  EstimatedMaxDecodeTime = DecodeTimePercentileFilter 95 百分位 (kPercentile=0.95f)
  render_delay_ = kDefaultRenderDelay (timing.cc:62)
  min_playout_delay = 应用/A/V 同步设定
```
`TargetVideoDelay()`（`timing.cc:259`）是对外接口。另有 `UseLowLatencyRendering`（`min_playout_delay==0` 且 `max_playout_delay` 小于阈值时走低延迟渲染路径，`timing.cc:289` 附近）。

#### 6.5.2 渲染时间

`RenderTime`（`timing.cc:195`）→ `RenderTimeInternal`（`:206`）：
```
RenderTime = extrapolated_local_time + current_delay
  extrapolated_local_time: 由 TimestampExtrapolator 把 RTP 时间戳映射到本地时钟
  current_delay: 速率限制地逼近 TargetDelay
```

#### 6.5.3 速率限制延迟调整

`UpdateCurrentDelay`（`timing.cc:124,165` 两个重载）：
```
// current_delay 以 kDelayMaxChangeMsPerS = 100 ms/s (timing.h:60) 的速率逼近 TargetDelay
diff = TargetDelay - current_delay
max_change = kDelayMaxChangeMsPerS * (elapsed time)
diff = clamp(diff, -max_change, max_change)
current_delay += diff
```
**延迟只能缓慢变**——避免抖动估计尖峰导致渲染时间跳变、画面卡顿。第二重载（`:165`）按实际解码时间与预期渲染时间之差修正。

### 6.6 TimestampExtrapolator：RTP→本地时间映射

`TimestampExtrapolator`（`modules/video_coding/timing/timestamp_extrapolator.{h,cc}`，M144 在 `timing/` 下）用 **Kalman 滤波**把 RTP 时间戳（90kHz）映射到本地接收时间。

```
状态: [local_time_estimate, drift_rate]
预测: predicted_local = w[0]*rtp_ts + w[1]
残差: residual = actual_arrival - predicted
Kalman 更新 w 和协方差
```

回绕处理：M144 用 `RtpTimestampUnwrapper`（`rtc_base/numerics/sequence_number_unwrapper.h`）展开 32 位时间戳（`timestamp_extrapolator.cc:157`），并带离群拒绝（`OutlierRejectionEnabled`，`cc:163-168`）。新流启动时用到达时间直接外推。

### 6.7 RttFilter：RTT 滤波

⚠️ **版本差异**：`VCMRttFilter` → **`RttFilter`**（`modules/video_coding/timing/rtt_filter.{h,cc}`），类名去 VCM 前缀并搬到 `timing/`。M144 结构：

```
Update (rtt_filter.cc:52):
  前几个样本直接存入 avg_rtt_/var_rtt_
  JumpDetection (cc:89): |rtt - avg| > jump_factor*stddev → 检出跳变
  DriftDetection (cc:~120): 连续同号偏差累积超 drift_factor → 检出漂移
  检出跳变/漂移 → Reset (cc:42)
  否则 EWMA 更新 avg_rtt_/var_rtt_
```

输出平滑 RTT 给 `JitterEstimator`（NACK 重传项）。

### 6.8 DecodeTimePercentileFilter：95 百分位解码时间

⚠️ **版本差异**：`VCMCodecTimer` → **`DecodeTimePercentileFilter`**（`modules/video_coding/timing/decode_time_percentile_filter.{h,cc}`），取 **95 百分位**（`kPercentile = 0.95f`，`cc:22`）——避免偶发慢解码拉高延迟，但容忍尖峰。`RequiredDecodeTimeMs`（`cc:53`）输出，喂给 `VCMTiming::EstimatedMaxDecodeTime`。

### 6.9 A/V 同步：RtpStreamsSynchronizer + StreamSynchronization

`RtpStreamsSynchronizer`（`video/rtp_streams_synchronizer2.{h,cc}`，⚠️ M144 文件名带 `2`）+ `StreamSynchronization`（`video/stream_synchronization.{h,cc}`）实现音视频同步。

```
音频作为主时钟(基准), 视频对齐音频:
  1. 测量音频/视频的相对延迟
  2. StreamSynchronization::ComputeRelativeDelay (stream_synchronization.cc:35)
     audio_delay = audio_jitter + audio_decode + playout
     video_delay = video_jitter + video_decode + render
     relative_delay = video_delay - audio_delay
  3. ComputeDelays (cc:65): 若 relative_delay 超阈值, 调整视频 min_playout_delay
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
| `PacketBuffer` | 收包线程（`packet_sequence_checker_`，`rtp_video_stream_receiver2.h:144`） | 无内部锁，调用方串行化（`packet_buffer.h:31` 类无 Mutex） |
| `FrameBuffer`（api/video） | **thread-unsafe**（`frame_buffer.h:31` 明确注释） | 由 `VideoStreamBufferController` 所在线程串行调用 |
| `VideoStreamBufferController` | decode/worker 队列 | 持有 `std::unique_ptr<FrameBuffer> buffer_`（`video_stream_buffer_controller.h:130`） |
| `FrameDecodeScheduler` | decode 队列 | 接口在 `video/frame_decode_scheduler.h`（无同名 .cc，已核实）；实现 `video/task_queue_frame_decode_scheduler.{h,cc}`，负责等待/超时唤醒（替代老版 `frame_event_` ConditionVar） |
| `JitterEstimator` | network + decode 交叉 | M144 由调用方串行化（RtpVideoStreamReceiver2 / VideoReceiveStream2 各自队列） |
| `VCMTiming` | decode + worker | `mutex_`（timing.h 各成员 `RTC_GUARDED_BY(mutex_)`） |
| `TimestampExtrapolator` | network | 无锁(单线程) |
| `RtpStreamsSynchronizer` | worker | 周期任务 |

⚠️ **版本差异**：老版 `FrameBuffer::NextFrame` 的"生产者 network 线程 + 消费者 decode 队列 + `crit_`/`frame_event_` ConditionVar"模型已不存在。M144 的 `FrameBuffer` 无锁，并发由 **`VideoStreamBufferController`（单线程持有）+ `FrameDecodeScheduler`（任务队列定时唤醒）** 解决：收包线程把帧组装好后 PostTask 给控制器线程做 `InsertFrame`，解码调度用 `TaskQueueFrameDecodeScheduler`（`video/task_queue_frame_decode_scheduler.{h,cc}`）定时唤醒，不再空转轮询。

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

`ResourceAdaptationProcessor` 在 **`call/adaptation/`**（`resource_adaptation_processor.{h,cc}`），不在 `video/adaptation/`。CPU 的 Resource 是 `EncodeUsageResource`（`video/adaptation/encode_usage_resource.{h,cc}`，包装 OveruseFrameDetector），质量是 `QualityScalerResource`，另有 `BandwidthQualityScalerResource`、`PixelLimitResource`。`BitrateConstraint`（`video/adaptation/bitrate_constraint.{h,cc}`）处理"码率不足先升后降"的限制。

### 7.3 CPU 过载检测：OveruseFrameDetector

`OveruseFrameDetector`（`video/adaptation/overuse_frame_detector.{h,cc}`）检测编码器是否过载。M144 角色是驱动 `EncodeUsageResource`（`video/adaptation/encode_usage_resource.{h,cc}`）。

#### 7.3.1 模型

```
encode_usage_percent = encode_time / frame_interval   // 编码占帧间隔百分比
// 滑动窗口统计 usage 的均值/方差, 自适应阈值
```

`OnEncodedFrame`（`overuse_frame_detector.cc:528` 附近）：每编码完一帧记录耗时。

#### 7.3.2 自适应阈值

```
// 滑动窗口 (min_frame_samples=120, h:46) 统计 encode_usage_percent
// 阈值自适应: 检测器内部维护 State { kNormal, kOveruse, kUnderuse } (cc:438)

if usage_percent >= high_encode_usage_threshold_percent(85, h:34):
    连续 high_threshold_consecutive_count(2, h:53) 个样本过阈 → kOveruse
elif usage_percent <= low_encode_usage_threshold_percent(默认 (85-1)/2=42, h:39-40):
    → kUnderuse
else:
    kNormal
```

阈值自适应：样本方差大时上调过用阈值（避免编码抖动误判过载）。

#### 7.3.3 参数

| 参数 | 默认 | 含义 |
|---|---|---|
| `high_encode_usage_threshold_percent` | 85 | 过用阈值（`overuse_frame_detector.h:34`） |
| `low_encode_usage_threshold_percent` | (high-1)/2 = 42 | 空闲阈值（`h:39-40`） |
| `frame_timeout_interval_ms` | 1500 | 帧间隔超时上限（`h:44`） |
| `min_frame_samples` | 120 | 最小样本窗口（`h:46`） |
| `high_threshold_consecutive_count` | 2 | 连续过阈次数（`h:53`） |

### 7.4 质量缩放：QualityScaler + QualityThreshold

`QualityScaler`（`modules/video_coding/utility/quality_scaler.{h,cc}`）基于编码器输出的 **QP（量化参数）** 判断质量。

#### 7.4.1 QP 阈值

`SetQpThresholds(VideoEncoder::QpThresholds)`（`quality_scaler.h:52`）双阈值，来自编码器能力：
```
thresholds_.high = codec.QpHigh()   // QP 过高 → 降级
thresholds_.low  = codec.QpLow()     // QP 低 → 升级
```

不同编码器阈值不同（VP8/VP9/H264 各有 `QpHigh`/`QpLow`）。

#### 7.4.2 算法

M144 用 **QpSmoother（EWMA 平滑）+ CheckQpTask（延迟任务）** 而非简单计数（`quality_scaler.cc:41,80`）：

```
OnEncodedFrame(qp) → 两个 QpSmoother(high路径/low路径) 各自 EWMA 平滑
CheckQpTask (cc:80, 周期检查, 同一时刻只跑一个):
  avg_qp_high = QpSmoother(high).GetAverage()
  avg_qp_low  = QpSmoother(low).GetAverage()
  if avg_qp_high > thresholds_.high:   → CheckQpResult::kDecrease (cc:302)  ⚠️已核实为错(枚举名)
  elif avg_qp_low < thresholds_.low    → kIncrease  ⚠️已核实为错(枚举名, 且为 <=)
  样本不足 kMinFramesNeededToScale(=2*30, cc:37) 不决策

> ✅ **核实结论（已对源码逐条复核）**：上文修正属实。M144 `QualityScaler::CheckQpResult` 枚举（`quality_scaler.h:66-71`）为 **`{kInsufficientSamples, kNormalQp, kHighQp, kLowQp}`**，无 `kDecrease/kIncrease`。判定（`quality_scaler.cc:302-307`）：`avg_qp_high > thresholds_.high` → `kHighQp`；`avg_qp_low <= thresholds_.low`（**`<=`**，非 `<`）→ `kLowQp`；否则 `kNormalQp`。`kMinFramesNeededToScale = 2 * 30`（`quality_scaler.cc:37`）已核实无误。`kHighQp/kLowQp` 经 `QualityScalerResourceAdaptation` 层翻译为 `adaptation::kAdaptDown`（降分辨率）——"降级/升级"是语义上的下游动作，不是 QualityScaler 枚举值本身。

```

`QualityScalerResource`（`video/adaptation/quality_scaler_resource.{h,cc}`）把 QP 过用/空闲转成 Resource 信号。

### 7.5 VideoStreamEncoderResourceManager：资源信号聚合

`VideoStreamEncoderResourceManager`（`video/adaptation/video_stream_encoder_resource_manager.{h,cc}`，已核实——不在 `video/` 顶层，在 `video/adaptation/` 子目录）是资源信号的聚合点：

```
注册的资源 (video/adaptation/):
  EncodeUsageResource (CPU, 包装 OveruseFrameDetector)
  QualityScalerResource (QP)
  BandwidthQualityScalerResource (带宽, 可选)
  PixelLimitResource (像素上限, 可选)

OnResourceUsageStateMeasured(resource, state):
  └─▶ 转发给 ResourceAdaptationProcessor (call/adaptation/)
```

它还管理**降级计数器**（`adaptation_counters_`：已降几次分辨率/帧率），限制最大降级次数，防止无限降级。

### 7.6 VideoStreamAdapter：VideoSourceRestrictions 计算

`VideoStreamAdapter`（`call/adaptation/video_stream_adapter.{h,cc}`）把"降级"转成具体的 `VideoSourceRestrictions`：

```cpp
struct VideoSourceRestrictions {
  size_t target_pixels_per_frame;         // 目标分辨率
  std::optional<size_t> max_pixels_per_frame;
  std::optional<double> max_frame_rate;    // 目标帧率
};
```

`GetAdaptationDown/Up`（`video_stream_adapter.cc:397` 附近）按降级策略算下一个 restrictions（步长常量注释在文件头 `:45,143`）：
- **降分辨率**：`target_pixels = current * 3/5`（升回去用 12/5 余量，`cc:57-71`）
- **降帧率**：`max_frame_rate = current * 2/3`（升 3/2，`cc:45`；有 `kMinFrameRateFps` 下限）

策略受 `encoder_settings_`（编码器能力）与 `DegradationPreference` 约束。

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

`EncoderBitrateAdjuster`（`video/encoder_bitrate_adjuster.{h,cc}`）平滑编码器目标码率，防过冲。M144 实现用 **utilization tracker**（`video/rate_utilization_tracker.{h,cc}`，滑窗数据点上限 `kMaxDataPointsInUtilizationTrackers=100`，`encoder_bitrate_adjuster.cc:148`）：

```
// 分 simulcast 层跟踪: link_utilization_factor(含开销) / media_utilization_factor(纯媒体)
// 目标: 让链路利用率 ≈ 1.0 (编码器实际产出对齐目标, 防过冲引发拥塞)
// overshoot 部分 = (link_utilization - max(1.0, media_utilization)) * target_rate (cc:42-53)
//   从下次目标中扣除; 仅对超时/超帧扣罚, 不奖励欠发 (欠发通常是场景内容少, 不该提码率)
```

防止编码器因目标码率突变而过冲（产出远超目标，引发拥塞）。

### 7.9 EncoderOvershootDetector：编码器过冲检测

`EncoderOvershootDetector`（`video/encoder_overshoot_detector.{h,cc}`）监控编码器是否持续产出超目标码率：

```
// 滑动窗口 (window_size_ms) 统计实际码率 vs 目标 (SetTargetRate cc:53)
// OnEncodedFrame(bytes, time) (cc:73) 累计 sum_overshoot_percent_
// 持续 overshoot → 通过 utilization 反馈给 EncoderBitrateAdjuster 压低目标
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
| `kMinFramesNeededToScale` | 60（2*30） | QP 决策最小样本（`quality_scaler.cc:37`） |
| 分辨率步长 | 3/5 降 / 12/5 升 | `video_stream_adapter.cc:57-71,143` |
| 帧率步长 | 2/3 降 / 3/2 升 | `video_stream_adapter.cc:45` |
| CPU 过用阈值 | 85% | `overuse_frame_detector.h:34` |
| CPU 空闲阈值 | 42% | `overuse_frame_detector.h:39-40` |
| `min_frame_samples` | 120 | CPU 统计窗口（`h:46`） |
| `high_threshold_consecutive_count` | 2 | 连续过阈次数（`h:53`） |

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

`AudioNetworkAdaptor`（`modules/audio_coding/audio_network_adaptor/include/audio_network_adaptor.h`）是抽象接口，实现 `AudioNetworkAdaptorImpl`（`modules/audio_coding/audio_network_adaptor/audio_network_adaptor_impl.{h,cc}`）：

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

`bitrate_controller.cc:52`（`MakeDecision`）：从目标音频码率扣除开销，算实际编码码率。

```
MakeDecision(config):
  if target_audio_bitrate and overhead_bytes_per_packet:
    frame_length = config.frame_length_ms
    offset = config.last_fl_change_increase ? fl_increase_offset : fl_decrease_offset
    overhead_rate = (overhead + offset) * 8 * 1000 / frame_length
    bitrate = max(0, target_audio_bitrate - overhead_rate)
    config.bitrate_bps = bitrate
```

帧长变化时用不同 offset 补偿开销变化（⚠️ M144 中 ANA 的开销补偿是**默认行为**，老 trial `WebRTC-SendSideBwe-WithOverhead` 已删除）。

#### 8.3.2 FrameLengthController

`frame_length_controller.cc`：`MakeDecision`（`:77`）在 20/40/60/120ms 间切换帧长。

**增长帧长**（`FrameLengthIncreasingDecision`，`frame_length_controller.cc:103`）：
```
// 防过用: 带宽极紧时长帧(降开销)
if uplink_bandwidth <= min_encoder_bitrate(6000) + 5000 + OverheadRate(current_fl):
    switch to longer frame_length; return true
// 带宽+丢包阈值
if uplink_bandwidth <= increase_threshold(fl_changing_bandwidths) and
   packet_loss <= fl_increasing_packet_loss_fraction:
    switch to longer; return true
```

**缩短帧长**（`FrameLengthDecreasingDecision`，`frame_length_controller.cc:159`）：
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

`dtx_controller.cc:36`（`MakeDecision`）：基于带宽开关 DTX。

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

`fec_controller_plr_based.cc:66`（`MakeDecision`）：基于丢包率开关 FEC，用**滞回阈值曲线**。

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

`channel_controller.cc:47`（`MakeDecision`）：单声道↔立体声切换。

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

`ControllerManagerImpl`（`controller_manager.cc:352` `GetSortedControllers`）决定 controller 执行顺序，用**评分点距离**动态重排。

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

`SquaredDistanceTo`（`controller_manager.cc:437`，归一化上限 `kMaxUplinkBandwidthBps=120000` 在 `:419`）：
```
norm_bw = bw / 120000          // 归一化 [0,1]
norm_loss = min(loss * 3.333, 1)
dist = (Δnorm_bw)² + (Δnorm_loss)²
```

离当前网络状态近的 controller 先执行——让最相关的 controller 先决策，影响后续。

#### 8.4.2 帧长变化与开销

`FrameLengthController` 决定帧长后，`last_fl_change_increase` 标志传给 `BitrateController`，后者用对应 offset 补偿开销。`kPreventOveruseMarginBps=5000`（`frame_length_controller.cc:26`）是防过用余量（使用处 `:140,187`）。

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
AudioSendStream::Reconfigure (audio/audio_send_stream.cc:195) / ReconfigureSendCodec (:658)
  └─▶ AudioEncoderOpusImpl::EnableAudioNetworkAdaptor(config) (audio_encoder_opus.cc:482)
        └─▶ DefaultAudioNetworkAdaptorCreator
              └─▶ ControllerManagerImpl::Create(config, ...)

网络反馈到达:
  AudioEncoderOpusImpl::OnReceivedUplinkBandwidth (:546) / OnReceivedUplinkPacketLossFraction (:491) / Rtt / Overhead
    └─▶ audio_network_adaptor_->SetUplinkBandwidth/SetUplinkPacketLossFraction/SetRtt/...
          └─▶ ApplyAudioNetworkAdaptor() (编码时, audio_encoder_opus.cc:762 取 config)
                └─▶ GetEncoderRuntimeConfig()  // 遍历 sorted controllers
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
- `WebRTC-AdjustOpusBandwidth`：Opus 带宽自动调整（`audio_encoder_opus.cc`，M144 实测存在）
- ⚠️ 老版 `WebRTC-SendSideBwe-WithOverhead`、`WebRTC-Audio-StableTargetAdaptation`、`UseTwccPlrForAna` 在 M144 树中已**不存在**——ANA 开销扣除已成默认行为，勿再引用

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
struct NetworkControlUpdate {           // GCC 输出 (network_types.h:280)
  std::optional<DataSize> congestion_window;
  std::optional<PacerConfig> pacer_config;
  std::vector<ProbeClusterConfig> probe_cluster_configs;
  std::optional<TargetTransferRate> target_rate;
  bool has_updates() const;             // 任一成员有值即 true
};
```

#### 9.2.2 TransportPacketsFeedback

```cpp
struct TransportPacketsFeedback {       // GCC 输入(TWCC 反馈) (network_types.h:194)
  Timestamp feedback_time;
  DataSize data_in_flight;
  bool transport_supports_ecn;
  std::vector<PacketResult> packet_feedbacks;
  TimeDelta smoothed_rtt;               // RFC6298 EWMA, alpha=1/8
  std::vector<Timestamp> sendless_arrival_times;
  // 辅助: ReceivedWithSendInfo()/LostWithSendInfo()/SortedByReceiveTime()/HasPacketWithEcnCe()
};
```

#### 9.2.3 SentPacket / PacketResult

```cpp
struct SentPacket {                     // 发送侧记录 (network_types.h:110)
  Timestamp send_time;
  DataSize size;                        // 含到 IP 层的开销
  DataSize prior_unacked_data;
  PacedPacketInfo pacing_info;          // 探测簇信息
  bool audio;
  int64_t sequence_number;              // 全 call 递增 transport seq
  DataSize data_in_flight;              // 发送时在途数据
};
struct PacketResult {                   // 反馈结果 (network_types.h:157)
  SentPacket sent_packet;
  Timestamp receive_time = Timestamp::PlusInfinity();   // ∞ = 丢失
  EcnMarking ecn;
  std::optional<RtpPacketInfo> rtp_packet_info;         // ssrc/seq/is_retransmission
  bool IsReceived() const { return !receive_time.IsPlusInfinity(); }   // :173
};
```

#### 9.2.4 TargetTransferRate / PacerConfig / ProbeClusterConfig

```cpp
struct TargetTransferRate {            // 目标码率 (network_types.h:269)
  Timestamp at_time;
  NetworkEstimate network_estimate;    // 链路估计(带宽/RTT)
  DataRate target_rate;
  double cwnd_reduce_ratio;            // cwnd pushback 降码率比例
};
struct PacerConfig {                    // Pacer 配置 (network_types.h:235)
  DataSize data_window;                // 信用窗口(时间×速率)
  DataRate rate_window;
  DataSize pad_window;                 // padding 窗口
  DataRate data_rate() / pad_rate();   // 派生速率
};
struct ProbeClusterConfig {            // 探测簇 (network_types.h:258)
  Timestamp at_time;
  DataRate target_data_rate;
  TimeDelta target_duration;
  TimeDelta min_probe_delta = 2ms;     // 突发间隔下限
  int32_t target_probe_count;
  int32_t id;
};
```

### 9.3 BWE 结构

```cpp
enum class BandwidthUsage { kNormal, kOverusing, kUnderusing };  // 过用状态

struct RateControlInput {              // AIMD 输入
  BandwidthUsage bw_state;
  absl::optional<DataRate> estimated_throughput;
  Timestamp at_time;                  /// ⚠️已核实为错 —— M144 无 at_time
};

> ✅ **核实结论（已对源码逐条复核）**：上文修正属实。M144 `RateControlInput`（`modules/remote_bitrate_estimator/include/bwe_defines.h:38-45`）只有 `bw_state`、`estimated_throughput` 两个成员，**没有 `at_time`**（时间由调用方 `AimdRateControl::Update(input, at_time)` 单独传入）；且用 `std::optional`（非 `absl::optional`）。

### 9.4 Pacing 结构

⚠️ `StreamPrioKey` 已随 RoundRobinPacketQueue 删除（M144 用 PrioritizedPacketQueue 的固定 5 级 + StreamQueue）。

```cpp
struct ProbeCluster {                  // 探测簇 (bitrate_prober.h:100 附近)
  PacedPacketInfo pace_info;           // probe_cluster_id/send_bitrate/min_probes/min_bytes
  Timestamp started_at;
  TimeDelta min_probe_delta;
  int sent_probes;
  int sent_bytes;
};

class IntervalBudget {                 // 区间预算(ALR/探测) (modules/pacing/interval_budget.h:21)
  int64_t target_rate_kbps_;   /// ⚠️已核实为错 —— 实为 int target_rate_kbps_;
  int64_t bytes_remaining_;
  bool can_build_up_underuse_;
  void UpdateBudget(int64_t delta_time_ms);   /// ⚠️已核实为错 —— 实为 IncreaseBudget
};
```

> ✅ **核实结论（已对源码逐条复核）**：上文修正属实。M144 `IntervalBudget`（`modules/pacing/interval_budget.h:21`）成员 `target_rate_kbps_` 类型为 **`int`**（`h:36`），方法名为 **`IncreaseBudget(int64_t delta_time_ms)`**（`h:28`，源文件 `h:27` 有 TODO 注释计划把它和 `UseBudget` 合并），并非 `UpdateBudget`。


### 9.5 分配结构

```cpp
struct MediaStreamAllocationConfig {   // 流分配配置 (call/bitrate_allocator.h:56)
  uint32_t min_bitrate_bps;
  uint32_t max_bitrate_bps;
  uint32_t max_padding_bitrate_bps;   /// ⚠️已核实为错 —— 实为 pad_up_bitrate_bps
  double bitrate_priority;             // 优先级 (h:71)
  bool enforce_min_bitrate;
  int track_id;                       /// ⚠️已核实为错 —— 无此字段
};
```

> ✅ **核实结论（已对源码逐条复核）**：上文修正属实。M144 `MediaStreamAllocationConfig`（`call/bitrate_allocator.h:56-73`）无 `max_padding_bitrate_bps`、无 `track_id`；真实字段是：
> `min_bitrate_bps`、`max_bitrate_bps`（uint32_t）、`pad_up_bitrate_bps`(uint32_t)、`priority_bitrate_bps`(int64_t)、`enforce_min_bitrate`、`bitrate_priority`(double)、`rate_elasticity`(`std::optional<TrackRateElasticity>`)。
> 另有 `enum TrackRateElasticity { kCanContributeUnusedRate, kCanConsumeExtraRate, kCanContributeAndConsume }`（`bitrate_allocator.h:50-54`）；分配器常量 `kToggleFactor=0.1`、`kMinToggleBitrateBps=20000`（`bitrate_allocator.h:47-49`）已核实。

struct BitrateAllocationLimits {        // 分配上限 (api/transport/network_types.h:33)
  DataRate min_total_allocated;
  DataRate max_total_allocated;
  DataRate max_padding_rate;
};

struct BitrateAllocationUpdate {       // 分配更新(给流) (api/call/bitrate_allocation.h:21)
  DataRate target_bitrate;
  double packet_loss_ratio;
  TimeDelta round_trip_time;
  TimeDelta bwe_period;                // 已 deprecated (TODO: 删除)
  double cwnd_reduce_ratio;            // cwnd pushback 降码率比例(丢帧用)
};
```

### 9.6 抖动结构

⚠️ **版本差异**：老版 `FrameInfo`/`VideoLayerFrameId`（frame_buffer2）已删除。M144 对应：

```cpp
struct FrameInfo {                     // 帧信息 (api/video/frame_buffer.h:73)
  std::unique_ptr<EncodedFrame> encoded_frame;   // 依赖/层信息在 EncodedFrame 内
  bool continuous;
};
using FrameMap = std::map<int64_t, FrameInfo>;   // int64_t frame id (h:78)

// 帧间延迟: InterArrivalDelta (goog_cc 路径, modules/congestion_controller/goog_cc/inter_arrival_delta.h)
struct InterArrivalDelta {              // 注: M144 goog_cc 用 InterArrivalDelta
  // 输出 {send_time_delta, arrival_time_delta, packet_size_delta} 三元组
};

// 视频接收侧帧间延迟: InterFrameDelayVariationCalculator
// (modules/video_coding/timing/inter_frame_delay_variation_calculator.{h,cc})
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
│  controller task queue  (无名, TaskQueueBase::Current(),            │
│                          即构造线程/network 线程, 已核实)           │
│    └─ GCC (GoogCcNetworkController), BitrateAllocator            │
│       TransportFeedbackAdapter                                    │
├─────────────────────────────────────────────────────────────────┤
│  pacer task queue      ("pacer")                                  │
│    └─ PacingController, PrioritizedPacketQueue, BitrateProber      │
│       PacketRouter                                                │
├─────────────────────────────────────────────────────────────────┤
│  encoder task queue    ("EncoderQueue")                           │
│    └─ VideoStreamEncoder, OveruseFrameDetector, QualityScaler    │
│       ResourceAdaptationProcessor, EncoderBitrateAdjuster        │
├─────────────────────────────────────────────────────────────────┤
│  decode queue          (VideoReceiveStream2::decode_queue_,      │
│                          video_receive_stream2.h:380)             │
│    └─ VideoStreamBufferController/FrameBuffer, Decoder, VCMTiming │
├─────────────────────────────────────────────────────────────────┤
│  worker thread 周期任务 (RepeatingTaskHandle, call.cc:751-753)   │
│    └─ ReceiveSideCongestionController::MaybeProcess               │
│  NackPeriodicProcessor (20ms RepeatingTask, worker thread)        │
│    └─ NackRequester::ProcessNacks                                │
└─────────────────────────────────────────────────────────────────┘
```

### 10.2 controller task queue（GCC 运行）

`RtpTransportControllerSend::task_queue_`（`rtp_transport_controller_send.cc:105`：`task_queue_(TaskQueueBase::Current())`）。⚠️已核实为错：无 `"rtp_send_controller"` 命名队列，控制器跑在构造它的线程/TaskQueue（network 线程）。

- **运行**：`GoogCcNetworkController` 全部逻辑、`BitrateAllocator`、`TransportFeedbackAdapter`
- **驱动**：
  - `RepeatingTaskHandle` 每 25ms 调 `OnProcessInterval`（周期处理，`StartProcessPeriodicTasks`，`rtp_transport_controller_send.cc:843-864`）
  - TWCC 反馈到达 → `PostTask(OnTransportPacketsFeedback)`
  - pacer 队列监控独立 25ms 周期（`kPacerQueueUpdateInterval`，`:71`）
- **保证**：串行由 `RTC_DCHECK_RUN_ON(&sequence_checker_)`（`sequence_checker_`）保证，非 `task_queue_` 上的 DCHECK（已核实）

> ✅ **核实结论（已对源码逐条复核）**：构造函数 `task_queue_(TaskQueueBase::Current())`（`rtp_transport_controller_send.cc:105`），全树 grep 无 `"rtp_send_controller"` 字符串；25ms 周期来自 `process_interval_`（GoogCC 工厂 `api/transport/goog_cc_factory.cc:52-53` `kUpdateIntervalMs=25`）。

设计：**单队列串行**，把并发控制交给调度者，而非每方法加锁。GCC 算法有状态（AIMD、趋势线窗口），串行避免状态竞争。

### 10.3 pacer task queue（PacingController 运行）

`TaskQueuePacedSender::task_queue_`（`"pacer"`）。

- **运行**：`PacingController`、`PrioritizedPacketQueue`、`BitrateProber`
- **驱动**：
  - `EnqueuePackets`/`SetPacingRates` → `PostTask`
  - `MaybeProcessPackets` 动态调度：发完一批算 `NextSendTime`，`PostDelayedTask` 唤醒（holdback 窗口合并）
- **保证**：`RTC_DCHECK_RUN_ON(task_queue_)`

设计：**独立队列**，发送路径不被 GCC/编码器阻塞。Pacer 是发送关键路径，精确节奏要求高，独立队列保证 5ms 级精度。

### 10.4 decode queue（FrameBuffer/解码）

`VideoReceiveStream2::decode_queue_`（`video/video_receive_stream2.h:380`）。

- **运行**：`VideoStreamBufferController` + `FrameBuffer`（提取可解码时间单元）、`Decoder::Decode`、`VCMTiming`
- **驱动**：`FrameDecodeScheduler`（`video/task_queue_frame_decode_scheduler.{h,cc}`）按解码时间 **`PostDelayedHighPrecisionTask`**（`task_queue_frame_decode_scheduler.cc`，已核实——普通 `PostDelayedTask` 精度不足，解码唤醒需要高精度定时）精确唤醒，不轮询
- **并发**：`FrameBuffer` 无锁（thread-unsafe），由控制器所在 decode queue 串行化；收包线程组帧后 PostTask 过来

设计：**生产者-消费者**。收包线程生产时间单元，decode queue 消费。分离避免解码阻塞收包。

### 10.5 接收侧 CC 周期驱动（⚠️ ProcessThread 已删除）

⚠️ **版本差异**：老版 `ProcessThread`（`modules/include/module.h`）在 M144 **已完全删除**（全树无 `class ProcessThread`）。替代：

- `ReceiveSideCongestionController::MaybeProcess`（返回下次该处理的时间）由 **`Call` 在 worker thread 上的 `RepeatingTaskHandle` 周期驱动**（`call/call.cc:751-753`），内部驱动 `TransportSequenceNumberFeedbackGenenerator`（TWCC 反馈）与 REMB
- `NackRequester::ProcessNacks` 由 `NackPeriodicProcessor` 的 20ms `RepeatingTaskHandle` 驱动（`nack_requester.cc:60-70`），跑在 worker thread
- RTCP 周期发送由各 RtpRtcp 模块自身的定时逻辑（`ModuleRtpRtcpImpl2`，`rtp_rtcp_impl2.cc:340` `TimeToSendRTCPReport`）+ 调用方周期任务驱动

### 10.6 network thread 与 worker thread

- **network thread**：RTP/RTCP 收发。`RtpVideoStreamReceiver2::OnRtpPacket`、`RTCPReceiver`、`FlexfecReceiver::OnRtpPacket`（⚠️ `NackRequester::OnReceivedPacket` 实际跑在 worker thread，见 5.2.4）
- **worker thread**：`Call`/流管理。`VideoStreamEncoder` 生命周期、`RtpStreamsSynchronizer`（A/V 同步）

### 10.7 跨线程同步机制

| 机制 | 用途 | 例子 |
|---|---|---|
| **Mutex (`mutex_`)** | 互斥 | `UlpfecGenerator::pending_params_`、`VCMTiming` 各成员、`FecControllerDefault` |
| **RaceChecker** | 同线程串行(非严格线程亲和) | `UlpfecGenerator` FEC 生成、`DelayBasedBwe` |
| **SequenceChecker** | 单线程断言(调试) | `FlexfecReceiver`、`LossNotificationController`、`BitrateAllocator` |
| **TaskQueue 投递** | 跨线程无锁通信 | GCC→Pacer `PostTask`、编码器→pacer、收包→decode queue |
| **`pending_params_` 无锁交接** | 生产者-消费者参数 | `UlpfecGenerator` 参数设置→生成 |
| **PostDelayedTask 定时唤醒** | 等待/唤醒 | `FrameDecodeScheduler` 解码调度、pacer `PostMaybeProcessPackets`（替代老版 ConditionVar `frame_event_`） |
| **线程亲和 (`RTC_DCHECK_RUN_ON`)** | 状态串行化 | `NackRequester`(worker)、`PacingController`(pacer)、GCC(controller queue) |

### 10.8 线程亲和 vs 锁的取舍

WebRTC 偏好**线程亲和**（thread affinity）而非锁：

- **优点**：无锁竞争，高性能；状态访问天然串行，避免数据竞争
- **实现**：`RTC_DCHECK_RUN_ON(queue_)` 断言某方法必须在某队列运行；跨线程调用必须 `PostTask`
- **代价**：API 使用门槛高（必须知道在哪个队列调用）；调试链路长

**锁的适用场景**：
- 简单参数交接（`pending_params_`）
- 少量跨线程读写（`VCMTiming` 被 decode/worker 交叉访问，用 `mutex_`）
- 保护小临界区（`FecControllerDefault` 的 loss_prot_logic_）

**演进趋势**：M144 已彻底移除 ProcessThread 与 ConditionVar 等待模型——新代码用 TaskQueue + SequenceChecker + PostDelayedTask 定时唤醒，核心 QoS 路径（GCC/Pacer/Adaptation/NACK/解码调度）全部在 TaskQueue 模型上。

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
  const std::unique_ptr<AlrDetector> alr_detector_;     /// ⚠️已核实为错 —— 实为值成员 AlrDetector alr_detector_;
  const std::unique_ptr<ProbeBitrateEstimator> probe_bitrate_estimator_;
  const std::unique_ptr<AcknowledgedBitrateEstimator> acknowledged_bitrate_estimator_;  /// ⚠️已核实为错 —— 实为 std::unique_ptr<AcknowledgedBitrateEstimatorInterface>
  const std::unique_ptr<CongestionWindowPushbackController> congestion_window_pushback_controller_;
  // ...
};
```

> ✅ **核实结论（已对源码逐条复核）**：上文修正属实。M144 `goog_cc_network_control.h:87-107` 的成员并非都是 `const std::unique_ptr`：
> - `AlrDetector alr_detector_;` 是**普通值成员**（非指针，`h:101`）。
> - `bandwidth_estimation_`、`delay_based_bwe_`、`probe_controller_`、`probe_bitrate_estimator_`、`network_estimator_`、`network_state_predictor_`、`acknowledged_bitrate_estimator_`、`congestion_window_pushback_controller_` 是 `std::unique_ptr`；其中 `acknowledged_bitrate_estimator_` 的类型是接口 **`AcknowledgedBitrateEstimatorInterface`**（`h:106-107`），非具体类 `AcknowledgedBitrateEstimator`。
> - 算术上非"8 个 uniform unique_ptr"——是 7 个 unique_ptr + 1 个值成员（不含可选实验组件时）。

**设计**：组合模式，父独占子，生命周期绑定。子组件不可共享，避免多父竞争。析构顺序确定（成员逆序析构）。

#### 11.1.2 scoped_refptr 共享

跨模块共享的对象用 `scoped_refptr`（引用计数）：
- `RtpTransportControllerSend` 被 `Call` 和多个 `VideoSendStream` 共享
- `Pacer` 被多个 `RtpRtcp` 模块共享

`scoped_refptr` 的线程安全：引用计数原子操作，但**对象本身在创建线程销毁**（`scoped_refptr` 设计哲学）。

#### 11.1.3 所有权图

```
Call (拥有)
  ├─ RtpTransportControllerSend (成员, rtp_transport_controller_send.h)
  │     ├─ unique_ptr<NetworkControllerInterface> = GoogCcNetworkController (GCC)
  │     │     ├─ unique_ptr<SendSideBandwidthEstimation>     (含 LossBasedBweV2)
  │     │     ├─ unique_ptr<DelayBasedBwe>                   (delay_based_bwe.h:121-125)
  │     │     │     ├─ unique_ptr<DelayIncreaseDetectorInterface> (视频/音频各一, 即 TrendlineEstimator)
  │     │     │     └─ (AimdRateControl 在 DelayBasedBwe 内)
  │     │     ├─ unique_ptr<ProbeController>
  │     │     └─ ... (AlrDetector, AcknowledgedBitrateEstimator, CongestionWindowPushbackController 等)
  │     ├─ BitrateAllocator (成员)
  │     └─ TaskQueuePacedSender pacer_ (成员, rtp_transport_controller_send.h:205)
  │           └─ PacingController pacing_controller_ (成员, task_queue_paced_sender.h:154)
  │                 └─ PrioritizedPacketQueue packet_queue_ (成员, pacing_controller.h:281)
  ├─ VideoSendStream (每流, 工厂 Create/DestroyVideoSendStream 管理)
  │     └─ VideoStreamEncoder
  │           └─ ResourceAdaptationProcessor + VideoStreamEncoderResourceManager
  └─ VideoReceiveStream2 (每流)
        └─ decode_queue_ (video_receive_stream2.h:380)
              └─ VideoStreamBufferController
                    └─ unique_ptr<FrameBuffer> (api/video/frame_buffer.h)
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
| Pacer `MaybeProcessPackets` | 动态（按 `NextSendTime` 延迟任务） | 发送节奏控制 |
| TWCC 反馈 | 50-250ms（动态） | 到达时间反馈 |
| NackRequester `ProcessNacks` | 20ms | NACK 重传请求 |
| 接收侧 CC `MaybeProcess` | 动态（worker thread RepeatingTask） | REMB/TWCC 反馈节拍 |
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

关键 field trials（M144 实测存在的名字）：
- `WebRTC-Bwe-LossBasedBweV2`：丢包 BWE v2（`loss_based_bwe_v2.cc:520`）⚠️ 老名 `WebRTC-Bwe-LossBasedControl` 已不存在
- `WebRTC-Bwe-MaxRttLimit`：RTT 回退（`send_side_bandwidth_estimation.cc:127`）
- `WebRTC-SendNackDelayMs`：NACK 首发延迟（`nack_requester.cc:46`）⚠️ `WebRTC-ExponentialNackBackoff` 已删除
- `WebRTC-AlrDetectorParameters`：ALR 参数（`alr_detector.cc`）
- `WebRTC-Pacer-DrainQueue/PadInSilence/BlockAudio/IgnoreTransportOverhead`：Pacer 参数（`pacing_controller.cc:63-68`）
- `WebRTC-Bwe-MinAllocAsLowerBound` / `WebRTC-Bwe-IgnoreProbesLowerThanNetworkStateEstimate` / `WebRTC-Bwe-LimitProbesLowerThanThroughputEstimate` / `WebRTC-Bwe-LimitPacingFactorByUpperLinkCapacityEstimate`（`goog_cc_network_control.cc:95-105`）
- `WebRTC-Bwe-SafeResetOnRouteChange`（`goog_cc_network_control.cc:141`）
- `WebRTC-AdjustOpusBandwidth`：Opus 带宽自动调整（`audio_encoder_opus.cc:386`）
- `WebRTC-JitterEstimatorConfig`：抖动估计器参数（`modules/video_coding/timing/jitter_estimator.h`）

⚠️ **音频开销扣除**：老 trial `WebRTC-SendSideBwe-WithOverhead` 已删除——M144 的 `BitrateController` **默认**就做开销扣除（`modules/audio_coding/audio_network_adaptor/bitrate_controller.cc`，`UpdateNetworkMetrics` `:46-49` 收 `overhead_bytes_per_packet`，`MakeDecision` `:52-68` 计算 `overhead_rate` 并从 `target_audio_bitrate_bps` 扣除），不再由开关控制。

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

3. 接收侧反馈 (TransportSequenceNumberFeedbackGenenerator)
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

**关键模块交互**：`ProbeController`（调度）→ `BitrateProber`（发送）→ `TransportSequenceNumberFeedbackGenenerator`（反馈）→ `ProbeBitrateEstimator`（估计）→ `DelayBasedBwe`（采纳）→ `AimdRateControl`（稳定）→ `BitrateAllocator`（分配）。

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
1. NACK 检测与重传 (NackRequester)
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
   ┌─ nack_list > 1000 → NackRequester 清空并请求关键帧 (nack_requester.cc:241-247)
   └─ LossNotificationController: 依赖不可解码 → RequestKeyFrame

6. 接收端 FEC 恢复
   ┌─ FlexfecReceiver/UlpfecReceiver: DecodeFec → AttemptRecovery
   ├─ 若缺 1 包: XOR 恢复
   └─ 恢复包标记 is_recovered, 不触发 NACK
```

**关键模块交互**：`NackRequester`（检测）→ RTX（重传）+ `SendSideBandwidthEstimation`（降码率）+ `FecControllerDefault`（增 FEC）+ `ForwardErrorCorrection`（恢复）。

**参数作用**：`low_loss_threshold=2%`、`high_loss_threshold=10%`、`kLowRttNackMs=20ms`（NACK/FEC 切换）、`kMaxNackPackets=1000`（关键帧回退）、FEC 掩码表（bursty/random）。

### 12.5 场景五：网络抖动增大

**场景**：网络延迟方差增大（路由波动、队列抖动），接收端需增大缓冲延迟抗卡顿。

**算法作用过程**：

```
1. 抖动估计上升 (JitterEstimator)
   ┌─ 帧到达时间方差增大
   ├─ Kalman: varNoise_ EWMA 上升
   ├─ residual 增大 → 测量噪声 R 增大
   └─ jitter = θ₀×(maxSize−avgSize) + kNoiseStdDevs(2.33)×sqrt(varNoise_) 上升

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

**关键模块交互**：`JitterEstimator`（估计）→ `VCMTiming`（目标延迟）→ `TimestampExtrapolator`（时间映射）→ `RtpStreamsSynchronizer`（A/V 同步）→ 可能 `TrendlineEstimator`（若伴随延迟梯度）。

**参数作用**：`kNoiseStdDevs=2.33`（噪声倍数，jitter_estimator.cc:62）、`kNumStdDevDelayOutlier=15`（离群点判定）、速率限制 `kDelayMaxChangeMsPerS=100ms/s`（timing.h:60）、`render_delay=10ms`（timing.h:59）。

### 12.6 场景六：CPU 过载

**场景**：设备 CPU 紧张，编码耗时超过帧间隔，编码器跟不上。

**算法作用过程**：

```
1. CPU 过载检测 (OveruseFrameDetector)
   ┌─ 每帧记录 encode_usage_percent (编码耗时占帧间隔百分比)
   ├─ 滑动窗口统计 (min_frame_samples=120, frame_timeout 1500ms)
   ├─ encode_usage > 85% 连续 2 次(high_threshold_consecutive_count): kOveruse
   ├─ encode_usage < (85-1)/2 = 42%: kUnderuse
   └─ EncodeUsageResource 传播信号

2. 视频降级 (ResourceAdaptationProcessor)
   ┌─ 收到 kOveruse
   ├─ VideoStreamAdapter::GetAdaptationDown
   ├─ 按 DegradationPreference:
   │    BALANCED: 先降帧率(2/3) 再降分辨率(3/5)
   │    MAINTAIN_FRAMERATE: 只降分辨率(3/5)
   │    MAINTAIN_RESOLUTION: 只降帧率(2/3)
   ├─ VideoSourceRestrictions{pixels, fps}
   └─ VideoSource::AddOrUpdateSink → 采集源降分辨率/帧率

3. 编码器收到更小/更少帧
   ┌─ 编码耗时下降
   ├─ encode_usage_percent 下降
   └─ 若 < 42%: emit kUnderuse → 升级

4. 码率可能调整
   ┌─ 降分辨率/帧率后, 实际码率需求下降
   └─ EncoderBitrateAdjuster 平滑调整
```

**关键模块交互**：`OveruseFrameDetector`（检测）→ `EncodeUsageResource`（信号）→ `ResourceAdaptationProcessor`（决策）→ `VideoStreamAdapter`（算 restrictions）→ `VideoStreamEncoder`（应用）→ 采集源。

**参数作用**：`high_encode_usage_threshold_percent=85`、`low_encode_usage_threshold_percent=(85-1)/2=42`、`min_frame_samples=120`、`high_threshold_consecutive_count=2`、`min_process_count=3`（overuse_frame_detector.h:32-53）；分辨率步长 `3/5`（VideoStreamAdapter）、帧率步长 `2/3`。

### 12.7 场景七：网络切换/路由变化

**场景**：网络切换（WiFi→4G）或路由变化，RTT/带宽突变。

**算法作用过程**：

```
1. RTT 突变检测
   ┌─ TWCC 反馈 RTT 突变
   ├─ feedback_max_rtts_ 滚动窗口捕获新 RTT
   └─ RttFilter 检测跳变 → 重置 (timing/rtt_filter.cc)

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
   ┌─ JitterEstimator: FPS<10Hz 时缩放 jitter (5-10Hz 线性插值, <5Hz 归零)
   ├─ 低帧率(5fps): 抖动估计放大
   └─ VCMTiming: TargetDelay 可能偏大

4. SVC 丢非基础层
   ┌─ 发送侧: SvcRateAllocator (modules/video_coding/svc/svc_rate_allocator.cc)
   │    低码率低于层激活阈值(FindLayerTogglingThreshold 二分查找) → 高层置 0
   ├─ 接收侧: FrameBuffer 只影响解码依赖 (非基础层帧依赖基础层)
   └─ 带宽不足时只保留基础层

5. FEC 策略
   ┌─ BitRateTooLowForFec: 码率太低关 FEC
   └─ 依赖 NACK (若 RTT 低)
```

**关键模块交互**：`AlrDetector` + `ProbeController`（ALR 探测）+ `JitterEstimator`（FPS 缩放）+ `FrameBuffer`（SVC 时间单元依赖）+ `FecControllerDefault`（低码率关 FEC）。

### 12.10 各场景模块交互时序总结

| 场景 | 主导模块 | 辅助模块 | 关键算法 |
|---|---|---|---|
| 启动爬坡 | ProbeController, BitrateProber | ProbeBitrateEstimator, AIMD | 指数探测 3x/6x/2x |
| 带宽骤降 | TrendlineEstimator, AIMD | PacingController, Pushback | 乘性减少 beta=0.85 |
| 带宽恢复 | AIMD, AlrDetector | ProbeController | 加性增加 + ALR 探测 |
| 高丢包 | NackRequester, SendSideBWE | FecController, RTX | NACK 重传 + FEC + 降码率 |
| 抖动增大 | JitterEstimator | VCMTiming, A/V sync | Kalman 抖动 + 速率限制 |
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
- `PccNetworkControllerFactory`（`modules/congestion_controller/pcc/pcc_factory.h:21`）→ `PccNetworkController`（PCC 算法）
- `ScreamNetworkControllerFactory`（`modules/congestion_controller/scream/`，含 SCReAM v2）→ `ScreamNetworkController`
- 自定义工厂 → 自定义 BWE（Android 经 `NetworkControllerFactoryFactory` 注入）

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

`internal::Call` 实现并注册为 `TargetTransferRateObserver`（`call.cc:801` `RegisterTargetTransferRateObserver(this)`），GCC 输出 target rate 时通知它，再经 `CongestionControlHandler`（`modules/congestion_controller/rtp/control_handler.h:29`）通知 pacer。`VideoSendStream`/`AudioSendStream` 注册为 `BitrateAllocatorObserver`，分配时通知。

**解耦**：GCC 不知道谁消费码率，BitrateAllocator 不知道谁用码率。观察者模式实现单向依赖。

### 13.4 状态机模式：AIMD / 探测 / 自适应

多个组件用状态机驱动：

- **`AimdRateControl`**：kRcHold/kRcIncrease/kRcDecrease 三态（aimd_rate_control.h:70），状态转换由 `BandwidthUsage` 驱动
- **`ProbeController`**：kInit/kWaitingForProbingResult/kProbingComplete 三态
- **`TrendlineEstimator`**：Normal/Overusing/Underusing 三态
- **`OveruseFrameDetector`**：经 `ResourceUsageState`（kOveruse/kUnderuse，api/adaptation/resource.h:24）上报，由 EncodeUsageResource 转为资源信号

状态机模式优势：**行为确定、转换条件明确、防震荡**。每个状态有明确的进入/退出条件，控制逻辑清晰。

### 13.5 组合模式：GoogCcNetworkController 组合子组件

`GoogCcNetworkController` 用组合（非继承）聚合 8 个子组件：

```cpp
class GoogCcNetworkController : public NetworkControllerInterface {  // goog_cc_network_control.h:46
  const std::unique_ptr<ProbeController> probe_controller_;              // :51
  const std::unique_ptr<CongestionWindowPushbackController> ..._;        // :52
  std::unique_ptr<SendSideBandwidthEstimation> bandwidth_estimation_;    // :55 (含 LossBasedBweV2 + RttBasedBackoff)
  AlrDetector alr_detector_;                                             // :56
  std::unique_ptr<DelayBasedBwe> delay_based_bwe_;                       // :60 (内含 AimdRateControl)
  std::unique_ptr<ProbeBitrateEstimator> probe_bitrate_estimator_;       // :102
  std::unique_ptr<NetworkStateEstimator> network_estimator_;             // :103 (实验性)
};
```

`OnTransportPacketsFeedback` 协调子组件调用顺序（TrendlineEstimator 在 `DelayBasedBwe` 内部）。**组合优于继承**：每个子组件独立可测、可替换，GoogCcNetworkController 是协调者而非巨型类。

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
class ReceiveSideCongestionController {  // 外观 (receive_side_congestion_controller.h:88-107)
  bool send_rfc8888_congestion_feedback_;
  TransportSequenceNumberFeedbackGenenerator transport_sequence_number_feedback_generator_;   // TWCC
  CongestionControlFeedbackGenerator congestion_control_feedback_generator_;                  // RFC8888
  std::unique_ptr<RemoteBitrateEstimator> rbe_;   // PickEstimator 选中 (REMB legacy 路径)
  RembThrottler remb_throttler_;                   // REMB 节流
  // 对外暴露 OnReceivedPacket/MaybeProcess, 内部协调子组件
};
```

外观模式：简化复杂子系统接口。调用方只需 `OnReceivedPacket`/`MaybeProcess`，不需知道 TWCC/RFC8888/BWE/REMB 节流的协作。

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

#### 14.2.4 legacy 遗留代码

⚠️ **版本差异**：老版本（≈M105-M125）长期新旧并存（`NackModule`/`NackRequester`、`PacedSender`/`TaskQueuePacedSender`、`ProcessThread`/TaskQueue 三套）。**M144 已完成大清理**：

- `PacedSender`、`ProcessThread`/`modules/include/module.h`、`NackModule`、`RtcpFeedbackBuffer`、`rtp_streams_synchronizer`(一代)、`RemoteEstimatorProxy` 已**整体删除**，不再双路径
- 残留的 deprecated 代码集中在 `modules/video_coding/deprecated/`（`VCMJitterBuffer`、旧 `FrameBuffer`）——仅 APM/网真旧调用方使用，正常视频链路不经过
- 历史包袱仍在：TWCC 与 REMB 双反馈路径并存（legacy 互通）、接收侧 Kalman BWE（REMB 路径）与发送侧 Trendline BWE 并存

#### 14.2.5 接口层级深

- `NetworkControllerInterface` 12 回调，`GoogCcNetworkController` 组合多个子组件（probe/pushback/bandwidth_estimation/alr/delay_based_bwe/probe_bitrate_estimator/network_estimator），每个子组件又有内部结构
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
