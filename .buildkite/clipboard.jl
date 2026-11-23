# InteractiveUtils' test "empty clipboard": EmptyClipboard, then clipboard() must return "".
using InteractiveUtils
println(VERSION, " on ", Sys.windows_version())
user32 = "user32"
function emptyclip()
    ccall((:OpenClipboard, user32), stdcall, Cint, (Ptr{Cvoid},), C_NULL) == 0 && Base.windowserror("OpenClipboard")
    try
        ccall((:EmptyClipboard, user32), stdcall, Cint, ()) == 0 && Base.windowserror("EmptyClipboard")
    finally
        ccall((:CloseClipboard, user32), stdcall, Cint, ()) == 0 && Base.windowserror("CloseClipboard")
    end
end
for i in 1:3
    emptyclip()
    ccall((:OpenClipboard, user32), stdcall, Cint, (Ptr{Cvoid},), C_NULL) == 0 && Base.windowserror("OpenClipboard")
    ccall(:SetLastError, stdcall, Cvoid, (UInt32,), 0)
    p = ccall((:GetClipboardData, user32), stdcall, Ptr{UInt16}, (Cuint,), 13)
    err = Libc.GetLastError()
    ccall((:CloseClipboard, user32), stdcall, Cint, ()) == 0 && Base.windowserror("CloseClipboard")
    println("try $i: GetClipboardData -> $p, GetLastError = 0x", string(err, base=16, pad=8), " (", Libc.FormatMessage(err), ")")
    r = try repr(clipboard()) catch e; sprint(showerror, e) end
    println("        clipboard() -> ", r)
end
clipboard("abc"); println("roundtrip: ", repr(clipboard()))
