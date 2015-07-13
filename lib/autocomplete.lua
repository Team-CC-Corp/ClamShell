-- Setup completion functions
local function completeMultipleChoice(sText, tOptions)
    local tResults = {}
    for n=1,#tOptions do
        local sOption = tOptions[n]
        if #sOption + (bAddSpaces and 1 or 0) > #sText and string.sub(sOption, 1, #sText) == sText then
            table.insert(tResults, string.sub(sOption, #sText + 1))
        end
    end
    return tResults
end
local function completeFile(shell, nIndex, sText, tPreviousText)
    return fs.complete(sText, shell.dir(), true, true)
end
local function completeDir(shell, nIndex, sText, tPreviousText)
    return fs.complete(sText, shell.dir(), false, true)
end


local function completeGlep(shell, nIndex, sText, tPreviousText)
    if nIndex > 1 then
        return completeFile(shell, nIndex, sText, tPreviousText)
    end
end

local function completeTest(shell, nIndex, sText, tPreviousText)
    local r = completeMultipleChoice(sText, {'-d', '-e', 'f'}) or {}
    for _, v in pairs(completeFile(shell, nIndex, sText, tPreviousText) or {}) do
            table.insert(r, v)
    end
    return r
end

local function completeXargs(shell, nIndex, sText, tPreviousText)
    if nIndex == 1 then
        return shell.completeProgram(sText)
    else
        local sProgram = shell.resolveProgram(tPreviousText[2])
        print(textutils.serialize(tPreviousText))
        local sPart = tPreviousText[nIndex] or ""
        table.remove(tPreviousText, 1)

        local tInfo = shell.getCompletionInfo()[sProgram]
        if tInfo then
            return tInfo.fnComplete( shell, nIndex - 1, sText, tPreviousText)
        end
    end
end

function setup(root, shell)
    shell.setCompletionFunction(root .. '/cat.lua', completeFile)
    shell.setCompletionFunction(root .. '/glep.lua', completeGlep)
    shell.setCompletionFunction(root .. '/list.lua', completeDir)
    shell.setCompletionFunction(root .. '/test.lua', completeTest)
    shell.setCompletionFunction(root .. '/xargs.lua', completeXargs)
end
