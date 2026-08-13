

使用dlopen动态加载的作用，比弱引用和直接编译引用so区别？



<think>
---


</think>好的，这是一个非常经典的系统编程问题。我们来详细拆解一下 `dlopen` 动态加载、弱引用和直接编译引用（隐式链接）三者的区别。

简单来说，它们的核心区别在于 **链接和加载的时机** 以及 **依赖关系的严格程度**。

---

### 1. 直接编译引用（隐式链接）

这是最常见、最简单的方式。在编译链接时，通过 `-l` 参数直接链接到共享库（如 `-lm` 链接数学库）。

*   **工作原理**：
    1.  **编译时**：编译器记录下程序依赖的库（如 `libmath.so`）。这些信息被写入可执行文件的头部。
    2.  **程序启动时（运行时）**：操作系统的动态链接器（如 `/lib/ld-linux.so`）会检查这些依赖，并在程序 `main` 函数执行**之前**，将所有指定的共享库加载到内存中，并完成所有符号（函数、变量）的解析和重定位。

*   **优点**：
    *   **简单方便**：编写和构建都很直接，无需额外代码。
    *   **性能好**：启动时一次性解决所有依赖，运行时函数调用就是普通的函数调用，开销极小。

*   **缺点**：
    *   **依赖必须存在**：如果任何一个被依赖的库在目标系统上不存在或版本不兼容，程序将**无法启动**，并报错（如 `error while loading shared libraries`）。
    *   **不够灵活**：无法在运行时选择加载哪个库或哪个版本的库。

---

### 2. 弱引用

弱引用是**隐式链接的一种补充机制**，而不是一个替代方案。它主要用于处理**可选的**功能。

*   **工作原理**：
    1.  在编译时，你仍然通过 `-l` 链接一个库，但将对其符号的引用标记为“弱”的。
    2.  程序启动时，动态链接器会尝试解析这些弱符号。
    3.  **如果符号存在**，则正常绑定，功能可用。
    4.  **如果符号不存在**，链接器不会报错，而是将该符号的值设为 `NULL`。程序在运行时必须**主动检查**该符号是否为 `NULL`，然后再决定是否调用它。

*   **优点**：
    *   **实现可选功能**：允许程序在不具备某些高级功能的系统上以基础模式运行。例如，程序可以链接一个高级图形库，但如果该库不存在，则回退到基本的文本模式。

*   **缺点**：
    *   **仍然需要链接库**：构建时仍需指定 `-l`，只是链接要求变弱了。
    *   **加载时机不变**：库的加载仍然发生在程序启动时。
    *   **编码复杂**：需要在每次调用弱引用符号前进行检查，增加了代码量。

**示例（使用 GCC 的弱属性）**：
```c
#include <stdio.h>

// 声明一个弱引用符号，这个函数可能存在于 libadvanced.so 中
extern void advanced_feature() __attribute__((weak));

int main() {
    if (advanced_feature) {
        // 如果系统提供了这个函数，就使用它
        printf("高级功能可用。\n");
        advanced_feature();
    } else {
        // 否则，回退到基础功能
        printf("高级功能不可用，使用基础模式。\n");
    }
    return 0;
}
```
编译：`gcc -o main main.c -ladvanced`

---

### 3. `dlopen` 动态加载（显式链接）

这是最灵活的方式，将链接器的部分工作搬到了你的程序代码中。

*   **工作原理**：
    1.  **编译时**：程序**不直接链接**目标共享库。你只需要链接 `libdl` 库（`-ldl`），它提供了 `dlopen`, `dlsym`, `dlclose` 等函数。
    2.  **运行时**：在程序的**任意时刻**，通过 `dlopen("libfoo.so", RTLD_LAZY)` 来手动加载一个共享库到内存。这个库的路径可以动态生成。
    3.  通过 `dlsym(handle, "function_name")` 手动查找并获取库中函数的地址。
    4.  将返回的地址转换为正确的函数指针，然后通过该指针调用函数。
    5.  使用完毕后，通过 `dlclose` 卸载库。

*   **优点**：
    *   **极致的灵活性**：
        *   **插件系统**：这是实现插件/模块化架构的标准方法。主程序可以动态加载未知的、后期开发的插件。
        *   **运行时决定**：可以根据配置文件、用户输入等条件，决定加载哪个库或哪个版本的库。
        *   **延迟加载**：可以在需要时才加载大型库，减少程序启动时间和初始内存占用。
    *   **依赖非强制**：即使库文件不存在，`dlopen` 也会返回 `NULL` 而不是让程序崩溃，程序可以优雅地处理错误。

*   **缺点**：
    *   **代码复杂**：需要编写额外的代码来管理库的加载、符号查找和错误处理。
    *   **使用繁琐**：调用函数需要通过函数指针，不如直接调用方便。
    *   **性能开销**：每次调用都有一次函数指针间接寻址的开销，并且 `dlopen` 和 `dlsym` 本身也有成本。

**示例**：
```c
#include <stdio.h>
#include <dlfcn.h>

int main() {
    void *handle;
    void (*hello_func)(void);
    char *error;

    // 1. 动态加载库
    handle = dlopen("./libhello.so", RTLD_LAZY);
    if (!handle) {
        fprintf(stderr, "无法加载库: %s\n", dlerror());
        return 1;
    }

    // 2. 查找符号
    hello_func = dlsym(handle, "hello");
    error = dlerror();
    if (error != NULL) {
        fprintf(stderr, "查找符号失败: %s\n", error);
        dlclose(handle);
        return 1;
    }

    // 3. 通过函数指针调用
    hello_func();

    // 4. 关闭库
    dlclose(handle);
    return 0;
}
```
编译：`gcc -o main main.c -ldl` （注意，这里没有 `-lhello`）

---

### 总结对比

