function EventHandlers(kind::String, d::Dict)

    hs=[]
    for (k,v) in d
        if kind in KNOWN_EVT_PROPS
            if v isa NamedTuple
               kis = keys(v)
               @assert :args in kis && :script in kis "Building EventHandler from NamedTuple requires both `args` and `script` keys"
               @assert v.args isa Vector "Function `args` must be of Type Vector{String}. `$(v.args)` of type $(typeof(v.args)) provided."
               if haskey(v, :props)
                   @assert v.props isa Dict "Function `props` must be of Type Dict. `$(v.props)` of type $(typeof(v.props)) provided."
                   if length(v.props)>0
                       push!(hs, CustomEventHandler(kind, k, v.args, v.script, "", "", v.props))
                   end
               else
                    push!(hs, CustomEventHandler(kind, k, v.args, v.script))
               end
            elseif v isa String
               push!(hs,CustomEventHandler(kind,k,[],v))
           elseif v isa Vector
               for script in v
                   push!(hs,CustomEventHandler(kind,k,[],script))
               end
           end
        elseif kind in KNOWN_HOOKS
            for (k,v) in d
                for script in v
                    push!(hs, CustomEventHandler(kind,script,[],script))
                end
            end
        end
    end
    function_script!.(hs)
    return hs
end

function create_events(events::NamedTuple)
    hs=[]
    append!(hs, EventHandlers("methods", events.methods))
    append!(hs, EventHandlers("computed",events.computed))
    append!(hs, EventHandlers("watch", events.watched))
    return hs
end

function_script!(eh::EventHandler)=nothing

function function_script!(eh::CustomEventHandler)

    if eh.path==""
        scope="app_state"
    else
        scope="app_state."*eh.path
    end
    args = size(eh.args, 1) > 0 ? join(eh.args, ",") : "event"
    str = ""
    if eh.kind in KNOWN_EVT_PROPS
        if eh.kind == "methods"
            str=
                replace("""$(eh.id) : function($args) {
                      $(eh.script)
                    }""",
                "@path@"=>"app_state.")

        elseif eh.kind == "computed"
            str = """$(eh.id) : function($args) {
                $(eh.script)
            }"""
        elseif eh.kind == "watch"
            if length(eh.props) > 0
                props = join(["$k:$v" for (k,v) in eh.props],",")
                str = """
                $(eh.id) : {
                $props,
                handler($args) {
                    $(eh.script)
                } }"""
            else
                str = "
                $(eh.id) :
                function($args) {
                    $(eh.script)
                }"
            end
            str = replace(str, "@path@"=>(eh.path != "" ? "$(eh.path)." : ""))
        end
    elseif eh.kind in KNOWN_HOOKS
        str = eh.script
    end

    eh.function_script=str
    return nothing
end

function events_script(vs::VueStruct)
    els=[]
    for e in KNOWN_EVT_PROPS
        ef=filter(x->x.kind==e,vs.events)
        if length(ef)!=0
            push!(els,"$e : {"*join(map(y->y.function_script,ef),",")*"}")
        end
    end
    for hook in KNOWN_HOOKS
        hf=filter(x->x.kind==hook, vs.events)
        if length(hf) > 0
            scripts = []
            for handler in hf
                push!(scripts, handler.function_script)
            end
            push!(els,"$hook() {"*join(scripts,";")*"}")
        end
    end
    return join(els,",")
end

function get_json_attr(d::Dict,a::String,path="app_state")
    out=Dict()
    for (k,v) in d
        if v isa Dict
            if haskey(v,a)
                out[k]=path*".$k.$a"
            else
                ret=get_json_attr(v,a,path*".$k")
                length(ret)!=0 ? out[k]=ret : nothing
            end
        end
    end
    return out
end

