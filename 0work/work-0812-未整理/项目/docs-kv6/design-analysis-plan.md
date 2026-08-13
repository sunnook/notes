# 音视频链路全栈详要 - 计划文档

## 项目概述
- **项目**: KV6 IPC/可视对讲设备 (F1Plus/F2pro/A2S/AI2)
- **版本**: V3.14.0
- **代码路径**: PJ14PD20260428091_V3.14.0/
- **参考文档**: hicore-architecture-analysis.md, netConn-design-analysis.md

---

## 章节大纲

### 第1章：音视频链路总览
- 1.1 系统音视频全景图
- 1.2 数据流与控制流概览
- 1.3 关键术语与缩写
- 1.4 与整体架构的关系（在 hicore 中的位置）

### 第2章：初始化全流程
- 2.1 三阶段启动模型回顾（aip_base → user_sysinit → usrAppEntry）
- 2.2 DSP 初始化详解（dsp_init, dsp_callback, dsp_command, dsp_interface）
- 2.3 音视频模块初始化（init_preview, vis_audio_paly_module_startup）
- 2.4 网络服务初始化（RTSP/SIP/RTP/NPQ）
- 2.5 存储系统初始化（init_stor_system）
- 2.6 初始化依赖关系图与时间线

### 第3章：DSP 编解码管线
- 3.1 DSP 架构总览（Davinci 平台）
- 3.2 视频编码管线（H.264/H.265/MPEG4）
  - 3.2.1 编码参数配置（STREAMPARAMS, ENC_TYPE_PARAM）
  - 3.2.2 帧结构（GROUP_HEADER, FRAME_HEADER, MEGA_STREAM_HEADER）
  - 3.2.3 码率控制（VBR/CBR, quantization）
  - 3.2.4 隐私掩码与ROI
- 3.3 音频编码管线（G.711/G.722/AAC/G.726）
  - 3.3.1 音频参数（AUDIOPARAMS）
  - 3.3.2 音频编码类型与码率
  - 3.3.3 音频采样率/通道/位深配置
- 3.4 DSP 共享内存机制（DSPSHAREDATA, DSP_TO_HOST_DATA, HOST_TO_DSP_DATA）
- 3.5 DSP 命令与回调机制
- 3.6 视频加密与安全（AES, 水印, RSA签名）

### 第4章：网络协议栈（多层）
- 4.1 网络协议全景图
- 4.2 预览通道层（SDK 二进制协议）
  - 4.2.1 NETCMD_HEADER 格式
  - 4.2.2 预览命令（NETCMD_PREVIEW）
  - 4.2.3 对讲命令（NETCMD_VOICE_TALK）
- 4.3 RTSP 控制层
  - 4.3.1 RTSP Server/Client 双模式
  - 4.3.2 SDP 协商
  - 4.3.3 通道与 Track 管理（VIDEO/AUDIO/METADATA/AUDIOBACK）
- 4.4 RTP/RTCP 传输层
  - 4.4.1 RTP 打包（PS 封装）
  - 4.4.2 RTCP 控制报告
  - 4.4.3 SRTP 加密
- 4.5 ONVIF/ISAPI 开放接口层
- 4.6 SIP 信令层（可视对讲）
- 4.7 云连接层（萤石 Ezviz）
- 4.8 WebSocket 与 Web 推送层
- 4.9 Ehome/ISUP 上行协议

### 第5章：QoS 保障体系（NPQ）
- 5.1 NPQ 架构总览
- 5.2 NACK 重传机制
  - 5.2.1 NACK 请求/响应流程
  - 5.2.2 NACK WiFi 自适应模式
- 5.3 FEC 前向纠错
  - 5.3.1 关键帧/非关键帧 FEC 比例
  - 5.3.2 FEC 编码/解码
- 5.4 去抖动（Jitter Buffer / NETEQ）
  - 5.4.1 视频去抖动
  - 5.4.2 音频去抖动（G.722.1 NETEQ）
- 5.5 带宽自适应
  - 5.5.1 TCC (Transport-Level Congestion Control)
  - 5.5.2 REMB (Receiver Estimated Maximum Bitrate)
  - 5.5.3 带宽探测（Bandwidth Probing）
  - 5.5.4 码率分配策略