| 特性 | 直接编译引用（隐式链接） | 弱引用 | `dlopen`（显式链接） |
| :--- | :--- | :--- | :--- |
| **链接时机** | 编译时 | 编译时（但链接要求弱） | **运行时**（在代码中） |
| **加载时机** | 程序启动时 | 程序启动时 | **程序运行中任意时刻** |
| **依赖关系** | **强依赖**，缺一不可 | **弱依赖**，可选 | **无编译时依赖**，完全动态 |
| **代码复杂度** | 低 | 中（需检查符号） | **高**（需手动管理生命周期） |
| **灵活性** | 低 | 中（实现可选功能） | **极高**（插件、延迟加载） |
| **性能** | **最佳**（直接调用） | 最佳（直接调用，但需检查） | 有开销（函数指针调用） |
| **典型应用** | 程序的核心、稳定依赖 | 可选的、增强型功能 | **插件系统、模块化设计** |

### 如何选择？

*   **使用直接编译引用**：当你的库是程序**核心、稳定、且目标平台肯定存在**的依赖时（如 `libc`, `libpthread`）。这是默认选择。
*   **使用弱引用**：当你需要链接一个库，但希望程序在**该库缺失时仍能正常运行**（只是缺少某些功能）。
*   **使用 `dlopen`**：当你需要实现**插件架构**、**延迟加载**，或者库的路径/名称需要**在运行时才能确定**的情况。这是实现高度模块化和可扩展性的关键手段。








弱引用不是调用时候动态加载的吗？我记得动态库是需要的时候加载的呀 2.增加一行判断，不算增加代码量吧；3.dlopen动态加载是不是还必须适时关闭；4.音视频里面有动态加载案例吗？ffmpeg gstreamer 或者srs什么的


<think>
---

