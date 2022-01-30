local file_name = "main.lorth"
local script = assert(io.open(file_name, "rb")):read("*all")

local function remove_comments(text)
    local commentless_text = {}
    for line in text:gmatch("[^\r\n]+") do
        local parts = {}
        for str in line:gmatch("[^#]+") do
            table.insert(parts, str)
        end
        table.insert(commentless_text, parts[1])
    end
    return table.concat(commentless_text, "\n")
end

local function raise(message, index)
    print("Exception raised: "..message.." (index "..index..")")
    os.exit()
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
    local require_aliases = {}

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
            
            local req_script

            if not pcall(function ()
                req_script = assert(io.open(code[index]..".lorth", "rb")):read("*all")
            end) then
                raise("invalid file name for require", index)
            end

            for _, new_token in ipairs(split(req_script)) do
                table.insert(code, new_token)
            end
        end
    end

    index = 0
    while index < #code do
        index = index + 1
        local token = code[index]
        if token == "funct" then
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

        elseif token == "dup" then
            push("DUPLICATE")

        elseif token == "del" then
            push("REMOVE")
        
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
        
        elseif token == "funct" then
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
                local ctk = tokens[temp_i]

                if ctk == "END" then
                    nesting = nesting + 1

                elseif ctk == "DO" or ctk == "THEN" or ctk == "ELSE" or ctk == "CONST" then
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

            push("END")
        
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
                require_aliases[code[index]] = true
            else
                require_aliases[code[index]] = true
            end
        
        elseif functs[token] ~= nil then
            push("CALL_FUNCT:"..token)

        elseif consts[token] ~= nil then
            push("CALL_CONST:"..token)
        
        elseif params[token] ~= nil then
            push("PUSH_PARAM:"..token)

        else
            push("UNKNOWN:"..token)
        end
    end

    return tokens
end

local function compile(code)
    local stack = {}
    local params = {}
    local function_addresses = {}
    local function_calls = {}
    local constant_addresses = {}
    local constant_calls = {}
    local tokens = parse(code)

    -- print(table.concat(tokens, " "))

    -- Appending library code
    local index = 0
    while index < #tokens do
        index = index + 1

        local elements = {}
        for str in string.gmatch(tokens[index], "[^:]+") do
            table.insert(elements, str)
        end
        local token = elements[1]
        local value = elements[2]

        if token == "REQUIRE_FILE" then
            local req_script

            if not pcall(function ()
                req_script = assert(io.open(value..".lorth", "rb")):read("*all")
            end) then
                raise("invalid file name for require", index)
            end

            local new_tokens = parse(req_script)

            for _, new_token in ipairs(new_tokens) do
                local e = {}
                for str in string.gmatch(new_token, "[^:]+") do
                    table.insert(e, str)
                end
                if e[1] == "FUNCT_NAME" then
                    new_token = "FUNCT_NAME:"..value..":"..e[2]
                end
                table.insert(tokens, new_token)
            end
        end
    end

    -- Hoisting functions and constants
    index = 0
    while index < #tokens do
        index = index + 1

        local elements = {}
        for str in string.gmatch(tokens[index], "[^:]+") do
            table.insert(elements, str)
        end
        local token = elements[1]
        local value = elements[2]

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

        local elements = {}
        for str in string.gmatch(tokens[index], "[^:]+") do
            table.insert(elements, str)
        end
        local token = elements[1]
        local value = elements[2]
        
        -- Data types
        if token == "OP_PUSH_STR" then
            table.insert(stack, value)

        elseif token == "OP_PUSH_NUM" then
            table.insert(stack, tonumber(value))

        elseif token == "OP_PUSH_BOOL" then
            local toboolean = {["true"]=true, ["false"]=false}
            table.insert(stack, toboolean[value])

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

        elseif token == "DUPLICATE" then
            table.insert(stack, stack[#stack])

        elseif token == "REMOVE" then
            table.remove(stack, #stack)

        elseif token == "THEN" then
            local bool = stack[#stack]
            table.remove(stack, #stack)
            if not bool then
                local nesting = 0 -- Workaround for nesting
                while true do
                    index = index + 1
                    local ctk = tokens[index]

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
            end

        elseif token == "ELSE" then
            local nesting = 0 -- Workaround for nesting
            while true do
                index = index + 1
                local ctk = tokens[index]

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

        elseif token == "ELIF" then
            local nesting = 0 -- Workaround for nesting
            while true do
                index = index + 1
                local ctk = tokens[index]

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

        elseif token == "DO" then -- only ever called on WHILE
            local bool = stack[#stack]
            table.remove(stack, #stack)
            if not bool then
                local nesting = 0 -- Workaround for nesting
                while true do
                    index = index + 1
                    local ctk = tokens[index]

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
            end

        elseif token == "END" then
            local temp_i = index
            local nesting = 0 -- Workaround for nesting
            while true do
                temp_i = temp_i - 1
                local ctk = tokens[temp_i]

                if ctk == "END" then
                    nesting = nesting + 1

                elseif ctk == "WHILE" or ctk == "FUNCT" or ctk == "LET" or ctk == "PEEK" or ctk == "IF" or ctk == "CONST" then
                    if nesting == 0 then
                        if ctk == "WHILE" then
                            index = temp_i
                        end
                        if ctk == "FUNCT" then
                            index = function_calls[#function_calls]
                            table.remove(function_calls, #function_calls)
                        end
                        if ctk == "CONST" then
                            index = constant_calls[#constant_calls]
                            table.remove(constant_calls, #constant_calls)
                        end
                        break
                    else
                        nesting = nesting - 1
                    end
                end
            end

        elseif token == "CONST" then
            local nesting = 0 -- Workaround for nesting
            while true do
                index = index + 1
                local ctk = tokens[index]

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
            local nesting = 0 -- Workaround for nesting
            while true do
                index = index + 1
                local ctk = tokens[index]

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
        end
    end
end

compile(script)