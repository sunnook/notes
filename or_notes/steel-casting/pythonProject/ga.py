from deap import base, creator, tools
import numpy as np
# 定义问题
creator.create('FitnessMin', base.Fitness, weights=(-1.0,)) #优化目标：单变量，求最小值
creator.create('Individual', list, fitness = creator.FitnessMin) #创建Individual类，继承 list

# 生成个体
IND_SIZE = 5
toolbox = base.Toolbox()

# 实数编码
toolbox.register('Attr_float', np.random.rand)
toolbox.register('Individual', tools.initRepeat, creator.Individual, toolbox.Attr_float, n=IND_SIZE)

# 生成初始族群
N_POP = 5
toolbox.register('Population', tools.initRepeat, list, toolbox.Individual)
pop = toolbox.Population(n = N_POP) # 产生 N_POP 个个体，每个个体都是由 list 的实数组成

# 定义评价函数
def evaluate(individual):
  return sum(individual), # 注意这个逗号，即使是单变量优化问题，也需要返回tuple

# 评价初始族群
toolbox.register('Evaluate', evaluate)
fitnesses = map(toolbox.Evaluate, pop) # 表示 pop 中每个个体都利用函数 toolbox.Evaluate 进行一次计算

for i in pop:
    print(i) # 打印每个个体的实数编码结果

for fit in pup:
    print(fit) # 打印每个个体的 fitness 值

# 将个体 population 与对应的 fitness 绑定
for ind, fit in zip(pop, fitnesses):
    ind.fitness.values = fit
    print(ind.fitness.values) # 打印每个个体的 fitness 值

# 结果：
# (2.593989197511478,)
# (1.1287944225903104,)
# (2.6030877077096717,)
# (3.304964061515382,)
# (2.534627558467466,)