['{"webPages": [{"name": "C 动态库热加载 - zhangyi1357 - 博客园", "summary": "动态库热加载原理 动态库热加载指的是在程序运行时,动态地加载动态库,从而达到不停止程序的情况下,更新程序的功能。 C++ 程序在运行时有两种方式加载动态连接库:隐式链接和显式链接[1]。 隐式链接就是在编译的时候使用 -l 参数链接的动态库,进程在开始执行时就将动态库文件映射到内存空间中。 显式链接使用 libdl.so 库的 API 接口在运行中加载和卸载动态库,主要的 API 有 dlopen、dlclose、dlsym、dlerror 。 隐式链接的方式要进行热加载需要不少 Hack,难度较大,本文主要讲解第二种方式。 简单版本 首先我们快速实现一个能够完成最小功能可运行的版本,熟悉相关 API 的使用。我们简单编写三个文件,分别为 main.cpp , replex.h , hello.cpp ,另外还编写一个快速编译运行代码的脚本 run.sh ,目录结构如下 . hello.cpp main.cpp replex.h run.sh replex.h 中对 dl* API 进行了简单的封装,使用一个 namespace 将API 进行了包装,代码如下 #pragma once#include <dlfcn.h>#include <cstdio>namespace Replex {inline void* Load(const char* filepath) { return dlopen(filepath, RTLD_LAZY);}inline void*", "url": "https://www.cnblogs.com/zhangyi1357/p/17945251"}, {"name": "2011 年 4月 25 日 随笔档案 - 高导 - 博客园", "summary": "摘要: z1.在适当的情况下对对象实现弱引用。 为对象实现弱引用,是有效提高性能的手段之一。弱引用是对象引用的一种“中间态”,实现了对象既可以通过GC回收其内存,又可被应用程序访问的机制。这种看似矛盾的解释,的确对胖对象的内存性能带来提升,因为胖对象需要大量的内存来创建,弱引用机制保证了胖对象在内存不足时GC可以回收,而不影响内存使用,在没有被GC回收前又可以再次引用该对象,从而达到空间与时间的双重节约。 在.NET中,WeakReference类用于表示弱引用,通过其Target属性来表示要追踪的对象,通过其值赋给变量来创建目标对象的强引用实例代码 1 namespace Project3 2 {", "url": "https://www.cnblogs.com/gaodao/archive/2011/04/25.html"}, {"name": "C++智能指针弱引用升级 临时共享所有权-C++-PHP中文网", "summary": "答案:std::weak_ptr通过lock()方法实现弱引用到临时共享所有权的安全升级,解决循环引用、观察者模式和缓存管理中的对象生命周期问题。\\nC++智能指针中的弱引用()扮演着一个相当微妙但至关重要的角色。它本质上是一种非拥有型引用,允许你观察一个对象,却不影响它的生命周期。当我们需要临时地、安全地访问这个被观察对象时,\\n提供了一个名为\\n的方法。这个方法就像一个“升级”机制,它会尝试将弱引用提升为一个共享指针(),从而在那个短暂的时刻,为你提供对目标对象的临时共享所有权。如果对象还活着,你就能拿到一个有效的\\n;如果对象已经香消玉殒,那么\\n会很诚实地返回一个空的\\n。这确保了我们永远不会通过一个悬空指针去访问内存,完美地解决了安全访问已销毁对象的问题。\\n解决方案\\n要实现C++智能指针弱引用到临时共享所有权的升级,核心就是利用\\n的\\n成员函数。这个函数的设计理念非常直接:它尝试获取一个\\n,如果\\n所指向的对象仍然存在,那么\\n会成功创建一个新的\\n,并增加对象的引用计数。这个新创建的\\n会在它自己的生命周期内确保对象的存活,从而赋予了我们对对象的“临时共享所有权”。一旦这个临时的\\n超出作用域,引用计数就会相应减少。\\n实际操作中,我们通常会这样使用它:#include\\n<iostream>\\n#include\\n<memory>\\n#include\\n<vector>\\nclass\\nMyObject\\n{\\npublic:\\nint\\nid;\\nMyObject(int\\ni)\\n:\\nid(i)\\n{\\nstd::cout\\n<<\\n\\"MyObject\\n\\"\\n<<\\nid\\n<<\\n\\"\\ncreated.\\"\\n<<\\nstd::endl;\\n}\\n~MyObject()\\n{\\nstd::cout\\n<<\\n\\"MyObject\\n\\"\\n<<\\nid\\n<<\\n\\"\\ndestroyed.\\"\\n<<\\nstd::endl;\\n}\\nvoid\\ndoSomething", "url": "https://www.php.cn/faq/1490015.html"}, {"name": "一种方便的动态库动态加载机制_库加载机制-CSDN博客", "summary": "动态加载动态库在很多时候的用户体验都比较好,可以检查发现缺失的文件,可以让可选的模块缺失而继续工作。但是动态加载涉及很多函数定义,函数寻址。写来写去非常繁琐且没有技术含量,遇到C++类导出基本没辙。这里我介绍我使用的一种方便使用的动态加载机制。 简单的来说就是将欲导出模块封装成类,定义一个纯虚函数类,模块的实现部分做成纯虚函数类的单例。模块仅导出两个函数,一个是创建模块实例,返回虚基类指针;一个是用虚基类指针释放模块。在这种情况下,动态加载模块仍然要处理两个函数,已经好非常多了。 具体的做法如下: macro.h //从RakNet库抄来的单例定义 #define _STATIC_FACTORY_DECLARATIONS(x) static x* GetInstance(void); \\\\ static void DestroyInstance( x *i); #define _STATIC_FACTORY_DEFINITIONS(x,y) x* x::GetInstance(void) {return new y;} \\\\ void x::DestroyInstance( x *i) {delete ( y* ) i;} 12345INetEngine.h //导出导入的定义 #if !defined(XNETENGINE_STATICLIB) # if defined(XNETENGINE_LIBRARY) # define XNETENGINE_SHARED Q_DECL_EXPORT # else # define XNETENGINE_SHARED Q_DECL_IMPORT # endif #else # define XNETENGINE_SHARED #endif //虚接口定义 class INetEngine { public: _STATIC_FACTOR", "url": "https://blog.csdn.net/jinzeyu_cn/article/details/45797351"}, {"name": "《深度解析 C++中的弱引用(weak reference):打破循环依赖的利器》-腾讯云开发者社区-腾讯云", "summary": "在\\nC++编程的世界里,内存管理一直是一个关键且复杂的话题。而弱引用(weak\\nreference)的出现,为我们处理一些特殊的内存相关问题提供了一种巧妙的方法。今天,我们就来深入了解一下什么是弱引用。一、从引用的基本概念说起我们都知道,在\\nC++中,引用是一种给变量起别名的方式。正常的引用(强引用)建立了对象和它的使用者之间的紧密联系。当我们创建一个对象的引用时,只要这个引用存在,对象就不会被销毁,因为编译器会保证对象的生命周期至少和引用一样长。这在很多情况下是非常有用的,但也可能会带来一些问题。例如,在复杂的对象关系网络中,可能会出现循环引用的情况。想象有两个类\\nA\\n和\\nB,A\\n类中有一个\\nB\\n类对象的指针或引用,同时\\nB\\n类中也有一个\\nA\\n类对象的指针或引用。当其他部分的代码不再使用\\nA\\n和\\nB\\n的实例时,由于它们相互引用,它们的内存无法被正确释放,这就导致了内存泄漏。这种情况在使用智能指针等内存管理机制时也可能会出现,即使智能指针已经很智能地管理内存了,但循环引用会让它们也陷入困境。二、弱引用的登场弱引用就是为了解决上述循环引用问题而引入的一种特殊类型的引用。弱引用不会阻止对象被销毁。也就是说,即使存在一个对象的弱引用,当该对象没有其他强引用指向它时,这个对象仍然可以被释放。弱引用就像是一个“旁观者”,它只是记录了对象的存在,但不会对对象的生命周期产生实质性的影响。当我们需要访问弱引用所指向的对象时,需要先检查这个对象是否还存在。如果对象已经被销毁了,那么弱引用就会告诉我们这个事实,而不会像强引用那样导致程序错误。三、弱引用的实际意义(一)在数据结构中的应用在一些复杂的数据结构中,比如图结构。节点之间可能存在相互指向的关系,如果使用普通的强引用,在删除图中的某些节点时,可能会因为复杂的引用关系而无法正确释放内存。而使用弱引用,可以在保持节点之间关联信息的同时,避免因", "url": "https://cloud.tencent.com/developer/article/2475489"}, {"name": "C弱引用在复杂数据结构中的应用 - 问答 - 亿速云", "summary": "在C++中,弱引用(weak_ptr)是一种智能指针,它可以监视一个对象而不会影响其生命周期 避免循环引用:在复杂数据结构中,对象之间可能存在相互引用的情况。这可能导致循环引用,从而使得对象无法被正确销毁。通过使用弱引用,我们可以打破循环引用,避免内存泄漏。 缓存:在某些情况下,我们可能需要缓存一些对象以提高性能。然而,如果我们使用共享指针(shared_ptr)来管理这些对象,那么即使它们已经不再被需要,它们也可能因为被缓存而无法被销毁。这时,我们可以使用弱引用来管理缓存中的对象,当对象不再被需要时,它们可以被正确销毁。 观察者模式:在实现观察者模式时,观察者需要监视主题的状态。然而,如果观察者持有主题的共享指针,那么主题将无法在没有观察者的情况下被销毁。这时,我们可以使用弱引用来让观察者监视主题,而不影响主题的生命周期。 避免引用失效:在某些情况下,我们可能需要在一段时间后访问一个对象。然而,如果我们持有该对象的共享指针,那么对象将不会被销毁,直到我们释放共享指针。这时,我们可以使用弱引用来管理对象,当对象不再被需要时,它可以被正确销毁。 总之,在复杂数据结构中,弱引用可以帮助我们更好地管理对象的生命周期,避免内存泄漏和其他问题。然而,使用弱引用时需要注意,弱引用不能直接访问其所监视的对象,而需要先将其转换为共享指针(shared_ptr)。此外,弱引用在转换为共享指针时可能会失败,因为其所监视的对象可能已经被销毁。因此,在使用弱引用时,需要谨慎处理这些情况。", "url": "https://www.yisu.com/ask/43807619.html"}, {"name": "C中弱引用的未来发展趋势 - 问答 - 亿速云", "summary": "C++中弱引用是一种特殊的引用类型,它允许我们引用一个对象而不增加该对象的引用计数,这意味着如果没有任何强引用指向该对象,该对象将被垃圾回收器回收。弱引用在C++中的应用场景和未来发展趋势如下: 弱引用在C++中的应用场景 库和框架设计 :弱引用在库和框架设计中非常有用,尤其是在提供默认实现的同时,允许用户通过弱引用来自定义实现,从而避免不必要的继承或重载。 多态性 :弱符号函数(弱引用函数)在多态性方面发挥作用,允许库提供默认实现,同时允许用户通过弱符号函数来自定义行为,增加了代码的灵活性和可扩展性。 C++中弱引用的未来发展趋势 智能指针的整合 :随着智能指针(如 std::shared_ptr 和 std::weak_ptr )的普及,弱引用在内存管理中的作用可能会更加凸显,特别是在解决循环引用问题时。 多线程和并发编程 :在多线程和并发编程中,弱引用可以帮助避免死锁,因为它们不会阻止对象被回收,从而减少了资源竞争的风险。 综上所述,C++中弱引用在库和框架设计、多态性、智能指针整合以及多线程和并发编程中的应用场景,以及其在内存管理和避免死锁方面的潜在优势,预示着其在未来C++编程中的重要性和增长趋势。", "url": "https://www.yisu.com/ask/5512906.html"}, {"name": "如何用智能指针实现延迟加载 weak_ptr配合工厂模式的实现方法-C++-PHP中文网", "summary": "使用weak_ptr实现延迟加载的核心原因是避免“伪引用”导致内存泄漏,同时配合工厂模式实现线程安全的对象管理。具体步骤为:1.\\n用weak_ptr检查实例是否存在,不增加引用计数;2.\\n若不存在则通过工厂方法创建并更新缓存;3.\\n多线程环境下加锁确保初始化安全;4.\\n每次访问时调用lock()验证弱引用有效性;5.\\n不长期持有shared_ptr以保证对象及时释放。该机制平衡了性能与内存占用,适用于高成本低频使用的对象初始化场景。\\n在C++中,延迟加载(Lazy\\nLoading)是一种常见的优化手段,尤其适用于资源消耗较大的对象。结合智能指针中的\\n和工厂模式,可以实现一个线程安全、资源可控的延迟加载机制。\\n核心思路是:用\\n管理对象生命周期,用\\n检查是否存在已有实例,没有时再通过工厂方法创建。这样既避免了重复创建,又不会造成内存泄漏。\\n为什么选择\\nweak_ptr\\n而不是\\nshared_ptr\\n使用\\n的主要原因是它不增加引用计数,也就是说,它不会影响对象的销毁时机。这在实现缓存或延迟加载时非常有用:\\n如果用\\n保存缓存引用,即使对象已经不再使用,只要缓存还在,对象就不会释放。\\n使用\\n可以避免这种“伪引用”,当对象真正被释放时,\\n会自动失效。\\n举个例子:\\nstd::weak_ptr<MyObject>\\ncache;\\nauto\\nptr\\n=\\ncache.lock();\\n//\\n尝试获取\\nshared_ptr\\nif\\n(!ptr)\\n{\\nptr\\n=\\nstd::make_shared<MyObject>();\\ncache\\n=\\nptr;\\n}登录后复制只有在对象不存在时才创建,否则复用已有对象。\\n工厂模式如何与\\nweak_ptr\\n配合\\n将延迟加载逻辑封装到工厂类中是一个常见做法。这样外部调用者不需要关心是否已存在实例,只需要调用工厂接口即可。\\n基本结构如下:class\\nMyObjectFact", "url": "https://www.php.cn/faq/1455349.html"}, {"name": "利用接口实现动态加载类以及 Activator.CreateInstance用法示例-其他-虫虫源码-最好最专业的源码资源下载站", "summary": "资源积分: 1积分 资源简介 接口机制实现动态加载类,其中包含 Activator.CreateInstance基本用法示例,有反射的味道 网站首页 | 服务条款 | 隐私协议 | 网站地图 | 免责声明 虫虫源码版权所有 © 2011-2025 苏ICP备2021027574号 本网站资源收集自网络及网站用户上传,若有侵权请邮件至(bugmaweb@163.com),核实后我们会在24小时内删除,谢谢!", "url": "https://www.bugma.cn/index/dl/336978.html"}, {"name": "C++环形引用检测 弱引用计数机制分析-C++-PHP中文网", "summary": "使用weak_ptr可打破shared_ptr的环形引用,避免内存泄漏。当多个对象相互持有shared_ptr时,引用计数无法归零,导致内存无法释放。通过将反向引用改为weak_ptr,可使该引用不参与引用计数,从而在外部指针释放后,对象能正常析构。weak_ptr通过lock()方法临时获取shared_ptr以安全访问对象,且仅增加强引用计数的临时副本。shared_ptr底层通过控制块维护强引用和弱引用计数,对象在强引用为0时即析构,控制块在弱引用为0时释放。环形引用需开发者主动避免,工具可辅助检测内存泄漏,但不自动识别环形结构。实践中建议在父子关系、观察者模式等场景中使用weak_ptr管理反向引用,以确保资源正确释放。\\n在C++中使用智能指针管理对象生命周期时,环形引用是一个常见但容易被忽视的问题,它会导致内存无法正常释放。特别是在使用\\nstd::shared_ptr时,多个对象相互持有对方的shared_ptr,会形成引用环,使引用计数永远无法归零,从而引发内存泄漏。解决这一问题的关键机制是引入弱引用(weak_ptr)。\\n环形引用问题的产生\\n当两个或多个对象通过\\nstd::shared_ptr相互引用时,每个对象的引用计数至少为1,即使外部不再持有任何指向它们的指针,它们的引用计数也不会降为0,析构函数不会被调用。\\n例如:\\nclass\\nNode;\\nusing\\nNodePtr\\n=\\nstd::shared_ptr<Node>;\\nclass\\nNode\\n{\\npublic:\\nNodePtr\\nparent;\\nNodePtr\\nchild;\\n};\\nauto\\nnode1\\n=\\nstd::make_shared<Node>();\\nauto\\nnode2\\n=\\nstd::make_shared<Node>();\\nnode1->child\\n=\\nnode2;\\nnode2->parent\\n=", "url": "https://m.php.cn/faq/1472530.html"}], "images": [{"url": "https://img.php.cn/upload/article/000/969/633/175677288285388.png"}, {"url": "https://csdnimg.cn/release/blogv2/dist/pc/img/newCodeMoreWhite.png"}, {"url": "https://img.php.cn/upload/article/000/969/633/175518174579023.png"}, {"url": "https://img.php.cn/upload/article/000/969/633/175518174693928.png"}, {"url": "https://img.php.cn/upload/article/000/969/633/175518174629081.png"}, {"url": "https://img.php.cn/upload/article/000/969/633/175609326239041.png?x-oss-process=image/resize,p_40"}]}', '{"webPages": [{"name": "Linux 动态库动态加载实例 - 道客巴巴", "summary": "下载积分: 50 内容提示: #ifndef STR_OUT_H #define STR_OUT_H extern \\"C\\" void str_out(const char* str); #endif #include <stdio.h> #include \\"str_out.h\\" void str_out( const char* str ) { printf( \\"%s\\\\n\\", str ); } #include <stdio.h> #include <dlfcn.h> // dlopen、dlsym、dlerror、dlclose 的头文件 #include <stdlib.h> #include \\"str_out.h\\" // 此例为动态加载动态库,Makefile 中会提到静态如何关联加载 int main() { typedef void (*STROUT)(const char*); void * hDynamicLib = 0; STROUT fpStrOut = 0; // 动态加载动态库... 文档格式:PDF | 页数:3 | 浏览次数:3 | #ifndef STR_OUT_H #define STR_OUT_H extern \\"C\\" void str_out(const char* str); #endif #include <stdio.h> #include \\"str_out.h\\" void str_out( const char* str ) { printf( \\"%s\\\\n\\", str ); } #include <stdio.h> #include <dlfcn.h> // dlopen、dlsym、dlerror、dlclose 的头文件 #include <stdlib.h> #include \\"str_out.h\\" // 此例为动态加载动态库", "url": "https://www.doc88.com/p-2857382668864.html"}, {"name": "Linux 动态库动态加载实例 - 道客巴巴", "summary": "下载积分: 0 内容提示: #ifndef STR_OUT_H #define STR_OUT_H extern \\"C\\" void str_out(const char* str); #endif #include <stdio.h> #include \\"str_out.h\\" void str_out( const char* str ) { printf( \\"%s\\\\n\\", str ); } #include <stdio.h> #include <dlfcn.h> // dlopen、 dlsym、 dlerror、 dlclose 的头文件 #include <stdlib.h> #include \\"str_out.h\\" // 此例为动态加载动态库, Makefile 中会提到静态如何关联加载 int main() { typedef void (*STROUT)(const char*); void * hDynamicLib = 0; STROUT fpStrOut = 0; // 动态加载动... 文档格式:DOC | 页数:3 | 浏览次数:6 | #ifndef STR_OUT_H #define STR_OUT_H extern \\"C\\" void str_out(const char* str); #endif #include <stdio.h> #include \\"str_out.h\\" void str_out( const char* str ) { printf( \\"%s\\\\n\\", str ); } #include <stdio.h> #include <dlfcn.h> // dlopen、 dlsym、 dlerror、 dlclose 的头文件 #include <stdlib.h> #include \\"str_out.h\\" // 此例为动态加", "url": "https://www.doc88.com/p-9562604307666.html"}, {"name": "libffmpeg.so动态库 - 开发实例、源码下载 - 好例子网", "summary": "【实例简介】 第一次搞这东西,试了几天终于编译出libffmpeg.so动态库,兴奋中...... 【实例截图】 【核心代码】 标签: 实例下载地址 libffmpeg.so动态库 点此下载实例 不能下载?内容有错? 点击这里报错 +投诉+提问好例子网口号: 伸出你的我的手 — 分享 ! 相关软件 小贴士 感谢您为本站写下的评论,您的评论对其它用户来说具有重要的参考价值,所以请认真填写。 类似“顶”、“沙发”之类没有营养的文字,对勤劳贡献的楼主来说是令人沮丧的反馈信息。 相信您也不想看到一排文字/表情墙,所以请不要反馈意义不大的重复字符,也请尽量不要纯表情的回复。 提问之前请再仔细看一遍楼主的说明,或许是您遗漏了。 请勿到处挖坑绊人、招贴广告。既占空间让人厌烦,又没人会搭理,于人于己都无利。 关于好例子网 本站旨在为广大IT学习爱好者提供一个非营利性互相学习交流分享平台。本站所有资源都可以被免费获取学习研究。本站资源来自网友分享,对搜索内容的合法性不具有预见性、识别性、控制性,仅供学习研究,请务必在下载后24小时内给予删除,不得用于其他任何用途,否则后果自负。基于互联网的特殊性,平台无法对用户传输的作品、信息、内容的权属或合法性、安全性、合规性、真实性、科学性、完整权、有效性等进行实质审查;无论平台是否已进行审查,用户均应自行承担因其传输的作品、信息、内容而可能或已经产生的侵权或权属纠纷等法律责任。本站所有资源不代表本站的观点或立场,基于网友分享,根据中国法律《信息网络传播权保护条例》第二十二与二十三条之规定,若资源存在侵权或相关问题请联系本站客服人员,点此联系我们。关于更多版权及免责申明参见 版权及免责申明", "url": "https://www.haolizi.net/example/view_218608.html"}, {"name": "Linux动态库动态加载实例.pdf_淘豆网", "summary": "文档列表 文档介绍 该【Linux动态库动态加载实例 】是由【小辰GG】上传分享,文档一共【3】页,该文档可以免费在线阅读,需要了解更多关于【Linux动态库动态加载实例 】的内容,可以使用淘豆网的站内搜索功能,选择自己适合的文档,以下文字是截取该文章内的部分文字,如需要获得完整电子版,请下载此文档到您的设备,方便您编辑和打印。#ifndefSTR_OUT_H #defineSTR_OUT_H extern\\"C\\"voidstr_out(constchar*str); #endif #include<> #include\\"\\" voidstr_out(constchar*str) { printf(\\"%s\\\\n\\",str); } #include<> #include<>//dlopen、dlsym、dlerror、dlclose的头文件 #include<> #include\\"\\" //此例为动态加载动态库,Makefile中会提到静态如何关联加载 intmain() { typedefvoid(*STROUT)(constchar*); void*hDynamicLib=0; STROUTfpStrOut=0; //动态加载动态库名字可以不用前缀lib,静态则一定要加 hDynamicLib=dlopen(\\"/home/nsc/document/testpro/staticlib/\\",RTLD_LAZY); if(0!=hDynamicLib) { fpStrOut=(STROUT)dlsym(hDynamicLib,\\"str_out\\"); char*szErrInfo=dlerror(); if(0==szErrInfo) { fpStrOut(\\"You\'resuccessagain!\\\\n\\"); } else { printf(\\"%s\\\\n\\",szErrInfo); } dlc", "url": "https://www.taodocs.com/p-849365494.html"}, {"name": "ffmpeg示例demo - 开发实例、源码下载 - 好例子网", "summary": "\ue50a发布时间: \ue50b\ue50a2021-01-11 \ue50busing System;using System.Collections.Generic;using System.ComponentModel;using System.Data;using System.Drawing;using System.Linq;using System.Text;using System.Threading;using System.Threading.Tasks;using System.Windows.Forms;using System.IO;namespace FFmpegDemo{ public partial class frmPlayer : Form { public frmPlayer() { InitializeComponent(); } tstRtmp rtmp = new tstRtmp(); Thread thPlayer; public String exePath = Application.StartupPath; private void btnStart_Click(object sender, EventArgs e) { btnStart.Enabled = false; if (thPlayer != null) { rtmp.Stop(); thPlayer = null; } else { thPlayer = new Thread(DeCoding); thPlayer.IsBackground = true; thPlayer.Start(); btnStart.Text = \\"停止播放\\"; btnStart.Enabled = true;summary> /// 播放线程执行方法 /// </summary> private unsafe voi", "url": "http://www.haolizi.net/example/view_154404.html"}, {"name": "gstreamer-examples:杂项演示使用gstreamer的示例_gstreamer例子资源-CSDN文库", "summary": "Qt5 Gstreamer 示例一般说明从源安装 Qt Gstreamer: 添加-DQT_VERSION=5编译标志,如下所示: : -DQT_VERSION=5 按照这里的文档: : 链接到像这里的库: : 如果需要,请使用cmake模块复制本地文件夹: ://cgit.freedesktop.org/gstreamer/qt-gstreamer/tree/cmake/mod 基于gstreamer的支持动态获取多路流的rtsp server示例 浏览:179 最近在做rtsp server相关的事情,调研了一些开源的服务器,大部分都是作为独立的进程启动,有点不符合自己的场景。偶然发现gstreamer,名气很大,但是用的人却很少。粗略百度了下相关资料--很少。大部分示例都是提供一路流,或者事先写死几路,没法根据自己播放访问时的url判断流存不存在并动态创建。后面花了点时间稍微了解了下,整理出一份动态创建流的代码,分享出来 移植Gstreamer 和gst-rtsp-server到Android实例 浏览:52 4星·用户满意度95% 移植Gstreamer 和gst-rtsp-server到Android的源代码小实例 Gstreamer in windows and demo 浏览:161 5星·资源好评率100% Gstreamer 在windows下开发坏境搭建、windows下创建demo列子(PlayerTest.zip)一个在windows下创建的一个MP3播放器和影音播放器只要配置好GStreamer 在windows 的坏境,就OK了 cpp-一系列GStreamer元素以在GStreamer框架中启用基于CNN模型的视频分析功能如对象检测分类识别 浏览:191 This repository contains a collection of GStr", "url": "https://download.csdn.net/download/weixin_42139302/18496955"}, {"name": "用gstreamer写一个图像采集并用h264压缩后每帧加时间戳分段保存成mkv文件 - 我爱学习网", "summary": "以下是一个使用gstreamer编写的图像采集并使用H264压缩的代码示例。该示例保存每帧图像,其中每帧图像都有时间戳,并分段保存为.mkv文件。 #include <gst/gst.h>int main(int argc, char *argv[]) { GstElement *pipeline, *source, *caps_filter, *h264_encoder, *muxer, *sink; GstCaps *caps; GstBus *bus; GstMessage *msg; guint bus_watch_id; GMainLoop *loop; gchar *filename_template = \\"video_%04d.mkv\\"; /* Initialize GStreamer */ gst_init(&argc, &argv); loop = g_main_loop_new(NULL, FALSE); /* Create pipeline */ pipeline = gst_pipeline_new(\\"video-pipeline\\"); /* Create source element */ source = gst_element_factory_make(\\"v4l2src\\", \\"video-source\\"); g_object_set(G_OBJECT(source), \\"device\\", \\"/dev/video0\\", NULL); /* Create caps filter element */ caps_filter = gst_element_factory_make(\\"capsfilter\\", NULL); caps = gst_caps_new_simple(\\"video/x-raw\\", \\"width\\", G_TYPE_INT, 640", "url": "https://www.5axxw.com/questions/simple/48iogp"}, {"name": "gstreamer教程系列之动态插件的实现与原理 - fei_ing的专栏", "summary": "展开  gstremer的插件机制是其核心,所有的元件的都是以插件的形式绑定在管道中用来实现媒体播放的效果。动态加 载机制简单的说就是gstreamer框架依照所请求的流的格式来向自己的插件库中寻找可用插件已实现自动绑定的一种模式。这大大方便了对于上层应用开发人员的使用。     decodebin2就是动态加载机制实现的一个解码管道,根据手册上说的可以知道,动态加载核心便是在管道中加载了一个typFIXME :  we can only deal with one type ,  we don \' t yet support dynamically changing     *  caps from the typefind  element   * /    if   ( decode_bin - > have_type  | |  decode_bin - > decode_chain_bin_signals [ SIGNAL_AUTOPLUG_FACTORIES ] ,  0 ,  dpad ,  caps ,        & factories ) ; 发送后,进入这个信号的执行函数中,发现调用了gst_element_factory_list_filter,通过执行这个函数后,得到满足caps的可能元件的工厂列表,然后从中选择出最合适的元件。    那从什么类行的工厂中选择的呢?这就是实现动态加载机制的关键所在了,我们接下去往下看 点击( 此处 )折叠或打开e类型以实现动态加载,所以,对于我们要做的demux类插件,只需要在生成了插件模板后,对于插件的等级,和class属性进行以上分析的设定便可。 发布了1 篇原创文章 · 获赞 2 · 访问量 2万+ gstreamer plugins的工作同所有的基于插件的程序的工作原理类似,本质上都是通过读取动态库实现的", "url": "https://blog.csdn.net/fei_ing/article/details/47253827?locationNum=9&fps=1"}, {"name": "ffmpegwindowssdk和动态库_ffmpeg接口开发资源-CSDN文库", "summary": "收起资源包目录 ffmpeg windows sdk 和 动态库 (210个子文件) transcode_aac.c 34KB transcoding.c 22KB muxing.c 21KB demuxing_decoding.c 14KB filter_audio.c 12KB filtering_audio.c 10KB vaapi_transcode.c 10KB filtering_video.c 9KB qsvdec.c 8KB resampling_audio.c 8KB hw_decode.c 8KB vaapi_encode.c 7KB encode_audio.c 6KB remuxing.c 6KB extract_mvs.c 6KB avio_dir_cmd.c 5KB encode_video.c 5KB decode_audio.c 5KB decode_video.c 5KB http_multiclient.c 5KB scaling_video.c 5KB avio_reading.c 4KB metadata.c 2KB bootstrap.min.css 107KB style.min.css 6KB default.css 2KB avutil-56.def 12KB avcodec-58.def 6KB avformat-58.def 4KB avfilter-7.def 2KB swscale-5.def 756B avdevice-58.def 544B swresample-3.def 473B postproc-55.def 223B avcodec-58.dll 42.42MB avformat-58.dll 9.9MB avfilter-7.dll 7.46MB avdevice-58.dll 2.6MB avutil-", "url": "https://download.csdn.net/download/ykun089/12948635"}, {"name": "提供一个用gstreamer采集图像并编码成h264码流后用appsink插件添加时间戳并分段保存成mkv文件的c语言例子 - 我爱学习网", "summary": "#include <stdio.h>#include <stdlib.h>#include <gst/gst.h>static gboolean bus_call(GstBus *bus, GstMessage *msg, gpointer data) { GMainLoop *loop = (GMainLoop *) data; switch (GST_MESSAGE_TYPE(msg)) { case GST_MESSAGE_EOS: g_print(\\"End of stream\\\\n\\"); g_main_loop_quit(loop); break; case GST_MESSAGE_ERROR: { gchar *debug; GError *error; gst_message_parse_error(msg, &error, &debug); g_free(debug); g_printerr(\\"ERROR: %s\\\\n\\", error->message); g_error_free(error); g_main_loop_quit(loop); break; } default: break; } return TRUE;}static GstFlowReturn add_timestamp(GstElement *sink, gpointer user_data) { static gint64 first_sample_time = -1; gint64 cur_sample_time = -1; GstSample *sample = gst_app_sink_pull_sample(GST_APP_SINK(sink)); if (!sample) return GST_FLOW_ERROR; GstBuffer *buffer = gst_sample_", "url": "https://www.5axxw.com/questions/simple/s9fydm"}], "images": [{"url": "https://img01.haolizi.net/2021/01/11/ff/9/f/ff9f455e68fc5403762612b1d160ce02.png"}, {"url": "https://csdnimg.cn/release/downloadcmsfe/public/img/scale.ab9e0183.png"}, {"url": "https://csdnimg.cn/release/downloadcmsfe/public/img/scale.ab9e0183.png"}]}']
</think>非常好的追问！这说明你对细节很关注，我们来逐一澄清这些重要的点。

