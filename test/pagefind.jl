using Test
using MultiDocumenter
using NodeJS_22_jll: npm, npx

const PageFind = MultiDocumenter.PageFind

@testset "npm_command" begin
    @testset "posix runs the shim directly" begin
        if !Sys.iswindows()
            # bin/npm and bin/npx are the npm CLI's JavaScript with a `#!/usr/bin/env node`
            # shebang there, so they need no interpreter of their own.
            cmd = PageFind.npm_command(
                "/js/bin/npx", "pagefind", "-V"; dir = "/root"
            )
            @test cmd == Cmd(`/js/bin/npx pagefind -V`; dir = "/root")
            @test cmd.exec == ["/js/bin/npx", "pagefind", "-V"]
            @test cmd.dir == "/root"

            # a space in a path is Julia's to escape here, not ours
            spaced = PageFind.npm_command(
                "/js b/npx", "install", "pagefind"; dir = "/r"
            )
            @test spaced.exec == ["/js b/npx", "install", "pagefind"]
        end
    end

    @testset "windows goes through cmd.exe /S /C" begin
        if Sys.iswindows()
            cmd = PageFind.npm_command(
                "C:\\js\\bin\\npx", "pagefind", "-V"; dir = "C:\\root"
            )
            # the .cmd sibling, wrapped in the form Base documents for cmd.exe
            @test cmd == Cmd(
                Cmd(["cmd.exe", "/S /C \"C:\\js\\bin\\npx.cmd pagefind -V\""]);
                windows_verbatim = true, dir = "C:\\root",
            )
            # windows_verbatim has to be set, or Julia would re-quote the line we assembled
            @test cmd != Cmd(
                Cmd(["cmd.exe", "/S /C \"C:\\js\\bin\\npx.cmd pagefind -V\""]);
                dir = "C:\\root",
            )
            @test cmd.dir == "C:\\root"

            # /S strips the outer quote pair, so a path with a space keeps its own quotes and
            # reaches the program intact -- the case a bare `cmd /c $path` gets wrong
            spaced = PageFind.npm_command(
                "C:\\Users\\John Doe\\bin\\npx", "pagefind", "-V"; dir = "C:\\r"
            )
            @test last(spaced.exec) ==
                "/S /C \"\"C:\\Users\\John Doe\\bin\\npx.cmd\" pagefind -V\""

            # the glob we pass contains none of cmd.exe's metacharacters, so it survives as-is
            glob = "*/{stable,dev}/**/*.{html}"
            globbed = PageFind.npm_command(
                "C:\\js\\bin\\npx", "pagefind", "--glob", glob; dir = "C:\\r"
            )
            @test occursin("--glob $(glob)", last(globbed.exec))
        end
    end

    @testset "the shims this platform needs exist" begin
        @test isfile(npx)
        @test isfile(npm)
        if Sys.iswindows()
            @test isfile(npx * ".cmd")
            @test isfile(npm * ".cmd")
        end
    end
end
