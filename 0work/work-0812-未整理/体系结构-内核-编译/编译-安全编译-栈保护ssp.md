


<think>
---

</think>
SSP（Stack Smashing Protector，栈溢出保护）是一种用于防止缓冲区溢出攻击的安全机制。以下是关于SSP的关键点：

1. **核心功能**：
   - 通过在函数栈帧中插入随机生成的"canary值"（类似哨兵值）
   - 在函数返回前验证该值是否被修改
   - 若检测到篡改则立即终止程序

2. 典型实现：
   ```c
   // 编译时添加-fstack-protector选项
   void vulnerable_func() {
       char buf[64];
       gets(buf); // 危险操作
   }
   ```
   实际会被编译器转换为：
   ```c
   void vulnerable_func() {
       uintptr_t canary = __stack_chk_guard;
       char buf[64];
       gets(buf);
       if (canary != __stack_chk_guard) 
           __stack_chk_fail();
   }
   ```

3. **防护范围**：
   - 主要防御基于栈的缓冲区溢出
   - 无法防护堆溢出或格式化字符串等攻击
   - 现代扩展版本（如SSP Strong）提供更全面的保护

4. **技术特点**：
   - GCC/Clang通过`-fstack-protector`系列选项启用
   - Canary值在程序启动时随机生成
   - 在glibc等标准库中默认部分启用

需要区分的是，SSP与ASLR（地址空间随机化）、DEP（数据执行保护）同属内存保护机制，但各自防护维度不同。在安全开发中常需组合使用这些技术。