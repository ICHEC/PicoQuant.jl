using LinearAlgebra

@testset "Test loading and conversion of qasm" begin

    qasm_str = """OPENQASM 2.0;
                  include "qelib1.inc";
                  qreg q[3];
                  h q[0];
                  cx q[0],q[1];
                  cx q[1],q[2];"""

    circ = load_qasm_as_circuit(qasm_str)
    InteractiveBackend()
    tng = convert_qiskit_circ_to_network(circ)
    tng_json = to_json(tng)

    @test begin
        circ.n_qubits == 3
    end

    @test begin
        length(circ.data) == 3
    end

    @test begin
        # test conversion to json and back maintains graph
        tng_to_json_from_json = to_json(network_from_json(tng_json))
        tng_to_json_from_json == tng_json
    end
end

@testset "Test tensor network data structure" begin
    tn = TensorNetworkCircuit(3)

    @test begin
        # Check if tn has the correct number of nodes
        length(tn.nodes) == 0
    end

    hadamard = [1 1; 1 -1]./sqrt(2)
    InteractiveBackend()
    add_gate!(tn, hadamard, [1])
    @test begin
        length(tn.nodes) == 1
    end

    @test begin
        length(edges(tn)) == 4
    end
end

@testset "Test tensor decomposition" begin
    InteractiveBackend()
    tn = TensorNetworkCircuit(2)
    gate_data = rand(ComplexF64, 2, 2, 2, 2)

    @test begin
        gate_labels = add_gate!(tn, gate_data, [1, 2], decompose=true)
        result_label = contract_pair!(tn, gate_labels...)
        # should now only be a single node left
        # index order will have changed so permute back before comparing
        # data = reshape(collect(values(backend.tensors))[1], 2, 2, 2, 2)
        data = backend.tensors[result_label]
        data = permutedims(data, (1, 3, 2, 4))
        data ≈ gate_data
    end
end

@testset "Test gate addition with decomposition" begin
    qasm_str = """OPENQASM 2.0;
                  include "qelib1.inc";
                  qreg q[3];
                  h q[0];
                  cx q[0],q[1];
                  cx q[1],q[2];"""

    circ = load_qasm_as_circuit(qasm_str)
    InteractiveBackend()
    tng = convert_qiskit_circ_to_network(circ, decompose=true)

    @test begin
        length(tng.nodes) == 5
    end
end

@testset "Test transpilation" begin
    qasm_str = """OPENQASM 2.0;
                  include "qelib1.inc";
                  qreg q[3];
                  h q[0];
                  cx q[0],q[2];"""

    circ = load_qasm_as_circuit(qasm_str)
    InteractiveBackend()
    tng = convert_qiskit_circ_to_network(circ, transpile=true)

    @test begin
        tng.qubit_ordering == [2, 1, 3]
    end
end


@testset "Test add input/output functions" begin

    tng = TensorNetworkCircuit(3)

    # test that add_input function adds nodes
    add_input!(tng, "000")
    @test length(tng.nodes) == 3

    # test that add_output function adds nodes
    add_output!(tng, "000")
    @test length(tng.nodes) == 6

    # test that add_input function does not add nodes if already present
    add_input!(tng, "000")
    @test length(tng.nodes) == 6

    # test that add_output function does not add nodes if already present
    add_output!(tng, "000")
    @test length(tng.nodes) == 6
end
