mutable struct REST_Specificity
    published_defs::Set
    listening_defs::Set
end

REST_Specificity_Main = REST_Specificity(Set(), Set())

# TODO: Only allow arguments defined in the file.
# TODO: Add other in-line syntax
"""
"""
macro publish(defs...)
    out = "Published: "
    for arg in defs
        try
            push!(REST_Specificity_Main.published_defs, Symbol(arg))
            out *= String(Symbol(arg)) * ", "
        catch e
            println("Couldn't publish ", string(Symbol(arg)))
            throw(e)
        end
    end
    @info "--- Published ---"
    out[1:end - 2]
end

macro unpublish(defs...)
    out = "Unpublished: "
    for arg in defs
        delete!(REST_Specificity_Main.published_defs, Symbol(arg))
        out *= String(Symbol(arg)) * ", "
    end
    out[1:end-2]
end

"""
"""
macro listen(defs...)
    out = "Listening: "
    for arg in defs
        try
            push!(REST_Specificity_Main.listening_defs, Symbol(arg))
            out *= String(Symbol(arg)) * ", "
        catch e
            println("Couldn't listen for ", string(Symbol(arg)))
            throw(e)
        end
    end
    @info "--- Listening ---"
    out[1:end-2]
end

macro unlisten(defs...)
    out = "Unlistened: "
    for arg in defs
        delete!(REST_Specificity_Main.listening_defs, Symbol(arg))
        out *= String(Symbol(arg)) * ", "
    end
    out[1:end-2]
end