function std_events!(vs::VueStruct, new_es::Vector{EventHandler})

    #### xhr #####
    function_script = """xhr : function(contents, url=window.location.pathname, method="POST", async=true, success=null, error=null) {

    console.log(contents)
    var xhr = new XMLHttpRequest();
    if (!error) {
        xhr.onerror = function(){console.log('Error! Request failed with status ' + xhr.status + ' ' + xhr.responseText);}
    }
    else if (typeof(error) === 'function') {
        xhr.onerror = function(xhr) {error(xhr);}
    } else {
        xhr.onerror = function() {return error;}
    }
    xhr.onreadystatechange = function() {
        if (this.readyState == 4) {
            if (this.status == 200 && this.responseText) {
                if (success) {
                    return typeof(success) === 'function' ? success(xhr) : success
                } else {
                    console.log(this.responseText);
                }
            } else {
                xhr.onerror;
            }
        }
    }
    xhr.open(method, url, async);
    xhr.send(contents);
    }"""
    push!(new_es,StdEventHandler("methods","xhr","",function_script))

    #### Submit Method ####
    value_script=replace(JSON.json(get_json_attr(vs.def_data,"value")),"\""=>"")
    function_script="""submit : function(context, url, method, async, success, error) {
        var ret=$value_script

        var search = function(obj, arr) {
            let result = {};
            for(key in obj) {
                if (arr.includes(key)) {
                    result[key] = obj[key];
                } else if (typeof(obj[key]) === 'object') {
                    Object.assign(result, search(obj[key], arr));
               	}
    	    }
            return result;
        }
        if (context && context.length) {
            ret = search(ret, context);
        }
        return xhr(JSON.stringify(ret), url, method, async, success, error)
    }"""
    push!(new_es,StdEventHandler("methods","submit","",function_script))

    ##### Open Method #####
    function_script="""open : function(url,name) {
        name = typeof name !== 'undefined' ? name : '_self';
        window.open(url,name);
        }"""

    push!(new_es,StdEventHandler("methods","open","",function_script))

    ## Datatable Col Format
    function_script="""datatable_col_format : function(item,format_script) {
        return format_script(item)
        }"""

    push!(new_es,StdEventHandler("methods","datatable_col_format","",function_script))

    #get cookie value by cookie name
    function_script="""
    getcookie : function(cname) {
        var name = cname + "=";
        var decodedCookie = decodeURIComponent(document.cookie);
        var ca = decodedCookie.split(';');
        for(var i = 0; i <ca.length; i++) {
            var c = ca[i];
            while (c.charAt(0) == ' ') {
              c = c.substring(1);
            }
            if (c.indexOf(name) == 0) {
              return c.substring(name.length, c.length);
            }
        }
        return "";
        }
    """
    push!(new_es,StdEventHandler("methods","getcookie","",function_script))

    #set a cookie
    function_script = """
    setcookie : function(name, value, days) {
        var d = new Date;
        d.setTime(d.getTime() + 24*60*60*1000*days);
        maxage = days*86400;
        document.cookie = name + "=" + value + ";path=/;max-age="+maxage+";expires=" + d.toGMTString();
    }
    """
    push!(new_es,StdEventHandler("methods","setcookie","",function_script))

    ##### Run in closure #####
    function_script="""run_in_closure : (function(context, fn) {
    path=context=='' ? 'app_state' : 'app_state.'+context
    for (key of Object.keys(eval(path))) {
        eval("var "+key+" = "+path+"."+key)
    }

    fnstr=fn.toString();
    fnstr=fnstr.replace('()=>','');
    eval(fnstr);
    })"""
    push!(new_es,StdEventHandler("methods","run_in_closure","",function_script))
    return nothing
end

"""
Wrapper around submit and xhr method(s)
Allows submissions to be defined at VueElement level as an action, `onclick`, `onchange`, etc
### Examples
```julia
@el(lun,"v-text-field",value="Luanda",label="Luanda",disabled=false)
@el(opo,"v-text-field",value="Oporto",label="Oporto")
@el(sub, "v-btn", value="Submit All", click=submit("api", context=[lun, opo],
    success=["this.window.alert('teste');","this.console.log('teste submissão');"],
    error=["this.console.log('teste erro');"]))
```
"""
function submit(
    url::String;
    method::String="POST",
    async::Bool=true,
    success::Vector=[],
    error::Vector=[],
    context::Vector=[])
    success = size(success, 1) > 0 ? """(function(xhr) {$(join(success,""))})""" : "null"
    error = size(error, 1) > 0 ? """(function(xhr) {$(join(error,""))})""" : "null"
    if context != []
        ids = [x.id for x in context] #Html or Vue Element `id`
        contents = replace(JSON.json(ids), "\""=>"'")
    else
        contents = "null"
    end
    return "submit($contents, '$url', '$method', $async, $success, $error)"
end

