# FFmpeg 8.1.2 核心业务流完整表格

> 三层结构映射:fftools(命令行工具层)→ 库公共 API → 库内部实现。
> 调用链每个步骤单独换行,便于阅读。

## 一、命令行解析与初始化

| 阶段 | fftools 涉及文件 | fftools 调用链 | 库公共 API | 库 API 涉及文件 | 库内部实现调用链 | 库内部实现涉及文件 | 描述和备注 |
|---|---|---|---|---|---|---|---|
| 1. 程序入口 | `ffmpeg.c` | `main`<br>→ `avdevice_register_all`<br>→ `avformat_network_init`<br>→ `sch_alloc`<br>→ `ffmpeg_parse_options`<br>→ `transcode` | `avdevice_register_all`<br>`sch_alloc` | `libavdevice/avdevice.h`<br>`fftools/ffmpeg_sched.h` | `avdevice_register_all` → 注册各设备 demuxer/muxer | `libavdevice/alldevices.c`<br>`libavformat/allformats.c` | 初始化设备、网络、创建 Scheduler,进入转码主流程。 |
| 2. 选项解析 | `ffmpeg_opt.c`<br>`cmdutils.c` | `ffmpeg_parse_options`<br>→ `open_input_file`<br>→ `open_output_file`<br>→ `opt_audio_codec`<br>→ `opt_video_codec`<br>→ `sch_add_demux`<br>→ `sch_add_mux`<br>→ `sch_add_dec/enc/filtergraph`<br>→ `sch_connect` | `avformat_open_input`<br>`avformat_alloc_output_context2` | `libavformat/avformat.h` | `avformat_open_input` → `init_input` → `av_probe_input_format2`(按扩展名/内容探测 demuxer) | `libavformat/utils.c`<br>`libavformat/demux.c`<br>`libavformat/format.c` | 解析 `-i`/输出/流映射/编解码选项,建立 Scheduler 有向图节点并连接。 |

## 二、媒体接收(输入/解封装)

| 阶段 | fftools 涉及文件 | fftools 调用链 | 库公共 API | 库 API 涉及文件 | 库内部实现调用链 | 库内部实现涉及文件 | 描述和备注 |
|---|---|---|---|---|---|---|---|
| 3. 流信息探测 | `ffmpeg_opt.c` | `avformat_open_input`<br>→ `avformat_find_stream_info`<br>→ `avcodec_parameters_to_context` | `avformat_find_stream_info`<br>`avcodec_parameters_to_context` | `libavformat/avformat.h`<br>`libavcodec/codec_par.h` | `avformat_find_stream_info` → `try_decode_frame` → 解码少量帧填充 `AVStream.codecpar` | `libavformat/demux.c`<br>`libavcodec/utils.c` | 读取头部数据解码探测,得到每条流的编码参数、时间基、宽高。 |
| 4. 解封装读包 | `ffmpeg_demux.c` | `demux_send`<br>→ `av_read_frame`<br>→ `input_packet_process`<br>→ `ts_fixup`<br>→ `sch_demux_send` | `av_read_frame` | `libavformat/avformat.h` | `av_read_frame` → `read_frame_internal` → `AVInputFormat.read_packet` → 返回 `AVPacket` | `libavformat/demux.c`<br>`libavformat/avidec.c`(示例 demuxer) | demux 线程逐包读取,做时间戳修正、丢弃无用流、demux 级 bsf,经 thread_queue 送解码线程。 |

## 三、解码

| 阶段 | fftools 涉及文件 | fftools 调用链 | 库公共 API | 库 API 涉及文件 | 库内部实现调用链 | 库内部实现涉及文件 | 描述和备注 |
|---|---|---|---|---|---|---|---|
| 5. 解码器初始化 | `ffmpeg_dec.c` | `dec_alloc`<br>→ `avcodec_find_decoder`<br>→ `avcodec_alloc_context3`<br>→ `avcodec_open2` | `avcodec_find_decoder`<br>`avcodec_alloc_context3`<br>`avcodec_open2` | `libavcodec/codec.h`<br>`libavcodec/avcodec.h` | `avcodec_open2` → `ff_decode_init` → `AVCodec.init`(按 codec_id 查注册表) | `libavcodec/utils.c`<br>`libavcodec/decode.c`<br>`libavcodec/allcodecs.c` | 按 `AVCodecParameters.codec_id` 查找解码器,分配上下文并打开。 |
| 6. 解码 | `ffmpeg_dec.c` | `decoder_thread`<br>→ `avcodec_send_packet`<br>→ `avcodec_receive_frame`<br>→ `video_frame_process` | `avcodec_send_packet`<br>`avcodec_receive_frame` | `libavcodec/avcodec.h` | `avcodec_send_packet` → `decode_simple_internal` → `codec->decode` → `avcodec_receive_frame` → `decode_simple_receive_frame` | `libavcodec/decode.c`<br>`libavcodec/h264dec.c`(示例) | 解码线程,新式 send/receive API;支持硬件加速(hwaccel 取回 GPU 帧)。 |

## 四、滤镜处理

