UPDATE_VALIDATION["v-data-table"]=(x)->begin
    col_pref="c__"
    trf_col=x->col_pref*vue_escape(string(x))
    trf_dom=x->begin
    x.attrs=Dict(k=>vue_escape(v) for (k,v) in x.attrs)
    x.value=x.value isa String ? vue_escape(x.value) : x.value
    end

    x.value_attr=nothing

    ## Has Items
    if haskey(x.attrs,"items")
        if x.attrs["items"] isa DataFrame
            df=x.attrs["items"]
            arr=[]
            col_idx=Dict{String,Int64}()
            i=1
            for n in names(df)
                col_arr=df[:,n]
               if length(arr)==0
                    arr=map(x->Dict{String,Any}(trf_col(n)=>x),col_arr)
                else
                    map((x,y)->y[trf_col(n)]=x,col_arr,arr)
                end
                col_idx[trf_col(string(n))]=i
                i+=1
            end
            x.attrs["items"]=arr
            if !(haskey(x.attrs,"headers"))
                x.attrs["headers"]=[Dict{String,Any}("value"=>trf_col(n),"text"=>n) for n in string.(names(df))]
            end

            ### Default Formatting
            for (i,n) in enumerate(names(df))
                n=string(n)
                ### Numbers
                if eltype(df[!,i])<:Union{Missing,Number}
                    map(x->x["text"]==n ? x["align"]="end" : nothing ,x.attrs["headers"])

                    ## Default Renders
                    if !haskey(x.attrs,"col_format") || (haskey(x.attrs,"col_format") && !haskey(x.attrs["col_format"],n))
                        digits=maximum(skipmissing(df[:,Symbol(n)]))>=1000 ? 0 : 2
                        eltype(df[!,i])<:Union{Missing,Int} ? digits=0 : nothing
                        haskey(x.attrs,"col_format") ? nothing : x.attrs["col_format"]=Dict{String,Any}()
                        x.attrs["col_format"][n]="x=> x==null ? x : x.toLocaleString('pt',{minimumFractionDigits: $digits, maximumFractionDigits: $digits})"
                    end
                end
            end
        end

        ## normalize Headers if not internally built
        if !(sum(map(c->startswith(c["value"],col_pref),x.attrs["headers"]))==length(x.attrs["headers"]))
            map(c->c["value"]=trf_col(c["value"]),x.attrs["headers"])
        end

        ## Col Format
        if haskey(x.attrs,"col_format")
            @assert x.attrs["col_format"] isa Dict "col_format should be a Dict of cols and anonymous js function!"
            new_col_format=Dict{String,Any}()
            for (k,v) in x.attrs["col_format"]
                new_col_format[trf_col(k)]=v
            end
            x.attrs["col_format"]=new_col_format

            for (k,v) in x.attrs["col_format"]
				x.slots["item.$k='{item}'"]="""<div v-html="datatable_col_format(item.$k,@path@$(x.id).col_format.$k)"></div>"""
			end
        end

        ## Col Template
        if haskey(x.attrs,"col_template")
            @assert x.attrs["col_template"] isa Dict "col_template should be a Dict of cols and HtmlElement!"
            new_col_template=Dict{String,Any}()
            for (k,v) in x.attrs["col_template"]
                new_col_template[trf_col(k)]=v
            end
            x.attrs["col_template"]=new_col_template

            for (k,v) in x.attrs["col_template"]
                value_dom=nothing
                v isa HtmlElement ? value_dom=v : nothing
                if v isa VueElement
                    vd=deepcopy(v)
                    vd.template=true
                    value_dom=dom(vd)
                end
                value_dom!=nothing ? trf_dom(value_dom) : nothing
                value_dom!=nothing ? value_str=htmlstring(value_dom) : nothing

                v isa String ? value_str=vue_escape(v) : nothing

                value_str=replace(value_str,"item."=>"item.$(col_pref)")
                x.slots["item.$k='{item}'"]=value_str

                x.attrs["headers"][col_idx[k]]["align"]="center"
			end
        end

    end
end

UPDATE_VALIDATION["v-switch"]=(x)->begin

    x.value_attr="input-value"
end

UPDATE_VALIDATION["v-btn"]=(x)->begin

    ## attr alias of content
    haskey(x.attrs,"value") ? (x.attrs["content"]=x.attrs["value"];delete!(x.attrs,"value")) : nothing
    haskey(x.attrs,"text") ? (x.attrs["content"]=x.attrs["text"];delete!(x.attrs,"text")) : nothing

    x.value_attr=nothing
end

UPDATE_VALIDATION["v-select"]=(x)->begin

    @assert haskey(x.attrs,"items") "Vuetify Select element with no arg items!"
    @assert typeof(x.attrs["items"])<:Array "Vuetify Select element with non Array arg items!"

    if !haskey(x.attrs,"value")
        x.attrs["value"] = get(x.attrs, "multiple", false) != false ? [] : nothing
    end
end

