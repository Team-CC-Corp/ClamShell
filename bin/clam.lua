local multishell = multishell
local parentShell = shell
local parentTerm = term.current()
local clamPkg = grin.packageFromExecutable(parentShell.getRunningProgram())
local bish = grin.getPackageAPI(clamPkg, "bish")
local BishInterpreter = grin.getPackageAPI(clamPkg, "BishInterpreter")
local buffer = grin.getPackageAPI(clamPkg, "buffer")
local read = grin.getPackageAPI(clamPkg, "readLine").read
local clamPath = grin.resolveInPackage(clamPkg, "clam.lua")

if clamPath:sub(1, 1) ~= "/" then clamPath = "/" .. clamPath end

if multishell then
    multishell.setTitle(multishell.getCurrent(), "shell")
end

local bExit = false
local sPath = ".:/" .. grin.getFromPackage(clamPkg, "tools") .. ":"
    .. ((parentShell and parentShell.path()) or "/rom/programs")
local tAliases = (parentShell and parentShell.aliases()) or {}
tAliases.sh = "clam"
tAliases.shell = "clam"

local environmentVariables = (parentShell and parentShell.getEnvironmentVariables) and parentShell.getEnvironmentVariables() or {}
local tCompletionInfo = (parentShell and parentShell.getCompletionInfo()) or {}
local tProgramStack = {}

local shell = {}
local tEnv = {
    shell = shell,
    multishell = multishell,
    read = read
}

-- Settings handling
local clamSettingsPath = ".clam.settings"
local clamSessionPath = ".clam.session"

local function writeSettings(path, table)
    if not table then return end

    local success, serialize = pcall(textutils.serialize, table)
    if not success then return end

    local file = fs.open(path, "w")
    if not file then return end
    file.write(serialize)
    file.close()
end

local function readSettings(path)
    local file = fs.open(path, "r")
    if not file then return end
    local contents = file.readAll()
    file.close()

    local result = textutils.unserialize(contents)
    if not result or type(result) ~= "table" then return end

    return result
end

-- Load settings
local clamSettings, session
do
    local colorProperties = { "promptColor", "textColor", "bgColor" }
    local defaults = {
        promptColor = "white",
        textColor = "white",
        bgColor = "black",

        aliases = {},
        env = {},

        pageScroll = 15,

        maxScrollback = 100,
        maxHistory = 100,
    }

    if term.isColor() then
        defaults.promptColor = "lightBlue"
    end

    clamSettings = readSettings(clamSettingsPath) or {}
    for k, v in pairs(defaults) do
        local value = clamSettings[k] or v
        if settings and type(value) ~= "table" then
            local value = settings.get("clam." .. k, value)
            settings.set("clam." .. k, value)
        end
        clamSettings[k] = value
    end
    session = readSettings(clamSessionPath) or {}

    -- Set session vars
    if type(session.dir) ~= "string" then
        session.dir = (parentShell and parentShell.dir and parentShell.dir()) or ""
    end

    if type(session.history) ~= "table" then
        session.history = {}
    end

    -- Colors
    local validColors = {}
    for i = 0, 16 do validColors[2^i] = true end

    local validator
    if term.isColor() then
        validator = function(c) return validColors[c] end
    else
        validator = function(c) return color == colors.black or color == colors.white end
    end

    for _, name in pairs(colorProperties) do
        local color = clamSettings[name]
        if type(color) == "string" then
            color = colors[color] or colours[color]
        end
        if not color or not validator(color) then
            color = defaults[name]
        end
        clamSettings[name] = color
    end

    -- Aliases
    local aliases = clamSettings.aliases
    if type(aliases) == "table" then
        for name, value in pairs(aliases) do
            if type(name) == "string" and type(value) == "string" then
                tAliases[name] = value
            end
        end
    end

    -- Environment
    local variables = clamSettings.env
    if type(variables) == "table" then
        for name, value in pairs(variables) do
            if type(name) == "string" and type(value) == "string" then
                environmentVariables[name] = value
            end
        end
    end

    -- Other settings
    session.maxHistory = tonumber(session.maxHistory)
    session.maxScrollback = tonumber(session.maxScrollback)
end

-- Install shell API
function shell.run( ... )
    local f, err = bish.compile(tEnv, shell, table.concat({...}, " "))
    if f then
        local ok, err = f()
        if not ok then
            printError(err)
            return false
        else
            return true
        end
    else
        printError(err)
        return false
    end
end

function shell.exit()
    bExit = true
end

function shell.dir()
    return session.dir
end

function shell.setDir( _sDir )
    session.dir = _sDir
    writeSettings(clamSessionPath, session)
end

function shell.path()
    return sPath
end

function shell.setPath( _sPath )
    sPath = _sPath
end

function shell.resolve( _sPath )
    local sStartChar = string.sub( _sPath, 1, 1 )
    if sStartChar == "/" or sStartChar == "\\" then
        return fs.combine( "", _sPath )
    else
        return fs.combine( session.dir, _sPath )
    end
end

