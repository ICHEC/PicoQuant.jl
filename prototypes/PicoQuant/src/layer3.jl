using PyCall
using JSON
using DataStructures
using LinearAlgebra

export TensorNetworkCircuit
export Node, Edge, add_gate!, edges
export new_label!, add_input!, add_output!
export load_qasm_as_circuit_from_file, load_qasm_as_circuit
export convert_qiskit_circ_to_network
export to_dict, to_json, network_from_dict, edge_from_dict, node_from_dict
export network_from_json
export inneighbours, outneighbours, virtualneighbours, neighbours
export inedges, outedges
export decompose_tensor!

# *************************************************************************** #
#           Tensor network circuit data structure and functions
# *************************************************************************** #

"Struct to represent a node in tensor network graph"
struct Node
    # the indices that the node contains
    indices::Array{Symbol, 1}
    # data tensor
    data_label::Symbol
end

"""
    function Node(data_label::Symbol)

Outer constructor to create an instance of Node with the given data label and no
index labels
"""
function Node(data_label::Symbol)
    Node(Array{Symbol, 1}(), data_label)
end

"Struct to represent an edge"
mutable struct Edge
    src::Union{Symbol, Nothing}
    dst::Union{Symbol, Nothing}
    qubit::Union{Int64, Nothing}
    virtual::Bool
    Edge(a::Union{Symbol, Nothing},
         b::Union{Symbol, Nothing},
         qubit::Union{Integer, Nothing},
         virtual::Bool=false) = new(a, b, qubit, virtual)
    Edge() = new(nothing, nothing, nothing, false)
end

"Struct for tensor network graph of a circuit"
struct TensorNetworkCircuit
    number_qubits::Integer

    # Reference to indices connecting to input qubits
    input_qubits::Array{Symbol, 1}

    # Reference to indices connecting to output qubits
    output_qubits::Array{Symbol, 1}

    # Map of nodes by symbol
    nodes::OrderedDict{Symbol, Node}

    # dictionary of edges indexed by index symbol where value is node pair
    edges::OrderedDict{Symbol, Edge}

    # implementation details, not shared outside module
    # counters for assigning unique symbol names to nodes and indices
    counters::Dict{String, Integer}
end

"""
    function TensorNetworkCircuit(qubits::Integer)

Outer constructor to create an instance of TensorNetworkCircuit for an empty
circuit with the given number of qubits.
"""
function TensorNetworkCircuit(qubits::Integer)
    # Create labels for edges of the network connecting input to output qubits
    index_labels = [Symbol("index_", i) for i in 1:qubits]

    # Create dictionary map from index label to node positions
    edges = OrderedDict{Symbol, Edge}()
    for i in 1:qubits
        edges[index_labels[i]] = Edge(nothing, nothing, i, false)
    end

    input_indices = index_labels
    output_indices = copy(index_labels)

    nodes = OrderedDict{Symbol, Node}()

    counters = Dict{String, Integer}()
    counters["index"] = qubits
    counters["node"] = 0

    # Create the tensor network
    TensorNetworkCircuit(qubits, input_indices, output_indices, nodes,
                         edges, counters)
end

"""
    function new_label!(network::TensorNetworkCircuit, label_str)

Function to create a unique symbol by incrememting relevant counter
"""
function new_label!(network::TensorNetworkCircuit, label_str)
    network.counters[label_str] += 1
    Symbol(label_str, "_", network.counters[label_str])
end

