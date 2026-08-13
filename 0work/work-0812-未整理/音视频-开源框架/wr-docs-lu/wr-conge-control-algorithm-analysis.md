# WebRTC 拥塞控制：算法流程、原理与优化指南

---

## 一、整体架构：数据流与控制流

```
发送端 BWE 数据流（每个 RTCP Transport Feedback 周期触发）:

OnTransportPacketsFeedback(report)
  │
  ├─→ AcknowledgedBitrateEstimator  ← ACK 速率估计
  ├─→ ProbeBitrateEstimator         ← 探测包速率估计
  ├─→ DelayBasedBwe
  │    └─→ TrendlineEstimator       ← 延迟趋势检测 (overuse/normal/underuse)
  │    └─→ AimdRateControl          ← AIMD 状态机 → target_bitrate
  ├─→ SendSideBandwidthEstimation
  │    ├─→ LossBasedBweV2           ← 丢包 MLE 估计
  │    ├─→ LossBasedBweV1           ← 旧版丢包估计 (可选)
  │    └─→ 多源融合 → target_rate()
  ├─→ ProbeController               ← 探测包调度器
  └─→ CongestionWindowPushbackController ← 拥塞窗口直接回退

输出: NetworkControlUpdate { target_rate, pacer_config, probe_cluster_configs }
```

---

## 二、核心算法流程详解

### 1. TrendlineEstimator — 延迟趋势检测（拥塞感知的"眼睛"）

**原理**: 对最近 N 个包的 queueing delay 做线性最小二乘回归，斜率 = (发送速率 - 链路容量)/链路容量

**详细流程** (`trendline_estimator.cc`):

```
每收到一个 PacketResult:
  │
  ├─ 1. 计算 queueing delay = recv_delta - send_delta
  │
  ├─ 2. 指数平滑滤波 (smoothing_coef_ = 0.9):
  │     smoothed_delay = 0.9 * smoothed_delay + 0.1 * accumulated_delay
  │
  ├─ 3. 维护滑动窗口 (默认 100 个包):
  │     delay_hist_ ← [arrival_time_ms, smoothed_delay_ms, accumulated_delay_ms]
  │
  ├─ 4. 线性回归 (当窗口满时):
  │     slope = Σ(x-x̄)(y-ȳ) / Σ(x-x̄)²
  │     trend = slope (斜率反映队列增长速率)
  │
  │     可选 cap 机制: 用首尾最小 delay 计算上限斜率，过滤异常值
  │
  └─ 5. Detect(trend, ts_delta, now_ms) — 状态判定:
       │
       ├─ modified_trend = min(num_of_deltas, 60) * trend * 4.0
       │
       ├─ if modified_trend > threshold:
       │    ├─ 累计 overuse 时间
       │    ├─ overuse_counter++
       │    ├─ if 时间 > 10ms 且 overuse_counter > 1 且 trend >= prev_trend:
       │    │   → hypothesis = kBwOverusing  (检测到拥塞!)
       │    │   → 重置计时器
       │    │
       │    ├─ else: 继续观察
       │    │
       │    └─ if modified_trend > threshold + 15ms: 不更新 threshold (防大 spike)
       │
       ├─ if modified_trend < -threshold:
       │    → hypothesis = kBwUnderusing  (队列在排空)
       │
       └─ else:
            → hypothesis = kBwNormal  (正常)
       │
       └─ 自适应 threshold (k_up=0.0087, k_down=0.039):
            在 normal 时快速增大 threshold，在 overuse 边缘时缓慢减小
            范围: [6, 600]
```

**关键参数**:
| 参数 | 默认值 | 含义 |
|------|--------|------|
| `smoothing_coef_` | 0.9 | 指数平滑系数，越大越平滑 |
| `threshold_gain_` | 4.0 | trend 放大倍数，提高敏感度 |
| `threshold_` | 12.5 | 自适应阈值，初始值 |
| `k_up_` | 0.0087 | threshold 增长速率 |
| `k_down_` | 0.039 | threshold 下降速率 (更快) |
| `overusing_time_threshold_` | 10ms | 连续 overuse 判定时间 |
| `window_size` | 100 包 | 回归窗口大小 |

