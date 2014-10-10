do
    local oldRead = read
    function _G.read(...)
        local args = {...}
        local ret, timer
        parallel.waitForAny(function()
            ret = oldRead(unpack(args))
        end, function()
            while true do
                local e, param = os.pullEvent()
                if e == "key" and param == keys.d then
                    timer = os.startTimer(0)
                elseif e == "char" and param:lower() == "d" then
                    timer = nil
                elseif e == "timer" and param == timer then
                    print()
                    return
                end
            end
        end)
        return ret
    end
end



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

local function run(tEnv, shell, program, ...)
    if loadfile(program) then
        return os.run(tEnv, program, ...)
    else
        local fh = assert(fs.open(program, "r"), "No such program")
        local text = fh.readAll()
        fh.close()
        local f = assert(compile(tEnv, shell, text))
        local ok, err = f(...)
        if not ok then
            printError(err)
            return false
        else
            return err
        end
    end
end

local function runCommandNode(node, tEnv, shell)
    local cmds = {}

    local stdin = {readLine=read,close=function()end}
    local stderr = {write=write,close=function()end}
    function stderr.writeLine(...)
        if term.isColor() then
            term.setTextColor(colors.red)
        end
        for n,v in ipairs({...}) do
            stderr.write(tostring(v))
        end
        stderr.write("\n")
        term.setTextColor(colors.white)
    end
    local curNode = node

    while curNode do
        local stdout, next_stdin
        local thisNode = curNode
        if curNode.pipeOut then
            local lineBuffer = ""
            local lines = {}
            local CLOSE = {}

            stdout = {isPiped=true, writeLine=print}
            next_stdin = {}
            function stdout.write(s)
                grin.expect("string", s)
                local nLines = 0
                for c in s:gmatch(".") do
                    if c == "\n" then
                        table.insert(lines, lineBuffer)
                        lineBuffer = ""
                        nLines = nLines + 1
                    else
                        lineBuffer = lineBuffer .. c
                    end
                end

                if nLines > 0 then
                    os.queueEvent("clamshell_pipeline_buffer_update")
                end
                return nLines
            end

            function stdout.close()
                table.insert(lines, CLOSE)
                os.queueEvent("clamshell_pipeline_buffer_update")
            end

            function next_stdin.readLine()
                while not lines[1] do
                    os.pullEvent("clamshell_pipeline_buffer_update")
                end
                if lines[1] == CLOSE then
                    return
                end
                return table.remove(lines, 1)
            end

            function next_stdin.close()
            end

            curNode = curNode.pipeOut.command
        else
            stdout = {writeLine=print,write=write,close=function()end}
            curNode = nil
        end
        local program = grin.assert(shell.resolveProgram(thisNode.command[1]), "No such program", 0)
        table.insert(cmds, {
            command = coroutine.create(function()
                return run(tEnv, shell, program, unpack(thisNode.command, 2))
            end),
            program = program,
            stdin = stdin,
            stdout = stdout,
            stderr = stderr
        })
        stdin = next_stdin
    end

    local tFilters = {}
    local tEvent = {}
    while #cmds > 0 do
        for i=#cmds,1,-1 do
            local cmd = cmds[i]
            if tFilters[cmd] == nil or tFilters[cmd] == tEvent[1] or tEvent[1] == "terminate" then
                local oldPrint, oldWrite,   oldRead,    oldStdout,  oldStdin,   oldStderr,  oldPrintError
                    = print,    write,      read,       _G.stdout,  _G.stdin,   _G.stderr,  _G.printError
                _G.print = cmd.stdout.writeLine
                _G.write = cmd.stdout.write
                _G.read = cmd.stdin.readLine
                _G.stdout = cmd.stdout
                _G.stdin = cmd.stdin
                _G.stderr = cmd.stderr
                _G.printError = cmd.stderr.writeLine
                shell.pushRunningProgram(cmd.program)
                local ok, param = coroutine.resume(cmd.command, unpack(tEvent))
                shell.popRunningProgram()
                _G.print = oldPrint
                _G.write = oldWrite
                _G.read = oldRead
                _G.stdout = oldStdout
                _G.stdin = oldStdin
                _G.stderr = oldStderr
                _G.printError = oldPrintError

                if not ok then
                    printError(param)
                    return false
                else
                    tFilters[cmd] = param
                end
                if coroutine.status(cmd.command) == "dead" then
                    cmd.stdout.close()
                    table.remove(cmds, i)
                    if not param then
                        return false
                    end
                end
            end
        end
        if #cmds == 0 then
            return true
        end
        tEvent = {os.pullEventRaw()}
    end
    return true
end

local function runNode(node, tEnv, shell)
    if node.type == "root" then
        return runNode(node.chunk, tEnv, shell)
    elseif node.type == "chunk" then
        for i,v in ipairs(node) do
            if not runNode(v.command, tEnv, shell) then
                return false
            end
        end
        return true
    elseif node.type == "command" then
        return runCommandNode(node, tEnv, shell)
    end
end

function compile(tEnv, shell, sProgram)
    local ok, f = pcall(function()
        local lex = lexer(sProgram)
        local emit = emitter()
        local parse = parser(lex, emit)

        parse.parse()

        return pfunc(function()
            return runNode(emit.node, tEnv, shell)
        end)
    end)
    if not ok then
        return ok, f
    else
        return f
    end
end