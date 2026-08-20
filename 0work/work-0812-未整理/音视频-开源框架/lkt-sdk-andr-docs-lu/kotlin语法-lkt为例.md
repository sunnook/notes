# LiveKit Android SDK 源码设计分析

> 本文面向有 C/C++ 经验、但对 Kotlin/Java/Android 不太熟悉的读者，对 LiveKit Android SDK（`client-sdk-android-main`）进行专业详要的架构与实现梳理。涵盖入口、架构、文件作用、数据流图、分层控制流图、模块交互、类图、设计方式，以及完整业务流程（音频/视频）的模块间数据流与控制流，最后总结工程特点并给出 Android SDK 的通用分析思路。

> 代码引用格式为 `相对路径:行号`，可在支持的工具中点击跳转。

---

## 第 0 章 阅读指南与前置知识（给 C/C++ 背景读者）

本章把阅读本 SDK 所需的 Kotlin/Java/Android 关键概念，用 C/C++ 读者熟悉的视角快速建立起来，并讲清 Kotlin/Java 与 C++（native WebRTC）的交互边界。

### 0.1 Kotlin 速查

- **`val` / `var`**：
	-`val` 是只读引用（类似 C++ 的 `const` 局部/成员，但对象本身可变），`var` 是可变引用。
- **`data class`**：
	-自动生成 `equals/hashCode/toString/copy`，类似 C++ 中带运算符重载的 POD 结构体。如 `data class TrackBitrateInfo(val codec: String, val maxBitrate: Long)`。
- **`sealed class`**：
	-受限继承体系（类似 C++ 的"已知子类集合"），编译器能做穷尽 `when` 检查。本 SDK 大量用于事件与错误类型，如 `sealed class RoomEvent`、`sealed class TrackException`。
- **`object`**：
	-单例对象。`object LiveKit { ... }` 即进程级单例（类似 C++ 中 Meyers 单例）。
- **`companion object`**：
	-类级单例，承载类似 Java `static` 的常量与工厂方法。
- **扩展函数/扩展属性**：
	-在不继承的情况下给已有类加方法，本质是"第一个参数是接收者"的静态函数。如 `livekit-android-sdk/.../RTCEngine.kt:1539` 的 `fun LivekitRtc.ICEServer.toWebrtc()`。
- **`by` 委托**：
	-把属性或接口的实现委托给另一个对象。本 SDK 最核心的 `flowDelegate` 即属性委托（见第 12 章）。
- **`suspend` 函数 / 协程（coroutine）**：
	-可挂起的函数。类比 C++20 协程，但 Kotlin 协程有成熟的库支持。`suspend fun connect(...)` 可在内部 `await` 而不阻塞线程；`CoroutineScope` 是协程的"所有权范围"，`SupervisorJob` 是结构化并发的失败隔离单元（子协程异常不会取消兄弟）。
- **`Flow` / `StateFlow` / `SharedFlow`**：
	-协程版的"可观察流"。`StateFlow` 持有最新值（类似 C++ 中带缓存的可订阅变量），`SharedFlow` 是广播流。`collect` 即订阅。
- **`@JvmInline value class`**：
	-零分配的包装类型（编译期内联为底层类型），用于强类型 ID，如 `value class Sid(val sid: String)`。
- **`inline fun` + `contract`**：
	-内联函数并声明调用契约，让编译器做更聪明的类型推断。如 `Track.kt:198` 的 `withRTCTrack`。

### 0.2 Java 速查

- **`interface`**：
	- Java 接口，Kotlin 也用。本 SDK 中大量 `interface Factory { fun create(...): X }` 用于依赖注入工厂。
- **注解（annotation）**：`
	- @Inject`、`@Singleton`、`@AssistedInject` 等是 Dagger 注解；`@JvmStatic` 让 Kotlin 的 `object` 成员对 Java 调用方表现为静态方法。
- **泛型**：
	- 与 C++ 模板不同，Java/Kotlin 泛型是运行期擦除的（erasure）。
- **`@Volatile`**：
	- Kotlin 的 `@Volatile` 对应 Java 的 `volatile`，保证可见性但不保证复合原子性（与 C++ 的 `volatile` 语义不同，更接近 `std::atomic` 的"可见性"部分）。

### 0.3 Android 速查

- **`Context`**：
	- Android 的"环境句柄"，能访问资源、启动服务、获取系统服务。`Application` 是整个进程的 Context，`Activity` 是单个界面。本 SDK 要求传 `appContext`，并警告若不是 `Application` 可能内存泄漏（`LiveKit.kt:87`）。
- **权限**：
	- 录音/相机需运行时权限 `RECORD_AUDIO` / `CAMERA`，SDK 在创建 track 时检查（`LocalVideoTrack.kt:478`、`LocalAudioTrack.kt:229`）。
- **`Handler` / `HandlerThread`**：
	- Android 的线程消息队列。`HandlerThread` 是自带 Looper 的工作线程，`Handler` 向其投递任务。`AudioSwitchHandler` 用它保证 AudioSwitch 单线程访问（`AudioSwitchHandler.kt:218`）。
- **`SurfaceView` / `TextureView`**：
	- 两种渲染视图。SDK 提供 `SurfaceViewRenderer` / `TextureViewRenderer`，底层是 WebRTC 的 `SurfaceViewRenderer`，通过 EGL 上下文把解码后的视频帧绘制到 Surface。
- **`EglBase`**：
	- WebRTC 对 OpenGL ES 上下文的封装，视频渲染与某些 GPU 编解码需要它。
- **`MediaProjection`**：
	- 屏幕录制权限与数据源，`LocalScreencastVideoTrack` 依赖它。
- **`AudioManager`**：
- 音频焦点（audio focus）、音频模式（MODE_IN_COMMUNICATION）、路由（扬声器/听筒/蓝牙）。

### 0.4 Kotlin ↔ Java 互操作

本 SDK 是纯 Kotlin 写的，但对外暴露 Java 友好 API：
- `@JvmStatic`：
	- `LiveKit.kt:40` 的 `var loggingLevel` 加了 `@JvmStatic`，Java 代码可 `LiveKit.setLoggingLevel(...)`。
- `@JvmInline value class`：
	- 对 Java 表现为普通类型。
- `null` 平台类型：
	- Kotlin 的可空 `String?` 对 Java 是平台类型，SDK 用 `@Nullable`/`@NonNull` 注解约束。
- `kotlin.reflect`：
	- 运行期反射，`FlowDelegate.kt:48` 用 `KProperty0.delegate` 反射拿到属性背后的 `StateFlow`，这是 `@FlowObservable` 机制的关键（见第 12 章）。



## 1. Kotlin 编码规范（官方 Kotlin / Android Kotlin 规范）

**大写开头 = 类型（类/接口）；小写开头 = 变量/函数** 是社区约定，不是语法规则。写错不会编译报错，但可读性直接爆炸。

 **快速记忆表格**

| 东西                | 命名约定             | 是否语法强制 |
| ----------------- | ---------------- | ------ |
| class / interface | PascalCase 首字母大写 | ❌ 仅约定  |
| 普通变量、函数、成员属性      | camelCase 首字母小写  | ❌ 仅约定  |
| const val 编译期常量   | ALL_UPPER_SNAKE  | ❌ 仅约定  |
|                   |                  |        |

> 这是**编码约定（convention），不是语法强制**。编译器不会报错，只是行业规范。

1. **类、接口、枚举、对象类型：大驼峰 `PascalCase`，首字母大写**
```kotlin
class RoomOptions    // ✅ 规范
class roomOptions    // 语法允许，但所有人都会认为写得烂
```
包括：`interface LiveKitComponent`，编译产出 `DaggerLiveKitComponent` 也遵守这个。

2. **变量、函数、属性：小驼峰 `camelCase`，首字母小写**
```kotlin
val ctx
val appContext
fun create()
```

### 哪些例外（语法允许，约定特殊）
- **常量（`const val`）**：全大写下划线分隔
```kotlin
const val MAX_RETRY_COUNT = 5
```
- 单例 `object`（Kotlin的对象声明，等价单例类），同样首字母大写。

> ⚠️ 语法层面：Kotlin**完全不强制大小写**。
> 下面代码编译可以跑，但是违反团队规范：
```kotlin
class badClass {}    // 语法合法，规范错误
val BadVariable = 1  // 语法合法，规范错误
```

对比C++：
C++也只是约定，编译器不强制；很多C++团队：类大驼峰，变量小驼峰/下划线，常量全大写。



## 2. 以livekit 为例

入口是 `LiveKit` 单例对象（`LiveKit.kt:34`）：

	静态工厂方法，**创建 LiveKit `Room` 对象**。
	`Room` 对应 RTC 房间实例，等价于 C++ 里 `std::unique_ptr<Room>` 工厂函数，不直接 new，走 Dagger 依赖注入框架构建。

`LiveKit.create()` 做三件事：构建 Dagger 依赖图 → 用工厂创建 `Room` → 应用 `RoomOptions`。

```kotlin
object LiveKit {
    
    fun create(
    appContext: Context, 
    options: RoomOptions = RoomOptions(), 
    overrides: LiveKitOverrides = LiveKitOverrides()
    ): Room
}
  
/**  
 * Create a Room object. */
fun create(  
    appContext: Context,  
    options: RoomOptions = RoomOptions(),  
    overrides: LiveKitOverrides = LiveKitOverrides(),  
): Room {  
    // 1.拿到编译器生成的Factory对象
    val ctx = appContext.applicationContext  
  
    if (ctx !is Application) {  
        LKLog.w 
        { "Application context was not found, this may cause memory leaks." }  
    }  
  
    // 2.调用factory.create()，传入外部必须的外部依赖 ctx、overrides 
    //   内部new出DaggerLiveKitComponent容器实例，内部把所有底层依赖全部装配完成
    val component = DaggerLiveKitComponent  
        .factory()  
        .create(ctx, overrides)  

    // 3.从容器取出已经装配完成的 RoomFactory  component.roomFactory()
    // 4.工厂创建Room对象，Room内部所需要的WebRTC、音频模块全部已经DI注入好了
    val room = component.roomFactory().create(ctx)  
    
    // 5.业务参数 RoomOptions 是运行时参数，Dagger不处理，手动set进去
    room.setRoomOptions(options)  
  
    return room  
}
```

```kotlin

fun create( 
    appContext: Context,  // Android 上下文，类比 C++ 传入环境 / 运行时句柄。
    options: RoomOptions = RoomOptions(),  // 默认参数, 房间配置：视频编码、音频、降噪、比特率等
    overrides: LiveKitOverrides = LiveKitOverrides(),  // 依赖注入覆盖配置，**用来替换内部默认实现类**
): Room 
{ 
    val ctx = appContext.applicationContext   // 强制拿 Application 全局上下文
    if (ctx !is Application) 
    {
        LKLog.w 
        { "Application context was not found, this may cause memory leaks." } 
    } 

    val component = DaggerLiveKitComponent 
    .factory() // Component 工厂，用来传入外部依赖（这里是 Android Context、overrides）
    .create(ctx, overrides)   // 实例化整个 IoC 容器，把全局上下文、自定义覆盖配置灌进去

    // `component.roomFactory()`：
    //             从 IoC 容器取出 `RoomFactory` 对象。工厂类，专门生产 Room 实例。
    // `.create(ctx)`：调用工厂方法真正构建 Room 对象。
    val room = component.roomFactory().create(ctx) 
    room.setRoomOptions(options) 

    return room 
}

```


# 问题拆解
源码再贴一遍，方便对照：
```kotlin
fun create(
    appContext: Context,
    options: RoomOptions = RoomOptions(),
    overrides: LiveKitOverrides = LiveKitOverrides(),
): Room {
    val ctx = appContext.applicationContext

    if (ctx !is Application) {
        LKLog.w { "Application context was not found, this may cause memory leaks." }
    }

    val component = DaggerLiveKitComponent
        .factory()
        .create(ctx, overrides)

    val room = component.roomFactory().create(ctx)
    room.setRoomOptions(options)

    return room
}
```

## 1. 区分：变量 / 类 / Kotlin语法符号（约定符号）
> C++背景：`class`=类；变量=实例/引用；符号是语言语法，不是变量也不是类。

### 🟦 类（类型，相当于C++ class/struct）
| 类名 | 说明 |
|---|---|
| `Context` | Android系统类，上下文句柄 |
| `RoomOptions` | LiveKit配置类 |
| `LiveKitOverrides` | DI覆盖配置类 |
| `Room` | 返回值类型，房间业务类 |
| `Application` | Android App全局应用类 |
| `DaggerLiveKitComponent` | **Dagger编译自动生成的类**（源码看不到，编译产物） |
| `LKLog` | LiveKit日志工具类 |

> `DaggerLiveKitComponent.factory()`：`factory()`是这个类的**静态方法**，返回一个工厂对象。

### 🟩 变量（内存里的实例/引用，对应C++引用/指针）
| 变量名          | 哪里定义                 | 类型                             | 来源                                                                                                                                                        |
| ------------ | -------------------- | ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `appContext` | 函数入参                 | `Context`                      | **调用者传入**，外部调用create的时候传进来                                                                                                                                |
| `options`    | 函数入参                 | `RoomOptions`                  | 调用者传入，有默认值                                                                                                                                                |
| `overrides`  | 函数入参                 | `LiveKitOverrides`             | 调用者传入，有默认值                                                                                                                                                |
| `ctx`        | 函数内部 `val ctx = ...` | `Context`                      | 👉**回答你的问题：ctx哪里来！**<br>`ctx = appContext.applicationContext`，拿入参`appContext`的属性，不是凭空创建。不管你传Activity还是别的Context，访问它的`.applicationContext`属性拿到**全局应用上下文**。 |
| `component`  | 函数内部 val             | DaggerLiveKitComponent（DI容器实例） | Dagger工厂create()返回出来的IoC容器实例                                                                                                                              |
| `room`       | 函数内部 val             | Room                           | `component.roomFactory().create(ctx)` 工厂产出的Room实例                                                                                                         |

> Kotlin `val` ≈ C++ `const`引用：引用本身不可重新赋值；但对象内部成员可以修改。
> `var` 才是可以重新指向别的对象。这里全部是`val`。

### 🟪 Kotlin约定语法符号（语言本身，不是类、不是变量）
|符号|含义，对标C++|
|---|---|
|`fun` | 定义函数；C++ `static` 函数 |
|`:` | 冒号：`变量: 类型`，**类型标注**。例 `appContext: Context`；C++反过来 `Context appContext` |
|`= RoomOptions()` | 默认参数；C++：`RoomOptions options = RoomOptions{}` |
|`val` | 只读引用（不能重新赋值）；≈ `auto const&` |
|`!is` | 类型判断运算符：**不是XX类型**<br>`ctx !is Application` → `if(!(ctx instanceof Application))`；C++没有内置运算符，等价`dynamic_cast`判空 |
|`{ ... }` lambda：`LKLog.w { "xxx" }` <br>w接收一个lambda，延迟执行字符串拼接；<br>C++等价lambda `[](){ return "str"; }` |
|`.` | 成员调用，和C++ `.` 一样；对象.方法 / 对象.属性 |
|`()` | 函数调用 |

> 重点区分：
> `RoomOptions()`：带括号，**构造函数调用，创建对象实例**
> `RoomOptions`：不带括号，指**类本身（类型）**

---

## 2. IOC是什么（IoC Inversion of Control 控制反转）
### 通俗对比C++
普通C++写法（正流程）：
**业务代码自己负责new所有依赖**
```cpp
// 业务代码主动创建各个依赖
auto audioModule = std::make_shared<AudioModule>();
auto netModule = std::make_shared<NetModule>();
auto room = std::make_shared<Room>(audioModule, netModule);
```
> 业务代码掌控对象创建、依赖装配。

**IoC / 控制反转：把对象创建、依赖装配交给容器。**
业务代码不再手动new依赖，只告诉容器：我需要一个Room。
容器内部自动把AudioModule、NetModule构造好、注入给Room。

- **IoC容器**：就是一个大对象仓库，管理所有对象生命周期、依赖关系。
- **DI（依赖注入 Dependency Injection）：是实现IoC的手段**。Dagger2就是Android编译期DI框架。

