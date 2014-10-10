local function pfunc(f)
    return function(...)
        return pcall(f, ...)
    end
end

local function lexer(sProgram)
    local lex = {}
    lex.t = {}
    local cursor = 1
    local c

    function lex.nextc()
        c = sProgram:sub(cursor, cursor)
        if c == "" then
            c = "EOF"
        else
            cursor = cursor + 1
        end
        return c
    end

    function lex._next()
        while true do
            if c == "\n" or c == ";" then
                lex.nextc()
                return "TK_NEWLINE", ";"
            elseif c:find("%s") then
                lex.nextc()
            elseif c == "EOF" then
                return "EOF", "EOF"
            elseif c == "\"" then
                local s = ""
                lex.nextc()
                while c ~= "\"" do
                    if c == "\n" or c == "EOF" then
                        error("Unfinished string", 0)
                    end
                    if c == "\\" then
                        lex.nextc()
                        if c ~= "\"" then
                            s = s .. "\\"
                        end
                    end
                    s = s .. c
                    lex.nextc()
                end
                lex.nextc() -- skip trailing quote
                return "TK_STRING", s
            elseif c == "|" then
                lex.nextc()
                return "|", "|"
            else
                local s = c
                lex.nextc()
                while not (c:find("[%s;|]") or c == "EOF") do
                    if c == "\\" then
                        c = lex.nextc()
                    end
                    s = s .. c
                    lex.nextc()
                end
                return "TK_STRING", s
            end
        end
    end

    function lex.next()
        local token, data = lex._next()
        lex.t = {token=token, data=data}
    end

    lex.nextc()
    return lex
end

local function parser(lex, emit)
    local parse = {}

    function parse.assert(cond, msg, level)
        if cond then return cond end
        if type(level) ~= "number" then
            level = 2
        elseif level <= 0 then
            level = 0
        else
            level = level + 1
        end
        error(msg .. " near " .. lex.t.data, level)
    end

    function parse.checkNext(token)
        parse.assert(parse.test(token), "Unexpected token", 0)
        lex.next()
    end

    function parse.test(token)
        return lex.t.token == token
    end

    function parse.testNext(token)
        if parse.test(token) then
            lex.next()
            return true
        else
            return false
        end
    end

    function parse.checkString()
        parse.assert(parse.test("TK_STRING"), "Expected string", 0)
        local s = lex.t.data
        lex.next()
        return s
    end

    function parse.parse()
        lex.next()
        parse.chunk()
    end
    
    function parse.chunk()
        emit.beginChunk()

        while parse.testNext("TK_NEWLINE") do
        end

        while not parse.test("EOF") do
            emit.beginArrayElement()
            parse.statement()
            emit.finishArrayElement()
            if not parse.testNext("EOF") then
                parse.checkNext("TK_NEWLINE")
            end

            while parse.testNext("TK_NEWLINE") do
            end
        end

        emit.finishChunk()
    end

    function parse.statement()
        -- statement -> command
        if parse.test("TK_STRING") then
            parse.command()
        end
    end

    function parse.command()
        -- command -> TK_STRING {commandArgs} {|command}
        local cmd = parse.checkString()
        emit.beginCommand(cmd)

        if parse.test("TK_STRING") then
            parse.commandArgs()
        end

        if parse.testNext("|") then
            --pipe
            emit.beginPipeOut()
            parse.command()
            emit.finishPipeOut()
        end

        emit.finishCommand()
    end

    function parse.commandArgs()
        -- commandArgs -> TK_STRING {commandArgs}
        local arg = parse.checkString()
        emit.addArgument(arg)
        if parse.test("TK_STRING") then
            parse.commandArgs()
        end
    end

    return parse
end

local function emitter()
    local emit = {
        nodeStack = {},
        node = {type="root"}
    }

    function emit.pushNode()
        table.insert(emit.nodeStack, emit.node)
        emit.node = {}
    end

    function emit.popNode()
        local currentNode = emit.node
        emit.node = table.remove(emit.nodeStack)
        return currentNode
    end

    -- A chunk is an array of commands
    function emit.beginChunk()
        emit.pushNode()
        emit.node.type = "chunk"
    end

    function emit.finishChunk()
        local chunk = emit.popNode()
        emit.node.chunk = chunk
    end

    -- A command is an array of strings
    function emit.beginCommand(cmd)
        emit.pushNode()
        emit.node.type = "command"
        emit.node.command = {cmd}
    end

    function emit.addArgument(arg)
        table.insert(emit.node.command, arg)
    end

    function emit.finishCommand()
        local command = emit.popNode()
        emit.node.command = command
    end

    -- Pipe out
    function emit.beginPipeOut()
        emit.pushNode()
        emit.node.type = "pipe_out"
    end

    function emit.finishPipeOut()
        local outCommand = emit.popNode()
        emit.node.pipeOut  = outCommand
    end

    -- Array elements
    function emit.beginArrayElement()
        emit.pushNode()
        emit.node.type = "array_element"
    end

    function emit.finishArrayElement()
        local elem = emit.popNode()
        table.insert(emit.node, elem)
    end

    return emit
end

function compile(tEnv, shell, sProgram)
    local ok, f = pcall(function()
        local lex = lexer(sProgram)
        local emit = emitter()
        local parse = parser(lex, emit)

        parse.parse()

        return pfunc(function()
            local bi = grin.getPackageAPI(__package, "BishInterpreter")
            return bi.runNode(emit.node, tEnv, shell)
        end)
    end)
    if not ok then
        return ok, f
    else
        return f
    end
end