function replace_path!(el::VueElement, evts::Vector)

    for evt in evts
        #keeping separate handling for hooks and evt_props since path handling is not yet a closed discussion.
        if evt.kind in KNOWN_HOOKS
            evt.script = replace(evt.script, "@path@"=>(el.path=="" ? "@path@" : "$(el.path)."))
        elseif evt.kind in KNOWN_EVT_PROPS
            evt.script = replace(evt.script, "@path@"=>(el.path=="" ? "@path@" : "$(el.path)."))
            if evt.kind == "watch"
                #check whether the id refers to another event, before applying quotes
                if !(evt.id in map(y->y.id, filter(x->x.kind in ["methods", "computed"], evts)))
                    evt.id = "'$(evt.id)'" #quotes used when watching for element props, important when there are nested elements
                end
                evt.id = replace(evt.id, "@path@"=>(el.path=="" ? "@path@" : "$(el.path)."))
            end
        end
    end
end

function element_evts(vs::VueStruct)
    return vcat(element_evts.(
            filter(x->x isa Vector || x isa VueElement || x isa VueStruct, vs.grid))...)
end

function element_evts(el::VueElement)
    auto_generated_evts!(el)
    evts = element_evts(el.events)
    replace_path!(el, evts)
    return evts
end

function element_evts(evts::Dict)
    out = []
    for (k,v) in evts
        if k in KNOWN_HOOKS
            evt = EventHandlers(k, Dict(k=>v))
            append!(out, evt)
        elseif k in KNOWN_EVT_PROPS
            append!(out, EventHandlers(k, v))
        end
    end
    return out
end

function element_evts(elements::Vector)
    elements = filter(x->x isa Vector || x isa VueElement || x isa VueStruct, elements)
    res = element_evts.(elements)
    evts = vcat(res...)
    return evts
end

function auto_generated_evts!(vue::VueElement)
    id = vue.id
    _value_attr = vue.value_attr isa Nothing ? "" : "."*vue.value_attr #prop we want to store
    interval = get(vue.attrs, "interval", 1000)
    @assert interval isa Int "Attribute interval not of Type Int, $interval of Type $(typeof(interval)) provided"

    mounted = get(vue.events, "mounted", [])
    created = get(vue.events, "created", [])
    watched = get(vue.events, "watch", Dict())
    computed = get(vue.events, "computed", Dict())
    methods = get(vue.events, "methods", Dict())

    if haskey(vue.attrs, "cookie")
        cname = vue.attrs["cookie"]
        read_only = get(vue.attrs, "cookie-read-only", true)

        @assert cname isa String "Attribute cookie not of Type String, $cname of Type $(typeof(cname)) provided"
        expiration = get(vue.attrs, "expiration", 1) #1 day
        @assert expiration isa Int "Attribute expiration not of Type Int, $expiration of Type $(typeof(expiration)) provided"

        compkey = "cookie"*id #computed method name/id
        default_value = get(vue.attrs, "value", "")
        delete!(vue.attrs, "value")
        path = "@path@"*id*_value_attr
        computed[compkey] = "{return this.$path}"
        if !read_only
            watched[compkey] =
    			(args=["val"],
    			script="app.setcookie('$cname', val, $expiration)")
        end
        #m = "this.$path = this.getcookie('$cname') || '$(default_value)'")
        m = """
        var loop = function() {
            window.setInterval(() => {
                this.$path = this.getcookie('$cname') || '$(default_value)'
            }, $interval)
        }.bind(this); loop();
        """
        push!(mounted, m)
        delete!(vue.attrs, "cookie")
        delete!(vue.attrs, "cookie-read-only")
        delete!(vue.attrs, "expiration")
    end

    storage = get(vue.attrs, "storage", false)
    if storage
        default_value = get(vue.attrs, "value", "undefined")
        path = "@path@"*id*_value_attr
        compkey = "storage"*id*"value" #computed method name/id
		storage_key = JSON.json(path) #key for local storage

        #add a computed to avoid overlapping other watch instances, then watch for this computed
        computed[compkey] = """return this.$path;"""
        #watch for the computed prop and act upon it's return value
        watched[compkey] =
			(args=["val"],
			script="""localStorage.setItem($(storage_key), val) """)
        hook_read = """
        var loop = function() {
            window.setInterval(() => {
                this.$path = localStorage[$(storage_key)] || '$(default_value)'
            }, $interval)
        }.bind(this); loop();
        """
        push!(mounted, hook_read)
        delete!(vue.attrs, "storage")
    end
    vue.events["computed"] = computed
    vue.events["mounted"] = mounted
    vue.events["watch"] = watched
end