> LiveKit这里 `DaggerLiveKitComponent` 就是这个IoC容器实例。
> 你只需要向容器拿 `roomFactory`，你不用关心Room内部需要Audio、WebRTC底层哪些类。容器全部装配完毕。

#### IoC两个关键点
1. **控制反转**：对象创建控制权从业务代码 → 交给容器
2. **依赖注入**：容器把依赖自动塞给目标类（构造注入/set注入）

> C++生态没有标准IoC，很多项目手写简易IoC容器；Java/Kotlin生态Dagger/Hilt广泛使用。

---

## 3. ctx 完整溯源：`val ctx = appContext.applicationContext`
1. `appContext`：外部调用`create()`的时候，调用方传进来的参数，可以是Activity、Service、Application。
2. 任何Android Context（Activity/Service）都有成员属性 `.applicationContext`。
3. 这个属性返回**全局单例Application上下文**，生命周期=整个APP进程，不会随页面销毁。

伪代码还原：
```kotlin
// 假设外部调用：
// Room.create(activity, ...)
// appContext 就是 activity
val ctx = activity.applicationContext // 取出全局App上下文，不再持有Activity
```

> 为什么要这么做？
如果Room长生命周期，直接持有Activity引用，Activity finish销毁后GC无法回收 → **内存泄漏**。
所以代码内部强制向上拿applicationContext。

> 日志警告：`ctx !is Application`，正常情况`.applicationContext`返回对象一定是Application类型；极少数魔改ROM会异常，打印警告。

### 小结快速记忆
1. `ctx`**不是凭空生成**，来源于传入参数`appContext`的`.applicationContext`属性。
2. IoC：对象创建交给容器，业务代码不手动组装一堆底层依赖；Dagger生成的Component就是IoC容器实例。
3. `val/fun/:/!is` 属于Kotlin语言语法符号，既不是变量，也不是类。

如果你需要，我可以下一步：把Dagger这几行，用纯C++手写模拟一份简易IoC伪代码，一眼看懂Dagger到底帮我们干了什么。








# LiveKit Android Kotlin create() 函数解析
> 你有C++背景，我会对标C++概念来讲，避开纯Kotlin玄学，重点讲**职责、Dagger依赖注入、对象生命周期、内存坑点**。

```kotlin
fun create(
    appContext: Context,
    options: RoomOptions = RoomOptions(),
    overrides: LiveKitOverrides = LiveKitOverrides(),
): Room {
    val ctx = appContext.applicationContext

    if (ctx !is Application) {
        LKLog.w { "Application context was not found, this may cause memory leaks." }
    }

    val component = DaggerLiveKitComponent
        .factory()
        .create(ctx, overrides)

    val room = component.roomFactory().create(ctx)
    room.setRoomOptions(options)

    return room
}
```

## 整体功能
静态工厂方法，**创建 LiveKit `Room` 对象**。
`Room` 对应 RTC 房间实例，等价于C++里 `std::unique_ptr<Room>` 工厂函数，不直接new，走Dagger依赖注入框架构建。

### 参数说明
1. `appContext: Context`
Android上下文，类比C++传入环境/运行时句柄。
- Activity Context：生命周期随页面销毁；
- Application Context：全局单例生命周期，整个App存活。

2. `options: RoomOptions = RoomOptions()`
带默认参数，Kotlin `= xxx` 就是默认实参，C++等价：
```cpp
RoomOptions options = RoomOptions{} // 默认参数
```
房间配置：视频编码、音频、降噪、比特率等。

3. `overrides: LiveKitOverrides = LiveKitOverrides()`
依赖注入覆盖配置，**用来替换内部默认实现类**。
> C++类比：依赖注入的策略注入，替换接口的默认实现，比如把默认日志器换成你自己的日志实现。

---

## 逐行拆解
```kotlin
val ctx = appContext.applicationContext
```
**强制拿Application全局上下文**。
哪怕你传入Activity（页面）的Context，代码主动取出它附属的`ApplicationContext`。
> ⚠️ Android经典内存泄漏坑：如果Room长生命周期，持有Activity Context，Activity销毁无法GC，内存泄漏。
> C++类比：不要保存局部栈对象的指针，要拿全局实例句柄。

```kotlin
if (ctx !is Application) {
    LKLog.w { "Application context was not found, this may cause memory leaks." }
}
```
`!is` = 不是这个类型，运行时类型判断。
理论上 `applicationContext` 一定返回`Application`，极少数定制ROM会异常，打警告日志。

```kotlin
val component = DaggerLiveKitComponent
    .factory()
    .create(ctx, overrides)
```
**Dagger2 依赖注入核心，这是最陌生的部分**。

- `LiveKitComponent`：Dagger的**Component接口**，相当于一个大的依赖容器（C++没有原生对应，类似手写IoC容器）。
- `DaggerLiveKitComponent`：Dagger编译期自动生成的实现类，你源码看不到，编译产物。
- `.factory()`：Component工厂，用来传入外部依赖（这里是Android Context、overrides）。
- `.create(ctx, overrides)`：实例化整个IoC容器，把全局上下文、自定义覆盖配置灌进去。

> C++通俗类比：
> Dagger在编译阶段帮你写好了一整套对象构造代码，不用手写大量new，自动处理类之间依赖关系。
> `LiveKitComponent`容器内部管理一堆底层对象：音频模块、视频模块、网络模块、日志、`RoomFactory`工厂等。
> `overrides`允许你替换容器内部某些默认对象，比如替换底层socket实现、替换编码器。

```kotlin
val room = component.roomFactory().create(ctx)
```
1. `component.roomFactory()`：从IoC容器取出 `RoomFactory` 对象。工厂类，专门生产Room实例。
2. `.create(ctx)`：调用工厂方法真正构建Room对象。

> C++视角：IoC容器里面拿到 `RoomFactory* factory`；`factory->create(ctx)`。
> Room对象内部大量依赖（WebRTC底层包装、音频管理等）全部由Dagger注入，不用我们手动传一堆构造参数。

```kotlin
room.setRoomOptions(options)
```
工厂构建完Room实例之后，**后置设置房间业务参数**。
> 为什么不直接传给构造函数？Dagger工厂是编译生成，不方便传入业务运行时参数；所以先构造对象，再set配置。

```kotlin
return room
```
返回Room实例给上层，后续调用`room.connect()`连接RTC房间。

---

# 对标C++ 关键概念对照表
| Kotlin / Android | C++等价理解 |
|---|---|
| `fun create(...) : Room` | static工厂函数 `static Room create(...)` |
| `Context` | 运行时环境句柄 |
| `applicationContext` | 全局App单例句柄，避免持有局部对象 |
| `Dagger Component` | IoC/依赖注入容器（编译生成，C++需要手写） |
| `overrides` | 策略模式，替换接口实现 |
| `RoomFactory` | 工厂模式，生产Room实例 |
| 默认参数 `= RoomOptions()` | C++默认实参 |

## 重点坑点（做RTC开发需要注意）
1. **必须传入Application上下文**
不要传Activity，否则如果Room没有销毁，页面Activity内存泄漏。
> 即使你传Activity，代码内部会自动拿applicationContext，但警告说明极端情况失效。

2. `DaggerLiveKitComponent` 是编译生成，不要手动new，不能自己new Room，**必须走这个create工厂**。
Room内部持有大量WebRTC native(C++)层对象，直接构造会缺失依赖，直接crash。

3. `LiveKitOverrides`：高级用法，比如替换底层网络、自定义音频模块；普通业务开发不传，用默认即可。

4. 生命周期：返回的Room对象，用完要调用`room.release()`，底层会释放WebRTC C++资源，否则native内存泄漏。

## 补充：这个代码的架构思想（和C++ RTC项目对比）
很多C++ RTC项目：手写一大堆工厂，构造函数传巨多依赖；
LiveKit Android 使用Dagger做编译期DI：
- 底层依赖（WebRTC包装、音频、视频）交给Dagger自动装配
- 业务层参数（RoomOptions），对象构建完成后set进去分离
- `overrides`提供扩展点，允许替换内部组件，方便二次开发。

如果你需要，我可以顺带讲一下Room对象内部大致的C++<->Kotlin JNI调用链路。








## 用C++手写极简模拟 Dagger 的逻辑

注意：
>这是**模拟伪代码**，不是真实Dagger源码；目的就是把
`DaggerLiveKitComponent.factory().create(ctx, overrides)`
翻译成你熟悉的C++，看懂DI容器到底在干什么。

原始Kotlin代码片段：
```kotlin
val component = DaggerLiveKitComponent
    .factory()
    .create(ctx, overrides)

val room = component.roomFactory().create(ctx)
```

源码里手写定义一个接口（这是你能看到的源码）
```kotlin
// 源码中手写接口，这是输入给Dagger编译器
interface LiveKitComponent {
    fun roomFactory(): RoomFactory

    interface Factory {
        fun create(ctx: Context, overrides: LiveKitOverrides): LiveKitComponent
    }
}


// Dagger编译自动生成产物，你看不到源码
class DaggerLiveKitComponent : LiveKitComponent {

    // 编译器生成的内部类，实现接口 LiveKitComponent.Factory
    private class FactoryImpl : LiveKitComponent.Factory {
        override fun create(ctx: Context, overrides: LiveKitOverrides): LiveKitComponent {
            // 真正构造 DaggerLiveKitComponent 对象，装配全部依赖
            return DaggerLiveKitComponent(ctx, overrides)
        }
    }

    // 静态方法 factory()，返回上面FactoryImpl实例（接口类型是 LiveKitComponent.Factory）
    companion object {
        fun factory(): LiveKitComponent.Factory {
            return FactoryImpl()
        }
    }

    // 实现接口 fun roomFactory(): RoomFactory
    override fun roomFactory(): RoomFactory {
        return m_cached_roomFactory
    }
}
```

> Dagger编译器读到这个接口，自动生成实现类 `DaggerLiveKitComponent`。


### C++模拟实现
```cpp
#include <memory>

// 前置类型（对应Android/Kotlin侧的类）
struct Context {};
struct LiveKitOverrides {};
struct Room {};

// 工厂抽象
class RoomFactory {
public:
    virtual ~RoomFactory() = default;
    virtual std::unique_ptr<Room> create(Context ctx) = 0;
};

// Component抽象接口，等价 Kotlin LiveKitComponent
class LiveKitComponent {
public:
    virtual ~LiveKitComponent() = default;
    virtual std::shared_ptr<RoomFactory> roomFactory() = 0;

    // 内部Factory接口，用来接收外部传入参数
    class Factory {
    public:
        virtual ~Factory() = default;
        virtual std::shared_ptr<LiveKitComponent> create(Context ctx, LiveKitOverrides overrides) = 0;
    };

    // 静态获取Factory实例
    static std::shared_ptr<Factory> factory();
};

// ========== Dagger编译器自动生成的实现类 ==========
// 等价 Kotlin DaggerLiveKitComponent，编译产物，你源码看不到
class DaggerLiveKitComponent : public LiveKitComponent, public std::enable_shared_from_this<DaggerLiveKitComponent> {
private:
    Context m_ctx;
    LiveKitOverrides m_overrides;
    std::shared_ptr<RoomFactory> m_roomFactory;

    // 构造函数私有！外部不能直接 new，只能走Factory
    DaggerLiveKitComponent(Context ctx, LiveKitOverrides overrides)
        : m_ctx(ctx), m_overrides(overrides)
    {
        // ✨DI容器核心：在这里装配所有内部依赖
        // 根据 overrides 判断：使用用户自定义实现，还是默认实现
        m_roomFactory = buildRoomFactory(m_ctx, m_overrides);
    }

public:
    std::shared_ptr<RoomFactory> roomFactory() override {
        return m_roomFactory;
    }

    // 编译器生成的Factory实现
    class FactoryImpl : public LiveKitComponent::Factory {
    public:
        std::shared_ptr<LiveKitComponent> create(Context ctx, LiveKitOverrides overrides) override {
            // 真正构造Component容器实例
            return std::shared_ptr<DaggerLiveKitComponent>(new DaggerLiveKitComponent(ctx, overrides));
        }
    };

    static std::shared_ptr<LiveKitComponent::Factory> factory() {
        static auto inst = std::make_shared<FactoryImpl>();
        return inst;
    }

private:
    // 内部装配逻辑：根据overrides选择具体实现类
    std::shared_ptr<RoomFactory> buildRoomFactory(Context ctx, LiveKitOverrides overrides);
};

// 调用方业务代码，等价原来Kotlin那两行
void demo() {
    Context ctx;
    LiveKitOverrides overrides;

    // 对应：DaggerLiveKitComponent.factory().create(ctx, overrides)
    auto component = DaggerLiveKitComponent::factory()->create(ctx, overrides);

    // 对应：component.roomFactory().create(ctx)
    auto room = component->roomFactory()->create(ctx);
}
```



# 核心回答
## 1. Dagger 确实会自动生成实现类
- 你手写：`interface LiveKitComponent`（父接口），嵌套子接口 `LiveKitComponent.Factory`
- Dagger编译器扫描这个接口 + Dagger注解，**编译阶段生成 Java/Kotlin 源代码**，输出 `DaggerLiveKitComponent`
- ✅ **两个接口全部自动实现**
  1. 实现外层 `LiveKitComponent`：重写 `fun roomFactory(): RoomFactory`
  2. 在生成的类内部，生成一个内部类 `FactoryImpl`，实现嵌套子接口 `LiveKitComponent.Factory`，重写 `fun create(...)`

> 注意：生成的是源码，不是运行时动态生成（不是反射！）。编译完你可以在build目录下找到 `DaggerLiveKitComponent.kt` / `.java` 文件，可以打开看完整代码。

C++类比：
想象你写一份`.idl`接口描述文件；代码生成器读取idl，帮你生成派生类，实现全部纯虚函数。Dagger就是做这件事的编译器插件。

---

## 2. 为什么非要自动实现？为什么不能手写？
先看如果**手写实现 LiveKitComponent**会发生什么，你就能体会痛点。

`LiveKitComponent` 这个Component，它的职责：
> 管理一大堆依赖对象：AudioModule、VideoModule、WebRTC底层包装、网络栈、日志、RoomFactory等等。
> 这些类之间互相依赖：A需要B，B需要C，C又需要外部传入的`Context`、`overrides`。

### 手写版本伪代码（C++视角）
```cpp
// 手写实现 LiveKitComponent
class MyLiveKitComponent : public LiveKitComponent
{
private:
    Context m_ctx;
    LiveKitOverrides m_overrides;

    // 一大堆被管理的依赖，几十行成员变量
    std::shared_ptr<AudioModule> m_audioModule;
    std::shared_ptr<VideoModule> m_videoModule;
    std::shared_ptr<NetTransport> m_net;
    std::shared_ptr<RoomFactory> m_roomFactory;

public:
    MyLiveKitComponent(Context ctx, LiveKitOverrides overrides)
        : m_ctx(ctx), m_overrides(overrides)
    {
        // 手动装配依赖，噩梦从这里开始
        // AudioModule 需要 Context
        m_audioModule = std::make_shared<AudioModule>(m_ctx);

        // VideoModule 需要 Context + AudioModule
        m_videoModule = std::make_shared<VideoModule>(m_ctx, m_audioModule);

        // NetTransport 需要 Context
        m_net = std::make_shared<NetTransport>(m_ctx);

        // RoomFactory 需要 audio/video/net 一大堆依赖
        m_roomFactory = std::make_shared<DefaultRoomFactory>(
            m_ctx,
            m_audioModule,
            m_videoModule,
            m_net,
            m_overrides
        );

        // 🔴 坑1：依赖顺序不能错！先构造被依赖对象，再构造使用者。
        // 🔴 坑2：新增一个底层模块，这里构造代码全部要改。
        // 🔴 坑3：如果某个类构造参数变了，所有手写装配代码全部要改。
        // 🔴 坑4：还要处理 overrides：如果用户传入自定义AudioModule，就替换默认。if else爆炸。
    }

    std::shared_ptr<RoomFactory> roomFactory() override {
        return m_roomFactory;
    }
};
```

