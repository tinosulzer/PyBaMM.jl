#
# Create and discretize the SPMe in pybamm, convert it to a format Julia DiffEq likes, and solve
# A lot of this could eventually be converted into functions in PyBaMM.jl
#

using PyCall

pybamm = pyimport("pybamm")
np = pyimport("numpy")

# load model
model = pybamm.lithium_ion.SPMe(name="SPMe")

parameter_values = model.default_parameter_values
parameter_values.update(
    Dict(
        # "Negative particle radius [m]" => pybamm.InputParameter("R_n") * 1e-5,
        # "Positive particle radius [m]" => pybamm.InputParameter("R_p") * 1e-5
        # "Electrolyte diffusivity [m2.s-1]" => 1e-10,
    )
)
parameter_values._dict_items["Positive particle radius [m]"]

var = pybamm.standard_spatial_vars
var_pts = Dict(var.x_n => 20, var.x_s => 20, var.x_p => 20, var.r_n => 20, var.r_p => 20)

sim = pybamm.Simulation(model, parameter_values=parameter_values, var_pts=var_pts)
sim.build()

input_parameter_order = []#"R_n", "R_p"]
rhs_str, u0_str = sim.built_model.generate_julia_diffeq()#input_parameter_order=input_parameter_order)

eval(Meta.parse(rhs_str))
eval(Meta.parse(u0_str))


dy = Array{Float64}(undef, sim.built_model.concatenated_rhs.shape[1])

using BenchmarkTools
# Check that function is not allocating
p = [1,1]
@btime SPMe!(dy,dy,p,0)


# Solve in Julia
using OrdinaryDiffEq

tend = 3600/sim.built_model.timescale.evaluate()
tspan = (0.0, tend)


u0 = Array{Float64}(undef, sim.built_model.concatenated_rhs.shape[1])
SPMe_u0!(u0, p)
u0
prob = ODEProblem(SPMe!, u0, tspan)#, p)

using Sundials
sol = solve(prob, CVODE_BDF(linear_solver=:Band,jac_upper=1,jac_lower=1), reltol=1e-6, abstol=1e-6, saveat=tend / 100);
sol.u

# Benchmarks
@btime solve(prob, KenCarp47(autodiff=false), reltol=1e-6, abstol=1e-6, saveat=tend / 100);
@btime solve(prob, CVODE_BDF(linear_solver=:Band,jac_upper=1,jac_lower=1), reltol=1e-6, abstol=1e-6, saveat=tend / 100);

# using LinearAlgebra
# LinearAlgebra.BLAS.set_num_threads(1)
# @btime solve(prob, KenCarp47(autodiff=false), reltol=1e-6, abstol=1e-6, saveat=tend / 100);
# @btime solve(prob, CVODE_BDF(linear_solver=:Band,jac_upper=1,jac_lower=1), reltol=1e-6, abstol=1e-6, saveat=tend / 100);
# LinearAlgebra.BLAS.set_num_threads(4)
# @btime solve(prob, KenCarp47(autodiff=false), reltol=1e-6, abstol=1e-6, saveat=tend / 100);
# @btime solve(prob, CVODE_BDF(linear_solver=:Band,jac_upper=1,jac_lower=1), reltol=1e-6, abstol=1e-6, saveat=tend / 100);
# LinearAlgebra.BLAS.set_num_threads(8)
# @btime solve(prob, KenCarp47(autodiff=false), reltol=1e-6, abstol=1e-6, saveat=tend / 100);
# @btime solve(prob, CVODE_BDF(linear_solver=:Band,jac_upper=1,jac_lower=1), reltol=1e-6, abstol=1e-6, saveat=tend / 100);

# With Jacobian
# using ModelingToolkit
# de = modelingtoolkitize(prob)
# ModelingToolkit.generate_jacobian(de)[2] # Second is in-place
# using SparsityDetection, SparseArrays
# input = rand(41)
# output = similar(input)
# sparsity_pattern = jacobian_sparsity(SPM!,output,input,0.0,0.0)
# jac_sparsity = Float64.(sparse(sparsity_pattern))

# using Plots
# spy(jac_sparsity,markersize=1,colorbar=false,color=:deep)

# Calculate voltage in Julia
V_str = pybamm.get_julia_function(sim.built_model.variables["Terminal voltage [V]"], funcname="V")#, input_parameter_order=input_parameter_order)
eval(Meta.parse(V_str))

V = Array{Float64}(undef, length(sol.t))
out = [0.0]
@btime V!(out, sol.u[1], p, sol.t[1])
for idx in 1:length(sol.t)
    out = [0.0]
    V!(out, sol.u[idx], p, sol.t[idx])
    V[idx] = out[1]
end

get_variable(sim, sol, "Terminal voltage [V]", input_parameter_order, p)
# Solve in python
inputs = Dict(input_parameter_order .=> p)
sol_pybamm = sim.solve(sol.t * sim.built_model.timescale.evaluate(), inputs=inputs)

sol_pybamm.update(["Terminal voltage [V]"])
V_pybamm = sol_pybamm.data["Terminal voltage [V]"]

# Plots
using Plots

plot(sol.t, V)
scatter!(sol.t, V_pybamm)