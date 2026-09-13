# WebRTC 音视频算法分析

> 读者画像：具备 C/C++ 与音视频基础，希望深入理解 WebRTC 各算法模块的"为什么这样设计 + 怎么工作 + 在什么场景生效"。
>
> 相关文档（互补）：
> - `wr-arch-design-analysis.md`：架构设计（分层/并发/传输/设计模式）
> - `wr-modules-analysis.md`：模块架构（26 个模块的职责与协作）
> - `wr-whole-process.md`：完整业务流程
> - `neteq/docs-lu/nq.md`：NetEq 代码深度分析
>
> 本文聚焦**算法**：算法设计目标、内部原理、参数配置、模块交互、核心数据结构、数据流/控制流、各业务场景下如何发挥作用。架构/分层/类图仅在必要处用局部图辅助，不重复整库架构。

---

## 目录

- [WebRTC 音视频算法分析](#webrtc-音视频算法分析)
  - [第 1 章：算法全景与文件结构](#第-1-章算法全景与文件结构)
    - [1.1 WebRTC 算法体系总览](#11-webrtc-算法体系总览)
    - [1.2 算法在整体架构中的位置](#12-算法在整体架构中的位置)
    - [1.3 文件结构设计（文件夹/文件作用与算法关系）](#13-文件结构设计文件夹文件作用与算法关系)
      - [1.3.1 音频处理域 `modules/audio_processing/`](#131-音频处理域-`modulesaudio_processing`)
      - [1.3.2 公共音频工具 `common_audio/`](#132-公共音频工具-`common_audio`)
      - [1.3.3 音频接收域 `modules/audio_coding/neteq/`](#133-音频接收域-`modulesaudio_codingneteq`)
      - [1.3.4 视频发送域 `video/` + `modules/video_coding/utility/` + `call/`](#134-视频发送域-`video`-+-`modulesvideo_codingutility`-+-`call`)
      - [1.3.5 视频接收域 `modules/video_coding/` + `modules/rtp_rtcp/source/`](#135-视频接收域-`modulesvideo_coding`-+-`modulesrtp_rtcpsource`)
      - [1.3.6 拥塞控制域 `modules/congestion_controller/` + `modules/remote_bitrate_estimator/` + `modules/pacing/`](#136-拥塞控制域-`modulescongestion_controller`-+-`modulesremote_bitrate_estimator`-+-`modulespacing`)
      - [1.3.7 文件夹↔算法↔业务场景对照表](#137-文件夹↔算法↔业务场景对照表)
    - [1.4 核心数据结构与控制接口速查](#14-核心数据结构与控制接口速查)
  - [第 2 章：音频处理算法（APE 管线与子算法）](#第-2-章音频处理算法ape-管线与子算法)
    - [2.1 APE 处理管线总览](#21-ape-处理管线总览)
    - [2.2 AEC3 回声消除](#22-aec3-回声消除)
      - [2.2.1 深入：AEC3 的数学原理（频域时域、自适应滤波公式）](#221-深入aec3-的数学原理频域时域自适应滤波公式)
    - [2.3 NS 降噪](#23-ns-降噪)
      - [2.3.1 深入：NS 的数学原理（频域、SNR、Wiener 滤波公式）](#231-深入ns-的数学原理频域snrwiener-滤波公式)
    - [2.4 AGC2 自适应增益（含 RNN VAD）](#24-agc2-自适应增益含-rnn-vad)
      - [2.4.1 深入：AGC2 的数学原理（增益映射、限速、限幅公式）](#241-深入agc2-的数学原理增益映射限速限幅公式)
    - [2.5 AGC1 旧版增益](#25-agc1-旧版增益)
      - [2.5.1 深入：AGC1 的数学原理（响度直方图 + 模拟增益闭环）](#251-深入agc1-的数学原理响度直方图-+-模拟增益闭环)
    - [2.6 VAD / HPF / transient / echo_detector 辅助算法](#26-vad-hpf-transient-echo_detector-辅助算法)
      - [2.6.1 深入：VAD / HPF 的数学原理](#261-深入vad-hpf-的数学原理)
    - [2.7 音频处理数据流图与类关系](#27-音频处理数据流图与类关系)
  - [第 3 章：音频接收算法（NetEq）](#第-3-章音频接收算法neteq)
    - [3.1 设计目标与定位](#31-设计目标与定位)
    - [3.2 整体架构与文件结构](#32-整体架构与文件结构)
    - [3.3 决策状态机](#33-决策状态机)
    - [3.4 DelayManager：IAT 直方图 → 目标缓冲](#34-delaymanageriat-直方图-→-目标缓冲)
    - [3.5 BufferLevelFilter：缓冲电平泄漏积分器](#35-bufferlevelfilter缓冲电平泄漏积分器)
    - [3.6 Expand：PLC 丢包隐藏](#36-expandplc-丢包隐藏)
    - [3.7 WSOLA 时间拉伸（Accelerate / PreemptiveExpand）](#37-wsola-时间拉伸accelerate-preemptiveexpand)
      - [3.7.1 深入：WSOLA 的数学原理（波形相似性重叠相加）](#371-深入wsola-的数学原理波形相似性重叠相加)
    - [3.8 Merge：expand ↔ normal 衔接](#38-mergeexpand-↔-normal-衔接)
      - [3.8.1 深入：Merge 的数学原理（相关对齐 + 交叉渐变）](#381-深入merge-的数学原理相关对齐-+-交叉渐变)
    - [3.9 背景噪声 / 舒适噪声（CNG）](#39-背景噪声-舒适噪声cng)
    - [3.10 关键参数](#310-关键参数)
    - [3.11 算法流程](#311-算法流程)
    - [3.12 业务场景作用](#312-业务场景作用)
  - [第 4 章：视频发送算法](#第-4-章视频发送算法)
    - [4.1 发送管线总览](#41-发送管线总览)
    - [4.2 质量缩放 QualityScaler](#42-质量缩放-qualityscaler)
    - [4.3 帧丢弃 FrameDropper](#43-帧丢弃-framedropper)
    - [4.4 Simulcast 码率分配 SimulcastRateAllocator](#44-simulcast-码率分配-simulcastrateallocator)
    - [4.5 BitrateAllocator（多流码率分配）](#45-bitrateallocator多流码率分配)
    - [4.6 EncoderBitrateAdjuster / OvershootDetector](#46-encoderbitrateadjuster-overshootdetector)
    - [4.7 资源管理 VideoStreamEncoderResourceManager](#47-资源管理-videostreamencoderresourcemanager)
    - [4.8 关键参数](#48-关键参数)
    - [4.9 业务场景作用](#49-业务场景作用)
  - [第 5 章：视频接收算法](#第-5-章视频接收算法)
    - [5.1 接收管线总览](#51-接收管线总览)
    - [5.2 FrameBuffer2：视频抖动缓冲](#52-framebuffer2视频抖动缓冲)
    - [5.3 JitterEstimator + InterFrameDelay + Timing](#53-jitterestimator-+-interframedelay-+-timing)
    - [5.4 NACK 模块](#54-nack-模块)
    - [5.5 FEC（前向纠错）](#55-fec前向纠错)
      - [5.5.1 深入：FEC 的掩码表与码率数学](#551-深入fec-的掩码表与码率数学)
    - [5.6 PacketBuffer / RtpFrameReferenceFinder / H264SpsPpsTracker / LossNotificationController](#56-packetbuffer-rtpframereferencefinder-h264spsppstracker-lossnotificationcontroller)
    - [5.7 关键参数](#57-关键参数)
    - [5.8 业务场景作用](#58-业务场景作用)
  - [第 6 章：拥塞控制算法（GoogCC / PCC / 接收侧 BWE）](#第-6-章拥塞控制算法googcc-pcc-接收侧-bwe)
    - [6.1 拥塞控制全景与闭环](#61-拥塞控制全景与闭环)
    - [6.2 GoogCC 控制循环](#62-googcc-控制循环)
    - [6.3 Trendline 延迟估计](#63-trendline-延迟估计)
    - [6.4 AIMD 速率控制](#64-aimd-速率控制)
    - [6.5 ALR 检测](#65-alr-检测)
    - [6.6 探测 ProbeController + ProbeBitrateEstimator](#66-探测-probecontroller-+-probebitrateestimator)
    - [6.7 AcknowledgedBitrateEstimator](#67-acknowledgedbitrateestimator)
    - [6.8 LossBasedBandwidthEstimation](#68-lossbasedbandwidthestimation)
    - [6.9 SendSideBandwidthEstimation（REMB/TMMBR 回退）](#69-sendsidebandwidthestimationrembtmmbr-回退)
    - [6.10 CongestionWindowPushbackController](#610-congestionwindowpushbackcontroller)
    - [6.11 接收侧 BWE](#611-接收侧-bwe)
    - [6.12 PCC（备选拥塞控制）](#612-pcc备选拥塞控制)
    - [6.13 关键参数与数据结构](#613-关键参数与数据结构)
    - [6.14 业务场景作用](#614-业务场景作用)
  - [第 7 章：Pacing 与 RTP/RTCP 算法](#第-7-章pacing-与-rtprtcp-算法)
    - [7.1 PacingController（漏桶发送整形）](#71-pacingcontroller漏桶发送整形)
    - [7.2 BitrateProber（探测注入）](#72-bitrateprober探测注入)
    - [7.3 IntervalBudget（令牌桶预算）](#73-intervalbudget令牌桶预算)
    - [7.4 RoundRobinPacketQueue（优先级队列）](#74-roundrobinpacketqueue优先级队列)
    - [7.5 RTP/RTCP](#75-rtprtcp)
    - [7.6 关键参数与业务场景](#76-关键参数与业务场景)
  - [第 8 章：算法协同与业务场景总览](#第-8-章算法协同与业务场景总览)
    - [8.1 端到端算法协同图](#81-端到端算法协同图)
    - [8.2 闭环反馈链](#82-闭环反馈链)
    - [8.3 典型业务场景算法联动](#83-典型业务场景算法联动)
    - [8.4 算法参数调优速查表](#84-算法参数调优速查表)
  - [附录](#附录)
    - [A. 关键文件-类-参数索引表（按算法域）](#a-关键文件-类-参数索引表按算法域)
    - [B. 术语表](#b-术语表)
    - [C. 参考文档](#c-参考文档)

---

## 第 1 章：算法全景与文件结构

### 1.1 WebRTC 算法体系总览

WebRTC 的"算法"分布在五个域，分别解决实时音视频通信中的五类问题：

| 算法域 | 解决的核心问题 | 代表算法 | 位置 |
|---|---|---|---|
| **音频处理（APE）** | 回声、噪声、音量不均、语音检测 | AEC3 回声消除、NS 降噪、AGC2 自适应增益、VAD、HPF | `modules/audio_processing/`、`common_audio/` |
| **音频接收（NetEq）** | 网络抖动、丢包、乱序、时钟漂移 | Jitter Buffer、PLC（丢包隐藏）、WSOLA 时间拉伸、CNG | `modules/audio_coding/neteq/` |
| **视频发送** | 编码质量/码率/分辨率/帧率的自适应 | QualityScaler 质量缩放、FrameDropper 丢帧、SimulcastRateAllocator、BitrateAllocator、EncoderBitrateAdjuster | `video/`、`modules/video_coding/utility/`、`call/` |
| **视频接收** | 抖动、丢包恢复、解码调度 | FrameBuffer2、JitterEstimator、NACK、FEC（ULPXOR/flexfec）、PacketBuffer、ReferenceFinder | `modules/video_coding/`、`modules/rtp_rtcp/source/` |
| **拥塞控制 + Pacing** | 网络带宽估计与码率闭环、发送整形 | GoogCC（trendline + AIMD + 探测）、ALR、PCC、PacingController、BitrateProber、IntervalBudget | `modules/congestion_controller/`、`modules/remote_bitrate_estimator/`、`modules/pacing/` |

这五个域不是孤立的：**拥塞控制是总开关**，它输出的目标码率同时驱动视频编码器码率、Simulcast 层分配和 Pacing 速率；**NetEq 和 FrameBuffer 是接收侧的双子星**，分别用时间拉伸和延迟调度对抗抖动；**APE 是发送侧音频质量的最后一道关**，在编码前处理原始 PCM。

### 1.2 算法在整体架构中的位置

下面这张总图标出各算法在端到端管线中的落点（发送侧 + 接收侧 + 反馈闭环）：

```
                              ┌──────────── 发送侧 ────────────┐
  麦克风 ──► ADM ──► APE音频处理 ──► 音频编码 ──────────────────┐
  (采集)         │   AEC3/NS/AGC2/VAD/HPF      (Opus/G711)      │
                │                                              ▼
                │                                         ┌─ Pacing ──┐  ──► 网络
  摄像头 ──► VPM ──► VideoStreamEncoder ──► 视频编码 ──────► │整形/探测  │
  (采集)   (裁剪/    │ QualityScaler  (VP8/VP9/H264)         │IntervalBudget│
           旋转)     │ FrameDropper                         └────────────┘
                    │ SimulcastRateAllocator                       ▲
                    │                                            │ 目标码率
                    └─► BitrateAllocator ◄── GoogCC ──────────────┘
                                  ▲              (trendline+AIMD+探测)
                                  │                      ▲
                                  └──── ALR/丢包/RTT ◄───┤
                                                         │
                              ┌──────────── 接收侧 ──────┴───┐
  网络 ──► RTP解包 ──► PacketBuffer ──► FrameBuffer2 ──► 视频解码 ──► 渲染
            │           (组帧)        (jitter调度)    (VP8/..)   ▲
            │              │             │                       │ 渲染时间
            │           ReferenceFinder  JitterEstimator ──► Timing
            │              │             │
            │           NACK模块 ◄── 丢包 ──► FEC恢复(ULPXOR/flexfec)
            │
            └─► NetEq ──► 音频解码 ──► 扬声器
                (Jitter+PLC+WSOLA)
```

**关键闭环**：接收侧通过 transport-cc 反馈（包到达时间）+ RTCP（丢包率/RTT）把网络状态回传发送侧；GoogCC 据此输出 `TargetTransferRate`，经 `BitrateAllocator` 分配给各流，再经 `SimulcastRateAllocator` 分到空间/时间层，最终落到编码器目标码率与 Pacing 速率。视频质量侧由 `QualityScaler` 根据 QP 反馈调整分辨率/帧率。

### 1.3 文件结构设计（文件夹/文件作用与算法关系）

WebRTC 的算法代码按"问题域"组织，而非按"发送/接收"组织。同一算法域的文件集中在同一目录，目录内的文件再按子算法细分。下面按算法域列出关键文件夹/文件作用。

#### 1.3.1 音频处理域 `modules/audio_processing/`

| 文件/子目录 | 作用 | 对应算法 |
|---|---|---|
| `audio_processing_impl.cc/.h` | **APE 主控**，组装 capture/render 处理管线，持有所有子模块 | 管线调度 |
| `include/audio_processing.h` | `AudioProcessing` 接口 + `Config`（`EchoCanceller`/`NoiseSuppression`/`GainController1`/`GainController2`/`HighPassFilter`/`VoiceDetection` 等嵌套配置） | 全域配置入口 |
| `audio_buffer.cc/.h` | 分带音频缓冲（fullband ↔ split bands），算法在分带域操作 | 数据载体 |
| `aec3/` | **AEC3 回声消除**（约 100 个文件） | 回声消除 |
| `aecm/` | 移动端轻量回声消除（AECM） | 回声消除（移动） |
| `ns/` | **NS 降噪**（频域 Wiener） | 降噪 |
| `agc2/` | **AGC2 自适应增益**（含 `rnn_vad/` RNN VAD） | 增益控制 |
| `agc/` | AGC1 旧版增益（loudness histogram） | 增益控制（旧） |
| `gain_control_impl.cc/.h` | AGC1 的 APE 适配层 | 增益控制 |
| `gain_controller2.cc/.h` | AGC2 的 APE 适配层 | 增益控制 |
| `high_pass_filter.cc/.h` | 高通滤波（去直流/低频噪声） | 预处理 |
| `voice_detection.cc/.h` | 语音检测（VAD 结果上报） | VAD |
| `transient/` | 瞬态抑制（键盘/敲击噪声） | 瞬态抑制 |
| `echo_detector/` + `residual_echo_detector.cc` | 残留回声检测（统计量） | 回声检测 |
| `vad/` | APE 内部 VAD（能量/过零率） | VAD |
| `splitting_filter.cc/.h` + `three_band_filter_bank.cc/.h` | 三带分带/合带滤波 | 分带 |
| `rms_level.cc/.h` + `level_estimator.cc/.h` | RMS/电平估计 | 电平 |
| `typing_detection.cc/.h` | 键盘敲击检测 | 瞬态 |

`aec3/` 内部按"处理阶段"再细分：`echo_canceller3`（入口）→ `block_processor`（块处理主控）→ `echo_remover`（回声消除核心）+ `render_delay_controller`（对齐）+ `echo_path_delay_estimator`/`matched_filter`（时延估计）+ `adaptive_fir_filter`（自适应滤波器）+ `suppression_filter`/`comfort_noise_generator`/`reverb_model`（后处理）+ `erl_estimator`/`erle_estimator`/`dominant_nearend_detector`/`aec_state`（状态与指标）。

#### 1.3.2 公共音频工具 `common_audio/`

| 文件/子目录 | 作用 | 算法关系 |
|---|---|---|
| `signal_processing/` | 定点 DSP 原语（能量、自相关、滤波、AGC 旧版） | AECM/AGC1/VAD 底层 |
| `vad/` | 独立 VAD（能量 + 子带 + 基音） | 音频编码/NetEq/APE 共用 |
| `resampler/` | 重采样 | 采样率适配 |
| `fir_filter_*.{cc,h}` | FIR 滤波（C/NEON/SSE 多版本） | AEC/NS/resampler |
| `real_fourier*.{cc,h}` | FFT 封装（Ooura） | AEC3/NS 频域处理 |
| `window_generator.cc/.h` | 窗函数生成 | 频域处理 |
| `smoothing_filter.cc/.h` | 指数平滑 | 各估计器 |
| `ring_buffer.c/.h` | 环形缓冲 | NetEq/音频缓冲 |

#### 1.3.3 音频接收域 `modules/audio_coding/neteq/`

| 文件 | 作用 | 算法 |
|---|---|---|
| `neteq_impl.cc/.h` | **NetEq 主控**，`InsertPacket`/`GetAudio` 入口 | 调度 |
| `decision_logic.cc/.h` | **决策状态机**（NORMAL/EXPAND/...） | 决策 |
| `delay_manager.cc/.h` | IAT 直方图 → 目标缓冲 | 目标延迟 |
| `buffer_level_filter.cc/.h` | 缓冲电平泄漏积分器 | 缓冲控制 |
| `expand.cc/.h` | **PLC 丢包隐藏** | 丢包恢复 |
| `accelerate.cc/.h` | 加速（WSOLA，消耗缓冲） | 时间拉伸 |
| `preemptive_expand.cc/.h` | 抢占扩展（WSOLA，增加缓冲） | 时间拉伸 |
| `time_stretch.cc/.h` | WSOLA 基类（相关 + overlap-add） | 时间拉伸 |
| `merge.cc/.h` | expand 尾与新解码的 crossfade | 衔接 |
| `normal.cc/.h` | 正常解码播放 | 正常 |
| `sync_buffer.cc/.h` | 同步缓冲（播放历史，PLC 输入） | 数据载体 |
| `packet_buffer.cc/.h` | RTP 包缓冲 | 缓冲 |
| `histogram.cc/.h` | IAT 概率直方图 | 目标延迟 |
| `statistics_calculator.cc/.h` | 统计（喂给决策） | 决策输入 |
| `background_noise.cc/.h` | 背景噪声建模 | CNG |
| `comfort_noise.cc/.h` | 舒适噪声生成 | CNG |
| `nack_tracker.cc/.h` | 音频 NACK | 丢包恢复 |
| `post_decode_vad.cc/.h` | 解码后 VAD | 静音 |
| `dsp_helper.cc/.h` | DSP 辅助（相关/窗） | PLC/WSOLA |
| `cross_correlation.cc/.h` | 互相关 | PLC/WSOLA |
| `random_vector.cc/.h` | 随机向量 | CNG/PLC |
| `api/neteq/neteq.h` | `NetEq` 接口 + `Config` | 配置入口 |

#### 1.3.4 视频发送域 `video/` + `modules/video_coding/utility/` + `call/`

| 文件 | 作用 | 算法 |
|---|---|---|
| `video/video_stream_encoder.cc/.h` | **视频发送主控**（编码 + 适配） | 发送调度 |
| `video/adaptation/video_stream_encoder_resource_manager.cc/.h` | 资源管理（CPU/质量/带宽） | 适配决策 |
| `video/adaptation/overuse_frame_detector.cc/.h` | 编码用时过载检测 | CPU 适配 |
| `video/encoder_bitrate_adjuster.cc/.h` | 编码器码率精调 | 码率 |
| `video/encoder_overshoot_detector.cc/.h` | 编码器超发检测 | 码率回压 |
| `modules/video_coding/utility/quality_scaler.cc/.h` | **质量缩放**（QP 阈值） | 分辨率适配 |
| `modules/video_coding/utility/frame_dropper.cc/.h` | **帧丢弃**（leaky bucket） | 帧率适配 |
| `modules/video_coding/utility/framerate_controller.cc/.h` | 帧率控制 | 帧率 |
| `modules/video_coding/utility/simulcast_rate_allocator.cc/.h` | **Simulcast 码率分配** | 码率分配 |
| `call/bitrate_allocator.cc/.h` | **多流码率分配**（比例公平） | 码率分配 |
| `call/rtp_video_sender.cc/.h` | 发送侧 RTP/编码/FEC 聚合 | 发送 |

#### 1.3.5 视频接收域 `modules/video_coding/` + `modules/rtp_rtcp/source/`

| 文件 | 作用 | 算法 |
|---|---|---|
| `modules/video_coding/frame_buffer2.cc/.h` | **视频 jitter buffer**（解码调度） | 抖动 |
| `modules/video_coding/jitter_estimator.cc/.h` | 帧间延迟方差 → jitter | 抖动估计 |
| `modules/video_coding/inter_frame_delay.cc/.h` | 帧间延迟计算 | 抖动 |
| `modules/video_coding/timing.cc/.h` | 渲染时间/延迟调整 | 渲染调度 |
| `modules/video_coding/rtt_filter.cc/.h` | RTT 过滤 | NACK/抖动 |
| `modules/video_coding/nack_module.cc/.h` | **NACK 模块** | 丢包恢复 |
| `modules/video_coding/packet_buffer.cc/.h` | RTP 包重组 | 组帧 |
| `modules/video_coding/rtp_frame_reference_finder.cc/.h` | 帧参考关系确定 | 组帧 |
| `modules/video_coding/h264_sps_pps_tracker.cc/.h` | H264 参数集跟踪 | 组帧 |
| `modules/video_coding/loss_notification_controller.cc/.h` | 丢包通知控制 | 丢包 |
| `modules/video_coding/fec_controller_default.cc/.h` | FEC 码率控制 | 丢包恢复 |
| `modules/video_coding/utility/decoded_frames_history.cc/.h` | 已解码帧历史（去重） | 解码 |
| `modules/rtp_rtcp/source/forward_error_correction.cc/.h` | **FEC 编解码**（ULPXOR） | 丢包恢复 |
| `modules/rtp_rtcp/source/flexfec_sender.cc/.h` + `flexfec_receiver.cc` | flexfec 编解码 | 丢包恢复 |
| `modules/rtp_rtcp/source/fec_private_tables_*.cc/.h` | FEC 掩码表 | FEC |
| `video/rtp_video_stream_receiver.cc/.h` | 接收侧 RTP 聚合 | 接收 |
| `video/video_receive_stream.cc/.h` | 视频接收流主控 | 接收 |

#### 1.3.6 拥塞控制域 `modules/congestion_controller/` + `modules/remote_bitrate_estimator/` + `modules/pacing/`

| 文件 | 作用 | 算法 |
|---|---|---|
| `congestion_controller/goog_cc/goog_cc_network_control.cc/.h` | **GoogCC 主控** | 拥塞控制 |
| `congestion_controller/goog_cc/delay_based_bwe.cc/.h` | 延迟带宽估计 | 延迟 BWE |
| `congestion_controller/goog_cc/trendline_estimator.cc/.h` | **trendline 延迟检测** | 过载检测 |
| `congestion_controller/goog_cc/acknowledged_bitrate_estimator.cc/.h` | ACK 码率估计 | 码率 |
| `congestion_controller/goog_cc/alr_detector.cc/.h` | **ALR 检测** | 应用受限 |
| `congestion_controller/goog_cc/probe_controller.cc/.h` | **探测控制** | 带宽探测 |
| `congestion_controller/goog_cc/probe_bitrate_estimator.cc/.h` | 探测码率评估 | 带宽探测 |
| `congestion_controller/goog_cc/send_side_bandwidth_estimation.cc/.h` | 接收端报告 BWE（REMB/TMMBR） | 回退 BWE |
| `congestion_controller/goog_cc/loss_based_bandwidth_estimation.cc/.h` | 丢包 BWE | 丢包降速 |
| `congestion_controller/goog_cc/congestion_window_pushback_controller.cc/.h` | cwnd 回压 | 拥塞窗 |
| `congestion_controller/pcc/` | PCC（monitor interval + 效用函数） | 拥塞控制（备选） |
| `congestion_controller/receive_side_congestion_controller.cc/.h` | 接收侧拥塞控制 | 接收侧 |
| `congestion_controller/rtp/transport_feedback_adapter.cc/.h` | transport-cc 反馈适配 | 反馈 |
| `remote_bitrate_estimator/aimd_rate_control.cc/.h` | **AIMD 速率控制** | 速率控制 |
| `remote_bitrate_estimator/overuse_estimator.cc/.h` + `overuse_detector.cc/.h` + `inter_arrival.cc/.h` | 接收侧过载估计（旧） | 过载检测 |
| `remote_bitrate_estimator/remote_estimator_proxy.cc/.h` | transport-cc 反馈代理 | 反馈 |
| `pacing/pacing_controller.cc/.h` | **Pacing 主控**（leaky bucket） | 发送整形 |
| `pacing/bitrate_prober.cc/.h` | **探测注入** | 带宽探测 |
| `pacing/interval_budget.cc/.h` | 令牌桶预算 | Pacing |
| `pacing/round_robin_packet_queue.cc/.h` | 优先级队列 | Pacing |
| `api/transport/network_control.h` + `network_types.h` | `NetworkControllerInterface` + 控制数据结构 | 控制接口 |

#### 1.3.7 文件夹↔算法↔业务场景对照表

| 文件夹 | 主要算法 | 典型业务场景 |
|---|---|---|
| `audio_processing/aec3` | 回声消除 | 免提通话、双讲、设备切换 |
| `audio_processing/ns` | 降噪 | 嘈杂环境、稳态/非稳态噪声 |
| `audio_processing/agc2` | 自适应增益 | 音量不稳、远近端电平差异 |
| `audio_coding/neteq` | jitter+PLC+时间拉伸 | 网络抖动、丢包、时钟漂移 |
| `video_coding/utility` | 质量缩放/丢帧/Simulcast 分配 | 弱网降质、CPU 过载 |
| `video_coding/frame_buffer2` | 视频抖动缓冲 | 抖动、丢包、关键帧等待 |
| `video_coding/nack_module` + `rtp_rtcp/.../forward_error_correction` | 丢包恢复 | 随机/突发丢包 |
| `congestion_controller/goog_cc` | 带宽估计与码率闭环 | 容量变化、弱网、屏幕共享 |
| `pacing` | 发送整形 + 探测 | 突发平滑、带宽探测 |

### 1.4 核心数据结构与控制接口速查

| 结构/接口 | 文件 | 作用 |
|---|---|---|
| `AudioProcessing::Config` | `audio_processing/include/audio_processing.h` | 音频处理全域配置（AEC/NS/AGC1/AGC2/HPF/VAD） |
| `EchoCanceller3Config` | `api/audio/echo_canceller3_config.h` | AEC3 详细参数（Delay/Filter/Erle/EpStrength/EchoAudibility...） |
| `NsConfig` | `audio_processing/ns/ns_config.h` | NS 抑制等级（k6/12/18/21dB） |
| `NetEq::Config` | `api/neteq/neteq.h` | NetEq 配置（sample_rate/max_packets/max_delay/...） |
| `VideoEncoder::QpThresholds` | `api/video_codecs/video_encoder.h` | 质量缩放 QP 上下限 |
| `MediaStreamAllocationConfig` | `call/bitrate_allocator.h` | 多流分配（min/max/priority/enforce_min） |
| `NetworkControllerInterface` | `api/transport/network_control.h` | 拥塞控制统一接口 |
| `NetworkControlUpdate` / `TargetTransferRate` / `PacerConfig` / `ProbeClusterConfig` | `api/transport/network_types.h` | 拥塞控制输出数据结构 |
| `TrendlineEstimatorSettings` | `congestion_controller/goog_cc/trendline_estimator.h` | trendline 窗口/阈值 |

---

## 第 2 章：音频处理算法（APE 管线与子算法）

### 2.1 APE 处理管线总览

`AudioProcessingImpl::ProcessCaptureStreamLocked()`（`audio_processing_impl.cc:1053`）是音频发送侧的核心管线。它按固定顺序调用各子算法，顺序经过精心设计（AEC 必须在 NS 之前分析、AGC 在最后等）。capture（采集/近端）侧处理顺序：

```
ProcessCaptureStreamLocked()
 1. EmptyQueuedRenderAudioLocked()        // 取出 render 队列音频（AEC 需要）
 2. HandleCaptureRuntimeSettings()        // 处理运行时增益设置
 3. high_pass_filter (fullband, 若 apply_in_full_band)   // 全带高通
 4. pre_amplifier->ApplyGain()             // 预放大（CapturePreGain）
 5. capture_input_rms_.Analyze()            // 输入 RMS 统计
 6. echo_controller->AnalyzeCapture()       // AEC3 分析 capture（饱和检测）
 7. agc_manager->AnalyzePreProcess()        // AGC1 预分析
 8. SplitIntoFrequencyBands()               // 分带（>16kHz 分成多带）
 9. high_pass_filter (split, 若分带模式)    // 分带高通
10. gain_control->AnalyzeCaptureAudio()     // AGC1 分析
11. noise_suppressor->Analyze()            // NS 分析（估噪，AEC 前）
12. echo_controller->ProcessCapture()       // AEC3 回声消除（核心）
13. noise_suppressor->Analyze(linear_aec)  // NS 分析线性 AEC 输出（可选）
14. noise_suppressor->Process()             // NS 降噪（维纳增益）
15. voice_detection->ProcessCaptureAudio() // VAD
16. agc_manager->Process()                 // AGC1 处理
17. gain_control->ProcessCaptureAudio()    // AGC1 数字增益
18. MergeFrequencyBands()                   // 合带
19. echo_detector->AnalyzeCaptureAudio()    // 残留回声检测
20. transient_suppressor->Suppress()        // 瞬态抑制
21. gain_controller2->Process()             // AGC2 处理
22. capture_post_processor->Process()       // 自定义后处理
23. output_level_estimator->ProcessStream() // 输出电平
24. echo_controller->GetMetrics()           // AEC 指标（ERL/ERLE/delay）
```

render（播放/远端参考）侧 `ProcessRenderStreamLocked()`（`:1424`）较简单：高通 → 预处理 → `echo_controller->AnalyzeRender()`（供 AEC 用）→ echo_detector 分析。render 音频通过 `SwapQueue` 异步送到 capture 侧（`EmptyQueuedRenderAudioLocked`），实现 render/capture 解耦。

**管线顺序的设计意图**：
- **AEC 在 NS 之前**：AEC 需要原始 capture 信号做回声路径估计，NS 会改变信号频谱影响估计精度；但 NS 的 `Analyze`（仅估噪）在 AEC 前，`Process`（实际降噪）在 AEC 后——这样 NS 估噪用未受 AEC 影响的信号，而降噪在去除回声后的信号上做，避免把回声当噪声。
- **AGC 在最后**：增益应在所有"净化"之后施加，否则放大噪声/回声残留。
- **分带处理**：>16kHz 信号分成多个子带，AEC/NS 在子带（低带）上运行，降低计算量。

```
┌─────────────── ProcessCaptureStreamLocked 管线（数据流）───────────────┐
│ capture PCM                                                            │
│   │                                                                    │
│   ▼ HPF(fullband) → pre_amp → RMS                                      │
│   │                                                                    │
│   ▼ AEC3.AnalyzeCapture (饱和检测) ── render 队列 ── AEC3.AnalyzeRender │
│   │                                                                    │
│   ▼ SplitIntoFrequencyBands                                            │
│   │                                                                    │
│   ▼ HPF(split) → AGC1.Analyze → NS.Analyze                             │
│   │                                                                    │
│   ▼ AEC3.ProcessCapture (回声消除) ──► linear_aec_output               │
│   │                                                                    │
│   ▼ NS.Process (降噪)                                                  │
│   │                                                                    │
│   ▼ VAD → AGC1.Process → MergeBands                                   │
│   │                                                                    │
│   ▼ echo_detector → transient → AGC2 → level_estimator                │
│   │                                                                    │
│   ▼ 输出 PCM                                                           │
└────────────────────────────────────────────────────────────────────────┘
```

### 2.2 AEC3 回声消除

**设计目标与定位**：消除扬声器播放的远端声音（render）被麦克风重新拾取形成的回声。AEC3 是 WebRTC 当前主力回声消除器（`modules/audio_processing/aec3/`），以"块"为单位处理（`kBlockSize=64` 样本，250 block/s），在频域用自适应滤波器建模回声路径。它替代了移动端的 AECM 和早期的 AEC。

**核心原理**：

1. **分区块频域自适应滤波（partitioned block frequency-domain NLMS）**：回声路径是一个长冲激响应（房间反射），时域卷积代价高。AEC3 把 render 信号做 128 点 FFT（`kFftLength=2*kFftLengthBy2=128`，`kFftLengthBy2=64`），在频域用分段（partitioned）滤波器逐块累加，每段长度 64 样本，多段拼接成长滤波器。自适应更新用归一化最小均方（NLMS）的频域变体，按误差信号调整滤波器系数。

2. **双滤波器结构（coarse + refined）**：`EchoRemover` 内部维护两套自适应滤波器——`CoarseConfiguration`（粗，快速跟踪，`rate` 较高）和 `RefinedConfiguration`（精，慢但稳，`error_floor`/`error_ceil`/`noise_gate`）。粗滤波器用于快速锁定回声路径变化，精细滤波器用于稳态高质量消除。`AecState` 决定何时切换/融合两者输出（`config_change_duration_blocks=250` 平滑过渡）。

3. **时延估计（delay estimation）**：AEC 必须先把 render 与 capture 在时间上对齐，否则滤波器无法建模。`RenderDelayController` 调用 `EchoPathDelayEstimator`，后者用 `MatchedFilter`（降采样后，`Delay.down_sampling_factor=4`）在降采样信号上做匹配滤波找峰值滞后，`MatchedFilterLagAggregator` 聚合多个候选得到稳定 `DelayEstimate`。对齐由 `render_buffer_->AlignFromDelay()` 完成。

4. **回声路径变化检测**：音量变化、设备切换、头部移动都会改变回声路径。`echo_path_gain_change` 在 `ProcessCaptureStreamLocked` 中由模拟增益/播放音量变化检测（`:1095-1115`），传给 AEC3 触发滤波器重置/加速跟踪。

5. **近端检测（dominant nearend detector）**：双讲时（近端也说话），误差信号同时含回声残差和近端语音，直接更新滤波器会把近端语音当回声消除掉。`DominantNearendDetector` 比较 render 与 capture 能量（用 ERL/ERLE 估计），判断当前是"远端主导"（应更新滤波器）还是"近端主导"（应停止/减弱更新）。

6. **ERL/ERLE 估计**：`ErlEstimator`（回声回损，render→capture 的天然衰减）和 `ErleEstimator`（回声回损增强，AEC 带来的额外衰减）持续估计，用于近端检测和抑制增益计算。`Erle.min=1`/`max_l=4`/`max_h=1.5`。

7. **抑制增益与舒适噪声**：计算抑制增益 `G`（频域），`SuppressionFilter::ApplyGain` 施加。为避免"音乐噪声"（频域处理后的人工Artifact），`ComfortNoiseGenerator` 生成与残差能量匹配的舒适噪声填补被抑制的频段。

8. **混响建模（reverb）**：`ReverbModel` 建模房间尾音混响，对长尾回声做额外抑制。

**关键参数（`EchoCanceller3Config`，`api/audio/echo_canceller3_config.h`）**：

| 参数 | 默认值 | 含义 |
|---|---|---|
| `Delay.down_sampling_factor` | 4 | 时延估计降采样因子 |
| `Delay.num_filters` | 5 | matched filter 个数 |
| `Delay.default_delay` | 5 | 默认延迟（block） |
| `Delay.delay_estimate_smoothing` | 0.7 | 延迟估计平滑系数 |
| `Filter.RefinedConfiguration.length_blocks` | — | 精细滤波器长度（block） |
| `Filter.CoarseConfiguration.rate` | — | 粗滤波器更新速率 |
| `Filter.initial_state_seconds` | 2.5 | 初始阶段时长（保守跟踪） |
| `Filter.enable_coarse_filter_output_usage` | true | 是否使用粗滤波器输出 |
| `Erle.min` / `max_l` / `max_h` | 1 / 4 / 1.5 | ERLE 估计上下限（低/高频） |
| `EpStrength.default_gain` | 1.0 | 回声路径增益初值 |
| `EchoAudibility.audibility_threshold_lf/mf/hf` | 10 | 可听度阈值（低/中/高频） |

APE 层 `AudioProcessing::Config::EchoCanceller`（`audio_processing.h:242`）：`enabled`/`mobile_mode`/`export_linear_aec_output`/`enforce_high_pass_filtering=true`。

**核心类与数据流**：

```
EchoCanceller3 (入口, echo_canceller3.h:85)
  ├─ AnalyzeRender()  →  BlockProcessor::ProcessRender()  →  render_buffer_.Insert()
  ├─ AnalyzeCapture() →  饱和检测
  └─ ProcessCapture() →  BlockProcessor::ProcessCapture()
                          ├─ RenderDelayController::GetDelay()   (时延估计)
                          │     └─ EchoPathDelayEstimator → MatchedFilter
                          ├─ render_buffer_.AlignFromDelay()      (对齐)
                          └─ EchoRemover::ProcessCapture()       (核心消除)
                                ├─ Subtractor (自适应滤波: main + shadow)
                                │     └─ AdaptiveFirFilter (频域 NLMS)
                                ├─ SuppressionGain (抑制增益 G)
                                ├─ ComfortNoiseGenerator (舒适噪声)
                                ├─ ReverbModel (混响)
                                ├─ ErlEstimator / ErleEstimator
                                ├─ DominantNearendDetector (近端检测)
                                └─ SuppressionFilter::ApplyGain (施加)
```

`BlockProcessor`（`block_processor.h:28`）持有 `render_buffer_`/`delay_controller_`/`echo_remover_`；`EchoRemoverImpl::ProcessCapture`（`echo_remover.cc:234`）依次：分析 render → 计算 capture 频谱 → 更新 `aec_state_` → 计算抑制增益 → CNG → `SuppressionFilter::ApplyGain`。

**算法流程（逐 block）**：
1. `AnalyzeRender`：render 块入 `render_buffer`（降采样副本供时延估计）
2. `ProcessCapture`：`RenderDelayController::GetDelay` 估计延迟 → `AlignFromDelay` 对齐 → `EchoRemover::ProcessCapture`：减去回声估计（频域 `Y = H·X`）→ 算残差 → 近端检测决定更新强度 → 算抑制增益 `G` → 施加 + 舒适噪声 → 输出

**业务场景作用**：
- **正常双讲**：近端检测生效，减弱滤波器更新，保护近端语音；抑制增益适中。
- **回声路径突变**（音量/设备切换）：`echo_path_gain_change` 触发，粗滤波器快速重新跟踪，`initial_state` 重新进入保守阶段。
- **远端单讲**（只有远端声音）：滤波器全力更新，高 ERLE，回声被深度抑制。
- **近端单讲**：近端主导，滤波器几乎不更新，避免误消。

#### 2.2.1 深入：AEC3 的数学原理（频域时域、自适应滤波公式）

**(1) 时域回声模型**。设远端参考（render）为 `x[n]`，回声路径冲激响应为 `h[n]`（房间扬声器→麦克风的长冲激响应，可达数百 ms），近端语音/噪声为 `v[n]`，则麦克风采集信号：

```
y[n] = (h * x)[n] + v[n] = Σ_l h[l]·x[n-l] + v[n]
```

AEC 的目标：估计 `ĥ[n]`，用 `x̂_echo[n] = (ĥ * x)[n]` 去减，得残差 `e[n] = y[n] - x̂_echo[n] ≈ v[n]`（只剩近端）。

**(2) 为何用频域**。`h[n]` 长达数千样本，时域卷积 + NLMS 更新每样本 O(L) 太贵。AEC3 用**分块频域自适应滤波（Partitioned Block Frequency Domain, PBFDLMS）**：把长 `h` 切成 P 段，每段长 `N=kFftLengthBy2=64`，对每段做 2N=128 点 FFT，频域逐段累加。

**(3) 分块频域卷积**。对第 `m` 块（64 样本），用重叠保留法（overlap-save）：render 块 `x_m` 与上一块 `x_{m-1}` 拼成 128 样本，加 **√Hann 窗**（`Aec3Fft::Window::kSqrtHanning`，`echo_remover.cc:101` `PaddedFft`），做 128 点 FFT 得 `X_m[k]`。滤波器第 p 段频域系数 `H_p[k]`，回声估计频域：

```
Y_m[k] = Σ_{p=0}^{P-1} H_p[k] · X_{m-p}[k]      (频域乘加)
```

逆 FFT 取后 64 样本（overlap-save 去除循环卷积混叠）得时域 `ŷ_m[n]`，残差 `e_m[n] = y_m[n] - ŷ_m[n]`。残差再做加窗 FFT 得 `E_m[k]`。

**(4) NLMS 频域更新公式**。这是 AEC3 自适应的核心。由 `coarse_filter_update_gain.cc:59-74` 实测代码：

```
mu[k] = rate / X2[k]              (当 X2[k] > noise_gate，否则 mu[k]=0)
G[k]  = mu[k] · E[k] · conj(X[k])   (代码: "G = mu * E * X2"，X2=|X|²)
H_p[k] ← H_p[k] + G[k]            (滤波器系数更新)
```

即归一化步长：`ΔH_p[k] = (rate / |X[k]|²) · E[k] · X*[k]`。这是**频域 NLMS**——步长用 render 功率归一化，使更新对 render 能量不敏感（鲁棒）。`noise_gate` 抑制低能量频段更新（避免无激励段漂移）。精细滤波器（`refined_filter_update_gain.cc`）用 `E2_refined`/`E2_coarse` 双误差驱动，并跟踪 `H_error_`（滤波器误差能量，初值 `kHErrorInitial=10000`）判断收敛状态。

**(5) 双滤波器（main + shadow）**。主滤波器（refined，长，高精度）和影子滤波器（coarse，短/快）并行运行。`AecState` 比较两者残差能量 `E2_refined` vs `E2_coarse`：若 shadow 更好（回声路径刚变化），临时用 shadow 输出并加速 main 重新收敛。`config_change_duration_blocks=250` 控制切换平滑。

**(6) 时延估计的数学**。匹配滤波在降采样（×4，即 8kHz 或更低）域做：对 render 降采样信号 `x̃` 与 capture 降采样信号 `ỹ`，计算互相关 `R(τ) = Σ_n x̃[n]·ỹ[n+τ]`，峰值位置 `τ*` 即回声延迟。`MatchedFilter` 用多个对齐偏移的滤波器覆盖不同延迟区间（`num_filters=5`，`kMatchedFilterWindowSizeSubBlocks=32`，`kMatchedFilterAlignmentShiftSizeSubBlocks=24`），`MatchedFilterLagAggregator` 聚合多帧峰值得到稳定 `DelayEstimate`（`delay_estimate_smoothing=0.7` 指数平滑）。

**(7) 近端检测的数学**。双讲时 `y = h*x + v`，残差 `e` 含近端 `v`。`DominantNearendDetector` 比较：
- `ERL(k) = X2[k] / Y2[k]`（回声回损，render→capture 天然衰减，`ErlEstimator`）
- `ERLE(k) = Y2[k] / E2[k]`（AEC 增强后的额外衰减，`ErleEstimator`，上下限 `Erle.min=1/max_l=4/max_h=1.5`）

若 `Y2[k]` 远大于 `X2[k]·ERL`（近端能量主导），判定近端主导，**降低 `mu` 或冻结更新**，保护近端语音不被当回声消除。

**(8) 抑制增益 G**。线性 AEC 后仍有非线性回声残差（扬声器失真），`SuppressionGain` 用残差能量 `E2`、render 能量 `X2`、ERLE 估计算频域抑制增益 `G[k]`（类似 NS 的 Wiener 思路但针对回声），`SuppressionFilter::ApplyGain` 施加：`E_sup[k] = G[k]·E[k]`。`ComfortNoiseGenerator` 用残差能量谱生成舒适噪声填补深抑制频段，避免"音乐噪声"。


### 2.3 NS 降噪

**设计目标与定位**：抑制背景噪声（稳态/非稳态），在频域用 Wiener 滤波实现。位于 `modules/audio_processing/ns/`，处理帧长 `kNsFrameSize=160`，FFT 长度 `kFftSize=256`（重叠 `kOverlapSize=96`），分带处理。

**核心原理**：

1. **先验/后验 SNR 估计**：对每个频点，后验 SNR = `|Y|²/σ_n²`（观测能量/噪声能量），先验 SNR = 语音能量/噪声能量。用决策导向（decision-directed）法结合上一帧增益估计先验 SNR。

2. **量化噪声估计（quantile noise estimator）**：`QuantileNoiseEstimator` 对每个频点的能量做分位数跟踪——在无语音段，噪声能量缓慢上升；有语音时保持。`NoiseEstimator` 聚合多带噪声估计。

3. **语音概率估计**：`SpeechProbabilityEstimator`（`speech_probability_estimator.h:23`）用三个特征综合判断语音概率：
   - **LRT**（似然比检验）：`kLtrFeatureThr=0.5`，`kBinSizeLrt=0.1`
   - **谱平坦度**（spectral flatness）：`kBinSizeSpecFlat=0.05`（语音谱不平坦，噪声谱平坦）
   - **谱差**（spectral difference）：`kBinSizeSpecDiff=0.1`
   三个特征在 `kFeatureUpdateWindowSize=500` 帧窗口内统计，输出 `prior_speech_prob_`（初值 0.5）。

4. **Wiener 滤波**：`WienerFilter`（`wiener_filter.h:23`）根据先验 SNR 计算频域增益 `H = ξ/(1+ξ)`（ξ 为先验 SNR），`Update()` 更新，`ComputeOverallScalingFactor` 算整体缩放因子（结合语音概率和能量比，避免过度抑制）。

5. **抑制曲线**：`SuppressionParams` 按 `NsConfig::SuppressionLevel`（k6/12/18/21dB）决定最大抑制深度。默认 `k12dB`。

6. **启动阶段**：`kShortStartupPhaseBlocks=50`/`kLongStartupPhaseBlocks=200`，初始噪声估计未稳时采用保守抑制。

**关键参数**：

| 参数 | 默认值 | 含义 |
|---|---|---|
| `NsConfig::target_level` | `k12dB` | 抑制等级（k6/k12/k18/k21dB） |
| `NoiseSuppression::level` | `kModerate` | APE 层等级（kLow/kModerate/kHigh/kVeryHigh） |
| `analyze_linear_aec_output_when_available` | false | 是否用 AEC 线性输出估噪 |
| `kFftSize` | 256 | FFT 长度 |
| `kNsFrameSize` | 160 | 处理帧长 |
| `kFeatureUpdateWindowSize` | 500 | 特征更新窗口 |

**核心类**：

```
NoiseSuppressor (noise_suppressor.h:29)
  ├─ Analyze(audio)  →  各通道 ChannelState.FilterBankState 分析
  │     ├─ NoiseEstimator / QuantileNoiseEstimator (噪声估计)
  │     ├─ SignalModelEstimator / PriorSignalModelEstimator (特征建模)
  │     └─ SpeechProbabilityEstimator (语音概率)
  └─ Process(audio)  →  WienerFilter.Update → AggregateWienerFilters → ApplyFilterBankWindow
        └─ SuppressionParams (抑制深度)
```

`Analyze`（`noise_suppressor.cc:288`）做估噪 + 特征；`Process`（`:382`）算 Wiener 增益并施加。`AggregateWienerFilters`（`:272`）合并多带增益。

**算法流程**：
1. `Analyze`：加窗 → FFT → 算功率谱 → 估噪（分位数）→ 算 LRT/谱平坦/谱差 → 语音概率 → 更新先验 SNR
2. `Process`：Wiener 增益 `H(ω)` → 整体缩放 → 频域相乘 → IFFT → overlap-add 输出

**业务场景作用**：
- **稳态噪声**（空调/风扇）：分位数估计快速收敛，深度抑制。
- **非稳态噪声**（键盘/敲击）：谱平坦度/谱差特征区分，但响应较慢；瞬态由 `transient_suppressor` 补充。
- **低 SNR**：语音概率低，抑制加深，但 `ComputeOverallScalingFactor` 防止过度抑制致语音失真。

#### 2.3.1 深入：NS 的数学原理（频域、SNR、Wiener 滤波公式）

**(1) 频域模型**。设第 `i` 帧加窗 FFT 后功率谱 `Y(ω)`，噪声功率谱 `N(ω)`，语音功率谱 `S(ω)`，假设加性模型 `Y(ω) = S(ω) + N(ω)`（功率近似可加）。NS 的目标：估计增益 `H(ω)`，输出 `Ŝ(ω) = H(ω)·Y(ω)`，使 `E[|S-Ŝ|²]` 最小。

**(2) 后验与先验 SNR**。对每个频点 `i`：
- 后验 SNR：`γ_i = Y_i / N_i`（观测/噪声，`Y_i` 当前帧功率谱，`N_i` 噪声估计）
- 先验 SNR：`ξ_i = S_i / N_i`（语音/噪声）

**决策导向（decision-directed）估计**（`wiener_filter.cc:51`）：
```
ξ_i = α · prev_tsa_i + (1-α) · current_tsa_i
```
其中 `α=0.98`（代码 `0.98f * prev_tsa + (1-0.98) * current_tsa`），`prev_tsa_i = H_{i-1}·Y_{i-1}`（上一帧"干净"功率谱，用上一帧增益反推），`current_tsa_i = max(γ_i - 1, 0)`（当前帧先验 SNR 的 ML 估计）。这种递推让先验 SNR 平滑，避免音乐噪声。

**(3) Wiener 滤波增益**（`wiener_filter.cc:52-55`）：
```
H_i = ξ_i / (over_subtraction_factor + ξ_i)
H_i = clamp(H_i, minimum_attenuating_gain, 1.0)
```
经典 Wiener 滤波 `H = ξ/(1+ξ)`，NS 加了 `over_subtraction_factor`（过减因子，由 `SuppressionParams` 按 `SuppressionLevel` 决定，等级越高因子越大、抑制越深）和 `minimum_attenuating_gain`（最小增益下限，防止完全静音致不自然）。`SuppressionLevel` k6/12/18/21dB 对应不同过减强度。

**(4) 量化噪声估计**（`quantile_noise_estimator.cc:42-49`）。对每个频点在**对数域**跟踪分位数：
```
若 log_Y_i > log_Q_i:  log_Q_i += 0.25 · multiplier   (信号高于分位数→上调)
否则:                  log_Q_i -= 0.75 · multiplier   (低于→下调，下调更快)
```
`log_Q_i` 是噪声功率的对数分位数估计（默认 ~0.97 分位，`quantile=1041529569` 即 0.97 in Q30）。在对数域做的好处是动态范围大、对语音帧（偶发高能量）鲁棒——语音偶尔抬高分位数，但下调系数 0.75 > 上调 0.25，长期收敛到噪声水平。多带分别估计，`kSimult` 个并行估计器（`kLongStartupPhaseBlocks=200` 启动期）。

**(5) 语音概率三特征**（`prior_signal_model_estimator.cc` + `speech_probability_estimator.cc`）。对每帧算三个特征，在 `kFeatureUpdateWindowSize=500` 帧直方图上建模：
- **LRT（似然比）**：`L_i = log(γ_i) - ξ_i/(1+ξ_i)`（语音 vs 噪声似然比），阈值 `kLtrFeatureThr=0.5`，直方图 bin `kBinSizeLrt=0.1`
- **谱平坦度**：`SF = exp(mean(log Y_i)) / mean(Y_i)`（几何/算术均值比），噪声谱平坦→SF≈1，语音谱有峰→SF<1，bin `kBinSizeSpecFlat=0.05`
- **谱差**：当前谱与噪声谱差异，bin `kBinSizeSpecDiff=0.1`

`SignalModelEstimator` 跟踪三特征直方图，`FindFirstOfTwoLargestPeaks`（`prior_signal_model_estimator.cc:24`）找双峰（语音峰/噪声峰），`PriorSignalModelEstimator` 据此算先验语音概率 `prior_speech_prob_`（初值 0.5）。`SpeechProbabilityEstimator::Update` 综合三特征输出后验语音概率。

**(6) 整体缩放**（`WienerFilter::ComputeOverallScalingFactor`）。纯频域增益可能在低 SNR 段过度抑制致语音能量损失。NS 用语音概率 `p` 和滤波前后能量比算一个时域整体缩放因子，补偿能量，保证语音可懂度。

**(7) 重构**。频域 `Ŝ_i = H_i · Y_i` → IFFT → overlap-add（`kOverlapSize=96` 重叠，`ApplyFilterBankWindow`）→ 时域输出。

### 2.4 AGC2 自适应增益（含 RNN VAD）

**设计目标与定位**：自动调节增益使输出电平接近目标，避免过小（听不清）或过大（削波）。AGC2（`modules/audio_processing/agc2/`）是当前推荐版本，用 RNN VAD 区分语音，自适应数字增益 + 限幅器。帧长 `kFrameDurationMs=10`，子帧 `kSubFramesInFrame=20`。

**核心原理**：

1. **固定数字增益（fixed_digital）**：`FixedDigitalLevelEstimator` 估输入电平，`fixed_digital.gain_db` 施加固定增益（默认 0dB）。

2. **自适应数字增益（adaptive_digital）**：`AdaptiveDigitalGainApplier`（`adaptive_digital_gain_applier.h:35`）是核心。每帧流程（`adaptive_digital_gain_applier.cc:97`）：
   - `ComputeGainDb(input_level_dbfs)`（`:28`）：把输入电平映射到目标增益
     - 输入极低（`< -(kHeadroomDbfs + kMaxGainDb)`，即 `< -31dBfs`）：用最大增益 `kMaxGainDb=30dB`
     - 输入在 `-31 ~ -1dBfs`：`gain = -kHeadroomDbfs - input_level = -1 - input`（拉到 -1dBfs）
     - 输入过高（`> -1dBfs`）：不增益（由 LevelEstimator 保证不报错值）
   - `LimitGainByNoise`（`:48`）：`gain + noise_level ≤ kMaxNoiseLevelDbfs(-50dBfs)`，避免放大噪声
   - `LimitGainByLowConfidence`（`:56`）：估计不自信时（`estimate_is_confident=false`）且限幅器已接近阈值，限制增益
   - `gain_increase_allowed_`：仅当 `vad_result.speech_probability > kVadConfidenceThreshold(0.9)` 时允许增益上升（`:gain_increase_allowed_`），避免静音时抬升底噪
   - `ComputeGainChangeThisFrameDb`（`:75`）：每帧增益变化限制在 `±kMaxGainChangePerFrameDb`（= `kMaxGainChangePerSecondDb(3) * 10/1000 = 0.03dB/帧`），平滑过渡
   - `last_gain_db_` 累积，`GainApplier` 施加

3. **RNN VAD**（`agc2/rnn_vad/`）：基于循环神经网络的语音活动检测，比传统 VAD 更准。`FeaturesExtraction` 提取特征（谱特征 + 基音：`pitch_search`/`lp_residual`/`auto_correlation`），`rnn.cc` 跑 RNN 推理输出语音概率。结果经 `VadWithLevel` 包装，喂给 `AdaptiveDigitalGainApplier`。

4. **电平估计**：`AdaptiveModeLevelEstimator`（基于 `VadWithLevel` 的语音帧电平，`kFullBufferSizeMs=1200` 滑窗，`kFullBufferLeakFactor` 泄漏）+ `NoiseLevelEstimator`/`NoiseSpectrumEstimator`（噪声电平，用于 `LimitGainByNoise`）。`estimate_is_confident` 在累积足够语音帧后置真。

5. **饱和保护**：`SaturationProtector`（`kSaturationProtectorAttackConstant=0.9988`/`DecayConstant=0.9998`）跟踪峰值，防止增益推到削波。

6. **限幅器**：`Limiter`（`limiter.cc`）+ `LimiterDbGainCurve` 在 `kLimiterThresholdForAgcGainDbfs=-kHeadroomDbfs=-1dBfs` 以上做硬限幅，`InterpolatedGainCurve`（`kInterpolatedGainCurveKneePoints=22`）平滑增益曲线。

**关键参数**：

| 参数 | 默认值 | 含义 |
|---|---|---|
| `GainController2.fixed_digital.gain_db` | 0 | 固定增益 |
| `GainController2.adaptive_digital.enabled` | false | 自适应增益开关 |
| `GainController2.adaptive_digital.level_estimator` | kRms | 电平估计器（kRms/kPeak） |
| `GainController2.adaptive_digital.use_saturation_protector` | true | 饱和保护 |
| `GainController2.adaptive_digital.extra_saturation_margin_db` | 2 | 额外饱和余量 |
| `kMaxGainDb` | 30 | 最大增益 |
| `kInitialAdaptiveDigitalGainDb` | 8 | 初始增益 |
| `kHeadroomDbfs` | 1 | 目标余量（目标 -1dBfs） |
| `kMaxGainChangePerSecondDb` | 3 | 每秒最大增益变化 |
| `kVadConfidenceThreshold` | 0.9 | 允许增益上升的语音概率阈值 |
| `kMaxNoiseLevelDbfs` | -50 | 噪声电平上限（限制增益放大噪声） |

**核心类**：

```
GainController2 (gain_controller2.cc)
  ├─ fixed_digital: FixedDigitalLevelEstimator + GainApplier
  └─ adaptive_digital: AdaptiveAgc (adaptive_agc.cc)
        ├─ VadWithLevel → RnnVad (rnn_vad/: FeaturesExtraction + Rnn)
        ├─ NoiseLevelEstimator / NoiseSpectrumEstimator
        ├─ AdaptiveModeLevelEstimator (语音电平)
        ├─ SaturationProtector (饱和保护)
        ├─ InterpolatedGainCurve (增益曲线)
        └─ AdaptiveDigitalGainApplier (增益计算+施加)
  └─ Limiter + LimiterDbGainCurve (限幅)
```

**算法流程**：每帧 → `FixedDigitalLevelEstimator` 估电平 → `VadWithLevel`(RNN) 算语音概率 → `NoiseLevelEstimator` 估噪 → `AdaptiveModeLevelEstimator` 估语音电平 → `SaturationProtector` 更新 → `ComputeGainDb` 目标增益 → `LimitGainByNoise`/`LimitGainByLowConfidence` 限幅 → `ComputeGainChangeThisFrameDb` 限速 → `GainApplier` 施加 → `Limiter` 限幅。

**业务场景作用**：
- **音量过小**（远端说话轻）：增益上升至目标 -1dBfs，受 `kMaxGainDb=30` 限制。
- **音量过大**（近削波）：增益不升，`SaturationProtector` 主动降低增益，`Limiter` 硬限幅。
- **静音段**：`vad_result.speech_probability < 0.9`，`gain_increase_allowed_=false`，增益不上升，避免抬底噪；`LimitGainByNoise` 防止放大噪声。
- **噪声环境**：`NoiseLevelEstimator` 估噪，`LimitGainByNoise` 限制增益 ≤ `kMaxNoiseLevelDbfs - noise_level`。

#### 2.4.1 深入：AGC2 的数学原理（增益映射、限速、限幅公式）

**(1) 电平与 dBFS**。AGC2 在 dBFS 域工作。输入电平 `L_in`（dBFS，≤0，0dBFS=满量程）。目标是把输出拉到 `-kHeadroomDbfs = -1 dBFS`（留 1dB 余量防削波）。

**(2) 目标增益映射 `ComputeGainDb`**（`adaptive_digital_gain_applier.cc:28-44`，分段函数）：
```
            ⎧  kMaxGainDb (=30)                      若 L_in < -(kHeadroomDbfs + kMaxGainDb) = -31 dBFS
gain_db =   ⎨  -kHeadroomDbfs - L_in = -1 - L_in      若 -31 ≤ L_in < -1 dBFS
            ⎩  0  (不增益, DCHECK L_in ≤ 0)            若 L_in ≥ -1 dBFS
```
直觉：输入越低，需要越大增益；但增益上限 30dB。当 `L_in=-31` 时 `gain=30`（拉到 -1）；`L_in=-10` 时 `gain=9`（拉到 -1）；`L_in=-1` 时 `gain=0`（已在目标）。这是**线性映射 + 饱和**。

**(3) 噪声限制 `LimitGainByNoise`**（`:48-54`）：
```
noise_headroom = kMaxNoiseLevelDbfs - L_noise = -50 - L_noise
gain = min(gain, max(noise_headroom, 0))
```
约束：`gain + L_noise ≤ kMaxNoiseLevelDbfs(-50dBFS)`。即放大后噪声不得超过 -50dBFS，避免"放大噪声"。若噪声已高于 -50dBFS（`L_noise > -50`），`noise_headroom<0`，`max(...,0)=0`，增益被限到 0。

**(4) 低置信度限制 `LimitGainByLowConfidence`**（`:56-71`）。当电平估计不自信（`estimate_is_confident=false`，语音样本不足）且限幅器输出已接近阈值：
```
L_before = L_limiter - last_gain          (去掉上次增益看原始电平)
new_gain = max(kLimiterThresholdForAgcGainDbfs - L_before, 0) = max(-1 - L_before, 0)
gain = min(new_gain, gain)                 (不超过原 gain)
```
防止在估计不准时盲目推高增益致削波。

**(5) 语音门控**（`:gain_increase_allowed_`）：
```
gain_increase_allowed = (vad_result.speech_probability > kVadConfidenceThreshold=0.9)
```
无语音时禁止增益上升（只能降），避免静音段抬底噪。这是 AGC2 区别于 AGC1 的关键——用 RNN VAD 精准门控。

**(6) 增限速 `ComputeGainChangeThisFrameDb`**（`:75-84`）：
```
Δ = target_gain - last_gain
若 !gain_increase_allowed: Δ = min(Δ, 0)          (只允许降)
Δ = clamp(Δ, -kMaxGainChangePerFrameDb, +kMaxGainChangePerFrameDb)
```
`kMaxGainChangePerFrameDb = kMaxGainChangePerSecondDb(3) × kFrameDurationMs(10)/1000 = 0.03 dB/帧`。即每帧增益变化不超过 ±0.03dB，每秒最多 3dB，**平滑过渡**避免增益跳变致爆音。`last_gain += Δ`，`GainApplier` 施加线性增益因子 `DbToRatio(last_gain) = 10^(last_gain/20)`。

**(7) 电平估计 `AdaptiveModeLevelEstimator`**。在 `kFullBufferSizeMs=1200` 滑窗内对**语音帧**（VAD 判定）的 RMS 电平做泄漏积分：
```
L_estimate = kFullBufferLeakFactor · L_estimate + (1-kFullBufferLeakFactor) · L_frame
kFullBufferLeakFactor = 1 - 1/1200 ≈ 0.99917
```
仅用语音帧（排除静音/噪声帧），故需足够语音样本才 `estimate_is_confident=true`。`kInitialSpeechLevelEstimateDbfs=-30` 初值。

**(8) 饱和保护 `SaturationProtector`**。跟踪近限幅器的峰值电平，用攻击/衰减系数（`kSaturationProtectorAttackConstant=0.9988`/`DecayConstant=0.9998`）平滑，当检测到接近削波时主动建议降低增益，`extra_saturation_margin_db=2` 额外余量。

**(9) 限幅器 `Limiter` + `LimiterDbGainCurve`**。在 `kLimiterThresholdForAgcGainDbfs=-1dBFS` 以上做压缩限幅，增益曲线由 `InterpolatedGainCurve`（`kInterpolatedGainCurveKneePoints=22` 膝点 + 10 超膝点）分段插值，膝段平滑过渡（软膝），超过阈值后增益随电平下降（硬限幅），保证不削波。

**(10) RNN VAD 的数学**（`agc2/rnn_vad/`）。输入特征：谱特征（`spectral_features.cc`，子带能量/相关性）+ 基音特征（`pitch_search.cc` 自相关找基音周期，`lp_residual.cc` LPC 残差）。`rnn.cc` 跑量化 RNN（GRU 类）推理，输出 `[0,1]` 语音概率。比传统能量 VAD 在低 SNR/非稳态噪声下更准，是 AGC2 增益决策的可靠前提。

### 2.5 AGC1 旧版增益

**设计目标与定位**：AGC1（`modules/audio_processing/agc/`）是早期版本，用响度直方图 + 模拟/数字增益。`agc_manager_direct.cc` 是主控，`agc.cc` 是核心。已被 AGC2 取代但仍可用。

**核心原理**：
- **响度直方图**（`loudness_histogram.cc`）：统计近 `kNumHistBins` 个 RMS 电平的直方图，找"活跃语音"的长期 RMS。
- **目标电平**：`target_level_dbfs=3`（默认，APE 层 `GainController1`），算法把 RMS 拉到目标附近。
- **压缩增益**：`compression_gain_db=9`（默认），数字增益范围；`enable_limiter=true` 限幅。
- **模拟增益**（`analog_gain_controller`）：`agc_manager_direct` 还可调硬件模拟音量（`analog_level_minimum=0`/`maximum=255`），`startup_min_volume`（默认 85，`kAgcStartupMinVolume`），`clipped_level_min=70`（`kClippedLevelMin`）防削波下调。`enable_agc2_level_estimator` 可让 AGC1 用 AGC2 的电平估计。
- **`gain_map_internal.h`**：增益映射查找表。

**关键参数**（`AudioProcessing::Config::GainController1`，`audio_processing.h:275`）：

| 参数 | 默认值 | 含义 |
|---|---|---|
| `enabled` | false | 开关 |
| `mode` | kAdaptiveAnalog | 模式（kAdaptiveAnalog/kAdaptiveDigital/kFixedDigital） |
| `target_level_dbfs` | 3 | 目标电平 |
| `compression_gain_db` | 9 | 压缩增益 |
| `enable_limiter` | true | 限幅 |
| `analog_gain_controller.enabled` | true | 模拟增益 |
| `analog_gain_controller.startup_min_volume` | 85 | 启动最小音量 |
| `analog_gain_controller.clipped_level_min` | 70 | 削波下调下限 |

#### 2.5.1 深入：AGC1 的数学原理（响度直方图 + 模拟增益闭环）

**(1) 响度直方图（`loudness_histogram.cc`）**。AGC1 不像 AGC2 用 RNN VAD，而是用**滑动窗口直方图**估计"活跃语音长期 RMS"。每帧 `Update(rms, activity_probability)`（`:90`）：
- 用 VAD 给的语音活动概率 `activity_probability`（连续 [0,1]，非硬判决）作为**软权重**，把当前 RMS 投到对应 bin（对数域均匀量化，`:199` "quantizer is uniform in log domain"）。
- 滑窗 `kNumAnalysisFrames` 帧（环形缓冲 `hist_bin_index_`），`RemoveOldestEntryAndUpdate`（`:104`）减去最旧帧的贡献，`InsertNewestEntryAndUpdate`（`:129`）加新帧——直方图始终反映近 `kNumAnalysisFrames` 帧的分布。
- `CurrentRms`（`:214`）：按 bin 概率加权求 RMS：`RMS = Σ_n p_n · bin_center_n`，`p_n = bin_count_n / total`。
- `AudioContent`：`Σ bin_count`（总活动量），低于 `kNumAnalysisFrames * kActivityThreshold` 判定无足够活跃语音。

**(2) 增益误差计算（`agc.cc:49` `GetRmsErrorDb`）**：
```
loudness = Linear2Loudness(CurrentRms)          # RMS → 响度（对数域）
error_db = Loudness2Db(target_level_loudness - loudness)   # 目标响度 - 当前响度 → dB 误差
```
即 `error_db = target_level_dbfs - current_rms_dbfs`（目标 - 当前），正值表示需增益、负值需衰减。`kDefaultLevelDbfs` 即 `target_level_dbfs=3`。每 `kNumAnalysisFrames` 帧重置直方图（`:67`）。

**(3) 数字增益更新（`agc_manager_direct.cc:186` `UpdateGain`）**。`compression_` 以 `kCompressionGainStep=0.05`（`:46`）步长向 `target_compression_`（`kDefaultCompressionGain`）逼近，`UpdateCompressor` 把 `compression_` 设到 `GainControl`。这是**步进式增益**（每帧最多变 0.05，平滑），而非 AGC2 的每帧限速。

**(4) 模拟增益闭环（`AnalyzePreProcess` + `Process`）**。AGC1 的 `kAdaptiveAnalog` 模式调硬件音量（0~255）：
- **削波检测**（`:122-133`）：统计 clipped 样本比例，若超阈值，`SetMaxLevel(max(max_level - kClippedLevelStep=15, clipped_level_min))`（`:195`）下调模拟音量上限，`clipped_level_min=70` 是下限。
- **VAD 驱动**：`agc_->Process` 用 VAD 概率更新直方图，`GetRmsErrorDb` 得误差，`SetMicVolume` 调模拟音量（`kClippedLevelStep=15` 步长），`startup_min_volume=85` 启动音量。
- **数字补偿**：模拟增益调不到位时，`compression_gain_db` 数字增益补足。

**(5) 与 AGC2 对比**。AGC1 用直方图 + 软 VAD（GMM），AGC2 用 RNN VAD + 电平估计 + 饱和保护 + 限幅器；AGC1 步进式（0.05/帧），AGC2 限速式（0.03dB/帧 + 语音门控）；AGC1 可调模拟音量，AGC2 纯数字。AGC2 在低 SNR/非稳态噪声下更鲁棒（RNN VAD 更准）。

### 2.6 VAD / HPF / transient / echo_detector 辅助算法

- **VAD**：多版本共存。`common_audio/vad/`（独立 VAD，能量+子带+基音，供编码/NetEq/APE 共用）、`audio_processing/vad/`（APE 内部）、`agc2/rnn_vad/`（RNN，AGC2 专用）、`neteq/post_decode_vad`（解码后）、`audio_processing/voice_detection`（结果上报）。`VoiceDetection` 配置 `enabled` + `frame_size_ms`。
- **HPF（high_pass_filter）**：`high_pass_filter.cc`，去直流和低频噪声，`HighPassFilter.enabled=false`/`apply_in_full_band=true`/`enforce_high_pass_filtering=true`（AEC 强制）。
- **瞬态抑制（transient）**：`transient/` + `transient_suppressor`，抑制键盘/敲击等瞬态噪声，用 `agc_manager->voice_probability` 辅助判断。
- **残留回声检测（echo_detector）**：`residual_echo_detector.cc` + `echo_detector/`，统计 render/capture 相关性，输出 `residual_echo_likelihood`（AEC 残留回声概率，非消除）。
- **键盘检测（typing_detection）**：`typing_detection.cc`，检测键盘敲击触发瞬态抑制。

#### 2.6.1 深入：VAD / HPF 的数学原理

**(1) 传统 VAD（`common_audio/vad/`，GMM-based）**。这是 WebRTC 最经典的 VAD，用**高斯混合模型（GMM）**区分语音/噪声。流程（`vad_core.c`）：
- **子带能量**（`vad_filterbank.c`）：对 80/160/240 样本帧做 6 个子带滤波（0~1k, 1~2k, ..., 4~8kHz），算各子带能量 `features[6]`（`log10(energy)`，`:128`）。
- **GMM 概率**（`vad_gmm.c` + `vad_core.c:133` `GmmProbability`）：对每个子带，用两个高斯分布建模——`kSpeechDataMeans/Stds/Weights` 和 `kNoiseDataMeans/Stds/Weights`（`:37-53`）。计算每个特征的语音/噪声条件概率 `sgprvec`/`ngprvec`：
```
p(x|speech) = N(x; μ_s, σ_s),  p(x|noise) = N(x; μ_n, σ_n)
```
- **总概率**：`total_power > kMinEnergy`（`:175`）才判语音，结合 6 子带概率与 `kMinimumDifference`（`:25`，子带最小差）综合判定。`kMinStd=384`（`:61`）防方差过小。帧长 80/160/240 对应不同阈值（`:157`）。
- **自适应更新**：噪声/语音的均值方差按新样本更新（`:342-405`），`kMinimumMean`/`kMinStd` 限制漂移。
- 这是**统计模型 VAD**——比纯能量 VAD 准（用频谱形状），比 RNN VAD 轻（定点、无神经网络）。

**(2) HPF（`high_pass_filter.cc`）**。二阶 IIR 高通，去直流和低频噪声（<80Hz）。系数（`:22-32`）按采样率：
```
48kHz:  b = [0.99079, -1.98157, 0.99079],  a = [1.0, -1.98157, 0.98158]
16kHz:  b = [0.97261, -1.94523, 0.97261],  a = [1.0, -1.94523, 0.94522]
```
差分方程：`y[n] = b0·x[n] + b1·x[n-1] + b2·x[n-2] - a1·y[n-1] - a2·y[n-2]`。这是标准二阶高通 Butterworth（截止 ~80Hz），`b0=b2`、`a1=-(b0+b2)` 是对称结构。AEC 强制 HPF（`enforce_high_pass_filtering=true`）因直流分量会干扰回声路径估计。

**(3) 瞬态抑制（`transient_suppressor`）**。检测键盘/敲击等瞬态（短时高频突增），用频域检测 + `voice_probability`（AGC 提供，区分瞬态 vs 语音）做增益抑制，避免把语音瞬态误抑。`key_pressed` 标志来自 `typing_detection`。

**(4) 残留回声检测（`residual_echo_detector`）**。计算 render 与 capture 的**互相关**（归一化），高相关 → 残留回声概率高。这是**检测**（输出 `residual_echo_likelihood` 供上层决策），非消除——AEC 消不干净时报警。

### 2.7 音频处理数据流图与类关系

```
┌─────────── APE capture 管线类关系（局部）───────────┐
│ AudioProcessingImpl                                 │
│   ├─ submodules_.high_pass_filter  (HighPassFilter)  │
│   ├─ submodules_.echo_controller   (EchoCanceller3)  │
│   │     └─ BlockProcessor → EchoRemover → ...        │
│   ├─ submodules_.noise_suppressor  (NoiseSuppressor) │
│   ├─ submodules_.agc_manager       (AgcManagerDirect)│
│   ├─ submodules_.gain_control      (GainControlImpl)│
│   ├─ submodules_.gain_controller2  (GainController2)│
│   ├─ submodules_.voice_detector    (VoiceDetection) │
│   ├─ submodules_.transient_suppressor               │
│   └─ submodules_.echo_detector                       │
│                                                      │
│ 数据载体: AudioBuffer (分带) ←→ SwapQueue (render)   │
│ 配置入口: AudioProcessing::Config (ApplyConfig)      │
└──────────────────────────────────────────────────────┘
```


---

## 第 3 章：音频接收算法（NetEq）

### 3.1 设计目标与定位

NetEq（`modules/audio_coding/neteq/`）是 WebRTC 音频接收端的核心，集 **Jitter Buffer（抖动缓冲）+ PLC（丢包隐藏）+ 时间拉伸（WSOLA）+ 解码** 于一体。它解决四个问题：
1. **抖动**：网络包到达间隔不均，用缓冲 + 时间拉伸平滑。
2. **丢包**：用 PLC 从历史信号外推生成替代音频。
3. **乱序/迟到**：用包缓冲 + 序号重排处理。
4. **时钟漂移**：发送/接收采样率微差，用时间拉伸补偿。

对外两个核心 API（`api/neteq/neteq.h`，生产者-消费者模型）：
- `InsertPacket(RTPHeader, payload)`：生产者，RTP 包入缓冲（线程内加锁 `crit_sect_`）。
- `GetAudio(AudioFrame*, muted*)`：消费者，按 **10ms**（`kOutputSizeMs=10`）固定步长拉取 PCM。

### 3.2 整体架构与文件结构

```
┌──────────────────── NetEqImpl (neteq_impl.cc) ────────────────────┐
│ InsertPacket()  →  PacketBuffer.InsertPacketList()                  │
│                    → DecoderDatabase 选解码器                       │
│                    → DelayManager.Update()  (IAT→目标缓冲)           │
│                    → StatisticsCalculator                            │
│                                                                      │
│ GetAudio()  →  DecisionLogic.GetDecision()  (决策状态机)             │
│                → 解码 (AudioDecoder)                                  │
│                → 按 Operation 执行: Normal/Expand/Accelerate/        │
│                  PreemptiveExpand/Merge/Fade/Cng/Dtmf                 │
│                → PostDecodeVad → 输出 10ms PCM                        │
└──────────────────────────────────────────────────────────────────────┘
   关键组件:
   DecisionLogic   决策树
   DelayManager    IAT 直方图 → 目标缓冲 (histogram.cc)
   BufferLevelFilter  缓冲电平泄漏滤波
   Expand          PLC 丢包隐藏 (expand.cc)
   Accelerate/PreemptiveExpand  WSOLA 时间拉伸 (time_stretch.cc)
   Merge           expand↔normal 衔接 (merge.cc)
   SyncBuffer      播放历史 (PLC 输入源)
   PacketBuffer    RTP 包缓冲
   StatisticsCalculator  统计喂决策
   BackgroundNoise/ComfortNoise  CNG
   NackTracker     音频 NACK
```

### 3.3 决策状态机

`DecisionLogic::GetDecision`（`decision_logic.cc:93`）是 NetEq 的大脑。它根据当前状态（`NetEqStatus`：`playout_timestamp`/`target_timestamp`/`packet_available`/`last_mode`/`next_packet`）选择一个 `Operation`。决策树：

```
GetDecision(status):
  if last_mode == kRfc3389Cng:           # 上一帧是 CNG
      → CngOperation(...)                 # 继续 CNG 或转 Expand
  if 加速/抢占刚成功 (last_mode in AccelerateSuccess/...):
      → kNormal                           # 强制正常一帧
  if last_mode != kRfc3389Cng 且 有 DTX 暂停:
      → kExpand (一次)                     # DTX 唤醒补一帧
  if 无目标包 (target_timestamp 无包):
      if play_dtmf: → kDtmf
      else: → CngOperation / kExpand
  if 目标包正好可用:
      → kNormal
  if 上一帧是 Expand 且连续 Expand:
      → kExpand (继续丢包隐藏)
  if 目标包已到(预期包):
      → ExpectedPacketAvailable()          # 见下
  else (未来包已到, 即目标包丢失/迟到):
      → FuturePacketAvailable()            # 见下
  最后: buffer_level_filter_.Update()  (更新缓冲电平)
```

**`ExpectedPacketAvailable`**（`:294`，目标包正好可用）——核心时间拉伸决策：
```
low_limit, high_limit = DelayManager.BufferLimits()
buffer_level_packets = filtered_level / (target_level << 8)
if buffer_level_packets >= high_limit << 2:   # 远高于上限
    → kFastAccelerate (若 enable_fast_accelerate)  # 快速加速消耗
if buffer_level_packets >= high_limit:        # 高于上限(缓冲过多)
    → kAccelerate                             # 加速(WSOLA 压缩时间)
if buffer_level_packets < low_limit:          # 低于下限(缓冲不足)
    → kPreemptiveExpand                        # 抢占扩展(WSOLA 拉长时间)
else:
    → kNormal
```

**`FuturePacketAvailable`**（`:320`，目标包丢失，未来包已到）：
```
if prev_mode == kExpand/kCodecPlc 且连续丢包:
    → kExpand (继续 PLC)
else:
    → kExpand (启动 PLC)
```

**Operation 枚举**（`neteq_impl.cc:820` 起分发）：`kNormal`/`kMerge`/`kExpand`/`kAccelerate`/`kFastAccelerate`/`kPreemptiveExpand`/`kRfc3389Cng`/`kRfc3389CngNoPacket`/`kDtmf`/`kComfortNoise`/`kFade`。

### 3.4 DelayManager：IAT 直方图 → 目标缓冲

**目标**：动态估计"需要多少缓冲（包数）才能覆盖抖动"。核心思想：统计包的**到达间隔时间（Inter-Arrival Time, IAT）**分布，取高分位数作为目标缓冲。

**算法**（`delay_manager.cc:130` `Update` + `:271` `CalculateTargetLevel`）：
1. 每收到一个包，由 RTP 序号差 + 时间戳差算 IAT（以包长为单位）：`iat = (arrival_ts - expected_ts) / packet_len`。
2. `histogram_->Add(iat)`：更新 IAT 直方图（`histogram.cc`，带 `forget_factor` Q15 遗忘，新数据权重大）。
3. `CalculateTargetLevel`：`bucket_index = histogram_->Quantile(histogram_quantile_)`，`histogram_quantile_=0.97`（`quantile=1041529569` in Q30，`:47`）。即取 IAT 分布的 **97 分位数**作为目标缓冲——覆盖 97% 的抖动。
4. `target_level_ = bucket_index << 8`（Q8 定点），`base_target_level_` 记录未限幅值。
5. 限幅：`target_level_` 受 `minimum_delay`/`maximum_delay`/`max_buffer_packets`（`max_packets_in_buffer=200`）约束，下限 `1<<8`（至少 1 包）。

**`BufferLimits`**（`:315`）：由 `target_level_` 派生上下限 `low_limit`/`high_limit`，供决策树判断加速/抢占。`base_target_level_` 初值 4 包。

### 3.5 BufferLevelFilter：缓冲电平泄漏积分器

**算法**（`buffer_level_filter.cc:30` `Update`）：
```
filtered = (level_factor · filtered_prev + (256 - level_factor) · buffer_size) >> 8
filtered -= time_stretched_samples              # 减去时间拉伸"消耗/增加"的样本
```
这是**指数移动平均（EMA）+ 时间拉伸补偿**。`level_factor` 由目标缓冲决定（`SetTargetBufferLevel`，`:48`）：target≤1→251, ≤3→252, ≤7→253, else→254（Q8，即 0.980~0.996）。目标越大平滑越重。减去 `time_stretched_samples` 是因为加速/抢占已人为改变了缓冲电平，滤波器需感知真实电平。

### 3.6 Expand：PLC 丢包隐藏

**目标**：丢包时从 `SyncBuffer`（播放历史）外推生成替代音频，连续丢包时逐渐衰减转噪声。

**算法**（`expand.cc:70` `Process` + `:370` `AnalyzeSignal`）：
1. **基音周期估计**：`AnalyzeSignal` 对播放历史做自相关 `Correlation()`（`:407`），在 `kNumCorrelationCandidates` 个候选滞后中找最大相关峰值，对应基音周期 `current_lag`（人声 80~400 样本）。`best_correlation`/`best_distortion` 双准则选最佳 lag。
2. **浊音/清音分解**：信号分浊音（周期性，用 `current_lag` 重复）和清音（噪声，用 LPC 残差 `ar_filter_state` + 随机激励 `random_vector`）。`voiced_vector` 用基音周期重复，`unvoiced_vector` 用 AR 滤波器（`kUnvoicedLpcOrder`/`kNoiseLpcOrder`）+ 随机数生成。
3. **overlap-add 平滑**（`:173-178`）：新外推向量与 `SyncBuffer` 末尾 `overlap_length_`（`5*fs/8000`，8kHz=5 样本… 实为窗长）做加权叠加：
```
out[i] = (mute_factor · voiced[i] · w_up[i] + history[i] · w_down[i]) >> 14
```
`mute_factor` 初值 `16384`(=1.0 in Q14)，控制衰减。
4. **连续丢包衰减**（`:286-289`）：`consecutive_expands_` 递增，`mute_factor` 逐帧降低（`gain = (mute_factor·...)>>14`），信号渐弱。`consecutive_expands_ > 3` 时 `mute_factor=0` 转纯噪声。`kMaxConsecutiveExpands=200`（`:75`），超过 `TooManyExpands()` 转舒适噪声/静音，避免长时间合成伪音。
5. 输出长度：首帧 `current_lag + overlap_length`，后续按 `expand_lags_[current_lag_index_]` 调整。

### 3.7 WSOLA 时间拉伸（Accelerate / PreemptiveExpand）

**目标**：在不改变音调的前提下，**压缩时间**（Accelerate，消耗过多缓冲）或**拉长时间**（PreemptiveExpand，补充不足缓冲）。核心是 **WSOLA（Waveform Similarity Overlap-Add）**。

**算法**（`time_stretch.cc:24` `Process` + `:160` `AutoCorrelation`）：
1. **降采样到 4kHz 域**（`fs_mult_ = fs/8000`），减少计算。
2. **自相关找最佳重叠点**（`AutoCorrelation`，`:160`）：在 lag `[kMinLag=10, kMaxLag=60]`（4kHz 域，对应基音范围）内算自相关 `R(τ) = Σ_n x[n]·x[n+τ]`，`PeakDetection`（`:66`）找峰值 `peak_index`，即最佳重叠偏移。
3. **overlap-add**：在最佳偏移处用窗（`kExpansionTable`）重叠相加，实现时间缩放。Accelerate 丢弃一个基音周期（压缩），PreemptiveExpand 重复一个基音周期（拉伸）。
4. **`CheckCriteriaAndStretch`**（`:74`）：检查拉伸后能量/相关性是否达标（避免失真），返回 `Success`/`LowEnergy`/`NoStretch`/`Success`，决策树据此选 `kAccelerate`/`kAccelerateLowEnergy` 等 Mode。

`Accelerate`（`accelerate.cc`）和 `PreemptiveExpand`（`preemptive_expand.cc`）继承 `TimeStretch`，仅拉伸方向/参数不同。`enable_fast_accelerate` 启用 `kFastAccelerate`（更激进）。

#### 3.7.1 深入：WSOLA 的数学原理（波形相似性重叠相加）

**(1) 为什么需要 WSOLA**。直接删/重复样本会改变音调（相位不连续致"咔哒"声）。WSOLA（Waveform Similarity Overlap-Add）通过**找波形相似点**做重叠相加，实现时间缩放而**保持音调**（基频不变）。

**(2) 时间缩放的目标**。设原始信号 `x[n]`，要压缩（Accelerate）到 `α<1` 倍长度或拉伸（Preemptive）到 `α>1` 倍。WSOLA 的做法：把信号分成重叠段，每段在**基音周期整数倍**处对齐重叠，重叠区用窗加权相加（overlap-add）。

**(3) 自相关找基音周期**（`time_stretch.cc:160` `AutoCorrelation`）。先降采样到 4kHz（`fs_mult_ = fs/8000`，减少计算 + 聚焦基频）。在 lag `[kMinLag=10, kMaxLag=60]`（4kHz 域，对应 2.5~15ms，即 67~400Hz 基频，覆盖人声）内算自相关：
```
R(τ) = Σ_n x[n] · x[n+τ]
```
`PeakDetection`（`:66`）找最大 `R(τ*)`，`τ*` 即基音周期（4kHz 域），换算回原采样率：`peak_index = τ* + kMinLag·fs_mult·2`（`:75`）。

**(4) 波形相似性验证**（`:87-110`）。找到基音周期后，验证两个相隔 `peak_index` 的段是否真相似：
```
vec1 = signal[fs_mult_120 - peak_index : ...]   # 前一段
vec2 = signal[fs_mult_120 : ...]                # 后一段
vec1_energy = Σ vec1²,  vec2_energy = Σ vec2²
cross_corr = Σ vec1·vec2
best_correlation = cross_corr / sqrt(vec1_energy · vec2_energy)   # 归一化互相关
```
`best_correlation` 接近 1 说明两段高度相似（周期性强），可安全重叠；低则信号非周期（清音/噪声），走 `SetParametersForPassiveSpeech`（被动语音分支，`:107`）。

**(5) overlap-add 时间缩放**。在最佳对齐处，用窗 `w`（`kExpansionTable`，三角/Hann 窗）加权相加：
```
y[n] = w[n]·vec1[n] + (1-w[n])·vec2[n]    (重叠区)
```
- **Accelerate**（压缩）：丢弃一个 `peak_index` 段，输出长度减少 `peak_index` 样本 → 消耗缓冲。
- **PreemptiveExpand**（拉伸）：重复一个 `peak_index` 段，输出长度增加 `peak_index` 样本 → 补充缓冲。
窗函数保证重叠区平滑过渡，无相位跳变。

**(6) `CheckCriteriaAndStretch`**（`:74`）：检查 `best_correlation` 和能量比，若不达标返回 `kNoStretch`（放弃拉伸，避免失真）或 `kLowEnergy`（低能量，决策树据此选 `kAccelerateLowEnergy` 等 Mode，降低后续 Expand 概率）。

**直觉**：WSOLA 利用语音的**准周期性**——浊音段基音周期重复，在周期整数倍处波形相似，故可安全删/重复一个周期而不改音调。清音/噪声段无周期性，`best_correlation` 低，走被动分支或放弃。

### 3.8 Merge：expand ↔ normal 衔接

**目标**：丢包恢复后（Expand 产生合成音频），真实包到达时，把 Expand 尾部与新解码音频平滑衔接，避免"咔哒"声。

**算法**（`merge.cc:57` `Process`）：
1. `GetExpandedSignal`（`:161`）：调 `Expand` 生成一段扩展信号（`expand_->SetParametersForMergeAfterExpand`），得 `expanded_length`。
2. **降采样 + 相关搜索**（`:263` `Merge::Correlation`）：把扩展信号和新解码信号降采样（`DspHelper::kDownsample*Tbl`，按采样率选表），在扩展信号尾找与新信号头最相关的偏移 `best_correlation_index`。
3. **crossfade**：在最佳偏移处，扩展信号尾与新信号头做加权交叉渐变（overlap-add），平滑过渡。`filter_coefficients` 是降采样滤波器系数。

#### 3.8.1 深入：Merge 的数学原理（相关对齐 + 交叉渐变）

**(1) 为什么需要 Merge**。Expand 产生的 PLC 音频是"合成"的（从历史外推），与真实解码音频在衔接点**相位不连续**——直接拼接会产生"咔哒"声。Merge 用**相关对齐 + 交叉渐变**消除跳变。

**(2) 相关对齐找最佳衔接点**（`merge.cc:263` `CorrelateAndPeakSearch`）。把扩展信号 `E` 和新解码信号 `D` 降采样（`DspHelper::kDownsample*Tbl`，按采样率选 FIR 系数，`:270-279`），在扩展信号尾段搜索与新信号头最相关的偏移 `best_correlation_index`：
```
R(δ) = Σ_n E[N-δ-n] · D[n]      # 扩展信号尾 vs 新信号头
best_correlation_index = argmax_δ R(δ)
```
`best_correlation_index` 是使两段最相似的衔接偏移。降采样是为减少搜索计算量（在低频域对齐即可，相位对齐不需全频段）。

**(3) 交叉渐变（CrossFade）**（`:80` `DspHelper::CrossFade`）。在 `best_correlation_index` 处，扩展信号尾与新信号头做线性加权渐变：
```
overlap_len = expanded_length - best_correlation_index
out[n] = (1 - n/overlap_len) · E[best_correlation_index + n] + (n/overlap_len) · D[n]    (重叠区)
```
前段（`best_correlation_index` 之前）直接用扩展信号 `E`（`memmove`，`:78`），重叠区交叉渐变，之后用新解码信号 `D`。输出长度 `best_correlation_index + input_length_per_channel`（`:84`）。

**(4) 与 WSOLA 的关系**。Merge 的交叉渐变与 WSOLA 的 overlap-add 本质相同——都是"找相似点 + 窗加权相加"。区别：WSOLA 在同一段信号内找基音周期对齐（时间缩放），Merge 在两段不同信号（合成 vs 真实）间找衔接点（拼接平滑）。两者都依赖**相关搜索**找最佳对齐，保证相位连续。

**(5) `SetParametersForMergeAfterExpand`**（`:167`）：调 Expand 生成扩展信号时设特殊参数（如更短 overlap，因 Merge 只需衔接不需长外推），使扩展信号尾适合与真实信号交叉渐变。

### 3.9 背景噪声 / 舒适噪声（CNG）

- **`BackgroundNoise`**（`background_noise.cc`）：在静音段建模背景噪声的 LPC 参数 + 能量，用于 DTX 期间生成舒适噪声。
- **`ComfortNoise`**（`comfort_noise.cc`）：用 `BackgroundNoise` 参数 + 随机激励生成 CNG 帧，与 RFC3389 CNG 互补。`kRfc3389Cng` 操作播放 RFC3389 SID 包描述的噪声；无 SID 时用内部 `BackgroundNoise`。

### 3.10 关键参数

| 参数 | 默认值 | 含义 |
|---|---|---|
| `NetEq::Config.sample_rate_hz` | 16000 | 初始采样率（随输入变） |
| `max_packets_in_buffer` | 200 | 包缓冲最大包数 |
| `max_delay_ms` | 0 | 最大延迟（0=不限） |
| `min_delay_ms` | 0 | 最小延迟 |
| `enable_fast_accelerate` | false | 快速加速 |
| `enable_muted_state` | false | 静音状态（长时间丢包转静音） |
| `enable_rtx_handling` | false | RTX 处理 |
| `for_test_no_time_stretching` | false | 测试用禁时间拉伸 |
| `enable_post_decode_vad` | false | 解码后 VAD（DTX） |
| `kOutputSizeMs` | 10 | 每次 GetAudio 输出 10ms |
| `kMaxFrameSize` | 5760 | 120ms@48kHz 最大帧 |
| `DelayManager.quantile` | 0.97 | IAT 目标分位数 |
| `kMaxConsecutiveExpands` | 200 | 最大连续 Expand |

### 3.11 算法流程

**InsertPacket 流**（`neteq_impl.cc`）：
1. 解析 RTP 头（序号、时间戳、SSRC、payload type）
2. `DecoderDatabase` 查解码器（按 payload type）
3. `PacketBuffer.InsertPacket` 入包缓冲（按时间戳排序，超 `max_packets_in_buffer` 丢旧）
4. `DelayManager.Update(seq, ts, fs)`：算 IAT → 更新直方图 → `CalculateTargetLevel`
5. `StatisticsCalculator` 记录丢包/乱序

**GetAudio 流**（`GetAudioInternal`，`:750`）：
1. `stats_->IncreaseCounter`（统计计时）
2. `DecisionLogic.GetDecision(status)` → `Operation op`
3. 按 `op` 分发（`:820` 起）：
   - `kNormal` → `DoNormal`：解码目标包 → 输出
   - `kExpand` → `DoExpand`：`Expand.Process` 生成 PLC 音频
   - `kAccelerate`/`kFastAccelerate` → `DoAccelerate`：解码 + `Accelerate.Process`（WSOLA 压缩）
   - `kPreemptiveExpand` → `DoPreemptiveExpand`：解码 + `PreemptiveExpand.Process`（WSOLA 拉伸）
   - `kMerge` → `DoMerge`：解码 + `Merge.Process`（expand↔normal 衔接）
   - `kRfc3389Cng` → 播放 CNG
   - `kDtmf` → 生成 DTMF
4. `PostDecodeVad`（若启用）→ 更新 `last_mode_` → 输出 10ms PCM

### 3.12 业务场景作用

- **正常到达**：`kNormal`，直接解码播放，缓冲电平在 `low/high_limit` 之间。
- **抖动尖峰**（包突然密集到达，缓冲过多）：`buffer_level > high_limit` → `kAccelerate`（WSOLA 压缩时间消耗缓冲），电平回落。
- **抖动低谷**（包稀疏，缓冲不足）：`buffer_level < low_limit` → `kPreemptiveExpand`（WSOLA 拉长时间补充缓冲），防下溢。
- **单包丢失**：目标包缺失 → `kExpand`（PLC 外推一帧），下一包到时 `kMerge` 衔接。
- **多包连续丢失**：连续 `kExpand`，`mute_factor` 逐帧衰减，`consecutive_expands_>3` 转噪声，`>200` 转静音/舒适噪声。
- **迟到包**：包缓冲按时间戳排序，迟到包若仍需则保留，否则丢弃；`kMaxHistoryMs=2000` 限制历史。
- **时钟漂移**：发送/接收采样率微差致缓冲长期偏移，`kAccelerate`/`kPreemptiveExpand` 周期性微调补偿。
- **DTMF**：`kDtmf` 操作用 `DtmfToneGenerator` 生成电话音，不走解码。

---

## 第 4 章：视频发送算法

### 4.1 发送管线总览

视频发送侧（`video/video_stream_encoder.cc` + `modules/video_coding/utility/` + `call/`）的核心是**在受限资源（CPU/带宽/质量）下动态调整分辨率、帧率、码率**，使主观质量最优。管线：

```
采集帧 ──► VideoStreamEncoder
            │  ├─ VideoStreamEncoderResourceManager (资源管理)
            │  │    ├─ OveruseFrameDetector (CPU 用时过载)
            │  │    ├─ QualityScalerResource (QP 质量适配)
            │  │    └─ 带宽/编码用时资源
            │  ├─ FrameDropper (编码前丢帧)
            │  ├─ FramerateController (帧率控制)
            │  ├─ EncoderBitrateAdjuster (码率精调)
            │  │    └─ EncoderOvershootDetector (超发检测)
            │  └─ 视频编码 (VP8/VP9/H264)
            │       └─ SimulcastRateAllocator (层码率分配)
            └─► BitrateAllocator (多流分配) ──► Pacing
```

### 4.2 质量缩放 QualityScaler

**目标**：根据编码器输出的 QP（量化参数）判断当前分辨率是否合适——QP 持续高（压缩过度、质量差）则降分辨率；QP 持续低（质量好、有余量）则升分辨率。

**算法**（`quality_scaler.cc`）：
1. **采样**：每编码一帧，`ReportQp(qp, time_sent_us)` 把 QP 存入 `average_qp_`（滑窗 `5*30=150` 帧，`:264`）和两个 `QpSmoother`（高/低平滑，alpha 不同）。
2. **周期检查**：`CheckQpTask`（`:82`）周期触发 `CheckQp()`（`:346`）。采样不足（`< kMinFramesNeededToScale=60`，`:39`）返回 `kInsufficientSamples`。
3. **判定**（`:367` 起）：
   - 平均 QP > `thresholds_.high` → `kHighQp` → `OnReportQpUsageHigh` → **降分辨率**（AdaptDown）
   - 平均 QP ≤ `thresholds_.low` → `kLowQp` → `OnReportQpUsageLow` → **升分辨率**（AdaptUp）
   - 之间 → `kNormalQp`（不动）
4. **双 smoother**：`qp_smoother_high_`（快响应降质）和 `qp_smoother_low_`（慢响应升质，避免抖动），`avg_qp_high`/`avg_qp_low` 分别取（`:371-376`）。`QpFastFilterLow` 快速过滤低 QP。
5. **检查间隔自适应**：`CheckQpTask` 完成后，若触发了 Adapt，下次间隔拉长（给新配置时间稳定）；否则缩短（`:187`）。

**参数**：`VideoEncoder::QpThresholds{low, high}`（编码器特定，如 VP8 low=29/high=95，H264 low=24/high=37）。`kMinFramesNeededToScale=60`。

**深入：QP 与质量的关系**。QP 是编码器量化步长，QP 越大压缩越狠、失真越大。QualityScaler 用 QP 作为"质量代理"——无需解码即可知道编码质量。降分辨率后，同样码率下每像素比特更多，QP 下降，质量回升。这是**码率-分辨率-帧率三角**的分辨率维适配。

### 4.3 帧丢弃 FrameDropper

**目标**：编码器过载（编码跟不上输入帧率，或单帧过大）时，在编码前丢帧，避免延迟累积。基于**漏桶（leaky bucket）**算法。

**算法**（`frame_dropper.cc`）：
1. **填充 `Fill(framesize_bytes, delta_frame)`**（`:80`）：每帧编码后调用，`accumulator_ += framesize_kbits`（`:121`）。关键帧（`!delta_frame`）特别处理：因关键帧远大于 P 帧，直接累加会瞬间溢出桶导致连续丢帧，故用 `large_frame_accumulation_count_`/`chunk_size_` 把关键帧大小**分摊到多帧**累积（`:88-113`）。`key_frame_ratio_`（EMA，alpha `kDefaultKeyFrameRatioAlpha`）估计关键帧比例，决定分摊数 `1/key_frame_ratio`。
2. **泄漏 `Leak(input_framerate)`**（`:125`）：每帧调用，`accumulator_ -= leak_rate`。`leak_rate = target_bitrate / framerate`（按目标码率匀速漏）。`large_frame_accumulation_spread_ = max(0.5*framerate, 5)`。
3. **丢帧判定 `DropFrame()`**：若 `accumulator_ > accumulator_max_`（桶满）则丢下一帧。`drop_ratio_`（EMA）跟踪丢帧比例，`UpdateRatio` 平滑。`max_drop_duration_secs_=4.0`（`:27`）限制连续丢帧最长 4 秒，超时强制放行一帧避免画面冻结。
4. **桶容量**：`kLeakyBucketSizeSeconds=0.5`（`:34`），`accumulator_max_ = target_bitrate * 0.5`（半秒数据量）。

**深入：漏桶的数学**。漏桶本质是**速率控制**：输入是帧大小（突发），输出是匀速漏（目标码率）。累积量 `A(t)` 满足 `dA/dt = r_in(t) - r_target`，其中 `r_in` 是实际编码码率，`r_target` 是目标。当 `A > A_max`（桶满）说明编码码率持续超目标，丢帧降低 `r_in`。关键帧分摊是关键优化——避免一个关键帧触发雪崩丢帧。

### 4.4 Simulcast 码率分配 SimulcastRateAllocator

**目标**：把单流总码率分配到多个**空间层（simulcast）**和**时间层（temporal）**。Simulcast 同时编码多个分辨率的流，接收端按带宽选其一。

**算法**（`simulcast_rate_allocator.cc`）：
1. **空间层分配 `DistributeAllocationToSimulcastLayers`**（`:82`）：从低分辨率（S0）到高分辨率（Sn）逐层分配。每层有 `minBitrate`/`targetBitrate`/`maxBitrate`（`SimulcastStream` 配置）。先满足每层 min，剩余按 `target` 分配，受 `max` 限制。`hysteresis_factor`（迟滞因子）放大 min 防抖动（`:168` `min_bitrate = min(hysteresis * min_bitrate, target)`）。
2. **时间层分配 `DistributeAllocationToTemporalLayers`**（`:208`）：每空间层内按时间层（T0~Tn）分。用**比例表** `kLayerRateAllocation[num_layers][temporal_id]`（`:32`）：
```
kLayerRateAllocation (示例, 3 时间层):
  T0: 0.4  T1: 0.0  T2: 0.0   (1 层)
  T0: 0.4  T1: 0.6  T2: 0.0   (2 层)
  T0: 0.4  T1: 0.3  T2: 0.3   (3 层, 默认)
```
即 T0（基础层）拿 40%，T1/T2（增强层）分剩余。`kBaseHeavy3TlRateAllocation`（`:39`）是 base-heavy 变体（T0 拿更多，屏幕共享用）。`GetTemporalRateAllocation`（`:47`）返回某时间层占比。
3. **`DefaultTemporalLayerAllocation`**：按 `bitrate_kbps` vs `max_bitrate_kbps` 决定激活几层时间层。

**深入**：时间层是分层编码（如 VP8 temporal scalability），T0 是基础帧（可独立解码），T1/T2 是增强帧。低带宽时只传 T0（低帧率但能解码），高带宽传全部（高帧率）。码率分配按"基础层优先"保证可解码性。空间层同理——低分辨率流保证弱网可看，高分辨率流给强网。

### 4.5 BitrateAllocator（多流码率分配）

**目标**：把 GoogCC 输出的总目标码率分配给多个并发流（如多路视频 + 音频），按**比例公平**。

**算法**（`call/bitrate_allocator.cc`）：
1. **`MediaStreamAllocationConfig`**（`bitrate_allocator.h:47`）：每流声明 `min_bitrate_bps`/`max_bitrate_bps`/`priority_bitrate_bps`/`enforce_min_bitrate`/`bitrate_priority`。
2. **分配逻辑**（`AllocateBitrates`，`:55` 起）：
   - 总码率 < 所有流 min 之和：按 min 比例分配（不足时）。
   - 否则：先保证每流 `min`，剩余按 `bitrate_priority` **加权比例**分配（`:120-181`）：
```
extra = total - sum(min)
each_track.extra = extra · (track.bitrate_priority / sum(bitrate_priority))
```
   `bitrate_priority` 高的流分到更多额外码率（`:118` 注释：priority 2.0 的流分 2 倍）。
3. **`enforce_min_bitrate`**：即使总码率不足也强制给 min（牺牲其他流）。
4. **暂停/恢复**：暂停流需码率降 `max(10%, 20kbps)` 才恢复（`:39`），防抖动。

**深入：比例公平**。这是网络资源分配的经典问题。WebRTC 的方案：min 保证基本可用，priority 决定超额分配权重。音频通常 `enforce_min_bitrate=true`（优先保音频），视频按 priority 分配剩余。

### 4.6 EncoderBitrateAdjuster / OvershootDetector

**目标**：编码器实际输出码率可能偏离目标（尤其 VP8/H264 硬件编码器），`EncoderBitrateAdjuster`（`video/encoder_bitrate_adjuster.cc`）根据实际码率微调目标，`EncoderOvershootDetector`（`encoder_overshoot_detector.cc`）检测超发并回压。

**算法**：`OvershootDetector` 滑窗统计实际码率 vs 目标，若持续超发（如 1.2x），`EncoderBitrateAdjuster` 降低给编码器的目标码率（乘以调整因子），使实际码率收敛到网络允许值。这是编码器层面的**二级码率控制**（一级是 GoogCC 给的总目标）。

### 4.7 资源管理 VideoStreamEncoderResourceManager

**目标**：统一管理多种"资源"（CPU 编码用时、QP 质量、带宽、解码用时），按资源过载触发适配（降分辨率/帧率/码率）。位于 `video/adaptation/`。

**算法**：
- **`OveruseFrameDetector`**（`overuse_frame_detector.cc`）：统计编码用时（`encode_time` / `frame_interval`），若占比持续高（过载），触发 CPU 适配（降分辨率/帧率）。类似 GoogCC 的过载检测但针对 CPU。
- **`QualityScalerResource`**：包装 `QualityScaler` 的 QP 适配为"资源"。
- **`encode_usage_resource`**：编码用时资源。
- **适配决策**：`VideoStreamEncoderResourceManager` 收集各资源信号，按 `BalancedPolicy`（或 `Adaptation` 模式）决定降/升哪一维（分辨率/帧率/码率），避免反复震荡。`AdaptDown`/`AdaptUp` 通过 `VideoStreamEncoder` 应用。

### 4.8 关键参数

| 参数 | 默认值 | 含义 |
|---|---|---|
| `VideoEncoder::QpThresholds.low/high` | 编码器特定 | 质量缩放 QP 上下限 |
| `kMinFramesNeededToScale` | 60 | 升降分辨率最少采样帧 |
| `kLeakyBucketSizeSeconds` | 0.5 | 漏桶容量（秒） |
| `max_drop_duration_secs` | 4.0 | 最长连续丢帧 |
| `SimulcastStream.{min,target,max}Bitrate` | 配置 | 每空间层码率 |
| `kLayerRateAllocation` | 比例表 | 时间层码率占比 |
| `MediaStreamAllocationConfig.bitrate_priority` | 1.0 | 多流优先级权重 |
| `enforce_min_bitrate` | true | 强制最小码率 |

### 4.9 业务场景作用

- **弱网降分辨率**：GoogCC 降总码率 → `SimulcastRateAllocator` 降层 → 若 QP 仍高，`QualityScaler` 降分辨率。
- **CPU 过载降帧率**：`OveruseFrameDetector` 检测编码用时高 → `FrameDropper` 丢帧 / 降帧率。
- **屏幕共享高码率**：`kBaseHeavy3TlRateAllocation`（base-heavy）+ 高 `maxBitrate` + 低帧率，保文字清晰。
- **编码器超发**：`OvershootDetector` 检测 → `EncoderBitrateAdjuster` 回压目标码率。

---

## 第 5 章：视频接收算法

### 5.1 接收管线总览

视频接收侧（`modules/video_coding/` + `modules/rtp_rtcp/source/` + `video/`）的核心是**在抖动和丢包下保证按时解码渲染**。管线：

```
网络 ──► RtpVideoStreamReceiver
          │  ├─ PacketBuffer (RTP 包重组为帧)
          │  ├─ RtpFrameReferenceFinder (确定帧参考关系)
          │  ├─ H264SpsPpsTracker (H264 参数集)
          │  ├─ NackModule (NACK 丢包重传请求)
          │  ├─ UlpfecReceiver / FlexfecReceiver (FEC 恢复)
          │  └─ LossNotificationController
          ▼
        FrameBuffer2 (jitter buffer, 解码调度)
          │  ├─ JitterEstimator (帧间延迟方差→jitter)
          │  ├─ InterFrameDelay (帧间延迟)
          │  ├─ Timing (渲染时间/延迟调整)
          │  └─ DecodedFramesHistory (去重)
          ▼
        视频解码 ──► 渲染
```

### 5.2 FrameBuffer2：视频抖动缓冲

**目标**：缓存已组帧的编码帧，按**可解码性 + 渲染时间**调度解码，对抗抖动并保证不丢帧地按时渲染。这是视频侧的 jitter buffer（对应音频的 NetEq，但用"延迟调度"而非"时间拉伸"）。

**算法**（`frame_buffer2.cc`）：
1. **`InsertFrame`**：帧入 `frames_`（按时间戳排序的 map）。更新 `num_missing_decodable`（缺的参考帧数）和 `continuous`（参考链是否连续）。`last_continuous_frame_` 跟踪最后一个参考链连续的帧。
2. **`NextFrame`**（`:70`，解码线程调用）：`FindNextFrame`（`:119`）找下一帧：
   - 遍历 `frames_` 到 `last_continuous_frame_`，跳过 `!continuous` 或 `num_missing_decodable > 0` 的帧（`:128-129`）。
   - 若 `keyframe_required_` 且非关键帧则跳过（`:135`，丢包恢复时强制等关键帧）。
   - **decodable-first 策略**（`:164-178`）：检查 superframe（多空间层同时间戳）的下一帧是否也可解码，避免部分解码。
   - 算渲染时间 `timing_->RenderTimeMs`（`:194`），`wait_ms = timing_->MaxWaitingTime(render_time, now)`（`:196`）——基于渲染时间算"还能等多久"。
   - `wait_ms < -kMaxAllowedFrameDelayMs(5ms)`（`:203`）说明已严重迟到，立即解码（或丢）。
3. **等待**：`NextFrame` 在 `wait_ms` 内阻塞（或被新帧到达唤醒），超时取帧解码。
4. **`GetNextFrame`**（`:213`）：取出帧，更新 `timing_`（关键帧时 `Reset`，`:227`）。
5. **限制**：`kMaxFramesBuffered=800`（`:39`），`kMaxFramesHistory=8192`（`:42`）。

**深入：视频 jitter 与音频的区别**。视频不能用 WSOLA 时间拉伸（会破坏帧完整性），故用**延迟调度**——提前解码并缓冲，按渲染时间释放。`Timing` 算每帧的渲染时间（`capture_time + 单向延迟 + jitter 余量`），`FrameBuffer` 据此决定等待。jitter 大时延迟自动增大（缓冲多帧），jitter 小时延迟减小（低延迟）。

### 5.3 JitterEstimator + InterFrameDelay + Timing

**目标**：估计网络抖动（帧到达时间的方差），喂给 `Timing` 算渲染延迟。

**JitterEstimator 算法**（`jitter_estimator.cc`，基于卡尔曼滤波）：
1. **帧大小 EMA**（`:133`）：`avgFrameSize = φ·avgFrameSize + (1-φ)·frameSize`，`φ=0.97`（`:37`）。
2. **帧大小方差**（`:141`）：`varFrameSize = φ·varFrameSize + (1-φ)·(frameSize - avgFrameSize)²`。
3. **延迟偏差**（`:159-166`）：`frameDelayMS` 限幅到 `max_time_deviation_ms`（`kDefaultMaxTimestampDeviationInSigmas=3.5` σ），`deviation = DeviationFromExpectedDelay(frameDelayMS, deltaFS)`（`:286`）：`dev = frameDelay - (θ[0]·deltaFS + θ[1])`，θ 是信道模型（斜率=每字节延迟，截距=固定延迟）。
4. **卡尔曼更新** `KalmanEstimateChannel`（`:208`）：用 `deviation` 更新 θ 和误差协方差，这是**卡尔曼滤波估计信道延迟模型**——把帧延迟建模为帧大小的线性函数 + 噪声，卡尔曼滤波最优估计系数。
5. **噪声方差**（`:342`）：`noiseThreshold = noiseStdDevs(2.33)·sqrt(varNoise) - noiseStdDevOffset(30)`，即 ~1% 概率的噪声门限。
6. **输出**（`:369`）：`filterJitterEstimate = CalculateEstimate()`，`GetJitterEstimate(rttMultiplier)` 返回 jitter + RTT 余量。

**InterFrameDelay**（`inter_frame_delay.cc`）：算相邻帧的相对延迟（基于 RTP 时间戳与到达时间）。

**Timing**（`timing.cc`）：`RenderTimeMs` 算渲染时间 = `estimated_max_decode_time + render_delay + jitter_delay`；`UpdateCurrentDelay` 根据实际解码/渲染时间调整当前延迟，向目标延迟靠拢（比例调整）。`SetJitterDelay` 设最小 jitter 延迟。

### 5.4 NACK 模块

**目标**：检测 RTP 序号缺口，向发送端请求重传丢失包。适合**低 RTT、随机单包丢失**。

**算法**（`nack_module.cc`）：
1. **`OnReceivedPacket(seq_num, is_keyframe, is_recovered)`**（`:113`）：收到包，更新 `newest_seq_num_`。若 `AheadOf(newest_seq_num_, seq_num)`（收到旧包），从 NACK 列表移除（`:136-138`，包已到不需重传）。否则若有缺口，`AddPacketsToNack`（`:81`）把缺口内序号加入 NACK 列表。
2. **`GetNackBatch`**（`:87`）：`Process` 周期调用，返回到期应发送的 NACK。每条 `NackInfo{seq_num, send_at_seq_num, sent_at_time, retries}`。
3. **RTT 退避**（`BackoffSettings`，`:60`）：重传间隔按 RTT 退避，`min_retry`/`max_rtt`/`base`（1.25 指数退避，`:70` 注释：10 次重传累积延迟）。`kDefaultRttMs=100`（`:28`），`kMaxNackRetries=10`（`:29`）。`send_at_seq_num` 控制何时发送（避免对乱序包过早 NACK）。
4. **`UpdateRtt`**（`:41`）：用 RTCP RTT 更新退避参数。
5. **`RemovePacketsUntilKeyFrame`**（`:86`）：丢包过多时清到下一个关键帧，避免无意义重传。

**深入：NACK 的退避数学**。重传请求间隔 `t_retry = min_retry · base^retries`（base≈1.25），随重试次数指数增长。结合 RTT：若 RTT 大，间隔拉长（等重传包回来）。`kMaxNackRetries=10` 后放弃（转依赖 FEC 或关键帧请求）。这是**可靠性 vs 延迟**的权衡——NACK 增加延迟但恢复单包丢失效率高。

### 5.5 FEC（前向纠错）

**目标**：发送端冗余包，接收端无需重传即可恢复丢失包。适合**高 RTT 或突发丢包**。WebRTC 支持 ULPXOR（RFC 5109，`forward_error_correction.cc`）和 flexfec（`flexfec_sender.cc`/`flexfec_receiver.cc`）。

**算法**（`forward_error_correction.cc`）：
1. **编码**：对一组 `k` 个媒体包，生成 `n-k` 个 FEC 包。FEC 包是媒体包的**异或（XOR）**组合，用**掩码表** `fec_private_tables_*.cc`（`bursty` 突发模式 / `random` 随机模式）决定哪些媒体包参与哪个 FEC 包的 XOR。掩码设计保证在特定丢包模式下可恢复。
2. **解码**（`DecodeFec`）：收到包后，若某媒体包丢失，但它的 FEC 组内其他包齐全，用 XOR 逆运算恢复：`lost = FEC ⊕ (other media packets)`（XOR 自逆）。
3. **UEP（不等保护）**：重要包（如关键帧）可参与更多 FEC 包，获更高保护。
4. **`FecControllerDefault`**（`fec_controller_default.cc`）：根据丢包率/RTT/带宽决定 FEC 码率（保护强度）。丢包率高/RTT 高→加 FEC；带宽紧→减 FEC。

**深入：XOR FEC 的数学**。XOR FEC 是 Reed-Solomon 在 GF(2) 的特例。对媒体包 `M1, M2, ..., Mk`，FEC 包 `F = Mi1 ⊕ Mi2 ⊕ ... ⊕ Mim`（掩码选择）。若 `Mi1` 丢失但 `F` 和其余 `Mi2..Mim` 收到，则 `Mi1 = F ⊕ Mi2 ⊕ ... ⊕ Mim`。一个 FEC 包只能恢复其组内**一个**丢失包（XOR 的限制），故 FEC 适合随机单丢，对连续多丢需更多 FEC 包或交织。掩码表的设计是关键——`bursty` 表用相邻包组合抗突发，`random` 表用分散包组合抗随机丢。

#### 5.5.1 深入：FEC 的掩码表与码率数学

**(1) FEC 包数量（`NumFecPackets`，`forward_error_correction.cc:189`）**：
```
num_fec_packets = (num_media_packets · protection_factor + 128) >> 8
```
`protection_factor` 是 0~255 的 Q8 比例（如 51 ≈ 20% 冗余）。`+128` 是四舍五入。即 FEC 包数 ≈ 媒体包数 × 冗余率。`protection_factor>0` 但算出 0 时强制 1（`:194`，至少 1 个 FEC 包）。

**(2) 掩码表（`PacketMaskTable`，`forward_error_correction_internal.cc:145`）**。掩码是一个 `num_fec_packets × num_media_packets` 的**二进制矩阵**，每行对应一个 FEC 包，每 bit 表示对应媒体包是否参与该 FEC 包的 XOR。两种表：
- **`kPacketMaskRandomTbl`**（`fec_private_tables_random.h`）：随机掩码，每个 FEC 包覆盖分散的媒体包——抗**随机独立丢包**，任一 FEC 包可恢复任一丢失。
- **`kPacketMaskBurstyTbl`**（`fec_private_tables_bursty.h`）：突发掩码，每个 FEC 包覆盖相邻媒体包——抗**突发丢包**（连续多丢），但恢复模式不同。
- `PickTable`（`:218`）：按 `FecMaskType` 和媒体包数选表。突发表覆盖范围有限（`kPacketMaskBurstyTbl[0]`），超范围退回随机表。

**(3) XOR 编码（`:207-221`）**。对第 i 个 FEC 包，遍历掩码 bit：
```
if packet_masks_[i] & (1 << (7 - media_pkt_idx)):   # 该 bit 为 1
    F[i] = F[i] XOR media_packets[media_pkt_idx]    # 累加 XOR
```
FEC 包 = 所有"参与"媒体包的逐字节 XOR。

**(4) UEP（不等保护，`num_important_packets`）**。重要包（如关键帧头）参与**更多** FEC 包的 XOR（掩码中重要包列的 1 更多），获更高保护概率。`num_important_packets ≤ num_media_packets`（`:118`）。

**(5) 恢复条件**。一个 FEC 包 `F = Ma ⊕ Mb ⊕ ...` 可恢复 `Ma`，当且仅当 `Mb, Mc, ...` 都收到（即组内除一个外全到）。故：
- 随机丢包下，多个 FEC 包独立覆盖不同子集，恢复概率高。
- 突发丢包下，若丢失包集中在某 FEC 包的覆盖集内（多个同时丢），该 FEC 包无法恢复——需交织（把相邻媒体包分散到不同 FEC 组）或突发掩码。

**(6) `FecControllerDefault` 的码率决策**。根据丢包率 `p`、RTT、带宽 `B` 决定 `protection_factor`：`p` 高/RTT 高 → 提高 `protection_factor`（加冗余）；`B` 紧 → 降冗余（保媒体）。这是**冗余 vs 带宽**的权衡——FEC 占用带宽但降低重传延迟。

### 5.6 PacketBuffer / RtpFrameReferenceFinder / H264SpsPpsTracker / LossNotificationController

- **PacketBuffer**（`packet_buffer.cc`）：按 RTP 序号缓存包，重组为完整帧（检测帧边界、序号连续）。支持 H264 的 FU-A 分片、VP8/VP9 的 RTP 载荷格式。
- **RtpFrameReferenceFinder**（`rtp_frame_reference_finder.cc`）：确定每帧的参考关系（依赖哪些前序帧）。VP8/VP9 从载荷头解析；H264 用 `H264SpsPpsTracker` 跟踪 SPS/PPS 参数集（关键帧依赖参数集）。
- **H264SpsPpsTracker**（`h264_sps_pps_tracker.cc`）：H264 的 SPS/PPS 可能单独 RTP 包或在关键帧内，跟踪参数集 ID，关联到依赖帧。
- **LossNotificationController**（`loss_notification_controller.cc`）：生成/处理 LossNotification RTCP，通知发送端丢包位置（比 NACK 更高效地触发关键帧）。

### 5.7 关键参数

| 参数 | 默认值 | 含义 |
|---|---|---|
| `kMaxFramesBuffered` | 800 | FrameBuffer 最大帧数 |
| `kMaxAllowedFrameDelayMs` | 5 | 最大允许迟到（ms） |
| `JitterEstimator._phi` | 0.97 | 帧大小 EMA 系数 |
| `kDefaultMaxTimestampDeviationInSigmas` | 3.5 | 延迟限幅（σ 倍数） |
| `noiseStdDevs` | 2.33 | 噪声门限（~1%） |
| `kDefaultRttMs` | 100 | NACK 默认 RTT |
| `kMaxNackRetries` | 10 | NACK 最大重试 |
| NACK 退避 base | 1.25 | 指数退避底数 |
| FEC 掩码表 | bursty/random | 保护模式 |
| `ProtectionMode` | NACK/FEC/NACK+FEC | 丢包保护策略 |

### 5.8 业务场景作用

- **随机单丢**（低 RTT）：NACK 重传，延迟增加一个 RTT，恢复快。
- **突发多丢**（高 RTT）：NACK 来回太慢，FEC 在接收端直接恢复（无需 RTT）。
- **关键帧丢失**：`keyframe_required_` 强制等下一关键帧；`LossNotificationController` 触发送端发关键帧；`RemovePacketsUntilKeyFrame` 清旧 NACK。
- **抖动**：`FrameBuffer` 延迟调度 + `JitterEstimator` 自适应延迟，jitter 大则缓冲多帧。
- **屏幕共享**：低帧率高码率，FEC 保护关键帧（文字丢失明显），NACK 对关键帧优先。

---

## 第 6 章：拥塞控制算法（GoogCC / PCC / 接收侧 BWE）

### 6.1 拥塞控制全景与闭环

GoogCC（Google Congestion Control）是 WebRTC 默认的**发送端拥塞控制**，基于 **transport-cc（transport-wide congestion control）反馈**。闭环：

```
发送端 ──发RTP包(带transport-cc序号+时间戳)──► 网络 ──► 接收端
                                                        │
                   ◄── transport-cc反馈(到达时间)── RemoteEstimatorProxy
                   │
              GoogCcNetworkController
              ├─ TrendlineEstimator (延迟趋势检测)
              ├─ AcknowledgedBitrateEstimator (ACK码率)
              ├─ AimdRateControl (AIMD速率控制)
              ├─ ProbeController + ProbeBitrateEstimator (探测)
              ├─ LossBasedBandwidthEstimation (丢包)
              ├─ SendSideBandwidthEstimation (REMB回退)
              └─ CongestionWindowPushbackController (cwnd回压)
                   │
                   ▼ TargetTransferRate + PacerConfig
              BitrateAllocator → SimulcastRateAllocator → 编码器 + PacingController
```

核心思想：**用包的到达延迟变化（排队延迟）推断网络拥塞**——延迟持续上升说明路由器队列堆积，应降速；延迟平稳/下降说明有空余，可加速。

### 6.2 GoogCC 控制循环

`GoogCcNetworkController`（`goog_cc_network_control.h:47`）实现 `NetworkControllerInterface`，由 `RtpTransportControllerSend` 在 task queue 上驱动。关键回调：
- `OnSentPacket(SentPacket)`：每发一个包记录（序号、大小、发送时间），更新 `AlrDetector` 和 outstanding 数据。
- `OnTransportPacketsFeedback(TransportPacketsFeedback)`：收到 transport-cc 反馈（包到达时间、是否到达），核心入口。分发到 `DelayBasedBwe`/`AcknowledgedBitrateEstimator`/`ProbeBitrateEstimator`，综合得 `TargetTransferRate`。
- `OnProcessInterval`：周期触发，处理探测/超时。
- `OnNetworkRouteChange`/`OnTargetRateConstraints`：网络变更/初始约束。

### 6.3 Trendline 延迟估计

**目标**：从 transport-cc 反馈的包到达时间，检测**延迟趋势**（上升=拥塞）。这是 GoogCC 的核心信号。

**算法**（`trendline_estimator.cc`）：
1. **累积延迟**（`:206`）：每个反馈包算 `delta_ms = recv_delta - send_delta`（到达间隔 - 发送间隔，正值=排队延迟增加），`accumulated_delay_ += delta_ms`。
2. **平滑延迟**（`:209`）：`smoothed_delay_ = smoothing_coef_ · smoothed_delay_ + (1 - smoothing_coef_) · accumulated_delay_`，`smoothing_coef_=0.9`（`kDefaultTrendlineSmoothingCoeff`）。
3. **线性回归**（`:62-71`）：在窗口 `window_size=20`（`kDefaultTrendlineWindowSize`）个样本上，对 `(arrival_time, smoothed_delay)` 做**最小二乘线性回归**算斜率 `trend`（`slope`）：
```
slope = Σ(x-x̄)(y-ȳ) / Σ(x-x̄)²
```
斜率 > 0 说明延迟随时间上升（拥塞），< 0 说明下降（空余）。
4. **检测**（`Detect`，`:56`）：用 `threshold = threshold_gain_ · kDefaultTrendlineThresholdGain(4.0)` 与 `trend` 比较，状态机：
   - `trend > threshold` → **overuse**（过载，应降速）
   - `trend < -threshold` → **underuse**（空余，可加速）
   - 之间 → **normal**
   `threshold_` 初值 12.5（`:176`），自适应调整（类似 GCC 原始论文的阈值自适应）。`kOverUsingTimeThreshold=10`（`:109`）要求过载持续一定时间才确认，防抖动。`kMinNumDeltas=60`（`:110`）启动期需足够样本。

**深入：trendline 的数学**。这是 GCC 论文（"A Google Congestion Control Algorithm"）的改进版。原始 GCC 用卡尔曼滤波 + 状态机（`overuse_estimator`/`overuse_detector`，仍在 `remote_bitrate_estimator/` 保留为接收侧 BWE），GoogCC 改用**trendline 线性回归**——更简单、更鲁棒。斜率 `trend` 是延迟变化率，单位 ms/s。`threshold_gain=4.0` 放大阈值防误报。窗口 20 个包平衡响应速度与稳定性。

### 6.4 AIMD 速率控制

**目标**：根据 trendline 的 overuse/underuse 信号，加性增/乘性减调整目标码率。位于 `AimdRateControl`（`aimd_rate_control.cc`），被 GoogCC 和接收侧 BWE 共用。

**状态机**（`RateControlState`，`bwe_defines.h:42`）：`kRcHold`（保持）/`kRcIncrease`（增加）/`kRcDecrease`（减少）。

**算法**（`ChangeBitrate`，`:70`）：
- **Decrease（乘性减）**：overuse 时，`MultiplicativeRateIncrease`（`:79`）：
```
new_bitrate = beta · estimated_throughput    # beta = kDefaultBackoffFactor = 0.85
```
即降到当前吞吐的 85%（`kDefaultBackoffFactor=0.85`，`:35`）。`beta` 可被 field trial 调整。`estimated_throughput` 来自 `AcknowledgedBitrateEstimator`。
- **Increase（加性增）**：underuse/normal 时，`AdditiveRateIncrease`（`:82`）：
```
new_bitrate = current_bitrate + GetNearMaxIncreaseRateBpsPerSecond() · Δt
```
`GetNearMaxIncreaseRateBpsPerSecond`（`:63`）≈ `current_bitrate · 0.08 / RTT`（每 RTT 增 8%），即**加性增但速率与当前码率成正比**（接近线性收敛到瓶颈）。`Δt` 是距上次更新时间。`kDefaultRtt=200ms`（`:34`）。
- **Hold**：保持当前码率（初始或信号不足）。
- **初始降速**（`initial_backoff_interval`，`:102`）：首次过载后 100ms 内允许快速降速，加速收敛。

**深入：AIMD 的数学**。AIMD（Additive Increase Multiplicative Decrease）是 TCP 经典策略：线性增（探测带宽）、乘性减（快速退拥塞）。GoogCC 的改进：增率与当前码率成正比（`0.08·B/RTT`），而非固定步长——高码率时增得快（快速探测）、低码率时增得慢（谨慎）。`beta=0.85` 比 TCP 的 0.5 温和（实时媒体不能降太狠致卡顿）。`ClampBitrate` 限幅到 `[min, max]`。

### 6.5 ALR 检测

**目标**：检测**应用受限区（Application Limited Region, ALR）**——发送端没产生足够数据填满带宽（如屏幕共享静止画面、低帧率），此时 ACK 码率低估真实容量，需主动探测。

**算法**（`alr_detector.cc`）：
1. `OnBytesSent(bytes, send_time)`（`:72`）：用 `IntervalBudget`（`alr_budget_`）跟踪"发了多少 vs 能发多少"。
2. `IncreaseBudget(Δt)`：预算按 `bandwidth_usage_ratio`（默认 ~65%）累积；`UseBudget(bytes)` 扣除实际发送。
3. **判定**（`:85`）：`budget_ratio() > start_budget_level_ratio`（预算堆积超阈值）→ 进入 ALR；`< stop_budget_level_ratio` → 退出。
4. ALR 时触发 `ProbeController` 探测（因 ACK 码率不可信）。

**深入**：ALR 是 GoogCC 区别于 TCP 的关键。TCP 假设发送端总有数据发（受限于网络），但实时媒体受限于采集/编码速率。ALR 检测"发送端是瓶颈"而非"网络是瓶颈"，避免误降速。

### 6.6 探测 ProbeController + ProbeBitrateEstimator

**目标**：主动发**探测包簇**（pacing 突发）测真实容量，用于初始估计、ALR 期间、容量上升时。

**算法**：
- **`ProbeController`**（`probe_controller.cc`）：决定何时探测、探测多大码率。`SetBitrates(min, start, max)` 初始探测（从 start 码率探测到 max）；ALR 时 `RequestProbe`；网络恢复时再探测。`ProbeControllerConfig`（`:30`）：`allocation_probe_max` 等。
- **探测簇**（`PacingController::CreateProbeCluster(bitrate, cluster_id)`）：pacing 以指定码率突发发一组包，`PacedPacketInfo{cluster_id, probe_cluster_min_bytes, min/max_probing_bitrate}` 标记。
- **`ProbeBitrateEstimator`**（`probe_bitrate_estimator.cc`）：收到反馈后，对探测簇的包算**到达码率**（`bytes / duration`），若结果 > 当前估计且稳定（多个包验证），接受为新估计。这避免了 AIMD 慢探测的延迟。

**深入：探测的数学**。探测簇以码率 `R_probe` 发 `N` 个字节，接收端测到达码率 `R_arrive = N / (t_last - t_first)`。若 `R_arrive ≈ R_probe`（无排队，网络容纳），说明容量 ≥ `R_probe`，可升速；若 `R_arrive < R_probe`（排队/丢包），容量 < `R_probe`。多个码率的探测簇（如 2x、4x 当前）快速定位容量。

### 6.7 AcknowledgedBitrateEstimator

**目标**：从 transport-cc ACK 算**实际吞吐**（接收端确认的码率），供 AIMD decrease 用。

**算法**（`acknowledged_bitrate_estimator.cc` + `bitrate_estimator.cc`）：滑窗（`kBitrateWindowMs=1000`）内对 ACK 的字节数/时间做**指数加权移动平均**（类似 KDE/AIMD 的吞吐估计），`BitrateEstimator::Update` 累积 bytes，`rate` 返回当前估计。这是 AIMD `estimated_throughput` 的来源——降速降到"实际能跑的码率"而非盲目乘 beta。

### 6.8 LossBasedBandwidthEstimation

**目标**：用 RTCP 报告的**丢包率**辅助降速（延迟信号之外的补充）。

**算法**（`loss_based_bandwidth_estimation.cc`）：丢包率超阈值（如 >10%）→ 降速；丢包率低（<2%）→ 允许升速。与延迟 BWE 取**较小值**（保守）。丢包是拥塞的强信号（路由器队列满才会丢），但实时媒体对丢包容忍度不同，故作为延迟信号的补充而非主信号。

### 6.9 SendSideBandwidthEstimation（REMB/TMMBR 回退）

**目标**：当 transport-cc 不可用时，用接收端 RTCP 报告的 **REMB（Receiver Estimated Maximum Bitrate）或 TMMBR/TMMBN** 做带宽估计。这是**回退路径**。

**算法**（`send_side_bandwidth_estimation.cc`）：收到 REMB/TMMBR → 更新估计；无反馈时按时间衰减（`kRtt`/超时降速）。增减逻辑类似 AIMD 但基于接收端报告值。与延迟 BWE 取较小值。

### 6.10 CongestionWindowPushbackController

**目标**：用**拥塞窗口（cwnd）**限制发送，当 outstanding 数据超 cwnd 时回压编码器（降码率/帧率）。

**算法**（`congestion_window_pushback_controller.cc`）：`SetCongestionWindow` 设 cwnd，`UpdateOutstandingData` 跟踪在途数据。若 outstanding > cwnd 且在 ALR，触发编码器降码率（`pushback`）。这是除 AIMD 之外的**第二级回压**——AIMD 调目标码率，cwnd 调瞬时发送量。

### 6.11 接收侧 BWE

**目标**：transport-cc 反馈在接收端生成，接收端也可做 BWE（旧路径，`remote_bitrate_estimator/`）。

**算法**（`overuse_estimator.cc` + `overuse_detector.cc` + `inter_arrival.cc`）：
- `InterArrival`：算包间到达时间差 `dt_arrival` 与发送时间差 `dt_send`。
- `OveruseEstimator`：**卡尔曼滤波**估计过载程度（`h`，延迟梯度），状态空间模型：`y = h·x + noise`，卡尔曼更新 `h`。这是 GCC 原始论文的方法。
- `OveruseDetector`：用 `h` 与阈值比较，状态机（Normal/Underuse/Overuse），`overuse_counter` + hold time 防抖。
- `AimdRateControl`：同 6.4，根据状态调码率。
- `RemoteEstimatorProxy`（`remote_estimator_proxy.cc`）：接收端生成 transport-cc 反馈报文（`TransportFeedback` RTCP）发回发送端。
- `ReceiveSideCongestionController`：接收侧拥塞控制主控（当 transport-cc 接收端估计时）。

**深入：卡尔曼 vs trendline**。原始 GCC 用卡尔曼滤波（`overuse_estimator`）估计延迟梯度——状态 `h` 是延迟变化率，观测是 `dt_arrival - dt_send`，卡尔曼最优估计。GoogCC 改用 trendline 线性回归——更直观、无需状态空间建模、对参数不敏感。两者数学等价（都是线性估计），但 trendline 实现简单、易调参。

### 6.12 PCC（备选拥塞控制）

**目标**：基于**效用函数**的拥塞控制（Performance-oriented Congestion Control），`modules/congestion_controller/pcc/`。

**算法**：把码率选择建模为优化效用函数 `U(bitrate)`（如吞吐 - 延迟惩罚）。`MonitorInterval`（`monitor_interval.cc`）发一段探测包测该码率下的效用，`BitrateController`（`bitrate_controller.cc`）用**梯度上升**调整码率：`bitrate += η · ∂U/∂bitrate`。`UtilityFunction`（`utility_function.cc`）定义效用。`RttTracker` 跟踪 RTT。PCC 不依赖延迟趋势检测，直接优化效用，理论更优但实际部署少。

### 6.13 关键参数与数据结构

| 参数 | 默认值 | 含义 |
|---|---|---|
| `kDefaultTrendlineWindowSize` | 20 | trendline 回归窗口（包数） |
| `kDefaultTrendlineSmoothingCoeff` | 0.9 | 延迟平滑系数 |
| `kDefaultTrendlineThresholdGain` | 4.0 | 阈值增益 |
| `threshold_` 初值 | 12.5 | 过载阈值 |
| `kOverUsingTimeThreshold` | 10 | 过载确认时间 |
| `kMinNumDeltas` | 60 | 最少样本数 |
| `kDefaultBackoffFactor` (beta) | 0.85 | AIMD 乘性减因子 |
| `kDefaultRtt` | 200ms | 默认 RTT |
| 增率 | 0.08·B/RTT | AIMD 加性增率 |
| `kBitrateWindowMs` | 1000 | ACK 码率窗口 |
| ALR `bandwidth_usage_ratio` | ~0.65 | ALR 触发比例 |
| `kMaxFecPackets` | — | FEC 最大包数 |

**核心数据结构**（`api/transport/network_types.h`）：
- `SentPacket`（`:104`）：发送包记录（序号、大小、时间）
- `TransportPacketsFeedback`（`:166`）：transport-cc 反馈（包到达时间、丢失）
- `TargetTransferRate`（`:219`）：GoogCC 输出（目标码率）
- `PacerConfig`（`:200`）：pacing 配置（pacing_rate、padding_rate）
- `ProbeClusterConfig`（`:211`）：探测簇配置
- `NetworkControlUpdate`（`:231`）：综合输出（含上述 + 探测请求）

### 6.14 业务场景作用

- **稳态**：延迟平稳，trendline ~0，AIMD 缓慢加性增，逼近瓶颈。
- **容量突降**（网络变差）：延迟上升，trendline > threshold → overuse → AIMD 乘性减（×0.85），快速降速。
- **容量上升**（网络变好）：ALR 检测或周期探测 → `ProbeController` 发探测簇 → `ProbeBitrateEstimator` 测得更高码率 → AIMD 升速。
- **高丢包链路**：`LossBasedBandwidthEstimation` 降速（丢包率 > 阈值）。
- **应用受限**（屏幕共享静止）：ALR 触发探测，避免 ACK 低估容量误降速。
- **无 transport-cc**：`SendSideBandwidthEstimation` 用 REMB/TMMBR 回退。

---

## 第 7 章：Pacing 与 RTP/RTCP 算法

### 7.1 PacingController（漏桶发送整形）

**目标**：把编码器突发产生的 RTP 包**匀速**发到网络，避免突发致路由器队列溢出，并支持探测。位于 `modules/pacing/pacing_controller.cc`，是发送侧的"流量整形器"。

**算法**：
1. **`SetPacingRates(pacing_rate, padding_rate)`**（`:214`）：设 pacing 速率（媒体发送速率）和 padding 速率（填充速率）。`pacing_rate` 通常 = 目标码率 × `kDefaultPaceMultiplier=2.5`（`:88`，2.5 倍以允许追赶），`padding_rate` 用于静音时填充探测。
2. **`IntervalBudget`（令牌桶）**（`interval_budget.cc`）：
   - `media_budget_`/`padding_budget_`：两个令牌桶，`max_bytes_in_budget_ = kWindowMs · target_rate / 8`（`:33`）。
   - `IncreaseBudget(Δt)`（`:38`）：`bytes = rate · Δt / 8`，桶增加（最多到 `max_bytes_in_budget_`）。`can_build_up_underuse_` 控制是否允许欠用累积（`:40`）。
   - `UseBudget(bytes)`（`:49`）：发包扣桶，`bytes_remaining -= bytes`（最多到 `-max_bytes_in_budget_`）。
   - `bytes_remaining()`：剩余可发字节，> 0 才发包。
3. **`ProcessPackets`**：周期调用（`PacedSender` 每 5ms 或 `TaskQueuePacedSender` 动态），按预算发包：
   - 优先发探测簇包（`BitrateProber` 激活时）
   - 按优先级从 `RoundRobinPacketQueue` 取包，扣 `media_budget_`
   - 无媒体包时发 padding（扣 `padding_budget_`）
4. **模式**（`ProcessMode`，`:53`）：`kPeriodic`（周期 5ms，`PacedSender`）/`kDynamic`（动态，`TaskQueuePacedSender`，按计算的下一次发送时间调度）。
5. **拥塞窗**（`:100`）：`SetCongestionWindow` + `UpdateOutstandingData`，outstanding 超 cwnd 时暂停发送（与 `CongestionWindowPushbackController` 配合）。

**深入：令牌桶的数学**。令牌桶是经典流量整形：桶以 `rate` 匀速累积令牌（`bytes_remaining += rate·Δt`），发包消耗令牌（`bytes_remaining -= size`）。`max_bytes_in_budget` 限桶容量（防止欠用累积过多致突发）。`kDefaultPaceMultiplier=2.5` 使 pacing 速率高于目标码率——允许在欠用时追赶（发得比产生快），但长期平均不超过目标。`kMaxExpectedQueueLength`（`:86`）限制队列长度，超时丢包防延迟累积。

### 7.2 BitrateProber（探测注入）

**目标**：在 pacing 中注入**探测簇**——以指定码率突发发一组包测容量。

**算法**（`bitrate_prober.cc`）：
1. **`CreateProbeCluster(bitrate, time, cluster_id)`**（`:89`）：创建探测簇，目标码率 `bitrate`。
2. **状态机**（`ProbingState`：`kDisabled`/`kInactive`/`kActive`）：有簇且数据足够（`>= RecommendedMinProbeSize`，`kMinProbePacketSize=200`，`:29`）→ `kActive`。
3. **注入**：`kActive` 时，`PacingController` 优先发探测簇包，按簇码率算发送间隔（`packet_size / bitrate`），`min_probe_packets_sent=5`（`:37`）保证簇内至少 5 包。
4. **`PacedPacketInfo`**：随包发送簇元数据（cluster_id、min/max probing bitrate、字节），接收端 `ProbeBitrateEstimator` 据此算到达码率。

**深入**：探测是"主动测量"——以高于当前的码率突发发包，看网络是否容纳（到达码率 ≈ 发送码率）vs 排队（到达码率 < 发送码率）。`kMinProbePacketSize=200` 防小包致测量噪声。多簇（如 2x、4x）快速定位容量。

### 7.3 IntervalBudget（令牌桶预算）

见 7.1，核心：`bytes_remaining = clamp(bytes_remaining + rate·Δt - used, -max, +max)`。`can_build_up_underuse` 决定欠用（`bytes_remaining<0`）时是否允许累积补偿。

### 7.4 RoundRobinPacketQueue（优先级队列）

**目标**：多流多类型包的调度，保证优先级 + 公平。

**算法**（`round_robin_packet_queue.cc`）：
1. **优先级**（`:30`）：数字大优先级高。典型：audio > video > retransmit > fec/padding。
2. **`Push(priority, packet)`**（`:137`）：按优先级入队。每流（SSRC）一个子队列。
3. **`Pop()`**（`:158`）：取最高优先级流中"发送字节最少"的包（`:189`，公平——让各流均衡）。`stream_priorities_` 按 `(priority, stream_size)` 排序，`StreamPrioKey`（`:213`）。
4. **优先级抢占**：高优先级包（音频）总是先发，低优先级（padding）最后。

**深入**：这是**加权公平排队（WFQ）的变体**——同优先级内按"已发字节最少"轮转（公平），优先级间严格抢占（音频优先）。保证音频低延迟（不被视频大帧阻塞），同时视频流间公平。

### 7.5 RTP/RTCP

- **RTP 封包**（`rtp_packetizer`）：编码帧拆为 RTP 包，加序号/时间戳/SSRC/transport-cc 扩展。
- **RTP 解包**（`rtp_depacketizer`）：接收端重组，`PacketBuffer` 组帧。
- **RTCP**（`rtcp_sender.cc`/`rtcp_receiver.cc`）：发送/接收 RTCP 报告（SR/RR 含丢包率/RTT/jitter）、transport-cc 反馈（`TransportFeedback`）、NACK、FIR/PLI（关键帧请求）、REMB/TMMBR。
- **`receive_statistics`**（`receive_statistics_impl.cc`）：统计丢包率/抖动/RTT，供 RTCP 报告。

### 7.6 关键参数与业务场景

| 参数 | 默认值 | 含义 |
|---|---|---|
| `kDefaultPaceMultiplier` | 2.5 | pacing 速率倍数 |
| `kMaxExpectedQueueLength` | — | 最大队列长度 |
| `kPausedProcessInterval` | — | 暂停时检查间隔 |
| `kMinProbePacketSize` | 200 | 最小探测包 |
| `min_probe_packets_sent` | 5 | 簇内最少包数 |
| 优先级 | audio>video>rtx>fec | 调度优先级 |

**业务场景**：突发平滑（pacing 匀速化突发）、探测（`BitrateProber` 注入）、音频优先（`RoundRobinPacketQueue`）、cwnd 回压（outstanding 超限时暂停）。

---

## 第 8 章：算法协同与业务场景总览

### 8.1 端到端算法协同图

```
┌──────────────────────── 发送侧协同 ────────────────────────┐
│ 音频: ADM → APE(AEC3→NS→AGC2) → 编码 → Pacing(音频优先)      │
│ 视频: 采集 → VPM → VideoStreamEncoder                         │
│         ├─ QualityScaler(QP→分辨率) ┐                         │
│         ├─ FrameDropper(漏桶→丢帧)  ├ 适配决策                 │
│         ├─ OveruseFrameDetector(CPU)┘                         │
│         └─ 编码 → SimulcastRateAllocator(层码率)              │
│                    ↓                                          │
│         BitrateAllocator(多流分配) ← GoogCC(TargetRate)       │
│                    ↓                                          │
│         PacingController(整形) + BitrateProber(探测)           │
│                    ↓                                          │
│                    网络                                        │
└───────────────────────────────────────────────────────────────┘
                              ↕ transport-cc/RTCP 反馈
┌──────────────────────── 接收侧协同 ────────────────────────┐
│ 音频: RTP → NetEq(InsertPacket→DelayManager→DecisionLogic   │
│         → Expand/Accelerate/Merge → 解码 → PostDecodeVad)     │
│ 视频: RTP → PacketBuffer → ReferenceFinder → FrameBuffer2     │
│         (JitterEstimator→Timing→解码调度)                     │
│         ├─ NackModule(丢包→重传请求)                          │
│         └─ FEC(ULPXOR/flexfec→恢复)                          │
│         → 解码 → 渲染(Timing)                                  │
│         → RemoteEstimatorProxy(transport-cc反馈)              │
└───────────────────────────────────────────────────────────────┘
```

### 8.2 闭环反馈链

**主闭环（码率）**：接收端 `RemoteEstimatorProxy` 生成 transport-cc 反馈 → 发送端 `GoogCcNetworkController`：`TrendlineEstimator` 检测延迟趋势 → `AimdRateControl` AIMD 调码率 → `ProbeController`/`BitrateProber` 探测 → `TargetTransferRate` → `BitrateAllocator`（多流分配）→ `SimulcastRateAllocator`（层分配）→ 编码器目标码率 + `PacingController` 速率。

**辅闭环（质量）**：编码器输出 QP → `QualityScaler` 判定 → 升/降分辨率；`OveruseFrameDetector` 检测 CPU 用时 → `FrameDropper` 丢帧/降帧率。

**丢包闭环**：接收端 `NackModule` 检测缺口 → RTCP NACK → 发送端重传；`FecControllerDefault` 按丢包率调 FEC 冗余 → `ForwardErrorCorrection` 生成 FEC 包 → 接收端 `FlexfecReceiver` 恢复。

### 8.3 典型业务场景算法联动

**弱网降码率**：
1. 延迟上升 → `TrendlineEstimator` overuse → `AimdRateControl` ×0.85 降速
2. `TargetTransferRate` 降 → `BitrateAllocator` 降各流 → `SimulcastRateAllocator` 降层
3. 若 QP 仍高 → `QualityScaler` 降分辨率
4. `PacingController` 降 pacing 速率

**丢包恢复**：
1. 随机单丢 → `NackModule` 请求重传（低 RTT）
2. 突发多丢 → `FEC` 接收端恢复（高 RTT）
3. 关键帧丢 → `LossNotificationController` 触发 PLI/FIR → 发送端关键帧

**抖动应对**：
1. 音频：`NetEq` `DelayManager` 升目标缓冲 → `Accelerate`/`PreemptiveExpand` 调整
2. 视频：`JitterEstimator` 升 jitter 估计 → `Timing` 升渲染延迟 → `FrameBuffer2` 多缓冲

**回声场景**：
1. `AEC3` 消回声（双滤波器 + 近端检测）
2. `NS` 降噪（AEC 后）
3. `AGC2` 增益（RNN VAD 门控）
4. `echo_detector` 监测残留

**屏幕共享**：
1. `ALR` 检测（静止画面应用受限）→ `ProbeController` 探测
2. 低帧率高码率 + `kBaseHeavy3TlRateAllocation`（base-heavy 时间层）
3. `FEC` 保护关键帧（文字丢失明显）

### 8.4 算法参数调优速查表

| 场景 | 推荐配置 |
|---|---|
| 高质量会议 | AEC3+NS(k12dB)+AGC2(adaptive)，GoogCC，Simulcast 多层 |
| 弱网移动 | NS(k18dB)，GoogCC 降速，FEC+NACK，降分辨率 |
| 屏幕共享 | ALR 探测，base-heavy 时间层，低帧率高码率，FEC 保护关键帧 |
| 高丢包链路 | FEC 冗余↑（protection_factor↑），NACK 退避↑，GoogCC beta↓ |
| 低延迟 | NetEq min_delay↓，FrameBuffer 低延迟模式，pacing multiplier↓ |

---

## 附录

### A. 关键文件-类-参数索引表（按算法域）

| 算法域 | 关键文件 | 关键类 | 关键参数 |
|---|---|---|---|
| AEC3 | `aec3/echo_canceller3.cc` | `EchoCanceller3`/`BlockProcessor`/`EchoRemover` | `EchoCanceller3Config`(Delay/Filter/Erle) |
| NS | `ns/noise_suppressor.cc` | `NoiseSuppressor`/`WienerFilter`/`SpeechProbabilityEstimator` | `NsConfig::SuppressionLevel` |
| AGC2 | `agc2/adaptive_digital_gain_applier.cc` | `GainController2`/`AdaptiveDigitalGainApplier`/`RnnVad` | `GainController2`(fixed/adaptive) |
| AGC1 | `agc/agc.cc` | `Agc`/`AgcManagerDirect`/`LoudnessHistogram` | `GainController1`(target_level/compression_gain) |
| NetEq | `neteq/neteq_impl.cc` | `NetEqImpl`/`DecisionLogic`/`Expand`/`TimeStretch` | `NetEq::Config`(max_packets/max_delay) |
| QualityScaler | `utility/quality_scaler.cc` | `QualityScaler`/`QpSmoother` | `QpThresholds`(low/high) |
| FrameDropper | `utility/frame_dropper.cc` | `FrameDropper` | `kLeakyBucketSizeSeconds` |
| Simulcast | `utility/simulcast_rate_allocator.cc` | `SimulcastRateAllocator` | `kLayerRateAllocation` |
| BitrateAllocator | `call/bitrate_allocator.cc` | `BitrateAllocator` | `MediaStreamAllocationConfig` |
| FrameBuffer | `video_coding/frame_buffer2.cc` | `FrameBuffer` | `kMaxFramesBuffered` |
| Jitter | `video_coding/jitter_estimator.cc` | `VCMJitterEstimator` | `_phi`/`noiseStdDevs` |
| NACK | `video_coding/nack_module.cc` | `NackModule` | `kMaxNackRetries`/backoff |
| FEC | `rtp_rtcp/source/forward_error_correction.cc` | `ForwardErrorCorrection`/`PacketMaskTable` | `protection_factor`/mask |
| GoogCC | `goog_cc/goog_cc_network_control.cc` | `GoogCcNetworkController`/`TrendlineEstimator`/`AimdRateControl` | trendline window/threshold, beta |
| ALR | `goog_cc/alr_detector.cc` | `AlrDetector` | `bandwidth_usage_ratio` |
| Probe | `goog_cc/probe_controller.cc` | `ProbeController`/`ProbeBitrateEstimator` | probe bitrate |
| Pacing | `pacing/pacing_controller.cc` | `PacingController`/`IntervalBudget`/`BitrateProber` | `kDefaultPaceMultiplier` |
| Queue | `pacing/round_robin_packet_queue.cc` | `RoundRobinPacketQueue` | priority |

### B. 术语表

| 术语 | 含义 |
|---|---|
| AEC | Acoustic Echo Cancellation，回声消除 |
| ERL | Echo Return Loss，回声回损（render→capture 天然衰减） |
| ERLE | Echo Return Loss Enhancement，AEC 额外增强衰减 |
| NER | Near-End Residual，近端残差 |
| NS | Noise Suppression，降噪 |
| AGC | Automatic Gain Control，自动增益控制 |
| VAD | Voice Activity Detection，语音活动检测 |
| PLC | Packet Loss Concealment，丢包隐藏 |
| WSOLA | Waveform Similarity Over-Add，波形相似性重叠相加（时间拉伸） |
| CNG | Comfort Noise Generation，舒适噪声生成 |
| DTX | Discontinuous Transmission，不连续发送 |
| IAT | Inter-Arrival Time，到达间隔时间 |
| BWE | Bandwidth Estimation，带宽估计 |
| GoogCC | Google Congestion Control，谷歌拥塞控制 |
| AIMD | Additive Increase Multiplicative Decrease，加性增乘性减 |
| ALR | Application Limited Region，应用受限区 |
| transport-cc | Transport-wide Congestion Control，传输层拥塞控制反馈 |
| REMB | Receiver Estimated Maximum Bitrate，接收端估计最大码率 |
| TMMBR/TMMBN | Temporary Maximum Media Bit Rate，临时最大媒体码率请求/通知 |
| FEC | Forward Error Correction，前向纠错 |
| NACK | Negative Acknowledgement，否定确认（重传请求） |
| Simulcast | 同源多流（多分辨率并发编码） |
| QP | Quantization Parameter，量化参数 |
| PLC | Packet Loss Concealment |
| UEP | Unequal Error Protection，不等错误保护 |
| PCC | Performance-oriented Congestion Control，性能导向拥塞控制 |
| cwnd | Congestion Window，拥塞窗口 |

### C. 参考文档

- `wr-arch-design-analysis.md`：架构设计（分层/并发/传输/设计模式）
- `wr-modules-analysis.md`：模块架构（26 个模块职责）
- `wr-whole-process.md`：完整业务流程
- `neteq/docs-lu/nq.md`：NetEq 代码深度分析
- GCC 论文："A Google Congestion Control Algorithm for Real-Time Communication"
- RFC 5109 (ULPFEC), RFC 3550 (RTP/RTCP), RFC 8888 (transport-cc)