---

### 1. 弱引用的加载时机 & 动态库的加载方式

这是一个常见的误解。我们来精确区分一下：

**动态库的“动态”体现在两个方面：**

1.  **链接的动态性（与静态库.a相对）**：动态库的代码在程序运行时才被加载到内存，而不是在编译时就被打包进可执行文件。这是所有共享库（.so）的基本特性。
2.  **加载时机的动态性（这才是核心区别）**：
    *   **隐式链接（包括弱引用）**：库的加载发生在程序启动时，由系统加载器自动完成。虽然库的代码是“按需”映射到物理内存的（操作系统的页机制），但库文件必须在程序启动时就被找到并准备好。**所以，弱引用并没有改变库的加载时机，它只是改变了符号解析的严格程度。**
    *   **显式链接（`dlopen`）**：库的加载发生在你的代码明确调用 `dlopen` 的那一刻。这才是真正的“需要的时候再加载”。

**举个例子来比喻：**

*   **隐式链接**：就像你出门旅行前，把所有可能用到的行李（外套、雨伞、充电宝）都塞进了行李箱。一出门（程序启动），行李就已经在身边了。弱引用像是把非必需品（比如一本可选的书）也塞进去，并贴个纸条：“如果太重可以扔掉”，但打包这个动作还是在出门前完成的。
*   **显式链接（`dlopen`）**：就像你只带了一个空行李箱出门，路上需要什么（比如到了下雨的地方需要买伞），再临时去商店（调用 `dlopen`）买来放进箱子。