### 手写的现实痛点（RTC项目这种依赖繁多的场景尤其痛）
1. **依赖顺序必须人工维护**
B依赖A，必须先实例化A，再实例化B。类一多，很容易顺序写错，直接crash。

2. **构造参数改动，连锁爆炸**
底层AudioModule增加一个构造参数，你要跑到Component的构造函数里改装配代码；所有用到AudioModule的地方都要改。

3. **覆写(overrides)逻辑繁琐**
LiveKitOverrides允许用户替换内部某个组件。手写就要写大量`if‑else`判断：如果用户给了自定义实现就用用户的，否则new默认实现。组件一多，代码臃肿。

4. **重复样板代码巨多**
项目里不止一个Component，每一个IoC容器都要写一大坨装配逻辑，全是机械重复劳动。

5. **容易手写错：漏传依赖、传错对象**
比如构造RoomFactory的时候，不小心传错一个模块，运行时才崩，调试成本高。

---

## Dagger自动生成解决什么？
开发者只做两件事：
1. 在各个类的构造函数上加注解，告诉Dagger：**这个类需要哪些依赖**。
2. 写Component接口，声明：“我对外要暴露出什么对象（`roomFactory()`）”。

剩下全部交给编译器：
- Dagger扫描所有类的构造函数，**自动分析依赖图**，自动排好实例化顺序。
- 如果用户给了`overrides`，自动分支选择自定义实现/默认实现。
- 自动生成全部new/装配代码。
- 编译期就检查依赖完整性：**缺依赖直接编译报错，而不是运行时崩溃**。

> 重点：**编译期检查，不是运行时反射**。这是Dagger对比Spring这类运行时IoC最大优势，适合Android移动端。

### 比喻
- 手写Component：你手工拼一台电脑，记住顺序：先装CPU，再装主板，再装内存，接错就开不了机。
- Dagger：你只写零件说明书（注解标记每个零件需要什么配件），编译器帮你按正确顺序组装整台机器。

---

## 回到LiveKit这个例子
LiveKit内部有大量WebRTC包装、音频、视频、网络模块，依赖链很长。
如果全部手写Component装配代码，维护成本极高；底层WebRTC版本升级，类构造一变，手写代码到处要改。

> 所以：手写接口（契约），Dagger生成实现。
> 你只管定义需要什么，不要管怎么new、怎么按顺序组装。

---

## 补充两个容易混淆点
1. **接口只是契约，Dagger根据契约+注解生成实现**
接口本身没有任何装配逻辑；注解才告诉Dagger各个类之间依赖关系。

2. 命名约定：手写接口叫`XxxComponent`；生成的实现类固定前缀`Dagger` → `DaggerXxxComponent`。

### 极简小结
1. ✔父接口`LiveKitComponent`，嵌套子接口`LiveKitComponent.Factory`，Dagger编译阶段全部生成实现代码。
2. 为什么自动实现：避免手写海量、容易出错的对象装配样板代码；编译期校验依赖，避免运行时bug；底层模块改动时，不需要人工修改容器组装代码。
3. C++生态没有标准Dagger，所以C++项目要么手写IoC容器，要么干脆直接new；Kotlin/Android大规模项目普遍用Dagger解决复杂依赖。

如果你想，下一步可以看：类上加的`@Component`、`@Factory`这些注解到底起什么作用。




### 关键点，对照回Kotlin

1. **构造函数私有**
`DaggerLiveKitComponent` 你不能直接 `new` / `DaggerLiveKitComponent()`。
必须走 `Factory::create()`，外部传入外部依赖：`ctx`、`overrides`。
> 这就是为什么LiveKit文档明确：**不要手动new Room，必须调用 Room.create()**。

2. `overrides` 的作用
`buildRoomFactory` 里面：如果用户在`overrides`传入自定义的`RoomFactory`，就用用户的；否则实例化默认的内部实现。
这就是DI容器的扩展点。

3. component 就是 IoC容器实例
容器内部一次性把所有底层依赖全部建好（音频模块、WebRTC wrapper、网络、日志等），保存为成员变量。
后面你只需要从容器拿已经装配好的对象，不用自己传一堆构造参数。

4. 编译期生成，不是运行时反射
> 这点和很多Java旧IoC不一样：Dagger没有运行时反射；全部是编译阶段生成如上的实现代码，性能高，适合移动端。

---

### 回到原来Kotlin完整流程，用大白话串一遍
```kotlin
// 1.拿到编译器生成的Factory对象
DaggerLiveKitComponent.factory()

// 2.调用factory.create，传入外部必须的外部依赖 ctx、overrides
// 内部new出DaggerLiveKitComponent容器实例，内部把所有底层依赖全部装配完成
val component = ... .create(ctx, overrides)

// 3.从容器取出已经装配完成的 RoomFactory
val factory = component.roomFactory()

// 4.工厂创建Room对象，Room内部所需要的WebRTC、音频模块全部已经DI注入好了
val room = factory.create(ctx)

// 5.业务参数 RoomOptions 是运行时参数，Dagger不处理，手动set进去
room.setRoomOptions(options)
```

> 为什么 `RoomOptions` 不走Dagger注入？
- `ctx`、`overrides`：属于**容器初始化外部依赖**，容器构建的时候就要。
- `RoomOptions`：业务运行时参数，每次创建Room可以不一样，不适合放到编译期DI容器，所以构建完对象之后set。

### 容易踩坑的点
1. 不要自己 `DaggerLiveKitComponent(...)`；构造私有，编译报错。
2. 不要自己 `Room()`，Room的构造函数也是内部私有；直接new会缺失一堆WebRTC底层依赖，直接crash/native内存异常。
3. component 实例不要反复创建，但是LiveKit封装在`Room.create()`内部，对你屏蔽了component，你感知不到。

如果你愿意，下一步我们可以看：`component.roomFactory().create(ctx)` 内部，Room类的构造大概长什么样，看哪些依赖是Dagger注入进来的。








## 类归属核对
> 你的判断大部分正确，有一处细节：`DaggerLiveKitComponent` **不是Dagger库自带类**，是Dagger编译生成的**本项目专属类**。

| 类                        | 归属                                                                                                                      | 你的判断校验                  |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| `RoomOptions`            | ✅ LiveKit 项目自定义 Kotlin 数据类，业务配置                                                                                         | 项目自己定义                  |
| `LiveKitOverrides`       | ✅ LiveKit 项目自定义，DI覆写配置                                                                                                  | 项目自己定义                  |
| `LKLog`                  | ✅ LiveKit内部日志工具类，项目自定义                                                                                                  | 项目自己定义                  |
| `Context`                | ✅ Android SDK framework 系统类（`android.content.Context`）                                                                  | Android系统类 ✔            |
| `Application`            | ✅ Android SDK `android.app.Application` 系统类                                                                             | Android系统类 ✔            |
| `DaggerLiveKitComponent` | ⚠️ **不是Dagger库自带类**<br>源码里你看不到这个文件；Dagger编译器扫描源码中接口 `LiveKitComponent`，编译时自动生成 `DaggerLiveKitComponent`，属于**当前项目编译产物**。 | ❗不是Dagger库自带，是为本项目生成的代码 |

> Dagger库提供的是注解、编译器；不会直接给你 `DaggerXxxComponent`，每个项目的Component都是编译生成。

---

## 类型大写开头、变量小写开头

---

## 补充一个容易混淆点
```kotlin
RoomOptions     // 引用【类本身】（类型）
RoomOptions()   // 调用构造函数，生成【实例对象】
```
`RoomOptions()` 返回出来的是实例，可以赋值给变量：
```kotlin
val options: RoomOptions = RoomOptions()
// 变量名options小写；类型RoomOptions大写，严格分开。
```

---


如果你需要，我们可以继续：把 `DaggerLiveKitComponent.factory().create(...)` 翻译成一份手写C++伪代码，把DI容器做个极简模拟，彻底看懂这行到底干了什么。


**一句话架构**：
> `Room` 是面向用户的门面（管理连接状态、参与者、轨道、事件），`
> RTCEngine` 是内部引擎（整合信令与媒体传输），`
> SignalClient` 负责 WebSocket 信令，`
> PeerConnectionTransport` 封装 WebRTC `PeerConnection`（媒体传输），`
> Participant`/`Track` 体系承载业务对象。

核心调用链（从用户视角）：

```
LiveKit.create() → Room
Room.connect(url, token) → RTCEngine.join() → SignalClient.join() (WebSocket)
                      → configure() 创建 publisher/subscriber PeerConnectionTransport
                      → negotiatePublisher() (SDP offer/answer)
                      → onJoinResponse() 回填 Room/LocalParticipant 状态
```

### 1.4 关键组件速览

| 组件 | 文件 | 职责 |
|---|---|---|
| `LiveKit` | `LiveKit.kt` | 进程级入口，创建 Room |
| `Room` | `room/Room.kt` | 主门面，连接/参与者/轨道/事件 |
| `RTCEngine` | `room/RTCEngine.kt` | 整合信令与 PeerConnection |
| `SignalClient` | `room/SignalClient.kt` | WebSocket 信令客户端 |
| `PeerConnectionTransport` | `room/PeerConnectionTransport.kt` | 单个 PeerConnection 封装 |
| `LocalParticipant` / `RemoteParticipant` | `room/participant/` | 参与者模型 |
| `LocalAudioTrack` / `LocalVideoTrack` / `RemoteAudioTrack` / `RemoteVideoTrack` | `room/track/` | 轨道模型 |
| `E2EEManager` | `e2ee/E2EEManager.kt` | 端到端加密 |
| `AudioSwitchHandler` | `audio/AudioSwitchHandler.kt` | 音频设备/焦点管理 |
| `FlowDelegate` | `util/FlowDelegate.kt` | `@FlowObservable` 响应式属性机制 |

---

## 第 2 章 分层架构与文件组织

### 2.1 四层架构

本 SDK 自上而下可分为四层，依赖严格单向向下：

```
┌─────────────────────────────────────────────────────────────┐
│  ① API 层（用户门面）                                         │
│  LiveKit, Room, RoomOptions, ConnectOptions, RoomEvent       │
│  用户只与这一层打交道                                          │
├─────────────────────────────────────────────────────────────┤
│  ② Room 编排层（业务对象与状态机）                              │
│  RTCEngine, Participant(Local/Remote), Track(Local/Remote),  │
│  TrackPublication, DefaultsManager, E2EEManager, events/      │
├─────────────────────────────────────────────────────────────┤
│  ③ 传输层（信令 + 媒体协商）                                   │
│  SignalClient(WebSocket), PeerConnectionTransport,           │
│  Publisher/SubscriberTransportObserver, DataChannelManager    │
├─────────────────────────────────────────────────────────────┤
│  ④ WebRTC 原生层（JNI → C++ libwebrtc）                        │
│  org.webrtc.* / livekit.org.webrtc.*, PeerConnectionFactory,  │
│  EglBase, AudioDeviceModule, RTC 线程                         │
└─────────────────────────────────────────────────────────────┘
```

- **①→②**：`Room` 把用户调用转译为对 `RTCEngine`/`LocalParticipant` 的内部调用，并把内部事件包装成 `RoomEvent` 暴露。
- **②→③**：`RTCEngine` 编排 `SignalClient`（信令）与两个 `PeerConnectionTransport`（publisher/subscriber）。
- **③→④**：`PeerConnectionTransport` 持有一个 native `PeerConnection`，所有调用经 `RTCThreadToken` 投递到 RTC 线程执行。

### 2.2 目录与架构映射

`livekit-android-sdk/src/main/java/io/livekit/android/` 下的目录与层、职责的映射：

| 目录 | 层 | 职责 |
|---|---|---|
| `annotations/` | ① | API 稳定性标注（`@Beta`）、WebRTC 敏感标注 |
| `audio/` | ②/④ | 音频设备管理（`AudioHandler`/`AudioSwitchHandler`）、音频处理、预连接缓冲、通信模式 workaround |
| `coroutines/` | 工具 | 协程工具（`FlowExt`、`ReentrantMutex`） |
| `dagger/` | 横切 | 依赖注入模块与组件 |
| `e2ee/` | ② | 端到端加密（`E2EEManager`、`KeyProvider`、`DataPacketCryptorManager`） |
| `events/` | ② | 事件总线与事件类型（`RoomEvent`/`ParticipantEvent`/`TrackEvent`） |
| `memory/` | 横切 | 资源生命周期（`CloseableManager`） |
| `renderer/` | ① | 视频渲染视图（`SurfaceViewRenderer`/`TextureViewRenderer`） |
| `room/` | ②/③ | 核心：`Room`、`RTCEngine`、`SignalClient`、`PeerConnectionTransport`、`participant/`、`track/`、`network/`、`rpc/`、`datastream/`、`metrics/`、`provisions/`、`util/`、`types/` |
| `rpc/` | ② | RPC 错误类型 |
| `stats/` | 横切 | 客户端/网络统计 |
| `token/` | ① | 鉴权 token 来源（`TokenSource` 体系） |
| `util/` | 横切 | 通用工具（`FlowDelegate`、`LKLog`、`Either`、`MutexEx`、`TTLMap` 等） |
| `webrtc/` | ④ | WebRTC 扩展与定制（编解码器工厂、SDP 工具、DataChannel 管理、RTC 线程工具） |

`room/` 子目录进一步细分：

| 子目录 | 职责 |
|---|---|
| `room/participant/` | `Participant` 基类与 `LocalParticipant`/`RemoteParticipant` |
| `room/track/` | `Track` 体系与各 Local/Remote 音视频轨道、`TrackPublication` |
| `room/track/video/` | 视频捕获/处理辅助（capturer、VideoProcessor、可见性、可伸缩性模式） |
| `room/track/screencapture/` | 屏幕共享轨道与前台服务 |
| `room/network/` | 重连策略、网络回调 |
| `room/rpc/` | 房间级 RPC 管理（client/server manager） |
| `room/datastream/` | 数据流（incoming/outgoing，文本/字节） |
| `room/metrics/` | RTC 指标采集 |
| `room/provisions/` | 内部对象持有（`LKObjects`） |
| `room/util/` | 房间内部工具（SDP observer、编码工具、约束键） |
| `room/types/` | 共享类型（Agent 类型、转录段） |

### 2.3 依赖方向

依赖严格单向向下，横切层（dagger/memory/util/stats）被各层共用。`Room` 不直接持有 `PeerConnection`，而是通过 `RTCEngine` → `PeerConnectionTransport` 间接操作，保证上层不被 WebRTC 细节污染。

### 2.4 类图（核心对象关系）

```
                    ┌──────────┐  creates   ┌──────────────┐
                    │ LiveKit  │──────────▶│     Room     │
                    └──────────┘           └──────┬───────┘
                                                  │ owns/listens
                              ┌───────────────────┼────────────────────┐
                              ▼                   ▼                    ▼
                       ┌─────────────┐    ┌────────────────┐   ┌──────────────────┐
                       │  RTCEngine  │    │LocalParticipant│   │RemoteParticipant │
                       │ (Listener) │    └───────┬────────┘   └────────┬─────────┘
                       └──────┬──────┘            │ owns                │ owns
              ┌──────────────┼───────────┐       ▼                     ▼
              ▼              ▼           ▼  ┌─────────────┐    ┌─────────────────┐
       ┌────────────┐  ┌───────────┐  ┌────┴──────┐ │LocalTrackPub│    │RemoteTrackPub│
       │SignalClient│  │Publisher   │  │Subscriber │ │ + LocalTrack│    │ + RemoteTrack │
       │ (WebSocket)│  │Transport   │  │Transport  │ └─────────────┘    └───────────────┘
       └────────────┘  │(PeerConn)  │  │(PeerConn) │
                       └─────┬───────┘  └─────┬─────┘
                             │                │
                             ▼                ▼
                      ┌──────────────────────────────┐
                      │  PeerConnectionFactory (native)│
                      │  + EglBase + AudioDeviceModule │
                      └──────────────────────────────┘
```

`Room` 同时实现 `RTCEngine.Listener`、`ParticipantListener`、`RpcManager`，是多方回调的汇聚点（`Room.kt:156`）。

---

## 第 3 章 依赖注入（Dagger）与对象图

### 3.1 Dagger 基础概念（给 C++ 读者）

