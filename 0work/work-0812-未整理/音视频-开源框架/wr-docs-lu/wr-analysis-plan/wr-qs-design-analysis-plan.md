# WebRTC QoS 设计分析计划

## 目标
深入分析 WebRTC 的 QoS（服务质量）子系统：拥塞控制（GCC）、带宽估计（BWE）、Pacing、码率分配、丢包恢复（NACK/FEC）、抖动缓冲、视频自适应、音频网络适配。结合文件与代码，讲解入口、架构、文件作用、数据流图、分层控制流图、模块交互、类图、核心数据结构、设计方式、线程架构、内存/控制架构、算法设计、内部原理、参数配置，以及各业务场景下动态网络变化中算法的作用。

## 读者画像
- 具备 C/C++ 经验，熟悉高级 C++ 用法但需要补充
- 已有 `wr-modules-analysis.md`、`wr-arch-design-analysis.md`、`wr-whole-process.md` 的认知
- 需要深入到算法内部原理与参数级别

## 输出
- 主文档：`wr-qs-analysis.md`（本计划的落地实现）
- 文档开头插入目录与索引

## 章节大纲

### 第 0 章：导读与全景
- 0.1 什么是 QoS？WebRTC QoS 的范畴与目标（实时性 vs 质量 vs 带宽的三角权衡）
- 0.2 QoS 全景图：发送侧闭环 + 接收侧闭环 + 反馈通道（ASCII 总图）
- 0.3 QoS 的三大控制目标：码率控制、丢包恢复、时延控制
- 0.4 文档组织与阅读路径

### 第 1 章：QoS 总体架构
- 1.1 QoS 在 WebRTC 五层架构中的位置
- 1.2 发送侧 QoS 架构：RtpTransportControllerSend → GCC → BitrateAllocator → Pacer → Encoder
- 1.3 接收侧 QoS 架构：ReceiveSideCongestionController + JitterBuffer + NACK/FEC + Timing
- 1.4 反馈通道：TWCC / REMB / RTCP NACK / RTCP Loss
- 1.5 总体架构图（3 级粒度：总览 → 模块关系 → 关键路径跨层调用链）
- 1.6 控制流 vs 数据流 vs 反馈流的三层分离
- 1.7 线程架构总览（network / worker / pacer task queue / controller task queue / decode queue / module process thread）

### 第 2 章：拥塞控制核心 —— GCC（Google Congestion Control）
- 2.1 GCC 设计哲学：基于延迟 + 基于丢包 + 探测 三路融合
- 2.2 入口与控制 API：NetworkControllerInterface 的 12 个回调
- 2.3 工厂与实例化：GoogCcNetworkControllerFactory → GoogCcNetworkController
- 2.4 类图与组件组合（GoogCcNetworkController 组合 8 个子组件）
- 2.5 延迟估计：TrendlineEstimator（趋势线线性回归 + 滞回阈值状态机）
  - 2.5.1 InterArrival 时间戳分组
  - 2.5.2 累积延迟 + 指数平滑 + 滑动窗口最小二乘
  - 2.5.3 检测状态机（Normal/Overusing/Underusing）与自适应阈值
  - 2.5.4 参数表（window_size=20, smoothing=0.9, gain=4.0, threshold=12.5, k_up/k_down）
- 2.6 延迟 BWE：DelayBasedBwe + AimdRateControl（AIMD 状态机）
  - 2.6.1 Hold/Increase/Decrease 状态转换
  - 2.6.2 乘性增加（1.08）/ 加性增加 / 乘性减少（×0.85）
  - 2.6.3 链路容量估计 LinkCapacityEstimator
- 2.7 丢包 BWE：SendSideBandwidthEstimation（经典 + 新版 LossBasedBandwidthEstimation）
  - 2.7.1 经典丢包算法（2%/10% 阈值，增加/保持/减少）
  - 2.7.2 新版 loss-to-bitrate 函数
  - 2.7.3 RTT 回退 RttBasedBackoff
  - 2.7.4 融合：min(delay, receiver, loss, max_configured)
