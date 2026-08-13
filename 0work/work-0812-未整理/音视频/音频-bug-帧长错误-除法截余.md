

<think>
<think>
1. **分析用户请求：**
    *   **输入：** 一条特定的警告日志信息（`Plugin Ao send slow!!! cur:147453, last:147428, gap:25 uFrmTime:16 640 16000 1 16!!!`）以及生成该信息的 C 代码片段。
    *   **问题：** "为什么\" (Why?) —— 用户想知道*为什么*会触发这条警告，以及日志中的数字代表什么含义，可能侧重于底层逻辑和音频参数。

2. **解构代码与日志：**

    *   **日志：**
        *   `cur:147453`：当前时间（`curTime`），可能以毫秒为单位。
        *   `last:147428`：上一帧的时间（`lastTime`），以毫秒为单位。
        *   `gap:25`：`curTime` 和 `lastTime` 之间的差值（`curTime - lastTime`）。
        *   `uFrmTime:16`：计算出的单帧时长（`uFrmTime`），以毫秒为单位。
        *   `640`：`uFrameLen`（帧长度，可能是每帧的采样点数或字节数——需要结合其他参数进一步确认）。
        *   `16000`：`uSampleRate`（采样率，Hz）。
        *   `1`：`uSoundMode`（声音模式，1 = 单声道，2 = 立体声）。
        *   `16`：`uBitWidth`（位深，每个采样的位数）。

    *   **代码逻辑：**
        *   `curTime = base_time_get();` -> 获取当前时间戳。
        *   `uFrmTime` 计算：
            ```c
            uFrmTime = (UINT64)uFrameLen / (uSampleRate/1000) / uSoundMode / (uBitWidth*8)
            ```
            *等等，让我仔细看看用户的代码片段：*
            ```c
            const UINT64 uFrmTime = (UINT64)pstAoDevInfo->stAudResFrame.stBaseAttr.uFrameLen \
                    /(pstAoDevInfo->stAudResFrame.stBaseAttr.uSampleRate/1000) \
                    /pstAoDevInfo->stAudResFrame.stBaseAttr.uSoundMode \
                    /pstAoDevInfo->stAudResFrame.stBaseAttr.uBitWidth*8; // ms
            ```
            *让我根据标准的音频公式重新评估 `uFrmTime` 的计算。*
            帧时长（毫秒）= `(FrameLen_in_Bytes * 1000) / (SampleRate * Channels * BytesPerSample)`
            让我们代入日志中的数字来反推 `uFrameLen` 代表什么：
            `16 = 640 / (16000/1000) / 1 / (16*8)` -> `16 = 640 / 16 / 1 / 128` -> `16 = 40 / 128` -> `16 = 0.3125`。这算不通！
            让我重读一下代码：`/pstAoDevInfo->stAudResFrame.stBaseAttr.uBitWidth*8`
            由于 C 语言中的运算符优先级，`/ uBitWidth * 8` 等同于 `(/ uBitWidth) * 8`。
            让我们重新计算：`16 = 640 / 16 / 1 / 16 * 8` -> `16 = 40 / 1 / 16 * 8` -> `16 = 40 / 16 * 8` -> `16 = 2.5 * 8` -> `16 = 20`。还是算不通。
            让我们再看看这个公式。也许 `uFrameLen` 是以*位*或*采样点*为单位，而不是字节？
            如果 `uFrameLen` 是采样点数：640 个采样点 @ 16000 Hz = 640 / 16000 秒 = 0.04 秒 = 40 毫秒。与 16 毫秒不匹配。
            如果 `uFrameLen` 是字节：640 字节。16000 Hz，16 位，单声道。1 毫秒内的字节数 = 16000 * 1 * (16/8) / 1000 = 32 字节/毫秒。640 / 32 = 20 毫秒。与 16 毫秒不匹配。
            让我们重新阅读代码的数学计算：
            `640 / (16000/1000) / 1 / 16 * 8`
            `640 / 16 / 1 / 16 * 8`
            `40 / 1 / 16 * 8`
            `40 / 16 * 8`
            `2 * 8 = 16`。
            等等！C 语言中的整数除法：`40 / 16 = 2`。然后 `2 * 8 = 16`。
            啊！`uFrmTime` 的计算公式存在一个运算符优先级的 Bug，或者至少是非常不直观的写法。
            让我们写出预期的物理公式：
            时长 (秒) = `总字节数 / (采样率 * 声道数 * 位深 / 8)`
            时长 (毫秒) = `总字节数 * 1000 / (采样率 * 声道数 * 位深 / 8)`
            = `(uFrameLen * 1000) / (uSampleRate * uSoundMode * uBitWidth / 8)`
            让我们看看代码是怎么写的：
            `uFrameLen / (uSampleRate/1000) / uSoundMode / uBitWidth * 8`
            让我们重新排列代码的公式：
            = `uFrameLen * 1000 / uSampleRate / uSoundMode / uBitWidth * 8`
            = `(uFrameLen * 1000 * 8) / (uSampleRate * uSoundMode * uBitWidth)`
            = `(uFrameLen * 8000) / (16000 * 1 * 16)`
            = `640 * 8000 / 256000`
            = `5120000 / 256000 = 20`。
            等等，为什么日志显示 `uFrmTime:16`？
            因为 C 语言整数运算的求值顺序是从左到右的！
            `640 / 16 = 40`
            `40 / 1 = 40`
            `40 / 16 = 2`  <-- 整数除法截断！40/16 是 2.5，截断为 2。
            `2 * 8 = 16` <-- 乘以 8。
            所以，`uFrmTime` 的计算由于整数除法截断而存在严重的精度丢失，但*计算结果*是 16。

            让我们验证一下真实的物理时长：
            640 字节。16000 Hz，16 位，单声道（1 声道）。
            每个采样的字节数 = 16/8 = 2 字节。
            1 毫秒内的采样点数 = 16000 / 1000 = 16 个采样点。
            1 毫秒内的字节数 = 16 * 2 * 1 = 32 字节。
            640 字节对应的时长 = 640 / 32 = 20 毫秒。
            所以*真实的*帧时长是 20 毫秒，但*计算出的* `uFrmTime` 是 16 毫秒，因为整数除法 `40 / 16 = 2`。

        *   **触发条件：**
            ```c
            if((curTime-lastTime > uFrmTime+2) && (curTime-lastTime < 300) )
            ```
            *   `curTime - lastTime`：两帧之间的实际时间间隔（`gap`）。日志显示为 25。
            *   `uFrmTime + 2`：预期的帧时长加上 2 毫秒的容差。16 + 2 = 18。
            *   `25 > 18`：为真。实际间隔（25 毫秒）大于允许的阈值（18 毫秒）。
            *   `curTime - lastTime < 300`：25 < 300。为真。这防止了在系统休眠或时间戳回绕时触发警告。
            *   结论：触发了警告，因为向音频输出（AO）插件发送帧的时间间隔为 25 毫秒，这超过了计算出的阈值 18 毫秒（计算出的帧时长 16 毫秒 + 2 毫秒缓冲）。