function shell.resolveProgram( _sCommand )
    -- Substitute aliases firsts
    if tAliases[ _sCommand ] ~= nil then
        _sCommand = tAliases[ _sCommand ]
    end

    -- If the path is a global path, use it directly
    local sStartChar = string.sub( _sCommand, 1, 1 )
    if sStartChar == "/" or sStartChar == "\\" then
        local sPath = fs.combine( "", _sCommand )
        if fs.exists(sPath .. ".lua") and not fs.isDir(sPath .. ".lua") then
            return sPath .. ".lua"
        elseif fs.exists( sPath ) and not fs.isDir( sPath ) then
            return sPath
        end
        return nil
    end

    -- Otherwise, look on the path variable
    for sPath in string.gmatch(sPath, "[^:]+") do
        sPath = fs.combine( shell.resolve( sPath ), _sCommand )
        if fs.exists(sPath .. ".lua") and not fs.isDir(sPath .. ".lua") then
            return sPath .. ".lua"
        elseif fs.exists( sPath ) and not fs.isDir( sPath ) then
            return sPath
        end
    end

    -- Not found
    return nil
end

function shell.programs( _bIncludeHidden )
    local tItems = {}

    -- Add programs from the path
    for sPath in string.gmatch(sPath, "[^:]+") do
        sPath = shell.resolve( sPath )
        if fs.isDir( sPath ) then
            local tList = fs.list( sPath )
            for n,sFile in pairs( tList ) do
                if not fs.isDir( fs.combine( sPath, sFile ) ) and
                   (_bIncludeHidden or string.sub( sFile, 1, 1 ) ~= ".") then
                    tItems[ sFile:gsub("%.lua$", "") ] = true
                end
            end
        end
    end

    -- Sort and return
    local tItemList = {}
    for sItem, b in pairs( tItems ) do
        table.insert( tItemList, sItem )
    end
    table.sort( tItemList )
    return tItemList
end

