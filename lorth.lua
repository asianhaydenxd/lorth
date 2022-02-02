local function remove_comments(text)
    local commentless_text = {}
    for line in text:gmatch("[^\r\n]+") do
        if line:sub(1,1) ~= "#" then
            local parts = {}
            for str in line:gmatch("[^#]+") do
                table.insert(parts, str)
            end
            table.insert(commentless_text, parts[1])
        end
    end
    return table.concat(commentless_text, "\n")
end

local function raise(message, index)
    message = message or "unspecified"
    index = index or "unknown"
    print("Exception raised: "..message.." (index "..index..")")
    os.exit()
end

local function tksplit(token)
    local t = {}
    for str in string.gmatch(token, "([^:]+)") do
        table.insert(t, str)
    end
    local token_name = t[1]
    table.remove(t, 1)
    local token_value = table.concat(t, ":")
    return token_name, token_value
end

local function skip_to_end(i, tokens)
    local nesting = 0 -- Workaround for nesting
    while true do
        i = i + 1
        local ctk = tksplit(tokens[i])

        if ctk == "DO" or ctk == "IF" or ctk == "CONST" then
            nesting = nesting + 1

        elseif ctk == "END" then
            if nesting == 0 then
                break
            else
                nesting = nesting - 1
            end
        end
    end
    return i
end

local function skip_to_elif_else_end(i, tokens)
    local nesting = 0 -- Workaround for nesting
    while true do
        i = i + 1
        local ctk = tksplit(tokens[i])

        if ctk == "DO" or ctk == "IF" or ctk == "CONST" then
            nesting = nesting + 1

        elseif ctk == "END" or ctk == "ELSE" or ctk == "ELIF" then
            if nesting == 0 then
                break
            else
                nesting = nesting - 1
            end
        end
    end
    return i
end