3. **综合解释：**
    *   **直接回答：** 解释*为什么*会触发警告。系统预期帧的到达间隔大约为 `uFrmTime`（16 毫秒），容差为 2 毫秒。但实际间隔（`gap`）是 25 毫秒。25 > 16 + 2，因此它认为音频发送“慢”了。
    *   **日志参数解析：** 逐一拆解日志中的数字，以便用户理解其含义。
        *   `cur`、`last`、`gap`：时间戳。
        *   `uFrmTime`：计算出的帧时长。
        *   `640`、`16000`、`1`、`16`：音频参数。
    *   **计算 Bug（关键发现）：** 指出 `uFrmTime` 计算中存在的严重 Bug。
        *   展示数学计算：`640 / 16 / 1 / 16 * 8`。
        *   解释整数截断：`40 / 16 = 2`，`2 * 8 = 16`。
        *   解释真实的物理时长：640 字节 @ 16k/16bit/Mono 实际上是 20 毫秒，而不是 16 毫秒。
        *   这意味着阈值被人为地降低了，使得警告更容易被触发。
    *   **为什么音频会被判定为“慢”？（根本原因）：** 即使修正了 Bug（阈值变为 20+2=22 毫秒），25 毫秒的间隔仍然会触发它。为什么实际间隔会是 25 毫秒？
        *   线程调度延迟（操作系统未能及时唤醒线程）。
        *   上游数据处理瓶颈（编码/解码耗时过长）。
        *   锁竞争（等待互斥锁/自旋锁）。
        *   中断延迟。
    *   **建议：** 如何修复代码和问题。
        *   修复 `uFrmTime` 中的整数除法 Bug（重新排列操作顺序或使用浮点数/先乘法）。
        *   调查上游延迟。

