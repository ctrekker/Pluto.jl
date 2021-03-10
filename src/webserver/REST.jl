module REST
import ..Pluto: ServerSession, Notebook, NotebookTopology, Cell, FunctionName, WorkspaceManager, where_assigned, where_referenced, update_save_run!
import UUIDs: UUID
import HTTP
import JSON
import MsgPack

function direct_parents(notebook::Notebook, topology::NotebookTopology, node::Cell)
    filter(notebook.cells) do cell
        any(x ∈ topology[node].references for x ∈ topology[cell].definitions)
    end
end

function upstream_roots(notebook::Notebook, topology::NotebookTopology, from::Cell)
    found = Set{Cell}()
    parents = direct_parents(notebook, topology, from)

    for p ∈ parents
        if length(direct_parents(notebook, topology, p)) == 0
            found = found ∪ Set([p])
        else
            found = found ∪ upstream_roots(notebook, topology, p)
        end
    end

    found
end
function upstream_roots(notebook::Notebook, topology::NotebookTopology, from::Union{Vector{Cell}, Set{Cell}})
    reduce(∪, (x->upstream_roots(notebook, topology, x)).(from))
end

function get_notebook_output(session::ServerSession, notebook::Notebook, topology::NotebookTopology, inputs::Dict{Symbol, Any}, outputs::Set{Symbol})
    assigned = where_assigned(notebook, topology, outputs)
    provided_set = keys(inputs)
    to_set = provided_set

    new_values = values(inputs)
    output_cell = where_assigned(notebook, topology, outputs)[1]

    to_reeval = [
        # Re-evaluate all cells that reference the modified input parameters
        # TODO: Change this to a recursive where_referenced down to outputs. Needs to be smarter
        where_referenced(notebook, notebook.topology, Set{Symbol}(to_set))...
        # Re-evaluate all input cells that were not provided as parameters
        # TODO: Uncomment and figure something out to prevent whole notebook from running
        where_assigned(notebook, notebook.topology, Set{Symbol}(filter(x->(x ∉ provided_set), to_set)))...
    ]

    function custom_deletion_hook((session, notebook)::Tuple{ServerSession,Notebook}, to_delete_vars::Set{Symbol}, funcs_to_delete::Set{Tuple{UUID,FunctionName}}, to_reimport::Set{Expr}; to_run::AbstractVector{Cell})
        to_delete_vars = Set([to_delete_vars..., to_set...]) # also delete the bound symbols
        WorkspaceManager.delete_vars((session, notebook), to_delete_vars, funcs_to_delete, to_reimport)
        for (sym, new_value) in zip(to_set, new_values)
            WorkspaceManager.eval_in_workspace((session, notebook), :($(sym) = $(new_value)))
        end
    end
    function custom_deletion_hook2((session, notebook)::Tuple{ServerSession,Notebook}, to_delete_vars::Set{Symbol}, funcs_to_delete::Set{Tuple{UUID,FunctionName}}, to_reimport::Set{Expr}; to_run::AbstractVector{Cell})
        to_delete_vars = Set([to_delete_vars...])
        WorkspaceManager.delete_vars((session, notebook), to_delete_vars, funcs_to_delete, to_reimport)
    end

    update_save_run!(session, notebook, to_reeval; deletion_hook=custom_deletion_hook, run_async=false, save=false)
    out = Dict(out_symbol => WorkspaceManager.eval_fetch_in_workspace((session, notebook), out_symbol) for out_symbol in outputs)
    update_save_run!(session, notebook, where_assigned(notebook, notebook.topology, Set{Symbol}(to_set)); deletion_hook=custom_deletion_hook2)

    out
end
get_notebook_output(session::ServerSession, notebook::Notebook, topology::NotebookTopology, inputs::Dict{Symbol, Any}, outputs::Vector{Symbol}) = get_notebook_output(session, notebook, topology, inputs, Set(outputs))


function evaluate(output::Symbol, host::AbstractString="localhost:1234", session_id::Union{AbstractString, Nothing}=nothing, with_json=false; kwargs...)
    query = ["outputs" => string(output), "inputs" => JSON.json(kwargs)]
    if !isnothing(session_id)
        push!(query, "id" => session_id)
    end
    request_uri = merge(HTTP.URI("http://$(host)/notebookfile/eval"); query=query)

    response = HTTP.get(request_uri, [
        "Accept" => with_json ? "application/json" : "application/x-msgpack"
    ])
    
    if with_json
        return JSON.parse(String(response.body))[string(output)]
    else
        return MsgPack.unpack(response.body)[string(output)]
    end
end
end