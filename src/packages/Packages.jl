
import .ExpressionExplorer: external_package_names
import .PkgTools
import .PkgTools: getfirst, is_stdlib

function external_package_names(topology::NotebookTopology)::Set{Symbol}
    union!(Set{Symbol}(), external_package_names.(c.module_usings_imports for c in values(topology.codes))...)
end

const tiers = [
	Pkg.PRESERVE_ALL,
	Pkg.PRESERVE_DIRECT,
	Pkg.PRESERVE_SEMVER,
	Pkg.PRESERVE_NONE,
]

const pkg_token = Token()


function write_semver_compat_entries!(ctx::Pkg.Types.Context)
    for p in keys(ctx.env.project.deps)
        if !haskey(ctx.env.project.compat, p)
            entry = getfirst(e -> e.name == p, values(ctx.env.manifest))
            if entry.version !== nothing
                ctx.env.project.compat[p] = "^" * string(entry.version)
            end
        end
    end
    Pkg.Types.write_env(ctx.env)
end


function clear_semver_compat_entries!(ctx::Pkg.Types.Context)
    for p in keys(ctx.env.project.compat)
        entry = getfirst(e -> e.name == p, values(ctx.env.manifest))
        if entry.version !== nothing
            if ctx.env.project.compat[p] == "^" * string(entry.version)
                delete!(ctx.env.project.compat, p)
            end
        end
    end
    Pkg.Types.write_env(ctx.env)
end


function use_plutopkg(topology::NotebookTopology)
    !any(values(topology.nodes)) do node
        Symbol("Pkg.activate") ∈ node.references ||
        Symbol("Pkg.API.activate") ∈ node.references ||
        Symbol("Pkg.add") ∈ node.references ||
        Symbol("Pkg.API.add") ∈ node.references
    end
end


function update_nbpkg(session::ServerSession, notebook::Notebook, old::NotebookTopology, new::NotebookTopology)
    ctx = notebook.nbpkg_ctx

    👺 = false

    use_plutopkg_old = ctx !== nothing
    use_plutopkg_new = use_plutopkg(new)
    
    if !use_plutopkg_old && use_plutopkg_new
        @info "Started using PlutoPkg!! HELLO reproducibility!"

        👺 = true
        ctx = notebook.nbpkg_ctx = PkgTools.create_empty_ctx()
    end
    if use_plutopkg_old && !use_plutopkg_new
        @info "Stopped using PlutoPkg 💔😟😢"

        no_packages_loaded_yet = (
            notebook.nbpkg_restart_required_msg === nothing &&
            notebook.nbpkg_restart_recommended_msg === nothing &&
            keys(ctx.env.project.deps) ⊆ PkgTools.stdlibs
        )
        👺 = !no_packages_loaded_yet
        ctx = notebook.nbpkg_ctx = nothing
    end
    

    if ctx !== nothing
        # search all cells for imports and usings
        new_packages = String.(external_package_names(new))
        
        removed = setdiff(keys(ctx.env.project.deps), new_packages)
        added = setdiff(new_packages, keys(ctx.env.project.deps))
        
        # We remember which Pkg.Types.PreserveLevel was used. If it's too low, we will recommend/require a notebook restart later.
        local used_tier = Pkg.PRESERVE_ALL
        
        withtoken(pkg_token) do
            to_remove = filter(removed) do p
                haskey(ctx.env.project.deps, p)
            end
            to_add = filter(PkgTools.package_exists, added)
            @show to_add
            
            # Progress stuff
            to_do_count = length(to_remove) + length(to_add)
            progress = 0
            @show to_do_count

            update_progress = (progress, current_package=nothing, operation=nothing) -> (
                putnotebookupdates!(session, notebook, UpdateMessage(:🙃, Dict(
                    :progress => progress,
                    :package => current_package,
                    :operation => operation,
                    :goal => to_do_count
                ), notebook, nothing, nothing))
            )


            update_progress(progress, nothing, :remove)

            if !isempty(to_remove)
                # See later comment
                mkeys() = keys(filter(!is_stdlib ∘ last, ctx.env.manifest)) |> collect
                old_manifest_keys = mkeys()

                for p in to_remove
                    update_progress(progress, p, :remove)
                    Pkg.rm(ctx, [Pkg.PackageSpec(name=p)])
                    progress += 1
                end


                # We record the manifest before and after, to prevent recommending a reboot when nothing got removed from the manifest (e.g. when removing GR, but leaving Plots), or when only stdlibs got removed.
                new_manifest_keys = mkeys()
                
                # TODO: we might want to upgrade other packages now that constraints have loosened???
            end

            
            # TODO: instead of Pkg.PRESERVE_ALL, we actually want:
            # "Pkg.PRESERVE_DIRECT, but preserve exact verisons of Base.loaded_modules"

            if !isempty(to_add)
                # We temporarily clear the "semver-compatible" [deps] entries, because Pkg already respects semver, unless it doesn't, in which case we don't want to force it.
                clear_semver_compat_entries!(ctx)

                for tier in [
                    Pkg.PRESERVE_ALL,
                    Pkg.PRESERVE_DIRECT,
                    Pkg.PRESERVE_SEMVER,
                    Pkg.PRESERVE_NONE,
                ]
                    used_tier = tier

                    try
                        for p in to_add
                            update_progress(progress, p, :add)
                            Pkg.add(ctx, [Pkg.PackageSpec(name=p)]; preserve=used_tier)
                            progress += 1
                        end
                        
                        break
                    catch e
                        if used_tier == Pkg.PRESERVE_NONE
                            # give up
                            rethrow(e)
                        end
                    end
                end

                write_semver_compat_entries!(ctx)

                @info "PlutoPkg done"
            end

            update_progress(progress, nothing, :add)

            should_instantiate = !notebook.nbpkg_ctx_instantiated || !isempty(to_add) || !isempty(to_remove)
            if should_instantiate
                # @info "Resolving"
                # Pkg.resolve(ctx)
                @info "Instantiating"
                Pkg.instantiate(ctx)
                notebook.nbpkg_ctx_instantiated = true
            end

            return (
                did_something=👺 || (
                    should_instantiate
                ),
                used_tier=used_tier,
                # changed_versions=Dict{String,Pair}(),
                restart_recommended=👺 || (
                    (!isempty(to_remove) && old_manifest_keys != new_manifest_keys) ||
                    used_tier != Pkg.PRESERVE_ALL
                ),
                restart_required=👺 || (
                    used_tier ∈ [Pkg.PRESERVE_SEMVER, Pkg.PRESERVE_NONE]
                ),
            )
        end
    else
        return (
            did_something=👺 || false,
            used_tier=Pkg.PRESERVE_ALL,
            # changed_versions=Dict{String,Pair}(),
            restart_recommended=👺 || false,
            restart_required=👺 || false,
        )
    end
end
