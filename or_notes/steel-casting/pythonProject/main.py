# 这是一个示例 Python 脚本。

# 按 Shift+F10 执行或将其替换为您的代码。
# 按 双击 Shift 在所有地方搜索类、文件、工具窗口、操作和设置。

from ortools.sat.python import cp_model

# 初始化模型,并创建变量
model = cp_model.CpModel()
S = model.NewIntVar(1, 9, 'S')
E = model.NewIntVar(0, 9, 'E')
N = model.NewIntVar(0, 9, 'N')
D = model.NewIntVar(0, 9, 'D')
M = model.NewIntVar(1, 9, 'M')
O = model.NewIntVar(0, 9, 'O')
R = model.NewIntVar(0, 9, 'R')
Y = model.NewIntVar(0, 9, 'Y')

# 添加约束
model.Add(1000 * S + 100 * E + 10 * N + D
          + 1000 * M + 100 * O + 10 * R + E
          == 10000 * M + 1000 * O + 100 * N + 10 * E + Y)

model.AddAllDifferent([S, E, N, D, M, O, R, Y])

def solver_fun():
    #求解并打印结果
    solver = cp_model.CpSolver()
    if solver.Solve(model) == cp_model.OPTIMAL:
        print([f'{v}={solver.Value(v)}' for v in [S,E,N,D,M,O,R,Y]])

# 按装订区域中的绿色按钮以运行脚本。
if __name__ == '__main__':
    solver_fun()

# 访问 https://www.jetbrains.com/help/pycharm/ 获取 PyCharm 帮助