4. **起草回复（为提高清晰度进行迭代完善）：**
    *   *语气：* 专业的、分析性的、有帮助的。
    *   *结构：*
        1.  直接回答（为什么会触发）。
        2.  日志参数解析。
        3.  代码 Bug 分析（关于整数除法的重要发现）。
        4.  音频延迟的根本原因。
        5.  代码修复建议。

5. **完善数学/代码解释（起草过程中的自我纠正）：**
    让我仔细检查一下 `uFrameLen` 的单位。是字节吗？是的，640 字节是 16k/16bit/Mono 下 20 毫秒音频的标准缓冲区大小。
    代码：`uFrameLen / (uSampleRate/1000) / uSoundMode / uBitWidth*8`
    等等，`uBitWidth*8`？如果 `uBitWidth` 是 16，`16*8 = 128`。这意味着 `uBitWidth` 实际上代表的是**字节**，而不是位！
    让我们重新阅读结构体：`uBitWidth`。通常，在音频 API（如 ALSA 或海思 MPP）中，`uBitWidth` 是以位为单位（16、24、32）。但看看公式：
    如果 `uBitWidth` 是位（16），`16*8 = 128`。`640 / 16 / 1 / 128` = 0.3。说不通。
    如果 `uBitWidth` 是字节（2），`2*8 = 16`。`640 / 16 / 1 / 2 * 8` = `40 / 1 / 2 * 8` = `20 * 8` = 160。说不通。
    等等，让我们看看 C 语言的运算符优先级：
    `/ uBitWidth * 8` 等同于 `(/ uBitWidth) * 8`。
    如果 `uBitWidth` 是 16（位）：
    `640 / 16 / 1 / 16 * 8` = `40 / 1 / 16 * 8` = `40 / 16 * 8` = `2 * 8 = 16`。
    好的，我之前的数学计算是正确的。代码字面上执行了 `40 / 16`，由于整数截断变成了 `2`，然后 `2 * 8 = 16`。
    正确的公式应该是：
    `uFrameLen * 8000 / (uSampleRate * uSoundMode * uBitWidth)`
    = `640 * 8000 / (16000 * 1 * 16)`
    = `5120000 / 256000 = 20`。
    所以 `uFrmTime` 应该是 20，但代码计算为 16。这绝对是一个 Bug。

6. **最终确定输出结构（中文）：**
    *   **一、直接原因**：gap(25) > uFrmTime(16) + 2。
    *   **二、日志参数解析**：逐个解释数字含义。
    *   **三、代码隐藏的严重Bug（重点）**：详细推演整数除法截断导致 uFrmTime 计算错误的过程（20ms算成了16ms）。
    *   **四、为什么实际间隔会达到25ms？**：分析系统调度、上游卡顿等原因。
    *   **五、修复建议**：给出正确的计算公式代码。

7. **对照用户上下文进行回顾：** 用户之前问过关于 `%lld` 和 `%ld` 的问题。当前的代码使用了 `%llu` 和 `%u`。这与格式说明符的上下文一致。分析是合理的。继续生成回复。
</think>这条日志触发的直接原因是：**音频帧的实际发送间隔（25ms）超过了代码计算出的理论帧长加上2ms的容差（16ms + 2ms = 18ms）。**

但这段代码中隐藏了一个**非常严重的整数除法截断Bug**，导致理论帧长被算错，从而让这个警告更容易被误触发。下面为你详细拆解：

---

### 一、 日志参数解析
根据你的日志：`cur:147453, last:147428, gap:25 uFrmTime:16 640 16000 1 16!!!`

*   `cur` (147453): 当前时间戳
*   `last` (147428): 上次发送时间戳
*   `gap` (25): 实际发送间隔 = 147453 - 147428 = 25ms
*   `uFrmTime` (16): 代码计算出的单帧理论时长 = 16ms
*   后面的 `640 16000 1 16` 分别对应：
    *   `uFrameLen` = 640 (帧长度，通常指字节数)
    *   `uSampleRate` = 16000 (采样率 16kHz)
    *   `uSoundMode` = 1 (声道数，1为单声道)
    *   `uBitWidth` = 16 (位深，16bit)

### 二、 代码隐藏的严重Bug（为什么 uFrmTime 是 16？）

根据音频物理公式，这帧音频的真实时长应该是：
> 时长 = 数据量 / 比特率 = 640字节 / (16000采样 * 1声道 * 2字节) = 640 / 32000 = **0.02秒 = 20ms**

**但代码算出来是 16ms，为什么？**

