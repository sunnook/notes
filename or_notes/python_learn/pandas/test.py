def simple_generator():
    print('开始执行')
    yield '这是第一个值'
    print('继续执行')
    yield '这是第二个值'
    print('这将是最后一条消息')

gen = simple_generator()  # 返回生成器对象，但不立即执行任何内部代码

print('00')

i=0
try:
    while True:
        print(next(gen))
        print(i)
        i=i+1
except StopIteration:
    print("生成器已执行完毕")