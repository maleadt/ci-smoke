# julia#47913 / Server 2025: clipboard() on an empty and on a non-text clipboard, before and
# after loading the patched stdlib/InteractiveUtils/src/clipboard.jl, then the patched
# clipboard section of InteractiveUtils' tests.
using InteractiveUtils, Test
println(VERSION, " on ", Sys.windows_version())
const user32 = "user32"
function setclip(fmt=nothing)
    ccall((:OpenClipboard, user32), stdcall, Cint, (Ptr{Cvoid},), C_NULL) == 0 && Base.windowserror("OpenClipboard")
    try
        ccall((:EmptyClipboard, user32), stdcall, Cint, ()) == 0 && Base.windowserror("EmptyClipboard")
        if fmt !== nothing
            h = ccall((:GlobalAlloc, "kernel32"), stdcall, Ptr{Cvoid}, (Cuint, Csize_t), 2, 1)
            ccall((:SetClipboardData, user32), stdcall, Ptr{Cvoid}, (Cuint, Ptr{Cvoid}), fmt, h) == C_NULL && Base.windowserror("SetClipboardData")
        end
    finally
        ccall((:CloseClipboard, user32), stdcall, Cint, ()) == 0 && Base.windowserror("CloseClipboard")
    end
end
const privfmt = ccall((:RegisterClipboardFormatW, user32), stdcall, Cuint, (Cwstring,), "ci-smoke private format")
probe(label) = for (what, fmt) in (("empty", nothing), ("non-text", privfmt))
    setclip(fmt)
    r = try repr(clipboard()) catch e; sprint(showerror, e) end
    println(rpad(label, 9), rpad(what, 9), "clipboard() -> ", r)
end
probe("stock")
Base.include(InteractiveUtils, joinpath(@__DIR__, "clipboard-patched.jl"))
probe("patched")
t = read(joinpath(@__DIR__, "interactiveutils-runtests.jl"), String)
sect = t[first(findfirst("# clipboard functionality", t)):first(findfirst("# buildbot path updating", t))-1]
@testset "patched clipboard tests" begin
    include_string(Main, sect)
end
