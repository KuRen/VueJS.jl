
mutable struct VueElement
    
    id::String
    dom::htmlElement
    path::String
    binds::Dict{String,String}
    value_attr::Union{Nothing,String}
    data::Dict{String,Any}
    cols::Union{Nothing,Int64}
    
end
 

specific_update_validation=Dict(

"v-switch"=>(x)->begin
    x.value_attr="input-value"
end,   
    
"v-btn"=>(x)->begin
    x.value_attr=nothing
end,   
"v-select"=>(x)->begin
    @assert haskey(x.dom.attrs,"items") "Vuetify Select element with no arg items!"
    @assert typeof(x.dom.attrs["items"])<:Array "Vuetify Select element with non Array arg items!"
end

)

function update_validate!(vuel::VueElement,args::Dict)
     
   
    ### Specific Validations and updates
    tag=vuel.dom.tag
    if haskey(specific_update_validation,tag)
        specific_update_validation[tag](vuel)
    end
    
     ## Bindig of non html accepted values => Arrays/Dicts
    for (k,v) in vuel.dom.attrs
       if !(v isa String || v isa Date || v isa Number)
          vuel.binds[k]=vuel.id.*"."*k
       end 
    end
    
    
    ## Default Binding value_attr
    if vuel.value_attr==nothing
        if haskey(vuel.dom.attrs,"value")
            vuel.dom.value=vuel.dom.attrs["value"]
            delete!(vuel.dom.attrs,"value")
        end
    else
        ## Decision was to tag as value even for the cases that it's not the value attr, better generalization and some attrs can not be used as JS vars e.g. text-input
        vuel.binds[vuel.value_attr]=vuel.id.*".value"
    end
    
    ## Events
    events=intersect(keys(vuel.dom.attrs),["click","mouseover"])
    for e in events
        event_js=vuel.dom.attrs[e]
        delete!(vuel.dom.attrs,e)
        vuel.dom.attrs["@$e"]=event_js isa Array ? join(event_js) : event_js
    end
   
    ## cols
    if vuel.cols==nothing
        vuel.cols=3
        vuel.dom.cols=3
    else
        vuel.dom.cols=vuel.cols
    end
    
    return nothing
end


function VueElement(id::String,tag::String;kwargs...)
    
    args=Dict(string(k)=>v for (k,v) in kwargs)
    
    ## Args for Vue
    haskey(args,"cols") ? cols=args["cols"] : cols=nothing
    
    vuel=VueElement(id,htmlElement(tag,args,cols,""),"",Dict(),"value",Dict(),cols)
    update_validate!(vuel,args)
    
    return vuel
end

macro el(args...)
    
    @assert typeof(args[1])==Symbol "1st arg should be Variable name"
    @assert typeof(args[2])==String "2nd arg should be tag name"
    
    varname=(args[1])
    
    newargs=join(string.(args[3:end]),",")
    
    newexpr=(Meta.parse("""VueElement("$(string(args[1]))","$(string(args[2]))",$newargs)"""))
    return quote
        $(esc(varname))=$(esc(newexpr))
    end
end