Dagger 是编译期依赖注入框架。C++ 读者可这样类比：
- **`@Module`**：一个"工厂集合"类，里面的 `@Provides` 方法是"构造函数"。
- **`@Inject`（构造器）**：告诉 Dagger 这个类可以用构造器直接创建，Dagger 会自动收集它的依赖。
- **`@AssistedInject`（构造器）**：半自动构造——部分参数由 DI 提供，部分参数由调用方在运行时传入（`@Assisted`）。配合 `@AssistedFactory` 接口生成工厂。类比 C++ 中"工厂方法接受运行时参数 + 其余依赖从容器取"。
- **`@Component`**：依赖图的入口，Dagger 为其生成实现类（`DaggerLiveKitComponent`）。`@Singleton` 控制作用域。
- **`@Named("xxx")`**：限定符，区分同一类型的不同绑定（如多个 `CoroutineDispatcher`）。

### 3.2 LiveKitComponent 与模块

`LiveKitComponent`（`dagger/LiveKitComponent.kt:32`）是顶层 `@Singleton` 组件，包含 8 个模块：

| 模块 | 提供内容 |
|---|---|
| `CoroutinesModule` | 协程调度器（`DISPATCHER_DEFAULT`、`DISPATCHER_IO` 等） |
| `RTCModule` | WebRTC 原生对象：`PeerConnectionFactory`、`EglBase`、`AudioDeviceModule`、编解码器工厂、`RTCThreadToken`、`SdpFactory` |
| `WebModule` | `OkHttpClient`、`WebSocket.Factory`、`Json` |
| `JsonFormatModule` | protobuf/JSON 格式工具 |
| `OverridesModule` | 用户自定义覆盖项（来自 `LiveKitOverrides`） |
| `AudioHandlerModule` | `AudioHandler` 绑定（默认 `AudioSwitchHandler`） |
| `MemoryModule` | `CloseableManager` |
| `InternalBindsModule` | 接口到实现的绑定 |

工厂入口：
```kotlin
DaggerLiveKitComponent.factory().create(ctx, overrides).roomFactory().create(ctx)
```

### 3.3 关键对象提供链路

以 `Room` 的创建为例（`LiveKit.kt:91`）：

```
DaggerLiveKitComponent.create(ctx, OverridesModule(overrides))
   └─ roomFactory(): Room.Factory  (AssistedFactory)
        └─ create(ctx): Room
             @AssistedInject 构造，参数由 DI 提供：
             - engine: RTCEngine          (Singleton, @Inject)
             - eglBase: EglBase            (RTCModule)
             - localParticipantFactory    (AssistedFactory)
             - audioHandler               (AudioHandlerModule/Overrides)
             - audioProcessingController  (RTCModule → CustomAudioProcessingFactory)
             - incomingDataStreamManager, rpcClientManager, rpcServerManager
             - remoteParticipantFactory
             - ... 共 20+ 依赖
```

`RTCEngine`（`RTCEngine.kt:113`）是 `@Singleton @Inject`，持有 `SignalClient`、`PeerConnectionTransport.Factory`、`RTCThreadToken` 等。

`RTCModule`（`dagger/RTCModule.kt:73`）是 WebRTC 原生层的提供者，几个关键点：
- **`libWebrtcInitialization`**（`:102`）：用 `@Named(LIB_WEBRTC_INITIALIZATION)` 标记的"哨兵"依赖。任何依赖 native 库的对象，只要在 `@Provides` 方法签名里加这个参数，Dagger 就会先触发 libwebrtc 初始化。这是用 DI 表达"初始化顺序"的优雅手法。
- **`peerConnectionFactoryManager`**（`:347`）：在 RTC 线程上创建 `PeerConnectionFactory`，并把 `dispose` 注册到 `CloseableManager`（且 dispose 也投递回 RTC 线程）。
- **`audioModule`**（`:154`）：构建 `JavaAudioDeviceModule`，设置 `setSamplesReadyCallback(audioRecordSamplesDispatcher)`——这是本地音频采样回调的注入点，让 `LocalAudioTrack.addSink` 能拿到麦克风原始采样。
- **`rtcThreadToken`**（`:396`）：`RTCThreadTokenImpl` 绑定到 `PeerConnectionFactoryManager`，保证 RTC 线程亲和性。

### 3.4 LiveKitOverrides：扩展点

`LiveKitOverrides`（`LiveKitOverrides.kt:41`）是用户替换内部实现的入口，通过 `OverridesModule` 注入为 `@Named(OVERRIDE_*)` 的可空绑定。各模块在 `@Provides` 中优先使用 override，否则用默认实现。可覆盖项：

- `okHttpClient`：网络客户端
- `videoEncoderFactory` / `videoDecoderFactory`：编解码器工厂
- `audioOptions.audioHandler`：音频处理策略（默认 `AudioSwitchHandler`，可换 `NoAudioHandler`/`AudioFocusHandler`/自定义）
- `audioOptions.audioDeviceModule`：音频设备模块（注意：自定义时不由 SDK 释放，用户负责 `release()`）
- `eglBase`：EGL 上下文
- `peerConnectionFactoryOptions`：PeerConnectionFactory 选项

> **设计要点**：DI + override 模式让 SDK 既"开箱即用"（合理默认），又"可替换关键部件"（高级定制），且替换点是编译期类型安全的。C++ 读者可类比"带默认注入的 IoC 容器 + 抽象接口注册"。

---

## 第 4 章 连接生命周期与状态机

### 4.1 两套状态

SDK 有两套相关但不同的状态：

- **`Room.State`**（`Room.kt:187`）：面向用户的高层状态 `CONNECTING / CONNECTED / DISCONNECTED / RECONNECTING`，通过 `@FlowObservable` 可观察。`Room` 在状态变化时启停音频处理（`:239`）：进入 CONNECTING 启动 `audioHandler`/`communicationWorkaround`，进入 DISCONNECTED 停止。
- **`ConnectionState`**（`room/ConnectionState.kt:19`）：`RTCEngine` 内部更细粒度的状态 `CONNECTING / CONNECTED / DISCONNECTED / RECONNECTING / RESUMING`。多了 `RESUMING`（软重连中）。

`RTCEngine.connectionState` 的变化触发 `Listener` 回调（`RTCEngine.kt:130`）：
- `DISCONNECTED → CONNECTED`：`onEngineConnected()`
- `RECONNECTING → CONNECTED`：`onEngineReconnected()`
- `RESUMING → CONNECTED`：`onEngineResumed()`
- `CONNECTED → DISCONNECTED`：触发 `reconnect()`

`Room` 收到这些回调后更新自己的 `State` 并广播 `RoomEvent`（`Room.kt:1175`）。

### 4.2 connect 流程时序

`Room.connect()`（`Room.kt:461`）是核心入口，流程如下：

```
Room.connect(url, token, options)
  │
  ├─ stateLock 加锁：校验 DISCONNECTED → state=CONNECTING
  │   ├─ 创建 CoroutineScope(defaultDispatcher + SupervisorJob)
  │   ├─ localParticipant.reinitialize(options)
  │   ├─ setupLocalParticipantEventHandling()  // 订阅 participant 事件转 RoomEvent
  │   └─ 若 e2eeOptions!=null：创建 E2EEManager 并 setup
  │
  └─ connectJob (ioDispatcher):
       ├─ (可选) AuthedAudioProcessingController.authenticate(url, token)
       ├─ 若是 LiveKit Cloud：创建/复用 RegionUrlProvider，异步 fetchRegionSettings
       ├─ nextUrl = regionUrl ?: url
       ├─ while (nextUrl != null):  // 区域回退循环
       │    ├─ engine.join(connectUrl, token, options, roomOptions)
       │    └─ 失败 → nextUrl = regionUrlProvider.getNextBestRegionUrl()，重试
       ├─ networkCallbackManager.registerCallback()
       ├─ if options.audio: setMicrophoneEnabled(true)  // 可能先 startPreconnectAudioJob
       ├─ if options.video: setCameraEnabled(true)
       └─ collectMetrics()  // 后台采集 RTC 指标
```

`RTCEngine.join()`（`RTCEngine.kt:235`）→ `joinImpl()`（`:250`）：

```
joinImpl:
  ├─ connectionState = CONNECTING
  ├─ client.join(url, token, options, roomOptions)  // SignalClient WebSocket 握手，等 JoinResponse
  ├─ listener.onJoinResponse(joinResponse)          // Room 回填 sid/name/metadata/本地参与者/已有远端参与者
  ├─ isSubscriberPrimary = joinResponse.subscriberPrimary
  ├─ configure(joinResponse, options)               // 创建 publisher/subscriber PeerConnection + DataChannel
  ├─ if (!subscriberPrimary || fastPublish): negotiatePublisher()  // 发起 SDP 协商
  └─ client.onReadyForResponses()                   // 开始处理 JoinResponse 之后的信令消息
```

`configure()`（`RTCEngine.kt:279`）在 RTC 线程创建两个 `PeerConnectionTransport`，根据 `subscriberPrimary` 决定哪个 PC 的连接状态驱动 `connectionState`，并创建 reliable/lossy DataChannel。

### 4.3 prepareConnection（预连接优化）

`Room.prepareConnection()`（`Room.kt:420`）在页面加载时提前调用，做 DNS 解析、TLS 预热；LiveKit Cloud 还会探测最佳边缘节点（`regionUrlProvider.getNextBestRegionUrl()`），把结果缓存到 `regionUrl`，供后续 `connect` 直接使用，加快首次连接。

### 4.4 重连机制

`RTCEngine.reconnect()`（`RTCEngine.kt:521`）是重连核心，策略由 `ReconnectPolicy`（默认 `DefaultReconnectPolicy`）决定退避。两种重连：

- **软重连（resume）**：WebSocket 断但希望保留 PC 状态。流程：
  - `subscriber.prepareForIceRestart()` → `client.reconnect(url, token, participantSid)`（带 `?reconnect=1&sid=...`）
  - 收到 `ReconnectResponse` 后更新 RTC 配置，`client.onReadyForResponses()`
  - `onSignalConnected(true)` → `sendSyncState()` 把订阅状态同步给服务器
  - 若 `hasPublished`：`negotiatePublisher()`（ICE restart）
  - 等待 publisher/subscriber ICE 连通 → `resendReliableMessagesForResume(lastMessageSeq)` 重放可靠消息 → `onPostReconnect(false)`

- **全量重连（full reconnect）**：`closeResources()` 后重新 `joinImpl()`。`onFullReconnecting()` 通知 Room 清空远端参与者；成功后 `onPostReconnect(true)` 让 `LocalParticipant.republishTracks()` 重新发布所有轨道。

何时全量 vs 软重连由 `ReconnectType` 与重试次数决定（`:579`）：首次尝试软重连，失败后转全量；服务器 `LeaveRequest.action=RECONNECT` 或 `canReconnect` 触发全量。

重连触发源：
- WebSocket `onClose`/`onFailure`（`SignalClient` → `RTCEngine.onClose` → `reconnect()`）
- PeerConnection ICE 断开（`connectionState → DISCONNECTED`）
- 网络回调 `onLost`/`onAvailable`（`Room.kt:1138`）

### 4.5 断连与清理

`Room.disconnect()`（`Room.kt:609`）：发 `sendLeave()` → `handleDisconnect(CLIENT_INITIATED)`。
`handleDisconnect()`（`:999`）：在 `stateLock` 内 `state=DISCONNECTED` → `cleanupRoom()`（清参与者/轨道/e2ee）→ `engine.close()` → `localParticipant.dispose()` → 广播 `RoomEvent.Disconnected` → 取消协程作用域。

`RTCEngine.close()`（`:448`）：取消重连 job、关闭协程作用域、`closeResources()`（RTC 线程上关闭两个 PC 与 DataChannel）、`client.close()`、清理可靠消息缓冲。

---

## 第 5 章 信令层 SignalClient

### 5.1 角色

`SignalClient`（`room/SignalClient.kt:75`）是与 LiveKit 服务器的 WebSocket 信令客户端，`@Singleton`。职责：
- 建立/维护 WebSocket 连接
- 用 protobuf 编解码 `SignalRequest`/`SignalResponse`
- 实现 join/reconnect 握手
- ping/pong 心跳与超时
- 把服务器消息分发给 `RTCEngine`（通过 `Listener`）

### 5.2 连接与握手

`connect()`（`SignalClient.kt:167`）：
- URL 构造：`{ws|wss}://host/rtc?protocol=..&auto_subscribe=..&adaptive_stream=..&sdk=android&version=..&...&client_protocol=..`（`createConnectionParams` `:207`）
- 请求头带 `Authorization: Bearer <token>`
- `websocketFactory.newWebSocket(request, this)`（OkHttp WebSocket）
- `suspendCancellableCoroutine` 等待 `JoinResponse`，带 10s 超时（`SIGNAL_CONNECT_TIMEOUT`）

`onMessage`（`:305`）：只处理二进制 protobuf（JSON 已不支持）。`LivekitRtc.SignalResponse.parseFrom` 后 `handleSignalResponse`。

握手状态机（`handleSignalResponse` `:668`）：
- 未连接时收到 `Join` → `isConnected=true`，启动请求队列与 ping，`resumeWith(ConnectResult.Join)`
- 未连接时收到 `Leave` → 当作连接失败
- 重连中收到任意消息 → 视为信令重连成功，`resumeWith(Reconnect/OtherResponse)`
- 已连接 → `responseFlow.tryEmit` 交给 `onReadyForResponses` 启动的收集器处理

### 5.3 请求/响应队列

`SignalClient` 用两个 `MutableSharedFlow` 做消息队列，保证顺序与背压：

- **`requestFlow`**（`:108`）：发送队列。`sendRequest()`（`:644`）对非跳过类型 `tryEmit` 入队，`startRequestQueue` 启动的协程顺序 `sendRequestImpl` 经 WebSocket 发出。跳过队列的类型（`skipQueueTypes` `:1006`：SYNC_STATE/TRICKLE/OFFER/ANSWER/SIMULATE/LEAVE）直接发送，避免被排队阻塞。
- **`responseFlow`**（`:115`）：接收队列。`onReadyForResponses()`（`:254`）后才启动收集器 `handleSignalResponseImpl` 处理，确保 JoinResponse 之后的消息在 Room 准备好后才消费。

> **设计要点**：用 SharedFlow 做消息队列而非直接处理，解耦了"网络接收"与"业务处理"，且 `resetReplayCache` 防止重放旧消息。C++ 读者可类比"生产者-消费者消息队列 + 顺序处理"。

### 5.4 ping/pong 心跳

`startPingJob()`（`:887`）按 `pingInterval` 周期发 `ping` 与 `pingReq`（带 rtt 与时间戳）。`startPingTimeout`（`:899`）等 `pingTimeout`，超时则 `close(CLOSE_REASON_PING_TIMEOUT)`。收到 `Pong`/`PongResp` 时 `resetPingTimeout` 并计算 rtt。

### 5.5 SignalResponse 分发

`handleSignalResponseImpl`（`:743`）按 `messageCase` 分发到 `Listener`：

| SignalResponse | Listener 回调 | 最终去向 |
|---|---|---|
| ANSWER | `onServerAnswer` | publisher.setRemoteDescription |
| OFFER | `onServerOffer` | subscriber.setRemoteDescription + createAnswer |
| TRICKLE | `onTrickle` | publisher/subscriber.addIceCandidate |
| UPDATE | `onParticipantUpdate` | Room.onUpdateParticipants |
| TRACK_PUBLISHED | `onLocalTrackPublished` | 唤醒 pendingTrackResolvers |
| TRACK_SUBSCRIBED | `onLocalTrackSubscribed` | Room 事件 |
| SPEAKERS_CHANGED | `onSpeakersChanged` | Room 更新活跃说话者 |
| LEAVE | `onLeave` | RTCEngine 决定 resume/reconnect/断连 |
| MUTE | `onRemoteMuteChanged` | LocalParticipant 同步 mute |
| ROOM_UPDATE | `onRoomUpdate` | Room 更新元数据/录制状态 |
| CONNECTION_QUALITY | `onConnectionQuality` | Room 更新连接质量 |
| STREAM_STATE_UPDATE | `onStreamStateUpdate` | 更新轨道流状态 |
| SUBSCRIBED_QUALITY_UPDATE | `onSubscribedQualityUpdate` | dynacast 调整发布层 |
| SUBSCRIPTION_PERMISSION_UPDATE | `onSubscriptionPermissionUpdate` | 订阅权限变更 |
| REFRESH_TOKEN | `onRefreshToken` | 更新 sessionToken |
| TRACK_UNPUBLISHED | `onLocalTrackUnpublished` | LocalParticipant 取消发布 |
| PONG/PONG_RESP | 重置心跳超时 | — |

