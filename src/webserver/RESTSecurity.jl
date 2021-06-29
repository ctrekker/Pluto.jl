published_defs = Set()
listening_defs = Set()

# mutable struct REST_Specificity
#     published_defs::Set
#     listening_defs::Set
# end

# REST_Specificity = REST_Specificity()

# TODO: Only allow arguments defined in the file.
# TODO: Add other in-line syntax
"""
"""
macro publish(defs...)
    out = "Published: "
    for arg in defs
        try
            push!(published_defs, Symbol(arg))
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
        delete!(published_defs, Symbol(arg))
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
            push!(listening_defs, Symbol(arg))
            out *= String(Symbol(arg)) * ", "
        catch e
            println("Couldn't listen for ", string(Symbol(arg)))
            throw(e)
        end
    end
end