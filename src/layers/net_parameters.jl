using JuMP
using AutoHashEquals

JuMPReal = Union{Real, JuMP.AbstractJuMPScalar}

abstract type LayerParameters end

@auto_hash_equals struct Conv2DParameters{T<:JuMPReal, U<:JuMPReal} <: LayerParameters
    filter::Array{T, 4}
    bias::Array{U, 1}

    function Conv2DParameters{T, U}(filter::Array{T, 4}, bias::Array{U, 1}) where {T<:JuMPReal, U<:JuMPReal}
        (filter_height, filter_width, filter_in_channels, filter_out_channels) = size(filter)
        bias_out_channels = length(bias)
        @assert(
            filter_out_channels == bias_out_channels,
            "For the convolution layer, number of output channels in filter, $filter_out_channels, does not match number of output channels in bias, $bias_out_channels."
        )
        return new(filter, bias)
    end

end

function Conv2DParameters(filter::Array{T, 4}, bias::Array{U, 1}) where {T<:JuMPReal, U<:JuMPReal}
    Conv2DParameters{T, U}(filter, bias)
end

function Conv2DParameters(filter::Array{T, 4}) where {T<:JuMPReal}
    bias_out_channels::Int = size(filter)[4]
    bias = zeros(bias_out_channels)
    Conv2DParameters(filter, bias)
end

function Base.string(p::Conv2DParameters)
    (filter_height, filter_width, filter_in_channels, filter_out_channels) = size(p.filter)
    "applies $filter_out_channels $(filter_height)x$(filter_width) filters"
end

struct PoolParameters{N} <: LayerParameters
    strides::NTuple{N, Int}
    pooling_function::Function
end

function Base.string(p::PoolParameters)
    (_, stride_height, stride_width, _) = p.strides
    function_display_name = Dict(
        MIPVerify.maximum => "max",
        Base.mean => "average",
    )
    string(
        "$(function_display_name[p.pooling_function]) pooling with a $(stride_height)x$(stride_width) filter and a stride of ($stride_height, $stride_width)"
    )
end

Base.hash(a::PoolParameters, h::UInt) = hash(a.strides, hash(string(a.pooling_function), hash(:PoolParameters, h)))

function MaxPoolParameters(strides::NTuple{N, Int}) where {N}
    PoolParameters(strides, MIPVerify.maximum)
end

function AveragePoolParameters(strides::NTuple{N, Int}) where {N}
    # TODO: pooling over variables not supported just yet
    PoolParameters(strides, Base.mean)
end

@auto_hash_equals struct ConvolutionLayerParameters{T<:Real, U<:Real} <: LayerParameters
    conv2dparams::Conv2DParameters{T, U}
    maxpoolparams::PoolParameters{4}

    function ConvolutionLayerParameters{T, U}(conv2dparams::Conv2DParameters{T, U}, maxpoolparams::PoolParameters{4}) where {T<:Real, U<:Real}
        @assert maxpoolparams.pooling_function == MIPVerify.maximum
        return new(conv2dparams, maxpoolparams)
    end

end

function Base.string(p::ConvolutionLayerParameters)
    string(
        "convolution layer. $(p.conv2dparams |> Base.string), followed by $(p.maxpoolparams |> Base.string), and a ReLU activation function.",
    )
end

function ConvolutionLayerParameters{T<:Real, U<:Real}(filter::Array{T, 4}, bias::Array{U, 1}, strides::NTuple{4, Int})
    ConvolutionLayerParameters{T, U}(Conv2DParameters(filter, bias), MaxPoolParameters(strides))
end

@auto_hash_equals struct MatrixMultiplicationParameters{T<:Real, U<:Real} <: LayerParameters
    matrix::Array{T, 2}
    bias::Array{U, 1}

    function MatrixMultiplicationParameters{T, U}(matrix::Array{T, 2}, bias::Array{U, 1}) where {T<:Real, U<:Real}
        (matrix_width, matrix_height) = size(matrix)
        bias_height = length(bias)
        @assert(
            matrix_height == bias_height,
            "Number of output channels in matrix, $matrix_height, does not match number of output channels in bias, $bias_height."
        )
        return new(matrix, bias)
    end

end

function MatrixMultiplicationParameters(matrix::Array{T, 2}, bias::Array{U, 1}) where {T<:Real, U<:Real}
    MatrixMultiplicationParameters{T, U}(matrix, bias)
end

input_size(p::MatrixMultiplicationParameters) = size(p.matrix)[1]
output_size(p::MatrixMultiplicationParameters) = size(p.matrix)[2]

@auto_hash_equals struct SoftmaxParameters{T<:Real, U<:Real} <: LayerParameters
    mmparams::MatrixMultiplicationParameters{T, U}
end

function SoftmaxParameters(matrix::Array{T, 2}, bias::Array{U, 1}) where {T<:Real, U<:Real}
    SoftmaxParameters(MatrixMultiplicationParameters(matrix, bias))
end

function Base.string(p::SoftmaxParameters)
    string(
        "softmax layer with $(p.mmparams |> input_size) inputs and $(p.mmparams |> output_size) output units."
    )
end

@auto_hash_equals struct FullyConnectedLayerParameters{T<:Real, U<:Real} <: LayerParameters
    mmparams::MatrixMultiplicationParameters{T, U}
end

function FullyConnectedLayerParameters(matrix::Array{T, 2}, bias::Array{U, 1}) where {T<:Real, U<:Real}
    FullyConnectedLayerParameters(MatrixMultiplicationParameters(matrix, bias))
end

function Base.string(p::FullyConnectedLayerParameters)
    string(
        "fully connected layer with $(p.mmparams |> input_size) inputs and $(p.mmparams |> output_size) output units, and a ReLU activation function."
    )
end

function check_size(input::AbstractArray, expected_size::NTuple{N, Int})::Void where {N}
    input_size = size(input)
    @assert input_size == expected_size "Input size $input_size did not match expected size $expected_size."
end

function check_size(params::ConvolutionLayerParameters, sizes::NTuple{4, Int})::Void
    check_size(params.conv2dparams, sizes)
end

function check_size(params::Conv2DParameters, sizes::NTuple{4, Int})::Void
    check_size(params.filter, sizes)
    check_size(params.bias, (sizes[end], ))
end

function check_size(params::MatrixMultiplicationParameters, sizes::NTuple{2, Int})::Void
    check_size(params.matrix, sizes)
    check_size(params.bias, (sizes[end], ))
end

abstract type NeuralNetParameters end

@auto_hash_equals struct StandardNeuralNetParameters <: NeuralNetParameters
    convlayer_params::Array{ConvolutionLayerParameters, 1}
    fclayer_params::Array{FullyConnectedLayerParameters, 1}
    softmax_params::SoftmaxParameters
    UUID::String
end

function Base.string(p::StandardNeuralNetParameters)
    convolutional_layer_text = (length(p.convlayer_params) == 0) ? "\n    (none)" : join(string.([""; p.convlayer_params]), "\n    ")
    fc_layer_text = (length(p.fclayer_params) == 0) ? "\n    (none)" : join(string.([""; p.fclayer_params]), "\n    ")
    softmax_text = string(
        "\n    ",
        string(p.softmax_params)
    )

    string(
        "convolutional neural net $(p.UUID)",
        "\n  `convlayer_params` [$(length(p.convlayer_params))]:", convolutional_layer_text,
        "\n  `fclayer_params` [$(length(p.fclayer_params))]:", fc_layer_text,
        "\n  `softmax_params`:", softmax_text
    )
end

Base.show(io::IO, p::Union{LayerParameters, NeuralNetParameters}) = print(Base.string(p))