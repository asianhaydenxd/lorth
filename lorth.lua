-- Lorth with IR

local file_name = "main.lorth"
local script = assert(io.open(file_name, "rb")):read("*all")

local function remove_comments(text)
    local commentless_text = {}
    for line in text:gmatch("[^\r\n]+") do
        local parts = {}
        for str in line:gmatch("[^--]+") do
            table.insert(parts, str)
        end
        table.insert(commentless_text, parts[1])
    end
    return table.concat(commentless_text, "\n")
end

local function split(text) -- Credit: Paul Kulchenko (stackoverflow)
    -- Split text using whitespace but keep single and double quotes intact
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
            table.insert(split_text, (str))
        end
    end
    if buf then
        print("Missing matching quote for "..buf)
        return nil
    end
    return split_text
end

local function raise(message, index)
    print("Exception raised: "..message.." (index "..index..")")
    os.exit()
end

local function parse(code)
    local tokens = {}
    local functs = {}
    local consts = {}
    local params = {}
    
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

        elseif token == "#" then
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
            consts[code[index]] = true
        
        elseif token == "funct" then
            push("FUNCT")
            index = index + 1
            push("FUNCT_NAME:"..code[index])
            functs[code[index]] = true
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

                elseif ctk == "DO" or ctk == "IF" or ctk == "CONST" then
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
        
        elseif functs[token] ~= nil then
            push("CALL_FUNCT:"..token)

        elseif consts[token] ~= nil then
            push("PUSH_CONST:"..token)
        
        elseif params[token] ~= nil then
            push("PUSH_PARAM:"..token)
        end
    end

    return tokens
end

local function compile(code)
    local stack = {}
    local params = {}
    local tokens = parse(split(remove_comments(code)))

    print(table.concat(tokens, " "))

    local index = 0
    while index < #tokens do
        index = index + 1

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

        elseif token == "READ" then
            print(stack[#stack])
        
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

        elseif token == "EXIT" then
            if stack[#stack] and stack[#stack] ~= 0 then
                raise(stack[#stack], index)
            end
            os.exit()

        elseif token == "LET" then
            local init_index = index -- for debugging
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
            local init_index = index -- for debugging
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

        elseif token == "PUSH_PARAM" then
            table.insert(stack, params[value])
        end
    end
end

compile(script)