- 2.8 探测 BWE：ProbeController + ProbeBitrateEstimator
  - 2.8.1 探测状态机（kInit → kWaitingForProbingResult → kProbingComplete）
  - 2.8.2 指数探测（3x → 6x → 2x）、ALR 周期探测、分配探测、跌落探测
  - 2.8.3 探测码率估计（send_rate / receive_rate 取小，饱和链路处理）
- 2.9 ALR 检测：AlrDetector（IntervalBudget，0.65/0.80/0.50）
- 2.10 确认码率：AcknowledgedBitrateEstimator / RobustThroughputEstimator
- 2.11 拥塞窗口与回退：CongestionWindowPushbackController（BDP cwnd，fill_ratio 分级回退）
- 2.12 输出：NetworkControlUpdate（target_rate + pacer_config + probe_cluster_configs + congestion_window）
- 2.13 GCC 完整数据流图与控制流图
- 2.14 GCC 线程模型（controller task queue，25ms 周期）

### 第 3 章：接收侧拥塞控制与反馈
- 3.1 接收侧 CC 入口：ReceiveSideCongestionController
- 3.2 双路径分发：TWCC（RemoteEstimatorProxy）vs 接收侧 BWE（WrappingBitrateEstimator）
- 3.3 接收侧 BWE（Kalman 滤波）：InterArrival → OveruseEstimator → OveruseDetector → AimdRateControl
  - 3.3.1 OveruseEstimator Kalman 方程（slope/offset 状态，残差，噪声估计）
  - 3.3.2 OveruseDetector 阈值与自适应阈值
  - 3.3.3 AbsSendTime vs SingleStream 两种实现
- 3.4 TWCC 反馈：RemoteEstimatorProxy
  - 3.4.1 到达时间记录与周期反馈
  - 3.4.2 TWCC RTCP 报文结构（base seq, status chunks, recv delta）
  - 3.4.3 动态反馈间隔（5% 带宽，50-250ms）
- 3.5 发送侧 TWCC 消费：TransportFeedbackAdapter（反馈→TransportPacketsFeedback）
- 3.6 反馈解复用：TransportFeedbackDemuxer
- 3.7 CongestionControlHandler：目标码率门控与紧急停止
- 3.8 AbsSendTime vs TWCC 对比与演进
- 3.9 完整反馈环数据流图
- 3.10 线程模型

### 第 4 章：Pacing 与码率分配
- 4.1 Pacing 入口与接口：RtpPacketSender / RtpPacketPacer
- 4.2 两种实现：PacedSender（ProcessThread）vs TaskQueuePacedSender（TaskQueue）
- 4.3 PacingController 核心算法：漏桶 + 债务/信用机制
  - 4.3.1 周期模式 vs 动态模式
  - 4.3.2 pacing rate = target × pacing_factor(2.5)，大队列排空加速
  - 4.3.3 padding 处理与 keepalive
- 4.4 RoundRobinPacketQueue：优先级 + 流间公平轮转
  - 4.4.1 优先级分级（音频1/RTX2/视频3/padding4）
  - 4.4.2 StreamPrioKey（priority, cumulative_bytes）公平性
  - 4.4.3 kMaxLeadingSize 公平性上限
- 4.5 BitrateProber：探测簇生命周期与发送时机
- 4.6 PacketRouter：按 SSRC 路由 + transport seq 分配
- 4.7 BitrateAllocator：多流码率分配算法
  - 4.7.1 三种分配模式（LowRate/Normal/Max）
  - 4.7.2 优先级码率 + 比例分配 + 滞回
  - 4.7.3 AddObserver/OnBitrateUpdated 流程
- 4.8 RtpBitrateConfigurator：SDP/客户端/relay 三源码率约束合并
- 4.9 完整控制闭环：GCC → BitrateAllocator → Stream → Pacer → Encoder
- 4.10 线程模型（pacer task queue / network queue / worker queue）

### 第 5 章：丢包恢复 —— NACK 与 FEC
- 5.1 丢包恢复总览：NACK（重传）vs FEC（前向纠错）的权衡
- 5.2 NACK 模块：NackModule
  - 5.2.1 丢包检测与 nack list 管理
  - 5.2.2 请求策略（重试次数、退避计时器、最大请求年龄）
  - 5.2.3 关键帧请求回退
  - 5.2.4 参数表（kMaxNackAge, kMaxNackRetries, 计时器）