### 5.6 发送 API

`SignalClient` 提供一组 `sendXxx` 方法封装 `SignalRequest`：`sendOffer`/`sendAnswer`/`sendCandidate`/`sendMuteTrack`/`sendAddTrack`/`sendUpdateTrackSettings`/`sendUpdateSubscription`/`sendUpdateSubscriptionPermissions`/`sendUpdateLocalMetadata`/`sendSyncState`/`sendLeave`/`sendPing`/`sendUpdateLocalAudioTrack`。这些是 `RTCEngine` 与 `LocalParticipant` 操作服务器的底层通道。

---

## 第 6 章 媒体传输层 RTCEngine + PeerConnectionTransport

### 6.1 双 PeerConnection 模型

LiveKit 用 SFU（选择性转发单元）架构，客户端与服务器之间有两条 PeerConnection（`RTCEngine.kt:187`）：

- **publisher**：本地→服务器，承载本地发布的音视频轨道与上行 DataChannel。
- **subscriber**：服务器→本地，承载远端音视频轨道与下行 DataChannel。

`subscriberPrimary`（来自 `JoinResponse`）决定谁主导：
- **subscriber primary**（常见）：服务器在 subscriber 上主动开 DataChannel；publisher 的连接状态变化只在断开时触发重连，subscriber 的连接状态驱动 `connectionState`。
- **非 subscriber primary**：publisher 的连接状态驱动 `connectionState`，连接后立即 `negotiatePublisher()`。

两个 `PeerConnectionTransport` 各配一个 `TransportObserver`（`PublisherTransportObserver`/`SubscriberTransportObserver`），它们实现 `PeerConnection.Observer`，把 native 回调转译为对 `RTCEngine`/`SignalClient` 的调用。

### 6.2 PeerConnectionTransport 封装

`PeerConnectionTransport`（`room/PeerConnectionTransport.kt:70`）是单个 `PeerConnection` 的封装，`internal` 类，构造时即在 RTC 线程创建 native `PeerConnection`（`:85`）。关键职责：

- **ICE 候选管理**（`:105`）：`addIceCandidate` 在有 remoteDescription 且非 ICE restart 时直接加，否则缓存到 `pendingCandidates`，等 `setRemoteDescription` 成功后批量补加。
- **SDP 协商**（`negotiate` `:146`）：`debounce(20ms)` 防抖的"创建并发送 offer"。`createAndSendOffer`（`:155`）在 `offerLock` 内、RTC 线程上：处理 ICE restart、生成 offer、**SDP munge**、setLocalDescription、通过 `listener.onOffer` 回调发给 `SignalClient.sendOffer`。
- **offerId 去重**（`:99` `latestOfferId`）：用递增的 offerId 拒绝过期的 answer，避免竞态。
- **状态查询**（`isConnected`/`iceConnectionState`/`signalingState`）：都经 `launchRTCIfNotClosed` 投递到 RTC 线程执行。
- **关闭**（`close`/`closeBlocking`）：RTC 线程上 `peerConnection.dispose()` 并取消协程作用域。

### 6.3 SDP 协商流程

发布侧（publisher）协商由 `onRenegotiationNeeded` 触发（`PublisherTransportObserver.kt:56` → `engine.negotiatePublisher()`）：

```
native PC 需要重协商
  → PublisherTransportObserver.onRenegotiationNeeded()
  → RTCEngine.negotiatePublisher()  (negotiatePublisherMutex 加锁)
  → publisher.negotiate(constraints)  (debounce 20ms)
  → createAndSendOffer:
       ├─ createOffer(constraints)   [native]
       ├─ SDP munge: ensureVideoDDExtensionForSVC + ensureCodecBitrates
       ├─ setLocalDescription(munged) [native]
       └─ listener.onOffer(sd, offerId)
  → SignalClient.sendOffer(sd, offerId)  [WebSocket 发给服务器]
```

服务器应答：
```
SignalClient 收到 ANSWER
  → RTCEngine.onServerAnswer(sd, offerId)
  → publisher.setRemoteDescription(sd, offerId)
       ├─ offerId 校验（拒绝旧 offer）
       ├─ peerConnection.setRemoteDescription [native]
       └─ 补加 pendingCandidates
```

订阅侧（subscriber）协商由服务器主动发 offer：
```
SignalClient 收到 OFFER
  → RTCEngine.onServerOffer(sd, offerId)
  → subscriber.setRemoteDescription(sd, offerId)
  → subscriber.withPeerConnection { createAnswer() }
  → subscriber.setLocalDescription(answer)
  → SignalClient.sendAnswer(answer, offerId)
```

### 6.4 SDP munge（修改 SDP）

`createAndSendOffer` 在 setLocalDescription 前对 SDP 做"munge"（`PeerConnectionTransport.kt:206`）：

- **`ensureVideoDDExtensionForSVC`**（`:405`）：对 SVC 编解码器（AV1/VP9）手动添加 dependency descriptor RTP 头扩展（若 SDP 中缺失），保证 SVC 正常工作。
- **`ensureCodecBitrates`**（`:452`）：对 SVC 编解码器注入 `x-google-start-bitrate`（目标码率的 70%）与 `x-google-max-bitrate`，避免 SVC 启动码率过低导致前几秒模糊。

> **给 C++ 读者**：SDP munge 是 WebRTC 客户端的常见技巧——在 native 层生成 SDP 后、设置前，用文本解析（这里是 `javax.sdp`）修改某些字段，绕过 native API 不暴露的配置。类似 C++ 中"序列化后改字符串再反序列化"。

### 6.5 ICE / Trickle

ICE 候选用 trickle ICE：native `onIceCandidate` 回调（`PublisherTransportObserver.kt:48`）→ `SignalClient.sendCandidate` → 服务器转发。服务器侧候选通过 `SignalResponse.TRICKLE` → `RTCEngine.onTrickle`（`RTCEngine.kt:1152`）按 target 分发到 publisher/subscriber 的 `addIceCandidate`。ICE restart 通过 SDP 里的 `ICE_RESTART` 约束触发（`getPublisherOfferConstraints` `:916`），用于重连。

### 6.6 DataChannel 与可靠消息

`RTCEngine` 维护两条 DataChannel（`RTCEngine.kt:190`）：
- **reliable**（`_reliable`）：有序、可靠，用于需要保证送达的数据（RPC、数据流）。
- **lossy**（`_lossy`）：无序、最多 0 次重传，用于可丢弃的数据（说话者状态、低优先级消息）。

`DataChannelManager`（`webrtc/DataChannelManager.kt`）封装 DataChannel 的 observer 与缓冲状态。

**可靠消息重放**（`RTCEngine.kt:733` `sendData` / `:820` `resendReliableMessagesForResume`）：
- 每条可靠消息带递增 `sequence`，发送后入 `reliableMessageBuffer`（按 bufferedAmount 上限修剪）。
- 软重连成功后，服务器返回 `lastMessageSeq`，客户端 `popToSequence(lastMessageSeq)` 后重放缓冲中 sequence 之后的消息，保证 resume 不丢消息。
- 接收侧用 `reliableReceivedState`（TTLMap）去重，丢弃重复或乱序的可靠包（`:1300`）。

### 6.7 RTC 线程模型

WebRTC native API 非线程安全，必须单线程访问。SDK 用专用 RTC 线程（`webrtc/peerconnection/RTCThreadUtils.kt`）：

- **单线程执行器**（`:49`）：`Executors.newSingleThreadExecutor`，线程名前缀 `LK_RTC_THREAD_`。
- **`executeOnRTCThread`**（`:71`）：若已在 RTC 线程则直接执行，否则 `executor.submit`。非阻塞。
- **`executeBlockingOnRTCThread`**（`:96`）：同步阻塞提交并 `get()`，返回结果。
- **`launchBlockingOnRTCThread`**（`:119`）：协程版，用 `async(rtcDispatcher).await()` 在协程里阻塞投递。
- **`RTCThreadToken`**（`:144`）：绑定到 `PeerConnectionFactoryManager` 的生命周期令牌，`isDisposed` 时所有 RTC 调用短路返回 null，避免在 PCF 释放后访问 native 对象。

`PeerConnectionTransport` 的所有 native 操作都经 `launchRTCIfNotClosed`/`executeRTCIfNotClosed`（`PeerConnectionTransport.kt:360`）走 RTC 线程并检查 closed 状态。

> **给 C++ 读者**：这是"单线程化"并发模型——把所有对非线程安全资源的访问串行化到一个线程，用 future/协程等待结果，避免锁。比加细粒度锁更简单且无死锁。`RTCThreadToken` 类似"弱引用令牌"，资源释放后调用自动 no-op。

---

## 第 7 章 参与者模型 Participant

### 7.1 继承体系

```
Participant (open class)
├── LocalParticipant   (本地，可发布/订阅/RPC)
└── RemoteParticipant  (远端，只能订阅)
```

`Participant`（`room/participant/Participant.kt:54`）是基类，承载所有参与者共有状态。

### 7.2 Participant 基类

`Participant` 持有大量 `@FlowObservable` 状态（可观察，见第 12 章）：
- `sid` / `identity`：参与者标识（`value class`，强类型）
- `name` / `metadata` / `attributes` / `agentAttributes`：元数据
- `state`：`JOINING/JOINED/ACTIVE/DISCONNECTED/UNKNOWN`
- `kind`：`AGENT/STANDARD/INGRESS/EGRESS/SIP/CONNECTOR/BRIDGE/UNKNOWN`（区分普通用户与 AI agent 等）
- `audioLevel` / `isSpeaking` / `lastSpokeAt`：说话状态
- `connectionQuality`：连接质量
- `permissions`：`ParticipantPermission`（canPublish/canSubscribe/canPublishData/hidden/recorder/canPublishSources/canUpdateMetadata/canSubscribeMetrics）
- `trackPublications`：sid → TrackPublication 的映射
- `clientProtocol`：对端通告的客户端协议版本（用于 RPC v2 协商）

派生的只读 Flow（`Participant.kt:325`）：
- `audioTrackPublications` / `videoTrackPublications`：按类型过滤的发布列表
- `isMicrophoneEnabled` / `isCameraEnabled` / `isScreenShareEnabled`：从对应轨道的 muted 状态派生

事件：每个 `Participant` 有自己的 `events`（`BroadcastEventBus<ParticipantEvent>`），状态变化时通过 `flowDelegate` 的 `onSetValue` 回调发事件（如 `isSpeaking` 变化发 `SpeakingChanged`，`:136`）。

`updateFromInfo`（`:438`）：从服务器 `ParticipantInfo` protobuf 同步所有字段。

### 7.3 LocalParticipant

`LocalParticipant`（`room/participant/LocalParticipant.kt:94`）扩展了发布能力：

- **创建轨道**：`createAudioTrack` / `createVideoTrack`（相机）/ `createScreencastTrack`（屏幕共享），通过各自的 `Factory`（`@AssistedFactory`）创建。
- **便捷开关**：`setMicrophoneEnabled` / `setCameraEnabled` / `setScreenShareEnabled`（`:306`/`:290`/`:329`），内部 `setTrackEnabled(source)`（`:340`）用 `sourcePubLocks`（每个 source 一把 `Mutex`）串行化，避免并发创建多个相同 source 的 capturer（相机死锁问题）。
- **发布轨道**：`publishAudioTrack` / `publishVideoTrack`（`:449`/`:506`）→ `publishTrackImpl`（`:631`）：
  1. 权限校验 `hasPermissionsToPublish`
  2. 构造 `AddTrackRequest`（含 layers、simulcastCodecs、source 等）
  3. `negotiate()`：在 publisher PC 上 `addTransceiver`（SEND_ONLY），设置 codec 偏好、degradationPreference
  4. `requestAddTrack()`：`engine.addTrack`（suspend，等服务器 `TrackPublishedResponse`）
  5. 创建 `LocalTrackPublication`，加入 `trackPublications`，发事件
- **数据发布**：`publishData` / `publishDtmf`（`:1004`/`:1046`）→ `engine.sendData`（DataChannel）。
- **RPC**：实现 `RpcManager`，委托 `rpcClientManager`/`rpcServerManager`。
- **取消发布**：`unpublishTrack`（`:955`）：移除 sender、停止 transceiver（视频）、发事件。
- **重连恢复**：`prepareForFullReconnect`（`:1286`）保存待重发列表，`republishTracks`（`:1302`）在全量重连后重新发布。
- **dynacast**：`handleSubscribedQualityUpdate`（`:1177`）根据服务器反馈调整发布层/codec。

### 7.4 RemoteParticipant

`RemoteParticipant` 由 `remoteParticipantFactory.create(info)` 创建（`Room.kt:833`），主要承载订阅侧状态：`addSubscribedMediaTrack`（由 `Room.onAddTrack` 调用）把 native 收到的 `MediaStreamTrack` 包装成 `RemoteAudioTrack`/`RemoteVideoTrack` 并加入发布。其事件被 `Room` 收集转发为 `RoomEvent`（`Room.kt:837`）。

### 7.5 权限模型

发布前 `LocalParticipant.hasPermissionsToPublish`（`:607`）校验 `permissions.canPublish` 与 `canPublishSources`。订阅权限通过 `setTrackSubscriptionPermissions`（`:943`）→ `engine.updateSubscriptionPermissions` → 服务器，控制谁能订阅本端轨道。

---

## 第 8 章 轨道模型 Track 体系

### 8.1 Track 继承体系

```
Track (abstract)
├── AudioTrack (abstract)
│   ├── LocalAudioTrack
│   └── RemoteAudioTrack
└── VideoTrack (abstract)
    ├── LocalVideoTrack
    └── RemoteVideoTrack
        └── LocalScreencastVideoTrack (extends LocalVideoTrack)
```

`Track`（`room/track/Track.kt:35`）是基类，持有 `name`/`kind`/`sid`/`streamState`/`enabled`/`statsGetter`/`rtcThreadToken`。`enabled` 的 getter/setter 都经 `withRTCTrack` 在 RTC 线程操作 native track（`:57`）。`isDisposed` 直接查 native `rtcTrack.isDisposed`。

### 8.2 TrackPublication 体系

```
TrackPublication (open)
├── LocalTrackPublication
└── RemoteTrackPublication
```

`TrackPublication`（`room/track/TrackPublication.kt:28`）是"轨道发布信息"的抽象，持有 `track`（可空，订阅后才填充）、`sid`/`name`/`kind`/`muted`/`source`/`simulcasted`/`dimensions`/`mimeType`/`encryptionType`，以及 `participant` 的 `WeakReference`（防内存泄漏）。`muted` 与 `track` 都是 `@FlowObservable`。`updateFromInfo` 从 `TrackInfo` 同步。

### 8.3 本地视频轨道链路

`LocalVideoTrack`（`room/track/LocalVideoTrack.kt:65`）的创建链路（`createTrack` `:498`）：

```
LocalVideoTrack.createTrack
  ├─ peerConnectionFactory.createVideoSource(isScreencast)   [native]
  ├─ (可选) ScaleCropVideoProcessor 包裹用户 VideoProcessor
  ├─ source.setVideoProcessor(finalVideoProcessor)
  ├─ SurfaceTextureHelper.create("VideoCaptureThread", eglContext)  // 采集线程
  ├─ (可选) CaptureDispatchObserver 拦截原始帧给本地预览
  ├─ capturer.initialize(surfaceTextureHelper, context, capturerObserver)
  ├─ peerConnectionFactory.createVideoTrack(uuid, source)   [native]
  └─ trackFactory.create(...)  // @AssistedFactory 构造 LocalVideoTrack
```