"""
    function add_gate!(network::TensorNetworkCircuit,
                       gate_data::Array{<:Number},
                       targetqubits::Array{Integer, 1};
                       decompose::Bool=false)

Add a node to the tensor network for the given gate acting on the given quibits
"""
function add_gate!(network::TensorNetworkCircuit,
                   gate_data::Array{<:Number},
                   target_qubits::Array{<:Integer,1};
                   decompose::Bool=false)

    n = length(target_qubits)
    # create new indices for connecting gate to outputs
    input_indices = [network.output_qubits[i] for i in target_qubits]
    output_indices = [new_label!(network, "index") for _ in 1:n]

    # remap output qubits
    for (i, target_qubit) in enumerate(target_qubits)
        network.output_qubits[target_qubit] = output_indices[i]
    end

    # create a node object for the gate
    # TODO: Having data_label equal the node_label is redundant
    # but thinking these can differ when avoiding duplication of tensor data.
    node_label = new_label!(network, "node")
    data_label = node_label
    new_node = Node(vcat(input_indices, output_indices), data_label)
    network.nodes[node_label] = new_node

    # Save the gate data to the executer
    save_tensor_data(backend, node_label, data_label, gate_data)

    # remap nodes that edges are connected to
    for qubit in 1:length(input_indices)
        input_index = input_indices[qubit]
        output_index = output_indices[qubit]
        network.edges[output_index] = Edge(node_label,
                                           network.edges[input_index].dst,
                                           target_qubits[qubit])

        # if there is an output node, we need to update incoming index
        if network.edges[input_index].dst != nothing
            out_node = network.nodes[network.edges[input_index].dst]
            for i in 1:length(out_node.indices)
                if out_node.indices[i] == input_index
                    out_node.indices[i] = output_index
                end
            end
        end
        network.edges[input_index].dst = node_label
    end

    # If we have a gate acting on 2 qubits and have decomposition enabled
    if n == 2 && decompose
        return decompose_tensor!(network,
                                 node_label,
                                 [input_indices[1], output_indices[1]],
                                 [input_indices[2], output_indices[2]])
    else
        return node_label
    end
end

function edges(network::TensorNetworkCircuit)
    network.edges
end

function add_input!(network::TensorNetworkCircuit, config::String)
    @assert length(config) == network.number_qubits
    for (input_index, config_char) in zip(network.input_qubits, config)
        node_label = new_label!(network, "node")
        data_label = node_label

        node_data = (config_char == '0') ? [1., 0.] : [0., 1.]
        network.nodes[node_label] = Node([input_index], data_label)

        # Save the gate data to the executer
        save_tensor_data(backend, node_label, data_label, node_data)

        network.edges[input_index].src = node_label
    end
end

function add_output!(network::TensorNetworkCircuit, config::String)
    @assert length(config) == network.number_qubits
    for (output_index, config_char) in zip(network.output_qubits, config)
        node_label = new_label!(network, "node")
        data_label = node_label

        node_data = (config_char == '0') ? [1., 0.] : [0., 1.]
        network.nodes[node_label] = Node([output_index], data_label)

        # Save the gate data to the executer
        save_tensor_data(backend, node_label, data_label, node_data)

        network.edges[output_index].dst = node_label
    end
end

function inneighbours(network::TensorNetworkCircuit,
                      node_label::Symbol)
    node = network.nodes[node_label]
    myarray = Array{Symbol, 1}()
    for index in node.indices
        edge = network.edges[index]
        if edge.src != nothing && edge.src != node_label && !edge.virtual
            push!(myarray, edge.src)
        end
    end
    myarray
end

function outneighbours(network::TensorNetworkCircuit,
                       node_label::Symbol)
    node = network.nodes[node_label]
    myarray = Array{Symbol, 1}()
    for index in node.indices
        edge = network.edges[index]
        if edge.dst != nothing && edge.dst != node_label && !edge.virtual
            push!(myarray, edge.dst)
        end
    end
    myarray
end

function virtualneighbours(network::TensorNetworkCircuit,
                           node_label::Symbol)
    node = network.nodes[node_label]
    myarray = Array{Symbol, 1}()
    for index in node.indices
        edge = network.edges[index]
        if edge.dst != nothing && edge.dst != node_label && edge.virtual
            push!(myarray, edge.dst)
        elseif edge.src != nothing && edge.src != node_label && edge.virtual
            push!(myarray, edge.src)
        end
    end
    myarray
end

function neighbours(network::TensorNetworkCircuit,
                    node_label::Symbol)
    vcat(inneighbours(network, node_label),
         outneighbours(network, node_label),
         virtualneighbours(network, node_label))
end

function inedges(network::TensorNetworkCircuit,
                 node_label::Symbol)
    idxs = network.nodes[node_label].indices
    [x for x in idxs if !network.edges[x].virtual && network.edges[x].dst == node_label]
end

function outedges(network::TensorNetworkCircuit,
                  node_label::Symbol)
    idxs = network.nodes[node_label].indices
    [x for x in idxs if !network.edges[x].virtual && network.edges[x].src == node_label]
end

# *************************************************************************** #
#                  Functions to read circuit from qasm
# *************************************************************************** #

"""
    function load_qasm_as_circuit_from_file(qasm_path::String)

Function to load qasm from the given path and return a qiskit circuit
"""
function load_qasm_as_circuit_from_file(qasm_path::String)
    qiskit = pyimport("qiskit")
    if isfile(qasm_path)
        return qiskit.QuantumCircuit.from_qasm_file(qasm_path)
    else
        return false
    end
