using Test
using MultiDocumenter

# Gumbo is not a declared test dependency, so reach it through MultiDocumenter
const Gumbo = MultiDocumenter.Gumbo

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
            # symlinks are not reliably testable on Windows. Note that `return` here
            # would exit the *enclosing* testset, silently skipping everything below.
            @test_skip false
        else
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
            # the link lives in the HTML, not here
            @test !occursin(MultiDocumenter.SEE_ALL_VERSIONS_LABEL, content)
        end
    end

    @testset "rewrite_versions_js without versions.js" begin
        mktempdir() do dir
            @test MultiDocumenter.rewrite_versions_js(dir, ["stable"]) === nothing
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

    @testset "see_all_versions_urls" begin
        ref(; kwargs...) = MultiDocumenter.MultiDocRef(;
            upstream = "up", name = "Pkg", kwargs...
        )
        limited = ref(
            path = "Limited",
            include_versions = ["stable"],
            all_versions_url = "https://org.github.io/Limited.jl/",
        )
        nested = ref(
            path = joinpath("group", "Nested"),
            include_versions = ["stable"],
            all_versions_url = "https://org.github.io/Nested.jl/",
        )
        # a URL without include_versions has nothing to link to
        unlimited = ref(path = "Full", all_versions_url = "https://org.github.io/Full.jl/")
        # ... and include_versions without a URL just limits versions
        no_url = ref(path = "Quiet", include_versions = ["stable"])

        urls = MultiDocumenter.see_all_versions_urls(
            Any[limited, nested, unlimited, no_url]
        )
        @test length(urls) == 2

        for_page(p) = MultiDocumenter.see_all_versions_url_for(urls, p)
        @test for_page(joinpath("Limited", "stable", "index.html")) ==
            "https://org.github.io/Limited.jl/"
        @test for_page(joinpath("Limited", "stable", "man", "guide.html")) ==
            "https://org.github.io/Limited.jl/"
        @test for_page(joinpath("group", "Nested", "stable", "index.html")) ==
            "https://org.github.io/Nested.jl/"
        @test for_page(joinpath("Full", "stable", "index.html")) === nothing
        @test for_page(joinpath("Quiet", "stable", "index.html")) === nothing
        @test for_page(joinpath("Other", "stable", "index.html")) === nothing
        # the aggregate root and the per-package redirect stub have no selector
        @test for_page("index.html") === nothing
        @test for_page(joinpath("Limited", "index.html")) ==
            "https://org.github.io/Limited.jl/"
        @test MultiDocumenter.see_all_versions_url_for(
            Dict{Vector{String}, String}(), joinpath("Limited", "stable", "index.html")
        ) === nothing
    end

    @testset "inject_see_all_versions_option!" begin
        selector = """
        <html><body><div id="documenter">
        <div class="docs-version-selector field has-addons">
        <div class="control"><span class="docs-label button is-static is-size-7">Version</span></div>
        <div class="docs-selector control is-expanded"><div class="select is-fullwidth is-size-7">
        <select id="documenter-version-selector"></select>
        </div></div></div></div></body></html>
        """
        url = "https://org.github.io/Pkg.jl/"

        html = Gumbo.parsehtml(selector)
        MultiDocumenter.inject_see_all_versions_option!(html, url)
        out = string(html)
        @test occursin("<option value=\"$(url)\">$(MultiDocumenter.SEE_ALL_VERSIONS_LABEL)</option>", out)
        # the option is inside the selector, and it is the only one
        @test count("<option", out) == 1

        # a page without a version selector is left alone
        bare = Gumbo.parsehtml("<html><body><div id=\"documenter\"></div></body></html>")
        MultiDocumenter.inject_see_all_versions_option!(bare, url)
        @test !occursin("option", string(bare))
    end

    @testset "uses_include_versions" begin
        ref(; kwargs...) = MultiDocumenter.MultiDocRef(;
            upstream = "up", path = "pkg", name = "Pkg", kwargs...
        )

        @test !MultiDocumenter.uses_include_versions(ref())
        @test !MultiDocumenter.uses_include_versions(ref(include_versions = String[]))
        @test MultiDocumenter.uses_include_versions(ref(include_versions = ["stable"]))
    end
end
