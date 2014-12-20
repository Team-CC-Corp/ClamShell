
local multishell = multishell
local parentShell = shell
local parentTerm = term.current()
local clamPkg = grin.packageFromExecutable(parentShell.getRunningProgram())
local bish = grin.getPackageAPI(clamPkg, "bish")
local BishInterpreter = grin.getPackageAPI(clamPkg, "BishInterpreter")
local buffer = grin.getPackageAPI(clamPkg, "buffer")
local readLine = grin.getPackageAPI(clamPkg, "readLine")
local clamPath = grin.resolveInPackage(clamPkg, "clam.lua")
local clamSettingsPath = ".clam.settings"

if multishell then
    multishell.setTitle( multishell.getCurrent(), "shell" )
end

local bExit = false
local sDir = (parentShell and parentShell.dir()) or ""
local sPath = ".:/" .. grin.getFromPackage(clamPkg, "tools") .. ":"
    .. ((parentShell and parentShell.path()) or "/rom/programs")
local tAliases = (parentShell and parentShell.aliases()) or {}
tAliases.sh = "clam"
tAliases.shell = "clam"
local tProgramStack = {}

local shell = {}
local tEnv = {
    [ "shell" ] = shell,
    [ "multishell" ] = multishell,
}

-- Colors
local promptColor, textColor, bgColor
if term.isColor() then
    promptColor = colors.lightBlue
    textColor = colors.white
    bgColor = colors.black
else
    promptColor = colors.white
    textColor = colors.white
    bgColor = colors.black
end

local tCommandHistory = {}
local function writeSettings()
    local settings = fs.open(clamSettingsPath, "w")
    settings.write(textutils.serialize({
        history = tCommandHistory,
        dir = shell.dir(),
    }))
    settings.close()
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
    return sDir
end

function shell.setDir( _sDir )
    sDir = _sDir
    writeSettings()
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
        return fs.combine( sDir, _sPath )
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
                    tItems[ sFile ] = true
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

local environmentVariables
if parentShell and parentShell.getEnvironmentVariables then
    environmentVariables = parentShell.getEnvironmentVariables()
else
    environmentVariables = {}
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
    term.redirect(thisBuffer)

    -- Print the header
    term.setBackgroundColor( bgColor )
    term.setTextColor( promptColor )
    print(os.version(), " - ", shell.version())
    term.setTextColor( textColor )

    -- Run the startup program
    if parentShell == nil then
        shell.run( "/rom/startup" )
    end

    -- Load the settings file
    local settingsFile = fs.open(clamSettingsPath, "r")
    if settingsFile then
        local content = settingsFile.readAll()
        settingsFile.close()

        local settings = textutils.unserialize(content)

        if settings ~= nil then
            if settings.history then tCommandHistory = settings.history end
            if settings.dir then sDir = settings.dir end
        end
    end

    -- Read commands and execute them
    while not bExit do
        term.redirect(thisBuffer)
        thisBuffer.friendlyClear(true)

        term.setBackgroundColor(bgColor)
        term.setTextColor(promptColor)

        write( shell.dir() .. "> " )
        term.setTextColor(textColor)

        local offset = 0
        local sLine = nil
        parallel.waitForAny(
            function() sLine = readLine.read(nil, tCommandHistory) end,
            function()
                while true do
                    local changed = false
                    local e, change = os.pullEvent()
                    if e == "mouse_scroll" then
                        local newOffset = offset + change
                        if newOffset > 0 then newOffset = 0 end
                        if newOffset < -thisBuffer.totalHeight() then newOffset = -thisBuffer.totalHeight() end

                        offset = newOffset
                        changed = true
                    elseif e == "key" or e == "paste" and offset ~= 0 then
                        offset = 0
                        changed = true
                    end

                    if changed then
                        term.setCursorBlink(offset == 0)
                        thisBuffer.draw(offset)
                    end
                end
            end
        )
        if offset ~= 0 then buffer.draw() end

        if not sLine then
            return
        end

        if sLine:match("[^%s]") then -- If not blank
            for i = #tCommandHistory, 1, -1 do
                if tCommandHistory[i] == sLine then
                    table.remove(tCommandHistory, i)
                end
            end

            while #tCommandHistory > 100 do -- Limit to 100 history items
                table.remove(tCommandHistory, 1)
            end
            table.insert( tCommandHistory, sLine )
            writeSettings()
        end

        shell.run( sLine )
    end
end
