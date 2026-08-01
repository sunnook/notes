# yeild能形成一个生成者和消费者

import time

def consume():
    r = ''
    while True:
        n = yield r
        if not n:
            return
    print('[consumer] consuming%s...' % n)
    time.sleep(1)
    r = 'well received'

def produce(c):
    next(c)
    n = 0
    while n < 5:
    n = n + 1
    print('[producer] producing%s...' % n)
    r = c.send(n)
    print('[producer] consumer return:%s' % r)
    c.close()

if __name__=='__main__':
    c = consume()
    produce(c)

# https://blog.csdn.net/weixin_39761481/article/details/111423229?ops_request_misc=&request_id=&biz_id=102&utm_term=yeild%20from&utm_medium=distribute.pc_search_result.none-task-blog-2~all~sobaiduweb~default-1-111423229.142^v100^pc_search_result_base1&spm=1018.2226.3001.4187
