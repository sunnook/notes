# 音视频链路全栈详要

> 项目: KV6 IPC/可视对讲设备 (F1Plus/F2pro/A2S/AI2)
> 版本: V3.14.0
> 代码路径: PJ14PD20260428091_V3.14.0/
> 参考: hicore-architecture-analysis.md, netConn-design-analysis.md

---

## 文档目录

|  章节  |                                                       内容                                                        |
|:------:|:-----------------------------------------------------------------------------------------------------------------:|
| 第1章  |                              音视频链路总览 — 系统全景图、数据流/控制流概览、关键术语                              |
| 第2章  |                              初始化全流程 — DSP/音视频/网络/存储/三阶段启动模型                                     |
| 第3章  |                              DSP 编解码管线 — 视频/音频编码、共享内存、命令回调、安全加密                             |
| 第4章  |                              网络协议栈（多层） — SDK/RTSP/RTP/ONVIF/SIP/萤石/WebSocket/Ehome                        |
| 第5章  |                              QoS 保障体系 (NPQ) — NACK/FEC/去抖动/带宽自适应/Pacing/音视频同步                       |
| 第6章  |                              存储系统 — storLib 架构、设备管理、文件管理、数据服务、录像规划                          |
| 第7章  |                              业务场景全流程 — 实时预览 (SDK/RTSP/WebSocket/萤石/多通道)                              |
| 第8章  |                              业务场景全流程 — 录像存储 (计划/移动侦测/报警/回放/搜索)                                |
| 第9章  |                              业务场景全流程 — 可视对讲 (SIP信令/媒体流/编解码切换/3方通话)                            |
| 第10章 |                              业务场景全流程 — 语音对讲 (SDK/RTSP/广播系统/报警语音)                                  |
| 第11章 |                              数据流全景图 — 视频/音频/控制/事件/配置 五大数据流                                       |
| 第12章 |                              模块间关系与交互 — 依赖图、opdevsdk IPC总线、POSIX mq、共享内存、事件驱动、线程协作       |
| 第13章 |                              设计模式与关键技术 — 七层架构、能力检测、配置驱动、三阶段启动、线程管理、安全机制         |
| 附录A  |                                          编解码类型速查表 (视频5种 + 音频6种)                                          |
| 附录B  |                                              端口与协议对照表 (12个端口)                                              |
| 附录C  |                                          帧结构定义 (NETCMD_HEADER/RTSP Track/PS Stream ID)                                          |
| 附录D  |                                              NPQ API 参考                                              |
| 附录E  |                                              线程-模块-栈大小速查表                                              |

---

## 第1章：音视频链路总览

### 1.1 系统音视频全景图

KV6 设备是一台嵌入式网络视频摄像机/可视对讲终端，其核心职责是**采集音视频 → 编码压缩 → 网络传输/本地存储**，同时支持**双向对讲**和**丰富的业务场景**（门禁、广播、云连接等）。

整个音视频链路可以概括为以下四层：

```
┌─────────────────────────────────────────────────────────────────────┐
│                    第1层：业务应用层                                   │
│  ┌──────────┬──────────┬──────────┬──────────┬──────────┐           │
│  │ 实时预览  │ 录像回放  │ 可视对讲  │ 广播系统  │ 云连接    │           │
│  │ SDK/RTSP │ 录像回放  │ SIP信令  │ 实时/定时 │ 萤石云    │           │
│  │ WebSocket│ 文件下载  │ 双向媒体  │ RTP寻呼  │ 外网访问  │           │
│  └──────────┴──────────┴──────────┴──────────┴──────────┘           │
├─────────────────────────────────────────────────────────────────────┤
│                    第2层：协议控制层                                   │
│  ┌──────────┬──────────┬──────────┬──────────┬──────────┐           │
│  │ SDK协议  │  RTSP    │  RTP/   │  SIP     │  萤石    │           │
│  │ 二进制   │  信令控制 │  RTCP   │  信令    │  云协议  │           │
│  │ TCP 8000│  554     │  动态   │  5060    │  HTTPS   │           │
│  └──────────┴──────────┴──────────┴──────────┴──────────┘           │
├─────────────────────────────────────────────────────────────────────┤
│                    第3层：QoS 保障层                                  │
│  ┌──────────────────────────────────────────────────────┐           │
│  │  NPQ (Network Quality)                               │           │
│  │  NACK | FEC | Jitter Buffer | BW Adapt | Pacing    │           │
│  └──────────────────────────────────────────────────────┘           │
├─────────────────────────────────────────────────────────────────────┤
│                    第4层：编解码与硬件层                               │
│  ┌──────────┬──────────┬──────────┬──────────┬──────────┐           │
│  │ 摄像头   │  DSP     │  存储    │  网络    │  音频    │           │
│  │ 传感器   │ H.264/   │  TF卡    │  以太网  │  麦克风  │           │
│  │ ISP处理  │ H.265/   │  SATA    │  WiFi    │  扬声器  │           │
│  │          │ MPEG4    │          │  PPP     │          │           │
│  └──────────┴──────────┴──────────┴──────────┴──────────┘           │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.2 数据流与控制流概览

#### 1.2.1 视频数据流（采集 → 编码 → 分发）

```
[摄像头传感器]
    │  模拟/数字视频信号
    ▼
[ISP 图像处理]
    isp_sensor_interface.c / isp_sensor_setting.c
    │  曝光、白平衡、色彩校正、降噪
    ▼
[DSP 硬件编码]
    dsp_callback.c / dsp_interface.c
    │  H.264 / H.265 / MPEG4 编码
    │
    ├──→ 主码流 (Main Stream)
    │     ├─→ 录像存储 (storLib → TF卡/SATA)
    │     ├─→ 云存储上传 (cstor)
    │     └─→ 萤石云预览 (ezviz)
    │
    ├──→ 子码流 (Sub Stream)
    │     ├─→ SDK 实时预览 (dvrNetServer → 客户端)
    │     ├─→ RTSP 预览 (rtsp_server → RTP)
    │     ├─→ WebSocket 预览 (ws_preview → 浏览器)
    │     └─→ ISAPI JPEG 预览 (isapi_http_jpeg_preview)
    │
    └──→ JPEG 抓拍
          ├─→ 事件截图 (event trigger)
          ├─→ 定时截图 (timing)
          └─→ FTP/邮件上传
```

#### 1.2.2 音频数据流（采集 → 编码 → 分发）

```
[麦克风/线路输入]
    │
    ▼
[DSP 音频编码]
    dsp_callback.c / dsp_interface.c
    │  G.711A / G.711U / G.722 / AAC / G.726
    │
    ├──→ RTSP 音频流 (RTP payload)
    ├──→ SDK 语音对讲 (NETCMD_VOICE_TALK)
    ├──→ SIP 对讲音频 (ysip → RTP)
    ├──→ 广播系统 (unicast/multicast/broadcast)
    └──→ 录像存储 (与视频流同步写入)
```

#### 1.2.3 控制数据流（客户端 → 设备）

```
[SDK 客户端 / Web / 手机App]
    │  配置命令 / 控制指令
    ▼
[网络接入层]
    SDK TCP 8000 / HTTP 80 / RTSP 554 / SIP 5060
    │
    ▼
[协议解析层]
    dvrNet.c (SDK) / isapi_entry.c (ISAPI) / rtsp_server.c (RTSP)
    │
    ▼
[业务处理层]
    权限校验 → 参数验证 → 配置写入 → 硬件控制
    │
    ▼
[执行层]
    HAL/DAL → GPIO/I2C/SPI → 硬件执行
```

### 1.3 关键术语与缩写

| 缩写 | 全称 | 说明 |
|------|------|------|
| **DSP** | Digital Signal Processor | 数字信号处理器，硬件编解码 |
| **ISP** | Image Signal Processor | 图像信号处理器 |
| **IPC** | Internet Protocol Camera | 网络摄像机 |
| **RTSP** | Real Time Streaming Protocol | 流媒体控制协议 (RFC 2326) |
| **RTP** | Real-time Transport Protocol | 实时传输协议 (RFC 3550) |
| **RTCP** | Real-Time Control Protocol | 实时传输控制协议 |
| **SRTP** | Secure RTP | 加密 RTP (RFC 3711) |
| **NPQ** | Network Quality | 海康 QoS 保障库 |
| **NACK** | Negative ACK | 负确认重传机制 |
| **FEC** | Forward Error Correction | 前向纠错 |
| **Pacing** | 流量整形 | 控制数据包发送节奏 |
| **TCC** | Transport-Level Congestion Control | 传输层拥塞控制 |
| **REMB** | Receiver Estimated Maximum Bitrate | 接收端估算最大码率 |
| **SIP** | Session Initiation Protocol | 会话发起协议 (RFC 3261) |
| **ONVIF** | Open Network Video Interface Forum | 开放视频接口标准 |
| **ISAPI** | Internet Service API | 海康 RESTful API |
| **SADP** | Smart Address Discovery Protocol | 海康设备发现协议 |
| **Ehome/ISUP** | 海康设备上行协议 | 设备主动上报平台 |
| **storLib** | Storage Library | 海康存储库 |
| **HAL** | Hardware Abstraction Layer | 硬件抽象层 |
| **DAL** | Device Abstraction Layer | 设备抽象层 |
| **HOI** | Hardware Interface | 硬件接口层 |
| **opdevsdk** | Open Device SDK | 海康 IPC 通信框架 |
| **AIP** | Application Integration Platform | 应用集成平台 |
| **VBR** | Variable Bit Rate | 可变码率 |
| **CBR** | Constant Bit Rate | 固定码率 |
| **I/P/B 帧** | Intra/Predicted/Bidirectional | H.264 帧类型 |
| **PS** | Packetized Stream | MPEG 封装格式 |
| **SDP** | Session Description Protocol | 会话描述协议 |
| **EEP** | 门口机/可视对讲终端 | 本设备类型 |

### 1.4 与整体架构的关系

在 hicore 整体架构中，音视频链路贯穿多个模块：

```
┌─────────────────────────────────────────────────────────────┐
│  mainCtrl (主控)                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ dsp_init / dsp_callback / dsp_command / dsp_interface│    │
│  │ init_preview / vis_audio_paly_module_startup         │    │
│  └─────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│  netConn (网络)                                              │
│  ┌──────┬──────┬──────┬──────┬──────┬──────┬──────┐        │
│  │ RTSP │ RTP  │ NPQ  │ SIP  │ SDK  │ 云   │ WS   │        │
│  │ Server│传输  │ QoS  │ 信令  │协议  │连接  │推送  │        │
│  └──────┴──────┴──────┴──────┴──────┴──────┴──────┘        │
├─────────────────────────────────────────────────────────────┤
│  storage (存储)                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ storLib: Device → FileManage → Record → Schedule    │    │
│  └─────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│  mediaPlay (媒体播放)                                         │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ vis_audio / broadcast / videoAds                    │    │
│  └─────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│  intercomSystem (对讲)                                        │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ talkback_control / analog / SIP 集成                 │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

音视频链路的核心特征是**跨模块协作**：DSP 编码在 mainCtrl，网络传输在 netConn，存储
在 storage，播放/广播在 mediaPlay，对讲在 intercomSystem。各模块通过 **opdevsdk IPC 框架**
和 **POSIX 消息队列**进行协作。

---

## 第2章：初始化全流程

### 2.1 三阶段启动模型回顾

KV6 的启动过程分为三个严格串行的阶段，音视频相关初始化分布在各阶段中：

```
main()
  │
  ├─ 阶段 1: 平台基础初始化 (aip_base)
  │   内容: 看门狗、安全用户锁、时间管理
  │   ★ 不涉及音视频
  │
  ├─ 阶段 2: 系统级初始化 (user_sysinit)
  │   ★ 关键: dsp_init() — DSP 音频初始化
  │   ★ 关键: setVSParams() — 设置视频参数
  │   ★ 关键: openssl_init() — 加密库(音视频加密依赖)
  │
  └─ 阶段 3: 应用业务初始化 (usrAppEntry)
      ★ 关键: init_preview() — 预览组件初始化
      ★ 关键: vis_audio_paly_module_startup() — 音频播放
      ★ 关键: dsp_if_netbuf_info() — DSP 网络缓冲区
      ★ 关键: dsp_if_insert_iframe() — DSP 关键帧插入
      ★ 关键: rtsp_server_module_startup() — RTSP 服务
      ★ 关键: NPQ_Process_start() — QoS 初始化
      ★ 关键: init_stor_system() — 存储系统
```

### 2.2 DSP 初始化详解

**文件**: `mainCtrl/dsp/dsp_init.c/h`, `dsp_callback.c/h`, `dsp_command.c/h`, `dsp_interface.c/h`

DSP（Digital Signal Processor）是海思平台的硬件编解码芯片，负责视频 H.264/H.265 编码
和音频 G.711/G.722/AAC 编码。

#### 2.2.1 DSP 初始化流程

```
dsp_init() [user_sysinit 阶段调用]
  │
  ├─ 1. 加载 DSP 固件/参数
  │     └─ 从 Flash 读取 DSP 配置文件
  │
  ├─ 2. 初始化音频编解码参数
  │     └─ AUDIOPARAMS 结构体配置
  │         ├── encoding_type: G.711A/G.711U/AAC/G.722
  │         ├── sample_rate: 8000Hz
  │         ├── channels: 1(Mono) / 2(Stereo)
  │         └── bit_rate: 64kbps (G.711) / 128kbps (AAC)
  │
  ├─ 3. 注册音频数据回调
  │     └─ dsp_callback.c 中的音频回调函数
  │
  ├─ 4. 初始化 DSP 共享内存
  │     └─ SHARE_MEM 结构体 (common.h)
  │
  └─ 5. 启动 DSP 服务
        └─ DSP 开始运行，等待编码请求
```

#### 2.2.2 DSP 接口模块

| 文件 | 职责 | 关键接口 |
|------|------|---------|
| `dsp_init.c/h` | DSP 参数配置与启动 | `dsp_init()` |
| `dsp_callback.c/h` | 音频数据回调 | 音频编码完成回调 |
| `dsp_command.c/h` | DSP 指令下发 | 编码参数修改、关键帧请求 |
| `dsp_interface.c/h` | 对外统一接口 | `dsp_if_netbuf_info()`, `dsp_if_insert_iframe()` |

#### 2.2.3 usrAppEntry 中的 DSP 后续初始化

```c
// usrAppEntry.c 中，在网络服务启动前
init_preview();                      // 预览组件初始化
dsp_if_netbuf_info();                // 配置 DSP 网络缓冲区
dsp_if_insert_iframe();              // 配置关键帧插入策略
```

这三个接口是 DSP 与网络传输的桥梁：
- **`init_preview()`**: 初始化预览组件，建立 DSP 编码数据到内存的通道
- **`dsp_if_netbuf_info()`**: 告知 DSP 网络传输的缓冲区信息，用于 RTP 打包
- **`dsp_if_insert_iframe()`**: 配置 DSP 在什么条件下插入关键帧（I 帧），
  影响 NACK 重传和断线恢复速度

### 2.3 音视频模块初始化

#### 2.3.1 预览组件初始化 (init_preview)

```
init_preview()
  │
  ├─ 1. 创建预览组件实例
  │     └─ 分配预览上下文结构体
  │
  ├─ 2. 注册 DSP 编码回调
  │     └─ DSP 编码完成后通知预览组件
  │
  ├─ 3. 配置主/子码流参数
  │     ├── 主码流: H.264, 高分辨率, 高码率 (用于录像)
  │     └── 子码流: H.264/MJPEG, 低分辨率, 低码率 (用于预览)
  │
  ├─ 4. 分配共享内存
  │     └─ alloc_share_memory() — 视频帧和 JPEG 共享内存
  │
  └─ 5. 启动预览线程
        └─ 从 DSP 获取编码帧并分发到各通道
```

#### 2.3.2 音频播放模块初始化 (vis_audio_paly_module_startup)

```
vis_audio_paly_module_startup()
  │
  ├─ 1. 创建音频播放线程 (vis_audio_play_task)
  │     └─ 优先级: AUDIOSEND_PRIO (70)
  │     └─ 栈大小: IPC_AUDIOPLAY
  │
  ├─ 2. 初始化音频解码器
  │     └─ 支持 G.711A/G.711U/AAC/G.726 解码
  │
  ├─ 3. 注册音频播放回调
  │     └─ vis_audio.c 中的音频输出函数
  │
  └─ 4. 初始化动作优先级管理
        └─ actionPriority/ — 不同音频冲突时的优先级
```

### 2.4 网络服务初始化

#### 2.4.1 RTSP 服务初始化

```
rtsp_server_module_startup()
  │
  ├─ 1. 创建 RTSP 服务线程
  │     └─ 优先级: RTSP_PRIO (60)
  │
  ├─ 2. 监听 RTSP 端口 (默认 554)
  │
  ├─ 3. 初始化客户端状态表
  │     └─ Mpeg4ClientInfo — 每通道独立客户端跟踪
  │
  └─ 4. 获取设备配置
        └─ GetDevconfig() — 匿名登录、用户名/密码、IP、组播IP、MAC
```

#### 2.4.2 SIP 服务初始化

```
exosipcIf_init()                    // SIP 客户端初始化
ysip_server_process_startup()       // SIP 服务端启动

SIP 模块结构:
  ysipc/                            // 萤石私有 SIP
    ├── ysipClientInterface.cpp     // SIP 客户端接口
    ├── ysipXmlProc.c               // XML 消息处理
    ├── ysipMediaStream.c           // 媒体流管理
    └── sipc_reg_manager.cpp        // 注册管理器
  exosipcApp/                       // ExoSIP 应用层
    ├── sipc_message_proc.c         // 消息处理
    ├── sipc_media_trans.c          // 媒体传输
    └── sipc_app_api.c              // 应用 API
```

#### 2.4.3 SDK 网络服务初始化

```
dvrnet_server_module_startup()      // SDK TCP 服务器 (8000端口)
dvrnet_tls_server_module_startup()  // SDK TLS 服务器 (8443端口)
visnet_server_module_startup()      // 私有协议服务器 (8102端口)
net_broken_server_module_startup()  // 断线心跳服务 (6666端口)
```

### 2.5 存储系统初始化

```
init_stor_system()
  │
  ├─ 1. 初始化存储设备管理
  │     ├── SATA 硬盘检测
  │     └── USB/SD 卡检测
  │
  ├─ 2. 初始化文件管理系统
  │     └── 挂载文件系统 (FAT32/EXT4)
  │
  ├─ 3. 初始化录像服务
  │     ├── streamRecord 线程 (每通道一个, 256KB 栈)
  │     └── recordSchedule 线程 (512KB 栈)
  │
  └─ 4. 初始化搜索系统
        └── search_ctrl_task (256KB 栈)
```

### 2.6 QoS 初始化

```
NPQ_Process_start()
  │
  ├─ 1. 创建 NPQ 管理线程
  │     └─ NPQ_Manage_Task (16KB 栈, COMMON_PRIO/50)
  │
  ├─ 2. 初始化 NPQ 实例
  │     ├── NPQ_Create(NPQ_QOS_SENDER) — 发送端 QoS
  │     └── NPQ_Create(NPQ_QOS_RECEIVER) — 接收端 QoS
  │
  ├─ 3. 配置 QoS 参数
  │     ├── NACK 使能
  │     ├── FEC 使能
  │     ├── 去抖动缓冲区
  │     ├── 带宽自适应
  │     └── Pacing 使能
  │
  └─ 4. 注册数据回调
        └── NPQ_RegisterDataCallBack()
```

### 2.7 初始化依赖关系图

```
阶段2: user_sysinit()
  │
  ├─ openssl_init() ──────────────────────┐
  ├─ dsp_init() ───────────────┐           │
  ├─ setVSParams() ────────┐   │           │
  ├─ init_net_interface() ─┤   │           │
  └─ alloc_share_memory() ─┘   │           │
                                ▼           ▼
阶段3: usrAppEntry()              DSP 就绪   内存就绪
  │
  ├─ opdevsdk_ipc_init() ──────→ IPC 就绪
  │
  ├─ init_preview() ──────────→ 预览组件就绪 (依赖: DSP + 内存)
  ├─ dsp_if_netbuf_info() ────→ DSP 网络缓冲区就绪
  ├─ dsp_if_insert_iframe() ──→ DSP 关键帧策略就绪
  │
  ├─ vis_audio_paly_module_startup() → 音频播放就绪 (依赖: DSP)
  │
  ├─ rtsp_server_module_startup() → RTSP 就绪 (依赖: 网络 + 预览)
  ├─ dvrnet_server_module_startup() → SDK 就绪 (依赖: 网络 + 预览)
  ├─ exosipcIf_init() → SIP 客户端就绪 (依赖: 网络)
  ├─ ysip_server_process_startup() → SIP 服务端就绪
  │
  ├─ NPQ_Process_start() → QoS 就绪 (依赖: RTSP/RTP)
  │
  ├─ init_stor_system() → 存储就绪 (依赖: 文件系统)
  │
  └─ bDevAppStarted = TRUE → ★ 系统就绪
```

---

## 第3章：DSP 编解码管线

### 3.1 DSP 架构总览

Davinci DSP 平台是海思的硬件编解码芯片，集成以下功能：

```
┌─────────────────────────────────────────────────────────────┐
│                    Davinci DSP                               │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │  Video Encoder  │  │  Audio Encoder  │                   │
│  │                 │  │                 │                   │
│  │ H.264/High      │  │ G.711A/U        │                   │
│  │ Profile/Main    │  │ G.722 (16/24/32)│                   │
│  │ H.265           │  │ AAC             │                   │
│  │ MPEG4           │  │ G.726           │                   │
│  │ MJPEG           │  │ G.722.1         │                   │
│  │                 │  │ ADPCM           │                   │
│  └────────┬────────┘  └────────┬────────┘                   │
│           │                    │                              │
│  ┌────────┴────────────────────┴────────┐                    │
│  │         Share Memory                  │                    │
│  │   DSPSHAREDATA / SHARE_MEM            │                    │
│  └───────────────────┬───────────────────┘                    │
│                      │                                        │
│  ┌───────────────────┴───────────────────┐                    │
│  │      DSP Command & Callback           │                    │
│  │   dsp_command.c / dsp_callback.c      │                    │
│  └───────────────────────────────────────┘                    │
└─────────────────────────────────────────────────────────────┘
```

DSP 通过**共享内存**与 Host (ARM CPU) 通信，通过**命令接口**接收配置，通过**回调函数**
通知编码完成。

### 3.2 视频编码管线

#### 3.2.1 编码参数配置

视频编码参数定义在 `davinci_dsp/common.h` 的 `STREAMPARAMS` 结构体中：

```c
typedef struct {
    // 视频编码类型 (支持多种)
    unsigned short video_enc_type[MAX_STREAMS];
    // 封装类型 (PS/RTP/TS)
    unsigned short packet_type[MAX_STREAMS];
    // 音频参数
    AUDIOPARAMS audioParam;
    // 分辨率
    IMAGE_SIZE image_size;
    // 码率控制
    unsigned int bps_type;      // VBR 或 CBR
    unsigned int max_bps;       // 最大码率
    unsigned int min_bps;       // 最小码率
    // 帧率
    unsigned int frame_rate;
    // I 帧间隔
    unsigned int iframe_interval;
    // B 帧数量 (0/1/2)
    unsigned int b_frame_num;
    // 图像质量 (0-100)
    unsigned int quality;
    // 编码 profile
    unsigned int profile;       // 0=baseline, 1=main, 2=high
    // 镜像设置
    unsigned int mirror_type;   // 0=无, 1=水平, 2=垂直, 3=旋转
    // 隐私掩码区域
    PRIVACY_REGION privacy_mask[MAX_PRIVACY_MASK_NUM];
    // ROI 区域
    ROI_REGION roi[ROI_MAX_REGION];
} STREAMPARAMS;
```

#### 3.2.2 帧结构体系

KV6 的帧结构分为三层：

**第1层: MEGA_STREAM_HEADER** (流头部)
```c
typedef struct {
    unsigned int magic;       // 0x20122012 (魔数标识)
    unsigned int type;        // 流类型 (视频/音频)
    unsigned int len;         // 数据长度
    unsigned int width;       // 图像宽度
    unsigned int height;      // 图像高度
    unsigned int time_sec;    // 时间戳 (秒)
    unsigned int time_milli;  // 时间戳 (毫秒)
} MEGA_STREAM_HEADER;
```