end

"""
    function load_qasm_as_circuit(qasm_str::String)

Function to load qasm from a given qasm string and return a qiskit circuit
"""
function load_qasm_as_circuit(qasm_str::String)
    qiskit = pyimport("qiskit")
    return qiskit.QuantumCircuit.from_qasm_str(qasm_str)
end

"""
    function convert_qiskit_circ_to_network(circ)

Convert the given a qiskit circuit to a tensor network
"""
function convert_qiskit_circ_to_network(circ; decompose::Bool=false)
    transpiler = pyimport("qiskit.transpiler")
    passes = pyimport("qiskit.transpiler.passes")
    qi = pyimport("qiskit.quantum_info")
    barrier = pyimport("qiskit.extensions.standard.barrier")

    coupling = [[i-1, i] for i = 1:circ.n_qubits]
    coupling_map = transpiler.CouplingMap(
                   PyCall.array2py([PyCall.array2py(x) for x in coupling]))

    pass = passes.BasicSwap(coupling_map=coupling_map)
    # pass = passes.LookaheadSwap(coupling_map=coupling_map)
    # pass = passes.StochasticSwap(coupling_map=coupling_map)
    pass_manager = transpiler.PassManager(pass)
    transpiled_circ = pass_manager.run(circ)

    tng = TensorNetworkCircuit(transpiled_circ.n_qubits)
    for gate in transpiled_circ.data
        # If the gate is a barrier then skip it
        if ! pybuiltin(:isinstance)(gate[1], barrier.Barrier)
            # Need to add 1 to index when converting from python
            target_qubits = [target.index+1 for target in gate[2]]
            dims = [2 for i = 1:2*length(target_qubits)]
            data = reshape(qi.Operator(gate[1]).data, dims...)
            add_gate!(tng, data, target_qubits, decompose=decompose)
        end
    end

    tng
end

# *************************************************************************** #
#                    To/from functions for TN circuits
# *************************************************************************** #

"""
    function to_dict(edge::Edge)

Function to convert an edge instance to a serialisable dictionary
"""
function to_dict(edge::Edge)
    Dict("src" => edge.src, "dst" => edge.dst,
         "virtual" => edge.virtual, "qubit" => edge.qubit)
end

"""
    function edge_from_dict(dict::Dict)

Function to create an edge instance from a dictionary
"""
function edge_from_dict(d::AbstractDict)
    Edge((d["src"] == nothing) ? nothing : Symbol(d["src"]),
         (d["dst"] == nothing) ? nothing : Symbol(d["dst"]),
         d["qubit"],
         d["virtual"])
end

"""
    function to_dict(node::Node)

Function to serialise node instance to json format
"""
function to_dict(node::Node)
    node_dict = Dict{String, Any}("indices" => [String(x) for x in node.indices])
    node_dict["data_label"] = string(node.data_label)
    node_dict
end

"""
    function node_from_dict(d::Dict)

Function to create a node instance from a json string
"""
function node_from_dict(d::AbstractDict)
    indices = [Symbol(x) for x in d["indices"]]
    data_label = Symbol(d["data_label"])
    Node(indices, data_label)
end

"""
    function to_dict(network::TensorNetworkCircuit)

Convert a tensor network to a nested dictionary
"""
function to_dict(network::TensorNetworkCircuit)
    top_level = OrderedDict{String, Any}()
    top_level["number_qubits"] = network.number_qubits
    top_level["edges"] = OrderedDict(String(k) => to_dict(v)
                                for (k,v) in pairs(network.edges))

    top_level["nodes"] = OrderedDict{String, Any}()
    nodes_dict = top_level["nodes"]
    for (node_label, node) in pairs(network.nodes)
        nodes_dict[String(node_label)] = to_dict(node)
    end
    top_level["input_qubits"] = [String(x) for x in network.input_qubits]
    top_level["output_qubits"] = [String(x) for x in network.output_qubits]
    top_level
end

