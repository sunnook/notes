---
name: congestion-controller-class-diagrams
description: Class diagrams and architecture of WebRTC congestion_controller module (goog-CC and PCC)
metadata: 
  node_type: memory
  type: reference
  originSessionId: 67eb17d6-4166-410c-9c0b-306a27c0b5d6
---

# WebRTC Congestion Controller 类图

## 1. goog-CC 整体架构类图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     NetworkControllerInterface                           │
│  (抽象接口 - api/transport/network_control.h)                            │
│  + OnNetworkAvailability()                                               │
│  + OnProcessInterval()                                                   │
│  + OnTransportPacketsFeedback()                                          │
│  + OnRemoteBitrateReport()                                               │
│  + OnRoundTripTimeUpdate()                                               │
│  + OnSentPacket()                                                        │
│  + OnStreamsConfig()                                                     │
│  + OnTargetRateConstraints()                                             │
│  + OnTransportLossReport()                                               │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ implements
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    GoogCcNetworkController                               │
│  ─────────────────────────────────────────────────────────────────────  │
│  - probe_controller_: ProbeController*                                  │
│  - bandwidth_estimation_: SendSideBandwidthEstimation*                   │
│  - delay_based_bwe_: DelayBasedBwe*                                     │
│  - acknowledged_bitrate_estimator_: AcknowledgedBitrateEstimator*        │
│  - alr_detector_: AlrDetector*                                          │
│  - probe_bitrate_estimator_: ProbeBitrateEstimator*                      │
│  - network_estimator_: NetworkStateEstimator*                            │
│  - congestion_window_pushback_: CongestionWindowPushbackController*      │
│  - pacing_factor_: float (default 2.5)                                   │
│  - min_data_rate_ / max_data_rate_                                      │
│  ─────────────────────────────────────────────────────────────────────  │
│  + OnTransportPacketsFeedback()  ← 核心入口                              │
│  + OnProcessInterval()    ← 周期性处理                                   │
│  + OnSentPacket()         ← 每包发送时调用                               │
│  + OnRemoteBitrateReport() ← REMB 回调                                   │
│  + GetNetworkState()        ← 获取当前网络状态                           │
│  + MaybeTriggerOnNetworkChanged() ← 触发码率更新                         │
└──────┬──────────────────────────────┬───────────────────────────────────┘
       │                              │
       ▼                              ▼
┌─────────────────────┐    ┌────────────────────────────────────────────┐
│   ProbeController   │    │         SendSideBandwidthEstimation        │
│  ────────────────── │    │  ───────────────────────────────────────── │
│ - config_: Config    │    │  ───────────────────────────────────────── │
│ - state_: State      │    │  - rtt_backoff_: RttBasedBackoff           │
│ - start_bitrate_    │    │  - link_capacity_: LinkCapacityTracker      │
│ - max_bitrate_      │    │  - loss_based_v1_: LossBasedBandwidthEst.   │
│                    │    │  - loss_based_v2_: LossBasedBweV2*          │
│ + SetBitrates()     │    │  - receiver_limit_ / delay_based_limit_    │
│ + RequestProbe()    │    │  ───────────────────────────────────────── │
│ + Process()         │    │  + UpdateEstimate()     ← 定期更新          │
│ + OnNetworkAvail()  │    │  + UpdateDelayBasedEstimate() ← 延迟估计输入│
└─────────────────────┘    │  + UpdateLossBasedEstimator() ← 丢包输入   │
                           │  + SetAcknowledgedRate()  ← ACK 速率输入   │
                           │  + target_rate()      ← 最终输出            │
                           │  + GetEstimatedLinkCapacity()              │
                           └──────┬───────────────┬─────────────────────┘
                                  │               │
                                  ▼               ▼
                    ┌─────────────────────┐  ┌────────────────────────┐
                    │    DelayBasedBwe    │  │   LossBasedBweV2       │
                    │  ────────────────── │  │ ────────────────────── │
                    │ - video_inter_     │  │ - config_: Config       │
                    │   arrival_delta_   │  │ - observations_          │
                    │ - delay_detector_: │  │ - current_best_estimate_ │
                    │   TrendlineEstimator│ │ ──────────────────────   │
                    │ - rate_control_:   │  │ + GetLossBasedResult()   │
                    │   AimdRateControl  │  │ + UpdateBandwidthEst()   │
                    │  ───────────────── │  │ + PaceAtLossBasedEst()   │
                    │ + IncomingPacket() │  └────────────────────────┘
                    │ + OnRttUpdate()    │
                    │ + last_estimate()  │
                    └──────────┬─────────┘
                               │
                               ▼
                  ┌────────────────────────┐
                  │  TrendlineEstimator    │
                  │  (DelayIncreaseDetector)│
                  │ ──────────────────────  │
                  │ - delay_hist_: deque<   │
                  │     PacketTiming>       │
                  │ - window_size: 20       │
                  │ - trendline 回归        │
                  │ ──────────────────────  │
                  │ + Update()              │
                  │ + State() → BandwidthUsage │
                  │   kBwOverusing / Normal / Underusing
                  └────────────────────────┘