所以，**弱引用不是调用时动态加载，它依然是启动时加载**。

---

### 2. 增加一行判断，不算增加代码量吧？

你说得对，从“行数”上看，增加一个 `if` 判断确实不多。但我所说的“代码复杂度”或“代码量”增加，更多是指**工程和维护层面**的：

*   **分散的检查**：你不是只在一个地方检查一次。每个使用到这个弱引用符号的地方，都需要进行 `if (func_ptr)` 检查。如果这个功能有10个入口，你就要写10次检查。
*   **错误处理逻辑**：健壮的代码不仅仅是检查是否为 `NULL`，还需要为“功能不可用”的情况提供回退（fallback）逻辑。这个回退逻辑本身也是增加的代码。
*   **可读性**：代码中穿插了大量的条件判断，会稍微影响主线逻辑的清晰度。

相比之下，隐式链接的函数调用是“理所当然”能成功的，代码非常干净。所以，虽然单次判断简单，但积少成多，并引入了额外的逻辑分支。

---

### 3. `dlopen` 动态加载是不是还必须适时关闭？

**是的，绝对需要！** 这是一个非常重要的好习惯。

*   **为什么必须关闭？**
    1.  **资源泄漏**：每个 `dlopen` 都会占用一个文件描述符和一些内存来管理库的映射信息。如果不 `dlclose`，这些资源会一直泄漏，直到进程结束。
    2.  **符号冲突**：如果你反复 `dlopen` / `dlclose` 同一个库的不同版本，不及时关闭旧版本可能会导致符号名冲突，出现不可预知的行为。
    3.  **文件锁**：在某些系统上，打开的动态库文件可能会被锁定，导致你无法在程序运行时删除或更新这个库文件。