"""
    function network_from_dict(dict::Dict{String, Any})

Convert a dictionary to a tensor network
"""
function network_from_dict(dict::AbstractDict{String, Any})
    number_qubits = dict["number_qubits"]
    # initialise counters
    counters = Dict("index" => 0, "node" => 0)

    # Get the index map and convert it to the right type
    edges = OrderedDict{Symbol, Edge}()
    for (k,v) in pairs(dict["edges"])
        edge_num = parse(Int64, split(k, "_")[end])
        counters["index"] = max(counters["index"], edge_num)
        edges[Symbol(k)] = edge_from_dict(v)
    end

    nodes = OrderedDict{Symbol, Node}()
    for (k, v) in dict["nodes"]
        node_num = parse(Int64, split(k, "_")[end])
        counters["node"] = max(counters["node"], node_num)
        nodes[Symbol(k)] = node_from_dict(v)
    end

    input_qubits = [Symbol(x) for x in dict["input_qubits"]]
    output_qubits = [Symbol(x) for x in dict["output_qubits"]]

    TensorNetworkCircuit(number_qubits, input_qubits, output_qubits, nodes,
                         edges, counters)
end



"""
    function to_json(tng::TensorNetworkCircuit)

Convert a tensor network to a json string
"""
function to_json(tng::TensorNetworkCircuit, indent::Integer=0)
    dict = to_dict(tng)
    if indent == 0
        return JSON.json(dict)
    else
        return JSON.json(dict, indent)
    end
end

"""
    function network_from_json(json_str::String)

Convert a json string to a tensor network
"""
function network_from_json(json_str::String)
    dict = JSON.parse(json_str, dicttype=OrderedDict)
    network_from_dict(dict)
end

"""
    function decompose_tensor!(tng::TensorNetworkCircuit,
                               node::Symbol
                               left_indices::Array{Symbol, 1},
                               right_indices::Array{Symbol, 1};
                               threshold::AbstractFloat=1e-15,
                               left_label::Union{Nothing, Symbol}=nothing,
                               right_label::Union{Nothing, Symbol}=nothing)

Decompose a tensor into two smaller tensors
"""
function decompose_tensor!(tng::TensorNetworkCircuit,
                           node_label::Symbol,
                           left_indices::Array{Symbol, 1},
                           right_indices::Array{Symbol, 1};
                           threshold::AbstractFloat=1e-15,
                           left_label::Union{Nothing, Symbol}=nothing,
                           right_label::Union{Nothing, Symbol}=nothing)
    node = tng.nodes[node_label]
    node_data = backend.tensors[node_label]

    index_map = Dict([v => k for (k, v) in enumerate(node.indices)])
    left_positions = [index_map[x] for x in left_indices]
    right_positions = [index_map[x] for x in right_indices]
    dims = size(node_data)
    left_dims = [dims[x] for x in left_positions]
    right_dims = [dims[x] for x in right_positions]

    A = permutedims(node_data, vcat(left_positions, right_positions))
    A = reshape(A, Tuple([prod(left_dims), prod(right_dims)]))

    # Use SVD here but QR could also be used
    F = svd(A)

    # find number of singular values above the threshold
    chi = sum(F.S .> threshold)
    s = sqrt.(F.S[1:chi])

    # assume that singular values and basis of U and V matrices are sorted
    # in descending order of singular value
    B = reshape(F.U[:, 1:chi] * Diagonal(s), Tuple(vcat(left_dims, [chi,])))
    C = reshape(Diagonal(s) * F.Vt[1:chi, :], Tuple(vcat([chi,], right_dims)))

    # plumb these nodes back into the graph and delete the original
    B_label = (left_label == nothing) ? new_label!(tng, "node") : left_label
    C_label = (right_label == nothing) ? new_label!(tng, "node") : right_label
    index_label = new_label!(tng, "index")
    B_node = Node(vcat(left_indices, [index_label,]), B_label)
    C_node = Node(vcat([index_label,], right_indices), C_label)

    # add the nodes
    tng.nodes[B_label] = B_node
    tng.nodes[C_label] = C_node

    backend.tensors[B_label] = B
    backend.tensors[C_label] = C

    # remap edge endpoints
    for index in left_indices
        if tng.edges[index].src == node_label
            tng.edges[index].src = B_label
        elseif tng.edges[index].dst == node_label
            tng.edges[index].dst = B_label
        end
    end
    for index in right_indices
        if tng.edges[index].src == node_label
            tng.edges[index].src = C_label
        elseif tng.edges[index].dst == node_label
            tng.edges[index].dst = C_label
        end
    end

    # add new edge
    tng.edges[index_label] = Edge(B_label, C_label, nothing, true)

    delete!(tng.nodes, node_label)

    (B_label, C_label)
end
