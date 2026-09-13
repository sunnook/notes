# WebRTC 音视频算法分析 —— 规划文档

> 目标产出：`wr-alg-analysis.md`（与 `wr-arch-design-analysis.md` / `wr-modules-analysis.md` 互补，本文聚焦**算法设计、内部原理、参数配置、模块交互、业务场景**）。
> 读者画像：具备 C/C++ 与音视频基础，希望深入理解 WebRTC 各算法模块的"为什么这样设计 + 怎么工作 + 在什么场景生效"。

---

## 0. 设计原则与写作约定

- **算法为主，架构为辅**：架构/分层/类图在已有文档中详述，本文仅在必要处用"局部架构图 / 数据流图 / 控制流图"辅助说明算法，不重复整库架构。
- **结合代码**：每个算法给出 `文件路径`、关键类/结构体名、关键方法名、参数字段名与默认值（尽量逐字引用）。
- **业务场景驱动**：每个算法末尾用"业务场景作用"小节说明在 正常通话 / 弱网 / 丢包 / 抖动 / 双讲 / 回声 / 屏幕共享 等场景下如何工作。
- **图示**：使用 ASCII 图（总体架构图、数据流图、控制流图、状态机图、局部模块交互图、类关系图）。
- **持久化策略**：按章写入 `wr-alg-analysis.md`，每章完成后确认文件已落盘；长章分多次追加；章间回读确认完整性；最后在开头插入带索引的目录。

---

## 章节大纲

### 第 1 章：算法全景与文件结构
- 1.1 WebRTC 算法体系总览（音频处理 / 音频编解码接收 / 视频编解码 / 拥塞控制 / pacing 五大算法域）
- 1.2 算法在整体架构中的位置（一张总图：采集→处理→编码→pacing→网络→接收→jitter→解码→渲染，标注各算法落点）
- 1.3 **文件结构设计**：按算法域列出关键文件夹/文件作用与算法关系
  - `modules/audio_processing/`（AEC3/aecm/NS/AGC/AGC2/VAD/HPF/transient/echo_detector）
  - `common_audio/`（signal_processing / resampler / vad / fir_filter）
  - `modules/audio_coding/neteq/`（jitter buffer + PLC + 时间拉伸）
  - `modules/audio_coding/codecs/`（opus/g711/g722/isac/cng/red）
  - `modules/video_coding/`（frame_buffer2 / jitter_estimator / nack_module / fec / packet_buffer / reference_finder / utility[quality_scaler/frame_dropper/simulcast_rate_allocator]）
  - `modules/video_coding/codecs/`（vp8/vp9/h264/av1）
  - `modules/video_processing/`（denoiser）
  - `video/`（video_stream_encoder / adaptation / encoder_bitrate_adjuster / overshoot_detector / rtp_video_stream_receiver / receive_statistics_proxy）
  - `modules/congestion_controller/`（goog_cc / pcc / rtp / receive_side）
  - `modules/remote_bitrate_estimator/`（aimd / overuse / inter_arrival / remote_estimator_proxy）
  - `modules/pacing/`（pacing_controller / bitrate_prober / interval_budget / round_robin_packet_queue）
  - `modules/rtp_rtcp/source/`（forward_error_correction / flexfec / rtcp / receive_statistics）
  - `api/transport/`（network_control / network_types 控制接口与数据结构）
  - 文件夹↔算法↔业务场景 三栏对照表
- 1.4 核心数据结构与控制接口速查（`AudioProcessing::Config`、`NetEq::Config`、`EchoCanceller3Config`、`NsConfig`、`NetworkControlUpdate`/`TargetTransferRate`/`PacerConfig`、`VideoEncoder::QpThresholds`）

