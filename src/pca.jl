using Statistics
using LinearAlgebra
using TSVD: tsvd


"""
    PCA(;ncomps=nothing, pratio=1) <: LinearAlgorithm
    PCA(ncomps; pratio=1)

Use principal components analysis (PCA) to form a low-rank orthonormal basis of the input. Uses deterministic singular-value decomposition (SVD) to decompose data.

If `ncomps` is `nothing`, it will be set to the number of frames in the reference cube when processed.

# References
* [Soummer, Pueyo, and Larkin (2012)](https://ui.adsabs.harvard.edu/abs/2012ApJ...755L..28S) "Detection and Characterization of Exoplanets and Disks Using Projections on Karhunen-Loève Eigenimages"

# Implements
* [`decompose`](@ref)
"""
@with_kw struct PCA <: LinearAlgorithm
    ncomps::Union{Int,Nothing} = nothing
    pratio::Float64 = 1.0
end

PCA(ncomps; kwargs...) = PCA(;ncomps=ncomps, kwargs...)

function decompose(alg::PCA, cube, angles, cube_ref=cube; kwargs...)
    @unpack ncomps, pratio = alg
    isnothing(ncomps) && (ncomps = size(cube, 1))
    ncomps > size(cube, 1) && error("ncomps ($ncomps) cannot be greater than the number of frames ($(size(cube, 1)))")

    # transform cube
    X = flatten(cube)
    X_ref = flatten(cube_ref)

    # fit SVD to get principal subspace of reference
    decomp = svd(X_ref)

    # get the minimum number comps to explain `pratio`
    pr = cumsum(decomp.S ./ sum(decomp.S))
    pr_n = findfirst(p -> p ≥ pratio, pr)
    nc = isnothing(pr_n) ? min(ncomps, size(decomp.Vt, 1)) : min(ncomps, pr_n, size(decomp.Vt, 1))

    nc < ncomps && @info "target pratio $pratio reached with only $nc components"
    # Get the principal components (principal subspace)
    P = decomp.Vt[1:nc, :]
    # reconstruct X using prinicipal subspace
    weights = X * P'

    return P, weights
end

"""
    TPCA(;ncomps=nothing) <: LinearAlgorithm
    TPCA(ncomps; pratio=1)

Perform principal components analysis (PCA) using truncated SVD (TSVD; provided by TSVD.jl) instead of deterministic SVD. This is often faster than [`PCA`](@ref) but is non-deterministic, so the results may be different.

If `ncomps` is `nothing`, it will be set to the number of frames in the reference cube when processed.

# Implements
* [`decompose`](@ref)

# See Also
* [`PCA`](@ref), [`TSVD.tsvd`](https://github.com/JuliaLinearAlgebra/TSVD.jl)
"""
@with_kw struct TPCA <: LinearAlgorithm
    ncomps::Union{Int,Nothing} = nothing
end

function decompose(alg::TPCA, cube, angles, cube_ref=cube; kwargs...)
    X = flatten(cube)
    X_ref = flatten(cube_ref)
    k = isnothing(alg.ncomps) ? size(cube, 1) : alg.ncomps
    k > size(cube, 1) && error("ncomps ($k) cannot be greater than the number of frames ($(size(cube, 1)))")
    A = _tsvd_projection(X_ref, k) # type instability 
    w = X * A'
    return A, w
end

function _tsvd_projection(X_ref, k)
    U, Σ, V = tsvd(X_ref, k)
    return V'
end