**第2层: GROUP_HEADER** (组头部 — 一个 GOP 的元数据)
```c
typedef struct GROUP_HEADER_STRU {
    unsigned int start_code;      // 起始码
    unsigned int frame_num;       // 帧号 (from 0)
    unsigned int time_stamp;      // 时间戳 (1ms 精度)
    unsigned int is_audio;        // 是否音频帧
    unsigned int block_number;    // 当前组内块数量
    IMAGE_SIZE image_size;        // 分辨率
    unsigned int picture_mode;    // 帧模式 (I/P/B)
    unsigned int frame_rate;      // 帧率

    // MPEG4/H.264 扩展信息 (union)
    union {
        struct {
            unsigned int I_quant_value;   // I 帧 quant
            unsigned int P_quant_value;   // P 帧 quant
            unsigned int B_quant_value;   // B 帧 quant
        } mpeg4_quant;

        struct {
            unsigned short time_extension;    // 时间扩展值
            unsigned short reserved[3];       // 保留字段
            unsigned int   stream_crc;        // CRC32 校验
        } H264_extension;
    } mpeg4_or_h264_info;

    unsigned int globalTime;      // 全局绝对时间
} GROUP_HEADER;
```

**第3层: FRAME_HEADER** (帧头部 — 单帧元数据)
```c
typedef struct _FRAME_HEADER_ {
    unsigned short type;          // 帧类型 (I/P/B/AUDIO)
    unsigned short version;       // H.264 版本号
    unsigned int top_size;        // TOP 数据长度
    unsigned int flags;           // H.264: NALU 标志
    char qp;                      // H.264: QP 系数
    char LFIdc;                   // 滤波样式 (0=jm20, 1=jm61e, 7=disable)
    char LFAlphaC0Offset;         // Alpha 滤波参数 (-6, 6)
    char LFBetaOffset;            // Beta 滤波参数 (-6, 6)
    char jpegQuality;             // JPEG 质量 (Motion JPEG)
    unsigned int size;            // 帧数据长度 (不含头部)
} FRAME_HEADER;
```

**帧类型枚举**:
```
I_FRAME_MODE    — I 帧 (Intra, 关键帧)
P_FRAME_MODE    — P 帧 (Predicted, 预测帧)
B_FRAME_MODE    — B 帧 (Bidirectional, 双向预测帧)
BP_FRAME_MODE   — B+P 帧组合
BBP_FRAME_MODE  — BBP 帧组合
AUDIO_I_BLOCK   — 音频 I 块
AUDIO_P_BLOCK   — 音频 P 块
VIDEO_I_BLOCK   — 视频 I 块
VIDEO_P_BLOCK   — 视频 P 块
VIDEO_B_BLOCK   — 视频 B 块
```

#### 3.2.3 码率控制

```
VBR (Variable Bit Rate):
  ┌─────────────────────────────────────────┐
  │  I 帧: 高码率 (复杂帧)                    │
  │  P 帧: 中码率 (预测帧)                    │
  │  B 帧: 低码率 (双向帧)                    │
  │  动态调整 quant 参数                      │
  │  适用: 录像存储 (空间优先)                 │
  └─────────────────────────────────────────┘

CBR (Constant Bit Rate):
  ┌─────────────────────────────────────────┐
  │  固定码率输出                             │
  │  帧质量波动 (复杂场景 quant 增大)          │
  │  适用: 网络传输 (带宽可控)                 │
  └─────────────────────────────────────────┘
```

默认编码参数（不同分辨率）:

| 分辨率 | 默认码率 | 默认帧率 | I帧间隔 | B帧 | 码率模式 |
|--------|---------|---------|---------|-----|---------|
| 4CIF | 4 Mbps | 0(自动) | 100 | 2 | VBR |
| CIF | 1 Mbps | 0(自动) | 25 | 2 | VBR |
| QCIF | 256 Kbps | 0(自动) | 100 | 2 | VBR |
| 720P | 2 Mbps | 25 | 25 | 0 | CBR |
| VGA | 1 Mbps | 25 | 25 | 2 | CBR |

#### 3.2.4 隐私掩码与 ROI

**隐私掩码 (Privacy Mask)**:
- 最多 30 个多边形区域
- 每个区域定义一组顶点坐标
- 编码时将这些区域模糊化/黑化
- 防止敏感区域被录制/传输

**ROI (Region of Interest)**:
- 最多 16 个矩形区域
- 每个区域可设置独立的 QP level
- ROI 区域使用更小的 QP (更高质量)
- 非 ROI 区域使用更大的 QP (节省码率)

### 3.3 音频编码管线

#### 3.3.1 音频参数定义

```c
typedef struct {
    unsigned int encoding_type;  // 编码类型
    unsigned int sample_rate;    // 采样率 (8000Hz)
    unsigned int channels;       // 通道数 (1=单声道, 2=立体声)
    unsigned int bit_rate;       // 码率 (bps)
    unsigned int block_align;    // 块对齐
    unsigned int avg_bytes_sec;  // 平均字节率
} AUDIOPARAMS;
```

#### 3.3.2 音频编码类型与码率

| 编码类型 | 常量 | 码率 | 采样率 | 说明 |
|---------|------|------|-------|------|
| G.711 A-law | AUDIO_G711_A (0x7111) | 64 kbps | 8 kHz | 最常用, 低延迟 |
| G.711 u-law | AUDIO_G711_U (0x7110) | 64 kbps | 8 kHz | 北美/日本 |
| G.722 | AUDIO_G722_16 (0x1011) | 64 kbps | 16 kHz | 宽带音频 |
| G.722 | AUDIO_G722_24 (0x1012) | 48 kbps | 16 kHz | 宽带音频 |
| G.722 | AUDIO_G722_32 (0x1013) | 56 kbps | 16 kHz | 宽带音频 |
| G.722.1 | AUDIO_G722_1 (0x7221) | 32 kbps | 16 kHz | 窄带宽带 |
| AAC | AUDIO_AAC (0x7acc) | 16-128 kbps | 8/16/44.1/48kHz | 高质量 |
| G.726 | AUDIO_G726_32 (0x7260) | 32 kbps | 8 kHz | ADPCM |
| G.726 | AUDIO_G726_16 (0x7262) | 16 kbps | 8 kHz | 超低码率 |
| ADPCM | AUDIO_ADPCM (0x1001) | 32 kbps | 8 kHz | 旧格式 |
| L16 | AUDIO_L16 (0x7001) | 128-384 kbps | 8-48 kHz | 未压缩 PCM |

#### 3.3.3 音频模式

```
单声道 (AUDIO_MONO = 0x1001):
  ─ 大多数对讲/语音场景
  ─ 节省 50% 带宽

立体声 (AUDIO_STEREO = 0x1002):
  ─ 音乐/高品质音频场景
  ─ 需要 DSP 支持双通道编码
```

### 3.4 DSP 共享内存机制

DSP 与 Host ARM CPU 通过共享内存交换数据和控制信息：

```
┌─────────────────────────────────────────────────────────────┐
│                    SHARE_MEM                                 │
│  ┌─────────────────────┐  ┌─────────────────────┐           │
│  │  HOST_TO_DSP_DATA   │  │  DSP_TO_HOST_DATA   │           │
│  │  (Host → DSP 命令)   │  │  (DSP → Host 数据)   │           │
│  │                     │  │                     │           │
│  │ - 编码参数配置       │  │ - 编码帧数据指针     │           │
│  │ - 码率调整           │  │ - 帧头信息           │           │
│  │ - 关键帧请求         │  │ - 时间戳             │           │
│  │ - 启动/停止编码      │  │ - QP 值              │           │
│  │ - ROI/隐私掩码设置   │  │ - 编码状态           │           │
│  └─────────────────────┘  └─────────────────────┘           │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              DSPSHAREDATA                            │    │
│  │  - 全局 DSP 状态                                     │    │
│  │  - 通道配置信息                                      │    │
│  │  - 编码统计信息                                      │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### 3.5 DSP 命令与回调机制

#### 3.5.1 命令下发流程

```
业务模块 (mainCtrl/dsp_interface.c)
    │
    ▼
dsp_command 接口
    │
    ├── 修改编码参数 (码率/帧率/分辨率)
    ├── 请求关键帧 (I-frame)
    ├── 启动/停止编码
    ├── 设置 ROI 区域
    └── 设置隐私掩码
    │
    ▼
通过共享内存 / IPC 写入 HOST_TO_DSP_DATA
    │
    ▼
DSP 硬件读取并执行
```

#### 3.5.2 回调通知流程

```
DSP 硬件编码完成一帧
    │
    ▼
触发回调 (dsp_callback.c)
    │
    ├── 视频编码完成回调
    │     └─→ 通知预览组件 / 存储线程 / RTP 打包
    │
    └── 音频编码完成回调
          └─→ 通知 RTSP 发送 / 对讲模块
```

### 3.6 视频加密与安全

#### 3.6.1 AES 加密

```c
// 加密参数 (codec.h)
typedef struct _SECRET_PARAM_ {
    unsigned int type;        // 加密类型 (HIK_SECRET_NONE / HIK_SECRET_AES)
    unsigned int mode;        // 加密模式 (I/P/B 帧独立控制)
    unsigned int keyLen;      // 密钥长度 (最大 32 字节 = 256 bit)
    unsigned char key[MAX_KEY_LENGTH];  // 128-bit AES 密钥
} SECRET_PARAM;

// 帧级别加密控制
#define HIK_SECRET_I_FRAME     (1<<0)   // I 帧加密
#define HIK_SECRET_P_FRAME     (1<<1)   // P 帧加密
#define HIK_SECRET_B_FRAME     (1<<2)   // B 帧加密
#define HIK_SECRET_AUDIO_FRAME (1<<3)   // 音频帧加密
```

#### 3.6.2 水印与 RSA 签名

```c
// 水印信息 (64 字节)
#define WATERMARK_INFO_LEN 64
typedef struct {
    WATERMARK_VER1 info;            // 水印内容
    unsigned char rsa_checkout[64]; // RSA 签名校验
} WATERMARK_VER1_RSA;

// 系统参数标志
#define HIK_STREAM_CRC     (1<<1)  // GROUP_HEADER CRC 校验
#define HIK_WATERMARK_VER1 (1<<2)  // 水印信息 (版本1, 64字节)
#define HIK_WATERMARK_RSA  (1<<3)  // RSA 512-bit 签名水印
```

#### 3.6.3 SRTP 加密

在网络传输层，RTP 数据包通过 SRTP 加密：

```
编码帧 → NPQ (QoS) → SRTP 加密 → 网络发送
                         │
                    AES-128-ICM
                    密钥: OpenSSL RAND_bytes
                    4 个独立会话:
                      - srtp_send_audio_session
                      - srtp_send_video_session
                      - srtp_recv_audio_session
                      - srtp_recv_video_session
```

---

## 第4章：网络协议栈（多层）

### 4.1 网络协议全景图

音视频数据在网络上经过多层协议封装，从内到外：

```
┌─────────────────────────────────────────────────────────────┐
│  应用层                                                      │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ 业务协议: SDK / RTSP / SIP / ISAPI / 萤石 / WebSocket│    │
│  └─────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│  控制层                                                      │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ RTSP (信令) / SIP (信令) / SDK NETCMD (控制)         │    │
│  └─────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│  传输层                                                      │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ RTP (媒体) / RTCP (控制) / SRTP (加密媒体)           │    │
│  └─────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│  QoS 层 (NPQ)                                                │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ NACK / FEC / Jitter Buffer / Pacing / BW Control    │    │
│  └─────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│  网络层                                                      │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ TCP / UDP / IPv4 / IPv6                              │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 预览通道层 — SDK 二进制协议

#### 4.2.1 协议格式

SDK 协议基于 TCP 8000 端口，采用"长度头 + 命令体"格式：

```
┌──────────────────────────────────────────────────────────────┐
│  IPv4 命令帧 (NETCMD_HEADER)                                  │
├──────────────────────────────────────────────────────────────┤
│  4字节: length    (网络字节序, 包含 length 自身)               │
│  1字节: version   (协议版本)                                  │
│  1字节: ipVer     (1=IPv6, 0=IPv4)                           │
│  1字节: headType  (头部类型)                                  │
│  1字节: reserved  (保留)                                      │
│  4字节: netCmd    (命令码, 网络字节序)                         │
│  4字节: userID    (登录会话ID, 0=未登录)                       │
│  4字节: sequence  (序列号, 请求-响应匹配)                      │
│  4字节: checkSum  (校验和)                                    │
│  ... (randomData, challengeString, clientMac, ...)            │
│  N字节: 命令参数 (按 netCmd 类型变化)                          │
└──────────────────────────────────────────────────────────────┘
```

#### 4.2.2 预览相关命令

| 命令 | 功能 | 方向 |
|------|------|------|
| `NETCMD_LOGIN` | 用户登录 | 客户端→设备 |
| `NETCMD_GET_CAPABILITES` | 获取设备能力 | 客户端→设备 |
| `NETCMD_PREVIEW_START` | 开始预览 | 客户端→设备 |
| `NETCMD_PREVIEW_STOP` | 停止预览 | 客户端→设备 |
| `NETCMD_VOICE_TALK` | 语音对讲开始 | 客户端→设备 |
| `NETCMD_VOICE_TALK_STOP` | 语音对讲停止 | 客户端→设备 |
| `NETCMD_FIND_FILE` | 查找录像文件 | 客户端→设备 |
| `NETCMD_PLAYBACK_START` | 开始回放 | 客户端→设备 |
| `NETCMD_PLAYBACK_STOP` | 停止回放 | 客户端→设备 |

#### 4.2.3 预览模式

```c
// 传输模式枚举
TCPMODE   — TCP 传输 (可靠, 适合局域网)
UDPMODE   — UDP 传输 (低延迟, 可能丢包)
MCASTMODE — 组播传输 (一对多, 需要路由器支持)
RTPMODE   — RTP 标准传输 (跨平台兼容)
```

### 4.3 RTSP 控制层

#### 4.3.1 RTSP Server/Client 双模式

**Server 模式** (设备作为流媒体服务器):
```
端口: 554 (默认)
监听: TCP + UDP
功能: 向客户端推送实时视频流和回放录像
```

**Client 模式** (设备作为 RTSP 客户端):
```
功能: 从其他设备/服务器拉取视频流
用途: 预览拉流、模拟对讲、DS-IP 设备接入
DSP 本地解码支持
```

#### 4.3.2 SDP 协商

RTSP 通过 SDP (Session Description Protocol) 描述媒体信息：

```
RTSP 方法        用途
─────────────────────────────────────────────
OPTIONS         查询服务器支持的方法
DESCRIBE        请求 SDP 描述
SETUP           建立传输通道 (指定 RTP/RTCP 端口)
PLAY            开始播放
PAUSE           暂停播放
TEARDOWN        终止会话
```

SDP 示例:
```
v=0
o=- 0 0 IN IP4 <device_ip>
s=Hikvision Media Server
c=IN IP4 <dest_ip>
t=0 0
m=video <rtp_port> RTP AVP 96
a=rtpmap:96 H264/90000
a=fmtp:96 packetization-mode=1; sprop-parameter-sets=...
a=control:trackID=1
m=audio <rtp_port+2> RTP AVP 0
a=rtpmap:0 PCMU/8000/1
a=control:trackID=2
```

#### 4.3.3 通道与 Track 管理

```c
// Track ID 定义 (generalapi.h)
VIDEO_TRACK_ID     = 1   // 视频 Track
AUDIO_TRACK_ID     = 2   // 音频 Track
METADATA_TRACK_ID  = 3   // ONVIF 元数据 Track
AUDIOBACK_TRACK_ID = 4   // 双向音频 Track
```

```c
// Payload Type 定义 (generalapi.h)
G711U_AUDIO_PT         = 0
G711A_AUDIO_PT         = 8
G722_AUDIO_PT          = 9
MPA_AUDIO_PT           = 14
MJPEG_VIDEO_PT         = 26
STD_H264_VIDEO_PT      = 96
STD_H265_VIDEO_PT      = 99
HIK264_VIDEO_PT        = 96
G726_AUDIO_PT          = 102
AAC_AUDIO_PT           = 103
ONVIF_METADATA_PT      = 107
HIK_PRIVATE_VIDEO_PT   = 112
OPUS_AUDIO_PT          = 115
AAC_LD_AUDIO_PT        = 100
```

### 4.4 RTP/RTCP 传输层

#### 4.4.1 RTP 打包流程

```
DSP 编码帧
    │
    ▼
FRAME_HEADER + 编码数据
    │
    ▼
PS 封装 (MPEG Program Stream)
    │
    ├── GROUP_HEADER 添加
    ├── MEGA_STREAM_HEADER 添加
    └── RTP 头部添加
         │
         ▼
RTP 包格式:
┌────────────────────────────────────┐
│  RTP Header (12 bytes minimum)     │
│  ├── Version (2 bits) = 2           │
│  ├── Padding (1 bit)                │
│  ├── Extension (1 bit)              │
│  ├── CC (4 bits)                    │
│  ├── Marker (1 bit)                 │
│  ├── Payload Type (7 bits)          │
│  ├── Sequence Number (16 bits)      │
│  ├── Timestamp (32 bits)            │
│  ├── SSRC (32 bits)                 │
│  └── CSRC List (0-15 × 32 bits)    │
│  RTP Payload (视频/音频数据)         │
└────────────────────────────────────┘
```

#### 4.4.2 RTCP 控制报告

```
RTCP 包类型:
┌──────────────────────────────────────────────┐
│ SR (Sender Report)      — 发送端报告          │
│ RR (Receiver Report)    — 接收端报告          │
│ SDES (Source Description) — 源描述            │
│ BYE                     — 会话结束            │
│ APP (Application-specific) — 应用特定         │
└──────────────────────────────────────────────┘

RTCP 携带的关键信息:
  - NTP 时间戳 (绝对时间)
  - RTP 时间戳
  - 发送包计数 / 字节计数
  - 丢包率
  - 抖动 (Jitter)
  - RTT (往返时延)
```

#### 4.4.3 SRTP 加密

```
未加密 RTP 包:
  [RTP Header][Payload]
       │
       ▼ SRTP 加密 (srtp_api.c)
       │
加密后 SRTP 包:
  [SRTP Header][Encryption(Payload)][MAC]
       │
  AES-128-ICM 加密算法
  密钥: 16 字节密钥 + 14 字节盐
  4 个独立会话 (发送音频/发送视频/接收音频/接收视频)
```

### 4.5 ONVIF/ISAPI 开放接口层

#### 4.5.1 ONVIF

```
协议: SOAP over HTTP
端口: 80 (HTTP) / 443 (HTTPS)
版本: ONVIF 2.1

核心服务:
  Device Service    — 设备管理 (GetCapabilities, SystemTime, Reboot)
  Media Service     — 媒体管理 (GetProfiles, GetStreamUri)
  Event Service     — 事件订阅 (Subscribe, PullMessage)
  Imaging Service   — 图像参数 (GetVideoSourceMode)
  Recording Service — 录制管理
  Replay Service    — 回放控制
```

#### 4.5.2 ISAPI

```
协议: HTTP + XML/JSON
端口: 80 / 443
URL 路由: /ISAPI/xxx

核心模块:
  /ISAPI/Stream/*          — 视频流管理
  /ISAPI/System/*          — 系统管理
  /ISAPI/Event/*           — 事件管理
  /ISAPI/Security/*        — 安全管理
  /ISAPI/PTZ/*             — PTZ 控制
  /ISAPI/VideoIntercom/*   — 视频对讲
  /ISAPI/AccessControl/*   — 门禁控制
```

### 4.6 SIP 信令层

SIP 用于可视对讲场景，遵循 RFC 3261：

```
呼叫流程:
  呼叫方                          设备
    │  INVITE (SDP 协商)           │
    │─────────────────────────────▶│
    │  180 Ringing                 │
    │◀─────────────────────────────│
    │                              │ 用户接听
    │  200 OK                      │
    │◀─────────────────────────────│
    │  ACK                         │
    │─────────────────────────────▶│
    │                              │
    │  RTP 媒体流 ←────────────→ RTP│
    │                              │
    │  BYE                         │
    │─────────────────────────────▶│
    │  200 OK                      │
    │◀─────────────────────────────│
```

SIP 编码协商:
- 音频: G.711A, G.726, AAC
- 视频: H.264, MJPEG
- 传输: RTP over UDP

### 4.7 云连接层 (萤石 Ezviz)

```
设备 ──(OpenSSL TLS)──▶ 萤石云平台 (test.ys7.com / dev.ezvizlife.com)
                              │
                              ▼
                        互联网
                              │
                              ▼
                        手机 App
```

模块结构:
- `ezviz/base_module/` — 登录、注册、连接管理
- `ezviz/preview_module/` — 实时预览
- `ezviz/playback_module/` — 录像回放
- `ezviz/talk_module/` — 语音对讲
- `ezviz/openssl_module/` — 加密传输

### 4.8 WebSocket 与 Web 推送层

```
浏览器 ──(WebSocket)──▶ 设备:8000/443
                            │
                            ├── ws_preview.c — 实时预览
                            ├── ws_playback.c — 录像回放
                            └── ws_webssh.c — Web SSH 终端
```

基于 libwebsockets 库，最多 6 个并发预览会话。

### 4.9 Ehome/ISUP 上行协议

```
设备 (Ehome Client) ──(TCP 主动连接)──▶ 平台 (Ehome Server)
                                              │
                                        Protocol Buffers
                                              │
                                        视频/报警/对讲上行
```

---

## 第5章：QoS 保障体系 (NPQ)

### 5.1 NPQ 架构总览

NPQ (Network Quality) 是海康自研的 QoS 库，为 RTP 媒体流提供完整的网络质量保障：

```
┌─────────────────────────────────────────────────────────────┐
│                    NPQ 架构                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  API Layer                                           │    │
│  │  NPQ_Create / NPQ_InputData / NPQ_SetParam / ...    │    │
│  └────────────────────┬────────────────────────────────┘    │
│                       │                                      │
│  ┌────────────────────┴────────────────────────────────┐    │
│  │  Role: SENDER / RECEIVER                             │    │
│  └────────────────────┬────────────────────────────────┘    │
│                       │                                      │
│  ┌──────┬──────┬──────────┬──────┬──────┬──────────┐       │
│  │ NACK │ FEC  │ Jitter   │ BW   │ Pacing│ PLI     │       │
│  │      │      │ Buffer   │ Adapt│      │ /FIR    │       │
│  └──────┴──────┴──────────┴──────┴──────┴──────────┘       │
│                       │                                      │
│  ┌────────────────────┴────────────────────────────────┐    │
│  │  Data Flow: RTP In → QOS Processing → RTP Out       │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 NACK 重传机制

#### 5.2.1 NACK 请求/响应流程

```
接收端                        NPQ                         发送端
  │                            │                            │
│ 检测到丢包 (seq gap)          │                            │
│                            │                            │
│  NPQ_InputData(RTCP RR)     │                            │
│                            │  解析丢包信息               │
│                            │  生成 NACK 请求             │
│                            │───────────────────────────▶│
│                            │                            │
│                            │  查找丢失数据包              │
│                            │  重新打包 RTP               │
│                            │───────────────────────────▶│
│                            │                            │
│  收到重传数据               │                            │
│  NPQ_InputData(RTP)         │                            │
│                            │                            │
│  数据补齐, 继续播放          │                            │
```

#### 5.2.2 NACK WiFi 自适应模式

WiFi 环境下网络不稳定，NPQ 提供自适应 NACK 策略：

```c
// NACK WiFi 自适应表
typedef struct _NPQ_NACK_WIFI_TABLE_ {
    char             bEnableNackWifi;        // 使能 NACK WiFi 模式
    unsigned int*    pNackWifiTableRtt;      // RTT 阈值表 (ms)
    unsigned int*    pNackWifiTableCnt;      // 对应重传次数表
    unsigned int     nNackWifiLevelTableLen; // 表长度
    unsigned int     nMaxWifiRttMs;          // 最大 WiFi RTT (ms)
} NPQ_NACK_WIFI_TABLE;