问题出在 C 语言的**整数除法截断**和**运算符优先级**上。来看你的代码：
```c
const UINT64 uFrmTime = (UINT64)pstAoDevInfo->stAudResFrame.stBaseAttr.uFrameLen \
        /(pstAoDevInfo->stAudResFrame.stBaseAttr.uSampleRate/1000) \
        /pstAoDevInfo->stAudResFrame.stBaseAttr.uSoundMode \
        /pstAoDevInfo->stAudResFrame.stBaseAttr.uBitWidth*8; // ms
```
代入实际参数，运算过程如下：
1. `640 / (16000/1000)` = `640 / 16` = **40**
2. `40 / 1` = **40**
3. `40 / 16` = **2** （⚠️ **致命截断**：整数除法 40/16 本应是 2.5，但 C 语言会直接截断小数部分变成 2）
4. `2 * 8` = **16** （⚠️ **优先级陷阱**：`/ uBitWidth * 8` 等价于 `(/ uBitWidth) * 8`，而不是 `/ (uBitWidth * 8)`）

**结论：** 因为整数除法截断，真实的 20ms 被错误计算成了 16ms。

### 三、 为什么会报 "Plugin Ao send slow"？

回到你的判断逻辑：
```c
if((curTime-lastTime > uFrmTime+2) && (curTime-lastTime < 300) )
```
1.  **错误阈值**：由于 `uFrmTime` 被算成了 16，判断条件变成了 `gap > 16 + 2`，即 `gap > 18`。
2.  **实际情况**：正常的音频帧长是 20ms。由于系统调度、内核中断或上游解码抖动，实际 `gap` 达到了 25ms，这其实是在合理的抖动范围内（25ms 仅比理论 20ms 慢了 5ms）。
3.  **误报产生**：代码拿 25ms 去和错误的阈值 18ms 比较，25 > 18，触发了警告。

如果你修正了计算公式，阈值会变成 `20 + 2 = 22ms`，此时 25ms 的抖动依然会触发警告，但这才是合理的警告（比理论慢了 5ms）。

### 四、 为什么实际间隔会达到 25ms？（系统层面）

即使修正了代码，实际音频发送间隔（gap）仍然可能超过理论值，常见原因有：
1.  **系统调度延迟**：线程在休眠或等待条件变量后被内核唤醒时，延迟了几毫秒。
2.  **上游供数慢**：解码器解码慢、网络拉流卡顿，导致 AO 插件没有及时拿到数据。
3.  **锁竞争**：获取 `pstAoDevInfo` 相关的互斥锁时被其他线程阻塞。
4.  **中断抢占**：硬中断或软中断占用了 CPU。

### 五、 修复建议

**1. 修正 `uFrmTime` 的计算公式（避免整数除法截断）：**
应该先进行乘法放大，最后再做除法，保证精度：
```c
// 正确公式： * 8000 / (SampleRate * SoundMode * BitWidth)
const UINT64 uFrmTime = (UINT64)pstAoDevInfo->stAudResFrame.stBaseAttr.uFrameLen * 8000 \
        / (pstAoDevInfo->stAudResFrame.stBaseAttr.uSampleRate \
        * pstAoDevInfo->stAudResFrame.stBaseAttr.uSoundMode \
        * pstAoDevInfo->stAudResFrame.stBaseAttr.uBitWidth); // ms
```
*代入 640 * 8000 / (16000 * 1 * 16) = 5120000 / 256000 = 20ms，结果完全正确。*

**2. 适当放宽容差：**
音频播放对抖动比较敏感，但 2ms 的容差在非实时操作系统（如 Linux 非 RT 内核）上太苛刻了。如果修正公式后依然频繁打印此警告，建议将容差 `+2` 改为 `+5` 或 `+10`：
```c
if((curTime-lastTime > uFrmTime+5) && (curTime-lastTime < 300) )
```








<think>
<think>
Thinking Process:

1.  **Analyze the Request:**
    *   Input: A log message `DSP_AO_ERROR("Plugin Ao Thr policy:%d, priority:%d!!!\n", policy, param.sched_priority);` where both `policy` and `param.sched_priority` are 0.
    *   Question: What does it mean when both are 0?
    *   Context: Previous conversation was about C programming (`%lld` vs `%ld`), audio output (AO) plugin performance issues (timing calculation bug), and now thread scheduling parameters in a DSP/Audio context.
    *   Language: Simplified Chinese (as per rules).