### 2. AIMD RateControl — 速率控制状态机

**原理**: 基于 delay_detector 的状态做 AIMD 调整

**详细流程** (`delay_based_bwe.cc`):

```
MaybeUpdateEstimate(acked_bitrate, probe_bitrate, network_estimate):
  │
  ├─ if delay_detector 状态 == kBwOverusing:
  │    ├─ if acked_bitrate 存在 且 TimeToReduceFurther 已到:
  │    │   → rate_control_.Update(input: overuse, acked_bitrate)
  │    │   → AIMD 将速率减半
  │    │
  │    └─ else if 没有 acked_bitrate:
  │         → 每 200ms 减半，直到有 ACK
  │
  └─ else (normal 或 underuse):
       ├─ if probe_bitrate 存在:
       │   → 直接使用 probe 速率
       │
       └─ else:
            → rate_control_.Update(input: normal/underuse, acked_bitrate)
            → AIMD 线性增加速率

AIMD 内部状态机:
  kStart → kIncrease
  kIncrease:
    ├─ normal/underuse → 线性增加 (Additive Increase)
    │   增长率 ≈ 8%/秒 (由 min_bitrate_history 滑动窗口控制)
    └─ overuse → kDecrease (Multiplicative Decrease)
         速率减半，等待 ACK 确认

  kDecrease:
    ├─ 收到 ACK → 检查是否稳定
    │   ├─ 稳定 → kIncrease
    │   └─ 不稳定 → 继续减半
    └─ 无 ACK → 每 200ms 减半
```

### 3. LossBasedBweV2 — 基于丢包的 MLE 估计

**原理**: 基于内在丢包模型 (inherent loss model)，用牛顿迭代法最大化似然函数，估计链路容量

**详细流程** (`loss_based_bwe_v2.cc`):

```
UpdateBandwidthEstimate(packet_results, delay_based_estimate, in_alr):
  │
  ├─ 1. PushBackObservation: 聚合 PacketResult 为 Observation
  │     统计: num_packets, num_lost, num_received, sending_rate
  │
  ├─ 2. 计算平均丢包率 (支持 packet/byte 两种模式)
  │
  ├─ 3. 生成候选信道参数 (GetCandidates):
  │     每个候选 = {inherent_loss, loss_limited_bandwidth}
  │     候选来源:
  │     ├─ candidate_factors × 当前最佳估计
  │     ├─ ACK 速率候选 (如果 append_acknowledged_rate_candidate)
  │     ├─ 延迟估计候选 (如果 append_delay_based_estimate_candidate)
  │     └─ ALR 下的上界候选
  │
  ├─ 4. 对每个候选: Newton 迭代优化
  │     GetDerivatives(候选) → 似然函数的一阶/二阶导数
  │     Newton's Method: inherent_loss -= f'(x)/f''(x)
  │     迭代 newton_iterations 次
  │
  ├─ 5. 选择最优候选:
  │     GetObjective(候选) → 似然值
  │     选最大似然值对应的候选作为 current_best_estimate_
  │
  └─ 6. 生成最终结果:
       ├─ bandwidth_estimate = 最优候选的 loss_limited_bandwidth
       ├─ state = kIncreasing / kDecreasing / kDelayBasedEstimate
       └─ 如果 loss > threshold → 降低速率
          如果 loss < threshold → 增加速率

Start Phase 行为:
  ├─ 前 2 秒 (kStartPhase): 如果 last_fraction_loss == 0
  │   → 信任 delay_based 或 REMB，不做丢包决策
  │   → 允许 probe 快速探测
  └─ 2 秒后: LossBasedBweV2 就绪，开始主导
```

**关键参数** (`Config`):
| 参数 | 含义 |
|------|------|
| `candidate_factors` | 候选倍率因子列表，用于探索不同信道假设 |
| `newton_iterations` | Newton 迭代次数 |
| `newton_step_size` | Newton 步长 |
| `temporal_weight_factor` | 时间衰减权重，近期观测权重更高 |
| `bandwidth_rampup_hold_threshold` | 增长率下降时的 hold 阈值 |
| `higher_bandwidth_bias_factor` | 高带宽偏好偏置，倾向于选择更高带宽 |
| `inherent_loss_lower_bound` | 内在丢包率下界 |