```

## 2. AIMD 速率控制类图

```
┌─────────────────────────────────┐
│      AimdRateControl            │
│  ─────────────────────────────  │
│ - min_rate_: DataRate           │
│ - max_rate_: DataRate           │
│ - rate_control_settings_:       │
│     RateControlSettings         │
│ - state_: RateControlState      │
│ - bytes_in_flight_: DataSize    │
│ - decrease_count_: int          │
│ ──────────────────────────────  │
│ + UpdateEstimate()              │
│ + UpdateLossState()             │
│ + UpdateRttState()              │
│ + UpdateProbeState()            │
│ + GetTargetRate() → DataRate    │
│ ──────────────────────────────  │
│ 状态机:                          │
│   kStart → kIncrease / kDecrease│
│   kIncrease:                     │
│     Normal  → 线性增长           │
│     Overuse → kDecrease (减半)   │
│   kDecrease:                     │
│     指数回退直到稳定             │
└─────────────────────────────────┘
```

## 3. 接收端拥塞控制类图

```
  ┌─────────────────────────────────────────────────────────────┐
  │                   pcc::PccNetworkController                   │
  │  ────────────────────────────────────────────────────────── │
  │  - mode_: Mode (Startup / SlowStart / OnlineLearning)       │
  │  - bandwidth_estimate_: DataRate                             │
  │  - bitrate_controller_: PccBitrateController                │
  │  - monitor_intervals_: vector<PccMonitorInterval>           │
  │  ────────────────────────────────────────────────────────── │
  │  + OnTransportPacketsFeedback()  ← 核心入口                  │
  │  + UpdateSendingRateAndMode() ← 模式切换 + 码率更新          │
  └──────────────────────┬──────────────────────────────────────┘
                         │
                         ▼
  ┌─────────────────────────────────────────────────────────────┐
  │          pcc::PccBitrateController                           │
  │  ────────────────────────────────────────────────────────── │
  │  - utility_function_: PccUtilityFunctionInterface*           │
  │  - dynamic_boundary_: double                                │
  │  ────────────────────────────────────────────────────────── │
  │  + ComputeRateUpdateForSlowStartMode()                      │
  │  + ComputeRateUpdateForOnlineLearningMode() ← 梯度上升       │
  └──────────────────────┬──────────────────────────────────────┘
                         │
                         ▼
  ┌─────────────────────────────────────────────────────────────┐
  │       pcc::PccUtilityFunctionInterface (抽象)                 │
  │                               │ implements                   │
  │                   ┌───────────┴───────────┐                  │
  │                   ▼                       ▼                  │
  │      ┌─────────────────────┐  ┌──────────────────────────┐  │
  │      │ VivaceUtilityFunc   │  │ ModifiedVivaceUtilityFunc │  │
  │      │ - delay_coeff_      │  │ - throughput_power_       │  │
  │      │ - loss_coeff_       │  │ ────────────────────────  │  │
  │      │ - throughput_coeff_ │  │ + Compute(MI) → double    │  │
  │      │ ─────────────────── │  │   (效用值 = 吞吐-延迟-丢包)│  │
  │      │ + Compute()         │  └──────────────────────────┘  │
  │      └─────────────────────┘                                │
  └─────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────────────────┐
│                   ReceiveSideCongestionController                        │
│  (implements CallStatsObserver)                                          │
│  ─────────────────────────────────────────────────────────────────────  │
│  - remb_throttler_: RembThrottler                                       │
│  - remote_estimator_proxy_: RemoteEstimatorProxy                        │
│  - rbe_: RemoteBitrateEstimator*                                        │
│  - using_absolute_send_time_: bool                                      │
│  ─────────────────────────────────────────────────────────────────────  │
│  + OnReceivedPacket()       ← RTP 包到达入口                             │
│  + MaybeProcess()           ← 周期性处理                                 │
│  + PickEstimator()          ← 切换 AST/TOF 估计器                        │
│  + LatestReceiveSideEstimate() ← 获取估计结果                            │
└──────┬──────────────────────────────────┬───────────────────────────────┘
       │                                  │
       ▼                                  ▼
