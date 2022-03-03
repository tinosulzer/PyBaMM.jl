#
# Functions to extract and evaluate variables from a simulation solution
#

function get_variable(sim, sol, var_name::String, inputs)
    input_parameter_order = isnothing(inputs) ? nothing : collect(keys(inputs))
    p = isnothing(inputs) ? nothing : collect(values(inputs))

    # Generate the function using PyBaMM
    pybamm = pyimport("pybamm")
    var_str = pybamm.get_julia_function(
        sim.built_model.variables[var_name],
        funcname="var_func",
        input_parameter_order=input_parameter_order
    )
    var_func! = runtime_eval(Meta.parse(var_str))

    # Evaluate and fill in the vector
    # 0D variables only for now
    var = Array{Float64}(undef, length(sol.t))
    out = [0.0]
    for idx in 1:length(sol.t)
        # Updating 'out' in-place
        var_func!(out, sol.u[idx], p, sol.t[idx])
        var[idx] = out[1]
    end
    return var
end

get_variable(sim, sol, var_name::String) = get_variable(sim, sol, var_name, nothing)

function get_l2loss_function(sim, var_name, inputs, data)
    input_parameter_order = isnothing(inputs) ? nothing : collect(keys(inputs))
    p = isnothing(inputs) ? nothing : collect(values(inputs))

    # Generate the function using PyBaMM
    pybamm = pyimport("pybamm")
    var_str = pybamm.get_julia_function(
        sim.built_model.variables[var_name],
        funcname="var_func",
        input_parameter_order=input_parameter_order
    )
    var_func! = runtime_eval(Meta.parse(var_str))

    # Evaluate L2 loss
    out = [0.0]

    function loss(sol)
        p = sol.prob.p
        sumsq = 0.0
        for i in 1:length(sol.t)
            # Updating 'out' in-place
            var_func!(out, sol.u[i], p, sol.t[i])
            sumsq += (data[i] - out[1])^2
        end
        sumsq
    end
end