数据流（采集→发布）：
```
Camera/MediaProjection
  → VideoCapturer (Camera2Capturer / ScreenCapturerAndroid)
  → SurfaceTextureHelper (专用采集线程，EGL 渲染)
  → VideoSource.capturerObserver
  → (VideoProcessor 链：ScaleCrop → 用户 Processor)
  → native VideoSource → native 编码器 → RTP
  → publisher PeerConnection → 服务器
```

关键能力：
- **`switchCamera`**（`:184`）：切换前后摄像头，等首帧确认后更新 options。
- **`restartTrack`**（`:267`）：用新 options 重建 capturer/source/rtcTrack，迁移 sinks。
- **`setPublishingLayers`**（`:321`）：dynacast——根据服务器反馈启用/禁用 simulcast 各层或 SVC 层级。
- **`setPublishingCodecs`**（`:388`）：处理服务器请求的 codec 切换，必要时触发备用 codec 发布。
- **Simulcast/SVC**：`simulcastCodecs` 映射 `VideoCodec → SimulcastTrackInfo`，`addSimulcastTrack`/`clearSimulcastCodecs` 管理多 codec 发布。

### 8.4 本地音频轨道链路

`LocalAudioTrack`（`room/track/LocalAudioTrack.kt:62`）创建链路（`createTrack` `:222`）：

```
LocalAudioTrack.createTrack
  ├─ MediaConstraints (echoCancellation/autoGainControl/noiseSuppression/...)
  ├─ factory.createAudioSource(constraints)   [native]
  ├─ factory.createAudioTrack(uuid, source)   [native]
  └─ audioTrackFactory.create(...)  // @AssistedFactory
```

数据流（采集→发布）：
```
麦克风 (AudioRecord, VOICE_COMMUNICATION 源)
  → JavaAudioDeviceModule (setSamplesReadyCallback → AudioRecordSamplesDispatcher)
  → native AudioSource → native 音频处理(AEC/NS/AGC + CustomAudioProcessingFactory)
  → native 编码器 → RTP
  → publisher PeerConnection → 服务器
```

关键能力：
- **`addSink`**（`:120`）：注册 `AudioTrackSink` 拿到麦克风原始 PCM（经 `AudioRecordSamplesDispatcher` 派发，依赖 `JavaAudioDeviceModule.setSamplesReadyCallback`）。
- **`setAudioBufferCallback`**（`:140`）：混入自定义音频。
- **`applyOptions`**（`:155`）：运行时更新音频处理选项（AEC/NS/AGC），通过 native `setAudioProcessingOptions`。
- **`features`**（`:180`）：派生 Flow，组合 options 特性与 `AudioProcessingController` 的后处理器（如 Krisp 降噪），上报给服务器。
- **`prewarm`**（`:104`）：通过 `AudioRecordPrewarmer` 预热录音栈，加快首次发布。

### 8.5 Simulcast / SVC / Dynacast / 备用编解码器

- **Simulcast**（多分辨率同发）：`computeVideoEncodings`（`LocalParticipant.kt:818`）按 capture 分辨率生成 h/m/l 三层 encoding（rid），从大到小排序。服务器按订阅者能力转发对应层。
- **SVC**（可伸缩编码，VP9/AV1）：单 encoding 带 `scalabilityMode`（如 `L3T3_KEY`），用 `setPublishingLayers` 切换层级而非多 encoding。SVC 强制开启 dynacast。
- **Dynacast**：`Room.dynacast` 开启后，服务器通过 `SUBSCRIBED_QUALITY_UPDATE` 反馈订阅者需要的质量，`LocalParticipant.handleSubscribedQualityUpdate` 调 `track.setPublishingLayers` 启停层，节省上行带宽/CPU。
- **备用编解码器**（`backupCodec`）：SVC codec（VP9/AV1）可能不被某些订阅者支持，服务器请求时 `publishAdditionalCodecForTrack`（`:1203`）额外发布一个 VP8/H264 编码的 simulcast track。

### 8.6 远端轨道与渲染

- **`RemoteVideoTrack`**（`room/track/RemoteVideoTrack.kt:40`）：订阅后由 `Room.onAddTrack` 创建。`addRenderer` 把 `VideoSink` 加到 native track。
- **adaptiveStream**（`autoManageVideo`）：开启后，`addRenderer` 传 `View` 时自动用 `ViewVisibility` 跟踪可见性与尺寸。`recalculateVisibility`（`:146`）在可见性/尺寸变化时发 `TrackEvent.VisibilityChanged`/`VideoDimensionsChanged`，上层据此通过 `sendUpdateTrackSettings` 让服务器只发需要的分辨率，不可见时暂停接收。
- **渲染视图**：`SurfaceViewRenderer`/`TextureViewRenderer`（`renderer/`），需先 `Room.initVideoRenderer` 用 `EglBase` 初始化。

---

## 第 9 章 完整业务流程：音频发布与订阅

本章把前面各层串起来，讲清音频从采集到对端播放的完整模块间数据流与控制流。

### 9.1 音频发布数据流（本地 → 服务器）

```
┌──────────────┐   PCM 16-bit   ┌──────────────────────────────┐
│ 麦克风硬件    │──────────────▶│ JavaAudioDeviceModule          │
│ (AudioRecord │                │  setSamplesReadyCallback       │
│  VOICE_COMM) │                │  → AudioRecordSamplesDispatcher │
└──────────────┘                └──────────────┬───────────────┘
                                               │ audio samples
                                               ▼
                                 ┌──────────────────────────────┐
                                 │ native AudioSource            │
                                 │ + CustomAudioProcessingFactory│
                                 │   (AEC/NS/AGC + 用户 Processor)│
                                 └──────────────┬───────────────┘
                                                │ processed PCM
                                                ▼
                                 ┌──────────────────────────────┐
                                 │ native 音频编码器 (Opus等)      │
                                 │ + DTX/RED (由 features 控制)   │
                                 └──────────────┬───────────────┘
                                                │ RTP packets
                                                ▼
                                 ┌──────────────────────────────┐
                                 │ publisher PeerConnection      │
                                 │  (RtpSender ← LocalAudioTrack │
                                 │   .transceiver)               │
                                 └──────────────┬───────────────┘
                                                │ SRTP/DTLS
                                                ▼
                                 ┌──────────────────────────────┐
                                 │ LiveKit SFU 服务器             │
                                 └──────────────────────────────┘
```

### 9.2 音频发布控制流

```
应用调用 room.connect(audio=true)
  → Room.connect → localParticipant.setMicrophoneEnabled(true)
  → LocalParticipant.setTrackEnabled(MICROPHONE)
  → getOrCreateDefaultAudioTrack() → LocalAudioTrack.createTrack
       (createAudioSource + createAudioTrack, native)
  → track.prewarm() / track.start()
  → publishAudioTrack(track)
  → publishTrackImpl:
       ├─ hasPermissionsToPublish 校验
       ├─ engine.addTrack(cid, name, AUDIO, ...)  [suspend, 等 TrackPublishedResponse]
       │    └─ SignalClient.sendAddTrack → 服务器 → TrackPublishedResponse
       │       └─ RTCEngine.onLocalTrackPublished → resume continuation
       ├─ engine.createSenderTransceiver(track.rtcTrack, SEND_ONLY)  [publisher PC]
       ├─ transceiver.sortVideoCodecPreferences / 设 degradationPreference
       └─ 创建 LocalTrackPublication, addTrackPublication, 发 TrackPublished 事件
  → (PublisherTransportObserver.onRenegotiationNeeded 自动触发)
  → engine.negotiatePublisher() → publisher.negotiate → createAndSendOffer
  → SignalClient.sendOffer → 服务器 → SignalClient.onServerAnswer
  → publisher.setRemoteDescription  [SDP 协商完成, 音频 RTP 开始上行]
  → 启动 features flow: track::features.flow.collect → engine.updateLocalAudioTrack
```

### 9.3 音频订阅数据流（服务器 → 本地播放）

```
┌──────────────────────────────┐
│ LiveKit SFU 服务器             │
└──────────────┬───────────────┘
               │ SRTP/DTLS (subscriber PC)
               ▼
┌──────────────────────────────┐
│ subscriber PeerConnection     │
│  (RtpReceiver → RemoteAudioTrack│
│   .receiver)                   │
└──────────────┬───────────────┘
               │ RTP packets
               ▼
┌──────────────────────────────┐
│ native 音频解码器 (Opus等)      │
└──────────────┬───────────────┘
               │ PCM
               ▼
┌──────────────────────────────┐
│ native AudioTrack → AudioTrack │
│  (JavaAudioDeviceModule 播放)  │
│  → 扬声器/听筒/蓝牙 (AudioSwitch)│
└──────────────────────────────┘
```

### 9.4 音频订阅控制流

```
服务器通知有远端音频轨道
  → (subscriber primary) 服务器在 subscriber PC 上发 offer
  → SignalClient.onServerOffer → RTCEngine.onServerOffer
  → subscriber.setRemoteDescription → createAnswer → setLocalDescription → sendAnswer
  → native onAddTrack(receiver, track, streams)
  → RTCEngine.onAddTrack → Room.onAddTrack
  → participant.addSubscribedMediaTrack(track, trackSid, ...)
  → 创建 RemoteAudioTrack (持 receiver)
  → RemoteTrackPublication.track = remoteAudioTrack
  → Room.onTrackSubscribed → RoomEvent.TrackSubscribed
  → (E2EE 若开启) E2EEManager.addSubscribedTrack 给 RtpReceiver 加 FrameCryptor
  → 应用可 remoteAudioTrack.addSink 拿 PCM，或直接由 native 播放
```

### 9.5 模块/文件夹间依赖关系（音频）

```
audio/                    提供 AudioHandler(AudioSwitchHandler)、AudioProcessingController、
                          AudioRecordPrewarmer、PreconnectAudioBuffer、ScreenAudioCapturer
   ↑ 被依赖
room/track/LocalAudioTrack  持有 audioProcessingController、audioRecordPrewarmer、dispatchers
   ↑ 被依赖
room/participant/LocalParticipant  创建/发布 LocalAudioTrack
   ↑ 被依赖
room/Room  编排，state 变化时启停 audioHandler
   ↑ 被依赖
room/RTCEngine  提供 addTrack/createSenderTransceiver/negotiatePublisher
   ↑ 被依赖
room/SignalClient  sendAddTrack/sendOffer/sendAnswer
   ↑ 被依赖
webrtc/ (native)  PeerConnectionFactory.createAudioSource/Track, AudioDeviceModule
```

### 9.6 关键时序：音频发布到首帧上行

```
T0  setMicrophoneEnabled(true)
T1  createAudioTrack (native source+track)
T2  engine.addTrack (sendAddTrack via WS)
T3  ← TrackPublishedResponse (服务器分配 sid)
T4  addTransceiver (publisher PC, SEND_ONLY)
T5  onRenegotiationNeeded → negotiatePublisher (debounce 20ms)
T6  createOffer → SDP munge → setLocalDescription
T7  sendOffer (WS)
T8  ← onServerAnswer → setRemoteDescription
T9  ICE 连通 → 音频 RTP 开始上行
T10 服务器转发给订阅者
```

---

## 第 10 章 完整业务流程：视频发布与订阅

### 10.1 视频发布数据流（本地 → 服务器）

```
┌───────────────┐  YUV frames  ┌──────────────────────────────┐
│ Camera2 /     │────────────▶│ VideoCapturer                 │
│ MediaProjection│             │ (Camera2Capturer/ScreenCapturer)│
└───────────────┘             └──────────────┬───────────────┘
                                              │
                                              ▼
                              ┌──────────────────────────────┐
                              │ SurfaceTextureHelper           │
                              │  (专用采集线程 + EGL)           │
                              └──────────────┬───────────────┘
                                              │ VideoFrame
                                              ▼
                              ┌──────────────────────────────┐
                              │ VideoSource.capturerObserver   │
                              │  + VideoProcessor 链            │
                              │   (ScaleCrop → 用户 Processor)  │
                              └──────────────┬───────────────┘
                                              │ processed VideoFrame
                                              ▼
                              ┌──────────────────────────────┐
                              │ native VideoSource             │
                              └──────────────┬───────────────┘
                                              │
                                              ▼
                              ┌──────────────────────────────┐
                              │ native 视频编码器               │
                              │  (VP8/H264/VP9/AV1)            │
                              │  Simulcast: 多层 / SVC: 多层级  │
                              └──────────────┬───────────────┘
                                              │ RTP packets (多层)
                                              ▼
                              ┌──────────────────────────────┐
                              │ publisher PeerConnection      │
                              │  (RtpSender ← LocalVideoTrack  │
                              │   .transceiver + simulcast)    │
                              └──────────────┬───────────────┘
                                              │ SRTP/DTLS
                                              ▼
                              ┌──────────────────────────────┐
                              │ LiveKit SFU 服务器             │
                              └──────────────────────────────┘
```

### 10.2 视频发布控制流

```
应用调用 room.connect(video=true) 或 setCameraEnabled(true)
  → LocalParticipant.setTrackEnabled(CAMERA)
  → getOrCreateDefaultVideoTrack() → LocalVideoTrack.createCameraTrack
       (权限检查 → CameraCapturerUtils.createCameraCapturer → createTrack)
  → track.start() / track.startCapture()
  → publishVideoTrack(track)
  → publishTrackImpl:
       ├─ 校验 enabledPublishVideoCodecs (服务器允许的 codec)
       ├─ isSVC 判断 → 强制 dynacast + backupCodec + scalabilityMode
       ├─ computeVideoEncodings (simulcast/SVC encodings)
       ├─ (若服务器支持多 codec) 并发: negotiate() || requestAddTrack()
       │   否则串行: requestAddTrack() → 回填 codec → negotiate()
       ├─ negotiate: addTransceiver(SEND_ONLY, encodings)
       │             sortVideoCodecPreferences
       │             set degradationPreference
       ├─ engine.addTrack (sendAddTrack, 含 layers + simulcastCodecs)
       ├─ 创建 LocalTrackPublication, 发 TrackPublished 事件
       └─ (onRenegotiationNeeded → negotiatePublisher → SDP 协商)
```

### 10.3 视频订阅数据流（服务器 → 本地渲染）

```
┌──────────────────────────────┐
│ LiveKit SFU 服务器             │
│  (按订阅者能力转发对应 simulcast 层)│
└──────────────┬───────────────┘
               │ SRTP/DTLS (subscriber PC)
               ▼
┌──────────────────────────────┐
│ subscriber PeerConnection     │
│  (RtpReceiver → RemoteVideoTrack│
│   .receiver)                   │
└──────────────┬───────────────┘
               │ RTP packets
               ▼
┌──────────────────────────────┐
│ native 视频解码器              │
│  (按 codec 选 hardware/software)│
└──────────────┬───────────────┘
               │ VideoFrame (I420/texture)
               ▼
┌──────────────────────────────┐
│ native VideoTrack             │
│  → 已 addSink 的 VideoSink 们  │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ SurfaceViewRenderer /          │
│ TextureViewRenderer (EGL 绘制) │
│  ← Room.initVideoRenderer 初始化│
└──────────────────────────────┘
```

### 10.4 视频订阅控制流

```
服务器通知远端视频轨道
  → (subscriber primary) 服务器发 offer
  → RTCEngine.onServerOffer → subscriber.setRemoteDescription → createAnswer → sendAnswer
  → native onAddTrack → Room.onAddTrack
  → participant.addSubscribedMediaTrack(track, trackSid, autoManageVideo=adaptiveStream)
  → 创建 RemoteVideoTrack (持 receiver, autoManageVideo 标志)
  → Room.onTrackSubscribed → RoomEvent.TrackSubscribed
  → (E2EE) E2EEManager.addSubscribedTrack 给 RtpReceiver 加 FrameCryptor
  → 应用: remoteVideoTrack.addRenderer(surfaceViewRenderer)
       └─ 若 autoManageVideo: 用 ViewVisibility 跟踪可见性
            → recalculateVisibility → TrackEvent.VisibilityChanged/VideoDimensionsChanged
            → 上层 sendUpdateTrackSettings (按尺寸选分辨率, 不可见则暂停)
```

### 10.5 adaptiveStream / dynacast 控制回路

这是 SDK 的带宽自适应核心，两条回路：