### 第 2 章：音频处理算法（APE 管线与子算法）
- 2.1 APE 处理管线总览（`ProcessCaptureStreamLocked` 顺序图：HPF→pre_amp→AEC3.AnalyzeCapture→AGC1.AnalyzePreProcess→分带→HPF(split)→AGC1.Analyze→NS.Analyze→AEC3.ProcessCapture→NS.Process→VAD→AGC1.Process→合带→echo_detector→transient→AGC2→level_estimator；render 侧 `ProcessRenderStreamLocked`）
- 2.2 **AEC3 回声消除**
  - 设计目标与定位（render/capture 双路、块处理 64 样本/block、250 block/s）
  - 核心原理：分区块频域自适应滤波（partitioned block frequency-domain NLMS）、双滤波器（coarse 粗对齐 + refined 精细）、时延估计（matched filter + decimator 降采样）、回声路径变化检测、近端检测（dominant nearend detector）、ERL/ERLE 估计、舒适噪声、reverb 建模
  - 关键参数（`EchoCanceller3Config`：Delay.down_sampling_factor=4/num_filters=5、Filter.RefinedConfiguration/CoarseConfiguration、Erle.min/max、EpStrength、EchoAudibility、initial_state_seconds=2.5 等）
  - 核心类：`EchoCanceller3`→`BlockProcessor`→`EchoRemover`/`RenderDelayController`/`EchoPathDelayEstimator`/`MatchedFilter`/`AdaptiveFirFilter`/`SuppressionFilter`/`ComfortNoiseGenerator`/`ReverbModel`/`AecState`/`ErleEstimator`/`ErlEstimator`/`DominantNearendDetector`
  - 算法流程（逐 block：render 入队→对齐→滤波→残差→抑制→输出）
  - 业务场景：正常双讲、回声路径突变（音量/设备切换）、远端单讲、近端单讲
- 2.3 **NS 降噪**
  - 设计目标与定位（频域、160 样本帧、256 FFT、分带）
  - 核心原理：先验/后验 SNR 估计、量化噪声估计（quantile）、Wiener 滤波、语音概率估计（LRT/spectralFlatness/spectralDiff 三特征）、抑制曲线
  - 关键参数（`NsConfig::SuppressionLevel` k6/12/18/21dB，默认 k12dB；`analyze_linear_aec_output_when_available`）
  - 核心类：`NoiseSuppressor`→`NoiseEstimator`/`QuantileNoiseEstimator`/`WienerFilter`/`PriorSignalModelEstimator`/`SignalModelEstimator`/`SpeechProbabilityEstimator`/`SuppressionParams`/`NsFft`
  - 算法流程（Analyze 估噪→Process 维纳增益）
  - 业务场景：稳态噪声、非稳态噪声、低 SNR
- 2.4 **AGC2 自适应增益（含 RNN VAD）**
  - 设计目标与定位（数字增益、目标电平、RNN VAD 区分语音）
  - 核心原理：固定数字增益 + 自适应数字增益（`AdaptiveDigitalGainApplier`，基于 `VadWithLevel` + `NoiseLevelEstimator` + `AdaptiveModeLevelEstimator` + `SaturationProtector`）、限幅器（`Limiter` + `LimiterDbGainCurve`）、插值增益曲线、每秒最大变化 3dB
  - 关键参数（`GainController2`：fixed_digital.gain_db=0、adaptive_digital.enabled/level_estimator(kRms)/use_saturation_protector/extra_saturation_margin_db=2；`agc2_common.h`：kMaxGainDb=30/kInitialAdaptiveDigitalGainDb=8/kHeadroomDbfs=1/kMaxGainChangePerSecondDb=3）
  - 核心类：`GainController2`→`AdaptiveAgc`/`FixedDigitalLevelEstimator`/`AdaptiveDigitalGainApplier`/`InterpolatedGainCurve`/`Limiter`/`NoiseLevelEstimator`/`SaturationProtector`/`RnnVad`(rnn_vad/)
  - 算法流程与业务场景
- 2.5 **AGC1 旧版增益**（loudness histogram + 模拟/数字增益、`agc_manager_direct`、`gain_map_internal`、target_level_dbfs=3/compression_gain_db=9）
- 2.6 **VAD / HPF / transient / echo_detector / voice_detection** 辅助算法
- 2.7 音频处理数据流图 + 类关系图（局部）

### 第 3 章：音频接收算法（NetEq）
- 3.1 设计目标与定位（jitter buffer + PLC + 时间拉伸，10ms 输出）
- 3.2 整体架构与文件结构（`neteq_impl`/`decision_logic`/`delay_manager`/`buffer_level_filter`/`expand`/`accelerate`/`preemptive_expand`/`time_stretch`/`merge`/`normal`/`sync_buffer`/`packet_buffer`/`statistics_calculator`/`histogram`/`background_noise`/`comfort_noise`/`nack_tracker`/`post_decode_vad`）
- 3.3 **决策状态机**（NORMAL/EXPAND/ACCELERATE/PREEMPTIVE_EXPAND/MERGE/FADE/REPLACE/CNG/DTMF；`GetDecision` 触发条件：buffer level vs target、包可用/丢失/迟到）
- 3.4 **DelayManager IAT 直方图→目标缓冲**（`histogram`、quantile、`CalculateTargetLevel`、`BufferLimits` 上下限）
- 3.5 **BufferLevelFilter**（漏桶/泄漏积分器）
- 3.6 **Expand (PLC)**（相关/基音周期估计/overlap-add/连续丢包静音衰减，`kMaxConsecutiveExpands=200`）
- 3.7 **WSOLA 时间拉伸**（Accelerate 加速/Preemptive 抢占、相关搜索、overlap-add、拉伸样本数）
- 3.8 **Merge**（expand 尾与新解码的 crossfade）
- 3.9 **背景噪声 / 舒适噪声**（CNG）
- 3.10 关键参数（`NetEq::Config`：sample_rate_hz=16000/max_packets_in_buffer=200/max_delay_ms/min_delay_ms/enable_fast_accelerate/enable_muted_state/enable_rtx_handling/for_test_no_time_stretching；常量 kOutputSizeMs=10/kMaxFrameSize=5760）
- 3.11 算法流程：`InsertPacket` 流 + `GetAudio` 决策流（带方法名）
- 3.12 业务场景：正常到达、抖动尖峰、单/多包丢失、迟到包、时钟漂移、DTMF