┌─────────────────────┐      ┌──────────────────────────────────────────┐
│    RembThrottler     │      │         RemoteEstimatorProxy              │
│ (implements          │      │  (发送端 BWE 的代理层)                    │
│  RemoteBitrateObser.)│      │ ──────────────────────────────────────── │
│ ──────────────────── │      │ - transport_feedback_sender_             │
│ - remb_sender_:      │      │ - network_state_estimator_               │
│   RembSender         │      │ ──────────────────────────────────────── │
│ ──────────────────── │      │ + IncomingPacket() ← RTP 包 (发送端BWE)  │
│ + OnReceiveBitrate() │      │ + Process() ← 周期性处理                  │
│   ← 触发 REMB 消息   │      │ + OnBitrateChanged() ← 反馈消息限速       │
└─────────────────────┘      └──────────────────────────────────────────┘
```

## 4. ACK 速率估计类图

```
┌───────────────────────────────────────────────┐
│ AcknowledgedBitrateEstimatorInterface         │
│ (抽象接口)                                     │
│ ────────────────────────────────────────────  │
│ + IncomingPacketFeedbackVector()              │
│ + bitrate() → optional<DataRate>              │
│ + PeekRate() → optional<DataRate>             │
│ + SetAlr()                                    │
└──────────────────┬────────────────────────────┘
                   │ implements (二选一)
                   ├──┐                          ├──┐
                   ▼                              ▼
┌─────────────────────────────┐  ┌─────────────────────────────────────┐
│  RobustThroughputEstimator   │  │  BitrateEstimator (旧版)             │
│  ────────────────────────── │  │  ──────────────────────────────────  │
│  - settings_: Settings      │  │  - sum_: int                         │
│  - window_: deque<          │  │  - bitrate_estimate_kbps_: float     │
│      PacketResult>          │  │  - bitrate_estimate_var_: float      │
│  ────────────────────────── │  │  ──────────────────────────────────  │
│  + IncomingPacketFeedback() │  │  + Update()  ← 贝叶斯估计            │
│  + bitrate()                │  │  + bitrate() → optional<DataRate>    │
│                             │  └─────────────────────────────────────┘
└─────────────────────────────┘
```

## 5. PCC 拥塞控制类图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     NetworkControllerInterface                           │
│                               │ implements                               │
└───────────────────────────────┼─────────────────────────────────────────┘
                                │
                   ┌────────────┘
                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                   pcc::PccNetworkController                              │
│  ─────────────────────────────────────────────────────────────────────  │
│  - mode_: Mode (Startup / SlowStart / OnlineLearning / DoubleCheck)     │
│  - bandwidth_estimate_: DataRate                                        │
│  - rtt_tracker_: RttTracker                                             │
│  - bitrate_controller_: PccBitrateController                            │
│  - monitor_intervals_: vector<PccMonitorInterval>                       │
│  - sampling_step_: double (ε)                                           │
│  ─────────────────────────────────────────────────────────────────────  │
│  + OnTransportPacketsFeedback()  ← 核心入口                             │
│  + OnProcessInterval()           ← 周期性处理                            │
│  + OnSentPacket()              ← 包发送记录                              │
│  + UpdateSendingRateAndMode()  ← 模式切换 + 码率更新                     │
│  + ComputeMonitorIntervalsDuration()                                   │
└──────┬──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│              pcc::PccBitrateController                                   │
│  ─────────────────────────────────────────────────────────────────────  │
│  - utility_function_: PccUtilityFunctionInterface*                      │
│  - dynamic_boundary_: double                                            │
│  - step_size_adjustments_number_: int                                   │
│  - previous_utility_: optional<double>                                  │
│  ─────────────────────────────────────────────────────────────────────  │
│  + ComputeRateUpdateForSlowStartMode()                                  │
│  + ComputeRateUpdateForOnlineLearningMode() ← 梯度上升                  │
└──────┬──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│         pcc::PccUtilityFunctionInterface (抽象)                          │
│                               │ implements                              │
│                   ┌───────────┴───────────┐                             │
│                   ▼                       ▼                             │
│      ┌─────────────────────┐   ┌──────────────────────────────┐        │
│      │ VivaceUtilityFunc   │   │ ModifiedVivaceUtilityFunc     │        │
│      │ ──────────────────  │   │ ───────────────────────────  │        │
│      │ - delay_coeff_     │   │ - throughput_power_           │        │
│      │ - loss_coeff_      │   │ - delay_gradient_threshold_   │        │
│      │ - throughput_coeff_│   │                               │        │
│      │ ──────────────────  │   │ + Compute(MonitorInterval)   │        │
│      │ + Compute()         │   │   → double (效用值)           │        │
│      │   → double          │   └──────────────────────────────┘        │
│      └─────────────────────┘                                            │
└─────────────────────────────────────────────────────────────────────────┘
```

