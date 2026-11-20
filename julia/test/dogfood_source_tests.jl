using BridgeStan
using Test

# The source pinned in julia/dogfood_source.toml must be this checkout's: the
# pinned commit's files outside julia/ are HEAD's, and its submodules are the
# pinned ones. This needs git and the pinned commit, so a shallow checkout (as
# in CI) or an installed package skips it.
@testset "dogfood source pin" begin
    pin = BridgeStan.DOGFOOD_SOURCE
    commit = pin["commit"]
    root = dirname(dirname(dirname(pathof(BridgeStan))))
    git(args...) = `git -C $root $args`
    has_commit =
        Sys.which("git") !== nothing &&
        success(pipeline(git("cat-file", "-e", "$commit^{commit}"), stderr = devnull))
    if !has_commit
        @test_skip "the pinned commit $commit is not in this checkout"
    else
        @test success(git("diff", "--quiet", commit, "HEAD", "--", ".", ":(exclude)julia"))
        tree = read(git("ls-tree", "-r", commit), String)
        gitlinks =
            Dict(m[2] => m[1] for m in eachmatch(r"^160000 commit (\w+)\t(.+)$"m, tree))
        @test gitlinks == Dict(path => sub["commit"] for (path, sub) in pin["submodules"])
        for (path, sub) in pin["submodules"]
            key = "submodule.$path.url"
            url =
                readchomp(ignorestatus(git("config", "--blob", "$commit:.gitmodules", key)))
            @test url == sub["repo"]
        end
    end
    @test BridgeStan.CURRENT_BRIDGESTAN == joinpath(
        BridgeStan.HOME_BRIDGESTAN,
        "bridgestan-$(BridgeStan.pkg_version)-dogfood-$(first(commit, 12))",
    )
end