### 第 4 章：视频发送算法
- 4.1 发送管线总览（采集→VPM→VideoStreamEncoder→质量适配→编码→SimulcastRateAllocator→BitrateAllocator→pacing）
- 4.2 **质量缩放 QualityScaler**（QP 阈值、上下采样决策、`CheckQpTask` 周期检查、`QpSmoother` 平滑、与帧率耦合）
- 4.3 **帧丢弃 FrameDropper**（leaky bucket 累加器、`Fill`/`Leak`/`DropFrame`、编码过载丢帧）
- 4.4 **Simulcast 码率分配 SimulcastRateAllocator**（空间/时间层分配、`DefaultTemporalLayerAllocation`、码率限制表）
- 4.5 **BitrateAllocator（call/）**（多流比例公平：min/max/priority_bitrate/bitrate_priority/enforce_min_bitrate）
- 4.6 **EncoderBitrateAdjuster / OvershootDetector**（编码器超发检测与目标码率回压）
- 4.7 **资源管理 VideoStreamEncoderResourceManager**（CPU/质量/带宽/编码用时资源、`overuse_frame_detector`、适配决策流：CPU/带宽/质量→分辨率/帧率/码率）
- 4.8 关键参数（`VideoEncoderConfig`/`VideoCodec`/`VideoEncoder::QpThresholds`/`RtpConfig`）
- 4.9 业务场景：弱网降分辨率、CPU 过载降帧率、屏幕共享高码率

### 第 5 章：视频接收算法
- 5.1 接收管线总览（RTP→packet_buffer→reference_finder→frame_buffer(jitter)→解码调度→解码→渲染）
- 5.2 **FrameBuffer2 抖动缓冲**（解码调度、decodable-first 策略、连续性/参考依赖等待、基于渲染时间的等待、丢包处理、`NextFrame`/`InsertFrame`）
- 5.3 **JitterEstimator + InterFrameDelay + Timing**（帧间延迟方差→jitter、噪声估计、`VCMTiming` 渲染时间计算与延迟调整）
- 5.4 **NACK 模块**（序号缺口检测、RTT 退避、`BackoffSettings`、`send_at_seq_num`、最大重试、`GetNackBatch`）
- 5.5 **FEC**（`ForwardErrorCorrection` ULPXOR / flexfec、掩码表 `fec_private_tables_*`、每媒体组生成 FEC、接收端恢复；`FecControllerDefault`）
- 5.6 **PacketBuffer / RtpFrameReferenceFinder / H264SpsPpsTracker / LossNotificationController**
- 5.7 关键参数（FEC 参数、frame buffer max wait、nack max retries、protection mode）
- 5.8 业务场景：随机丢包（NACK）、突发丢包（FEC）、关键帧丢失、抖动、屏幕共享