```
  ┌─────────────────────────────────────────────────────────────┐
  │                   pcc::PccNetworkController                   │
  │  ────────────────────────────────────────────────────────── │
  │  - mode_: Mode (Startup / SlowStart / OnlineLearning)       │
  │  - bandwidth_estimate_: DataRate                             │
  │  - bitrate_controller_: PccBitrateController                │
  │  - monitor_intervals_: vector<PccMonitorInterval>           │
  │  ────────────────────────────────────────────────────────── │
  │  + OnTransportPacketsFeedback()  ← 核心入口                  │
  │  + UpdateSendingRateAndMode() ← 模式切换 + 码率更新          │
  └──────────────────────┬──────────────────────────────────────┘
                         │
                         ▼
  ┌─────────────────────────────────────────────────────────────┐
  │          pcc::PccBitrateController                           │
  │  ────────────────────────────────────────────────────────── │
  │  - utility_function_: PccUtilityFunctionInterface*           │
  │  - dynamic_boundary_: double                                │
  │  ────────────────────────────────────────────────────────── │
  │  + ComputeRateUpdateForSlowStartMode()                      │
  │  + ComputeRateUpdateForOnlineLearningMode() ← 梯度上升       │
  └──────────────────────┬──────────────────────────────────────┘
                         │
                         ▼
  ┌─────────────────────────────────────────────────────────────┐
  │       pcc::PccUtilityFunctionInterface (抽象)                 │
  │                               │ implements                   │
  │                   ┌───────────┴───────────┐                  │
  │                   ▼                       ▼                  │
  │      ┌─────────────────────┐  ┌──────────────────────────┐  │
  │      │ VivaceUtilityFunc   │  │ ModifiedVivaceUtilityFunc │  │
  │      │ - delay_coeff_      │  │ - throughput_power_       │  │
  │      │ - loss_coeff_       │  │ ────────────────────────  │  │
  │      │ - throughput_coeff_ │  │ + Compute(MI) → double    │  │
  │      │ ─────────────────── │  │   (效用值 = 吞吐-延迟-丢包)│  │
  │      │ + Compute()         │  └──────────────────────────┘  │
  │      └─────────────────────┘                                │
  └─────────────────────────────────────────────────────────────┘
```

## 6. RTP 反馈层类图

```
┌─────────────────────────────────────────────────────────────────────────┐
│              StreamFeedbackProvider (抽象接口)                           │
│  + RegisterStreamFeedbackObserver(ssrcs, observer)                      │
│  + DeRegisterStreamFeedbackObserver(observer)                           │
│  + AddPacket(packet_info)                                               │
│  + OnTransportFeedback(rtcp_feedback)                                   │
└────────────────────┬────────────────────────────────────────────────────┘
                     │ implements
                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│            TransportFeedbackDemuxer                                      │
│  ─────────────────────────────────────────────────────────────────────  │
│  - history_: map<int64_t, StreamPacketInfo>  ← 包历史                   │
│  - observers_: vector<(ssrcs, observer*)>    ← SSRC → 观察者映射        │
│  - seq_num_unwrapper_: RtpSequenceNumberUnwrapper ← 序列号展开          │
│  ─────────────────────────────────────────────────────────────────────  │
│  + OnTransportFeedback()  ← 解析 RTCP Transport Feedback               │
│    → 展开序列号 + 关联发送信息                                          │
│    → 遍历 observers_ 分发到各观察者                                     │
└─────────────────────────────────────────────────────────────────────────┘
```

