local parse = grin.getPackageAPI(__package, "parse")
local pipe = grin.getPackageAPI(__package, "pipe")
local utils = grin.getPackageAPI(__package, "utils")

local runChunk, runCommand, resolveArguments
local write = write
local function p(t) write(t .. "\n") end

--- Resolves an argument, handling command and variables correctly
local function resolveArgument(arg, tEnv, shell)
    local tag = arg.tag

    if tag == "string" then
        return arg[1]
    elseif tag == "variable" then
        return shell.getenv(arg[1]) or ""
    elseif tag == "compound" then
        return table.concat(utils.map(arg, resolveArgument, tEnv, shell))
    else
        local stream, lines = pipe.linesOut()
        runCommand(arg, tEnv, shell, nil, stream, nil)
        return table.concat(lines, "\n")
    end
end

function resolveArgumentStatic(arg, shell)
    local tag = arg.tag

    if tag == "string" then
        return arg[1]
    elseif tag == "variable" then
        return shell.getenv(arg[1]) or ""
    elseif tag == "compound" then
        return table.concat(utils.map(arg, resolveArgumentStatic, tEnv, shell))
    else
        return ""
    end
end

--- Run a command with arguments
local function run(tEnv, shell, program, ...)
    if program:find("%.sh$") then
        local fh = assert(fs.open(program, "r"), "No such program")
        local text = fh.readAll()
        fh.close()

        local ok, err = compile(contents, program, false, tEnv, shell)
        if not ok then
            printError(err)
            return false
        else
            return err
        end
    else
        local tArgs = { ... }
        setmetatable( tEnv, { __index = _G } )
        local r
        local fnFile, err = loadfile( program, tEnv )
        if fnFile then
            local ok, err = pcall( function()
                fnFile( table.unpack( tArgs ) )
            end )
            if not ok then
                if err and err ~= "" then
                    printError( err )
                end
                r = false
            end
            r = true
        end
        if err and err ~= "" then
            printError( err )
        end
        r = false

        return r
    end
end

--- Execute one iteration of a command
-- This pushes locals, resumes it and pops locals again.
-- It also handles event yielding and other magic.
-- @tparam table cmd Command to Execute
-- @tparam table event The event to execute with
-- @treturn boolean Success value
local function resumeCommand(cmd, tEnv, shell, event)
    -- The coroutine must be dead
    if cmd.command == nil then
        return true
    end

    local filter, current = cmd.filter, event[1]
    if filter ~= nil and filter ~= current and current ~= "terminate" then
        return true
    end

    local oldPrint, oldWrite, oldRead, oldStdout, oldStdin, oldStderr, oldPrintError, envRead
        = print,    write,    read,    stdout,    stdin,    stderr,    printError,    tEnv.read

    if cmd.streams then
        _G.print = pipe.createPrint(cmd.stdout)
        _G.write = cmd.stdout.write
        _G.read = cmd.stdin.readLine
        tEnv.read = cmd.stdin.readLine
        _G.stdout = cmd.stdout
        _G.stdin = cmd.stdin
        _G.stderr = cmd.stderr
        _G.printError = pipe.createPrint(cmd.stderr)
    end

    if cmd.program then
        shell.pushRunningProgram(cmd.program)
    end

    local ok, param = coroutine.resume(cmd.command, unpack(event))

    if cmd.program then
        shell.popRunningProgram()
    end

    if cmd.streams then
        _G.print = oldPrint
        _G.write = oldWrite
        _G.read = oldRead
        tEnv.read = envRead
        _G.stdout = oldStdout
        _G.stdin = oldStdin
        _G.stderr = oldStderr
        _G.printError = oldPrintError
    end

    if not ok then
        printError(param)
        return false, true
    else
        cmd.filter = param
    end

    if coroutine.status(cmd.command) == "dead" then
        cmd.command = nil
        -- Propagate success
        return param, true
    end

    return true
end