### 第 6 章：拥塞控制算法（GoogCC / PCC / 接收侧 BWE）
- 6.1 拥塞控制全景与闭环（发送包→transport-cc 反馈→估计→速率决策→pacer→编码器）
- 6.2 **GoogCC 控制循环**（`GoogCcNetworkController`：`OnSentPacket`/`OnTransportPacketsFeedback`/`OnProcessInterval`）
- 6.3 **Trendline 延迟估计**（累积延迟增量、线性回归斜率、`kDefaultTrendlineWindowSize=20`/`kDefaultTrendlineThresholdGain=4.0`/smoothing 0.9、overuse/underuse/normal 状态机、hold time）
- 6.4 **AIMD 速率控制**（`AimdRateControl`：Hold/Increase/Decrease、加性增/乘性减、`GetNearMaxIncreaseRateBpsPerSecond`、RTT）
- 6.5 **ALR 检测**（`AlrDetector`：bytes vs expected，触发探测）
- 6.6 **探测 ProbeController + ProbeBitrateEstimator**（probe cluster min/max bitrate、包数、间隔、探测结果评估）
- 6.7 **AcknowledgedBitrateEstimator / BitrateEstimator**（ACK 窗口码率）
- 6.8 **LossBasedBandwidthEstimation**（丢包率阈值→降速）
- 6.9 **SendSideBandwidthEstimation**（REMB/TMMBR 接收端报告回退路径）
- 6.10 **CongestionWindowPushbackController**（cwnd + alr 对编码器回压）
- 6.11 接收侧 BWE（`remote_bitrate_estimator`：`overuse_estimator`/`overuse_detector`/`inter_arrival`/`aimd_rate_control`、`remote_estimator_proxy` transport-cc 反馈代理、`ReceiveSideCongestionController`）
- 6.12 **PCC**（monitor interval + 效用函数梯度，简述）
- 6.13 关键参数与数据结构（`NetworkControlUpdate`/`TargetTransferRate`/`PacerConfig`/`ProbeClusterConfig`、AIMD 因子、探测码率）
- 6.14 业务场景：稳态、容量突降（overuse）、容量上升（探测）、高丢包链路、应用受限（屏幕共享低码率）

### 第 7 章：Pacing 与 RTP/RTCP 算法
- 7.1 **PacingController**（leaky bucket、`SetPacingRates`、`kDefaultPaceMultiplier`、周期/动态模式、cwnd）
- 7.2 **BitrateProber**（probe cluster 注入、`CreateProbeCluster`）
- 7.3 **IntervalBudget**（令牌桶预算、`target_rate_kbps`/`bytes_remaining`/`can_build_up_underuse`）
- 7.4 **RoundRobinPacketQueue**（优先级：audio > video > retransmit > fec/padding）
- 7.5 **RTP/RTCP**（封包/解包、`receive_statistics`、RTCP 报告、transport-cc 反馈生成）
- 7.6 关键参数与业务场景

### 第 8 章：算法协同与业务场景总览
- 8.1 端到端算法协同图（发送侧：APE→编码→码率分配→pacing→拥塞控制；接收侧：jitter→PLC/FEC/NACK→解码→渲染）
- 8.2 闭环反馈链（接收 transport-cc/RTCP → GoogCC → 目标码率 → BitrateAllocator → SimulcastRateAllocator → 编码器 + pacer；视频质量 → QualityScaler → 分辨率/帧率）
- 8.3 典型业务场景算法联动
  - 弱网降码率（GoogCC overuse → 降码率 → Simulcast 降层 → QualityScaler 降分辨率）
  - 丢包恢复（NACK 短期 + FEC 突发 + 关键帧请求）
  - 抖动应对（NetEq 时间拉伸 / FrameBuffer 解码调度 + JitterEstimator）
  - 回声场景（AEC3 + NS + AGC2 联动）
  - 屏幕共享（ALR + 低帧率高码率 + FEC）
- 8.4 算法参数调优速查表（按场景给出推荐配置）

### 附录
- A. 关键文件-类-参数索引表（按算法域）
- B. 术语表（AEC/ERL/ERLE/PLC/WSOLA/BWE/ALR/transport-cc/REMB/TMMBR/FEC/NACK/Simulcast）
- C. 参考文档（`wr-arch-design-analysis.md`、`wr-modules-analysis.md`、`neteq/docs-lu/nq.md`）

---

## 执行计划

1. 先写本规划文档（当前文件）。
2. 创建 `wr-alg-analysis.md`，按章顺序写入：
   - 第 1 章（全景 + 文件结构）
   - 第 2 章（音频处理算法，较长，分 2-3 次追加）
   - 第 3 章（NetEq）
   - 第 4 章（视频发送）
   - 第 5 章（视频接收）
   - 第 6 章（拥塞控制，较长，分 2 次追加）
   - 第 7 章（Pacing/RTP）
   - 第 8 章（算法协同 + 场景）
   - 附录
3. 每章写完用 `ls -l` + `wc -l` 确认落盘；章间回读已写章节标题确认完整。
4. 全部完成后，在文档开头插入带索引的目录（章节标题 + 锚点）。
5. 若单文件过大（>800KB），提示拆分为多文件。

## 预估规模
- 8 章 + 附录，预估 1200-1800 行 Markdown，约 80-130KB。
- 若实际超过预期，按域拆为 `wr-alg-audio.md` / `wr-alg-video.md` / `wr-alg-cc.md`。