*   **最佳实践**：
    *   将 `dlopen` 返回的句柄视为一种资源，像文件描述符一样管理。
    *   使用 RAII（Resource Acquisition Is Initialization）模式（在C++中）或 `atexit` 等机制，确保在作用域结束或程序退出时，句柄能被正确关闭。

**注意**：`dlclose` 并不是立即从内存中卸载库。它只是减少该库的引用计数。当引用计数减到0时，系统才会真正卸载它。对于隐式链接的库，引用计数初始就不为0，所以即使你显式 `dlclose` 它，也不会被卸载。

---

### 4. 音视频里面的动态加载案例吗？ffmpeg/gstreamer/srs？

**当然有！这两个都是重度使用 `dlopen` 式动态加载的经典案例，尤其是为了实现插件化架构。**

#### **GStreamer**

GStreamer 是整个框架都构建在插件（Plugin）之上的，是动态加载的终极范例。

*   **工作原理**：
    1.  核心的 `gstreamer` 库非常小，只包含管道（Pipeline）、元件（Element）等基础管理功能。
    2.  所有具体的功能，如解码器（`libav`）、编码器（`x264enc`）、源（`filesrc`, `v4l2src`）、输出（`autovideosink`）等，都以独立的插件库形式存在（如 `libgstlibav.so`, `libgstcoreelements.so`）。
    3.  当你创建一个管道，例如 `gst-launch-1.0 filesrc location=video.mp4 ! decodebin ! autovideosink`：
        *   `filesrc` 插件被加载，负责读文件。
        *   `decodebin` 是一个特殊的“智能”元件，它会**动态地**检查视频流的格式（H.264? HEVC?），然后根据格式去插件目录中寻找合适的解码器插件（比如 `libgstlibav.so` 中的 H.264 解码器），并用 `dlopen` 加载它。
        *   这就是典型的运行时按需加载，实现了极致的灵活性。

