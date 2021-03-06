using JuMP
using ConditionalJuMP
using Memento

function tight_upperbound(x::JuMP.AbstractJuMPScalar; tighten::Bool = true)
    u = upperbound(x)
    if !tighten
        return u
    end
    m = ConditionalJuMP.getmodel(x)
    @objective(m, Max, x)
    status = solve(m)
    if status == :Optimal || status == :UserLimit
        u = min(getobjectivebound(m), u)
        if status == :UserLimit
            log_gap(m)
        end
    end
    debug(get_logger(current_module()), "  Δu = $(upperbound(x)-u)")
    return u
end

function tight_lowerbound(x::JuMP.AbstractJuMPScalar; tighten::Bool = true)
    l = lowerbound(x)
    if !tighten
        return l
    end
    m = ConditionalJuMP.getmodel(x)
    @objective(m, Min, x)
    status = solve(m)
    if status == :Optimal || status == :UserLimit
        l = max(getobjectivebound(m), l)
        if status == :UserLimit
            log_gap(m)
        end
    end
    debug(get_logger(current_module()), "  Δl = $(l-lowerbound(x))")
    return l
end

function log_gap(m::JuMP.Model)
    gap = abs(1-getobjectivebound(m)/getobjectivevalue(m))
    notice(get_logger(current_module()), "Hit user limit during solve to determine bounds. Multiplicative gap was $gap.")
end

function relu(x::Real)::Real
    return max(0, x)
end

function relu(x::JuMP.AbstractJuMPScalar)::JuMP.Variable
    model = ConditionalJuMP.getmodel(x)
    x_rect = @variable(model)
    u = tight_upperbound(x)
    l = tight_lowerbound(x)

    if u < 0
        # rectified value is always 0
        @constraint(model, x_rect == 0)
        setlowerbound(x_rect, 0)
        setupperbound(x_rect, 0)
    elseif l > 0
        # rectified value is always equal to x itself.
        @constraint(model, x_rect == x)
        setlowerbound(x_rect, l)
        setupperbound(x_rect, u)
    else
        a = @variable(model, category = :Bin)

        # refined big-M formulation that takes advantage of the knowledge
        # that lower and upper bounds  are different.
        @constraint(model, x_rect <= x + (-l)*(1-a))
        @constraint(model, x_rect >= x)
        @constraint(model, x_rect <= u*a)
        @constraint(model, x_rect >= 0)

        # model.ext[:objective] = get(model.ext, :objective, 0) + x_rect - x
        model.ext[:objective] = get(model.ext, :objective, 0) + x_rect - x*u/(u-l)

        # Manually set the bounds for x_rect so they can be used by downstream operations.
        setlowerbound(x_rect, 0)
        setupperbound(x_rect, u)
    end

    return x_rect
end

function maximum(xs::AbstractArray{T, N})::T where {T<:Real, N}
    return Base.maximum(xs)
end

function maximum(xs::AbstractArray{T, N}; tighten::Bool = true)::JuMP.Variable where {T<:JuMP.AbstractJuMPScalar, N}
    @assert length(xs) >= 1
    model = ConditionalJuMP.getmodel(xs[1])
    ls = tight_lowerbound.(xs; tighten = tighten)
    us = tight_upperbound.(xs; tighten = tighten)
    l = Base.maximum(ls)
    u = Base.maximum(us)
    x_max = @variable(model,
        lowerbound = l,
        upperbound = u)
    
    xs_filtered::Array{T, 1} = map(
        t-> t[1], 
        Iterators.filter(
            t -> t[2]>l, 
            zip(xs, us)
        )
    )

    if length(xs_filtered) == 1
        @constraint(model, x_max == xs_filtered[1])
    else
        indicators = []
        for (i, x) in enumerate(xs_filtered)
            a = @variable(model, category =:Bin)
            umaxi = Base.maximum(us[1:end .!= i])
            @constraint(model, x_max <= x + (1-a)*(umaxi - ls[i]))
            @constraint(model, x_max >= x)
            push!(indicators, a)
        end
        @constraint(model, sum(indicators) == 1)
    end
    return x_max
end

function abs_ge(x::JuMP.AbstractJuMPScalar)::JuMP.Variable
    model = ConditionalJuMP.getmodel(x)
    x_abs = @variable(model)
    u = upperbound(x)
    l = lowerbound(x)
    if u < 0
        @constraint(model, x_abs == -x)
        setlowerbound(x_abs, -u)
        setupperbound(x_abs, -l)
    elseif l > 0
        @constraint(model, x_abs == x)
        setlowerbound(x_abs, l)
        setupperbound(x_abs, u)
    else
        @constraint(model, x_abs >= x)
        @constraint(model, x_abs >= -x)
        setlowerbound(x_abs, 0)
        setupperbound(x_abs, max(-l, u))
    end
    return x_abs
end

function abs_strict(x::JuMP.AbstractJuMPScalar)::JuMP.Variable
    model = ConditionalJuMP.getmodel(x)
    x_abs = @variable(model)
    u = upperbound(x)
    l = lowerbound(x)
    if u < 0
        @constraint(model, x_abs == -x)
        setlowerbound(x_abs, -u)
        setupperbound(x_abs, -l)
    elseif l > 0
        @constraint(model, x_abs == x)
        setlowerbound(x_abs, l)
        setupperbound(x_abs, u)
    else
        a = @variable(model, category = :Bin)
        @constraint(model, x_abs <= x + 2(-l)*(1-a))
        @constraint(model, x_abs >= x)
        @constraint(model, x_abs <= -x + 2*u*a)
        @constraint(model, x_abs >= -x)
        setlowerbound(x_abs, 0)
        setupperbound(x_abs, max(-l, u))
    end
    return x_abs
end

function set_max_index(
    x::Array{T, 1},
    target_index::Integer,
    tol::Real = 0) where {T<:JuMP.AbstractJuMPScalar}
    """
    Sets the target index to be the maximum.

    Tolerance is the amount of gap between x[target_index] and the other elements.
    """
    @assert length(x) >= 1
    @assert (target_index >= 1) && (target_index <= length(x))
    model = ConditionalJuMP.getmodel(x[1])

    other_vars = [x[1:target_index-1]; x[target_index+1:end]]
    @constraint(model, other_vars - x[target_index] .<= -tol)
    
end