using MIPVerify: ConvolutionLayerParameters, SoftmaxParameters, FullyConnectedLayerParameters
using MIPVerify: StandardNeuralNetParameters
using MIPVerify: PerturbationParameters, AdditivePerturbationParameters, BlurPerturbationParameters
using MIPVerify.IntegrationTestHelpers: batch_test_adversarial_example
using Base.Test

@testset "Conv + Softmax" begin

### Parameters for neural net
batch = 1
in1_height = 8
in1_width = 8
stride1_height = 2
stride1_width = 2
strides1 = (1, stride1_height, stride1_width, 1)
pooled1_height = round(Int, in1_height/stride1_height, RoundUp)
pooled1_width = round(Int, in1_width/stride1_width, RoundUp)
in1_channels = 1
filter1_height = 2
filter1_width = 2
out1_channels = 3

B_height = 3
B_width = pooled1_height*pooled1_width*out1_channels

### Choosing data to be used
srand(5)
x0 = rand(batch, in1_height, in1_width, in1_channels)

conv1params = ConvolutionLayerParameters(
    rand(filter1_height, filter1_width, in1_channels, out1_channels)*2-1,
    rand(out1_channels)*2-1,
    strides1
)

softmaxparams = SoftmaxParameters(
    rand(B_width, B_height)*2-1,
    rand(B_height)*2-1
)
nnparams = StandardNeuralNetParameters(
    [conv1params], 
    [],
    softmaxparams,
    "tests.integration.generated_weights.conv+softmax"
)

expected_objective_values::Dict{Int, Dict{PerturbationParameters, Dict{Real, Dict{Real, Float64}}}} = Dict(
    1 => Dict(
        AdditivePerturbationParameters() => Dict(
            1 => Dict(
                0 => 1.50622,
                0.1 => 1.58907,
                1 => 2.34482
            ),
            Inf => Dict(
                0 => 0.100834,
                0.1 => 0.106183,
                1 => 0.156280
            )
        ),
        BlurPerturbationParameters((5, 5)) => Dict(
            1 => Dict(
                0 => 23.8680,
                0.01 => 24.0720,
                0.1 => NaN
            ),
            Inf => Dict(
                0 => 0.923521,
                0.01 => 0.928150,
                0.1 => NaN
            )

        )
    )
)

batch_test_adversarial_example(nnparams, x0, expected_objective_values)


end