#### **FFmpeg**

FFmpeg 也大量使用动态加载来管理其编解码器、封装格式等。

*   **工作原理**：
    1.  在配置编译 FFmpeg 时，你可以选择将编解码器**静态链接**进主程序，也可以编译成**独立的共享库**（如 `libavcodec.so`, `libavformat.so`），并进一步让主程序在运行时动态加载这些库中的具体组件。
    2.  当您使用 `avformat_open_input` 打开一个媒体文件时，FFmpeg 会探测文件格式，然后从已注册的封装/解封装器（Demuxer）列表中找到匹配的那个。这些解封装器很多就是通过类似动态加载的机制注册进去的。
    3.  虽然 FFmpeg 内部机制的抽象层次很高，不像 GStreamer 那样直接暴露 `dlopen` API，但其“插件化”的思想和动态加载的效益是相同的：避免主程序臃肿，允许用户只安装需要的编解码器，方便扩展。

#### **SRS (Simple RTMP Server)**

SRS 作为流媒体服务器，其模块化程度也很高。虽然其核心可能为了性能采用直接链接，但对于一些扩展功能，比如：
*   **HTTP回调认证**
*   **自定义的转码插件**
*   **特定的数据统计模块**
完全可以设计成通过 `dlopen` 动态加载的插件，以实现高度的可定制性，而无需修改和重新编译主服务器程序。

### 总结

*   **弱引用不改变加载时机**，它只是让启动时的依赖检查变宽松。
*   **`dlopen` 是真正的运行时加载**，提供了最大的灵活性，是构建插件化系统的基石。
*   **音视频领域（尤其是 GStreamer）是动态加载技术最典型和应用最成功的场景之一**，它完美解决了多媒体格式和协议众多、需要灵活组合的问题。









