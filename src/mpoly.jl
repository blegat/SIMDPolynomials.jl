abstract type AbstractMultivariatePolynomial{T,M} <: AbstractPolynomial end
abstract type AbstractUnivariatePolynomial{T,M} <: AbstractMultivariatePolynomial{T,M} end
const AMP{T,M} = AbstractMultivariatePolynomial{T,M}
#Base.promote_rule(t::Type{<:AMP{T,Nothing}}, ::Type{<:AMP{T}}) where {T} = t
# default polynomial type
struct MPoly{T,M} <: AMP{T,M}
    terms::T
    metadata::M
end

(P::Type{<:AMP})(x) = parameterless_type(P)(x, nothing)
(P::Type{<:AMP})(x::AbstractTerm) = parameterless_type(P)([dropmetadata(x)], metadata(x))
function (P::Type{<:AMP{T}})(x::Union{CoeffType,<:AbstractMonomial}) where {T}
    TT = eltype(T)
    parameterless_type(P)(Term{coefftype(TT),monomialtype(TT)}(x))
end

terms(x::AMP) = x.terms
metadata(x::AMP) = x.metadata

_copy(x) = copy(x)
_copy(x::Nothing) = x
Base.copy(x::P) where {P<:AMP} = P(map(copy, terms(x)), _copy(metadata(x)))

Base.:*(x::AbstractTerm, p::AMP) = p * x
function Base.:*(p::K, x::T1) where {K<:AMP,T1<:AbstractTerm}
    v = checkmetadata(p, x)
    P = parameterless_type(K)
    T = dropmetadata(T1)
    if iszero(x)
        return P(emptyterm(T), v)
    elseif isone(x)
        return p
    else
        P(T[t * x for t in terms(p) if !iszero(t)], v)
    end
end
Base.:*(p::AMP, x::AMP) = sum(t->p * t, terms(x))
Base.:+(p::AMP, x::AbstractTerm) = add!(copy(p), x)
Base.:-(p::AMP, x::AbstractTerm) = sub!(copy(p), x)

Base.:-(p::AMP) = -1 * p
sub!(p::AMP, x::AbstractTerm) = add!(p, -x)

addcoef(x::T, c) where {T<:AbstractTerm} = (c += coeff(x); return iszero(c), parameterless_type(T)(c, monomial(x)))
addcoef(x::T, c::T) where {T<:AbstractTerm} = addcoef(x, c.coeff)
subcoef(x::T, c) where {T<:AbstractTerm} = (c = coeff(x) - c; return iszero(c), parameterless_type(T)(c, monomial(x)))
subcoef(x::T, c::T) where {T<:AbstractTerm} = subcoef(x, c.coeff)

function add!(p::AMP, x::AbstractTerm)
    q = _add!(p, x);
    (debugmode() && !issorted(terms(q), rev=true)) && throw("Polynomial not sorted!")
    q
end
function _add!(p::AMP, x::AbstractTerm)
    iszero(x) && return p
    ts = terms(p)
    # TODO: remove this line cause bugs
    x = dropmetadata(x)
    for (i, t) in enumerate(ts)
        if ismatch(t, x)
            iz, t = addcoef(t, x)
            if iz
                deleteat!(ts, i)
            else
                ts[i] = t
            end
            return p
        elseif t < x
            insert!(ts, i, x)
            return p
        end
    end
    push!(ts, x)
    return p
end

function add!(p::AbstractPolynomial, x::AbstractPolynomial)
    for t in terms(x)
        add!(p, t)
    end
    return p
end
function sub!(p::AbstractPolynomial, x::AbstractPolynomial)
    for t in terms(x)
        sub!(p, t)
    end
    return p
end
Base.:+(p::AbstractPolynomial, x::AbstractPolynomial) = add!(copy(p), x)
Base.:-(p::AbstractPolynomial, x::AbstractPolynomial) = sub!(copy(p), x)

function rmlt!(p::MPoly)
    ts = terms(p)
    popfirst!(ts)
    return p
end
function takelt!(p::MPoly, x::MPoly)
    add!(p, lt(x))
    rmlt!(x)
    return p
end

function Base.divrem(p::MPoly, d::MPoly)
    p = copy(p)
    q = MPoly(similar(terms(p), 0))
    r = MPoly(similar(terms(p), 0))
    while !isempty(terms(p))
        nx, fail = lt(p) / lt(d)
        if fail
            takelt!(r, p)
        else
            #p -= d * nx
            #q += nx
            sub!(p, d * nx)
            add!(q, nx)
        end
    end
    return q, r
end

function divexact(p::MPoly, d::MPoly)
    p = copy(p)
    q = MPoly(similar(terms(p), 0))
    while !isempty(terms(p))
        nx, fail = lt(p) / lt(d)
        @assert !fail
        sub!(p, d * nx)
        add!(q, nx)
    end
    return q
end

function Base.rem(p::AbstractPolynomial, d::AbstractPolynomial)
    p = copy(p)
    r = MPoly(similar(terms(p), 0))
    while !isempty(terms(p))
        nx, fail = lt(p) / lt(d)
        if fail
            takelt!(r, p)
        else
            p -= d * nx
        end
    end
    return r
end

# TODO
Base.:(/)(x::MPoly, y::MPoly) = divexact(x, y)

Base.gcd(x::AbstractTerm, y::MPoly) = gcd(MPoly(x), y)
Base.gcd(x::MPoly, y::AbstractTerm) = gcd(y, x)
function Base.gcd(x::MPoly, y::MPoly)
    # trival case
    if iszero(x) || isone(y)
        return y
    elseif iszero(y) || isone(x) || x == y
        return x
    end

    v1, p1 = to_univariate(x)
    v2, p2 = to_univariate(y)
    if v1 < v2
        x, y = y, x
        v1, v2 = v2, v1
        p1, p2 = p2, p1
    end
    # v2 < v1
    # both are constants
    v2 == NOT_A_VAR && return MPoly(gcd(lt(x), lt(y)))
    if v2 < v1
        # `v2` in p2 doesn't exist in `x`, so the gcd at this level is 1 and we
        # just move on to the next level
        return gcd(x, content(p2))
    end
    v1 == v2 || error("unreachable")

    g = gcd(p1, p2)
    return univariate_to_multivariate(g)
end

function pick_var(x::MPoly)
    ts = terms(x)
    v = NOT_A_VAR
    for (i, t) in enumerate(ts)
        if degree(t) > 0
            m = monomial(t)
            vv = m.ids[1] # get the minvar
            if vv < v
                v = vv
            end
        end
    end
    return v
end

function to_univariate(x::MPoly)
    v = pick_var(x)
    v, (v == NOT_A_VAR ? nothing : SPoly(x, v))
end