### 4. ProbeController — 探测包状态机

**原理**: 主动发送探测包来发现可用带宽，管理多种探测策略

**详细流程** (`probe_controller.cc`):

```
State 状态机: kInit → kWaitingForProbingResult → kProbingComplete → kInit...

SetBitrates(min, start, max):
  │
  └─ InitiateExponentialProbing:
       ├─ 第一轮: 发送 p1×start_bitrate 和 p2×start_bitrate 的探测
       │   (默认 p1=1.0, p2=1.05)
       │
       └─ 后续轮: 如果 estimate >= 上次探测结果 × further_probe_threshold
          → 发送 further_probe_scale × estimate 的探测
          (默认 scale=1.05, threshold=1.2)

TimeForAlrProbe(now):
  └─ ALR (应用受限) 结束后:
       ├─ 周期性 ALR 探测 (默认 interval=10s, scale=1.05)
       └─ ALR 期间发送的流量不反映网络真实容量
          → 需要在 ALR 结束后重新探测

TimeForNetworkStateProbe(now):
  └─ 如果有 NetworkStateEstimate:
       ├─ 如果 estimate < network_state_estimate × ratio
       │   → 需要探测以确认
       ├─ 探测间隔: estimate_lower_than_network_state_estimate_probing_interval
       └─ 探测大小: network_state_probe_scale × estimate

RequestProbe():
  └─ 从 overuse 恢复时:
       → 立即触发探测，加速恢复

Process(now):
  └─ 检查是否需要触发各类探测:
       ├─ Exponential probing (初始/恢复)
       ├─ ALR probing (ALR 结束后)
       ├─ Network state probing (外部估计差异大)
       └─ Allocation probe (max allocated bitrate 变化)
```

### 5. SendSideBandwidthEstimation — 多源融合器

**原理**: 综合 delay-based、loss-based、REMB、ACK rate 等多种估计，输出最终目标码率

**详细流程** (`send_side_bandwidth_estimation.cc`):

```
UpdateEstimate(at_time):
  │
  ├─ 1. RTT 回退检查:
  │   if rtt_backoff_.IsRttAboveLimit():
  │     → 每 1s + RTT 减半，最低 5kbps
  │
  ├─ 2. Start Phase (前 2 秒且无丢包):
  │   → 信任 delay_based 或 REMB，跳过丢包逻辑
  │   → 允许 probe 快速启动
  │
  ├─ 3. LossBasedBweV1 就绪?
  │   → 使用 V1 的贝叶斯估计更新
  │
  ├─ 3. LossBasedBweV2 就绪?
  │   → 使用 V2 的 MLE 估计更新 ← 默认路径
  │
  └─ 4. 纯丢包启发式 (fallback):
       ├─ loss < 2%: 速率 × 1.08 + 1kbps (线性增长)
       ├─ 2% ≤ loss ≤ 10%: 不动
       └─ loss > 10%: 速率 × (1 - 0.5×lossRate)
          降低频率限制: 每 300ms + RTT 一次
```

---

## 三、优化/修改指南

### 场景 1: 调整响应速度 (太快/太慢)

**目标**: 网络变好时更快提升，网络变差时更快降低

**修改位置**: `delay_based_bwe.h` → `RateControlSettings`

```cpp
// 加快响应: 增大 k_up_ (增长系数) 或减小 k_down_ (降低系数)
// 减慢响应: 减小 k_up_ 或增大 k_down_

// 通过 Field Trial 配置 (无需改代码):
// WebRTC-RateControlSettings:k_up_<value>:k_down_<value>
// 例如: WebRTC-RateControlSettings:k_up_0.015:k_down_0.02
```

**修改文件**: `rtc_base/experiments/rate_control_settings.cc`

### 场景 2: 调整对延迟的敏感度

**目标**: 更敏感地检测拥塞 (更早降速) 或更不敏感 (容忍更高延迟)

**修改位置**: `trendline_estimator.cc`