- 5.3 LossNotificationController：丢包通知 RTCP 优化
- 5.4 发送侧重传响应：RTX 路径（RtpVideoSender → PacketRouter → RtpRtcp）
- 5.5 ULP FEC：XOR 保护 + 掩码表（bursty vs random）
- 5.6 FlexFEC：灵活 FEC，掩码/交织，接收端 XOR 恢复
- 5.7 FecControllerDefault：FEC 开销决策（码率表 + 保护因子）
- 5.8 保护模式：kProtectionNack / kProtectionNackFEC / kProtectionFEC
- 5.9 NACK 与 FEC 协同策略
- 5.10 线程模型

### 第 6 章：抖动缓冲与时延控制
- 6.1 接收路径总览：RTP → PacketBuffer → FrameBuffer → Decode → Render
- 6.2 抖动估计：VCMJitterEstimator（Kalman 滤波）
  - 6.2.1 模型：frameDelay = θ₀·Δsize + θ₁ + noise
  - 6.2.2 Kalman 更新方程（增益、协方差、测量噪声 σ）
  - 6.2.3 随机抖动估计（avgNoise/varNoise EWMA）
  - 6.2.4 最终抖动 = θ₀·(maxSize−avgSize) + NoiseThreshold
  - 6.2.5 NACK 重传项与 FPS 缩放
  - 6.2.6 参数表
- 6.3 FrameBuffer：依赖图模型（VideoLayerFrameId，连续性/可解码性传播）
- 6.4 VCMJitterBuffer（legacy）：三链表 + 连续性 + NACK
- 6.5 VCMTiming：渲染时间计算与延迟调整
  - 6.5.1 TargetDelay = max(min_playout, jitter + decode_time + render_delay)
  - 6.5.2 RenderTime = extrapolated_local + clamp(current_delay)
  - 6.5.3 速率限制延迟调整（100ms/s）
- 6.6 TimestampExtrapolator：RTP 时间戳→本地时间 Kalman 映射
- 6.7 VCMRttFilter：RTT 滤波（EWMA + 跳变/漂移检测）
- 6.8 VCMCodecTimer：95 百分位解码时间
- 6.9 A/V 同步：RtpStreamsSynchronizer + StreamSynchronization
- 6.10 抖动反馈闭环：jitter → SetJitterDelay → current_delay → render_time → wait
- 6.11 线程模型（decode queue / worker / network）

### 第 7 章：视频自适应
- 7.1 视频自适应总览：码率/CPU/质量 三路降级
- 7.2 Resource 抽象与 ResourceAdaptationProcessor
- 7.3 CPU 过载检测：OveruseFrameDetector（编码时间 vs 帧间隔，自适应阈值）
- 7.4 质量缩放：QualityScaler + QualityThreshold（QP 高低阈值）
- 7.5 VideoStreamEncoderResourceManager：资源信号聚合
- 7.6 VideoStreamAdapter：VideoSourceRestrictions 计算（分辨率/帧率/层）
- 7.7 自适应决策管线：Resource → Processor → Adapter → Encoder
- 7.8 EncoderBitrateAdjuster：码率平滑与防过冲
- 7.9 EncoderOvershootDetector：编码器过冲检测
- 7.10 QualityLimitationReasonTracker：质量限制原因追踪
- 7.11 三路信号优先级与合并
- 7.12 参数表（QP 阈值、像素步长、帧率上限）
- 7.13 线程模型（encoder thread / worker）

### 第 8 章：音频网络适配（audio_network_adaptor）
- 8.1 音频适配总览：码率/帧长/DTX/FEC/通道数动态调整
- 8.2 AudioNetworkAdaptor 与 Controller 管理器
- 8.3 各 Controller：BitrateController / FrameLengthController / DtxController / FecControllerPlrBased / ChannelController
- 8.4 ControllerManager：基于网络条件选择激活控制器
- 8.5 配置 proto 与 debug dump
- 8.6 与 ANA 的集成入口
- 8.7 线程模型