| 阶段 | fftools 涉及文件 | fftools 调用链 | 库公共 API | 库 API 涉及文件 | 库内部实现调用链 | 库内部实现涉及文件 | 描述和备注 |
|---|---|---|---|---|---|---|---|
| 7. 滤镜图构建 | `ffmpeg_filter.c` | `graph_parse`<br>→ `avfilter_graph_create_filter`<br>→ `avfilter_graph_config` | `avfilter_graph_create_filter`<br>`avfilter_graph_config` | `libavfilter/avfilter.h` | `avfilter_graph_create_filter` → 按名字查 `AVFilter` 注册表 → 分配 `AVFilterContext` | `libavfilter/avfilter.c`<br>`libavfilter/allfilters.c` | 解析 `-vf/-af` 字符串,构建滤镜图,协商各 link 的像素/采样格式。 |
| 8. 滤镜执行 | `ffmpeg_filter.c` | `filter_thread`<br>→ `av_buffersrc_add_frame`<br>→ `av_buffersink_get_frame` | `av_buffersrc_add_frame`<br>`av_buffersink_get_frame` | `libavfilter/buffersrc.h`<br>`libavfilter/buffersink.h` | `av_buffersrc_add_frame` → 滤镜图逐级处理 → `av_buffersink_get_frame` 取结果 | `libavfilter/buffersrc.c`<br>`libavfilter/vf_scale.c`(示例)<br>`libavfilter/avfilter.c` | 缩放、色彩转换、裁剪、特效等;内部可调用 swscale/swresample。 |

## 五、编码

| 阶段 | fftools 涉及文件 | fftools 调用链 | 库公共 API | 库 API 涉及文件 | 库内部实现调用链 | 库内部实现涉及文件 | 描述和备注 |
|---|---|---|---|---|---|---|---|
| 9. 编码器初始化 | `ffmpeg_enc.c` | `enc_open`<br>→ `avcodec_find_encoder`<br>→ `avcodec_alloc_context3`<br>→ `avcodec_open2` | `avcodec_find_encoder`<br>`avcodec_open2` | `libavcodec/codec.h`<br>`libavcodec/avcodec.h` | `avcodec_open2` → `ff_encode_init` → `AVCodec.init` | `libavcodec/utils.c`<br>`libavcodec/encode.c`<br>`libavcodec/libx264.c`(示例) | 按输出编码器名/ID 查找并打开编码器。 |
| 10. 编码 | `ffmpeg_enc.c` | `encode_frame`<br>→ `avcodec_send_frame`<br>→ `avcodec_receive_packet` | `avcodec_send_frame`<br>`avcodec_receive_packet` | `libavcodec/avcodec.h` | `avcodec_send_frame` → `encode_simple_internal` → `codec->encode` → `avcodec_receive_packet` | `libavcodec/encode.c`<br>`libavcodec/h264enc.c`(示例) | 编码线程,统计帧率/码率,输出 `AVPacket`。 |

## 六、封装/输出

| 阶段 | fftools 涉及文件 | fftools 调用链 | 库公共 API | 库 API 涉及文件 | 库内部实现调用链 | 库内部实现涉及文件 | 描述和备注 |
|---|---|---|---|---|---|---|---|
| 11. 封装写包 | `ffmpeg_mux.c` | `muxer_thread`<br>→ `avformat_write_header`<br>→ `av_interleaved_write_frame`<br>→ `av_write_trailer` | `avformat_write_header`<br>`av_interleaved_write_frame`<br>`av_write_trailer` | `libavformat/avformat.h` | `av_interleaved_write_frame` → `write_packet` → `AVOutputFormat.write_packet` → 写容器字节流 | `libavformat/mux.c`<br>`libavformat/avienc.c`(示例)<br>`libavformat/url.c` | mux 线程写输出,支持流复制(`of_streamcopy`,不经编解码直接拷贝)。 |

## 七、播放与分析(ffplay / ffprobe)

| 阶段 | fftools 涉及文件 | fftools 调用链 | 库公共 API | 库 API 涉及文件 | 库内部实现调用链 | 库内部实现涉及文件 | 描述和备注 |
|---|---|---|---|---|---|---|---|
| 12. 播放器 | `ffplay.c`<br>`ffplay_renderer.c` | `main`<br>→ `avformat_open_input`<br>→ `av_read_frame`<br>→ `avcodec_send_packet`<br>→ `avcodec_receive_frame`<br>→ `SDL_UpdateTexture` | `avformat_open_input`<br>`av_read_frame`<br>`avcodec_send_packet`<br>`avcodec_receive_frame` | `libavformat/avformat.h`<br>`libavcodec/avcodec.h` | 解码→`AVFrame`→SDL 渲染/音频输出(含音视频同步) | `ffplay.c`(SDL 播放循环)<br>`libavcodec/decode.c` | 极简播放器,SDL2 渲染,内置音视频时钟同步。 |
| 13. 媒体分析 | `ffprobe.c` | `main`<br>→ `avformat_open_input`<br>→ `avformat_find_stream_info`<br>→ `av_read_frame`<br>→ 输出 JSON/XML/CSV | `avformat_open_input`<br>`avformat_find_stream_info`<br>`av_read_frame` | `libavformat/avformat.h` | 遍历 `AVStream`/`AVPacket` 元数据 | `ffprobe.c`(writer 输出层) | 分析工具,输出流信息、包信息、帧信息到多种格式。 |

---

## 核心数据流转(贯穿全表)

```
容器字节流
  ↓ av_read_frame            [libavformat demuxer]
AVPacket
  ↓ avcodec_send_packet      [libavcodec decoder]
AVFrame
  ↓ av_buffersrc_add_frame   [libavfilter graph]
AVFrame
  ↓ avcodec_send_frame       [libavcodec encoder]
AVPacket
  ↓ av_interleaved_write_frame [libavformat muxer]
容器字节流
```

**关键点**:整个管线由 `ffmpeg_sched.c` 的 **Scheduler** 以多线程方式驱动,各阶段(demux/dec/filter/enc/mux)是独立线程,通过 `thread_queue`/`sync_queue` 传递数据并同步。核心数据对象 `AVPacket`(压缩包)与 `AVFrame`(未压缩帧)在库间流转。