2.  **Identify the Technical Domain:**
    *   The log format `DSP_AO_ERROR` suggests a Digital Signal Processor (DSP) or Audio Output (AO) module within an embedded system (likely Linux-based given the previous context of `printf`, `UINT64`, etc.).
    *   The variables `policy` and `param.sched_priority` strongly indicate POSIX thread scheduling attributes (`pthread_attr_t`, `struct sched_param`).
    *   This is about Linux/POSIX thread scheduling policies and priorities.

3.  **Analyze the Values (0, 0):**
    *   `policy`: In POSIX threads (`pthread`), scheduling policies are defined in `<sched.h>`.
        *   `SCHED_OTHER` (or `SCHED_NORMAL`): Typically value 0. This is the standard time-sharing policy for normal threads.
        *   `SCHED_FIFO`: Real-time FIFO policy (usually value 1).
        *   `SCHED_RR`: Real-time Round-Robin policy (usually value 2).
    *   `param.sched_priority`: Priority value.
        *   For `SCHED_OTHER` (policy 0): The priority *must* be 0. You cannot set a real-time priority for a normal time-sharing thread.
        *   For `SCHED_FIFO`/`SCHED_RR`: Priority ranges from 1 to 99 (usually).

4.  **Interpret the Meaning:**
    *   **Policy 0 (`SCHED_OTHER`)**: The thread is running under the standard Linux time-sharing scheduler. It does not have real-time guarantees. It competes for CPU time with other normal processes/threads based on nice values and dynamic priorities managed by the kernel (CFS - Completely Fair Scheduler).
    *   **Priority 0**: This is the only valid priority for `SCHED_OTHER`. It doesn't mean "lowest priority" in the real-time sense, but rather "default priority" for normal threads.
    *   **Combined Meaning**: The Audio Output (AO) plugin thread is running as a **normal user-space thread**, not a real-time thread.

5.  **Evaluate the Implications (especially in Audio Context):**
    *   Audio processing often requires low latency and jitter stability.
    *   Running with `SCHED_OTHER` (0, 0) means the thread can be preempted by other processes, including system daemons, UI tasks, etc.
    *   This could explain the "Plugin Ao send slow" issue from the previous turn. If the thread isn't real-time, it might get scheduled out, causing the `gap` to increase (e.g., the 25ms vs 20ms issue).
    *   **Risk**: Potential for audio glitches, underruns, or increased latency if the system is under load.
    *   **Recommendation**: For audio threads, it's often recommended to use `SCHED_FIFO` or `SCHED_RR` with a moderate priority (e.g., 10-50) to ensure timely execution, provided the system allows it (requires `CAP_SYS_NICE` capability or root).

6.  **Draft the Response:**
    *   **Direct Answer**: Policy 0 = `SCHED_OTHER` (Normal time-sharing), Priority 0 = Default priority for this policy.
    *   **Detailed Explanation**:
        *   Explain `SCHED_OTHER` (Linux default, CFS).
        *   Explain Priority 0 constraint (must be 0 for `SCHED_OTHER`).
    *   **Impact on Audio (AO)**:
        *   No real-time guarantee.
        *   Susceptible to jitter/preemption.
        *   Link back to the previous "send slow" issue (this scheduling config might be the root cause).
    *   **Suggestions**:
        *   Consider switching to `SCHED_FIFO`/`SCHED_RR`.
        *   Mention permission requirements (root/capabilities).
        *   Mention `pthread_setschedparam`.

7.  **Refine the Language (Simplified Chinese):**
    *   Ensure technical terms are accurate (调度策略，实时优先级，时间片轮转，etc.).
    *   Keep the tone helpful and analytical.

8.  **Self-Correction/Check:**
    *   Is policy 0 always `SCHED_OTHER`? On Linux, yes (`#define SCHED_OTHER 0`). On some RTOSes, it might differ, but given the previous context (Linux-like `printf`, `UINT64`, `base_time_get`), Linux POSIX is the safest assumption. I should mention Linux specifically.
    *   Is priority 0 always default? Yes, for `SCHED_OTHER`.
    *   Does this explain the previous error? Yes, likely contributes to it.

9.  **Final Output Structure:**
    *   Core conclusion (Normal thread, not Real-time).
    *   Detailed breakdown of Policy 0 and Priority 0.
    *   Impact on Audio performance (linking to previous "slow" log).
    *   Optimization suggestions.

10. **Final Polish:** Ensure clear formatting (bolding, lists).