// 默认配置示例:
// RTT:  {10, 20, 40, 80, 150, 250, 350, 500} ms
// 重传: {8,  7,  6,  5,  4,   3,   2,   1}  次
// 含义: RTT=12ms → 重传8次; RTT=500ms → 重传1次
```

### 5.3 FEC 前向纠错

FEC 通过在发送端添加冗余数据，使接收端能够在不请求重传的情况下恢复丢失包：

```
发送端:
  原始数据:  [P1][P2][P3][P4][P5]
  FEC 编码:  [F1] = P1 XOR P2 XOR P3
  
  发送:      [P1][P2][P3][P4][P5][F1]

接收端:
  收到:      [P1][P3][P4][P5][F1]  (P2 丢失)
  恢复:      P2 = F1 XOR P1 XOR P3 XOR P4 XOR P5
```

FEC 参数配置:
```c
// 发送端通知参数
typedef struct _NPQ_SENDER_NOTIFY_PARAM_ {
    bool bHaveFec;                // 是否使能 FEC
    unsigned char nKeyFecFactor;  // 关键帧 FEC 冗余比例
    unsigned char nDeltaFecFactor;// 非关键帧 FEC 冗余比例
    NPQ_SVC_PARAM stSvcParam;     // SVC 参数
} NPQ_SENDER_NOTIFY_PARAM;
```

### 5.4 去抖动 (Jitter Buffer / NETEQ)

#### 5.4.1 视频去抖动

```
接收顺序:  [F1][F3][F2][F5][F4]
                    │
                    ▼  Jitter Buffer
                    │  按时间戳排序
                    ▼
播放顺序:  [F1][F2][F3][F4][F5]
```

NPQ 通过 `NPQ_DATA_RTP_VIDEO` 输入数据，内部维护一个有序缓冲区，
根据时间戳和序列号对乱序到达的 RTP 包进行重排序。

#### 5.4.2 音频去抖动 (NETEQ)

音频对延迟更敏感，NPQ 集成了 Google NETEQ 算法：

```c
// 音频去抖动参数
typedef struct _NPQ_RECEIVER_PARAM_ {
    int  bVaild;
    int  bG7221BigEndian;   // G.722.1 大端模式
    char bSkipErrFrame;     // 丢弃错误帧
    char bNoSupportNETEQ;   // 是否不使用 NETEQ (1=禁用)
    int  iMinBitrate;       // 最小码率
    int  iMaxBitrate;       // 最大码率
} NPQ_RECEIVER_PARAM;
```

### 5.5 带宽自适应

#### 5.5.1 TCC (Transport-Level Congestion Control)

TCC 是发送端拥塞控制算法，基于丢包率反馈调整发送码率：

```
接收端                        发送端
  │                            │
│  RTCP RR (丢包率)             │
│─────────────────────────────▶│
│                            │  解析丢包率
│                            │  计算拥塞程度
│                            │  调整发送码率
│                            │
│  RTCP REMB (可选)           │
│─────────────────────────────▶│
│                            │  使用 REMB 建议码率
```

#### 5.5.2 REMB (Receiver Estimated Maximum Bitrate)

REMB 由接收端估算可用带宽，并通过 RTCP 包通知发送端：

```c
// 拥塞控制类型
typedef enum _NPQ_CC_TYPE_ {
    NPQ_CC_TCC = 0,   // 发送端 TCC
    NPQ_CC_REMB       // 接收端 REMB
} NPQ_CC_TYPE;
```

#### 5.5.3 带宽探测 (Bandwidth Probing)

NPQ 支持主动带宽探测，在空闲期发送探测包测量可用带宽：

```c
// 发送端参数
typedef struct _NPQ_SENDER_PARAM_ {
    char bStopBWProbe;     // 停止带宽探测
    char bOpenPacing;      // 使能 Pacing (BW 关闭时有效)
    char bUseNewCCAlgorithm;     // 使用新算法
    unsigned int unNewCCDetermineMs;   // 拥塞判定时间 (ms)
    unsigned int unNewCCBufferDetectMs; // 缓冲区探测时间 (ms)
} NPQ_SENDER_PARAM;
```

#### 5.5.4 码率分配策略

多路流场景下，NPQ 支持按比例的码率分配：

```c
typedef struct _NPQ_BITRATE_ALLOCATION_STRATEGY_ {
    NPQ_MAIN_TYPE enMainType;         // 媒体类型 (视频/音频/私有)
    float fStreamBitrateRatio;        // 该路流占总码率的比例
    int nMaxQueueLengh;               // 最大队列长度 (ms)
} NPQ_BITRATE_ALLOCATION_STRATEGY;
```

### 5.6 Pacing 流量整形

Pacing 控制数据包的发送节奏，避免突发发送导致网络拥塞：

```
无 Pacing:
  数据包: [P][P][P][P][P][P][P][P]  ← 突发
  网络:   ~~~~~~~~ 拥塞 ~~~~~~~~ 丢包~~~~

有 Pacing:
  数据包: [P]·[P]·[P]·[P]·[P]·[P]·  ← 均匀
  网络:   ~~~~~~~~~~~~~~~~~~~~~~~~~~ 平稳
```

```c
typedef struct _NPQ_PACING_PARAM_ {
    int  nPacingBitrate;                           // Pacing 码率 (bps)
    int  nStreamNum;                               // 流数量
    NPQ_BITRATE_ALLOCATION_STRATEGY* pStream;      // 码率分配
} NPQ_PACING_PARAM;
```

### 5.7 PLI/FIR 关键帧请求

当检测到丢包或网络恢复时，NPQ 可以请求发送端发送关键帧：

```
接收端                        发送端
  │                            │
│  大量丢包 / 网络恢复           │
│                            │
│  NPQ_SetNotifyParam         │
│  (bHaveForceIframe=1)       │
│─────────────────────────────▶│
│                            │  发送 PLI/FIR
│                            │  编码 I 帧
│                            │
│  收到 I 帧, 恢复正常          │
```

### 5.8 音视频同步

NPQ 支持通过 NTP 时间戳实现音视频同步：

```c
// 设置媒体 NTP 时间和时间戳
NPQ_SetMediaNTPTimeAndTimeStamp(
    id,                        // NPQ 实例 ID
    NPQ_MAIN_VEDIO,            // 媒体类型
    nCaptureTime,              // 采集时刻 NTP 时间 (us)
    nTimeStamp                 // RTP 时间戳
);
```

### 5.9 NPQ 状态监控 (NPQ_STAT)

NPQ 提供丰富的状态信息：

```c
typedef struct _NPQ_STAT_ {
    unsigned int nRttUs;              // RTT (us)
    unsigned int nBitRate;            // 当前实际码率 (bps)
    unsigned char cLossFraction;      // 丢包率 (1/256)
    unsigned char nVideoPicQ;         // 视频质量: 0=好, 1=一般, 2=差
    unsigned char nVideoRTQ;          // 视频实时质量
    unsigned char nVideoFluQ;         // 视频流畅质量
    unsigned char nAudioTonQ;         // 音频质量
    unsigned char nAudioRTQ;          // 音频实时质量
    unsigned int nFrameRate;          // 检测统计帧率
    unsigned int nBitRateFec;         // FEC 冗余码率 (bps)
    unsigned int nVideoJitterI;       // 视频输入抖动 (us)
    unsigned int nVideoJitterO;       // 视频输出抖动 (us)
    unsigned int nVideoDelay;         // 视频延迟 (us)
    unsigned int nPacingQueueTimeMs;  // Pacing 队列等待时间 (ms)
    unsigned int nMaxRetransCnt;      // 最大重传次数
    unsigned int nMeanRetransCnt;     // 平均重传次数
} NPQ_STAT;
```

### 5.10 NPQ API 完整使用流程

```c
// 1. 创建 NPQ 实例
int id = NPQ_Create(NPQ_QOS_SENDER);  // 或 NPQ_QOS_RECEIVER

// 2. 设置参数
NPQ_PARAM param;
param.m_type = QOS_TYPE_ALL;          // 启用所有 QoS 功能
param.unDifParam.strSender.bOpenPacing = 1;
param.unDifParam.strSender.bStopBWProbe = 0;
NPQ_SetParam(id, &param);

// 3. 注册回调
NPQ_RegisterDataCallBack(id, my_callback, NULL);

// 4. 启动
NPQ_Start(id);

// 5. 输入数据 (RTP/RTCP)
NPQ_InputData(id, NPQ_DATA_RTP_VIDEO, rtp_packet, packet_len);
NPQ_InputData(id, NPQ_DATA_RTCP_VIDEO, rtcp_packet, rtcp_len);

// 6. 获取状态
NPQ_STAT stat;
NPQ_GetStat(id, NPQ_MAIN_VEDIO, &stat);

// 7. 停止
NPQ_Stop(id);

// 8. 销毁
NPQ_Destroy(id);
```

---

## 第6章：存储系统

### 6.1 storLib 架构总览

存储系统 (`storLib`) 是音视频链路的数据落盘层，负责将 DSP 编码后的音视频数据持久化到各类存储介质。整体架构分为四层：

```
┌─────────────────────────────────────────────────────────┐
│              业务调用层 (Business Layer)                   │
│  stor_manual_start_record / stor_flush_stream / ...     │
├─────────────────────────────────────────────────────────┤
│              数据服务层 (DataService)                     │
│  Record / Schedule / Pic / DataSearch / ANR             │
├─────────────────────────────────────────────────────────┤
│              文件管理层 (FileManage)                      │
│  文件分配 / 分段 / 锁定 / 索引管理                         │
├─────────────────────────────────────────────────────────┤
│              设备管理层 (Device/DeviceManage)             │
│  SATA / USB / SD / NFS / iSCSI / MiniSAS                 │
├─────────────────────────────────────────────────────────┤
│              硬件抽象层 (HAL)                             │
│  blkdev / hd_file_oper / fstype / 文件系统                │
└─────────────────────────────────────────────────────────┘
```

**核心设计原则**：
- **回调驱动**：存储层通过 `STOR_SYS_CALLBACK_FUNC_T` 注册约 20 个回调函数，向业务层索取运行时信息（通道状态、编码类型、录像配置等），实现存储核心与业务逻辑解耦
- **能力检测**：通过 `STOR_SYSTEM_ABILITY_T` 声明设备支持的存储能力（通道数、盘位、循环录像、双录、配额等）
- **消息队列**：每个通道独立的 POSIX mq 消息队列 (`recMsgId`)，生产者（DSP数据流）通过 `RECORD_MSGS` 消息通知存储层写入
- **录像缓冲**：每通道独立 `STOR_AV_BUFFER`（音视频数据缓冲）+ `IFRAME_INFO` 数组（I帧索引），支持断电恢复和异常片段分析

### 6.2 设备管理（Device/DeviceManage）

#### 6.2.1 存储介质类型

```c
typedef enum hd_Type {
    HD_TYPE_ATA     = 0,
    HD_TYPE_SATA    = 1,      // 内置SATA硬盘（NVR）
    HD_TYPE_USB     = 2,      // USB外接存储
    HD_TYPE_SD      = 3,      // TF/SD卡（IPC标配）
    HD_TYPE_NFS     = 4,      // NFS网络存储
    HD_TYPE_ISCSI   = 5,      // iSCSI网络存储
    HD_TYPE_ESATA   = 7,      // 外置eSATA
    HD_TYPE_MINISAS = 8,      // MiniSAS扩展
    HD_TYPE_REPAIR  = 10      // 修复模式
} HD_TYPE;
```

#### 6.2.2 硬盘状态管理

每个硬盘通过 `HDISK_PARAM` 结构维护完整状态：

```c
typedef struct {
    HPR_BOOL   exist;                  // 磁盘是否安装
    HPR_INT8   hdName[PART_NAME_LEN];  // /dev/sda, /dev/mmcblk0p1
    HPR_UINT8  hdType;                 // HD_TYPE_SD/SATA/...
    HPR_UINT32 hdStatus;               // HD_ERROR/HD_SMART_ERR/HD_FULL/...
    HPR_UINT8  fsType;                 // 文件系统类型 (FAT32/EXT4)
    BIG_BIT_PARAM struChans;           // 该磁盘承载的通道位图
    HPR_UINT16 nMaxRecordTasks;        // 最大并发录像任务数（IO能力）
    // S.M.A.R.T 信息
    HPR_INT8   serial[21];             // 序列号
    HPR_INT8   firmware[9];            // 固件版本
    HPR_INT8   model[41];              // 型号
    // 回调接口（不同介质实现不同）
    P_flush_cache_F   flush_cache_callback;
    P_hd_lock_F       hd_lock_callback;
    P_getBlkDevSectors_F getBlkDevSectors_callback;
    P_clear_partitions_F clear_partitions_callback;
    P_pre_init_fs_F   pre_init_fs_callback;
} HDISK_PARAM;
```

**硬盘状态标志** (`HD_ERRNO`)：
- `HD_ERROR` — 硬盘错误
- `HD_SUPPORT_SMART` / `HD_SMART_ERR` — S.M.A.R.T 健康状态
- `HD_FULL` / `HD_ALL_PARTS_FULL` — 磁盘满
- `HD_UNFORMAT_ERR` / `HD_FMT_NOT_SUPPORT` — 未格式化/文件系统不支持
- `HD_NFSDSK_MOUNT_FAILED` — NFS挂载失败
- `HD_UNLOADED` / `HD_NOT_EXIST` — 未卸载/不存在（热插拔）

#### 6.2.3 存储能力声明

设备启动时通过 `STOR_SYSTEM_ABILITY_T` 声明能力：

```c
STOR_SYSTEM_ABILITY_T struAbility = {
    .iEncChanNo       = 1,        // 编码通道数
    .iIpcChanNo       = 0,        // IPC通道数
    .iSataHdNo        = 0,        // SATA盘数
    .iSdCardNo        = 1,        // SD卡数（IPC=1）
    .iEsataHdNo       = 0,        // eSATA盘数
    .iNetHdNo         = 0,        // 网络存储(NFS/iSCSI)数
    .iMiniSasHdNo     = 0,        // MiniSAS盘数
    .bySdFileSysType  = RECORD_FILE_SYSTEM_FAT32,  // SD卡文件系统
    .bSupPubInfoPart  = HPR_TRUE, // 支持公共信息分区
    .bSupPicStore     = HPR_FALSE,// 支持图片存储
    .bSupRecPlan      = HPR_TRUE, // 支持录像计划
    .bEnableQuota     = HPR_TRUE, // 启用配额模式
    .bSupDiskRatioQuota = HPR_TRUE, // 磁盘比例配额
    .bCyclicRecord    = HPR_TRUE, // 循环录像
    .iRecSwitchSecs   = 0,        // 分段间隔(0=不支持动态切换)
    .bHdBalanced      = HPR_FALSE,// 不支持硬盘均衡
    .bSupDualRecord   = HPR_TRUE, // 支持双码流同时录像
    .bSupAnrRecord    = HPR_FALSE,// 不支持ANR断网续录
};
```

**硬盘属性**：
```c
typedef enum _HDProperty {
    PROPERTY_NORMAL     = 0,   // 普通磁盘
    PROPERTY_READONLY   = 1,   // 只读
    PROPERTY_REDUNDANCY = 2,   // 冗余磁盘（双盘备份）
} HD_PROPERTY;
```

#### 6.2.4 热插拔支持

```c
static HPR_BOOL stor_is_support_hotplug(HPR_INT32 hdType)
{
    if (hdType == HD_TYPE_SD || hdType == HD_TYPE_ESATA || hdType == HD_TYPE_MINISAS)
        return HPR_TRUE;
    return HPR_FALSE;
}
```

SD卡、eSATA、MiniSAS 支持热插拔，通过 `stor_notify_disk_status_change` 回调通知 GUI 层磁盘状态变化。

### 6.3 文件管理（FileManage）

#### 6.3.1 文件状态机

```
NORMAL (0) → LOCKED (1) → COMBINED (3) → INVALID (2)
   ↓            ↓              ↓
可写入      锁定保护      片段拼接中
```

**文件标识**：
- `FILE_NORMAL_FLAG` — 正常录像文件，可覆盖
- `FILE_LOCKED_FLAG` — 锁定文件（报警/事件录像），不可覆盖
- `FILE_INVALID_FLAG` — 无效/已删除文件
- `FILE_COMBINED_FLAG` — 片段拼接状态

#### 6.3.2 录像文件结构

每个通道的录像文件由三层索引组织：

```
FILE_IDX_RECORD (文件级)
├── sGuid [32]          // 文件GUID（唯一标识）
├── encoderType         // 编码类型（低4位视频+高4位音频）
├── aSeg[64]            // 片段数组（SEGMENT_IDX_RECORD）
│   ├── startOffset/endOffset   // 文件内偏移
│   ├── startTime/endTime       // 时间范围
│   ├── firstKeyFrame_*         // 首个关键帧信息
│   └── lastFrame_stdTime       // 末帧相对时间
│
SEGMENT_IDX_RECORD (片段级)
├── startOffset/endOffset       // PS流数据偏移
├── infoStartOffset/infoEndOffset // 附加信息偏移
├── startTime/endTime           // 片段时间范围
├── IFRAME_MSG_BODY             // I帧元数据
│   ├── Iframe_abstime          // 绝对时间
│   ├── Iframe_stdtime          // 相对时间 (1/45000s)
│   ├── Iframe_offset           // 文件内偏移
│   └── Iframe_length           // I帧长度
│
EXTRA_MSG_HEADER (附加信息)
├── major_type / minor_type     // 信息类型（报警/移动侦测等）
├── startTime / endTime         // 事件时间范围
└── body[]                      // 事件详情
```

#### 6.3.3 编码类型存储格式

录像片段的 `encoderType` 字段采用 8bit 打包：

```
┌──────┬──────┐
│音频  │视频  │  ← SEGMENT_IDX_RECORD.encoderType
│4bit  │4bit  │
└──────┴──────┘

视频编码 (低4bit):
  0 = H.264 (HIK私有)
  1 = H.264 (标准)
  2 = H.265 (HEVC)
  3 = MPEG4
  4 = MJPEG
  5 = SVAC
  6 = H.264 (原始)

音频编码 (高4bit):
  0 = G.711μ
  1 = AAC
  2 = G.729
  3 = G.722.1_16k
  8 = G.711A
  9 = G.726
```

### 6.4 数据服务层（DataService）

#### 6.4.1 录像服务（Record）

**录像消息队列**：每个通道一个 POSIX mq，消息类型为 `RECORD_MSGS`：

```c
typedef struct recMsg {
    HPR_UINT8 msgId;           // 消息类型
    union {
        struct {               // START_RECORD (0x11)
            HPR_UINT8 recMode;
            HPR_UINT32 minRecType;
            STOR_EVENT_ID struEventId;
        } startRec;
        struct {               // FLUSH_STREAM (0x16)
            HPR_UINT32 idx;           // I帧在buffer中的索引
            struct timeval absTime;   // 绝对时间
            HPR_UINT32 stdTime;       // 相对时间
            HPR_UINT32 len;           // I帧长度
            HPR_UINT16 uFrameType;
        } IFrame;
        struct {               // PIC_FRAME_IN (0x24)
            HPR_UINT32 iPicLen;
            HPR_UINT32 iWriteIdx;
            HPR_UINT32 iTimeStamp;
            PIC_EXT_INFO struPicExtInfo;
        } struPicFrame;
    } msgParam;
} RECORD_MSGS;
```

**消息类型**：
| 值 | 宏 | 含义 |
|---|---|---|
| 0x11 | START_RECORD | 开始录像 |
| 0x12 | STOP_RECORD | 停止录像 |
| 0x13 | STREAM_IN | 数据进入录像缓冲 |
| 0x14 | IFRAME_IN | I帧进入录像缓冲 |
| 0x15 | MODIFY_ADDIT_INFO | 修改附加信息 |
| 0x16 | FLUSH_STREAM | 刷盘 |
| 0x17 | MODIFY_FILE | 修改录像文件片段 |
| 0x24 | PIC_FRAME_IN | 图片帧 |
| 0x26 | STOP_RECORD_V2 | 停止录像V2（补最后一I帧） |
| 0x27 | CLEAN_STREAM | 清理录像缓冲（未启动状态） |

#### 6.4.2 录像通道结构

```c
typedef struct {
    HPR_INT32               channel;            // 内部通道号
    HPR_INT32               iExtChan;           // 外部通道号
    PTHREAD_TID             strurecTaskThread;  // 录像任务线程
    mqd_t                   recMsgId;           // 消息队列ID

    STOR_AV_BUFFER          recBuf;             // 音视频数据缓冲
    IFRAME_INFO             IFrames[MAX_IFRAME_NUMS]; // I帧索引表(200)
    STOR_AV_BUFFER          infoBuf;            // 附加信息缓冲

    HPR_UINT8               currRecType;        // 当前录像类型
    HPR_UINT8               currCompParaType;   // 压缩参数类型
    HPR_UINT8               currMinRecType;     // 外部传入的录像类型

    RECORD_FILE_STATUS      struFileStatus[RECORD_FILES]; // 当前录像文件状态
    RECORD_STAT             recStat[RECORD_FILES];        // 录像统计

    PAL_REC_POOL_T          recPool;            // DSP录像缓冲池
} STOR_RECORDER;
```

#### 6.4.3 计划任务（Schedule）

录像计划结构：

```c
// 每天配置 (8字节)
typedef struct {
    HPR_UINT8 bAllDayRecord;     // 全天录像标志
    HPR_UINT8 recType;          // 录像类型
    HPR_UINT8 compParaType;     // 压缩参数类型
} STOR_RECORDDAY;

// 时间段配置 (4字节)
typedef struct {
    HPR_UINT16 startTime;       // HHMM 打包 (0830 = 0x0830)
    HPR_UINT16 stopTime;        // HHMM 打包
} STOR_TIMESEGMENT;

// 录像计划 (8字节)
typedef struct {
    STOR_TIMESEGMENT recActTime;
    HPR_UINT8 type;            // 录像类型
    HPR_UINT8 compParaType;    // 压缩参数类型
} STOR_RECORDSCHED;

// 完整录像参数 (592字节)
typedef struct {
    HPR_UINT8   enableRecord;           // 是否录像
    HPR_UINT8   enableSchedule;         // 是否支持计划录像
    HPR_UINT8   enableRedundancyRec;    // 冗余录像
    HPR_UINT8   enableAudioRec;         // 录像时是否录音频
    HPR_UINT8   cbSubRec;              // 子码流录像模式(0不录/1主码流/2同时)
    STOR_RECORDDAY recordDay[STOR_MAX_DAYS];  // 7天配置
    STOR_RECORDSCHED recordSched[STOR_MAX_DAYS][STOR_MAX_TIMESEGMENT]; // 每天最多8个时间段
    HPR_UINT32  preRecordTime;          // 预录时间(秒)
    HPR_UINT32  recordDelay;            // 移动侦测/报警录像延迟时间
    HPR_UINT32  recorderDuration;       // 录像文件最长保存时间
} STOR_RECORDPARA;
```

#### 6.4.4 数据配额（Quota）

```c
#define DISK_QUOTA_BY_VOLUME    0x0   // 按磁盘容量
#define DISK_QUOTA_BY_DURATION  0x1   // 按时长
#define DISK_QUOTA_BY_RATIO     0x2   // 按通道比例

