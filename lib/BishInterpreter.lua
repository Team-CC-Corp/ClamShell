do
    local oldRead = read
    function _G.read(rep, history)
        local ret, timer
        parallel.waitForAny(function()
            ret = oldRead(rep, history)
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



local function run(tEnv, shell, program, ...)
    if loadfile(program) then
        return os.run(tEnv, program, ...)
    else
        local bish = grin.getPackageAPI(__package, "bish")
        local fh = assert(fs.open(program, "r"), "No such program")
        local text = fh.readAll()
        fh.close()
        local f = assert(bish.compile(tEnv, shell, text))
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

function runNode(node, tEnv, shell)
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