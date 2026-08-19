using Test
using MultiDocumenter

@testset "include_versions" begin
    @testset "cp_select_versions" begin
        mktempdir() do src
            write(joinpath(src, "index.html"), "<!DOCTYPE html>")
            write(joinpath(src, "versions.js"), "var DOC_VERSIONS = [];")
            mkdir(joinpath(src, "stable"))
            write(joinpath(src, "stable", "index.html"), "stable")
            mkdir(joinpath(src, "dev"))
            write(joinpath(src, "dev", "index.html"), "dev")
            mkdir(joinpath(src, "v1.0"))
            write(joinpath(src, "v1.0", "index.html"), "v1.0")

            mktempdir() do dst
                MultiDocumenter.cp_select_versions(src, dst, ["stable", "dev"])

                @test isfile(joinpath(dst, "index.html"))
                @test isfile(joinpath(dst, "versions.js"))
                @test isdir(joinpath(dst, "stable"))
                @test read(joinpath(dst, "stable", "index.html"), String) == "stable"
                @test isdir(joinpath(dst, "dev"))
                @test read(joinpath(dst, "dev", "index.html"), String) == "dev"
                @test !isdir(joinpath(dst, "v1.0"))
                @test !isdir(joinpath(dst, ".git"))
            end
        end
    end

    @testset "cp_select_versions with symlink stable" begin
        if Sys.iswindows()
            @test_broken false # symlinks not reliably testable on Windows
            return
        end
        mktempdir() do src
            write(joinpath(src, "versions.js"), "var DOC_VERSIONS = [];")
            mkdir(joinpath(src, "v5.5.0"))
            write(joinpath(src, "v5.5.0", "siteinfo.js"), "{}")
            # stable -> v5.5.0 (simulates Documenter deploy)
            symlink("v5.5.0", joinpath(src, "stable"))
            mkdir(joinpath(src, "dev"))
            write(joinpath(src, "dev", "siteinfo.js"), "{}")

            mktempdir() do dst
                MultiDocumenter.cp_select_versions(src, dst, ["stable", "dev"])

                @test isfile(joinpath(dst, "versions.js"))
                @test isdir(joinpath(dst, "stable"))
                @test isfile(joinpath(dst, "stable", "siteinfo.js"))
                @test isdir(joinpath(dst, "dev"))
                @test !isdir(joinpath(dst, "v5.5.0"))
            end
        end
    end

    versions_js = """
    var DOC_VERSIONS = [
        "stable",
        "v1.0",
        "dev",
    ];
    var DOCUMENTER_NEWEST = "v1.0";
    """

    @testset "rewrite_versions_js" begin
        mktempdir() do dir
            vjs = joinpath(dir, "versions.js")
            write(vjs, versions_js)
            MultiDocumenter.rewrite_versions_js(dir, ["stable", "dev"])
            content = read(vjs, String)
            @test occursin("DOC_VERSIONS", content)
            @test occursin("\"stable\"", content)
            @test occursin("\"dev\"", content)
            # dropped from DOC_VERSIONS (but still named by DOCUMENTER_NEWEST below)
            @test !occursin("\n    \"v1.0\"", content)
            # unrelated declarations are left alone, and we don't leave a stray `;`
            @test occursin("var DOCUMENTER_NEWEST = \"v1.0\";", content)
            @test !occursin(";;", content)
            # no URL given, so no "See All Versions" entry
            @test !occursin(MultiDocumenter.SEE_ALL_VERSIONS_BEGIN, content)
        end
    end

    @testset "rewrite_versions_js with all_versions_url" begin
        mktempdir() do dir
            vjs = joinpath(dir, "versions.js")
            write(vjs, versions_js)
            url = "https://org.github.io/Pkg.jl/"
            MultiDocumenter.rewrite_versions_js(dir, ["stable", "dev"], url)
            content = read(vjs, String)
            @test occursin(MultiDocumenter.SEE_ALL_VERSIONS_BEGIN, content)
            @test occursin(MultiDocumenter.SEE_ALL_VERSIONS_END, content)
            @test occursin("var url = \"$(url)\";", content)
            @test occursin("var label = \"$(MultiDocumenter.SEE_ALL_VERSIONS_LABEL)\";", content)
            @test occursin("\"stable\"", content)
            @test !occursin("\n    \"v1.0\"", content)

            # rewriting again replaces the block rather than appending a second one
            MultiDocumenter.rewrite_versions_js(dir, ["stable", "dev"], url)
            @test read(vjs, String) == content
            @test count(MultiDocumenter.SEE_ALL_VERSIONS_BEGIN, content) == 1

            # ... and dropping the URL removes the block again
            MultiDocumenter.rewrite_versions_js(dir, ["stable", "dev"])
            without = read(vjs, String)
            @test !occursin(MultiDocumenter.SEE_ALL_VERSIONS_BEGIN, without)
            @test !occursin(url, without)
            @test occursin("var DOCUMENTER_NEWEST = \"v1.0\";", without)
        end
    end

    @testset "rewrite_versions_js without versions.js" begin
        mktempdir() do dir
            @test MultiDocumenter.rewrite_versions_js(dir, ["stable"], "https://x.org/") ===
                nothing
            @test !isfile(joinpath(dir, "versions.js"))
        end
    end

    @testset "see_all_versions_url" begin
        ref(; kwargs...) = MultiDocumenter.MultiDocRef(;
            upstream = "up", path = "pkg", name = "Pkg", kwargs...
        )

        @test MultiDocumenter.see_all_versions_url(ref()) === nothing
        @test MultiDocumenter.see_all_versions_url(ref(all_versions_url = "")) === nothing
        @test MultiDocumenter.see_all_versions_url(
            ref(all_versions_url = "https://org.github.io/Pkg.jl/")
        ) == "https://org.github.io/Pkg.jl/"
        @test MultiDocumenter.see_all_versions_url(
            ref(all_versions_url = "http://example.org/")
        ) == "http://example.org/"

        # not derived from giturl: only an explicitly set URL is used
        @test MultiDocumenter.see_all_versions_url(
            ref(giturl = "https://github.com/org/Pkg.jl.git")
        ) === nothing

        # relative URLs would point inside the aggregate, so they are rejected
        @test (
            @test_logs (:warn,) MultiDocumenter.see_all_versions_url(
                ref(all_versions_url = "../elsewhere/")
            )
        ) === nothing
    end

    @testset "uses_include_versions" begin
        ref(; kwargs...) = MultiDocumenter.MultiDocRef(;
            upstream = "up", path = "pkg", name = "Pkg", kwargs...
        )

        @test !MultiDocumenter.uses_include_versions(ref())
        @test !MultiDocumenter.uses_include_versions(ref(include_versions = String[]))
        @test MultiDocumenter.uses_include_versions(ref(include_versions = ["stable"]))
    end

    @testset "MultiDocRef include_versions and all_versions_url" begin
        ref = MultiDocumenter.MultiDocRef(
            upstream = "/tmp/up",
            path = "pkg",
            name = "Pkg",
            giturl = "https://github.com/org/Pkg.jl.git",
            include_versions = ["stable", "dev"],
            all_versions_url = "https://custom.github.io/Pkg.jl/",
        )
        @test ref.include_versions == ["stable", "dev"]
        @test ref.all_versions_url == "https://custom.github.io/Pkg.jl/"

        ref2 = MultiDocumenter.MultiDocRef(
            upstream = "/tmp/up",
            path = "pkg",
            name = "Pkg",
            giturl = "https://github.com/org/Pkg.jl.git",
        )
        @test ref2.include_versions === nothing
        @test ref2.all_versions_url === nothing
    end
end