typedef struct {
    HPR_UINT8 sGuid[STOR_BTREE_GUID_LEN]; // 通道GUID
    HPR_UINT8 quotaType;          // 配额类型
    HPR_UINT8 byRatio;            // 比例(%)
    HPR_UINT32 iDuration;         // 时长(小时)
    HPR_UINT64 lVolume;           // 容量(MB)
} STOR_CHAN_QUOTA;
```

#### 6.4.5 图片服务（Pic）

图片存储类型：
```c
#define PIC_TYPE_JPEG   0x1001
#define PIC_TYPE_BMP    0x1002
#define PIC_TYPE_PNG    0x1003
```

图片帧结构：
```c
typedef struct {
    HPR_UINT32 iTimestamp;     // 时间戳
    HPR_UINT32 iChannel;       // 通道
    HPR_UINT32 iSuffix;        // 后缀(时间)
    HPR_UINT32 iOffset;        // 文件偏移
    HPR_UINT32 iLen;           // 图片长度
    HPR_UINT8  byPicType;      // 图片格式
    HPR_UINT8  cbPicStat;      // 0=正常 1=锁定 0xff=已删除
} PIC_FRAME_MSG_BODY;
```

图片触发源：
```c
#define PIC_TIMING_REC          0x1a  // 定时抓图
#define PIC_MOTION_DETECT_REC   0x1b  // 移动侦测抓图
#define PIC_ALARM_REC           0x1c  // 报警抓图
#define PIC_VCA_ALARM_REC       0x1d  // 智能分析抓图
#define PIC_FACE_TYPE           0x1e  // 人脸检测抓图
#define PIC_SMD_TYPE            0x1f  // 行为分析抓图
#define PIC_READ_CARD_TYPE      0x20  // 刷卡抓图(可视对讲)
```

#### 6.4.6 数据搜索（DataSearch）

搜索模块通过 `SEARCH_SYS_PARAM_T` 初始化：

```c
SEARCH_SYS_PARAM_T struSearchSysParam = {
    .iVoChans     = (1 << (iMainVoChan - 1)),
    .iChansNum    = struAbility.iEncChanNo + struAbility.iIpcChanNo,
    .iMainVoChan  = iMainVoChan,
    .struSearchCallBack = {
        .getDspAlteredClkRef_callback = getDspAlteredClkRef,  // DSP修正时钟
        .getTotalSecs_callback      = stor_get_total_secs,    // 计算时长
        .getEncoderType_callback    = stor_get_search_encoderType,  // 编码类型查询
    }
};
search_module_init(&struSearchSysParam);
```

附加信息搜索支持的事件类型：
```c
#define VIDEO_IFRAME_INFO   0x1001  // 视频I帧信息
#define ALARM_INFO          0x1002  // 报警信息
#define MOTION_INFO         0x1003  // 移动侦测
#define POS_INFO            0x1005  // POS信息
#define VCA_PLATE_INFO      0x1006  // 车牌识别
#define VCA_FD_INFO         0x1007  // 人脸检测
#define VCA_IVS_INFO        0x1008  // 智能视频分析
#define PIC_FRAME_INFO      0x1009  // 图片帧信息
```

### 6.5 录像规划与执行

#### 6.5.1 回调驱动架构

存储层通过回调函数向业务层索取信息，实现核心与业务解耦：

```
┌──────────────────────────────────────────────────────────────┐
│                    storLib 核心层                              │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐             │
│  │ DeviceMgmt │→│ FileManage │→│ RecordSvc   │             │
│  └────────────┘  └────────────┘  └────────────┘             │
│       ↑                  ↑                ↑                  │
│       │                  │                │                  │
│  ←────┼──── callback ←───┼──── callback ←─┼──── callback ←──┤
│       │                  │                │                  │
└───────┼──────────────────┼────────────────┼──────────────────┘
        │                  │                │
        ▼                  ▼                ▼
┌──────────────────────────────────────────────────────────────┐
│                   stor_layer.c (业务适配层)                    │
│  stor_is_cyclic_record  stor_get_rec_cfg  stor_get_encode_type│
│  stor_capture_I_frame   stor_get_chan_disk_quota             │
│  stor_get_rec_pool      stor_analyze_incomplete_seg          │
├──────────────────────────────────────────────────────────────┤
│                   外部系统 (DSP/Config/DB)                     │
│  DSP RecPool    配置中心      编码模块      TF Manager         │
└──────────────────────────────────────────────────────────────┘
```

**核心回调函数集** (`STOR_SYS_CALLBACK_FUNC_T`)：

| 回调函数 | 用途 | 业务层实现 |
|---|---|---|
| `is_chan_work` | 判断通道是否工作 | `interface_is_chan_work()` |
| `is_cyclic_record` | 是否循环录像 | `pDevCfgParam->recordPara.cyclicRecord` |
| `get_encode_type` | 获取编解码类型 | 从 `DEVICECONFIG.encType` 读取 |
| `get_rec_cfg` | 获取录像计划配置 | `record_plan_get_video_schedule_from_config()` |
| `get_pic_rec_cfg` | 获取图片录像计划 | `record_plan_get_snapshot_schedule_from_config()` |
| `get_chan_disk_quota` | 获取通道磁盘配额 | `tf_get_hard_disk_quota()` |
| `captureIFrame` | 强制I帧 | `dsp_if_insert_iframe_all()` |
| `setEncoderParamEx` | 切换编码参数 | 事件录像时切换参数 |
| `get_rec_pool` | 获取DSP录像缓冲池 | 从 `g_pDspInitPara->RecPoolMain/Sub` |
| `stor_analyze_incomplete_seg` | 异常恢复片段分析 | `stor_analyze_incomplete_seg()` |
| `notify_disk_status_change` | 磁盘状态变化通知 | 通知GUI更新 |

#### 6.5.2 录像类型

```c
#define TIMING_REC                0x0  // 计划定时录像
#define MOTION_DETECT_REC         0x1  // 移动侦测录像
#define ALARM_REC                 0x2  // 报警录像
#define ALARMORMOTION_REC         0x3  // 报警 OR 移动侦测
#define ALARMANDMOTION_REC        0x4  // 报警 AND 移动侦测
#define COMMAND_REC               0x5  // 命令触发录像
#define MANUAL_REC                0x6  // 手动录像
#define SHAKEALARM_REC            0x7  // 震动报警录像
#define ENVIRONMENT_ALARM_REC     0x8  // 环境报警录像
#define VCA_ALARM_REC             0x9  // 智能分析报警
#define EVENT_REC                 0x9  // 事件录像(同VCA)
#define ZONE_ALARM_REC            0xa  // 区域报警
#define EMERGENCY_ALARM_REC       0xb  // 一键紧急报警录像
#define BUSINESS_CONSULTATION_REC 0xc  // 业务咨询录像
#define CALL_INTERCOM_REC         0x10 // 呼叫对讲录像
#define CALL_ANSWER_REC           0x11 // 呼叫接听录像
#define CALL_NOT_ANSWER_REC       0x12 // 呼叫未接听录像
```

#### 6.5.3 录像启动流程

```
业务层调用 stor_manual_start_record(userId, chans, bLocal)
    │
    ├→ 发送 START_RECORD 消息到通道 mq
    │     ├─ recMode = MANUAL_REC
    │     └─ minRecType = 录像类型
    │
    ├→ 检查通道状态 is_chan_work(channel)
    │
    ├→ 获取录像配置 get_rec_cfg(channel, &recPara)
    │     └→ record_plan_get_video_schedule_from_config()
    │
    ├→ 获取编码类型 get_encode_type(channel, bSubStream)
    │     └→ 从 DEVICECONFIG 读取 H.264/H.265/G.711 等
    │
    ├→ 获取DSP录像缓冲池 get_rec_pool(channel, &recPool)
    │     └→ 指向 g_pDspInitPara->RecPoolMain[iChan]
    │
    ├→ stor_component_init(&ability)
    │     ├→ 初始化设备管理(SD/SATA/NFS)
    │     ├→ 初始化文件管理(索引btree)
    │     └→ 启动录像任务线程
    │
    └→ 创建/打开录像文件
          ├→ 分配 FILE_IDX_RECORD
          ├→ 初始化 SEGMENT_IDX_RECORD
          └→ 写入 HIK_MEDIAINFO 头
```

#### 6.5.4 数据写入流程

```
DSP 编码帧 (PS封装)
    │
    ├→ 数据写入 DSP RecPool (共享内存)
    │
    ├→ 通知存储层 STREAM_IN 消息
    │
    ├→ 存储层从 RecPool 读取数据
    │     ├→ 检查 I 帧: check_buffer_iframe()
    │     └→ 记录 I 帧信息到 IFrames[] 数组
    │
    ├→ 写入当前录像文件
    │     ├→ hd_file_write(fd, offset, data, len)
    │     └→ 更新 SEGMENT_IDX_RECORD.endOffset
    │
    ├→ I 帧时触发:
    │     ├→ stor_send_iframe_info()
    │     │     └→ 记录 I 帧绝对时间/相对时间/偏移
    │     ├→ 可选: 强制下一个 I 帧 captureIFrame()
    │     └→ 更新文件索引 btree
    │
    └→ 定时 FLUSH_STREAM
          └→ hd_file_flush() 确保数据落盘
```

### 6.6 录像回放数据流

#### 6.6.1 回放文件定位

```
用户请求回放
    │
    ├→ 根据时间范围 + 通道号
    │   └→ 在文件索引 btree 中查找
    │       ├→ FILE_IDX_RECORD (匹配通道GUID)
    │       └→ SEGMENT_IDX_RECORD (时间范围匹配)
    │
    ├→ 查找首个 I 帧 (回放起点)
    │   └→ stor_get_next_IF_by_pos_in_file_PS()
    │       ├→ 扫描文件数据
    │       ├→ GetNewFrmTime() 检测 I 帧
    │       └→ 返回 I 帧偏移和长度
    │
    └→ 打开文件 hd_file_open()
```

#### 6.6.2 回放数据读取

```
hd_file_seek(fd, iKeyOffset)
    │
    ├→ hd_file_read(fd, offset, buf, len)
    │   └→ 读取 PS 封装的音视频数据
    │
    ├→ 解析 PS 流
    │   ├→ STOR_STREAM_ELEMENT_VIDEO_I_PS (0x01)
    │   ├→ STOR_STREAM_ELEMENT_VIDEO_P_PS (0x02)
    │   └→ STOR_STREAM_ELEMENT_AUDIO_PS   (0x21)
    │
    ├→ 填充 HIK_MEDIAINFO 头
    │   └→ getMediainfo_forPlay()
    │       ├→ video_format = VIDEO_AVC264 / VIDEO_H265
    │       └→ audio_format = PAL_AUDIO_G711_A / G722.1 / AAC
    │
    └→ 通过 RTSP/SDK 推送给客户端
```

#### 6.6.3 异常片段恢复

断电/异常后，未完成的录像片段需要恢复：

```
stor_analyze_incomplete_seg(pPart, iFileNo, pstruSeg, &bUpdate)
    │
    ├→ 打开录像文件
    ├→ 从片段结束偏移开始扫描
    │   └→ 每次扫描 ANALYZE_NO_KEY_FRAME (16MB)
    │
    ├→ stor_get_next_IF_by_pos_in_file_PS()
    │   ├→ 读取数据块
    │   ├→ GetNewFrmTime() 查找 I 帧
    │   └→ 返回 I 帧在文件中的偏移
    │
    ├→ 时间校验:
    │   └→ if (abs(ikeyFrameTime - pstruSeg->endTime) < 180s)
    │       └→ 更新片段结束时间和偏移
    │
    └→ 如果片段过短 (< 256字节)
        └→ 标记 bUpdate = TRUE，删除无效片段
```

### 6.7 视频下载（TF卡文件下载）

#### 6.7.1 TF卡管理器

TF卡通过 `tf_manager` 模块管理，提供独立的配额和文件管理：

```c
// 配额结构
typedef struct {
    STOR_CHAN_QUOTA struRecordQuota;  // 录像配额
    STOR_CHAN_QUOTA struPicQuota;     // 图片配额
    STOR_CHAN_QUOTA struPubInfoFile;  // 公共信息文件配额
} INTER_DISK_QUOTA_CFG;

// 获取配额
tf_get_hard_disk_quota(&quotaCfg, &hdStatus);
```

#### 6.7.2 文件下载流程

```
客户端请求下载 TF卡文件
    │
    ├→ 验证权限 + 通道
    ├→ TF卡状态检查 (是否在线/满/错误)
    │
    ├→ 定位文件 (通过文件GUID/时间/通道)
    │   └→ 在 btree 索引中查找
    │
    ├→ 读取文件数据
    │   ├→ pic_single_get() (图片)
    │   └→ hd_file_read() (录像片段)
    │
    └→ 通过 SDK/HTTP 返回文件数据
```

#### 6.7.3 TF卡异常处理

```
TF卡异常类型:
├── 拔出检测 → stor_notify_disk_status_change(HD_NOT_EXIST)
├── 文件系统错误 → HD_UNFORMAT_ERR / HD_IDX_FILE_ERR
├── 写保护 → 切换为只读模式
└── 空间不足 → HD_ALL_PARTS_FULL → 告警通知

异常恢复:
├── 重新插入 → stor_is_support_hotplug(HD_TYPE_SD) = TRUE
├── 重新挂载 → pre_init_fs_callback
├── 重新分区 → clear_partitions_callback
└── 格式化 → stor_component_init 自动处理
```

---

*以上内容为第6章：存储系统。*

---

## 第7章：业务场景全流程 — 实时预览

### 7.1 SDK 客户端预览全流程

SDK 预览使用海康私有二进制协议，通过 `NETCMD_HEADER` 封装命令。

#### 7.1.1 连接与登录

```
客户端                    设备                         DSP              网络层
  │                         │                           │                  │
  ├─ TCP Connect(:8000) ──→ │                           │                  │
  │                         ├─ 创建监听 socket           │                  │
  │                         ├─ 接受连接                  │                  │
  │                         └─ 创建 NET_SERVER 会话      │                  │
  │                         │                           │                  │
  ├─ NET_LOGIN ───────────→ │──────────────────────────│                  │
  │  NETCMD_HEADER           │                          │                  │
  │  {user, pwd, chanMask}  │                          │                  │
  │                         ├─ 验证用户名密码           │                  │
  │                         ├─ check_capa_support()    │                  │
  │                         ├─ 分配客户端 slot          │                  │
  │                         └─ 返回 LOGIN_RESULT ─────→│                  │
  │                         │                          │                  │
```

#### 7.1.2 预览启动

```
客户端                    设备                         DSP
  │                         │                           │
  ├─ NET_PREVIEW_START ──→ │                           │
  │  NETCMD_HEADER          │                           │
  │  {chanId, streamType,   │                           │
   transportMode}          │                           │
  │                         ├─ 验证通道状态             │
  │                         │   interface_is_chan_work(chanId)
  │                         ├─ 获取编码参数             │
  │                         │   get_encode_type(chanId, bSubStream)
  │                         ├─ 创建预览会话             │
  │                         │   create_preview_session()
  │                         ├─ 分配 RTP socket          │
  │                         │   rtp_socket = socket()
  │                         │   rtcp_socket = socket()
  │                         ├─ 设置传输模式             │
  │                         │   TCP (interleaved) / UDP / Multicast
  │                         ├─ 注册数据回调             │
  │                         │   DSP编码完成后回调推送    │
  │                         ├─ 启动数据推送线程         │
  │                         │   从 DSP RecPool 读取    │
  │                         └─ 返回 START_RESULT ─────→│
  │                         │                           │
```

**传输模式**：
| 值 | 模式 | 说明 |
|---|---|---|
| 0 | TCP | RTSP over TCP (interleaved) |
| 1 | UDP | RTP over UDP |
| 2 | Multicast | RTP over Multicast |
| 3 | TCP Active | 设备主动连接客户端 |

#### 7.1.3 预览数据推送

```
DSP ──编码帧──→ RecPool(共享内存) ──→ 预览推送线程
                                              │
                                              ├→ 读取 PS 封装帧
                                              ├→ 打包 RTP 包
                                              │   ├─ header: {SSRC, seq, timestamp}
                                              │   ├─ payload: PS 数据
                                              │   └─ 加密: SRTP (可选)
                                              ├→ 发送 RTP packet
                                              │   sendto(rtp_socket, ...)
                                              │
                                              ├→ 发送 RTCP SR 报告
                                              │   sendto(rtcp_socket, ...)
                                              │
                                              └→ QoS 处理 (NPQ)
                                                  ├→ 如果启用 NPQ: NPQ_InputData()
                                                  ├→ NACK 请求处理
                                                  ├→ FEC 编码
                                                  └→ Pacing 流量整形
```

#### 7.1.4 预览停止

```
客户端                    设备
  │                         │
  ├─ NET_PREVIEW_STOP ──→ │
  │                         ├─ 停止数据推送线程
  │                         ├─ 关闭 RTP/RTCP socket
  │                         ├─ 释放客户端 slot
  │                         └─ 返回 STOP_RESULT ─────→│
```

### 7.2 RTSP 预览全流程

RTSP 预览基于标准 RTSP 协议，使用 SDP 协商媒体参数。

#### 7.2.1 RTSP 五步交互

```
客户端                    RTSP Server                  DSP
  │                           │                          │
  │ ────── OPTIONS ─────────→ │                          │
  │ ←───── 200 OK ─────────── │                          │
  │   Public: DESCRIBE,       │                          │
  │           SETUP, PLAY     │                          │
  │                           │                          │
  │ ────── DESCRIBE ────────→ │                          │
  │   Accept: application/sdp │                          │
  │                           ├─ 生成 SDP 描述           │
  │                           │   generate_sdp()         │
  │                           │   ├─ track: VIDEO(1)    │
  │                           │   ├─ track: AUDIO(2)    │
  │                           │   ├─ track: METADATA(3) │
  │                           │   └─ track: AUDIOBACK(4)│
  │                           │   ├─ RTP_MAP:           │
  │                           │   │   video: H264 PT=96 │
  │                           │   │   audio: G711A PT=8 │
  │                           │   └─ SSRC 生成          │
  │ ←───── 200 OK + SDP ─────│                          │
  │   v=0                    │                          │
  │   o=- 0 0 IN IP4 x.x.x.x │                          │
  │   s=HikVision RTSP       │                          │
  │   c=IN IP4 x.x.x.x      │                          │
  │   t=0 0                  │                          │
  │   m=video 0 RTP ...96   │                          │
  │   a=rtpmap:96 H264/90000 │                          │
  │   a=control:trackid=1    │                          │
  │   m=audio 0 RTP ...8    │                          │
  │   a=rtpmap:8 PCMA/8000   │                          │
  │   a=control:trackid=2    │                          │
  │                           │                          │
  │ ────── SETUP ──────────→ │                          │
  │   Transport:            │                          │
  │   RTP/AVP;unicast;      │                          │
  │   client_port=8000-8001 │                          │
  │                           ├─ 分配 RTP/RTCP socket   │
  │                           ├─ 保存客户端信息         │
  │                           │   findslot_save_rtspclient()
  │                           │   save_rtspclient_media_info()
  │                           ├─ RTSP_CLIENT_INFO:      │
  │                           │   {rtp_socket, rtcp_socket,
  │                           │    channel_id, stream_id,
  │                           │    ssrc, interleaved}   │
  │                           ├─ 为每个 track SETUP     │
  │                           │   VIDEO_TRACK_ID=1       │
  │                           │   AUDIO_TRACK_ID=2       │
  │                           └─ 返回 SETUP_RESULT ────→│
  │   ←───── 200 OK ─────────│                          │
  │     Transport:           │                          │
  │     RTP/AVP;unicast      │                          │
  │     server_port=9000-9001│                          │
  │     session=abc123       │                          │
  │                           │                          │
  │ ────── PLAY ───────────→ │                          │
  │   Range: 0.000           │                          │
  │                           ├─ 启动数据推送           │
  │                           │   start_rtsp_send()      │
  │                           │   ├→ 从 DSP 读取编码帧 │
  │                           │   ├→ 封装 RTP           │
  │                           │   ├→ 发送 RTP/RTCP     │
  │                           │   └→ NPQ QoS 处理      │
  │                           └─ 返回 PLAY_RESULT ─────│
  │   ←───── 200 OK ─────────│                          │
  │                           │                          │
```

#### 7.2.2 SDP 协商详解

`generate_sdp()` 函数生成完整 SDP 描述：

```sdp
v=0
o=- 0 0 IN IP4 192.168.1.100       # 设备IP
s=HikVision RTSP
c=IN IP4 192.168.1.100             # 媒体目标地址
t=0 0
a=range:npt=0-                     # 支持实时流
m=video 0 RTP/AVP 96              # 视频媒体
a=rtpmap:96 H264/90000            # H.264, 90kHz 时钟
a=control:trackid=1                # 视频 track ID
a=fmtp:96 profile-level-id=4200;  # H.264 参数
         packetization-mode=1
m=audio 0 RTP/AVP 8               # 音频媒体
a=rtpmap:8 PCMA/8000              # G.711A, 8kHz
a=control:trackid=2                # 音频 track ID
a=mediatype:audio                  # 媒体类型标记
```

#### 7.2.3 Track 管理

RTSP Server 支持 4 个 Track：

| Track ID | 类型 | Payload Type | 说明 |
|---|---|---|---|
| 1 | VIDEO | 96 | 主视频流 (H.264/H.265) |
| 2 | AUDIO | 8/9/103 | 音频流 (G.711/G.722/AAC) |
| 3 | METADATA | 107 | ONVIF 元数据 |
| 4 | AUDIOBACK | - | 双向对讲回传 |

#### 7.2.4 TEARDOWN

```
客户端                    RTSP Server
  │                           │
  ├─ TEARDOWN ──────────────→ │
  │                           ├─ 停止所有 track 数据推送
  │                           ├─ 释放 RTP/RTCP socket
  │                           ├─ releaseslot_rtspclient(socket)
  │                           ├─ free_rtspclient_mediainfo()
  │                           └─ 返回 200 OK
```

### 7.3 WebSocket 预览全流程

WebSocket 预览用于 Web 端/APP 端无插件预览。

```
客户端 (Browser)              WebSocket Server              RTSP Server
       │                            │                              │
       │ ─── WS Handshake ────────→ │                              │
       │   GET /ws/stream           │                              │
       │   Upgrade: websocket       │                              │
       │                            ├─ 接受连接                    │
       │   ←── 101 Switching ──────┤                              │
       │                            ├─ 创建 WebSocket 会话         │
       │                            │                              │
       │ ─── WS Message ──────────→ │                              │
       │   {"action":"startPreview" │                              │
       │    ,"channel":1,           │                              │
       │    ,"stream":"main"}       │                              │
       │                            ├─ 调用 RTSP 预览接口          │
       │                            │   create_rtsp_session()      │
       │                            │   save_rtspclient_media_info()
       │                            │                              │
       │                            │ ←── RTP Data ────────────────┤
       │                            │   (从DSP读取编码帧)          │
       │                            │   封装为 WS binary frame     │
       │ ←── WS Binary ─────────────┤   {data: base64, type: "video"}
       │                            │                              │
       │ ─── WS Message ──────────→ │                              │
       │   {"action":"stopPreview"} │                              │
       │                            ├─ 停止 RTSP 会话             │
       │                            ├─ 释放资源                    │
       │                            └─ 返回成功
```

**WebSocket 消息类型**：
```json
// 控制消息
{"action": "startPreview", "channel": 1, "stream": "main"}
{"action": "stopPreview", "channel": 1}
{"action": "captureSnapshot", "channel": 1}
{"action": "ptzControl", "command": "up", "speed": 5}

// 数据消息 (binary)
{
  "type": "video" | "audio" | "snapshot",
  "channel": 1,
  "data": "<base64_encoded_ps_data>",
  "timestamp": 1234567890,
  "frameType": "I" | "P" | "B"
}
```

### 7.4 萤石云预览全流程

萤石云预览通过云连接层转发，设备端作为萤石生态的接入节点。

```
客户端(APP)              萤石云服务器              设备(Ehome)
     │                         │                        │
     │ ─── 预览请求 ──────────→ │                        │
     │                         ├─ 设备在线检测           │
     │                         ├─ 转发预览请求(Ehome) ──→│
     │                         │                        ├─ 创建预览会话
     │                         │                        ├─ 启动RTP推送
     │                         │                        │
     │                         │ ←── RTP 数据 ────────┤
     │                         │   (云侧转发/缓存)      │
     │                         │                        │
     │ ←── RTP 数据 ──────────┤                        │
     │                         │                        │
     │ ─── TEARDOWN ─────────→ │                        │
     │                         ├─ 转发停止命令 ────────→│
     │                         │                        ├─ 停止预览
