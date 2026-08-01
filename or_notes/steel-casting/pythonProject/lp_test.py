
from ortools.init.python import init
from ortools.linear_solver import pywraplp

def a_lp_example():
    # 声明求解器
    solver = pywraplp.Solver.CreateSolver("GLOP")  # GLOP
    if not solver:
        print("Could not create solver GLOP")
        return

    # 创建变量 solver.Number
    x_var = solver.NumVar(0,1,"x")  # x变量的取值范围0-1
    y_var = solver.NumVar(0,2,"y")  # y变量的取值范围为0-2
    print("Number of variables = ", solver.NumVariables())

    # 定义约束条件  solver.Constraint() solver.SetCoefficient()
    # x+y≤2
    infinity = solver.infinity()
    constraint1 = solver.Constraint(-infinity, 2, "ct") # ≤2
    constraint1.SetCoefficient(x_var, 1)  # x+  ≤2
    constraint1.SetCoefficient(y_var, 1)  #  +y ≤2

    # 定义目标函数  solver.Objective()
    # max(3*x + 1*y)
    objective = solver.Objective()
    objective.SetCoefficient(x_var, 3)  # 3*x+
    objective.SetCoefficient(y_var, 1)  #    +1*y
    objective.SetMaximization()         # max (3*x + 1*y)

    print(f"Solving with {solver.SolverVersion}")  # 打印求解器版本
    result_status = solver.Solve()                 # 进行求解，并返回状态
    if result_status != pywraplp.Solver.OPTIMAL:       # 最优解
        print("The problem does not have an optimal solution!")
        if result_status == pywraplp.Solver.FEASIBLE:  # 可行解
            print("A potentially suboptimal solution was found.")
        else:                                          # 无解
            print("The solver could not solve the problem.")
            return
    print("Solution:")
    print("  Objective value = ", objective.Value())
    print("  x = ", x_var.solution_value())
    print("  y = ", y_var.solution_value())

a_lp_example()