**adaptiveStream（订阅侧驱动）**：
```
RemoteVideoTrack 的 renderer 可见性/尺寸变化
  → recalculateVisibility → TrackEvent
  → (上层/SDK) sendUpdateTrackSettings(sid, disabled, dimensions, quality)
  → 服务器只发对应分辨率的层；不可见时暂停
```

**dynacast（发布侧驱动）**：
```
服务器根据所有订阅者的需求汇总
  → SignalResponse.SUBSCRIBED_QUALITY_UPDATE
  → RTCEngine.onSubscribedQualityUpdate → LocalParticipant.handleSubscribedQualityUpdate
  → (dynacast 开启) track.setPublishingLayers(qualities)
       ├─ SVC: 调 encoding.active 启停整个 SVC 层级
       └─ Simulcast: 按 rid 启停各层 encoding
  → native 编码器相应启停层，节省上行带宽/CPU
```

### 10.6 模块/文件夹间依赖关系（视频）

```
room/track/video/          CameraCapturerUtils, VideoProcessor 链, CaptureDispatchObserver,
                          ScaleCropVideoProcessor, VideoSinkVisibility, ScalabilityMode
room/track/screencapture/  ScreenCaptureService (前台服务), ScreenCaptureConnection
   ↑ 被依赖
room/track/LocalVideoTrack / LocalScreencastVideoTrack
   ↑ 被依赖
room/participant/LocalParticipant  computeVideoEncodings, publishVideoTrack
   ↑ 被依赖
room/Room  adaptiveStream 标志传递, initVideoRenderer
   ↑ 被依赖
room/RTCEngine  createSenderTransceiver, registerTrackBitrateInfo, negotiatePublisher
   ↑ 被依赖
room/SignalClient  sendAddTrack, sendUpdateTrackSettings
   ↑ 被依赖
webrtc/  CustomVideoEncoderFactory/DecoderFactory, SimulcastVideoEncoderFactoryWrapper,
        PeerConnectionExt, RtpTransceiverExt, SdpExt
renderer/  SurfaceViewRenderer, TextureViewRenderer (EGL)
```

### 10.7 关键时序：视频发布到首帧上行

```
T0  setCameraEnabled(true)
T1  createCameraTrack (权限检查 → capturer → source → rtcTrack)
T2  startCapture (Camera2 开始出帧)
T3  engine.addTrack (sendAddTrack, 含 layers + simulcastCodecs)
T4  ← TrackPublishedResponse
T5  addTransceiver (publisher PC, SEND_ONLY, encodings)
T6  sortVideoCodecPreferences (按 videoCodec 排序)
T7  onRenegotiationNeeded → negotiatePublisher (debounce 20ms)
T8  createOffer → SDP munge (DD ext + bitrate) → setLocalDescription
T9  sendOffer → ← onServerAnswer → setRemoteDescription
T10 ICE 连通 → 视频 RTP 多层开始上行
T11 服务器转发 → 订阅者解码 → 渲染首帧
```

---

## 第 11 章 数据通道与数据流（DataChannel / DataStream / RPC）

### 11.1 DataChannel 基础

`RTCEngine` 在 publisher PC 上创建两条 DataChannel（`RTCEngine.kt:345`/`:371`）：
- `_reliable`：有序可靠，用于 RPC、数据流。
- `_lossy`：无序无重传，用于可丢弃消息。

发送：`engine.sendData(dataPacket)`（`:733`）→ 选 channel → `channel.send(Buffer)`。可靠消息带 sequence 并入重放缓冲。接收：`DataChannelObserver.onMessage`（`:1293`）→ 解析 `DataPacket` → 按 `valueCase` 分发（SPEAKER/USER/TRANSCRIPTION/RPC_*/STREAM_*）。

### 11.2 用户数据 publish/receive

发布：`LocalParticipant.publishData`（`LocalParticipant.kt:1004`）构造 `UserPacket`（payload/topic/destinationIdentities）→ `engine.sendData`。
接收：`RTCEngine.onMessage` 的 `USER` 分支 → `Room.onUserPacket`（`Room.kt:1326`）→ `RoomEvent.DataReceived`。

### 11.3 DataStream（文本/字节流）

DataStream 支持大块数据的流式传输（突破单包 15KB 限制），分 incoming/outgoing：

**incoming**（`room/datastream/incoming/`）：
- `IncomingDataStreamManager`（`:91`）按 topic 注册 `TextStreamHandler`/`ByteStreamHandler`。
- 收到 `STREAM_HEADER` → `openStream` 创建 `Channel<ByteArray>` 并调用对应 handler（`TextStreamReceiver`/`ByteStreamReceiver` 从 channel 读）。
- 收到 `STREAM_CHUNK` → `channel.trySend`；`STREAM_TRAILER` → `channel.close`（成功/异常）。
- `Room` 在 init 时为 RPC v2 注册了 `lk.rpc_request`/`lk.rpc_response` 两个保留 topic（`Room.kt:167`）。

**outgoing**（`room/datastream/outgoing/`）：
- `OutgoingDataStreamManager`（`LocalParticipant` 通过 by 委托继承）提供 `sendText`/`sendBytes`，把数据切成 chunk 通过 `engine.sendData` 发 `STREAM_HEADER`/`STREAM_CHUNK`/`STREAM_TRAILER`。

### 11.4 RPC 机制

RPC 让一个参与者调用另一个参与者上注册的方法，分 v1/v2：

- **`RpcManager`**（`room/rpc/RpcManager.kt`）：接口，`registerRpcMethod`/`unregisterRpcMethod`/`performRpc`。`Room` 与 `LocalParticipant` 都实现它，`Room` 委托给 `LocalParticipant`。
- **调用方**（`RpcClientManager`）：`performRpc` 构造 `RpcRequest` → `engine.sendData`，等 `RpcResponse`/`RpcAck`（带超时）。
- **被调方**（`RpcServerManager`）：收到 `RpcRequest` → 查注册的 `RpcHandler`（`suspend (RpcInvocationData) -> String`）→ 返回结果或 `RpcError`。
- **v1**：请求与响应内联在 `DataPacket` 中，payload 限 15KB。
- **v2**：请求与成功响应用 text data stream 传输（topic `lk.rpc_request`/`lk.rpc_response`），突破 15KB 限制。由 `ClientProtocolVersion.DATA_STREAM_RPC` 协商，`Room` 在 init 时根据对端 `clientProtocol` 决定走 v1 还是 v2（`Room.kt:179` 的 `getRemoteClientProtocol`）。

`LocalParticipant.handleDataPacket`（`:1075`）区分 `rpcRequest`/`rpcResponse`/`rpcAck` 分别交给 server/client manager。

---

## 第 12 章 事件体系

### 12.1 BroadcastEventBus

`events/BroadcastEventBus.kt` 是事件总线基础，基于 `MutableSharedFlow`（`extraBufferCapacity = Int.MAX_VALUE`，不丢事件）。提供 `postEvent`（suspend）/`tryPostEvent`/`postEvent(scope)`（异步）。`EventListenable` 暴露只读 `events: SharedFlow<T>`，用户用 `room.events.collect { ... }` 订阅。

### 12.2 事件类型层次

```
Event (base)
├── RoomEvent (sealed, room.events)
│   ├── Connected / Reconnecting / Reconnected / Disconnected / FailedToConnect
│   ├── ParticipantConnected / ParticipantDisconnected
│   ├── ParticipantMetadataChanged / ParticipantAttributesChanged / ParticipantNameChanged / ParticipantStateChanged
│   ├── ParticipantPermissionsChanged
│   ├── TrackPublished / TrackPublicationFailed / TrackUnpublished
│   ├── TrackSubscribed / TrackSubscriptionFailed / TrackUnsubscribed
│   ├── TrackMuted / TrackUnmuted / TrackStreamStateChanged / TrackSubscriptionPermissionChanged
│   ├── TrackE2EEStateEvent / LocalTrackSubscribed
│   ├── DataReceived / ConnectionQualityChanged / ActiveSpeakersChanged
│   ├── RoomMetadataChanged / RecordingStatusChanged / TranscriptionReceived
├── ParticipantEvent (sealed)   // participant 内部事件，Room 转译为 RoomEvent
├── TrackEvent (sealed)          // track 内部事件
└── TrackPublicationEvent (sealed)
```

### 12.3 事件传递路径

事件从底层到上层的典型路径：

```
native / 服务器消息
  → RTCEngine (SignalClient.Listener) 收到信号
  → Room (RTCEngine.Listener) 处理
  → 更新 Participant/Track 状态 (flowDelegate 触发)
  → eventBus.postEvent(RoomEvent)
  → room.events (SharedFlow) → 应用 collect
```

例：服务器发 `SPEAKERS_CHANGED`：
```
SignalClient.onSpeakersChanged → RTCEngine.onSpeakersChanged
  → Room.onSpeakersChanged → handleSpeakersChanged
  → 更新 participant.audioLevel/isSpeaking (flowDelegate)
  → eventBus.postEvent(RoomEvent.ActiveSpeakersChanged)
  → room.events.collect
```

`Participant` 的状态变化事件（`ParticipantEvent`）由 `Room.setupLocalParticipantEventHandling`（`Room.kt:700`）和 `getOrCreateRemoteParticipant`（`:837`）收集，转译为对应 `RoomEvent`。

### 12.4 @FlowObservable 机制

`util/FlowDelegate.kt` 是 SDK 响应式状态的核心。用法：

```kotlin
@FlowObservable
@get:FlowObservable
var identity: Identity? by flowDelegate(identity)
```

`flowDelegate` 返回 `MutableStateFlowDelegate`，它：
- 包装一个 `MutableStateFlow<T>`，`getValue` 返回 `flow.value`，`setValue` 更新 flow 并触发 `onSetValue` 回调。
- 通过 `DelegateAccess` 的 `ThreadLocal` 技巧：当用 `participant::identity.flow` 访问时，`KProperty0.delegate` 扩展（`:48`）触发一次 `get()`，期间 `MutableStateFlowDelegate.getValue` 把自身塞进 `DelegateAccess.delegate`，从而拿到底层 `StateFlow`。

这样同一个属性既能当普通变量用（`participant.identity`），又能当 Flow 观察（`participant::identity.flow.collectAsState()`），对 Compose 友好。

`onSetValue` 回调用于发事件：如 `Participant.isSpeaking` 变化时发 `SpeakingChanged`（`Participant.kt:136`），`Room.state` 变化时启停音频（`Room.kt:239`）。

> **给 C++ 读者**：`@FlowObservable` 类似"可观察属性 + 信号槽"。`flowDelegate` 是属性委托，等价于 C++ 中"用代理对象封装一个带订阅者的变量"。`DelegateAccess` 的 ThreadLocal 反射技巧是为了让 `::prop.flow` 这种"属性引用"能拿到内部的 StateFlow，因为 Kotlin 反射不直接暴露委托实例。

---

## 第 13 章 端到端加密 E2EE

### 13.1 概述

E2EE 确保只有持有密钥的参与者能解密媒体/数据，服务器（SFU）无法解密。本 SDK 的 E2EE 分两条线：媒体帧加密（`FrameCryptor`）与数据包加密（`DataPacketCryptorManager`）。

### 13.2 E2EEManager

`e2ee/E2EEManager.kt:43` 是 E2EE 入口，`@AssistedInject` 构造，需 `KeyProvider`。

**媒体帧加密**（per-track）：
- `addPublishedTrack`（`:140`）：对本地 track 的 `RtpSender` 创建 `FrameCryptor`（`FrameCryptorFactory.createFrameCryptorForRtpSender`），native 层在编码后/发送前加密每帧。
- `addSubscribedTrack`（`:106`）：对远端 track 的 `RtpReceiver` 创建 `FrameCryptor`，接收后/解码前解密。
- `setObserver` 监听加密状态变化 → `RoomEvent.TrackE2EEStateEvent`（OK/MISSING_KEY/ENCRYPTION_FAILED 等）。
- `enabled` 切换时批量启停所有 `frameCryptor`。

**数据包加密**（DataChannel）：
- `DataPacketCryptorManager`（`e2ee/DataPacketCryptorManager.kt`）用 `KeyProvider` 的密钥做 AES-GCM 加解密。
- `RTCEngine.sendData`（`:748`）：若 `dataChannelEncryptionEnabled`，把 `DataPacket` 的 payload 包装成 `EncryptedPacketPayload` → `e2EEManager.encrypt` → 替换为 `EncryptedPacket`。
- `RTCEngine.onMessage`（`:1313`）：收到 `EncryptedPacket` → `dataPacketCryptor.decrypt` → 还原 payload。

### 13.3 KeyProvider

`e2ee/KeyProvider.kt` 管理密钥：`rtcKeyProvider`（给 `FrameCryptor` 用）、`getLatestKeyIndex`、`ratchetSharedKey`（密钥轮换）、`setSifTrailer`（服务器下发的 SIF trailer，用于密钥派生）。

### 13.4 集成点

- `Room.connect` 时若 `e2eeOptions != null`：创建 `E2EEManager`，`setup(room)` 遍历已有 track 注册，并赋给 `engine.e2EEManager`（`Room.kt:488`）。
- `Room.onJoinResponse`：设置 `sifTrailer`（`Room.kt:677`）。
- `Room.onTrackPublished`/`onTrackSubscribed`：注册对应 `FrameCryptor`（`Room.kt:1544`/`:1562`）。
- `Room.onTrackUnpublished`/`onTrackUnsubscribed`：移除。
- `cleanupRoom` 时 `e2eeManager.dispose()`。

---

## 第 14 章 音频设备与音频处理子系统

`audio/` 目录负责 Android 音频设备管理、音频焦点、采集前后处理、以及若干设备/系统兼容性 workaround。它不直接做编解码（编解码在 WebRTC native 层），而是为 WebRTC 的 `JavaAudioDeviceModule`（ADM）准备环境、注入处理逻辑。

### 14.1 AudioHandler：音频生命周期入口

`AudioHandler`（`audio/AudioHandler.kt`）是极简接口：`start()` / `stop()`。`Room` 在连接建立/断开时调用它（`Room.kt` 的 `startAudio`/`stopAudio`）。有三个实现，通过 `LiveKitOverrides` 或 `RoomOptions.audioTrackPublishDefaults` 选择：

- **`AudioSwitchHandler`**（`audio/AudioSwitchHandler.kt`，363 行）：默认实现，基于 Twilio 的 AudioSwitch 库。内部用 `HandlerThread` 跑设备监听，维护 `preferredDeviceList`，在设备插拔时 `selectDevice` 自动切换到最优设备（扬声器/听筒/蓝牙耳机/有线耳机）。`start()` 注册 `AudioManager.AudioDeviceCallback` 并激活音频路由；`stop()` 还原。
- **`AudioFocusHandler`**（`audio/AudioFocusHandler.kt`）：只管音频焦点（`AudioManager.requestAudioFocus` / `abandonAudioFocus`），不管设备路由。`focusMode` 默认 `AUDIOFOCUS_GAIN`，Android O+ 用 `AudioFocusRequest`，低版本用旧 API。适合不希望 SDK 接管设备切换、只想要焦点的场景。
- **`NoAudioHandler`**：空实现，SDK 完全不碰音频设备/焦点，由应用自行管理。

> **给 C++ 读者**：Android 音频是"系统级共享资源"。`AudioManager` 管路由（哪个设备出声）和焦点（谁能发声）。焦点类似"互斥锁"——电话来了会抢走焦点，你的播放要暂停或降音量。AudioSwitch 解决的是"插入蓝牙耳机后声音要不要切过去"这类路由问题。

### 14.2 AudioProcessingController：采集/渲染前后处理

`AudioProcessingController`（`audio/AudioProcessingController.kt`）暴露两个注入点：
- `capturePostProcessor`：采集后、编码前处理（如自定义降噪）。
- `renderPreProcessor`：解码后、播放前处理。
- `bypassCapturePostProcessing` / `bypassRenderPreProcessing`：运行时旁路开关。

全部用 `@FlowObservable` 声明，意味着应用可以 `controller::capturePostProcessor.flow.collect` 观察变化。`AudioProcessorInterface` 是处理接口（`processAudio` 收发 PCM）。实现通过 `RTCModule` 注入到 WebRTC ADM 的 audio processing 链路。

