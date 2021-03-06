module Layer1Tests

using Test
using HDF5

using PicoQuant
include("test_utils.jl")


@testset "Layer 1 tests" begin
    @testset "Test executing dsl commands from file" begin
        qasm_str = """OPENQASM 2.0;
                    include "qelib1.inc";
                    qreg q[3];
                    h q[0];
                    cx q[0],q[1];
                    cx q[1],q[2];"""

        circ = load_qasm_as_circuit(qasm_str)
        tng = convert_qiskit_circ_to_network(circ, DSLBackend("contract_network.tl",
                                                              "tensor_data.h5",
                                                              "",
                                                              true))
        add_input!(tng, "000")
        add_output!(tng, "000")
        plan = random_contraction_plan(tng)

        try
            # Try executing the dsl commands created by contract_network!().
            contract_network!(tng, plan)
            execute_dsl_file(Array{ComplexF64}, "contract_network.tl", "tensor_data.h5")

            # Check if the correct amplitube was computed
            @test begin
                result = h5open("tensor_data.h5", "r") do file
                    read(file, "result")
                end
                result ≈ 1/sqrt(2)
            end

        finally
            # Clean up any files created.
            rm("contract_network.tl", force=true)
            rm("tensor_data.h5", force=true)
        end
    end

    @testset "Test tensor functions" begin

        # Create a tensor A to manipulate.
        A = [1+1im 1im; -1im 2.0]
        tensors = Dict{Symbol, Array{<:Number}}(:A => A)

        # Use the transpose and conjugate functions to get the adjoint of A.
        tensors[:A] = transpose_tensor(tensors[:A], [2,1])
        tensors[:A] = conjugate_tensor(tensors[:A])

        # Test if the correct tensor was created
        @test tensors[:A] == A'

        # Test reshaping the tensor.
        tensors[:A] = reshape_tensor(tensors[:A], 4)
        @test tensors[:A] == [1-1im, -1im, 1im, 2.0]
    end
end
end