*(Self-Correction during drafting)*: Wait, I should check if there are any specific DSP contexts where 0 means something else. In HiSilicon Hi35xx SDKs (common in embedded video/audio), `SCHED_OTHER` is 0. In general Linux, it's 0. The log format `DSP_AO_ERROR` looks like Hisilicon or similar embedded SDK. The interpretation holds.

Let's write the response.
</think>

在 Linux/POSIX 线程调度上下文中，`policy:0` 和 `priority:0` 表示该音频线程运行在**普通时间共享模式**，**不具备实时调度保障**。

这很可能是导致你上一条日志中 `Plugin Ao send slow`（音频发送慢）的根本原因之一。

以下是详细解读：

### 1. 参数含义解析

| 参数 | 值 | 含义 | 说明 |
| :--- | :--- | :--- | :--- |
| **policy** | **0** | **`SCHED_OTHER`** | **普通调度策略**（Linux 默认）。线程由内核的完全公平调度器（CFS）管理，与其他普通进程竞争 CPU。 |
| **priority** | **0** | **默认优先级** | 对于 `SCHED_OTHER` 策略，优先级**必须为 0**。你不能为普通线程设置实时优先级（1-99）。 |

### 2. 对音频性能的影响

音频处理（AO）通常对**延迟**和**抖动**非常敏感。使用 `(0, 0)` 配置意味着：

1.  **无实时保障**：
    该线程随时可能被其他进程抢占。如果系统负载高（例如有人启动了 UI 界面、网络传输突发、日志打印过多），音频线程可能无法及时获得 CPU 时间片。
2.  **导致“发送慢”警告**：
    结合你上一条日志，理论帧长 20ms，实际间隔 25ms。这多出的 5ms 抖动，很可能是因为线程被调度器“挂起”了一会儿，没能按时醒来发送数据。
3.  **优先级竞争**：
    虽然优先级是 0，但在 `SCHED_OTHER` 下，实际调度顺序还受 `nice` 值影响。如果其他进程 `nice` 值更低（优先级更高），音频线程会被挤占。

### 3. 为什么会出现 (0, 0)？

通常有以下几种情况：
*   **默认创建**：创建线程时未显式设置调度属性，系统默认为 `SCHED_OTHER`。
*   **权限不足**：代码试图设置实时策略（如 `SCHED_FIFO`），但进程没有 `CAP_SYS_NICE` 能力（即非 root 用户），设置失败后回退到默认值。
*   **配置错误**：初始化代码中未正确填充 `struct sched_param` 或 `pthread_attr_t`。

### 4. 优化建议（解决音频卡顿/慢发）

为了保证音频流畅，建议将该线程升级为**实时线程**。

#### 方案 A：设置为 FIFO 实时策略（推荐）
修改线程创建代码，设置策略为 `SCHED_FIFO`，优先级设为中等（如 10~50）。

```c
#include <pthread.h>
#include <sched.h>

pthread_attr_t attr;
struct sched_param param;

pthread_attr_init(&attr);
// 1. 设置策略为 FIFO
pthread_attr_setschedpolicy(&attr, SCHED_FIFO); 
// 2. 设置优先级 (1-99，50 通常足够音频使用)
param.sched_priority = 50; 
pthread_attr_setschedparam(&attr, &param);
// 3. 显式声明使用继承的调度属性
pthread_attr_setinheritscheduler(&attr, PTHREAD_EXPLICIT_SCHED);

// 创建线程
pthread_create(&thread_id, &attr, ThreadFunc, NULL);
```

#### 方案 B：检查权限
如果设置失败，确保程序以 **root** 运行，或者具备 `CAP_SYS_NICE` 能力：
```bash
# 临时提权运行
sudo ./your_audio_app

# 或者设置 capability (无需 root)
sudo setcap cap_sys_nice=eip ./your_audio_app
```

#### 方案 C：调整 Nice 值（如果不允许实时策略）
如果系统禁止实时线程，至少降低 Nice 值以提高普通优先级：
```c
#include <sys/resource.h>
// 设置 nice 值为 -20 (最高普通优先级)
setpriority(PRIO_PROCESS, 0, -20); 
```

### 总结
*   **`policy:0, priority:0`** = **普通线程，无实时保障**。
*   **风险**：系统忙时容易导致音频卡顿、发送延迟（即你遇到的 `gap:25` 问题）。
*   **对策**：建议改为 **`SCHED_FIFO` + 优先级 50**，并确保有足够权限。






