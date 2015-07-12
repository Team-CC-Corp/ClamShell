local function pfunc(f)
    return function(...)
        return pcall(f, ...)
    end
end

local tokenNameMap = {
    TK_NEWLINE = ";",
    TK_STRING = "string",
    TK_IF = "if",
    TK_ELSE = "else",
    TK_WHILE = "while",
    ["|"] = "|",
    [">"] = ">",
    [">>"] = ">>",
    ["{"] = "{",
    ["}"] = "}",
    ["="] = "="
}

local nameTokenMap = {}
for k,v in pairs(tokenNameMap) do
    nameTokenMap[v] = k
end

local symbolChars = "|>{}="
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
            else
                local s = c
                lex.nextc()
                if symbolChars:find(s, 1, true) then
                    -- symbol
                    while symbolChars:find(c, 1, true) do
                        s = s .. c
                        lex.nextc()
                    end
                    grin.assert(nameTokenMap[s], "Unknown token: " .. s, 0)
                else
                    while not (c:find("[%s;]") or symbolChars:find(c, 1, true) or c == "EOF") do
                        if c == "\\" then
                            c = lex.nextc()
                        end
                        s = s .. c
                        lex.nextc()
                    end
                end

                if nameTokenMap[s] then
                    return nameTokenMap[s], s
                end

                return "TK_STRING", s
            end
        end
    end

    function lex.next()
        local token, data = lex._next()
        lex.t = lex.lookahead
        lex.lookahead = {token=token, data=data}
    end

    lex.nextc()
    lex.next() -- fill the first lookahead
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
        error(msg .. " near " .. lex.t.data)
    end

    function parse.check(token)
        parse.assert(parse.test(token), "Expected "..(tokenNameMap[token] or token), 0)
    end

    function parse.checkNext(token)
        parse.check(token)
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

    function parse.testLookahead(token)
        return lex.lookahead.token == token
    end

    function parse.checkString()
        parse.check("TK_STRING")
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

        while not parse.chunkFollow() do
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

    function parse.chunkFollow()
        return parse.test("EOF") or parse.test("}")
    end

    function parse.statement()
        -- statement -> command
        if parse.test("TK_STRING") then
            if parse.testLookahead("=") then
                parse.assignment()
            else
                parse.command()
            end
        elseif parse.test("TK_IF") then
            parse.ifStat()
        elseif parse.test("TK_WHILE") then
            parse.whileStat()
        end
    end

    function parse.command()
        -- command -> TK_STRING {commandArgs} {pipe}
        local cmd = parse.checkString()
        emit.beginCommand(cmd)

        if parse.test("TK_STRING") then
            parse.commandArgs()
        end

        if parse.test("|") or parse.test(">") or parse.test(">>") then
            --pipe
            parse.pipe()
        end

        emit.finishCommand()
    end

    function parse.pipe()
        -- pipe -> PIPE command | FILEPIPE fileName
        if parse.testNext("|") then
            emit.beginPipeOut()
            parse.command()
            emit.finishPipeOut()
        elseif parse.testNext(">") then
            emit.filePipeOut(parse.checkString())
        elseif parse.testNext(">>") then
            emit.filePipeOut(parse.checkString(), true)
        end
    end

    function parse.commandArgs()
        -- commandArgs -> TK_STRING {commandArgs}
        local arg = parse.checkString()
        emit.addArgument(arg)
        if parse.test("TK_STRING") then
            parse.commandArgs()
        end
    end

    function parse.ifStat()
        -- ifStat -> TK_IF command '{' chunk '}' [elseStat]
        parse.checkNext("TK_IF") -- skip if
        emit.beginIf()
        parse.command()
        parse.checkNext("{")
        parse.chunk()
        parse.checkNext("}")
        if parse.test("TK_ELSE") then
            parse.elseStat()
        end
        emit.finishIf()
    end

    function parse.elseStat()
        -- elseStat -> TK_ELSE (ifStat | '{' chunk '}')
        parse.checkNext("TK_ELSE")
        emit.beginElse()

        if parse.test("TK_IF") then
            parse.ifStat()
        else
            parse.checkNext("{")
            parse.chunk()
            parse.checkNext("}")
        end

        emit.finishElse()
    end

    function parse.whileStat()
        parse.checkNext("TK_WHILE")
        emit.beginWhile()
        parse.command()
        parse.checkNext("{")
        parse.chunk()
        parse.checkNext("}")
        emit.finishWhile()
    end

    function parse.assignment()
        emit.beginAssignment(parse.checkString())
        parse.checkNext("=")
        emit.assignmentValue(parse.checkString())
        emit.finishAssignment()
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
        emit.node.statement = command
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

    -- File pipe out
    function emit.filePipeOut(fileName, append)
        emit.node.filePipeOut = fileName
        emit.node.filePipeOutAppend = append
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

    -- If control
    function emit.beginIf()
        emit.pushNode()
        emit.node.type = "if_stat"
    end

    function emit.finishIf()
        local ifStat = emit.popNode()
        emit.node.statement = ifStat
    end

    function emit.beginElse()
        emit.pushNode()
        emit.node.type = "else_stat"
    end

    function emit.finishElse()
        local elseStat = emit.popNode()
        emit.node.elseStat = elseStat
    end

    -- While control
    function emit.beginWhile()
        emit.pushNode()
        emit.node.type = "while_stat"
    end

    function emit.finishWhile()
        local whileStat = emit.popNode()
        emit.node.statement = whileStat
    end

    -- Assignment
    function emit.beginAssignment(name)
        emit.pushNode()
        emit.node.type = "assignment"
        emit.node.name = name
    end

    function emit.assignmentValue(val)
        emit.node.value = val
    end

    function emit.finishAssignment()
        local assignment = emit.popNode()
        emit.node.statement = assignment
    end

    return emit
end

function parse(sProgram)
    local lex = lexer(sProgram)
    local emit = emitter()
    local parse = parser(lex, emit)

    parse.parse()

    return emit.node
end

function compile(tEnv, shell, sProgram)
    local ok, f = pcall(function()
        local node = parse(sProgram)

        return pfunc(function()
            local bi = grin.getPackageAPI(__package, "BishInterpreter")
            return bi.runNode(node, tEnv, shell)
        end)
    end)
    if not ok then
        return ok, f
    else
        return f
    end
end