local function split(text) -- Credit: Paul Kulchenko (stackoverflow)
    -- Split text using whitespace but keep single and double quotes intact
    text = remove_comments(text)
    local split_text = {}
    local spat, epat, buf, quoted = [=[^(['"])]=], [=[(['"])$]=], nil, nil
    for str in text:gmatch("%S+") do
        local squoted = str:match(spat)
        local equoted = str:match(epat)
        local escaped = str:match([=[(\*)['"]$]=])
        if squoted and not quoted and not equoted then
            buf, quoted = str, squoted
        elseif buf and equoted == quoted and #escaped % 2 == 0 then
            str, buf, quoted = buf .. ' ' .. str, nil, nil
        elseif buf then
            buf = buf .. ' ' .. str
        end
        if not buf then
            table.insert(split_text, str)
        end
    end
    if buf then
        raise("missing matching quote for "..buf, #split_text+1)
        return nil
    end
    return split_text
end

local function parse(code)
    local tokens = {}
    local functs = {}
    local consts = {}
    local params = {}

    local libdata = {}

    code = split(code)
    
    local function is_within(token, a, b)
        return token:sub(1, 1) == a and token:sub(#token) == b
    end

    local function push(token)
        table.insert(tokens, token)
    end

    local index = 0
    while index < #code do
        index = index + 1
        local token = code[index]
        if token == "require" then
            index = index + 1
            
            local req_name = code[index]
            local req_script

            if not pcall(function ()
                req_script = assert(io.open(req_name, "rb")):read("*all")
            end) then
                raise("invalid file name for require", index)
            end

            if req_name:sub(-string.len(".lorth")) == ".lorth" then
                local req_alias = req_name:sub(1, -7)
                if code[index + 1] == "as" then
                    index = index + 2
                    req_alias = code[index]
                end
    
                local parsed_script = parse(req_script)
    
                for token_index, new_token in ipairs(split(req_script)) do
                    local req_token = tksplit(parsed_script[token_index])
                    
                    if req_token == "FUNCT_NAME" or req_token == "CALL_FUNCT" or req_token == "CONST_NAME" or req_token == "CALL_CONST" then
                        table.insert(code, req_alias..":"..new_token)
                    else
                        table.insert(code, new_token)
                    end
                end
            elseif req_name:sub(-string.len(".lua")) == ".lua" then
                local req_alias = req_name:sub(1, -5)
                if code[index + 1] == "as" then
                    index = index + 2
                    req_alias = code[index]
                end

                local library = require(req_name:sub(1, -5))
                for i, v in pairs(library) do
                    local librarydata = req_alias..":"..i
                    if libdata[librarydata] then raise("library data "..librarydata.." already imported", index) end
                    libdata[librarydata] = v
                end
            end

        end
    end

    index = 0
    while index < #code do
        index = index + 1
        local token = code[index]
        if token == "function" then
            index = index + 1
            functs[code[index]] = true
            while code[index+1] ~= "do" do
                index = index + 1
            end

        elseif token == "const" then
            index = index + 1
            consts[code[index]] = true
        end
    end

    index = 0
    while index < #code do
        index = index + 1
        local token = code[index]
        
        -- Data types
        if is_within(token, [["]], [["]]) or is_within(token, [[']], [[']]) then
            push("OP_PUSH_STR:"..token:sub(2, #token-1))

        elseif tonumber(token) then
            push("OP_PUSH_NUM:"..token)

        elseif token == "true" then
            push("OP_PUSH_BOOL:true")

        elseif token == "false" then
            push("OP_PUSH_BOOL:false")

        -- Arithmetic operators
        elseif token == "+" then
            push("OP_ADD")

        elseif token == "-" then
            push("OP_SUBTRACT")

        elseif token == "*" then
            push("OP_MULTIPLY")

        elseif token == "/" then
            push("OP_DIVIDE")

        elseif token == "%" then
            push("OP_MODULUS")
        
        -- Comparison operators
        elseif token == "=" then
            push("OP_EQUAL")

        elseif token == "!=" then
            push("OP_NOT_EQUAL")
        
        elseif token == ">" then
            push("OP_GREATER_THAN")
        
        elseif token == "<" then
            push("OP_LESS_THAN")
        
        elseif token == ">=" then
            push("OP_GREATER_EQUAL")
        
        elseif token == "<=" then
            push("OP_LESS_EQUAL")

        -- Logical operators
        elseif token == "and" then
            push("OP_AND")
        
        elseif token == "or" then
            push("OP_OR")
        
        elseif token == "not" then
            push("OP_NOT")
        
        -- Keywords
        elseif token == "print" then
            push("PRINT")

        elseif token == "read" then
            push("READ")

        elseif token == "printall" then
            push("PRINT_STACK")

        elseif token == "stacklen" then
            push("PUSH_STACK_LENGTH")

        elseif token == "type" then
            push("TYPE")

        elseif token == "assert" then
            push("ASSERT")

        elseif token == "dup" then
            push("DUPLICATE")

        elseif token == "del" then
            push("REMOVE")

        elseif token == "argc" then
            push("PUSH_ARG_LENGTH")

        elseif token == "argv" then
            push("PUSH_ARG_VALUE")

        elseif token == "continue" then
            push("CONTINUE")

        elseif token == "break" then
            push("BREAK")

        elseif token == "return" then
            push("RETURN")
        
        elseif token == "if" then
            push("IF")
        
        elseif token == "then" then
            push("THEN")
        
        elseif token == "else" then
            push("ELSE")

        elseif token == "elif" then
            push("ELIF")
        
        elseif token == "while" then
            push("WHILE")

        elseif token == "const" then
            push("CONST")
            index = index + 1
            push("CONST_NAME:"..code[index])
        
        elseif token == "function" then
            push("FUNCT")
            index = index + 1
            push("FUNCT_NAME:"..code[index])
            while code[index+1] ~= "do" do
                index = index + 1
                push("PARAM:"..code[index])
                params[code[index]] = true
            end
        
        elseif token == "let" then
            push("LET")
            local init_index = index -- for debugging
            while code[index+1] ~= "do" do
                index = index + 1
                if code[index] == nil then raise("let does not have closing do", init_index) end
                push("PARAM:"..code[index])
                params[code[index]] = true
            end
        
        elseif token == "peek" then
            push("PEEK")
            local init_index = index -- for debugging
            while code[index+1] ~= "do" do
                index = index + 1
                if code[index] == nil then raise("peek does not have closing do", init_index) end
                push("PARAM:"..code[index])
                params[code[index]] = true
            end
        
        elseif token == "do" then
            push("DO")

        elseif token == "end" then
            local temp_i = index -- Temporary index
            local nesting = 0 -- Unmatched bracket counter; workaround for nesting
            while true do
                temp_i = temp_i - 1
                local ctk = tksplit(tokens[temp_i])

                if ctk == "END" then
                    nesting = nesting + 1

                elseif ctk == "WHILE" or ctk == "FUNCT" or ctk == "LET" or ctk == "PEEK" or ctk == "IF" or ctk == "CONST" then
                    if nesting == 0 then
                        break
                    else
                        nesting = nesting - 1
                    end
                
                -- To destroy params before being called outside
                elseif params[code[temp_i]] ~= nil then
                    params[code[temp_i]] = nil

                elseif ctk == nil then
                    raise("unmatched end", index)
                end
            end

            push("END:"..temp_i)
        
        elseif token == "exit" then
            push("EXIT")

        elseif token == "tokens" then
            push("PRINT_TOKENS")

        elseif token == "require" then
            push("REQUIRE")
            index = index + 1
            push("REQUIRE_FILE:"..code[index])
            if code[index+1] == "as" then
                index = index + 1
                push("REQUIRE_AS")
                index = index + 1
                push("REQUIRE_ALIAS:"..code[index])
            end
        
        elseif functs[token] ~= nil then
            push("CALL_FUNCT:"..token)

        elseif consts[token] ~= nil then
            push("CALL_CONST:"..token)
        
        elseif params[token] ~= nil then
            push("PUSH_PARAM:"..token)

        elseif libdata[token] ~= nil then
            push("LIBDATA:"..token)

        else
            push("UNKNOWN:"..token)
        end
    end

    return tokens, libdata
end

local function compile(code)
    local stack = {}
    local params = {}
    local function_addresses = {}
    local function_calls = {}
    local constant_addresses = {}
    local constant_calls = {}
    local tokens, libdata = parse(code)

    -- print(table.concat(tokens, " "))

    -- Hoisting functions and constants
    local index = 0
    while index < #tokens do
        index = index + 1

        local token, value = tksplit(tokens[index])

        if token == "FUNCT_NAME" then
            local init_index = index - 1
            local funct_name = value
            while true do
                index = index + 1
                if tokens[index] == "DO" then
                    break
                end
            end
            function_addresses[funct_name] = init_index

        elseif token == "CONST_NAME" then
            constant_addresses[value] = index
        end
    end

    -- Run everything else
    index = 0
    while index < #tokens do
        index = index + 1
        -- print(index)

        local token, value = tksplit(tokens[index])
        
        -- Data types
        if token == "OP_PUSH_STR" then
            table.insert(stack, value)

        elseif token == "OP_PUSH_NUM" then
            table.insert(stack, tonumber(value))

        elseif token == "OP_PUSH_BOOL" then
            local toboolean = {["true"]=true, ["false"]=false}
            table.insert(stack, toboolean[value])

        elseif token == "OP_PUSH_NULL" then
            table.insert(stack, nil)

        -- Arithmetic operators
        elseif token == "OP_ADD" then
            local a = stack[#stack-1]
            local b = stack[#stack]
            table.remove(stack, #stack)
            table.remove(stack, #stack)
            table.insert(stack, a + b)

        elseif token == "OP_SUBTRACT" then
            local a = stack[#stack-1]
            local b = stack[#stack]
            table.remove(stack, #stack)
            table.remove(stack, #stack)
            table.insert(stack, a - b)
            
        elseif token == "OP_MULTIPLY" then
            local a = stack[#stack-1]
            local b = stack[#stack]
            table.remove(stack, #stack)
            table.remove(stack, #stack)
            table.insert(stack, a*b)

        elseif token == "OP_DIVIDE" then
            local a = stack[#stack-1]
            local b = stack[#stack]
            table.remove(stack, #stack)
            table.remove(stack, #stack)
            table.insert(stack, a/b)
        
        elseif token == "OP_MODULUS" then
            local a = stack[#stack-1]
            local b = stack[#stack]
            table.remove(stack, #stack)
            table.remove(stack, #stack)
            table.insert(stack, math.fmod(a, b))

        elseif token == "OP_EQUAL" then
            local a = stack[#stack-1]
            local b = stack[#stack]
            table.remove(stack, #stack)
            table.remove(stack, #stack)
            table.insert(stack, a == b)
        
        elseif token == "OP_NOT_EQUAL" then
            local a = stack[#stack-1]
            local b = stack[#stack]
            table.remove(stack, #stack)
            table.remove(stack, #stack)
            table.insert(stack, a ~= b)
        
        elseif token == "OP_GREATER_THAN" then
            local a = stack[#stack-1]
            local b = stack[#stack]
            table.remove(stack, #stack)
            table.remove(stack, #stack)
            table.insert(stack, a > b)

        elseif token == "OP_LESS_THAN" then
            local a = stack[#stack-1]
            local b = stack[#stack]
            table.remove(stack, #stack)
            table.remove(stack, #stack)
            table.insert(stack, a < b)

        elseif token == "OP_GREATER_EQUAL" then
            local a = stack[#stack-1]
            local b = stack[#stack]
            table.remove(stack, #stack)
            table.remove(stack, #stack)
            table.insert(stack, a >= b)
        
        elseif token == "OP_LESS_EQUAL" then
            local a = stack[#stack-1]
            local b = stack[#stack]
            table.remove(stack, #stack)
            table.remove(stack, #stack)
            table.insert(stack, a <= b)

        -- Logical operators
        elseif token == "OP_AND" then
            local a = stack[#stack-1]
            local b = stack[#stack]
            table.remove(stack, #stack)
            table.remove(stack, #stack)
            table.insert(stack, a and b)

        elseif token == "OP_OR" then
            local a = stack[#stack-1]
            local b = stack[#stack]
            table.remove(stack, #stack)
            table.remove(stack, #stack)
            table.insert(stack, a or b)

        elseif token == "OP_NOT" then
            local a = stack[#stack]
            table.remove(stack, #stack)
            table.insert(stack, not a)

        -- Keywords
        elseif token == "PRINT" then
            if #stack == 0 then raise("cannot interpret empty stack", index) end
            print(stack[#stack])
            table.remove(stack, #stack)
        
        elseif token == "PRINT_STACK" then
            local out = ""
            for address, element in ipairs(stack) do
                if address ~= 1 then
                    out = out..", "
                end
                out = out..element
            end
            print(out)

        elseif token == "TYPE" then
            local item = stack[#stack]
            table.remove(stack, #stack)
            table.insert(stack, type(item))

        elseif token == "ASSERT" then
            if stack[#stack] == false then
                raise("assertion failed", index)
            end

        elseif token == "DUPLICATE" then
            table.insert(stack, stack[#stack])

        elseif token == "REMOVE" then
            table.remove(stack, #stack)

        elseif token == "PUSH_ARG_LENGTH" then
            table.insert(stack, #arg)

        elseif token == "PUSH_ARG_VALUE" then
            local item = stack[#stack]
            table.remove(stack, #stack)
            if arg[item] == nil then raise("invalid arg", index) end
            table.insert(stack, arg[item])

        elseif token == "CONTINUE" then
            while true do
                local ctk, cv = tksplit(tokens[index + 1])
                if ctk == "END" and tokens[tonumber(cv)] == "WHILE" then
                    break
                end
                index = index + 1
            end

        elseif token == "BREAK" then
            while true do
                local ctk, cv = tksplit(tokens[index + 1])
                if ctk == "END" and tokens[tonumber(cv)] == "WHILE" then
                    break
                end
                index = index + 1
            end
            index = index + 1

        elseif token == "RETURN" then
            while true do
                local ctk, cv = tksplit(tokens[index + 1])
                if ctk == "END" and tokens[tonumber(cv)] == "FUNCT" then
                    break
                end
                index = index + 1
            end

        elseif token == "THEN" then
            local bool = stack[#stack]
            table.remove(stack, #stack)
            if not bool then
                index = skip_to_elif_else_end(index, tokens)
            end

        elseif token == "ELSE" then -- Is only called when everything above is run
            index = skip_to_end(index, tokens)

        elseif token == "ELIF" then -- Is only called when everything above is run
            index = skip_to_end(index, tokens)

        elseif token == "DO" then -- only ever called on WHILE
            local bool = stack[#stack]
            table.remove(stack, #stack)
            if not bool then
                index = skip_to_end(index, tokens)
            end

        elseif token == "END" then
            if tokens[tonumber(value)] == "WHILE" then
                index = tonumber(value)
            elseif tokens[tonumber(value)] == "FUNCT" then
                index = function_calls[#function_calls]
                table.remove(function_calls, #function_calls)
            elseif tokens[tonumber(value)] == "CONST" then
                index = constant_calls[#constant_calls]
                table.remove(constant_calls, #constant_calls)
            end

        elseif token == "CONST" then
            index = skip_to_end(index, tokens)

        elseif token == "CALL_CONST" then
            table.insert(constant_calls, index)
            index = constant_addresses[value]

        elseif token == "FUNCT" then
            index = index + 1
            while true do
                index = index + 1
                if tokens[index] == "DO" then
                    break
                end
            end
            index = skip_to_end(index, tokens)
        
        elseif token == "CALL_FUNCT" then
            table.insert(function_calls, index)
            index = function_addresses[value]
            local unordered_params = {}
            while true do
                index = index + 1
                
                if tokens[index] == "DO" then
                    break
                else
                    table.insert(unordered_params, tokens[index])
                end
            end
            for i = #unordered_params, 1, -1 do
                params[unordered_params[i]:sub(7)] = stack[#stack]
                table.remove(stack, #stack)
            end

        elseif token == "LET" then
            local unordered_params = {}
            while true do
                index = index + 1
                
                if tokens[index] == "DO" then
                    break
                else
                    table.insert(unordered_params, tokens[index])
                end
            end
            for i = #unordered_params, 1, -1 do
                params[unordered_params[i]:sub(7)] = stack[#stack]
                table.remove(stack, #stack)
            end
        
        elseif token == "PEEK" then
            local unordered_params = {}
            while true do
                index = index + 1
                
                if tokens[index] == "DO" then
                    break
                else
                    table.insert(unordered_params, tokens[index])
                end
            end
            for i = #unordered_params, 1, -1 do
                params[unordered_params[i]:sub(7)] = stack[#stack-#unordered_params+i]
            end

        elseif token == "EXIT" then
            if stack[#stack] and stack[#stack] ~= 0 then
                raise(stack[#stack], index)
            end
            os.exit()

        elseif token == "PRINT_TOKENS" then
            print(table.concat(tokens, " "))

        elseif token == "PUSH_PARAM" then
            table.insert(stack, params[value])

        elseif libdata[value] then
            local return_value = libdata[value]
            if type(return_value) == "function" then
                local param_count = debug.getinfo(libdata[value]).nparams -- number of args that libdata[value] takes
                if param_count > 0 then
                    return_value = libdata[value](table.unpack(stack, #stack - param_count + 1))
                    for i = 1, param_count do table.remove(stack, #stack) end
                else
                    return_value = libdata[value]()
                end
            end
            if type(return_value) == "table" then
                if not pcall(function ()
                    for i, v in ipairs(return_value) do
                        table.insert(stack, v)
                    end
                end) then
                    for i, v in pairs(return_value) do
                        table.insert(stack, v)
                    end
                end
            else
                table.insert(stack, return_value)
            end
        end
    end
end

if not arg[1] then
    while true do
        io.write("> ")
        local command = io.read()
        compile(command)
    end
end

local file_name = arg[1]
local script = assert(io.open(file_name, "rb")):read("*all")

compile(script)