- 5.6 Pacing 流量整形
  - 5.6.1 Pacing 队列与码率控制
  - 5.6.2 多路流码率分配
- 5.7 PLI/FIR 关键帧请求
- 5.8 音视频同步
- 5.9 NPQ 状态监控（NPQ_STAT 详解）
- 5.10 NPQ 发送端/接收端 API 使用

### 第6章：存储系统
- 6.1 storLib 架构总览
- 6.2 设备管理（Device/DeviceManage）
  - 6.2.1 SATA 硬盘
  - 6.2.2 外置设备（USB/SD）
- 6.3 文件管理（FileManage）
- 6.4 数据服务层（DataService）
  - 6.4.1 Record 录像服务
  - 6.4.2 Schedule 计划任务
  - 6.4.3 Video/Pic 数据管理
  - 6.4.4 DataSearch 数据搜索
- 6.5 录像规划与执行
  - 6.5.1 连续录像
  - 6.5.2 移动侦测录像
  - 6.5.3 报警录像
  - 6.5.4 事件录像
- 6.6 录像回放数据流
- 6.7 视频下载（TF卡文件下载）

### 第7章：业务场景全流程 — 实时预览
- 7.1 SDK 客户端预览全流程
- 7.2 RTSP 预览全流程
- 7.3 WebSocket 预览全流程
- 7.4 萤石云预览全流程
- 7.5 多通道预览
- 7.6 主/子码流同时预览
- 7.7 预览中的 QoS 保障
- 7.8 预览控制（暂停/恢复/TEARDOWN）

### 第8章：业务场景全流程 — 录像存储
- 8.1 计划录像全流程
- 8.2 移动侦测录像全流程
- 8.3 报警录像全流程
- 8.4 录像文件结构
- 8.5 录像回放全流程
- 8.6 录像搜索与定位
- 8.7 TF卡异常处理

### 第9章：业务场景全流程 — 可视对讲（音视频通话）
- 9.1 SIP 信令交互流程
- 9.2 媒体流建立（RTP/RTCP）
- 9.3 音视频编解码切换
- 9.4 对讲中的 QoS 保障
- 9.5 对讲会话管理
- 9.6 对讲中断与恢复
- 9.7 室内机-门口机-手机 三方通话
- 9.8 对讲录音与存储

### 第10章：业务场景全流程 — 语音对讲（单向）
- 10.1 SDK 语音对讲
- 10.2 RTSP 语音对讲
- 10.3 广播系统（实时广播/定时广播/RTP广播寻呼）
- 10.4 报警语音

### 第11章：数据流全景图
- 11.1 视频数据流（传感器 → DSP → 网络/存储）
- 11.2 音频数据流（麦克风 → DSP → 网络/存储）
- 11.3 控制数据流（客户端 → 协议层 → 业务层 → 硬件）
- 11.4 事件数据流（硬件 → DAL → 业务 → 上传）
- 11.5 配置数据流（客户端 → 配置层 → 数据库 → 运行时）

### 第12章：模块间关系与交互
- 12.1 模块依赖关系图
- 12.2 IPC 消息总线（opdevsdk pub-sub + req-resp）
- 12.3 消息队列机制（POSIX mq）
- 12.4 共享内存机制
- 12.5 事件驱动模型
- 12.6 跨模块线程协作关系

### 第13章：设计模式与关键技术
- 13.1 分层设计原则
- 13.2 能力检测机制（check_capa_support）
- 13.3 配置驱动设计
- 13.4 模块化启动模型
- 13.5 线程优先级与栈管理
- 13.6 安全机制（AES加密, SRTP, 水印, RSA签名）
- 13.7 多平台适配策略

### 附录
- A. 编解码类型速查表
- B. 端口与协议对照表
- C. 帧结构完整定义
- D. NPQ API 完整参考
- E. 线程-模块-栈大小速查表

---

## 执行步骤
1. 按章节顺序逐章写入 `av-pipeline-detailed.md`
2. 每章完成后确认文件已持久化
3. 每章之间读取已写内容确认完整性，再继续下一章
4. 如果某章较长，分多次写入（先写前半段，再追加后半段）
5. 注意上下文限制，内容过多时提醒用户 compact

## 输出文件
- 目标路径: `/data1/luhonghao/codes/rtcp-lab/doc-lu/docs-kv6/av-pipeline-detailed.md`