UPDATE_VALIDATION["v-list"]=(x)->begin

    mark_template!(v)=nothing
    mark_template!(v::Array)=mark_template.(v)
    mark_template!(v::VueElement)=v.template=true

    @assert haskey(x.attrs,"items") "Vuetify List element with no arg items!"
    @assert typeof(x.attrs["items"])<:Array "Vuetify List element with non Array arg items!"
    @assert haskey(x.attrs,"item") "Vuetify List element with no arg item!"

    x.value_attr="items"

    x.attrs["v-for"]="item in @path@$(x.id).value"
    x.attrs["v-bind:key"]="item.id"

    x.child=x.attrs["item"]
    mark_template!(x.child)
    delete!(x.attrs,"item")

end

UPDATE_VALIDATION["v-tabs"]=(x)->begin

    @assert haskey(x.attrs,"names") "Vuetify tab with no names, please define names array!"
    @assert x.attrs["names"] isa Array "Vuetify tab names should be an array"
    @assert length(x.attrs["names"])==length(x.elements) "Vuetify Tabs elements should have the same number of names!"

    x.render_func=y->begin
       content=[]
       for (i,r) in enumerate(y.elements)
           push!(content,HtmlElement("v-tab",Dict(),nothing,y.attrs["names"][i]))
           value=r isa Array ? dom(r) : dom([r])
           push!(content,HtmlElement("v-tab-item",Dict(),12,value))
       end
       HtmlElement("v-tabs",y.attrs,12,content)
    end
end

UPDATE_VALIDATION["v-navigation-drawer"]=(x)->begin

    @assert haskey(x.attrs,"items") "Vuetify navigation with no items, please define items array!"
    @assert x.attrs["items"] isa Array "Vuetify navigation items should be an array"

    x.value_attr="items"

    item_names=collect(keys(x.attrs["items"][1]))
    x.tag="v-list"
    x.attrs["item"]="""<v-list-item dense link @click="open(item.href)">
            $("icon" in item_names ? "<v-list-item-icon><v-icon>{{ item.icon }}</v-icon></v-list-item-icon>" : "")
            <v-list-item-content><v-list-item-title>{{ item.title }}</v-list-item-title></v-list-item-content></v-list-item"""

    update_validate!(x)

    x.render_func=y->begin

        dom_nav=dom(y,prevent_render_func=true)

        nav_attrs=Dict()

        for (k,v) in Dict("clipped"=>true,"width"=>200, "expand-on-hover"=>true, "permanent"=>true, "right"=>false)
            haskey(y.attrs,k) ? nav_attrs[k]=y.attrs[k] : nav_attrs[k]=v
        end

        HtmlElement("v-navigation-drawer",nav_attrs,12,dom_nav)
    end
end

UPDATE_VALIDATION["v-card"]=(x)->begin

    @assert haskey(x.attrs,"names") "Vuetify card with no names, please define names array!"
    @assert x.attrs["names"] isa Array "Vuetify card names should be an array"
    @assert length(x.attrs["names"])==length(x.elements) "Vuetify card elements should have the same number of names!"

    x.render_func=y->begin
       content=[]
       for (i,r) in enumerate(y.elements)
           push!(content,HtmlElement(y.attrs["names"][i],Dict(),12,dom(r)))
       end
       HtmlElement("v-card",y.attrs,y.cols,content)
    end
end

UPDATE_VALIDATION["v-alert"]=(x)->begin


	## Validations
	haskey(x.attrs,"value") ? (@assert x.attrs["value"] isa Bool "Value Attr of Alert Should be Bool") : nothing

	## 3 Basic Defaults
	haskey(x.attrs,"content") ? nothing : x.attrs["content"]=""
	haskey(x.attrs,"type") ? nothing : x.attrs["type"]="success"
	haskey(x.attrs,"value") ? nothing : x.attrs["value"]=false

	## 3 Basic Bindings
	x.binds["content"]=x.id*".content"
	x.binds["type"]=x.id*".type"
	x.binds["value"]=x.id
	x.value_attr=nothing

	dismissible = get(x.attrs, "dismissible", false)
	timeout = get(x.attrs, "timeout", 0)
	delay = get(x.attrs, "delay", 0)

	if !haskey(x.slots, "default")
		tmp = Dict("default"=>"{{@path@"*x.id*".content}}")
		length(x.slots) != 0 ? merge!(x.slots, tmp) : x.slots = tmp
	end

	if !haskey(x.slots, "close") && (dismissible || timeout > 0)
		icon = get(x.attrs, "close-icon", "mdi-close")
		tmp = Dict("close='{toggle}'"=>"""<v-icon @click="this.window.setTimeout(()=>{ @path@$(x.id).value = false }, $delay)">$icon</v-icon>""")
		length(x.slots) != 0 ? merge!(x.slots, tmp) : x.slots = tmp
	end
	if timeout > 0
		watched = get(x.events, "watch", Dict())
		timeout_hook = """setTimeout(()=>{@path@$(x.id).value=false}, $timeout)"""
		watched["@path@$(x.id).value"] =
			(args=["newval"],
			props=Dict("immediate"=>true),
			script="""if(newval){setTimeout(()=>{this.@path@$(x.id).value=false}, $timeout)}""")
		x.events["watch"] = watched
	end
end