```

### 7.5 多通道预览

设备支持同时多通道预览：

```
RTSP_CLIENT_INFO slot 表:
┌────────┬──────────┬──────────┬──────────┬──────────┐
│ Slot 0 │ Slot 1   │ Slot 2   │ Slot 3   │ Slot 4   │
│ client#│ client#1 │ client#2 │ client#3 │ client#4 │
│ chan=1 │ chan=2   │ chan=1   │ chan=1   │ chan=1   │
│ main   │ main     │ sub      │ main     │ main     │
│ TCP    │ UDP      │ UDP      │ TCP      │ MCAST    │
└────────┴──────────┴──────────┴──────────┴──────────┘
```

**并发限制**：
- `MAX_RTSP_CLIENT` = 6 (RTSP 并发连接数)
- `MAX_PLAYBACK_CLIENT` = 2 (回放并发连接数)
- SDK 预览: 由 NET_SERVER 最大会话数决定

### 7.6 主/子码流同时预览

```
客户端请求主+子码流预览
    │
    ├→ 创建两个独立 RTSP session
    │   ├→ session 1: channel=1, stream_id=0 (main)
    │   └→ session 2: channel=1, stream_id=1 (sub)
    │
    ├→ 每个 session 独立:
    │   ├→ 独立 RTP socket
    │   ├→ 独立 SSRC
    │   ├→ 独立 track (VIDEO_TRACK_ID=1)
    │   └→ 独立数据推送线程
    │
    └→ 共享同一 DSP 编码通道
        ├→ DSP 同时输出 main + sub 码流
        └→ 两个推送线程从不同 RecPool 读取
            ├→ RecPoolMain → main 码流推送
            └→ RecPoolSub → sub 码流推送
```

### 7.7 预览中的 QoS 保障

预览过程中 NPQ 在多个层面介入：

```
DSP 编码帧
    │
    ▼
┌─────────────────────────────────────────┐
│  NPQ 发送端 (设备侧)                      │
│                                         │
│  1. Pacing 流量整形                      │
│     └→ 控制发送速率，避免突发             │
│                                         │
│  2. FEC 前向纠错                         │
│     ├→ 关键帧: FEC_RATIO = 10%          │
│     └→ 非关键帧: FEC_RATIO = 5%         │
│                                         │
│  3. SRTP 加密 (可选)                     │
│     └→ 对 RTP 数据包加密                 │
│                                         │
│  4. 网络发送                             │
│     └→ sendto(rtp_socket, ...)          │
└─────────────────────────────────────────┘
    │
    ▼ 网络
    │
┌─────────────────────────────────────────┐
│  NPQ 接收端 (客户端侧)                    │
│                                         │
│  1. Jitter Buffer 去抖动                 │
│     └→ 排序 + 延迟缓冲                   │
│                                         │
│  2. NACK 重传                            │
│     ├→ 检测丢失包 (gap in seq)           │
│     ├→ 发送 NACK 请求                    │
│     └→ 等待重传 (超时丢弃)               │
│                                         │
│  3. 带宽自适应                            │
│     ├→ RTCP RR 报告丢包率/延迟           │
│     ├→ TCC/REMB 反馈带宽                 │
│     └→ 调整发送码率                      │
│                                         │
│  4. 解码渲染                              │
│     └→ PS 解封装 → 视频/音频分离         │
└─────────────────────────────────────────┘
```

### 7.8 预览控制（暂停/恢复/TEARDOWN）

#### 7.8.1 暂停/恢复

```
客户端                    RTSP Server
  │                           │
  ├─ PAUSE ──────────────────→ │
  │                           ├─ 停止 RTP 发送 (不关闭 socket)
  │                           ├─ 保留 session 状态
  │                           └─ 返回 200 OK
  │                           │
  ├─ PLAY ───────────────────→ │
  │   Range: npt=0.000-       │ ← 从暂停点恢复 (RTSP标准行为)
  │                           ├→ 继续从 DSP 读取并推送
  │                           └─ 返回 200 OK
```

#### 7.8.2 截图控制

```
客户端                    设备
  │                         │
  ├─ NET_SNAPSHOT ────────→ │
  │  {chanId}               │
  │                         ├→ 从 DSP 获取当前帧
  │                         │   dsp_if_get_current_frame(chanId)
  │                         ├→ JPEG 编码
  │                         └─ 返回 JPEG 数据 ────────→│
```

---

*以上内容为第7章：业务场景全流程 — 实时预览。*

---

## 第8章：业务场景全流程 — 录像存储

### 8.1 计划录像全流程

```
用户通过配置界面设置录像计划
    │
    ├→ 修改配置: STOR_RECORDPARA
    │   ├→ recordDay[7] (7天配置)
    │   ├→ recordSched[7][8] (每天最多8个时间段)
    │   └→ 调用 record_plan_set_video_schedule_to_config()
    │
    ▼
录像计划调度器 (Record Plan Manager)
    │
    ├→ 定时器: 每分钟检查当前时间
    │   ├→ 查找当前天 (dayOfWeek)
    │   ├→ 查找当前时间段 (STOR_TIMESEGMENT)
    │   │   ├→ startTime/stopTime 打包为 HHMM
    │   │   └→ 比较当前时间与时间段边界
    │   └→ 判断是否需要启动/停止录像
    │
    ▼
录像启动 (定时时间段开始)
    │
    ├→ 遍历所有通道
    │   └→ 对每个通道:
    │       ├→ stor_manual_start_record(userId, chanMask, bLocal)
    │       │   │
    │       │   ├→ 1. 检查通道状态
    │       │   │   is_chan_work(channel)
    │       │   │
    │       │   ├→ 2. 获取录像配置
    │       │   │   get_rec_cfg(channel, &recPara)
    │       │   │   └→ record_plan_get_video_schedule_from_config()
    │       │   │
    │       │   ├→ 3. 获取编码类型
    │       │   │   get_encode_type(channel, bSubStream)
    │       │   │   └→ 从 DEVICECONFIG 读取
    │       │   │       video: H.264(0x0)=S264, H.265(0x2)=HEVC
    │       │   │       audio: G.711(0x0)=G711U, G.722(0x3)=G722.1
    │       │   │
    │       │   ├→ 4. 获取DSP录像缓冲池
    │       │   │   get_rec_pool(channel, &recPool)
    │       │   │   └→ 指向 g_pDspInitPara->RecPoolMain[iChan]
    │       │   │
    │       │   ├→ 5. 发送 START_RECORD 消息到通道 mq
    │       │   │   mq_send(recMsgId, START_RECORD, ...)
    │       │   │   ├─ recMode = TIMING_REC (0x0)
    │       │   │   └─ minRecType = TIMING_REC
    │       │   │
    │       │   └→ 6. 录像任务线程收到消息
    │       │       ├→ 创建/打开录像文件
    │       │       │   ├→ 分配 FILE_IDX_RECORD
    │       │       │   │   ├─ sGuid: 通道唯一GUID
    │       │       │   │   └─ encoderType: 编码类型打包
    │       │       │   ├→ 初始化 SEGMENT_IDX_RECORD
    │       │       │   │   ├─ startOffset = 0
    │       │       │   │   ├─ startTime = now
    │       │       │   │   └─ endOffset = 0
    │       │       │   └→ 写入 HIK_MEDIAINFO 文件头
    │       │       │       ├─ fourcc = 0x484B4D49 ("HKMI")
    │       │       │       ├─ system_format = MPEG2_PS
    │       │       │       └─ video/audio format 根据编码类型
    │       │       │
    │       │       └→ 设置 recStarted = TRUE
    │       │
    │       └→ 启动数据写入
    │           └→ 录像任务线程持续从 RecPool 读取数据
    │               ├→ 收到 STREAM_IN 消息 → 写入当前文件
    │               ├→ 收到 IFRAME_IN 消息 → 记录I帧索引
    │               ├→ 收到 FLUSH_STREAM 消息 → hd_file_flush()
    │               └→ 定时刷盘保证数据落盘
    │
    ▼
文件分段 (时间段结束 / 文件大小限制)
    │
    ├→ 时间段结束: stor_send_switch_seg_msg_to_scheduler()
    │   ├→ 关闭当前文件
    │   ├→ 更新 SEGMENT_IDX_RECORD.endOffset/endTime
    │   ├→ 更新 btree 索引
    │   └→ 创建新文件 (fileNo++)
    │
    ├→ 文件大小限制:
    │   └→ 单文件最大 4GB (文件系统限制)
    │
    └→ 循环覆盖 (cyclicRecord = TRUE):
        ├→ stor_hd_check_overflow() 检查磁盘空间
        ├→ 如果磁盘满:
        │   ├→ 查找最早的文件
        │   ├→ 如果文件未锁定 (非报警/事件录像)
        │   │   └→ 删除最早文件，重用空间
        │   └→ 如果所有文件都锁定:
        │       └→ 告警: HD_ALL_PARTS_FULL
        └→ 更新磁盘状态

录像停止 (定时时间段结束)
    │
    ├→ 定时器检测到时间段结束
    ├→ stor_manual_stop_record(userId, chanMask, bLocal)
    │   ├→ 发送 STOP_RECORD_V2 消息到通道 mq
    │   │   └→ 补最后一I帧后停止
    │   ├→ 更新文件索引
    │   ├→ 关闭文件描述符
    │   └→ 设置 recStarted = FALSE
    └→ 完成
```

### 8.2 移动侦测录像全流程

```
移动侦测模块 (DSP/算法)
    │
    ├→ 检测到移动 (macroblock 变化超过阈值)
    │   └→ 发送移动侦测事件
    │       ├→ alarmInChan = motChan
    │       ├─ startTime = now
    │       └─ IPv4/IPv6 地址
    │
    ▼
存储层接收事件
    │
    ├→ stor_input_motion_detect_info(chan, motChan, startTime, endTime, IPv4)
    │   └→ 记录到 infoBuf
    │
    ├→ stor_send_motion_trigger_rec_msg(chans, iAction, motChan)
    │   ├→ iAction = TRUE (开始移动侦测)
    │   └→ 触发录像启动
    │
    ▼
录像启动 (与计划录像类似)
    │
    ├→ currMinRecType = MOTION_DETECT_REC (0x1)
    ├→ 发送 START_RECORD 消息
    │   └─ recMode = MOTION_DETECT_REC
    │
    └→ 录像任务线程创建文件
        └→ 文件中标记 recType = MOTION_DETECT_REC
            附加信息中记录 MOTION_INFO:
            ├─ major_type = MOTION_INFO (0x1003)
            ├─ minor_type = HIK_MOTION_START_INFO (0x1001)
            └─ body: {motChan, startTime, image_size, motion_info[]}
```

**移动侦测停止**：
```
移动侦测停止
    │
    ├→ stor_input_motion_detect_info(chan, motChan, startTime, endTime, IPv4)
    ├→ stor_send_motion_trigger_rec_msg(chans, FALSE, motChan)
    │   └→ iAction = FALSE (移动侦测停止)
    │
    └→ 延迟录像 (recordDelay):
        └→ 如果 recordDelay > 0，继续录像 recordDelay 秒后停止
            发送 STOP_RECORD_V2
```

### 8.3 报警录像全流程

```
报警输入 (IO/网络/智能分析)
    │
    ├→ 报警触发源:
    │   ├─ 外部IO报警 (Alarm In)
    │   ├─ IP报警 (网络报警)
    │   ├─ 智能分析报警 (VCA/IVS)
    │   ├─ 一键紧急报警 (Emergency)
    │   └─ 震动报警 (Shake Alarm)
    │
    ▼
报警事件上报
    │
    ├→ 外部IO: stor_input_alarm_in_Info(chan, alarmInChan, idx, startTime, endTime, IPv4)
    ├→ IP报警: stor_send_ip_alarm_trigger_rec_msg(chans, TRUE, ipChan, alarmInNo)
    ├→ 智能:    stor_send_vca_trigger_rec_msg(chans, iAction, vcaChan, type)
    └→ 紧急:    stor_send_event_trigger_rec_msg(EMERGENCY_ALARM_REC, chans, TRUE, chan)
    │
    ▼
录像启动
    │
    ├→ currMinRecType = ALARM_REC (0x2) / EMERGENCY_ALARM_REC (0xb) / ...
    ├→ 发送 START_RECORD 消息
    │   └─ recMode = ALARM_REC
    │
    └→ 录像文件标记为锁定 (FILE_LOCKED_FLAG)
        └→ 不会被循环覆盖删除
```

**报警停止**：
```
报警停止
    │
    ├→ stor_input_alarm_in_Info(..., endTime, ...)
    ├→ stor_send_alarm_trigger_rec_msg(chans, FALSE, alarmInNo)
    │   └→ bAlarmed = FALSE
    │
    └→ 延迟录像后停止 (recordDelay)
        └→ 文件保持锁定状态 (不被覆盖)
```

### 8.4 录像文件结构

#### 8.4.1 文件命名与路径

```
/ata0a0/record/CH01/2024-01-15/
├── 080000_083000.hik    # 08:00-08:30 录像文件
├── 083000_090000.hik    # 08:30-09:00
├── 090000_093000.hik
└── ...

文件命名规则: HHMMSS_HHHMMSS.hik
- 文件名 = 开始时间_结束时间
- 扩展名: .hik (海康私有格式)
```

#### 8.4.2 文件头结构

```
┌─────────────────────────────────────┐
│ HIK_MEDIAINFO (64 bytes)            │  ← 文件头
│ magic: 0x484B4D49 ("HKMI")          │
│ version: 0x0101                     │
│ device_id: 0                        │
│ system_format: MPEG2_PS             │
│ video_format: AVC264 / H265         │
│ audio_format: G711A / G722.1 / AAC  │
│ audio_channels: 1                   │
│ audio_bits_per_sample: 16           │
│ audio_samplesrate: 8kHz / 16kHz     │
│ audio_bitrate: 64kbps / 16kbps      │
├─────────────────────────────────────┤
│ FILE_IDX_RECORD (文件索引)           │
│ ├─ sGuid [32]                       │  ← 文件唯一GUID
│ ├─ encoderType (1 byte)             │  ← 编解码类型
│ ├─ aSeg[64]                         │  ← 最多64个片段
│ └─ ...                             │
├─────────────────────────────────────┤
│ SEGMENT 0 (片段0)                    │
│ ├─ startOffset: 0                   │
│ ├─ endOffset: 0x100000              │
│ ├─ startTime: 2024-01-15 08:00:00   │
│ ├─ endTime: 2024-01-15 08:15:00     │
│ ├─ firstKeyFrame: offset=0, time=0 │
│ └─ PS流数据: [I帧][P帧][P帧]...    │
├─────────────────────────────────────┤
│ EXTRA_INFO (附加信息)               │
│ ├─ start_code: 0x494E464F ("INFO") │
│ ├─ length: 256                      │
│ ├─ major_type: MOTION_INFO (0x1003)│
│ ├─ minor_type: HIK_MOTION_START    │
│ └─ body: {motChan, startTime, ...} │
├─────────────────────────────────────┤
│ SEGMENT 1 (片段1)                    │
│ ...                                │
└─────────────────────────────────────┘
```

#### 8.4.3 PS 封装格式

```
┌───────────────────────────────────────┐
│ PS Stream Packet                      │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ PES Header (Packet Elementary Stream) │
│ │  start_code: 0x000001xx           │ │
│ │  stream_id:                       │ │
│ │    0x1B = 视频I帧 (STOR_STREAM_ELEMENT_VIDEO_I_PS)
│ │    0x1B = 视频P帧 (STOR_STREAM_ELEMENT_VIDEO_P_PS)
│ │    0x21 = 音频帧 (STOR_STREAM_ELEMENT_AUDIO_PS)
│ │  PES_length                       │ │
│ │  PES_timestamp (DTS/PTS)          │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ DSP FRAME_HEADER                  │ │
│ │  frameLen                         │ │
│ │  frameType: I/P/B                 │ │
│ │  timestamp                        │ │
│ │  channel                          │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ Encoded Data (编码数据)            │ │
│ │  H.264 NALU / H.265 NALU / Audio  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ └───────────────────────────────────┘ │
```

### 8.5 录像回放全流程

```
用户在客户端选择回放
    │
    ├→ 选择参数:
    │   ├─ 通道号: channel
    │   ├─ 开始时间: startTime
    │   ├─ 结束时间: endTime
    │   └─ 录像类型: TIMING_REC / MOTION_DETECT_REC / ...
    │
    ▼
搜索匹配文件
    │
    ├→ 在文件索引 btree 中搜索
    │   ├→ 匹配通道 GUID
    │   ├→ 匹配时间范围
    │   └→ 匹配录像类型
    │
    ├→ 找到目标文件
    │   └→ FILE_IDX_RECORD {sGuid, aSeg[64]}
    │
    ▼
定位首个 I 帧
    │
    ├→ stor_get_next_IF_by_pos_in_file_PS()
    │   ├→ 打开文件: hd_file_open(partName, FILE_TYPE, fileNo, READ)
    │   ├→ 从 startOffset 开始扫描
    │   │   └→ 每次读取 MAX_READ_FILE_LEN (最大读取长度)
    │   ├→ GetNewFrmTime(&frameInfo)
    │   │   ├→ 检测 PS stream_id
    │   │   ├→ 解析 FRAME_HEADER
    │   │   └→ 返回 bIfrm = TRUE/FALSE
    │   └→ 找到首个 I 帧:
    │       ├─ iKeyOffset = I帧在文件中的偏移
    │       ├─ iFrmLen = I帧长度
    │       └─ startTime = I帧时间
    │
    ▼
创建回放会话
    │
    ├→ 打开文件: hd_file_open()
    ├→ 分配回放客户端 slot
    │   └→ MAX_PLAYBACK_CLIENT = 2
    ├→ 填充 HIK_MEDIAINFO 头
    │   └→ getMediainfo_forPlay(buf, video_type, audio_type)
    │       ├→ video_format = VIDEO_AVC264 / VIDEO_H265
    │       └→ audio_format = 根据编码类型
    ├→ 通过 RTSP/SDK 推送给客户端
    │
    ▼
数据读取与推送
    │
    ├→ 读取 PS 流数据
    │   └→ hd_file_read(fd, offset, buf, readLen)
    │       ├→ offset += readLen
    │       └→ 直到 endOffset
    │
    ├→ 解析 PS 流
    │   ├→ 根据 stream_id 分离视频/音频
    │   │   ├─ 0x1B → 视频帧
    │   │   └─ 0x21 → 音频帧
    │   └→ 填充 RTP 包
    │       ├─ header: {SSRC, seq, timestamp}
    │       └─ payload: PS 数据
    │
    ├→ 发送 RTP 数据
    │   └→ sendto(rtp_socket, ...)
    │
    └→ 客户端播放
        └→ 接收 → 去抖动 → 解码 → 渲染
```

### 8.6 录像搜索与定位

#### 8.6.1 时间轴搜索

```
用户在时间轴上拖动选择时间段
    │
    ├→ 搜索条件:
    │   ├─ channel: 1
    │   ├─ startTime: 2024-01-15 06:00:00
    │   ├─ endTime: 2024-01-15 10:00:00
    │   └─ eventTypes: [MOTION, ALARM, ALL]
    │
    ├→ 搜索模块查询
    │   └→ search_module_query()
    │       ├→ 遍历文件索引 btree
    │       ├→ 匹配时间范围
    │       ├→ 匹配事件类型
    │       └→ 返回匹配片段列表
    │
    └→ 返回时间轴标记
        ├→ 08:00-08:30: 计划录像 (蓝色)
        ├→ 08:15-08:20: 移动侦测 (绿色)
        ├→ 09:00-09:05: 报警录像 (红色, 锁定)
        └→ 09:30-10:00: 计划录像 (蓝色)
```

#### 8.6.2 事件搜索

```
搜索特定事件类型的录像
    │
    ├→ 搜索类型:
    │   ├─ VIDEO_IFRAME_INFO (0x1001) → I帧信息
    │   ├─ ALARM_INFO (0x1002) → 报警
    │   ├─ MOTION_INFO (0x1003) → 移动侦测
    │   ├─ VCA_IVS_INFO (0x1008) → 智能分析
    │   ├─ VCA_FD_INFO (0x1007) → 人脸检测
    │   └─ VCA_PLATE_INFO (0x1006) → 车牌识别
    │
    ├→ 搜索范围:
    │   ├─ 通道: 1
    │   ├─ 时间范围: 2024-01-15 ~ 2024-01-16
    │   └─ 事件详情过滤 (如: 人脸检测 → 返回人脸图片)
    │
    └→ 返回匹配结果
        └→ 每个结果包含:
            ├─ 事件时间
            ├─ 文件偏移
            ├─ 片段信息
            └→ 可跳转到对应时间点回放
```

### 8.7 TF卡异常处理

#### 8.7.1 TF卡状态检测

```
TF卡状态机:
┌─────────┐    拔出    ┌──────────┐   重新插入   ┌─────────┐
│  ONLINE  │──────────→│ REMOVING │─────────────→│ INSERTING│
│ (正常)   │←──────────│ (拔出中) │              │ (检测中) │
└────┬─────┘          └──────────┘              └────┬────┘
     │                                               │
     │ 文件系统错误                                   │ 格式化
     │ → ERROR_STATE                                 │ → MOUNTING
     │                                               │
     ▼                                               ▼
┌──────────┐                              ┌──────────────┐
│ ERROR     │ ←── 拔出 ────→ REMOVING     │ MOUNTING     │
│ STATE     │                              │ → ONLINE     │
└──────────┘                              └──────────────┘
```

#### 8.7.2 异常处理策略

```
异常类型                    处理方式
─────────────────────────────────────────────────────────
TF卡拔出                   1. stor_notify_disk_status_change(HD_NOT_EXIST)
                           2. 停止该通道录像
                           3. 告警通知
                           4. 客户端显示"存储异常"

TF卡重新插入               1. stor_is_support_hotplug(HD_TYPE_SD) = TRUE
                           2. stor_get_dev_path() 获取设备节点
                           3. pre_init_fs_callback() 预初始化文件系统
                           4. stor_component_init() 重新初始化存储
                           5. 恢复录像

文件系统错误               1. HD_UNFORMAT_ERR / HD_IDX_FILE_ERR
                           2. 尝试修复: clear_partitions_callback()
                           3. 如果修复失败 → 格式化
                           4. 告警通知

磁盘满                     1. HD_ALL_PARTS_FULL
                           2. 检查循环录像是否启用
                           3. 启用: 覆盖最早的非锁定文件
                           4. 禁用: 告警 + 停止录像

写保护                     1. 切换为只读模式
                           2. 停止写入操作
                           3. 告警通知