-- Create a command system
local function createCommand(node, tEnv, shell, stdin, stdout, stderr)
    local tag = node.tag

    if tag == "command" then
        local cmd = utils.map(node, resolveArgument, tEnv, shell)
        local program = grin.assert(shell.resolveProgram(cmd[1]), "No such program", 0)

        return {
            command = coroutine.create(function()
                return run(tEnv, shell, program, unpack(cmd, 2))
            end),
            program = program,
            streams = true,
            stdin = stdin,
            stdout = stdout,
            stderr = stderr,
        }
    elseif tag == "pipe" then
        local firstStdout, nextStdin = pipe.pipe()
        local left =  createCommand(node[1], tEnv, shell, stdin, firstStdout, stderr)
        local right = createCommand(node[2], tEnv, shell, nextStdin, stdout, stderr)

        return {
            command = coroutine.create(function()
                local success
                local leftFinished, rightFinished = false, false
                local event = {}
                while not leftFinished and not rightFinished do

                    if not leftFinished then
                        success, leftFinished = resumeCommand(left, tEnv, shell, event)
                        if leftFinished then firstStdout.close() end

                        if not success then return false, true end
                    end

                    if not rightFinished then
                        success, rightFinished = resumeCommand(right, tEnv, shell, event)
                        if rightFinished then nextStdin.close() end

                        if not success then return false, true end
                    end

                    event = {coroutine.yield()}
                end

                return true, true
            end),
        }
    elseif tag == "write" or tag == "append" then
        local file = resolveArgument(node[2], tEnv, shell)
        utils.expect(file, "string", "file name")
        local fileOut = pipe.fileOut(shell.resolve(file), tag)

        local command = createCommand(node[1], tEnv, shell, stdin, fileOut, stderr)
        return {
            command = coroutine.create(function()
                local event = {}
                while true do
                    local success, finished = resumeCommand(command, tEnv, shell, event)
                    if finished then
                        fileOut.close()
                        return success
                    end

                    event = {coroutine.yield(command.filter)}
                end
            end),
        }
    elseif tag == "and" then
        local command = createCommand(node[1], tEnv, shell, stdin, stdout, stderr)

        return {
            command = coroutine.create(function()
                local event = {}
                local doneFirst = false
                while true do
                    local success, finished = resumeCommand(command, tEnv, shell, event)

                    if finished then
                        if doneFirst then
                            return success
                        elseif success then
                            doneFirst = true
                            command = createCommand(node[2], tEnv, shell, stdin, stdout, stderr)
                        else
                            return false
                        end
                    end

                    event = {coroutine.yield()}
                end

                return true, true
            end),
        }
    elseif tag == "or" then
        local command = createCommand(node[1], tEnv, shell, stdin, stdout, stderr)

        return {
            command = coroutine.create(function()
                local event = {}
                local doneFirst = false
                while true do
                    local success, finished = resumeCommand(command, tEnv, shell, event)

                    if finished then
                        if doneFirst then
                            return success
                        elseif success then
                            return true
                        else
                            doneFirst = true
                            command = createCommand(node[2], tEnv, shell, stdin, stdout, stderr)
                        end
                    end

                    event = {coroutine.yield()}
                end

                return true, true
            end),
        }
    else
        error("Unknown tag " .. tostring(tag))
    end
end


runCommand = function(node, tEnv, shell, stdin, stdout, stderr)
    stdin = stdin or pipe.stdIn(tEnv.read or read)
    stdout = stdout or pipe.stdOut()
    stderr = stderr or pipe.stdErr()

    local command = createCommand(node, tEnv, shell, stdin, stdout, stderr)
    local event = {}
    while true do
        local success, finished = resumeCommand(command, tEnv, shell, event)

        if finished then
            stdin.close()
            stdout.close()
            stderr.close()
            return success
        end

        event = {coroutine.yield(command.filter)}
    end
end

local function runStatement(node, tEnv, shell)
    local tag = node.tag
    if tag == "set" then
        local var = resolveArgument(node[1], tEnv, shell)
        local value = resolveArgument(node[2], tEnv, shell)

        utils.expect(var, "string", "variable")
        utils.expect(value, "string", "value")

        shell.setenv(var, value)
    elseif tag == "if" then
        if runCommand(node[1], tEnv, shell) then
            return runChunk(node[2], tEnv, shell)
        end

        for i = 3, #node do
            local sub = node[i]
            local subTag = sub.tag
            if subTag == "elseif" then
                if runCommand(sub[1], tEnv, shell) then
                    return runChunk(sub[2], tEnv, shell)
                end
            elseif subTag == "else" then
                return runChunk(sub[1], tEnv, shell)
            else
                error("Unknown tag " .. tostring(subTag))
            end
        end
    elseif tag == "while" then
        while runCommand(node[1], tEnv, shell) do
            runChunk(node[2], tEnv, shell)
        end
    elseif tag == "for" then
        local var = resolveArgument(node[1], tEnv, shell)
        utils.expect(var, "string", "variable")

        local stream, lines = pipe.linesOut()
        runCommand(node[2], tEnv, shell, nil, stream, nil)

        for _, line in ipairs(lines) do
            shell.setenv(var, line)
            runChunk(node[3], tEnv, shell)
        end
    else
        return runCommand(node, tEnv, shell)
    end
end

runChunk = function(node, tEnv, shell)
    for _, v in ipairs(node) do
        if not runStatement(v, tEnv, shell) then
            return false
        end
    end
    return true
end

function compile(text, name, fancyHandling, tEnv, shell)
    local ok, parsed = pcall(parse.parse, text, program, fancyHandling, tEnv, shell)
    if not ok then return false, parsed end

    return function() return pcall(runChunk, parsed, tEnv, shell) end
end