## 7. 关键数据结构

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PacketResult (包反馈结果 - 核心数据结构)                                 │
│  ─────────────────────────────────────────────────────────────────────  │
│  - sent_packet: SentPacket {                                            │
│      send_time: Timestamp      ← 发送时间                                │
│      packet_size: DataSize     ← 包大小                                  │
│      pacing_info: PacedPacketInfo {                                     │
│        probe_cluster_id: int       ← 探测包标识                           │
│      }                                                                   │
│    }                                                                     │
│  - receive_time: Timestamp     ← 到达时间                                 │
│  - feedback_time: Timestamp    ← 反馈时间 (RTCP 到达时间)                 │
│  - bytes_acked: DataSize       ← 已确认字节数                             │
│  - is_received: bool         ← 是否收到 (非丢包)                          │
│  - delay_change: TimeDelta   ← 延迟变化                                   │
│  - propagation_delay: TimeDelta ← 传播延迟 (减去队列延迟)                  │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  NetworkControlUpdate (控制器输出 - 给上层)                               │
│  ─────────────────────────────────────────────────────────────────────  │
│  + target_rate: TargetTransferRate {                                     │
│      at_time: Timestamp                                                │
│      target_rate: DataRate        ← 给编码器的目标码率                    │
│      stable_target_rate: DataRate ← 稳定目标码率 (链路容量)               │
│      cwnd_reduce_ratio: float     ← 拥塞窗口回退比例                     │
│      network_estimate: {                                               │
│        round_trip_time: TimeDelta                                      │
│        loss_rate_ratio: float                                          │
│        bwe_period: TimeDelta                                           │
│      }                                                                   │
│    }                                                                     │
│  + pacer_config: PacerConfig {                                           │
│      data_window: DataSize      ← pacing 数据窗口                        │
│      pad_window: DataSize       ← padding 窗口                           │
│    }                                                                     │
│  + probe_cluster_configs: vector<ProbeClusterConfig> ← 探测包集群        │
│  + congestion_window: optional<DataSize> ← 拥塞窗口大小                   │
└─────────────────────────────────────────────────────────────────────────┘
```

## 8. 模块依赖关系

```
congestion_controller/
│
├── include/
│   └── receive_side_congestion_controller.h  ← 接收端 BWE 入口
│
├── remb_throttler.cc/h                       ← REMB 消息限流
│
├── rtp/
│   ├── transport_feedback_adapter.cc/h       ← RTCP Feedback → PacketResult
│   ├── transport_feedback_demuxer.cc/h       ← SSRC 解复用
│   └── control_handler.cc/h                  ← 异步安全访问
│
├── goog_cc/                                  ← goog-CC 算法
│   ├── goog_cc_network_control.cc/h          ← 总调度器 ★
│   ├── send_side_bandwidth_estimation.cc/h   ← 多源融合 ★
│   ├── delay_based_bwe.cc/h                  ← 延迟估计 ★
│   ├── trendline_estimator.cc/h              ← 线性回归趋势检测
│   ├── loss_based_bwe_v2.cc/h                ← 丢包估计 V2 ★
│   ├── loss_based_bandwidth_estimation.cc/h  ← 丢包估计 V1
│   ├── acknowledged_bitrate_estimator*.cc/h  ← ACK 速率估计
│   ├── robust_throughput_estimator.cc/h      ← 鲁棒吞吐量
│   ├── probe_controller.cc/h                 ← 探测包控制 ★
│   ├── probe_bitrate_estimator.cc/h          ← 探测码率估计
│   ├── alr_detector.cc/h                     ← 应用受限检测
│   ├── congestion_window_pushback_controller.cc/h
│   ├── bitrate_estimator.cc/h
│   ├── link_capacity_estimator.cc/h
│   ├── inter_arrival_delta.cc/h
│   └── test/goog_cc_printer.cc/h             ← 调试打印
│
├── pcc/                                      ← PCC Vivace 算法
│   ├── pcc_network_controller.cc/h           ← PCC 总控制器 ★
│   ├── bitrate_controller.cc/h               ← 码率梯度更新
│   ├── utility_function.cc/h                 ← 效用函数 ★
│   ├── monitor_interval.cc/h                 ← 监控区间统计
│   ├── rtt_tracker.cc/h                      ← RTT 追踪
│   └── pcc_factory.cc/h                      ← 工厂
│
└── BUILD.gn                                  ← 构建配置
```

注: ★ 标记为核心关键文件
