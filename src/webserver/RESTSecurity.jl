mutable struct REST_Specificity
    published_defs::Set
    listening_defs::Set
    restricted_tokens::Dict
end

REST_Specificity_Main = REST_Specificity(Set(), Set(), Dict())
PlutoAPIKey = nothing

# TODO: Only allow arguments defined in the file.
# TODO: Add other in-line syntax

function get_symbol(expr)
    if typeof(expr) == Symbol
        @info "'Expression' is symbol: $expr"
        expr
    elseif typeof(expr) == Expr
        if expr.head == :function 
            @info "Expression is function"
            expr.args[1].args[1]
        elseif expr.head == :(=)
            @info "Expression is assignment"
            expr.args[1]
        elseif expr.head == :macrocall
            @info "Experession is macro call"
            get_symbol(expr.args[3])
        end
    else
        throw(ErrorException("Unknown expression type $expr");)
    end
end


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

macro publish(expr::Expr)    
    try
        symbol = get_symbol(expr)
        @info "Publishing symbol is: $symbol"
        push!(REST_Specificity_Main.published_defs, symbol)  
    catch e
        println("Couldn't publish $symbol")
        throw(e)
    end          
    return esc(expr)
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

macro listen(expr::Expr)    
    try
        symbol = get_symbol(expr)
        @info "Listening symbol is: $symbol"
        push!(REST_Specificity_Main.listening_defs, symbol)  
    catch e
        println("Couldn't publish $symbol")
        throw(e)
    end          
    return esc(expr)
end

macro unlisten(defs...)
    out = "Unlistened: "
    for arg in defs
        delete!(REST_Specificity_Main.listening_defs, Symbol(arg))
        out *= String(Symbol(arg)) * ", "
    end
    out[1:end-2]
end

"""
To call a restricted item use `nb(;Pluto_API_Token=My_Token).item`
"""
macro restrict(token::String, defs...)
    out = "Restricted: "
    for arg in defs
        try
            REST_Specificity_Main.restricted_tokens[Symbol(arg)] = token
            out *= String(Symbol(arg)) * " => $(token)" * ", "
        catch e
            println("Couldn't restrict ", string(Symbol(arg)))
            throw(e)
        end
    end
    @info "--- Published ---"
    out[1:end - 2]
end

macro restrict(token::String, expr::Expr)    
    try
        symbol = get_symbol(expr)
        @info "Restricting symbol is: $symbol"
        REST_Specificity_Main.restricted_tokens[symbol] = token
    catch e
        println("Couldn't restrict $symbol")
        throw(e)
    end          
    return esc(expr)
end

macro unrestrict(defs...)
    out = "Unrestricted: "
    for arg in defs
        delete!(REST_Specificity_Main.restricted_tokens, Symbol(arg))
        out *= String(Symbol(arg)) * ", "
    end
    out[1:end-2]
end