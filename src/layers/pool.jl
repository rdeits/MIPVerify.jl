"""
For pooling operations on an array where a given element in the output array
corresponds to equal-sized blocks in the input array, returns (for a given
dimension) the index range in the input array corresponding to a particular
index `output_index` in the output array.

Returns an empty array if the `output_index` does not correspond to any input
indices.

# Arguments
* `stride::Integer`: the size of the operating blocks along the active
     dimension.

"""
function getsliceindex(input_array_size::Int, stride::Int, output_index::Int)::Array{Int, 1}
    parent_start_index = (output_index-1)*stride+1
    parent_end_index = min((output_index)*stride, input_array_size)
    if parent_start_index > parent_end_index
        return []
    else
        return parent_start_index:parent_end_index
    end
end

"""
For pooling operations on an array, returns a view of the parent array
corresponding to the `output_index` in the output array.
"""
function getpoolview(input_array::AbstractArray{T, N}, strides::NTuple{N, Int}, output_index::NTuple{N, Int})::SubArray{T, N} where {T, N}
    it = zip(size(input_array), strides, output_index)
    input_index_range = map(x -> getsliceindex(x...), it)
    return view(input_array, input_index_range...)
end

"""
For pooling operations on an array, returns the expected size of the output
array.
"""
function getoutputsize(input_array::AbstractArray{T, N}, strides::NTuple{N, Int})::NTuple{N, Int} where {T, N}
    output_size = ((x, y) -> round(Int, x/y, RoundUp)).(size(input_array), strides)
    return output_size
end

"""
Returns output from applying `f` to subarrays of `input_array`, with the windows
determined by the `strides`.
"""
function poolmap(f::Function, input_array::AbstractArray{T, N}, strides::NTuple{N, Int}) where {T, N}
    output_size = getoutputsize(input_array, strides)
    output_indices = collect(CartesianRange(output_size))
    return ((I) -> f(getpoolview(input_array, strides, I.I))).(output_indices)
end

function pool(
    input::AbstractArray{T, N},
    params::PoolParameters{N}) where {T<:JuMPReal, N}
    if T<:JuMP.AbstractJuMPScalar
        logger = get_logger(current_module())
        info(logger, "Specifying pooling constraints ... ")
    end
    return poolmap(params.pooling_function, input, params.strides)
end

(p::PoolParameters)(x::Array{T}) where {T<:JuMPReal} = pool(x, p)