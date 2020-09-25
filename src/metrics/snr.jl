using ImageTransformations: center
using Photometry
using Distributions
using Statistics
using ImageFiltering
using StatsBase: mad
using HCIToolbox: get_annulus_segments

"""
    detectionmap([method=snr], data, fwhm; fill=0)

Parallel implementation of arbitrary detection mapping applied to each pixel in the input image. Any invalid values will be set to `fill`.

The following methods are provided in the [`Metrics`](@ref) module:
* [`snr`](@ref) - signal-to-noise ratio (S/N) using student-t statistics to account for small sample penalty.
* [`significance`](@ref) - Gaussian signifance using student-t statistics to account for samll sample penalty.

!!! tip
    This code is automatically multi-threaded, so be sure to set `JULIA_NUM_THREADS` before loading your runtime to take advantage of it!
"""
function detectionmap(method, data::AbstractMatrix{T}, fwhm; fill=zero(T)) where T
    out = fill!(similar(data), fill)
    width = minimum(size(data)) / 2 - 1.5 * fwhm

    masked = get_annulus_segments(data, fwhm/2 + 2, width, mode=:apply)
    coords = findall(!iszero, masked)

    Threads.@threads for coord in coords
        val = method(data, coord, fwhm)
        @inbounds out[coord] = isfinite(val) ? val : fill
    end
    
    return out
end

detectionmap(data, fwhm) = detectionmap(snr, data, fwhm)

"""
    snr(data, position, fwhm)

Calculate the signal to noise ratio (SNR, S/N) for a test point at `position` using apertures of diameter `fwhm` in a residual frame.

Uses the method of Mawet et al. 2014 which includes penalties for small sample statistics. These are encoded by using a student's t-test for calculating the SNR.

!!! note
    SNR is not equivalent to significance, use [`significance`](@ref) instead
"""
function snr(data::AbstractMatrix, position, fwhm)
    x, y = position
    cy, cx = center(data)
    separation = sqrt((x - cx)^2 + (y - cy)^2)
    separation > fwhm / 2 + 1 || return NaN

    θ = 2asin(fwhm / 2 / separation)
    N = floor(Int, 2π / θ)

    sint, cost = sincos(θ)
    xs = similar(data, N)
    ys = similar(data, N)

    # initial points
    rx = x - cx
    ry = y - cy

    @inbounds for idx in eachindex(xs)
        xs[idx] = rx + cx
        ys[idx] = ry + cy
        rx, ry = cost * rx + sint * ry, cost * ry - sint * rx
    end

    r = fwhm / 2

    apertures = CircularAperture.(xs, ys, r)
    fluxes = aperture_photometry(apertures, data, method=:exact).aperture_sum
    other_elements = @view fluxes[2:end]
    bkg_σ = std(other_elements) # ddof = 1 by default
    return (fluxes[1] - mean(other_elements)) / (bkg_σ * sqrt(1 + 1/(N - 1)))
end

snr(data::AbstractMatrix, idx::CartesianIndex, fwhm) = snr(data, (idx.I[2], idx.I[1]), fwhm)

"""
    significance(data, position, fwhm)

Calculates the Gaussian significance from the signal-to-noise ratio (SNR, S/N) for a test point at `position` using apertures of diameter `fwhm` in a residual frame.

The Gaussian signifiance is calculated from converting the SNR confidence limit from a student t distribution to a Gaussian via

``\\text{sig}(\\text{SNR}) = \\Phi^{-1}\\left[\\int_0^\\text{SNR}{t_\\nu(x)dx}\\right]``

where the degrees of freedom ``\\nu`` is given as ``2\\pi r / \\Gamma - 2`` where r is the radial distance of each pixel from the center of the frame.

# See Also
[`snr`](@ref)
"""
function significance(data::AbstractMatrix, position, fwhm)
    x, y = position
    cy, cx = center(data)
    separation = sqrt((x - cx)^2 + (y - cy)^2)
    _snr = snr(data, position, fwhm)
    # put in one line to allow broadcast fusion
    return snr_to_sig(snr, separation, fwhm)
end
significance(data::AbstractMatrix, idx::CartesianIndex, fwhm) = snr(data, (idx.I[2], idx.I[1]), fwhm)

function snr_to_sig(snr, separation, fwhm)
    dof = 2 * π * separation / fwhm - 2
    dof > 0 || return NaN
    return quantile(Normal(), cdf(TDist(dof), Float64(snr)))
end
function sig_to_snr(sig, separation, fwhm)
    dof = 2 * π * separation / fwhm - 2
    dof > 0 || return NaN
    return quantile(TDist(dof), cdf(Normal(), Float64(sig)))
end