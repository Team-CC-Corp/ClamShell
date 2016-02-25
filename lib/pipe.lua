local select, tostring, term, type = select, tostring, term, type
local queueEvent, pullEvent = os.queueEvent, os.pullEvent
local grin = grin
local insert, remove = table.insert, table.remove

local write, print = write, print

local function doWrite(write, ...)
    local sum = 0
    local n = select('#', ...)
    for i = 1, n do
        if i > 1 then
            sum = sum + write("\t")
        end

        sum = sum + write(tostring(select(n, ...)))
    end

    return sum
end

local function doPrint(write, ...)
    return doWrite(write, ...) +  write("\n")
end

--- Basic stdin: just reads from terminal
function stdIn(read)
    return {readLine = read, close = function() end}
end

--- Basic stdout: just writes to terminal
function stdOut()
    return {write = write, writeLine = print, flush = function() end, close = function() end}
end

--- Stderr: coloured stdout. Nothing fancy
function stdErr()
    local stderr = stdOut()

    function stderr.write(x)
        if type(x) ~= "string" then error("Expected string", 2) end

        local old = term.getTextColor()
        if term.isColor() then term.setTextColor(colors.red) end
        write(tostring(x))
        if term.isColor() then term.setTextColor(old) end
    end

    function stderr.writeLine(...)
        local old = term.getTextColor()
        if term.isColor() then term.setTextColor(colors.red) end
        local n = doPrint(write, ...)
        if term.isColor() then term.setTextColor(old) end

        return n
    end
end

--- An output that redirects to a file
function fileOut(path, mode)
    if mode == "append" then
        mode = "a"
    elseif mode == "write" then
        mode = "w"
    end

    local stdout = fs.open(fname, writeType)
    if not stdout then error("File could not be opened: " .. fname, 0) end

    local oldWriteLine = stdout.writeLine
    stdout.writeLine = function(...)
        doWrite(stdout.write, ...)
        oldWriteLine("")
        return 1
    end

    stdout.isPiped = true

    return stdout
end

--- Simply stores a list of lines
function linesOut()
    local lineBuffer = ""
    local lines = {}

    local stdout = {isPiped = true, writeLine = print}
    function stdout.write(s)
        grin.expect("string", s)
        local nLines = 0

        local pos, len = 1, #s
        while pos <= len do
            local newPos = s:find("\n")

            if newPos then
                insert(lines, lineBuffer .. s:sub(pos, newPos - 1))
                lineBuffer = ""
                nLines = nLines + 1
            else
                newPos = len
                lineBuffer = lineBuffer .. s:sub(pos, newPos)
            end

            pos = newPos + 1
        end

        return nLines
    end

    function stdout.writeLine(...)
        return doPrint(stdout.write, ...)
    end

    function stdout.flush() end

    function stdout.close()
        if lineBuffer ~= "" then
            insert(lines, lineBuffer)
            lineBuffer = ""
        end
    end

    return stdout, lines
end

--- A command pipe
local function pipe()
    local lineBuffer = ""
    local lines = {}
    local CLOSE = {}

    local stdout = {isPiped = true}
    local next_stdin = { isPiped = true }
    function stdout.write(s)
        grin.expect("string", s)
        local nLines = 0

        local pos, len = 1, #s
        while pos <= len do
            local newPos = s:find("\n")

            if newPos then
                insert(lines, lineBuffer .. s:sub(pos, newPos - 1))
                lineBuffer = ""
                nLines = nLines + 1
            else
                newPos = len
                lineBuffer = lineBuffer .. s:sub(pos, newPos)
            end

            pos = newPos + 1
        end

        if nLines > 0 then
            queueEvent("clamshell_pipeline_buffer_update")
        end
        return nLines
    end

    function stdout.writeLine(...)
        return doPrint(stdout.write, ...)
    end

    function stdout.flush() end

    function stdout.close()
        if lineBuffer ~= "" then
            insert(lines, lineBuffer)
            lineBuffer = ""
        end
        insert(lines, CLOSE)
        queueEvent("clamshell_pipeline_buffer_update")
    end

    function next_stdin.readLine()
        while not lines[1] do
            pullEvent("clamshell_pipeline_buffer_update")
        end
        if lines[1] == CLOSE then
            return
        end
        return remove(lines, 1)
    end

    function next_stdin.close()
    end

    return stdout, next_stdin
end