```cpp
// 更敏感: 增大 threshold_gain_ (默认 4.0) 或减小 threshold_ (默认 12.5)
// 更不敏感: 减小 threshold_gain_ 或增大 threshold_

// 通过 Field Trial:
// WebRTC-TrendlineEstimatorSettings:gain_<value>:threshold_<value>
```

**注意**: `k_up_` 和 `k_down_` 控制 threshold 自适应速度。`k_down_` 大 → 在 normal 时 threshold 快速增大 → 更难触发 overuse → 更不敏感。

### 场景 3: 调整 AIMD 增长/降低幅度

**目标**: 增加或减少 AIMD 的激进程度

**修改位置**: `delay_based_bwe.h` → `AimdRateControl`

```cpp
// 增长阶段:
//   k_up = 0.0087 → 增大到 0.015 增长更快
// 降低阶段:
//   k_down = 0.039 → 增大到 0.05 降得更快
//   AIMD 降低比例: 默认减半 (0.5)
//   修改 AimdRateControl::Update() 中的乘数

// 增长速率也受 SendSideBandwidthEstimation 中的 1.08 影响:
// send_side_bandwidth_estimation.cc:567
//   new_bitrate = min_bitrate_history × 1.08  // 改为 1.05 降低增长
```

### 场景 4: 调整探测策略

**目标**: 改变探测频率、大小或触发条件

**修改位置**: `probe_controller.h` → `ProbeControllerConfig`

```cpp
// 增加探测频率:
//   alr_probing_interval: 从 10s 改为 5s
//   network_state_estimate_probing_interval: 从 10s 改为 5s

// 增大探测幅度:
//   first_exponential_probe_scale: 从 1.0 改为 1.1
//   alr_probe_scale: 从 1.05 改为 1.1
//   further_exponential_probe_scale: 从 1.05 改为 1.1

// 通过 Field Trial:
// WebRTC-ProbeControllerConfig:alr_probing_interval_5000ms:alr_probe_scale_1.1
```

**关键参数**:
| 参数 | 默认值 | 含义 |
|------|--------|------|
| `first_exponential_probe_scale` | 1.0 | 第一轮探测倍率 |
| `second_exponential_probe_scale` | 1.05 | 第二轮探测倍率 |
| `further_exponential_probe_scale` | 1.05 | 后续探测倍率 |
| `further_probe_threshold` | 1.2 | 触发后续探测的倍率阈值 |
| `alr_probe_scale` | 1.05 | ALR 探测倍率 |
| `network_state_probe_scale` | 1.05 | 网络状态探测倍率 |
| `min_probe_duration` | 500ms | 最小探测持续时间 |
| `min_probe_packets_sent` | 1 | 最小探测包数 |

### 场景 5: 调整 LossBasedBweV2 行为

**目标**: 改变丢包估计的探索策略或收敛速度

**修改位置**: `loss_based_bwe_v2.cc` → `Config`

```cpp
// 增加探索范围 (更多候选):
//   candidate_factors: 添加更多倍率因子
//   例如: {0.5, 0.75, 1.0, 1.25, 1.5, 2.0}

// 加快收敛:
//   newton_iterations: 增加迭代次数
//   temporal_weight_factor: 增大 → 更重视近期数据

// 提高带宽偏好:
//   higher_bandwidth_bias_factor: 增大 → 倾向选择更高带宽
//   higher_log_bandwidth_bias_factor: 同上 (对数尺度)

// 通过 Field Trial:
// WebRTC-LossBasedBweV2:candidate_factors_0.5,0.75,1.0,1.25,1.5:newton_iterations_10
```

### 场景 6: 添加新的估计策略

**架构位置**: `SendSideBandwidthEstimation` 是多源融合的中心

```
添加新估计器的步骤:

1. 在 goog_cc/ 下创建新文件, 实现类似 interface:
   class MyNewEstimator {
     void Update(...);
     optional<DataRate> bitrate();
   };

2. 在 send_side_bandwidth_estimation.h 中添加成员:
   std::unique_ptr<MyNewEstimator> my_estimator_;

3. 在 UpdateEstimate() 中集成:
   void SendSideBandwidthEstimation::UpdateEstimate(...) {
     // 在 LossBasedBweV2 检查之后添加:
     if (my_estimator_->Ready()) {
       DataRate new_bitrate = my_estimator_->bitrate();
       UpdateTargetBitrate(new_bitrate, at_time);
       return;
     }
     ...
   }

4. 在 goog_cc_network_control.cc 中调用:
   bandwidth_estimation_->my_estimator_->Update(packet_results);

5. 在 BUILD.gn 中添加编译依赖
```

