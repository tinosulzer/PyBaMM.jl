function build_pack(Np, Ns, model, tend=3600.0, functional=true)
    
    netlist = lp.setup_circuit(Np, Ns, I=25.0)
    
    pybamm_pack = pybamm.Pack(model, netlist, functional=functional, thermal=true)
    pybamm_pack.build_pack()

    timescale = pyconvert(Float64,pybamm_pack.timescale.evaluate())
    

    if functional
        cellconverter = pybamm.JuliaConverter(cache_type = "symbolic", inplace=true)
        cellconverter.convert_tree_to_intermediate(pybamm_pack.cell_model)
        cell_str = cellconverter.build_julia_code()
        cell_str = pyconvert(String, cell_str)
        cell! = eval(Meta.parse(cell_str))
    else
        cell_str = ""
    end

    myconverter = pybamm.JuliaConverter(cache_type = "symbolic")
    myconverter.convert_tree_to_intermediate(pybamm_pack.pack)
    pack_str = myconverter.build_julia_code()

    ics_vector = pybamm_pack.ics
    np_vec = ics_vector.evaluate()
    jl_vec = vec(pyconvert(Array{Float64}, np_vec))

    pack_str = pyconvert(String, pack_str)
    jl_func = eval(Meta.parse(pack_str))

    dy = similar(jl_vec)

    jac_sparsity = float(Symbolics.jacobian_sparsity((du,u)->jl_func(du,u,p,t),dy,jl_vec))

    netlist = lp.setup_circuit(Np, Ns, I=25.0)
    
    pybamm_pack = pybamm.Pack(model, netlist, functional=functional, thermal=true)
    pybamm_pack.build_pack()

    timescale = pyconvert(Float64,pybamm_pack.timescale.evaluate())
    

    if functional
        cellconverter = pybamm.JuliaConverter(cache_type = "dual", inplace=true)
        cellconverter.convert_tree_to_intermediate(pybamm_pack.cell_model)
        cell_str = cellconverter.build_julia_code()
        cell_str = pyconvert(String, cell_str)
        cell! = eval(Meta.parse(cell_str))
    else
        cell_str = ""
    end

    myconverter = pybamm.JuliaConverter(cache_type = "dual")
    myconverter.convert_tree_to_intermediate(pybamm_pack.pack)
    pack_str = myconverter.build_julia_code()

    ics_vector = pybamm_pack.ics
    np_vec = ics_vector.evaluate()
    jl_vec = vec(pyconvert(Array{Float64}, np_vec))

    pack_str = pyconvert(String, pack_str)
    jl_func = eval(Meta.parse(pack_str))

    #build mass matrix.
    pack_eqs = falses(pyconvert(Int,pybamm_pack.len_pack_eqs))

    cell_rhs = trues(pyconvert(Int,pybamm_pack.len_cell_rhs))
    cell_algebraic = falses(pyconvert(Int,pybamm_pack.len_cell_algebraic))
    cells = repeat(vcat(cell_rhs,cell_algebraic),pyconvert(Int, pybamm_pack.num_cells))
    differential_vars = vcat(pack_eqs,cells)
    mass_matrix = sparse(diagm(differential_vars))
    func = ODEFunction(jl_func, mass_matrix=mass_matrix,jac_prototype=jac_sparsity)
    prob = ODEProblem(func, jl_vec, (0.0, 1/timescale), nothing)
    return prob
end