```

---

*以上内容为第8章：业务场景全流程 — 录像存储。*

---

## 第9章：业务场景全流程 — 可视对讲（音视频通话）

### 9.1 对讲系统架构

可视对讲系统 (`intercomSystem`) 采用协议无关的会话模型，支持多种对讲协议：

```
┌─────────────────────────────────────────────────────────────┐
│                    业务场景层                                │
│  室内机呼叫 → 门口机响铃 → 手机APP接听                        │
├─────────────────────────────────────────────────────────────┤
│              对讲会话控制层 (talkback_control)                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              TalkbackSession (会话管理)               │   │
│  │  session_id | participants | state | recording       │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              TalkbackRules (规则引擎)                 │   │
│  │  号码转换 | 优先级 | 呼叫路由 | 并发控制               │   │
│  └─────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│              协议适配层 (Protocol Adapters)                   │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐      │
│  │ SIP/ISUP │ │ HikCloud │ │ Ezviz    │ │ NetSDK   │      │
│  │ (IP对讲) │ │ (萤石云) │ │ (萤石生态)│ │ (客户端) │      │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘      │
├─────────────────────────────────────────────────────────────┤
│              媒体处理层                                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                    │
│  │ 音频编码  │ │ RTP发送  │ │ RTP接收  │                    │
│  │G.711/AAC │ │/RTCP     │ │/去抖动   │                    │
│  └──────────┘ └──────────┘ └──────────┘                    │
├─────────────────────────────────────────────────────────────┤
│              DSP/硬件层                                      │
│  麦克风采集 → ADC → DSP编码 → 网络发送                        │
│  网络接收 → DSP解码 → DAC → 扬声器播放                       │
└─────────────────────────────────────────────────────────────┘
```

**协议适配层**：
| 协议 | 文件 | 用途 |
|---|---|---|
| SIP/ISUP | `talkback_sip.cpp` / `talkback_ISUP.cpp` | IP网络对讲（SIP信令） |
| HikCloud | `talkback_hik_cloud.cpp` | 海康云平台对讲 |
| Ezviz | `talkback_ezviz.cpp` | 萤石云生态对讲 |
| NetSDK | `talkback_net_sdk.cpp` | SDK私有协议对讲 |
| Private Analog | `talkback_private_analog.cpp` | 模拟/RS485对讲 |

### 9.2 SIP 信令交互流程

#### 9.2.1 呼叫建立（室内机 → 门口机 → 手机）

```
室内机APP              设备(SIP Server)         门口机              手机APP
    │                        │                      │                   │
    │   INVITE sip:door@dev  │                      │                   │
    │   → From: indoor@app   │                      │                   │
    │   → To: door@device    │                      │                   │
    │   → SDP:               │                      │                   │
    │     m=audio 12345 RTP  │                      │                   │
    │     a=rtcp:12346 IN IP4│                      │                   │
    │                        │                      │                   │
    │                        ├─ SIP注册/查找用户     │                   │
    │                        │   门口机SIP URI解析   │                   │
    │                        ├─ 创建对讲会话         │                   │
    │                        │   TalkbackSession::create()              │
    │                        │   ├─ session_id = generate_id()         │
    │                        │   ├─ participants = [indoor, door]      │
    │                        │   └─ state = CALLING                    │
    │                        ├─ 分配音频资源     │                   │
    │                        │   ├→ 麦克风通道开启   │                   │
    │                        │   ├→ DSP音频编码配置  │                   │
    │                        │   └→ RTP socket分配   │                   │
    │                        │                      │                   │
    │                        ├─ 转发INVITE → 门口机  │                   │
    │                        │   INVITE sip:door@dev│                   │
    │                        ├─ 门口机响铃           │                   │
    │                        │   播放振铃音频         │                   │
    │                        │                      │                   │
    │   ←─ 180 Ringing ──────│                      │                   │
    │                        │                      ├─ 门口机响铃        │
    │                        │                      │   显示来电画面      │
    │                        │                      │                   │
    │                        │                      │ INVITE接受         │
    │                        │                      │ ←─ 180 Ringing ───│
    │                        │                      │   用户点击接听      │
    │                        │                      │                   │
    │                        │                      │ 200 OK            │
    │                        │   ←─ 200 OK ─────────│                   │
    │                        │   ACK                 │                   │
    │                        │                      │                   │
    │                        │   ←─ 200 OK ──────────│                   │
    │   ACK                  │                      │                   │
    │   →                    │                      │                   │
    │                        ├─ 媒体通道建立          │                   │
    │                        │   配置RTP路径:         │                   │
    │                        │   indoor ↔ device ↔ door ↔ mobile        │
    │                        │                      │                   │
    │ ←── RTP Audio ─────────│←── RTP Audio ────────│                   │
    │ ←── RTP Audio ───────────────────────────────→│                   │
    │                        │                      │                   │
    │   QoS监控:             │                      │                   │
    │   RTCP SR/RR           │                      │                   │
    │   NPQ_STAT 上报        │                      │                   │
```

#### 9.2.2 SDP 媒体协商

```
INVITE 中的 SDP:
  v=0
  o=indoor_app 1234567 1 IN IP4 192.168.1.100
  s=Intercom Call
  c=IN IP4 192.168.1.100
  t=0 0
  m=audio 12345 RTP/AVP 0 8 96   # 支持 G.711U(0), G.711A(8), 私有(96)
  a=rtpmap:0 PCMU/8000
  a=rtpmap:8 PCMA/8000
  a=rtcp:12346 IN IP4 192.168.1.100
  a=sendrecv                        # 双向音频
  a=mid:0

200 OK 中的 SDP (协商结果):
  m=audio 23456 RTP/AVP 8   # 选择 G.711A
  a=rtpmap:8 PCMA/8000
  a=rtcp:23457 IN IP4 192.168.1.101  # 设备RTP端口
```

### 9.3 媒体流建立

#### 9.3.1 音频编码切换

对讲过程中可能根据网络状况切换音频编码：

```
初始协商: G.711A (8kHz, 64kbps)
    │
    ├→ 网络质量好 → 保持 G.711A
    │
    ├→ 网络质量下降 → 尝试 G.726 (32kbps)
    │   ├→ re-INVITE 携带新 SDP
    │   │   m=audio 23456 RTP/AVP 102  # G.726 PT=102
    │   │   a=rtpmap:102 G726-32/8000
    │   └→ 对端确认
    │
    └→ 网络质量很差 → AAC (16kbps)
        └→ 同样通过 re-INVITE 协商

编码切换流程:
  1. 检测到 QoS 下降 (RTCP RR 报告高丢包率)
  2. TalkbackSession 触发编码切换
  3. 发送 re-INVITE 携带新 SDP
  4. 对端确认后切换 DSP 编码参数
  5. 新 RTP 包使用新 payload type
```

#### 9.3.2 RTP 音频打包

```
DSP 编码音频帧 (G.711A, 20ms, 160 bytes)
    │
    ├→ 封装 RTP 头:
    │   ├─ version: 2
    │   ├─ PT: 8 (G.711A)
    │   ├─ seq: 递增
    │   ├─ timestamp: 递增 (8000Hz × 20ms = 160)
    │   ├─ SSRC: 会话唯一标识
    │   └─ payload: 160 bytes G.711A 数据
    │
    ├→ SRTP 加密 (如果启用):
    │   ├─ 计算 MAC
    │   ├─ 加密 payload
    │   └─ 添加 salt
    │
    └→ 发送: sendto(rtp_socket, rtp_packet, len)
```

### 9.4 对讲中的 QoS 保障

```
对讲音频流
    │
    ▼
┌──────────────────────────────────────────────┐
│ 发送端 (设备侧)                                │
│                                              │
│ 1. 音频采集                                   │
│    └→ DSP 麦克风采集 → G.711A 编码            │
│                                              │
│ 2. NPQ 发送处理                               │
│    ├→ FEC: 音频 FEC_RATIO = 15% (高优先级)    │
│    ├→ NACK 启用: 音频重传优先级高               │
│    └→ Pacing: 恒定 64kbps (G.711A)            │
│                                              │
│ 3. 网络发送                                   │
│    └→ RTP → SRTP → UDP                        │
└──────────────────────────────────────────────┘
    │
    ▼ 网络
    │
┌──────────────────────────────────────────────┐
│ 接收端 (对端)                                  │
│                                              │
│ 1. RTP 接收                                   │
│    └→ 排序 + 去抖动 (Jitter Buffer)           │
│                                              │
│ 2. NACK 处理                                  │
│    ├→ 检测 seq gap                            │
│    ├→ 发送 NACK Request                       │
│    └→ 等待重传 (超时丢弃)                      │
│                                              │
│ 3. 解码播放                                   │
│    ├→ RTP 解包 → G.711A 解码                 │
│    ├→ 音频输出 → DSP → DAC → 扬声器           │
│    └→ 音频同步: 与视频保持 AV Sync             │
└──────────────────────────────────────────────┘
```

### 9.5 对讲会话管理

#### 9.5.1 会话状态机

```
┌──────────┐
│ IDLE     │ ← 会话空闲
└────┬─────┘
     │ INVITE 发起
     ▼
┌──────────┐    超时/拒绝    ┌──────────┐
│ CALLING  │───────────────→│ ERROR    │
│ 呼叫中    │                │ 错误      │
└────┬─────┘                └──────────┘
     │ 对方响应 200 OK
     ▼
┌──────────┐    媒体建立失败  ┌──────────┐
│ CONNECTING│───────────────→│ ERROR    │
│ 连接中     │                │           │
└────┬─────┘                └──────────┘
     │ RTP 通道建立成功
     ▼
┌──────────┐    BYE/挂断    ┌──────────┐
│ ACTIVE   │───────────────→│ IDLE     │
│ 通话中    │                │           │
└────┬─────┘                └──────────┘
     │ 超时自动挂断
     ▼
┌──────────┐
│ TIMEOUT  │ → ERROR → IDLE
└──────────┘
```

#### 9.5.2 会话数据结构

```cpp
TalkbackSession {
    session_id          // 会话唯一ID
    state               // IDLE/CALLING/CONNECTING/ACTIVE/TIMEOUT
    participants[]      // 参与者列表
    audio_codec         // G.711A/G.726/AAC
    rtp_socket_tx       // RTP发送socket
    rtp_socket_rx       // RTP接收socket
    ssrc                // RTP SSRC
    recording           // 是否录音
    timeout_timer       // 超时定时器
    qos_stat            // NPQ_STAT
}
```

### 9.6 对讲中断与恢复

```
对讲中断场景:
┌─────────────────────────────────────────────────────────┐
│ 场景           │ 检测方式          │ 恢复策略            │
├─────────────────────────────────────────────────────────┤
│ 网络断开       │ RTCP RR 无响应    │ 重连 + 重新INVITE   │
│ WiFi信号弱     │ NPQ_STAT 丢包率高 │ 降码率 + FEC增强     │
│ 来电打断       │ 新INVITE到达      │ 当前会话 HOLD        │
│ 磁盘满         │ HD_ALL_PARTS_FULL│ 停止录音 + 告警       │
│ DSP异常        │ 音频采集超时      │ 重启DSP音频通道        │
└─────────────────────────────────────────────────────────┘
```

### 9.7 室内机-门口机-手机 三方通话

```
室内机APP    设备(SIP Server)    门口机    手机APP
    │              │              │         │
    │  INVITE      │              │         │
    │  → chan1     │              │         │
    │              ├─ 创建会话     │         │
    │              │   session[0] = indoor↔door
    │              │              │         │
    │ ←─ RTP ──────┤              │         │
    │              ├─ RTP ───────→│         │
    │              │              │←── 接听  │
    │              │              │         │
    │  INVITE      │              │         │
    │  → add chan2 │              │         │
    │              ├─ 添加参与者   │         │
    │              │   session[0].participants += mobile
    │              │              │         │
    │              ├─ 媒体混音/转发│         │
    │              │   indoor ↔ door ↔ mobile
    │              │              │         │
    │ ←─ RTP ──────┤←── RTP ─────┤←── RTP ─┤
    │ ←─ RTP ──────────────────────┤         │
    │ ←─ RTP ──────────────────────────┤     │
    │                                       │
    │  三方通话建立完成                       │
    │  所有参与者可互相通话                   │
```

**三方通话媒体路由**：
```
设备作为媒体混合/转发中心:
  indoor  RTP ──→ [设备] ──→ door RTP
                    │
                    ├→ 音频混合 (可选)
                    │
                    └──→ mobile RTP

或作为媒体透传:
  indoor  RTP ──→ [设备SIP Proxy] ──→ door RTP
  door    RTP ──→ [设备SIP Proxy] ──→ indoor RTP
  door    RTP ──→ [设备SIP Proxy] ──→ mobile RTP
  mobile  RTP ──→ [设备SIP Proxy] ──→ door RTP
```

### 9.8 对讲录音与存储

```
对讲开始
    │
    ├→ TalkbackSession::startRecording()
    │   ├→ 创建录音文件
    │   │   ├─ 文件名: CALL_RECORD_YYYYMMDD_HHMMSS.wav
    │   │   └─ 路径: /record/call_record/
    │   ├→ 启动录音任务
    │   │   ├→ 从 RTP 接收缓冲区读取音频
    │   │   ├→ 解码 → PCM
    │   │   └→ 封装 WAV 文件
    │   └→ currMinRecType = CALL_INTERCOM_REC (0x10)
    │
    ├→ 录音过程中:
    │   ├→ 持续写入录音文件
    │   ├→ 文件锁定 (FILE_LOCKED_FLAG)
    │   └→ 录音数据也写入录像索引
    │       └→ EXTRA_MSG_INFO: CALL_RECORD_INFO
    │
    └→ 对讲结束
        ├→ TalkbackSession::stopRecording()
        ├→ 关闭录音文件
        ├→ 更新文件索引
        └→ 录音文件可回放/下载
```

**录音类型**：
```c
#define CALL_INTERCOM_REC     0x10  // 呼叫对讲录音
#define CALL_ANSWER_REC       0x11  // 呼叫接听录音
#define CALL_NOT_ANSWER_REC   0x12  // 呼叫未接听录音
```

---

## 第10章：业务场景全流程 — 语音对讲（单向）

### 10.1 SDK 语音对讲

SDK 语音对讲使用私有二进制协议，通过 `NETCMD_VOICE_TALK` 命令实现。

#### 10.1.1 对讲启动流程

```
客户端                    设备                         DSP
  │                         │                           │
  ├─ NET_VOICE_TALK_START─→│                           │
  │  NETCMD_HEADER          │                           │
  │  {mode: VOICE_TALK,     │                           │
   audioType, buffer}       │                           │
  │                         ├─ 验证对讲权限             │
  │                         ├─ 分配对讲通道             │
  │                         ├─ 配置音频编码             │
  │                         │   audioType = G.711/G.722/AAC
  │                         ├─ 创建音频接收缓冲区        │
  │                         ├─ 启动音频解码线程         │
  │                         │   从缓冲区读取 → 解码 → DSP播放
  │                         └─ 返回 START_RESULT ─────→│
  │                         │                           │
  ├─ 持续发送音频包 ───────→│                           │
  │  {seq, timestamp,       │                           │
   audio_data[160]}         │                           │
  │                         ├→ 写入对讲缓冲区           │
  │                         └→ 通知解码线程             │
  │                         │                           │
  │                         ├─ 解码音频                 │
  │                         │   G.711 → PCM             │
  │                         ├─ 送入 DSP 音频输出        │
  │                         │   DSP_voice_talk_play()   │
  │                         └─ 通过扬声器播放           │
  │                         │                           │
  ├─ NET_VOICE_TALK_STOP ──→│                           │
  │                         ├─ 停止解码线程             │
  │                         ├─ 释放缓冲区               │
  │                         └─ 返回 STOP_RESULT ───────→│
```

#### 10.1.2 音频编码支持

```c
typedef enum {
    AUDIO_TYPE_G711A = 0,   // G.711A, 64kbps
    AUDIO_TYPE_G711U = 1,   // G.711μ, 64kbps
    AUDIO_TYPE_G722 = 2,    // G.722 (宽频), 48/56/64kbps
    AUDIO_TYPE_AAC   = 3,   // AAC, 16-48kbps
    AUDIO_TYPE_G726  = 4,   // G.726, 16/24/32/40kbps
} AUDIO_ENCODE_TYPE;
```

### 10.2 RTSP 语音对讲

RTSP 扩展了 AUDIOBACK Track 支持双向对讲回传。

```
CLIENT ── RTSP SETUP ──→ SERVER
                    a=control:trackid=4  ← AUDIOBACK Track

CLIENT ── RTSP PLAY ──→ SERVER
    │
    ├→ 发送端: trackid=4 的 RTP 流 (麦克风采集)
    │   m=audio <port> RTP/AVP <PT>
    │   a=control:trackid=4
    │   a=sendrecv
    │
    └→ 接收端: 从 trackid=2 (AUDIO) 接收设备音频
        m=audio <server_port> RTP/AVP 8
        a=rtpmap:8 PCMA/8000
        a=control:trackid=2
```

### 10.3 广播系统

#### 10.3.1 实时广播

```
广播源 (麦克风/音频文件)          设备                  客户端
       │                          │                        │
       ├─ 音频采集/读取            │                        │
       ├─ DSP 编码 (G.711/AAC)    │                        │
       │                          ├─ 组播/单播推送          │
       │                          │   多客户端同时接收       │
       │                          ├→ RTP 组播 (:5004)      │
       │                          └→ RTCP 组播 (:5005)     │
       │                          │                        │
       │                          │ ←── JOIN MCAST ────────┤
       │                          │                        ├→ RTP
       │                          │                        ├→ RTP
       │                          │                        └→ RTP
```

#### 10.3.2 定时广播

```
用户配置定时广播:
  ├─ 广播时间: 每天 08:00, 12:00, 18:00
  ├─ 广播内容: /audio/promotion.wav
  ├─ 广播通道: CH1-CH4 (全部)
  └─ 广播音量: 70%

调度器执行:
  08:00 → 读取音频文件 → DSP编码 → 推送至 CH1-CH4
  12:00 → 读取音频文件 → DSP编码 → 推送至 CH1-CH4
  18:00 → 读取音频文件 → DSP编码 → 推送至 CH1-CH4
```

#### 10.3.3 RTP 广播寻呼

```
外部系统 ── RTP/UDP ──→ 设备 (:5004)
    │
    ├→ 接收 RTP 音频流
    ├→ 解析 PS 封装
    ├→ 解码音频
    └→ 通过设备扬声器播放
        └→ 实现远程广播寻呼功能