### 场景 7: 调整 REMB/接收端影响

**目标**: 改变接收端估计对发送端的权重

**修改位置**: `send_side_bandwidth_estimation.cc`

```cpp
// receiver_limit_ 直接限制最终 target_rate:
// send_side_bandwidth_estimation.cc:333
//   target = min(target, receiver_limit_)

// 如果想降低 REMB 的权重:
//   → 修改 target_rate() 中的 min 逻辑
//   → 或在 receive_side_congestion_controller 中调整 REMB 发送策略
```

### 场景 8: 调整拥塞窗口 (Cwnd)

**目标**: 改变 Cwnd 大小以适配不同网络类型

**修改位置**: `goog_cc_network_control.cc` → `UpdateCongestionWindowSize`

```cpp
// 当前公式: cwnd = last_loss_based_target_rate × (min_feedback_max_rtt + additional_time)
// additional_time 来自 RateControlSettings::GetCongestionWindowAdditionalTimeMs()

// 增大 Cwnd (适合高带宽延迟积网络):
//   → 增大 additional_time_ms

// 减小 Cwnd (低延迟优先):
//   → 减小 additional_time_ms，或直接使用 CongestionWindowPushbackController
```

### 场景 9: 通过 Field Trial 快速实验

WebRTC 的 Field Trial 系统允许运行时切换参数，无需重新编译:

```python
# Python 示例: 设置 Field Trial
import webrtc

# 组合多个参数
field_trial = (
    "WebRTC-TrendlineEstimatorSettings:window_size_50:"
    "WebRTC-RateControlSettings:k_up_0.012:k_down_0.03:"
    "WebRTC-ProbeControllerConfig:alr_probing_interval_5000ms"
)
```

**常用 Field Trial 键**:
| Field Trial 键 | 控制内容 |
|----------------|----------|
| `WebRTC-TrendlineEstimatorSettings` | 延迟检测窗口、cap、threshold |
| `WebRTC-RateControlSettings` | AIMD 的 k_up_/k_down_ |
| `WebRTC-ProbeControllerConfig` | 探测倍率、间隔 |
| `WebRTC-LossBasedBweV2` | 丢包估计参数 |
| `WebRTC-Bwe-MaxRttLimit` | RTT 回退阈值 |
| `WebRTC-Bwe-LinkCapacity` | 链路容量跟踪速率 |

### 场景 10: 切换 goog-CC 和 PCC

**修改位置**: `Call` 初始化或 `NetworkControllerInterface` 工厂

```cpp
// 当前默认: GoogCcNetworkController
// 切换到 PCC:
// auto controller = std::make_unique<pcc::PccNetworkController>(config);
// 而非:
// auto controller = std::make_unique<GoogCcNetworkController>(config, goog_cc_config);

// PCC 更适合稳定高带宽网络 (如数据中心)，goog-CC 更适合变化剧烈的公网
```

---

## 四、修改代码时的注意事项

1. **线程安全**: `SendSideBandwidthEstimation` 和 `DelayBasedBwe` 中的关键方法通过 `network_race_` 做序列化保护，修改时不要破坏这个锁
2. **ALR 感知**: `AlrDetector` 检测应用受限区域，ALR 期间发送的流量不反映网络容量。所有估计器都通过 `in_alr` 参数感知此状态
3. **最小/最大码率约束**: `min_data_rate_` 和 `max_data_rate_` 在所有估计输出前被 clamp，修改估计逻辑后仍需遵守这些边界
4. **Pacing Factor**: 最终 pacing 速率 = target_rate × pacing_factor (默认 2.5)，过大会导致缓冲区膨胀，过小会导致发送不足
5. **RTT 反馈**: RTT 更新同时影响 `DelayBasedBwe::OnRttUpdate()` 和 `RttBasedBackoff`，两者独立但协同工作
