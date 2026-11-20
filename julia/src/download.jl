using Downloads, Tar, TOML, Inflate

"""
Windows-friendly way to get the user's home directory.
"""
function get_home()
    if Sys.iswindows()
        if haskey(ENV, "USERPROFILE")
            userhome = ENV["USERPROFILE"]
        else
            drive = get(ENV, "HOMEDRIVE", "")
            userhome = joinpath(drive, ENV["HOMEPATH"])
        end
        return userhome
    else
        return expanduser("~/")
    end
end

function get_version()
    return VersionNumber(
        TOML.parsefile(joinpath(dirname(@__DIR__), "Project.toml"))["version"],
    )
end
const pkg_version = get_version()

# The dogfood line compiles against its own source, pinned in
# dogfood_source.toml, not against upstream's release of the same version.
const DOGFOOD_SOURCE_TOML = joinpath(dirname(@__DIR__), "dogfood_source.toml")
include_dependency(DOGFOOD_SOURCE_TOML)
const DOGFOOD_SOURCE = TOML.parsefile(DOGFOOD_SOURCE_TOML)

const HOME_BRIDGESTAN = joinpath(get_home(), ".bridgestan")
# Named after the pinned commit, so it never shares a directory with upstream's
# release or with another dogfood source.
const CURRENT_BRIDGESTAN = joinpath(
    HOME_BRIDGESTAN,
    "bridgestan-$pkg_version-dogfood-$(first(DOGFOOD_SOURCE["commit"], 12))",
)

const RETRIES = 5


"""
Download the pinned dogfood source to `CURRENT_BRIDGESTAN`: GitHub's archive of
the BridgeStan commit, with the archives of the submodule commits it pins
unpacked into their directories. The source is assembled next to its final
location and moved there in one step, so an interrupted download leaves no
partial source behind.
"""
function get_bridgestan_src()
    mkpath(HOME_BRIDGESTAN)
    staging = mktempdir(HOME_BRIDGESTAN; prefix = ".download-")
    try
        src = joinpath(staging, "bridgestan")
        download_archive(DOGFOOD_SOURCE["repo"], DOGFOOD_SOURCE["commit"], src, staging)
        for (path, sub) in DOGFOOD_SOURCE["submodules"]
            download_archive(sub["repo"], sub["commit"], joinpath(src, path), staging)
        end
        try
            mv(src, CURRENT_BRIDGESTAN)
        catch
            # Another process installed the same source first.
            isfile(joinpath(CURRENT_BRIDGESTAN, "Makefile")) || rethrow()
        end
    finally
        rm(staging; recursive = true, force = true)
    end
end

"""
Unpack GitHub's archive of `repo` at `commit` as the directory `dest`, which
must be absent or empty, using `staging` for the intermediate files.
"""
function download_archive(repo, commit, dest, staging)
    url = "$repo/archive/$commit.tar.gz"
    tmp = joinpath(staging, "$commit.tar.gz")
    err_text = "Failed to download $url."
    for i = 1:RETRIES
        try
            Downloads.download(url, tmp)
            break
        catch e
            if i == RETRIES
                error(err_text, "\n", sprint(showerror, e))
            end
            println(err_text)
            println("Retrying ($(i+1)/$RETRIES)...")
            sleep(1)
        end
    end

    try
        unpacked = joinpath(staging, commit)
        Tar.extract(IOBuffer(Inflate.inflate_gzip(tmp)), unpacked, copy_symlinks = true)
        # The archive holds one directory, `<repository>-<commit>`. A
        # submodule's directory is in its parent's archive, empty.
        isdir(dest) && rm(dest)
        mv(joinpath(unpacked, only(readdir(unpacked))), dest)
    catch e
        error("Failed to unpack $url during installation\n", sprint(showerror, e))
    finally
        rm(tmp; force = true)
    end
end
