using SteadyStateDiffEq, DiffEqBase, NLsolve, Sundials
using Test

function f(du, u, p, t)
    du[1] = 2 - 2u[1]
    du[2] = u[1] - 4u[2]
end
u0 = zeros(2)
prob = SteadyStateProblem(f, u0)
abstol = 1e-8
sol = solve(prob, SSRootfind())
@test sol.retcode == ReturnCode.Success
p = nothing

du = zeros(2)
f(du, sol.u, nothing, 0)
@test maximum(du) < 1e-11

prob = ODEProblem(f, u0, (0.0, 1.0))
prob = SteadyStateProblem(prob)
sol = solve(prob,
    SSRootfind(nlsolve = (f, u0, abstol) -> (NLsolve.nlsolve(f, u0,
        autodiff = :forward,
        method = :newton,
        iterations = Int(1e6),
        ftol = abstol))))
@test sol.retcode == ReturnCode.Success
@test typeof(sol.original) <: NLsolve.SolverResults

f(du, sol.u, nothing, 0)
@test du == [0, 0]

# Use Sundials
sol = solve(prob, SSRootfind(nlsolve = (f, u0, abstol) -> (res = Sundials.kinsol(f, u0))))
@test sol.retcode == ReturnCode.Success
f(du, sol.u, nothing, 0)
@test du == [0, 0]

using OrdinaryDiffEq
sol = solve(prob, DynamicSS(Rodas5()))
@test sol.retcode == ReturnCode.Success

f(du, sol.u, p, 0)
@test du≈[0, 0] atol=1e-7

sol = solve(prob, DynamicSS(Rodas5(), tspan = 1e-3))
@test sol.retcode != ReturnCode.Success

sol = solve(prob, DynamicSS(CVODE_BDF()), dt = 1.0)
@test sol.retcode == ReturnCode.Success

# scalar save_idxs
scalar_sol = solve(prob, DynamicSS(CVODE_BDF()), dt = 1.0, save_idxs = 1)
@test scalar_sol[1] ≈ sol[1]

f(du, sol.u, p, 0)
@test du≈[0, 0] atol=1e-6

# Float32
u0 = [0.0f0, 0.0f0]

function foop(u, p, t)
    @test eltype(u) == eltype(u0)
    dx = 2 - 2u[1]
    dy = u[1] - 4u[2]
    [dx, dy]
end

function fiip(du, u, p, t)
    @test eltype(u) == eltype(u0)
    du[1] = 2 - 2u[1]
    du[2] = u[1] - 4u[2]
end

tspan = (0.0f0, 1.0f0)
proboop = SteadyStateProblem(foop, u0)
prob = SteadyStateProblem(fiip, u0)

sol = solve(proboop, DynamicSS(Tsit5(), tspan = 1.0f-3))
@test typeof(u0) == typeof(sol.u)
proboop = SteadyStateProblem(ODEProblem(foop, u0, tspan))
sol2 = solve(proboop, DynamicSS(Tsit5(), abstol = 1e-4))
@test typeof(u0) == typeof(sol2.u)

sol = solve(prob, DynamicSS(Tsit5(), tspan = 1.0f-3))
@test typeof(u0) == typeof(sol.u)
prob = SteadyStateProblem(ODEProblem(fiip, u0, tspan))
sol2 = solve(prob, DynamicSS(Tsit5(), abstol = 1e-4))
@test typeof(u0) == typeof(sol2.u)

for mode in instances(NLSolveTerminationMode.T)
    mode == NLSolveTerminationMode.NLSolveDefault && continue

    termination_condition = NLSolveTerminationCondition(mode; abstol = 1e-4, reltol = 1e-4)
    sol = solve(prob,
        DynamicSS(Tsit5(); abstol = 1e-4, reltol = 1e-4, termination_condition),
        save_everystep = mode ∈ DiffEqBase.SAFE_BEST_TERMINATION_MODES)

    @test sol.retcode == ReturnCode.Success
    @test sol.u ≈ sol2.u

    sol = solve(proboop,
        DynamicSS(Tsit5(); abstol = 1e-4, reltol = 1e-4, termination_condition),
        save_everystep = mode ∈ DiffEqBase.SAFE_BEST_TERMINATION_MODES)

    @test sol.retcode == ReturnCode.Success
    @test sol.u ≈ sol2.u
end

# Complex u
u0 = [1.0im]

function fcomplex(du, u, p, t)
    du[1] = (0.1im - 1) * u[1]
end

prob = SteadyStateProblem(ODEProblem(fcomplex, u0, (0.0, 1.0)))
sol = solve(prob, DynamicSS(Tsit5()))
@test sol.retcode == ReturnCode.Success
@test abs(sol.u[end]) < 1e-8

# Callbacks 
using DiffEqCallbacks
u0 = zeros(2)
prob = SteadyStateProblem(f, u0)
saved_values = SavedValues(Float64, Vector{Float64})
cb = SavingCallback((u, t, integrator) -> copy(u), saved_values,
    save_everystep = true, save_start = true)
sol = solve(prob,
    DynamicSS(Rodas5()),
    callback = cb,
    save_everystep = true,
    save_start = true)
@test sol.retcode == ReturnCode.Success
@test isapprox(saved_values.saveval[end], sol.u)

include("autodiff.jl")