```

### 10.4 报警语音

```
报警触发
    │
    ├→ 报警类型:
    │   ├─ 入侵报警 → 播放 "您已进入监控区域"
    │   ├─ 火灾报警 → 播放 "火灾警报，请迅速撤离"
    │   └─ 自定义 → 播放预录语音
    │
    ├→ 从 Flash 读取语音文件
    │   └→ /audio/alarm/*.wav
    │
    ├→ DSP 编码 (G.711)
    ├→ 通过扬声器播放
    └→ 同时可通过 RTP 推送给客户端
        └→ 客户端播放报警语音提示
```

---

## 第11章：数据流全景图

### 11.1 视频数据流（传感器 → DSP → 网络/存储）

#### 11.1.1 总览

```
传感器 (Sensor)
  │
  ├→ ISP (Image Signal Processor)
  │   ├─ hwifdef.h / isp_sensor_interface.c
  │   ├─ 图像增强、白平衡、曝光控制
  │   └→ 原始 RAW → YUV/RGB
  │
  ├→ DSP 编码 (Davinci)
  │   ├─ GOM + VEDN (硬件编解码引擎)
  │   ├─ H.264 / H.265 / MPEG4 / MJPEG
  │   ├─ 编码参数: STREAMPARAMS / ENC_TYPE_PARAM
  │   └→ 编码帧 → STREAM_ELEMENT 回调
  │       │
  │       ├→ dsp_callback_fr_result()     (人脸识别/IQA/1vN)
  │       ├→ dsp_callback_jpeg_img_result() (JPEG 抓拍)
  │       ├→ dsp_callback_md_result()     (移动侦测)
  │       ├→ dsp_callback_qrcode_result() (二维码识别)
  │       └→ dsp_callback_enc_data()      (编码视频流)
  │           │
  │           ├→ 预览分发 (Preview Component)
  │           │   ├→ NETBUF_INFO 共享内存
  │           │   ├→ SDK 协议 (TCP/UDP)
  │           │   ├→ RTSP/RTP (UDP/TCP)
  │           │   ├→ WebSocket
  │           │   ├→ 萤石云 (Ezviz)
  │           │   └→ Ehome/ISUP
  │           │
  │           └→ 录像存储 (Storage)
  │               ├→ stor_manual_start_record()
  │               ├→ RECORD_MSGS (START_RECORD/FLUSH_STREAM/IFRAME)
  │               ├→ storLib 写入 PS 文件
  │               └→ SATA / SD Card
  │
  └→ 事件关联
      ├→ 移动侦测 → 抓拍 + 事件上传
      ├→ 人脸识别 → 抓拍 + 告警上传
      └→ 二维码识别 → 开门/告警
```

#### 11.1.2 编码帧分发机制

DSP 编码完成后，通过 `STREAM_ELEMENT` 回调将数据推送至 `dsp_callback.c`。编码帧通过 `STREAM_ELEMENT_FR_ENC` 类型标识，由 `dsp_callback_enc_data()` 接收：

```
STREAM_ELEMENT 结构体
  ├─ type: STREAM_ELEMENT_FR_ENC (编码视频帧)
  │        STREAM_ELEMENT_FR_DEC (解码音频帧)
  │        STREAM_ELEMENT_FR_FFD_IQA (人脸识别/IQA)
  │        STREAM_ELEMENT_FR_CP (1vN 比对)
  │        STREAM_ELEMENT_FR_BM (人脸模板)
  │        STREAM_ELEMENT_FR_1VN_SIM (1vN 相似度)
  │        STREAM_ELEMENT_JPEG_IMG (JPEG 抓拍)
  │        STREAM_ELEMENT_FR_BM (人脸模板)
  │        STREAM_ELEMENT_FR_MD (移动侦测)
  │        STREAM_ELEMENT_QR_CODE (二维码)
  ├─ chan: 通道号 (0/1 = 采集/回放)
  ├─ dataLen: 数据长度
  └─ id: 子类型标识

编码帧分发路径:
  DSP 编码
    │
    ├→ g_preview_link_list (预览连接列表)
    │   ├→ 通过 NETBUF_INFO 共享内存获取编码数据
    │   │   │
    │   │   │ p_get_preview_netbuf_fun → dsp_if_netbuf_info()
    │   │   │
    │   │   ├→ SDK 预览 (visNet)
    │   │   ├→ RTSP 预览 (rtspApp)
    │   │   ├→ WebSocket 预览
    │   │   ├→ 萤石云预览 (ezviz)
    │   │   └→ Ehome 预览
    │   │
    │   └→ 每个连接独立读取 NETBUF_INFO
    │       ├─ data_buf_addr: 编码数据地址
    │       ├─ data_buf_widx_addr: 写索引
    │       ├─ data_buf_totallen: 总长度
    │       └→ 各协议层自行打包发送
    │
    └→ g_recording_channel (录像通道位图)
        ├→ stor_send_rec_msg(START_RECORD)
        ├→ 编码帧 → RECORD_MSGS (FLUSH_STREAM)
        │   ├─ start_stream: 流起始位置
        │   ├─ end_stream: 流结束位置
        │   ├─ is_iframe: 是否关键帧
        │   └→ storLib 写入文件
        └→ IFRAME 事件
            ├→ 记录 I 帧索引
            ├→ 用于回放定位
            └→ IFRAME_INFO[200] 每通道
```

**关键 API**:
- `dsp_if_netbuf_info()` — 从 DSP 获取编码数据缓冲区信息
- `dsp_if_insert_iframe()` — 强制插入 I 帧
- `dsp_if_get_iframe_idx()` — 获取当前 I 帧索引
- `preview_component` — 预览分发组件，管理所有预览连接

#### 11.1.3 事件帧处理

```
DSP 事件回调
  │
  ├→ dsp_callback_fr_result()
  │   ├─ STREAM_ELEMENT_FR_FFD_IQA → face_component_dsp_data_callback()
  │   ├─ STREAM_ELEMENT_FR_DEC → 人脸识别解码
  │   ├─ STREAM_ELEMENT_FR_CP → 1vN 比对
  │   └→ do_key_backlight_on() → 按键背光 + UI 通知
  │
  ├→ dsp_callback_jpeg_img_result()
  │   ├─ PIC_SNAP_TYPE_OPEN_DOOR → 开门抓拍
  │   ├─ PIC_SNAP_TYPE_FACE → 人脸抓拍
  │   ├─ PIC_SNAP_TYPE_DYNAMIC → 动态抓拍 (ONVIF)
  │   ├─ PIC_SNAP_TYPE_CALL → 对讲抓拍
  │   ├─ PIC_SNAP_TYPE_MOTDETECT → 移动侦测抓拍
  │   └→ image_static_pool / image_dynamic_pool
  │       └→ 关联事件上传
  │
  ├→ dsp_callback_md_result()
  │   ├─ 移动侦测区域匹配
  │   ├─ motDetTimes[] 计数
  │   └→ semPost(&motDetSyncSem) → motion_detection 线程触发
  │
  └→ dsp_callback_qrcode_result()
      └→ qr_code_process() → 二维码解析 → 开门/告警
```

### 11.2 音频数据流（麦克风 → DSP → 网络/存储）

#### 11.2.1 上行音频（采集 → 编码 → 网络/存储）

```
麦克风 (MIC)
  │
  ├→ ADC (模数转换)
  ├→ DSP 音频预处理
  │   ├─ AEC (声学回声消除)
  │   ├─ ANS (噪声抑制)
  │   ├─ AGC (自动增益控制)
  │   └→ 预处理音频数据
  │
  ├→ DSP 音频编码
  │   ├─ G.711A / G.711U / G.722 / AAC / G.726
  │   ├─ 编码参数: AUDIOPARAMS
  │   └→ 编码帧 → STREAM_ELEMENT 回调
  │       │
  │       └→ dsp_callback_audio_play_result()
  │           └→ vis_audio_send_MqMsg() → 音频播放模块
  │
  ├→ 预览分发
  │   ├→ NETEQ (音频去抖动)
  │   ├→ NPQ QoS (NACK/FEC/带宽自适应)
  │   └→ 各协议层发送
  │       ├→ SDK: HIK 私有协议
  │       ├→ RTSP: RTP 封装
  │       ├→ 对讲: VOIP RTP
  │       └→ 萤石云
  │
  └→ 录像存储
      ├→ stor_send_rec_msg(FLUSH_STREAM)
      ├─ PS 封装: Stream ID = 0x21
      └→ 写入录像文件
```

#### 11.2.2 下行音频（网络 → 解码 → 扬声器）

```
网络接收 (SDK/RTSP/对讲)
  │
  ├→ RTP/RTCP 接收
  ├→ NPQ QoS 处理
  │   ├─ NACK 重传
  │   ├─ FEC 恢复
  │   └→ 去抖动 (Jitter Buffer)
  │
  ├→ DSP 解码
  │   ├─ G.711/G.722/AAC 解码
  │   └→ PCM 数据
  │
  ├→ 音频播放
  │   ├→ AO (Audio Output) 硬件接口
  │   ├→ dsp_callback_audio_play_result()
  │   │   ├─ AUDIOPLAY_END_MSG → 播放完成
  │   │   └─ AUDIOPLAY_INTERRPUTED_MSG → 播放中断
  │   └→ vis_audio_send_MqMsg() → 通知上层
  │
  └→ 扬声器 (Speaker)
```

#### 11.2.3 对讲音频流

```
对讲发起 (SIP/ISUP)
  │
  ├→ 主叫方音频
  │   ├→ MIC → DSP 编码 → RTP 发送
  │   └→ NPQ QoS 保障
  │
  ├→ 被叫方接收
  │   ├→ RTP 接收 → NPQ 处理 → DSP 解码
  │   └→ AO 播放 → 扬声器
  │
  ├→ 反向通道 (全双工)
  │   ├→ 被叫方 → MIC → DSP 编码 → RTP
  │   └→ 主叫方接收 → 解码 → 播放
  │
  └→ 对讲录音
      └→ 复制一路编码流 → storLib 录像
```

### 11.3 控制数据流（客户端 → 协议层 → 业务层 → 硬件）

#### 11.3.1 总览

```
客户端 (SDK/RTSP/Web/萤石)
  │
  ├→ 协议封装
  │   ├─ SDK: NETCMD_HEADER + 业务命令
  │   ├─ RTSP: DESCRIBE/SETUP/PLAY/TEARDOWN
  │   ├─ WebSocket: JSON 命令
  │   └─ HTTP: RESTful API
  │
  ├→ 网络传输层
  │   ├─ SDK: TCP 8000 / TLS 8443
  │   ├─ RTSP: TCP 554
  │   ├─ WebSocket: TCP 80/443
  │   └→ 数据包到达 netConn 层
  │
  ├→ 命令解析 (netConn)
  │   ├─ SDK 命令分发
  │   │   ├─ dvrNet.c: NETCMD_HEADER 解析
  │   │   ├─ NETCMD_PREVIEW → 预览控制
  │   │   ├─ NETCMD_VOICE_TALK → 对讲控制
  │   │   ├─ NETCMD_RECORD_START/STOP → 录像控制
  │   │   ├─ NETCMD_GET_CONFIG/SET_CONFIG → 配置读写
  │   │   └→ 各 handler 函数分发
  │   │
  │   ├─ RTSP 命令处理
  │   │   ├─ rtspApp.c: RTSP 状态机
  │   │   ├─ DESCRIBE → SDP 协商
  │   │   ├─ SETUP → Track 绑定 + RTP 通道建立
  │   │   └→ PLAY/TEARDOWN → 媒体流控制
  │   │
  │   └→ WebSocket 命令处理
  │       └→ websocket_service.c → 命令分发
  │
  ├→ 业务处理层 (opdevsdk IPC 总线)
  │   │
  │   ├→ req-resp 模式
  │   │   ├─ opdevsdk_ipc_server_start(IPC_HIK_MAIN_SERVICE)
  │   │   └→ main_service_task() 处理请求
  │   │
  │   ├→ pub-sub 模式
  │   │   ├─ opdevsdk_inproc_sub() 订阅
  │   │   └→ pub_service_task() 处理广播
  │   │
  │   └→ 跨进程 IPC
  │       ├─ HICORE 进程 ↔ 业务模块
  │       ├─ 消息队列: /home/config/ 共享内存
  │       └→ POSIX mq (录像消息等)
  │
  ├→ 硬件控制层
  │   ├→ DAL (Device Abstraction Layer)
  │   │   ├─ dal_keyboard_start → 按键控制
  │   │   ├─ dal_door_ctrl_start → 门锁控制
  │   │   ├─ dal_illm_start → 照明控制
  │   │   ├─ dal_dabi_start → 双鉴探测器
  │   │   ├─ dal_cdrd_start → 读卡器
  │   │   └→ dal_mdoorbell_start → 机械门铃
  │   │
  │   ├→ HAL 接口
  │   │   ├─ hal_interface/dal_interface/
  │   │   ├─ sdcard.h → SD 卡操作
  │   │   ├─ dai_light.h → 灯光控制
  │   │   └→ hal.h → 通用硬件抽象
  │   │
  │   └→ RS485/GPIO
  │       ├─ dai_rs485_info_init()
  │       └→ 外接云台/报警器
  │
  └→ 配置更新
      ├→ 数据库 (dbutil)
      ├→ Flash 持久化
      └→ 运行时热更新
```

#### 11.3.2 典型控制流 — 开始录像

```
客户端发送 NETCMD_RECORD_START
  │
  ├→ netConn 层解析 NETCMD_HEADER
  ├→ 路由到录像处理函数
  │   │
  ├→ stor_send_rec_msg(START_RECORD)
  │   │
  ├→ RECORD_MSGS.start_stream
  │   ├─ start_stream: 流起始位置
  │   ├─ is_iframe: 标记
  │   └→ mq_send() → 录像消息队列
  │       │
  ├→ storLib 线程消费消息
  │   ├→ 分配 STOR_AV_BUFFER
  │   ├→ 创建新录像文件
  │   ├→ PS 封装 (Stream ID 0x1B/0x21)
  │   └→ 开始写入磁盘
  │
  └→ 返回成功状态给客户端
```

#### 11.3.3 典型控制流 — RTSP 预览建立

```
RTSP DESCRIBE → SDP 协商
  │
  ├→ rtspApp.c 解析 DESCRIBE
  ├→ generate_sdp() 生成 SDP
  │   ├─ m=video (Track 1)
  │   │   ├─ RTP_MAP: H264/G.711/AAC
  │   │   ├─ SSRC 生成
  │   │   └→ SDP answer
  │   │
  ├→ RTSP SETUP (Track 1: VIDEO)
  │   ├→ save_rtspclient_media_info()
  │   ├→ 创建 RTP socket
  │   ├→ 创建 RTCP socket
  │   └→ RTP_INFO_HEADER 初始化
  │
  ├→ RTSP PLAY
  │   ├→ preview_component 启动预览
  │   ├→ 连接 DSP 编码数据流
  │   └→ RTP 打包发送
  │
  └→ 视频流开始传输
```

### 11.4 事件数据流（硬件 → DAL → 业务 → 上传）

#### 11.4.1 事件系统架构

```
事件系统三层架构:

  硬件层 (DAL)
    │
    ├─ DAL 设备表:
    │   ├─ DAL_KEYBOARD → 按键事件
    │   ├─ DOOR_CTRL → 门状态事件
    │   ├─ ILLM → 照明事件
    │   ├─ DABI → 双鉴探测器事件
    │   ├─ CDRD → 读卡器事件
    │   └→ MDOORBELL → 门铃事件
    │
    ├→ 事件触发 → 中断/轮询
    │
  业务层 (eventCtrl)
    │
    ├─ event_ctrl.c: 事件主控制器
    │   ├─ event_ctrl_module_startup()
    │   ├─ g_event_upload_msg: 事件上传消息队列
    │   ├─ event_lock: 互斥锁保护
    │   └→ event_upload_blocks_head: 事件块链表
    │
    ├─ 事件处理:
    │   ├─ get_event_id() → 自动分配事件 ID
    │   ├─ is_need_store_event() → 判断是否离线存储
    │   ├─ is_need_store_pic() → 判断是否存储抓拍
    │   └→ check_capa_support(DEVCHK_SW_CAPA, SW_OFFLINE_EVENT_UPLOAD)
    │
    ├─ 事件图片管理 (event_pic_manage.c)
    │   ├─ event_pic_data_mutex_lock
    │   └→ JPEG 图片缓存 + 关联事件
    │
    └→ 事件上传分发 (event_upload.c)
        │
        ├─ send_event_info_to_sip_server()
        │   └→ ysipc_send_alarm_info() → SIP 服务器
        │
        ├─ event_upload_to_client()
        │   ├─ ARMING_SDK_MQ_MSG → SDK 客户端
        │   └→ event_arming_sdk_msg_send()
        │
        ├─ event_upload_to_center()
        │   ├─ event_monitor_sdk_msg_send() → 报警中心
        │   └→ SDK Monitor 通道
        │
        └→ 多渠道上传:
            ├─ event_arming_sdk_channel → SDK 协议
            ├─ event_arming_isapi_channel → ISAPI 协议
            ├─ event_isup_channel → Ehome/ISUP 协议
            ├─ event_ezviz_alarm_channel → 萤石云
            ├─ event_ezviz_isapi_channel → 萤石 ISAPI
            ├─ event_monitor_sdk_channel → 监控中心
            ├─ event_monitor_isapi_channel → 监控 ISAPI
            └→ event_syslog_channel → Syslog

  云端/远程层
    │
    ├─ SIP (YSIPC): ysipClientInterface → 告警推送
    ├─ SDK: 报警 SDK → 客户端/中心
    ├─ ISAPI: Ehome → NVR/平台
    ├─ 萤石云: Ezviz → 手机 App
    └→ Syslog: 日志服务器
```

#### 11.4.2 典型事件流 — 移动侦测

```
DSP 移动侦测检测
  │
  ├→ dsp_callback_md_result()
  │   ├─ 区域匹配: pData[i] & pmoto_area[i][0]
  │   ├─ motDetTimes[dwChan]++
  │   └→ semPost(&motDetSyncSem) → 信号量通知
  │
  ├→ motion_detection 线程唤醒
  │   ├→ 触发录像 (stor_send_motion_trigger_rec_msg)
  │   ├→ 触发抓拍 (JPEG_SNAP_TYPE_MOTDETECT)
  │   └→ 触发告警事件
  │
  ├→ event_ctrl 创建事件
  │   ├─ get_event_id()
  │   ├─ 分配 event_upload_block
  │   ├─ 关联抓拍图片
  │   └→ 加入上传队列
  │
  ├→ 事件上传
  │   ├→ SDK 客户端 (event_upload_to_client)
  │   ├→ 报警中心 (event_upload_to_center)
  │   └→ SIP 服务器 (send_event_info_to_sip_server)
  │
  └→ 客户端收到告警推送
```

#### 11.4.3 典型事件流 — 对讲请求

```
室内机/门口机 按键
  │
  ├→ DAL 检测按键事件
  │   └→ dal_keyboard_start 线程
  │
  ├→ IPC_HICORE_MSG → send_msg_to_ui_process_async()
  │   └→ UI 层通知
  │
  ├→ 触发 SIP INVITE
  │   ├→ exosipcIf_init() → SIP 客户端
  │   └→ ysip_server_process_startup() → SIP 服务器
  │
  ├→ 对讲会话建立
  │   ├→ talkback_rules_module_init()
  │   ├→ talkback_session_control → 状态机
  │   │   IDLE → CALLING → CONNECTING → ACTIVE
  │   └→ RTP 媒体流建立
  │
  └→ 手机端 SIP 接听
      └→ 全双工音视频通话
```

### 11.5 配置数据流（客户端 → 配置层 → 数据库 → 运行时）

#### 11.5.1 配置系统架构

```
配置数据流:

  客户端设置
    │
    ├→ SDK SET_CONFIG
    ├→ RTSP SET_CONFIG
    ├→ Web HTTP API
    └→ 萤石云远程配置
    │
    ├→ 协议层解析
    │   ├─ sdk_cfg_api.c: NETCMD 配置命令处理
    │   ├─ isapi_video.c: ISAPI 配置解析
    │   └→ 统一配置数据结构
    │
    ├→ 配置验证
    │   ├─ schema 校验 (SUPPORT_SCHEMA)
    │   │   └→ schema_validate_manage.c
    │   ├─ check_capa_support() → 能力检测
    │   └→ 范围/类型验证
    │
    ├→ 数据库持久化
    │   ├─ dbutil.h → 数据库操作
    │   ├─ db_user_info_shell.c → 用户配置
    │   ├─ db_event_info_shell.c → 事件配置
    │   └→ Flash 存储
    │
    ├→ 运行时更新
    │   ├─ opdevsdk IPC 广播
    │   │   └→ pub_service_task() 接收更新
    │   ├─ pDevCfgParam → 全局配置指针
    │   │   ├─ chanPara[] → 通道参数
    │   │   ├─ deviceConfigParms → 设备配置
    │   │   └→ get_cfg_param() → 读取配置
    │   └→ 模块热更新
    │       ├─ 编码参数 → DSP 重新配置
    │       ├─ 网络参数 → 网络模块重启
    │       ├─ 存储参数 → storLib 重新配置
    │       └→ 对讲参数 → talkback 模块
    │
    └→ 配置备份
        └→ backup_dev_cfg → 线程 (SW_SUP_DB_BACKUP)
```

#### 11.5.2 配置更新流程

```
客户端修改编码参数 (H.265, 4Mbps)
  │
  ├→ SDK SET_CONFIG 命令
  ├→ netConn 层解析
  ├→ 写入数据库 (dbutil)
  │
  ├→ 全局配置更新
  │   ├─ pDevCfgParam->encType.media_stream_enctype[0].video_enctype = H265
  │   └→ pDevCfgParam->encType.media_stream_enctype[0].bitrate = 4000
  │
  ├→ DSP 重新配置
  │   ├─ dsp_command → 设置编码类型
  │   ├─ STREAMPARAMS 更新
  │   └→ ENC_TYPE_PARAM 更新
  │
  ├→ Preview Component 通知
  │   └→ 通知所有预览连接新参数
  │
  └→ 配置生效 (无缝切换)
```

---

## 第12章：模块间关系与交互

### 12.1 模块依赖关系图

```
音视频链路模块依赖总览:

                    ┌─────────────────────┐
                    │     usrAppEntry      │
                    │   (启动编排层)        │
                    └─────────┬───────────┘
                              │
              ┌───────────────┼────────────────┐
              │               │                │
    ┌─────────▼──────┐ ┌─────▼──────┐  ┌──────▼───────┐
    │  DSP 子系统     │ │  网络子系统 │  │  存储子系统   │
    │                │ │            │  │              │
    │ dsp_init       │ │ dvrNet     │  │ init_stor_   │
    │ dsp_callback   │ │ netConn    │  │   system()   │
    │ dsp_interface  │ │ rtspServer │  │ storLib      │
    │ dsp_interface  │ │ rtspClient │  │ deviceMgr    │
    │                │ │ visNet     │  │ fileMgr      │
    └───────┬────────┘ │ ezviz      │  │ dataService  │
            │          │ isup/ehome │  │ search       │
    ┌───────▼────────┐ └─────┬──────┘  └──────┬───────┘
    │  预览组件      │       │                │
    │                │       │                │
    │ preview_comp   │       │                │
    │ NETBUF_INFO    │       │                │
    └───────┬────────┘       │                │
            │                │                │
    ┌───────▼────────────────▼────────────────▼───────┐
    │              opdevsdk IPC 总线                    │
    │  ┌─────────────┐  ┌─────────────┐               │
    │  │ req-resp    │  │ pub-sub     │               │
    │  │ main_svc    │  │ pub_svc     │               │
    │  └─────────────┘  └─────────────┘               │
    └────────────────────────────────────────────────┘
              │               │                │
    ┌─────────▼────┐  ┌──────▼──────┐  ┌──────▼───────┐
    │  业务模块     │  │  硬件抽象层  │  │  配置管理     │
    │              │  │             │  │              │
    │ event_ctrl   │  │ DAL         │  │ dbutil       │
    │ motion_detect│  │ HAL         │  │ schema       │
    │ alarm_ctrl   │  │ keyboard    │  │ pDevCfgParam │
    │ talkback     │  │ door_ctrl   │  │              │
    │ broadcast    │  │ illm        │  │              │
    │ face_comp    │  │ dabi        │  │              │
    │ audio_play   │  │ cdrd        │  │              │
    └──────────────┘  └─────────────┘  └──────────────┘
```

### 12.2 IPC 消息总线（opdevsdk pub-sub + req-resp）

#### 12.2.1 架构

```
opdevsdk IPC 总线
  │
  ├→ 初始化 (usrMainApp.c → usrAppEntry)
  │   ├─ opdevsdk_ipc_init(IPC_FILE_SELF, system_service_task, "HICORE")
  │   ├─ opdevsdk_ipc_center_init()    → pub 消息中心初始化
  │   ├─ opdevsdk_ipc_server_start(IPC_HIK_MAIN_SERVICE, main_service_task)
  │   └→ opdevsdk_inproc_sub("", pub_service_task)
  │
  ├→ 两种消息模式
  │   │
  │   ├─ req-resp (请求-响应)
  │   │   ├─ 客户端发送请求 → 指定服务名
  │   │   ├─ HICORE 进程路由到对应 server
  │   │   ├─ main_service_task() 处理请求
  │   │   └→ 返回响应给客户端
  │   │   │
  │   │   └─ 典型场景:
  │   │       ├─ 配置读取/设置
  │   │       ├─ 设备信息查询
  │   │       ├─ 模块状态查询
  │   │       └→ 跨模块服务调用
  │   │
  │   └─ pub-sub (发布-订阅)
  │       ├─ 任意模块可发布 pub 消息
  │       ├─ pub_service_task() 接收所有 pub 消息
  │       └→ 根据消息类型分发处理
  │           │
  │           └─ 典型场景:
  │               ├─ 模块启动完成通知
  │               ├─ 状态变更广播
  │               ├─ 事件通知
  │               └→ 配置更新广播
  │
  └→ 通信机制
      ├─ 进程内通信: 共享内存 + 信号量
      ├─ 跨进程通信: /home/config/ 共享内存文件
      └→ 消息格式: PHEOP_MSG_T / PHEOP_REQ_T
```

#### 12.2.2 消息类型

```
PHEOP_MSG_T 消息类型:
  ├─ APP2UI_MSG_STREAM_MOVE → 流移动 → UI 背光
  ├─ APP2UI_MSG_SPEECH_CMD_RESULT → 语音命令结果 → UI
  ├─ APP2UI_MSG_SPEECH_CMD_STATUS → 语音命令状态
  ├─ APP2UI_MSG_STATUS → 状态通知
  └→ ...更多

PHEOP_REQ_T 请求消息:
  ├─ 配置读写请求
  ├─ 设备信息查询
  ├─ 模块控制请求
  └→ ...更多
```

### 12.3 消息队列机制（POSIX mq）

#### 12.3.1 录像消息队列

```
RECORD_MSGS 消息队列 (每通道独立)
  │
  ├─ 消息类型:
  │   ├─ START_RECORD: 开始录像
  │   │   ├─ start_stream: 流起始位置
  │   │   ├─ end_stream: 流结束位置
  │   │   └→ is_iframe: 是否关键帧
  │   │
  │   ├─ FLUSH_STREAM: 推送编码流
  │   │   ├─ start_stream / end_stream
  │   │   └→ is_iframe: 标记
  │   │
  │   ├─ IFRAME: 关键帧事件
  │   │   └→ 记录 I 帧索引到 IFRAME_INFO
  │   │
  │   └─ PIC_FRAME: 抓拍事件
  │       ├─ PIC_FRAME_MSG_BODY_V2_T
  │       ├─ 关联事件 ID
  │       └→ JPEG 图片数据
  │
  ├─ 发送端:
  │   ├─ stor_send_rec_msg() → mq_send()
  │   ├─ stor_send_motion_trigger_rec_msg()
  │   ├─ stor_send_alarm_trigger_rec_msg()
  │   ├─ stor_send_vca_trigger_rec_msg()
  │   ├─ stor_send_event_trigger_rec_msg()
  │   └→ stor_send_cmd_trigger_rec_msg()
  │
  └─ 接收端:
      └→ storLib 线程 mq_receive()
```

#### 12.3.2 其他消息队列

```
其他 mq 使用:
  ├─ HPR_MsgQ → 对讲消息队列
  │   └→ vis_audio_send_MqMsg()
  │
  ├─ motDetSyncSem → 移动侦测信号量
  │   └→ dsp_callback_md_result() → semPost()
  │
  ├─ videoSignalSem → 视频信号信号量
  │   └→ usrMainApp.c 全局
  │
  └─ JPEG 抓拍信号量
      └→ pstSnapHdr->semInfo → semPost()
```

### 12.4 共享内存机制

#### 12.4.1 DSP ↔ Host 共享内存

```
DSP 共享内存布局:
  │
  ├─ HOST_TO_DSP_DATA (Host → DSP)
  │   ├─ 编码参数配置
  │   ├─ ROI 区域定义
  │   ├─ 隐私掩码区域
  │   └→ DSP 命令控制
  │
  ├─ DSP_TO_HOST_DATA (DSP → Host)
  │   ├─ 编码帧数据
  │   ├─ 事件通知 (MD/Face/QR)
  │   ├─ 状态信息
  │   └→ 统计信息
  │
  └─ DSPSHAREDATA
      ├─ 全局 DSP 状态
      ├─ 通道配置
      └→ 共享参数
```

#### 12.4.2 预览数据共享内存

```
PREVIEW_DATA_BUF_INFO (预览缓冲区)
  │
  ├─ data_buf_addr: 编码数据地址
  ├─ data_buf_widx_addr: 写索引 (原子操作)
  ├─ data_buf_totallen: 总长度
  ├─ data_buf_totalwlen_addr: 历史总长度
  │
  └→ 多连接并发读取
      ├─ 每个预览连接独立 read_idx
      ├─ 无锁读取 (写索引原子操作)
      └→ 连接断开时释放
```

#### 12.4.3 录像缓冲区共享内存

```
STOR_AV_BUFFER (录像缓冲区)
  │
  ├─ recBuf: 编码数据缓冲区
  ├─ infoBuf: 文件信息缓冲区
  ├─ IFrames[200]: I 帧索引数组
  ├─ recStat[2]: 主/子码流状态
  │
  └→ 每通道独立 STOR_RECORDER
      └→ storLib 内部管理
```

#### 12.4.4 图像池共享内存

```
image_static_pool (静态图像池)
  │
  ├─ MAX_IMAGE_NUM: 图像槽位数
  ├─ poolIdx: 槽位索引
  ├─ JPEG_SNAP_HEARD_S: 图像头 (type/len/poolIdx)
  │
  └→ image_dynamic_pool (动态图像池)
      └→ ONVIF 等动态抓拍
```

### 12.5 事件驱动模型

#### 12.5.1 事件源

```
事件源分类:
  │
  ├─ DSP 事件 (硬件加速)
  │   ├─ 人脸识别 → STREAM_ELEMENT_FR_FFD_IQA
  │   ├─ IQA 图像质量 → STREAM_ELEMENT_FR_IQA
  │   ├─ 移动侦测 → STREAM_ELEMENT_FR_MD
  │   ├─ JPEG 抓拍 → STREAM_ELEMENT_JPEG_IMG
  │   ├─ 二维码 → STREAM_ELEMENT_QR_CODE
  │   └→ 1vN 比对 → STREAM_ELEMENT_FR_CP
  │
  ├─ 硬件事件 (DAL)
  │   ├─ 按键 → DAL_KEYBOARD
  │   ├─ 门状态 → DOOR_CTRL
  │   ├─ 双鉴探测器 → DABI
  │   ├─ 读卡器 → CDRD
  │   └→ 照明 → ILLM
  │
  ├─ 网络事件
  │   ├─ 客户端连接 → netConn
  │   ├─ RTSP 会话 → rtspServer
  │   ├─ SIP 呼叫 → SIP Server
  │   └→ 萤石连接 → Ezviz
  │
  └─ 存储事件
      ├─ 磁盘异常 → storLib callback
      ├─ 容量告警 → 事件上传
      └→ 录像完成 → 文件索引
```

#### 12.5.2 事件处理链

```
事件处理链:

  事件触发
    │
    ├→ 1. 数据采集 (DSP/HAL)
    │   └→ 回调函数 / 信号量 / 中断
    │
    ├→ 2. 事件封装
    │   └→ EVENT_UPLOAD_MSG_BLOCK
    │       ├─ event_msg_head
    │       ├─ upload_detail
    │       └→ event_upload_stat
    │
    ├→ 3. 事件处理
    │   ├─ 离线存储 (Flash/SD)
    │   ├─ 图片关联
    │   └→ 事件块入队
    │
    ├→ 4. 事件上传
    │   ├─ 渠道选择 (SDK/SIP/Ezviz/ISAPI)
    │   ├─ 并发控制 (occupied_nums)
    │   └→ 状态跟踪 (READY → PROCESSING → SUCC/FAIL)
    │
    └→ 5. 事件清除
        └→ 上传成功后从队列移除
```

### 12.6 跨模块线程协作关系

#### 12.6.1 主要线程

```
主应用线程 (usrAppEntry)
  │
  ├→ streamRecvTaskId
  │   └→ DSP 编码数据接收 + 分发
  │
  ├→ streamEventTaskId
  │   └→ DSP 事件数据处理
  │
  ├→ recordTaskId
  │   └→ 录像管理
  │
  ├→ hdCtrlTaskId
  │   └→ 硬盘控制
  │
  ├→ netSvrTaskId
  │   └→ 网络服务
  │
  ├→ sadpTaskId
  │   └→ SADP 发现
  │
  ├→ ipdomemotionschedulid
  │   └→ 移动侦测调度
  │
  ├→ backup_dev_cfg_taskid
  │   └→ 配置备份
  │
  └→ streamEventTaskId
      └→ 流事件处理
```

#### 12.6.2 线程间协作

```
线程协作关系:

  streamRecvTask ←→ preview_component
    │
    ├→ 从 DSP 接收编码数据
    ├→ 通过 NETBUF_INFO 共享内存分发
    ├→ preview_component 管理所有预览连接
    └→ 各连接独立读取，无锁设计

  streamRecvTask ←→ storLib
    │
    ├→ 编码帧通过 RECORD_MSGS 推送
    ├→ mq_send/mq_receive 同步
    └→ storLib 线程消费，写入文件

  motion_detection ←→ streamEventTask
    │
    ├→ semPost(&motDetSyncSem) 信号量同步
    ├→ motion_detection 等待信号量
    ├→ 触发录像 + 抓拍 + 告警
    └→ 8秒冷却期 (dwMoveDetectTime)

  event_ctrl ←→ 各模块
    │
    ├→ 接收各模块事件通知
    ├→ 通过 opdevsdk pub 消息
    ├→ 封装事件块
    └→ 多渠道上传

  talkback_session ←→ SIP/ISUP
    │
    ├→ SIP 信令 → talkback_sip.cpp
    ├→ ISUP 信令 → talkback_ISUP.cpp
    ├→ 萤石 → talkback_ezviz.cpp
    ├→ 萤石 → talkback_ezviz.cpp
    ├→ 海康云 → talkback_hik_cloud.cpp
    ├→ 海康 SDK → talkback_net_sdk.cpp
    └→ 模拟 → analog dispatcher
    └→ talkback_net_sdk.cpp
    └→ 模拟 → analog_handle_main_setup()
    │
    └→ 统一 session 模型
        ├→ 状态机: IDLE → CALLING → CONNECTING → ACTIVE
        ├→ 规则引擎: talkback_rules_control
        └→ 媒体流: RTP/RTCP
```

---

## 第13章：设计模式与关键技术

### 13.1 分层设计原则

整个音视频链路采用清晰的七层架构：

```
七层架构:

  Layer 7 — 业务场景层
    ├─ 实时预览 (SDK/RTSP/WebSocket/萤石)
    ├─ 录像回放
    ├─ 可视对讲 (SIP/ISUP)
    ├─ 语音对讲 (单向广播)
    └→ 云连接 (萤石)

  Layer 6 — 协议层
    ├─ SDK 二进制协议 (NETCMD_HEADER)
    ├─ RTSP/RTP/RTCP
    ├─ SIP (YSIPC + Exosip)
    ├─ ONVIF/ISAPI
    ├─ WebSocket
    ├─ Ehome/ISUP
    └→ 萤石私有协议

  Layer 5 — 传输/QoS 层
    ├─ NPQ (NACK/FEC/TCC/REMB/Pacing)
    ├─ RTCP 控制报告
    ├─ SRTP 加密传输
    └→ Jitter Buffer

  Layer 4 — 分发/路由层
    ├─ Preview Component (预览分发)
    ├─ storLib (录像存储)
    ├─ 广播系统 (实时/定时/RTP)
    └→ 对讲会话管理

  Layer 3 — 编解码层 (DSP)
    ├─ H.264/H.265/MPEG4/MJPEG 视频编码
    ├─ G.711/G.722/AAC/G.726 音频编码
    ├─ DSP 共享内存
    └→ STREAM_ELEMENT 回调

  Layer 2 — 硬件抽象层
    ├─ DAL (Device Abstraction Layer)
    ├─ HAL (Hardware Abstraction Layer)
    ├─ ISP (Image Signal Processor)
    └→ AO/ADC (音频输出/输入)

  Layer 1 — 硬件层
    ├─ Davinci DSP (GOM + VEDN)
    ├─ Sensor (CMOS)
    ├─ MIC (MEMS)
    ├─ SATA/SD Card
    └→ 网络 PHY
```

**分层设计原则**:
- 每层只依赖下一层，不跨层调用
- 层间通过标准化接口通信
- 上层变更不影响下层，下层升级不影响上层
- 协议层可插拔 (SDK/RTSP/SIP/ONVIF 可独立增减)

### 13.2 能力检测机制（check_capa_support）

#### 13.2.1 架构

```
能力检测系统:

  check_capa_support(分类, 检测项)
    │
    ├─ 分类:
    │   ├─ DEVCHK_HW_CAPA → 硬件能力
    │   ├─ DEVCHK_SW_CAPA → 软件能力
    │   └→ DEVCHK_NET_CAPA → 网络能力
    │
    ├─ 硬件能力检测项:
    │   ├─ HW_THERMAL_SUP → 热成像支持
    │   ├─ HW_SECURITY_MODULE_SUP → 安全模块
    │   ├─ HW_BLUETOOTH_SUP → 蓝牙
    │   └→ ...
    │
    ├─ 软件能力检测项:
    │   ├─ SW_OFFLINE_EVENT_UPLOAD → 离线事件上传
    │   ├─ SW_OFFLINE_EVENT_PIC → 离线事件图片
    │   ├─ SW_GUI_SUP → GUI 支持
    │   ├─ SW_FACE_REC_SUP → 人脸识别
    │   ├─ SW_BROADCAST_SUP → 广播
    │   ├─ SW_SMART_AUDIO_DETECT → 智能音频检测
    │   ├─ SW_RS485_JOIN_DECICES_AT_SAME_TIME → RS485 多设备
    │   ├─ SW_SUP_DB_BACKUP → 数据库备份
    │   ├─ SW_WEB_UPDATE_DATA_SUP → Web 远程升级
    │   └→ ...
    │
    └→ 返回值: CAPA_SUPPORTED / CAPA_NOT_SUPPORT
```

#### 13.2.2 使用模式

```
能力检测在代码中的使用:

  // 启动前检测
  if (CAPA_SUPPORTED == check_capa_support(DEVCHK_SW_CAPA, SW_FACE_REC_SUP)) {
      face_component_module_startup();
  }

  // 条件执行
  if (CAPA_SUPPORTED == check_capa_support(DEVCHK_SW_CAPA, SW_BROADCAST_SUP)) {
      real_time_broadcast_init();
  }

  // 配置验证
  if (CAPA_NOT_SUPPORT == check_capa_support(DEVCHK_SW_CAPA, SW_OFFLINE_EVENT_UPLOAD)) {
      return FALSE; // 不支持离线上传
  }

  // 硬件检测
  if (CAPA_SUPPORTED == check_capa_support(DEVCHK_HW_CAPA, HW_THERMAL_SUP)) {
      start_thermal_ctrl_proc();
      start_thermal_proc();
  }
```

**能力检测的价值**:
- 同一套代码适配多种硬件平台 (F1Plus/F2pro/A2S/AI2)
- 功能模块按需启用，减少资源占用
- 新增功能无需修改核心代码，只需注册能力项
- 编译时/运行时双重能力检查

### 13.3 配置驱动设计

#### 13.3.1 配置层次

```
配置层次:

  持久化层 (Flash)
    │
    ├─ 数据库 (dbutil)
    │   ├─ 用户配置
    │   ├─ 事件配置
    │   ├─ 网络配置
    │   └→ 设备配置
    │
    ├─ XML/JSON 配置文件
    │   ├─ 编码参数
    │   ├─ 预览参数
    │   └→ 对讲参数
    │
    └→ Schema 校验 (SUPPORT_SCHEMA)
        └→ schema_validate_manage.c

  运行时层 (内存)
    │
    ├─ pDevCfgParam → 全局配置指针
    │   ├─ chanPara[] → 通道参数
    │   ├─ deviceConfigParms → 设备配置
    │   └→ get_cfg_param() → 读取
    │
    ├─ 编码参数
    │   ├─ encType.media_stream_enctype[]
    │   ├─ 视频编码类型
    │   └→ 音频编码类型
    │
    └→ 模块私有配置
        ├─ storLib 存储配置
        ├─ NPQ QoS 配置
        ├─ RTSP 服务器配置
        └→ 对讲会话配置

  配置更新流程:
    客户端 → 协议层 → 数据库 → 全局指针 → DSP/模块热更新
```

#### 13.3.2 配置驱动的关键场景

```
1. 编码参数驱动:
   pDevCfgParam->encType → DSP STREAMPARAMS → 实时生效

2. 存储参数驱动:
   循环录像/配额模式 → stor_set_sys_callback_func() → storLib 重配置

3. 网络参数驱动:
   IP/端口/DNS → 网络模块热重启

4. 对讲参数驱动:
   SIP 服务器/端口/认证 → SIP 模块重连

5. 报警参数驱动:
   移动侦测区域 → motDetpara → DSP 重新配置
```

### 13.4 模块化启动模型

#### 13.4.1 三阶段启动

```
阶段 1: aip_base (基础层)
  │
  ├─ 系统初始化
  │   ├─ 内存分配 (alloc_share_memory)
  │   ├─ 信号量/互斥锁初始化
  │   ├─ 目录创建 (creat_support_dir)
  │   └→ 数据库初始化
  │
  ├─ IPC 总线初始化
  │   ├─ opdevsdk_ipc_init()
  │   ├─ opdevsdk_ipc_center_init()
  │   ├─ opdevsdk_ipc_server_start()
  │   └→ opdevsdk_inproc_sub()
  │
  └→ 基础模块启动
      ├─ HAL 初始化 (_usrMain_HAL_init)
      ├─ 音频播放模块 (vis_audio_paly_module_startup)
      ├─ 报警探测模块 (alarm_probe_module_startup)
      ├─ 按键业务 (key_business_module_startup)
      ├─ 指纹模块 (fingerprint_module_startup)
      └→ 权限验证 (permission_check_module_startup)

阶段 2: user_sysinit (业务层)
  │
  ├─ 兼容处理 (compatible_process_task)
  ├─ MCU 模块 (mcu_module_startup)
  ├─ 视频播放 (ad_video_play_startup)
  ├─ 人脸组件 (face_component_module_startup)
  ├─ 前端参数同步 (UniNetIf_sync_FrontParam)
  │
  └→ 进度: 30% → 60% → 100%
      └→ compatible_set_percentage()

阶段 3: usrAppEntry (应用层)
  │
  ├─ 网络服务启动
  │   ├─ preview_component 初始化
  │   ├─ dvrnet_server (8000)
  │   ├─ dvrnet_tls_server (8443)
  │   ├─ visnet_server (8102)
  │   ├─ net_broken_server (6666)
  │   ├─ rtsp_server (554)
  │   ├─ rtsp_client
  │   ├─ SADP server/client
  │   ├─ ONVIF
  │   ├─ 萤石云
  │   ├─ Ehome/ISUP
  │   └→ WebSocket
  │
  ├─ 对讲系统
  │   ├─ talkback_rules_module_init()
  │   ├─ analog_handle_main_setup()
  │   ├─ alarm_voice_module_startup()
  │   ├─ real_time_broadcast_init()
  │   ├─ rb_com_module_startup()
  │   └→ rtp_pager_multicast_init()
  │
  ├─ 存储系统
  │   └→ init_stor_system()
  │
  ├─ QoS 系统
  │   └→ NPQ_Process_start()
  │
  └→ bDevAppStarted = TRUE
```

#### 13.4.2 启动进度管理

```
compatible_set_percentage(E_COMPATIBLE_OTHER_MODULE, 30)
compatible_set_percentage(E_COMPATIBLE_OTHER_MODULE, 60)
compatible_set_percentage(E_COMPATIBLE_OTHER_MODULE, 100)

UI 层通过进度条显示启动状态:
  0% → aip_base 开始
  30% → 基础模块完成
  60% → HAL 完成
  100% → user_sysinit 完成 → 发送 HICORE 初始化完成消息
  100% → 应用层启动完成 → bDevAppStarted = TRUE
```

### 13.5 线程优先级与栈管理

#### 13.5.1 线程创建模式

```
线程创建: pthreadSpawn(stack_size, priority, stack_size, func, arg)

主要线程:
  ├─ streamRecvTaskId: DSP 编码数据接收
  │   └→ COMMON_PRIO, 32KB stack
  │
  ├─ recordTaskId: 录像管理
  │   └→ COMMON_PRIO
  │
  ├─ hdCtrlTaskId: 硬盘控制
  │   └→ COMMON_PRIO
  │
  ├─ netSvrTaskId: 网络服务
  │   └→ COMMON_PRIO
  │
  ├─ backup_dev_cfg_taskid: 配置备份
  │   └→ COMMON_PRIO, 64KB stack
  │
  └─ blueToothTaskId: 蓝牙任务
      └→ COMMON_PRIO, 32KB stack
```

**线程设计原则**:
- 实时性要求高的线程 (streamRecv) 使用较高优先级
- 大数据处理线程 (backup_dev_cfg) 使用较大栈空间
- 独立功能模块使用独立线程，避免阻塞
- 线程间通过信号量/消息队列同步，避免忙等

### 13.6 安全机制

#### 13.6.1 视频加密

```
视频加密体系:

  编码层加密
    │
    ├─ AES 加密
    │   ├─ 编码后数据 AES 加密
    │   ├─ encrypt_interface.c
    │   └→ 密钥管理
    │
    ├─ 水印技术
    │   ├─ 视频帧水印
    │   └→ 防篡改验证
    │
    └→ RSA 签名
        ├─ 编码数据 RSA 签名
        ├─ 完整性验证
        └→ 防伪造
```

#### 13.6.2 传输加密

```
传输安全:

  ├─ SRTP (Secure RTP)
  │   ├─ RTP 数据包加密
  │   ├─ 源认证
  │   └→ 重放保护
  │
  ├─ TLS (传输层安全)
  │   ├─ SDK TLS: 8443 端口
  │   ├─ dvrnet_tls_server_module_startup()
  │   └→ 端到端加密
  │
  ├─ HTTPS (Web 管理)
  │   ├─ appweb SSL
  │   ├─ p_ssl_write_fun SSL 写回调
  │   └→ MprSocket (appweb MprSocket)
  │
  └→ 本地认证
      ├─ 用户权限管理 (authorityManagement)
      ├─ 密码加密存储
      └→ 会话超时
```

#### 13.6.3 数据安全

```
数据安全:

  ├─ 存储加密
  │   ├─ 录像文件加密存储
  │   ├─ cstorCom 组件
  │   └→ 密钥分片存储
  │
  ├─ 配置安全
  │   ├─ 配置文件加密
  │   ├─ schema 校验
  │   └→ 配置变更审计
  │
  └→ 固件升级安全
      ├─ RSA 签名验证
      ├─ 升级包完整性检查
      └→ 回滚保护
```

### 13.7 多平台适配策略

#### 13.7.1 平台宏定义

```
平台适配机制:

  #ifdef F1PLUS
    // F1Plus 平台特定代码
    #define HICORE_PATH "/home/config/hicore"
  #else
    // 其他平台
    #define HICORE_PATH "/home/app/hicore"
  #endif

  #ifdef SUPPORT_RECORD
    init_stor_system();
  #endif

  #ifdef ONVIF
    onvif_module_startup();
  #endif

  #ifdef RTP_RTCP
    rtcp_init();
  #endif

  #ifdef NET_EMAIL
    sendemail_ctrl();
  #endif

  #ifdef ANDROID
    // Android 特定代码
  #else
    // Linux 标准代码
  #endif
```

#### 13.7.2 能力检测 + 平台宏双保险

```
双保险机制:

  编译时: #ifdef 平台宏
    ├─ 决定哪些模块参与编译
    ├─ 减少二进制体积
    └→ 平台特定代码隔离

  运行时: check_capa_support()
    ├─ 决定哪些模块实际启动
    ├─ 同一二进制适配多平台
    └→ 功能按需启用

  结合效果:
    ├─ 编译时: 只编译当前平台相关代码
    ├─ 运行时: 根据实际硬件能力启用功能
    └→ 一套代码树覆盖 F1Plus/F2pro/A2S/AI2 多平台
```

#### 13.7.3 兼容处理流程

```
compatible_process_task()
  │
  ├─ 版本兼容: 旧配置格式 → 新格式迁移
  ├─ 参数兼容: 旧参数 → 新参数映射
  ├─ 功能兼容: 旧功能 → 新功能替代
  └→ 渐进式升级支持
```

---

## 附录

### 附录 A：编解码类型速查表

#### A.1 视频编码

| 编码类型 | 枚举值 | 最大分辨率 | 典型码率 | 应用场景 |
|---------|--------|----------|---------|---------|
| H.264 | 0x01 | 4K | 1-16 Mbps | 通用编码，兼容性最好 |
| H.265 (HEVC) | 0x02 | 4K | 0.5-8 Mbps | 高压缩比，节省带宽/存储 |
| MPEG4 | 0x03 | 1080p | 1-8 Mbps | 老设备兼容 |
| MJPEG | 0x04 | 1080p | 2-20 Mbps | 低延迟抓拍 |
| SVAC | 0x05 | 4K | 1-16 Mbps | 国标加密编码 |

#### A.2 音频编码

| 编码类型 | 枚举值 | 采样率 | 码率 | 应用场景 |
|---------|--------|-------|------|---------|
| AAC | 0x01 | 8/16/44.1/48 kHz | 8-256 kbps | 高质量音乐/对讲 |
| G.729 | 0x02 | 8 kHz | 8 kbps | 低带宽对讲 |
| G.722 | 0x03 | 16 kHz | 48-64 kbps | 宽频语音，清晰度高 |
| G.711A | 0x04 | 8 kHz | 64 kbps | PCM A律，RTSP 默认 |
| G.711U | 0x05 | 8 kHz | 64 kbps | PCM μ律，北美默认 |
| G.726 | 0x06 | 8 kHz | 16-40 kbps | 低码率语音 |

### 附录 B：端口与协议对照表

| 端口 | 协议 | 方向 | 用途 |
|-----|------|------|------|
| 80 | HTTP | 双向 | Web 管理界面 |
| 443 | HTTPS | 双向 | 安全 Web 管理 |
| 554 | RTSP/TCP | 双向 | RTSP 预览/回放 |
| 8000 | HIK SDK TCP | 双向 | 海康私有 SDK 协议 |
| 8443 | HIK SDK TLS | 双向 | 加密 SDK 协议 |
| 8102 | visNet TCP | 双向 | 可视对讲私有协议 |
| 6666 | netBroken TCP | 双向 | 断线重连保活 |
| 1935 | RTMP | 上行 | 视频直播推送 |
| 5000 | Ezviz UDP | 双向 | 萤石云连接 |
| 20000+ | Ehome TCP | 上行 | Ehome 平台接入 |
| 5060 | SIP UDP/TCP | 双向 | 可视对讲信令 |
| 30000+ | RTP/UDP | 双向 | 媒体流 |

### 附录 C：帧结构定义

#### C.1 SDK 命令头 (NETCMD_HEADER)

```c
typedef struct {
    UINT32 uiMagic;          // 魔数: 0x4B4948 ("HIK")
    UINT32 uiCmdType;        // 命令类型 (NETCMD_*)
    UINT32 uiSessionId;      // 会话 ID
    UINT32 uiSeqNo;          // 序列号
    UINT32 uiParamLen;       // 参数长度
    UINT32 uiDataLen;        // 数据长度
    UINT32 uiChannel;        // 通道号
    UINT32 uiStreamType;     // 码流类型
    UINT8  ucReserved[64];   // 保留
} NETCMD_HEADER;
```

#### C.2 RTSP Track ID

| Track ID | 类型 | RTP Payload | 说明 |
|---------|------|-------------|------|
| 1 | VIDEO | H264/H.265/MJPEG | 视频 Track |
| 2 | AUDIO | G.711/G.722/AAC | 音频 Track |
| 3 | METADATA | - | 元数据 Track |
| 4 | AUDIOBACK | G.711/G.722 | 回传音频 Track (对讲) |

#### C.3 PS 封装 Stream ID

| Stream ID | 类型 | 说明 |
|-----------|------|------|
| 0x1B | 视频 | H.264 NALU 封装 |
| 0x21 | 音频 | G.711/G.722/AAC 封装 |
| 0x00-0xBF | PES 包 | 包内容标识 |
| 0xBD | PES 视频流 | 视频 PES |
| 0xBE | Padding | 填充 |
| 0xBF | System Header | 系统头 |

### 附录 D：NPQ API 参考

| API | 方向 | 用途 |
|-----|------|------|
| NPQ_Process_start() | 初始化 | 启动 NPQ 处理线程 |
| npq_send_init() | 发送端 | 初始化发送端 QoS |
| npq_recv_init() | 接收端 | 初始化接收端 QoS |
| npq_set_nack_param() | 配置 | 设置 NACK 参数 |
| npq_set_fec_param() | 配置 | 设置 FEC 参数 |
| npq_set_bandwidth() | 配置 | 设置带宽限制 |
| npq_send_nack_req() | 发送端 | 发送 NACK 请求 |
| npq_recv_nack_resp() | 接收端 | 处理 NACK 响应 |
| npq_stat_get() | 监控 | 获取 NPQ 统计信息 |

### 附录 E：线程-模块-栈大小速查表

| 线程 | 模块 | 优先级 | 栈大小 | 说明 |
|------|------|-------|-------|------|
| streamRecvTaskId | DSP 数据接收 | COMMON_PRIO | 32 KB | 编码数据接收分发 |
| streamEventTaskId | DSP 事件处理 | COMMON_PRIO | 32 KB | 事件回调处理 |
| recordTaskId | 录像管理 | COMMON_PRIO | 32 KB | 录像文件管理 |
| hdCtrlTaskId | 硬盘控制 | COMMON_PRIO | 32 KB | SATA/SD 卡管理 |
| netSvrTaskId | 网络服务 | COMMON_PRIO | 64 KB | 网络服务主线程 |
| backup_dev_cfg_taskid | 配置备份 | COMMON_PRIO | 64 KB | 配置数据备份 |
| sadpTaskId | SADP | COMMON_PRIO | 32 KB | 设备发现 |
| ipdomemotionschedulid | 移动侦测 | COMMON_PRIO | 32 KB | MD 调度 |
| blueToothTaskId | 蓝牙 | COMMON_PRIO | 32 KB | 蓝牙任务 |
| NPQ 线程 | QoS 处理 | HIGH_PRIO | 64 KB | NPQ 发送/接收 |
| rtsp 线程 | RTSP 服务器 | COMMON_PRIO | 64 KB | RTSP 客户端连接 |
| SIP 线程 | SIP 信令 | COMMON_PRIO | 64 KB | SIP 信令处理 |
| event 线程 | 事件上传 | COMMON_PRIO | 32 KB | 事件上传处理 |

---

*以上内容为第13章：设计模式与关键技术，以及所有附录。*

*至此，音视频链路全栈详要文档（第1-13章 + 附录 A-E）全部完成。*
