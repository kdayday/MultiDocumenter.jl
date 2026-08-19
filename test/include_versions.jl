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

    @testset "cp_select_versions reports what it copied" begin
        mktempdir() do src
            write(joinpath(src, "versions.js"), "var DOC_VERSIONS = [];")
            mkdir(joinpath(src, "dev"))
            write(joinpath(src, "dev", "siteinfo.js"), "{}")

            mktempdir() do dst
                # "stable" does not exist upstream, so it is reported and skipped
                kept = @test_logs (:warn,) MultiDocumenter.cp_select_versions(
                    src, dst, ["stable", "dev"]
                )
                @test kept == ["dev"]
                @test !ispath(joinpath(dst, "stable"))
                @test isdir(joinpath(dst, "dev"))
            end

            mktempdir() do dst
                kept = @test_logs (:warn,) MultiDocumenter.cp_select_versions(
                    src, dst, ["stable"]
                )
                @test isempty(kept)
            end
        end
    end

    @testset "cp_select_versions ordering follows the request" begin
        mktempdir() do src
            for v in ["dev", "stable"]
                mkdir(joinpath(src, v))
                write(joinpath(src, v, "siteinfo.js"), "{}")
            end
            mktempdir() do dst
                @test MultiDocumenter.cp_select_versions(src, dst, ["dev", "stable"]) ==
                    ["dev", "stable"]
            end
            mktempdir() do dst
                @test MultiDocumenter.cp_select_versions(src, dst, ["stable", "dev"]) ==
                    ["stable", "dev"]
            end
        end
    end

    @testset "cp_select_versions survives a dangling symlink" begin
        if Sys.iswindows()
            @test_skip false
        else
            mktempdir() do src
                mkdir(joinpath(src, "dev"))
                write(joinpath(src, "dev", "siteinfo.js"), "{}")
                # stable -> v9.9.9, whose directory was pruned from gh-pages by hand
                symlink("v9.9.9", joinpath(src, "stable"))
                # a root level symlink to a file that is gone
                symlink("nowhere.js", joinpath(src, "orphan.js"))

                mktempdir() do dst
                    # one warning, naming the dangling link -- not also a generic
                    # "does not exist upstream" for the same entry
                    kept = @test_logs (:warn,) MultiDocumenter.cp_select_versions(
                        src, dst, ["stable", "dev"]
                    )
                    @test kept == ["dev"]
                    @test !ispath(joinpath(dst, "stable"))
                    @test !ispath(joinpath(dst, "orphan.js"))
                    @test isdir(joinpath(dst, "dev"))
                end
            end
        end
    end

    @testset "cp_select_versions resolves root level symlinks" begin
        if Sys.iswindows()
            @test_skip false
        else
            mktempdir() do src
                write(joinpath(src, "real.js"), "contents")
                symlink("real.js", joinpath(src, "alias.js"))
                mkdir(joinpath(src, "dev"))
                mktempdir() do dst
                    MultiDocumenter.cp_select_versions(src, dst, ["dev"])
                    # copied as a real file, not as a symlink that may dangle in the output
                    @test isfile(joinpath(dst, "alias.js"))
                    @test !islink(joinpath(dst, "alias.js"))
                    @test read(joinpath(dst, "alias.js"), String) == "contents"
                end
            end
        end
    end

    function fake_version_tree(dir, versions; newest = "v2.0.0", stable = "stable")
        write(
            joinpath(dir, "versions.js"),
            "var DOC_VERSIONS = [\n  \"stable\",\n  \"v2.0.0\",\n  \"v1.0.0\",\n  \"dev\",\n];\n" *
                "var DOCUMENTER_NEWEST = \"$(newest)\";\n",
        )
        for (v, current) in versions
            mkpath(joinpath(dir, v))
            write(
                joinpath(dir, v, "siteinfo.js"),
                "var DOCUMENTER_CURRENT_VERSION = \"$(current)\";\n" *
                    "var DOCUMENTER_STABLE = \"$(stable)\";\n",
            )
        end
        return nothing
    end

    @testset "rewrite_versions_js updates DOCUMENTER_NEWEST" begin
        mktempdir() do dir
            # v2.0.0 was not copied, so it must not keep claiming to be the newest
            fake_version_tree(dir, ["v1.0.0" => "v1.0.0", "dev" => "dev"])
            MultiDocumenter.rewrite_versions_js(dir, ["v1.0.0", "dev"])
            content = read(joinpath(dir, "versions.js"), String)
            @test occursin("var DOCUMENTER_NEWEST = \"v1.0.0\";", content)
            @test !occursin("v2.0.0", content)
        end

        mktempdir() do dir
            # stable holds the newest release, so DOCUMENTER_NEWEST is already right
            fake_version_tree(dir, ["stable" => "v2.0.0", "dev" => "dev"])
            MultiDocumenter.rewrite_versions_js(dir, ["stable", "dev"])
            @test occursin(
                "var DOCUMENTER_NEWEST = \"v2.0.0\";",
                read(joinpath(dir, "versions.js"), String),
            )
        end

        mktempdir() do dir
            # nothing kept is a release, and `dev` never triggers the banner anyway
            fake_version_tree(dir, ["dev" => "dev"])
            MultiDocumenter.rewrite_versions_js(dir, ["dev"])
            @test occursin(
                "var DOCUMENTER_NEWEST = \"v2.0.0\";",
                read(joinpath(dir, "versions.js"), String),
            )
        end
    end

    @testset "rewrite_stable_target!" begin
        mktempdir() do dir
            # stable was not copied, so the banner must point at the newest kept release
            fake_version_tree(dir, ["v1.0.0" => "v1.0.0", "dev" => "dev"])
            MultiDocumenter.rewrite_stable_target!(dir, ["v1.0.0", "dev"])
            for v in ["v1.0.0", "dev"]
                @test occursin(
                    "var DOCUMENTER_STABLE = \"v1.0.0\";",
                    read(joinpath(dir, v, "siteinfo.js"), String),
                )
            end
        end

        mktempdir() do dir
            # stable was copied, so it stays the target
            fake_version_tree(dir, ["stable" => "v2.0.0", "dev" => "dev"], stable = "stable")
            MultiDocumenter.rewrite_stable_target!(dir, ["stable", "dev"])
            @test occursin(
                "var DOCUMENTER_STABLE = \"stable\";",
                read(joinpath(dir, "stable", "siteinfo.js"), String),
            )
        end

        mktempdir() do dir
            # no release kept: leave siteinfo.js alone rather than invent a target
            fake_version_tree(dir, ["dev" => "dev"])
            before = read(joinpath(dir, "dev", "siteinfo.js"), String)
            MultiDocumenter.rewrite_stable_target!(dir, ["dev"])
            @test read(joinpath(dir, "dev", "siteinfo.js"), String) == before
        end
    end

    @testset "is_generated_redirect" begin
        @test MultiDocumenter.is_generated_redirect(
            "<!--This file is automatically generated by MultiDocumenter.jl-->\n<meta/>"
        )
        @test MultiDocumenter.is_generated_redirect(
            "<!--This file is automatically generated by Documenter.jl-->\n<meta/>"
        )
        @test !MultiDocumenter.is_generated_redirect("<!DOCTYPE html><html><body>hi</body>")
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