### 第 9 章：核心数据结构与单位系统
- 9.1 单位类型：DataRate / DataSize / TimeDelta / Timestamp（api/units）
- 9.2 控制消息结构：NetworkControlUpdate / TransportPacketsFeedback / SentPacket / TargetTransferRate / PacerConfig / ProbeClusterConfig
- 9.3 BWE 结构：PacketResult / PacedPacketInfo / BandwidthUsage / RateControlInput
- 9.4 Pacing 结构：QueuedPacket / StreamPrioKey / ProbeCluster / IntervalBudget
- 9.5 分配结构：MediaStreamAllocationConfig / AllocatableTrack / BitrateAllocationLimits / BitrateAllocationUpdate
- 9.6 抖动结构：FrameInfo / TimestampGroup / Kalman 状态 / TimingFrameInfo
- 9.7 数据结构设计哲学（值语义 + optional + 不可变单位）

### 第 10 章：线程架构与并发控制
- 10.1 QoS 涉及的线程/队列全景
- 10.2 controller task queue（GCC 运行）
- 10.3 pacer task queue（PacingController 运行）
- 10.4 decode queue（FrameBuffer/解码）
- 10.5 module process thread（接收侧 CC / RemoteEstimatorProxy）
- 10.6 network thread（包收发）与 worker thread（流管理）
- 10.7 跨线程同步：CriticalSection / RaceChecker / SequenceChecker / TaskQueue 投递
- 10.8 线程亲和 vs 锁的取舍

### 第 11 章：内存与控制架构
- 11.1 所有权体系：unique_ptr 子组件组合 / scoped_refptr 共享
- 11.2 控制架构：反馈控制闭环（闭环增益、时延、稳定性）
- 11.3 分层控制：网络层（GCC）→ 流层（BitrateAllocator）→ 媒体层（Encoder/Adaptation）
- 11.4 控制周期：25ms（GCC）/ 5ms（pacer）/ 100ms（TWCC）/ 1000ms（A/V sync）
- 11.5 状态机驱动的控制（AIMD、探测、自适应）
- 11.6 参数化与 field trial 机制

### 第 12 章：动态网络场景下的算法作用
- 12.1 场景一：链路启动与爬坡（初始探测 → 指数探测 → 稳定）
- 12.2 场景二：带宽骤降（延迟过用 → AIMD 减少 → 探测恢复）
- 12.3 场景三：带宽恢复（ALR 探测 → 指数爬坡）
- 12.4 场景四：高丢包（丢包 BWE 减少 + NACK 重传 + FEC）
- 12.5 场景五：网络抖动增大（jitter 估计上升 → 延迟增加）
- 12.6 场景六：CPU 过载（视频降分辨率/帧率）
- 12.7 场景七：网络切换/路由变化（route change → BWE 重置）
- 12.8 场景八：应用限流 ALR（探测受限 → 周期探测）
- 12.9 场景九：低码率屏幕共享（FPS 缩放抖动、SVC 丢非基础层）
- 12.10 各场景下模块交互时序图

### 第 13 章：设计模式与设计哲学
- 13.1 策略模式：BWE 算法可替换（GCC/PCC/自定义）
- 13.2 工厂模式：NetworkControllerFactoryInterface
- 13.3 观察者模式：TargetTransferRateObserver / BitrateAllocatorObserver
- 13.4 状态机模式：AIMD / 探测 / 自适应
- 13.5 组合模式：GoogCcNetworkController 组合子组件
- 13.6 接口隔离：NetworkControllerInterface 抽象控制契约
- 13.7 反馈控制哲学：闭环、负反馈、稳定性优先
- 13.8 保守下降、激进探测的设计取向

### 第 14 章：QoS 设计优缺点与最佳实践
- 14.1 优点：分层清晰、算法可替换、闭环稳健、参数可调
- 14.2 缺点：参数繁多、调试困难、多反馈源冲突、legacy 双路径并存
- 14.3 与其他实现对比（TCP Reno/Cubic、SCReAM、NADA）
- 14.4 可复用的 QoS 设计模式

## 执行策略
- 按章节顺序逐章写入 `wr-qs-analysis.md`
- 每章完成后确认文件已持久化
- 每章之间读取已写内容确认完整性
- 长章节分多次写入（前半段 + 后半段）
- 文档过长时分多文件
- 最后在开头插入目录与索引