local function completeProgram( sLine )
    if #sLine > 0 and string.sub( sLine, 1, 1 ) == "/" then
        -- Add programs from the root
        return fs.complete( sLine, "", true, false )
    else
        local tResults = fs.complete( sLine, session.dir, true, false )
        local tSeen = {}

        -- Add aliases
        for sAlias, sCommand in pairs( tAliases ) do
            if #sAlias > #sLine and string.sub( sAlias, 1, #sLine ) == sLine then
                local sResult = string.sub( sAlias, #sLine + 1 )
                if not tSeen[ sResult ] then
                    table.insert( tResults, sResult )
                    tSeen[ sResult ] = true
                end
            end
        end

        -- Add programs from the path
        local tPrograms = shell.programs()
        for n=1,#tPrograms do
            local sProgram = tPrograms[n]
            if #sProgram > #sLine and string.sub( sProgram, 1, #sLine ) == sLine then
                local sResult = string.sub( sProgram, #sLine + 1 )
                if not tSeen[ sResult ] then
                    table.insert( tResults, sResult )
                    tSeen[ sResult ] = true
                end
            end
        end

        -- Sort and return
        table.sort( tResults )
        return tResults
    end
end

local function completeProgramArgument( sProgram, nArgument, sPart, tPreviousParts )
    local tInfo = tCompletionInfo[ sProgram ]
    if tInfo then
        return tInfo.fnComplete( shell, nArgument, sPart, tPreviousParts )
    end
    return nil
end

local function findCommand(node)
    local type = node.type

    if type == "command" then
        if node.pipeOut then
            return findCommand(node.pipeOut)
        elseif node.filePipeOut then
            return true, node.filePipeOut
        else
            return false, node.command
        end
    elseif type == "array_element" then
        return findCommand(node.statement)
    elseif type == "chunk" then
        if #node == 0 then return nil end
        return findCommand(node[#node])
    elseif type == "root" then
        return findCommand(node.chunk)
    elseif type == "pipe_out" then
        return findCommand(node.statement)
    else
        print(type)
    end
end

function shell.complete( sLine )
    if #sLine > 0 then
        local success, root = pcall(bish.parse, sLine)
        if not success then return nil end

        local isFile, tWords = findCommand(root)
        if not tWords then return nil end

        if isFile then
            return fs.complete(tWords, session.dir)
        end

        local nIndex = #tWords
        if string.sub( sLine, #sLine, #sLine ) == " " then
            nIndex = nIndex + 1
        end
        if nIndex == 1 then
            local sBit = tWords[1] or ""
            local sPath = shell.resolveProgram( sBit )
            if tCompletionInfo[ sPath ] then
                return { " " }
            else
                local tResults = completeProgram( sBit )
                for n=1,#tResults do
                    local sResult = tResults[n]
                    local sPath = shell.resolveProgram( sBit .. sResult )
                    if tCompletionInfo[ sPath ] then
                        tResults[n] = sResult .. " "
                    end
                end
                return tResults
            end

        elseif nIndex > 1 then
            local sPath = shell.resolveProgram( tWords[1] )
            local sPart = tWords[nIndex] or ""
            local tPreviousParts = tWords
            tPreviousParts[nIndex] = nil
            return completeProgramArgument( sPath , nIndex - 1, sPart, tPreviousParts )

        end
    end
	return nil
end

function shell.completeProgram( sProgram )
    return completeProgram( sProgram )
end

function shell.setCompletionFunction( sProgram, fnComplete )
    tCompletionInfo[ sProgram ] = {
        fnComplete = fnComplete
    }
end

function shell.getCompletionInfo()
    return tCompletionInfo
end

function shell.pushRunningProgram(prg)
    table.insert(tProgramStack, prg)
end

function shell.popRunningProgram()
    return table.remove(tProgramStack)
end

function shell.getRunningProgram()
    if #tProgramStack > 0 then
        return tProgramStack[#tProgramStack]
    end
end

function shell.setAlias( _sCommand, _sProgram )
    tAliases[ _sCommand ] = _sProgram
end

function shell.clearAlias( _sCommand )
    tAliases[ _sCommand ] = nil
end

function shell.aliases()
    -- Add aliases
    local tCopy = {}
    for sAlias, sCommand in pairs( tAliases ) do
        tCopy[sAlias] = sCommand
    end
    return tCopy
end

function shell.version()
    return "ClamShell 1.0"
end

function shell.getEnvironmentVariables()
    local copy = {}
    for k,v in pairs(environmentVariables) do
        copy[k] = v
    end
    return copy
end

function shell.getenv(name)
    grin.expect("string", name)
    return environmentVariables[name]
end

function shell.setenv(name, value)
    grin.expect("string", name)
    grin.expect("string", value)
    environmentVariables[name] = value
end

if multishell then
    function shell.openTab( ... )
        return multishell.launch(tEnv, "rom/programs/shell", clamPath, table.concat({...}," "))
    end

    function shell.switchTab( nID )
        multishell.setFocus( nID )
    end
end

grin.getPackageAPI(clamPkg, "autocomplete").setup(grin.getFromPackage(clamPkg, "tools"), shell)

local tArgs = { ... }
if #tArgs > 0 then
    -- "shell x y z"
    -- Run the program specified on the commandline
    shell.run( ... )

else
    -- "shell"
    -- Buffer
    term.clear()
    term.setCursorPos(1, 1)

    local thisBuffer = buffer.new(parentTerm)
    thisBuffer.bubble(true)
    thisBuffer.maxScrollback(clamSettings.maxScrollback)
    term.redirect(thisBuffer)

    -- Print the header
    term.setBackgroundColor(clamSettings.bgColor)
    term.setTextColor(clamSettings.promptColor)
    print(os.version(), " - ", shell.version())
    term.setTextColor(clamSettings.textColor)

    local tCommandHistory = session.history
    local maxHistory = clamSettings.maxHistory

    local function redirectRead(char, history, complete)
        local offset = 0
        local line = nil
        parallel.waitForAny(
            function() line = read(char, history, complete) end,
            function()
                while true do
                    local change = 0
                    local e, eventArg = os.pullEvent()
                    if e == "mouse_scroll" then
                        change = eventArg
                    elseif e == "key" and eventArg == keys.pageDown then
                        change = clamSettings.pageScroll
                    elseif e == "key" and eventArg == keys.pageUp then
                        change = -clamSettings.pageScroll
                    elseif e == "key" or e == "paste" then
                        -- Reset offset if another key is pressed
                        change = -offset
                    elseif e == "term_resize" then
                        thisBuffer.updateSize()
                        thisBuffer.draw(offset)
                    end

                    if change ~= 0 then
                        offset = offset + change
                        if offset > 0 then offset = 0 end
                        if offset < -thisBuffer.totalHeight() then offset = -thisBuffer.totalHeight() end

                        term.setCursorBlink(offset == 0)
                        thisBuffer.draw(offset)
                    end
                end
            end
        )
        if offset ~= 0 then thisBuffer.draw() end

        return line
    end

    tEnv.read = redirectRead

    -- Read commands and execute them
    while not bExit do
        term.redirect(thisBuffer)
        thisBuffer.friendlyClear(true)

        term.setBackgroundColor(clamSettings.bgColor)
        term.setTextColor(clamSettings.promptColor)

        write( shell.dir() .. "> " )
        term.setTextColor(clamSettings.textColor)

        local complete
        if not settings or settings.get("shell.autocomplete") then
            complete = shell.complete
        end
        local sLine = redirectRead(nil, tCommandHistory, complete)

        if not sLine then
            return
        end

        if sLine:match("[^%s]") then -- If not blank
            for i = #tCommandHistory, 1, -1 do
                if tCommandHistory[i] == sLine then
                    table.remove(tCommandHistory, i)
                end
            end

            if maxHistory > -1 then
                while #tCommandHistory > maxHistory do -- Limit to n number of history items
                    table.remove(tCommandHistory, 1)
                end
            end
            table.insert(tCommandHistory, sLine)
            writeSettings(clamSessionPath, session)
        end

        parallel.waitForAny(function () shell.run( sLine ) end, function()
            while true do
                os.pullEvent("term_resize")
                thisBuffer.updateSize()
                thisBuffer.draw(offset)
            end
        end)
    end
end