`AuthedAudioProcessingController` 扩展接口加 `authenticate(url, token)`，用于需要鉴权的云端音频处理（如 LiveKit 的 noise cancellation cloud 服务）。

### 14.3 AudioRecordSamplesDispatcher：原始 PCM 分发

`AudioRecordSamplesDispatcher`（`audio/AudioRecordSamplesDispatcher.kt`）实现 WebRTC 的 `SamplesReadyCallback`。WebRTC ADM 在采集到 10ms PCM 帧时回调 `onWebRtcAudioRecordSamplesReady`，它把 `AudioSamples` 转成 `AudioTrackSink.onData` 格式分发给所有注册的 sink。`RTCModule`（`:154`）创建 ADM 时 `setSamplesReadyCallback(this)` 注入它。

`LocalAudioTrack.addSink`（`LocalAudioTrack.kt`）把 sink 注册到这个 dispatcher，从而让外部能拿到原始采集 PCM——这是 `PreconnectAudioBuffer` 能缓冲语音的前提。

### 14.4 CommunicationWorkaround：通信模式保活

`CommunicationWorkaround`（`audio/CommunicationWorkaround.kt`）针对 Android 11+ 的 bug（[issuetracker 209493718](https://issuetracker.google.com/issues/209493718)）：通信模式（`USAGE_VOICE_COMMUNICATION`）下若 6 秒无播放/采集，系统会重置音频模式导致后续播放异常。

`CommunicationWorkaroundImpl` 的解法：用一个静音的 `AudioTrack`（`MODE_STATIC` + 循环空 buffer）在"已启动但播放停止"期间持续播放静音帧，骗系统保持通信模式不重置。状态机由 `started` + `playoutStopped` 两个 `MutableStateFlow` 驱动，`combine` + `collectLatest` 响应变化。`NoopCommunicationWorkaround` 是低版本/禁用时的空实现。

> **给 C++ 读者**：这是典型的"对抗系统行为"的 workaround。等价于在 C++ 里开一个静音线程持续写音频设备，防止设备进入低功耗休眠。`AtomicBoolean` + `synchronized` 保证 AudioTrack 操作线程安全。

### 14.5 AudioRecordPrewarmer：采集预热

`AudioRecordPrewarmer`（`audio/AudioRecordPrewarmer.kt`）解决首次采集的冷启动延迟。`JavaAudioRecordPrewarmer.prewarm` 调用 `audioDeviceModule.prewarmRecording(AudioProcessingOptions)`，提前初始化录音链路（AEC/NS/AGC/HPF 配置）。`LocalAudioTrack.prewarm`（`:104`）触发它，配合 `PreconnectAudioBuffer` 在真正发布前就启动采集。

### 14.6 PreconnectAudioBuffer：预连接音频缓冲

`PreconnectAudioBuffer`（`audio/PreconnectAudioBuffer.kt`）是 LiveKit Agents 场景的优化：用户连进房间前就开始说话，把语音缓冲下来；当 Agent（远端参与者）连入并订阅了本地音频，就把缓冲的语音通过 DataStream（`streamBytes`）发给 Agent，让 Agent "提前听到"用户开头的话，降低感知延迟。

机制：
- 实现 `AudioTrackSink`，`onData` 把 PCM 写入 `ByteArrayOutputStream`，限时 `TIMEOUT`（10s）。
- `startPreconnectAudioJob` 监听 `RoomEvent`：`LocalTrackSubscribed`（Agent 订阅了本地音频）→ 停止录制；`ParticipantConnected`/`ParticipantStateChanged` 且对方是 `Kind.AGENT` 且 `ACTIVE` → 用 `localParticipant.streamBytes` 把缓冲字节流发给该 Agent。
- `withPreconnectAudio` 是给应用用的顶层封装（已 `@Deprecated`，推荐用 `RoomOptions.audioTrackPublishDefaults.preconnect`）。

> **给 C++ 读者**：这是"用空间换时间"——把用户开口的最初几秒音频先存内存，等对端就绪再补发。DataStream 的 `streamBytes` 把大块 PCM 切成 chunk 走可靠 DataChannel 传输。`engine::connectionState.flow.takeWhile { it != CONNECTED }.collect()` 是协程写法，等价于"阻塞等到连接成功"。

### 14.7 音频子系统类图

```
                    AudioHandler (interface)
                    /       |        \
        AudioSwitchHandler  AudioFocusHandler  NoAudioHandler
        (Twilio AudioSwitch,  (AudioManager      (空)
         设备路由切换)         焦点)

   AudioProcessingController (interface, @FlowObservable)
   ├── capturePostProcessor : AudioProcessorInterface?
   ├── renderPreProcessor   : AudioProcessorInterface?
   └── bypass* : Boolean
        │
   AuthedAudioProcessingController (+authenticate)

   AudioRecordSamplesDispatcher ──implements──> SamplesReadyCallback (WebRTC ADM)
        │ onWebRtcAudioRecordSamplesReady
        └── 分发到 AudioTrackSink 集合
                ↑
   PreconnectAudioBuffer ──implements──> AudioTrackSink
        │ onData 缓冲 PCM
        └── sendAudioData → localParticipant.streamBytes (DataStream)

   CommunicationWorkaround (interface)
   ├── NoopCommunicationWorkaround
   └── CommunicationWorkaroundImpl (Android 11+, 静音 AudioTrack 保活)

   AudioRecordPrewarmer (interface)
   ├── NoAudioRecordPrewarmer
   └── JavaAudioRecordPrewarmer (audioDeviceModule.prewarmRecording)
```

### 14.8 音频子系统与 Room/Track 的集成

```
Room.connect
  → audioHandler.start()              // AudioSwitch 接管设备路由
  → (若 preconnect) startPreconnectAudioJob
       → getOrCreateDefaultAudioTrack
       → audioTrack.addSink(PreconnectAudioBuffer)
       → audioTrack.prewarm()         // AudioRecordPrewarmer 预热

LocalAudioTrack.createTrack
  → PeerConnectionFactory.createAudioSource
  → ADM (JavaAudioDeviceModule, RTCModule 提供)
       ├── setSamplesReadyCallback(AudioRecordSamplesDispatcher)
       └── audioProcessing ← AudioProcessingController 的 processor

Room.disconnect / cleanupRoom
  → audioHandler.stop()
  → communicationWorkaround.stop()
  → preconnectAudioBuffer.clear()
```

---

## 第 15 章 工程特点总结与 Android SDK 分析方法论

### 15.1 工程特点

#### 15.1.1 全协程化（Coroutine-first）

整个 SDK 以 Kotlin 协程为并发骨架，几乎不用裸线程/回调：
- `Room`、`RTCEngine` 持有 `CloseableCoroutineScope`（`SupervisorJob` + 指定 dispatcher），子协程失败不传染父级。
- `suspend` 函数贯穿连接、发布、订阅、RPC 全链路，调用方可用同步写法写异步逻辑。
- `Flow` / `StateFlow` / `SharedFlow` 用于状态暴露与事件流：`connectionState`、`events`、`@FlowObservable` 属性。
- `Mutex`（如 `LocalParticipant.sourcePubLock`）替代 `synchronized` 做协程友好的互斥。

> **C++ 对照**：协程 ≈ C++20 协程 + 一个运行时调度器。`suspend fun` ≈ 返回 `co_await` 的函数，`Flow` ≈ 可订阅的异步序列（类似 Rx 但语言级）。优势是异步代码线性化、无回调地狱；代价是要理解 dispatcher（协程跑在哪个线程/线程池）。

#### 15.1.2 响应式属性 @FlowObservable

SDK 自研的 `flowDelegate` 让普通属性同时具备"变量读写"和"Flow 订阅"两种语义，对 Compose 尤其友好（`collectAsState` 直接驱动 UI 重组）。`DelegateAccess` 的 ThreadLocal 反射技巧是点睛之笔——绕过 Kotlin 反射不暴露委托实例的限制。

#### 15.1.3 Dagger 2 依赖注入

- 全 SDK 用 Dagger 2 管理对象图，`@Singleton` 控制生命周期，`@Named` 区分多实例（如多个 dispatcher）。
- `@AssistedInject` + `@AssistedFactory` 处理"运行时参数 + 依赖注入"混合构造（`Room` 需要 `ctx` 又需要注入 `RTCEngine`）。
- `LiveKitOverrides` 提供扩展点：应用可替换 `okHttpClient`、`videoEncoderFactory`、`audioHandler`、`eglBase` 等关键实现，无需改 SDK 源码。

> **C++ 对照**：Dagger ≈ 编译期生成工厂代码的 IoC 容器。相比手写工厂，它集中管理依赖图、自动解析顺序、支持作用域。代价是注解处理器（kapt/ksp）增加编译时间，错误信息晦涩。

#### 15.1.4 RTC 线程安全模型

WebRTC 对线程亲和性要求严格（同 PeerConnection 的操作必须在同一线程）。SDK 用 `RTCThreadUtils`（`webrtc/peerconnection/RTCThreadUtils.kt`）封装：
- `LK_RTC_THREAD_` 单线程 executor 作为 RTC 线程。
- `executeOnRTCThread` / `executeBlockingOnRTCThread` / `launchBlockingOnRTCThread` 把操作投递到该线程。
- `RTCThreadToken` 接口标记"必须在 RTC 线程调用"的对象（如 `PeerConnectionFactoryManager.dispose`）。

> **C++ 对照**：等价于"所有 libwebrtc 调用都 Post 到一个 `std::thread` 的任务队列"。这避免了多线程同时操作 PC 导致的 native 崩溃。

#### 15.1.5 防御式错误处理

- 重连：`ReconnectPolicy` 指数退避，区分 soft resume（信令重连，复用 PC）与 full reconnect（重建一切）。
- 可靠消息重放：`DataPacketBuffer` + `reliableReceivedState`（TTLMap 去重），resume 时 `resendReliableMessagesForResume` 重发未确认消息。
- SDP munge：在协商失败/需要微调时不重新协商，直接改 SDP 文本（加 DD extension、改 codec bitrate）。
- ICE restart：连通失败时触发 ICE restart 重新收集候选。
- 处处 `try/catch` + `LKLog`，单个 track/参与者失败不影响整体。

#### 15.1.6 可测试性与可观测性

- 接口先行：`AudioHandler`、`RpcManager`、`IncomingDataStreamManager`、`CommunicationWorkaround` 都是接口，便于 mock。
- `@VisibleForTesting` 标注内部可测入口。
- `LKLog` 统一日志（`util/LKLog.kt`），带 lambda 懒求值，可按级别过滤。
- `OverridesModule` 让测试可注入假实现。

#### 15.1.7 native 边界清晰

- `org.webrtc` / `livekit.org.webrtc` 包是 Java 绑定层，JNI 到 C++ libwebrtc。
- SDK 不直接写 JNI，而是通过 Google 提供的 Java API（`PeerConnectionFactory`、`VideoCapturer`、`AudioDeviceModule`）操作 native。
- `PeerConnectionFactoryManager` 集中管理 native 工厂生命周期，`dispose()` 必须在 RTC 线程。
- `FrameCryptor` / `DataPacketCryptor` 是少数需要触及 native 帧加密的地方。

### 15.2 类比 C++ 的整体视角

| 维度 | C++ 习惯 | 本 SDK (Kotlin/Android) |
|------|---------|----------------------|
| 并发 | `std::thread` + mutex + condition_variable | 协程 + `Mutex` + `Flow` |
| 资源管理 | RAII 析构 | `CloseableCoroutineScope`、`dispose()`、`use{}` |
| 事件 | 信号槽/回调 | `SharedFlow.collect` |
| 可观察属性 | getter + observer 列表 | `@FlowObservable` + `flowDelegate` |
| 对象创建 | 工厂/手写 new | Dagger DI |
| 线程亲和 | `PostTask` 到单线程 | `executeOnRTCThread` |
| 跨语言 | — | Kotlin→Java→JNI→C++(libwebrtc) |
| 错误 | 异常/返回码 | `try/catch` + `Result` + `rethrowIfCancellationSignal` |

### 15.3 通用的 Android SDK 分析思路与方法

分析一个陌生 Android SDK，可按以下步骤系统展开：

**第一步：找入口**
- 找 `object` / `class` 上的 `@JvmStatic` 方法、`Application.onCreate` 钩子、`ContentProvider` 自动初始化、Manifest 中的 `meta-data`。
- 本例：`LiveKit.create()` 是唯一入口。入口往往揭示"对象图怎么建"。

**第二步：画依赖图（DI）**
- 若用 Dagger/Hilt：从 `@Component` → `@Module` → `@Provides` 顺藤摸瓜，理出"谁创建谁、谁是单例"。
- 若无 DI：从构造函数参数倒推。
- 这一步定下"骨架对象"（本例：Room、RTCEngine、SignalClient、PeerConnectionFactory）。

**第三步：分层**
- 把文件按"API 门面 / 编排 / 传输 / 平台 native"分层，看依赖是否单向向下。本例四层清晰。
- 看目录命名：`room/`、`audio/`、`e2ee/`、`dagger/`、`webrtc/`、`events/`、`util/` 已暗示职责。

**第四步：抓状态机**
- 找 `enum class State`、`sealed class`、`when(state)`。本例 `Room.State`、`ConnectionState` 是连接生命周期的核心。
- 画状态转移图：什么事件触发什么迁移。

**第五步：抓线程模型**
- 搜 `CoroutineDispatcher`、`HandlerThread`、`Executor`、`Thread`。
- 厘清"哪类操作跑在哪个线程/线程池"。本例：RTC 单线程、IO dispatcher、主线程 UI。
- 特别注意 native 库的线程亲和要求（WebRTC 必须单线程）。

**第六步：抓事件流**
- 找 `Flow`/`LiveData`/`BroadcastReceiver`/回调注册。
- 从底层 native/网络事件追到顶层 API 事件，画"事件传递路径"。本例：SignalClient→RTCEngine→Room→eventBus→应用。

**第七步：抓 native 边界**
- 搜 `external fun`、`System.loadLibrary`、JNI 包名（`org.webrtc`）。
- 厘清"哪些功能是 Java/Kotlin 实现，哪些是 C++ 实现"。本例编解码、网络传输、媒体加密都在 native。

**第八步：抓关键业务流程**
- 选 1-2 个端到端业务（本例音频、视频），从用户 API 调用追到 native 再回来，画数据流 + 控制流时序图。
- 这一步验证前七步的理解是否正确。

**第九步：看工程化**
- 测试目录结构、`build.gradle` 的依赖与插件、CI 配置、lint/detekt 规则、`@VisibleForTesting`/`@Deprecated` 的使用。
- 评估可测试性、可扩展性（override 点）、可观测性（日志/指标）。

**第十步：读 README / samples / changelog**
- 官方文档和示例代码揭示"设计意图"——为什么这么设计，典型用法是什么。
- `samples/` 目录的调用顺序往往就是推荐用法。

**通用工具**：
- `grep -r "关键字" --include=*.kt` 定位实现。
- 画图工具（mermaid/PlantUML）把类图、时序图、状态机可视化。
- 对 native 部分，用 `nm`/`objdump` 看 `.so` 符号，或读 WebRTC 源码对应模块。

### 15.4 一句话总结

LiveKit Android SDK 是一个**协程化、响应式、Dagger 注入、RTC 单线程**的 SFU 客户端：`Room` 是门面，`RTCEngine` 是内核，`SignalClient` + `PeerConnectionTransport` 是传输，`org.webrtc` 是 native 底座；通过 `@FlowObservable` 把状态变事件，通过双 PC + subscriber primary 适配 SFU 模型，通过重放缓冲与重连策略保证可靠性，通过 `LiveKitOverrides` 开放扩展。理解它，就是理解"Kotlin 协程 + WebRTC JNI + SFU 信令"三者如何在一个 Android 工程里编排起来。

---

> 全文完。共 15 章（第 0-15 章），覆盖前置知识、架构、DI、连接生命周期、信令、媒体传输、参与者、轨道、音频/视频业务流、数据通道、事件、E2EE、音频子系统、工程总结与分析方法论。


