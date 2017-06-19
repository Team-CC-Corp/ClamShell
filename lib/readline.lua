function read(replaceChar, history, completeFunction, default)
    term.setCursorBlink(true)

    local line
    if type(default) == "string" then
        line = default
    else
        line = ""
    end
    local historyPos
    local pos = #line
    local downKeys = {}
    local modifier = 0
    if replaceChar then
        replaceChar = replaceChar:sub(1, 1)
    end

    local completions, currentCompletion
    local function recomplete()
        if completeFunction and pos == #line then
            completions = completeFunction(line)
            if completions and #completions > 0 then
                currentCompletion = 1
            else
                currentCompletion = nil
            end
        else
            completions = nil
            currentCompletion = nil
        end
    end

    local function uncomplete()
        completions = nil
        currentCompletion = nil
    end

    local function updateModifier()
        modifier = 0
        if downKeys[keys.leftCtrl] or downKeys[keys.rightCtrl] then modifier = modifier + 1 end
        if downKeys[keys.leftAlt] or downKeys[keys.rightAlt] then modifier = modifier + 2 end
    end

    local function nextWord()
        -- Attempt to find the position of the next word
        local offset = line:find("%w%W", pos + 1)
        if offset then return offset else return #line end
    end

    local function prevWord()
        -- Attempt to find the position of the previous word
        local offset = 1
        while offset <= #line do
            local nNext = line:find("%W%w", offset)
            if nNext and nNext < pos then
                offset = nNext + 1
            else
                return offset - 1
            end
        end
    end

    local w, h = term.getSize()
    local sx = term.getCursorPos()

    local function redraw(clear)
        local scroll = 0
        if sx + pos >= w then
            scroll = (sx + pos) - w
        end

        local cx,cy = term.getCursorPos()
        term.setCursorPos(sx, cy)
        local replace = (clear and " ") or replaceChar
        if replace then
            term.write(replace:rep(math.max(#line - scroll, 0)))
        else
            term.write(line:sub(scroll + 1))
        end

        if currentCompletion then
            local sCompletion = completions[currentCompletion]
            local oldText
            if not clear then
                oldText = term.getTextColor()
                term.setTextColor(colors.gray)
            end
            if replace then
                term.write(replace:rep(#sCompletion))
            else
                term.write(sCompletion)
            end
            if not clear then
                term.setTextColor(oldText)
            end
        end

        term.setCursorPos(sx + pos - scroll, cy)
    end

    local function clear()
        redraw(true)
    end

    recomplete()
    redraw()

    local function acceptCompletion()
        if currentCompletion then
            -- Clear
            clear()

            -- Find the common prefix of all the other suggestions which start with the same letter as the current one
            local completion = completions[currentCompletion]
            local firstLetter = completion:sub(1, 1)
            local commonPrefix = completion
            for n=1, #completions do
                local result = completions[n]
                if n ~= currentCompletion and result:find(firstLetter, 1, true) == 1 then
                    while #commonPrefix > 1 do
                        if result:find(commonPrefix, 1, true) == 1 then
                            break
                        else
                            commonPrefix = commonPrefix:sub(1, #commonPrefix - 1)
                        end
                    end
                end
            end

            -- Append this string
            line = line .. commonPrefix
            pos = #line

            -- Redraw
            recomplete()
            redraw()
        end
    end
    while true do
        local event, param = os.pullEvent()
        if modifier == 0 and event == "char" then
            -- Typed key
            clear()
            line = string.sub(line, 1, pos) .. param .. string.sub(line, pos + 1)
            pos = pos + 1
            recomplete()
            redraw()

        elseif event == "paste" then
            -- Pasted text
            clear()
            line = string.sub(line, 1, pos) .. param .. string.sub(line, pos + 1)
            pos = pos + #param
            recomplete()
            redraw()

        elseif event == "key" then
            if param == keys.leftCtrl or param == keys.rightCtrl or param == keys.leftAlt or param == keys.rightAlt then
                downKeys[param] = true
                updateModifier()
            elseif param == keys.enter then
                -- Enter
                if currentCompletion then
                    clear()
                    uncomplete()
                    redraw()
                end
                break
            elseif modifier == 1 and param == keys.d then
                -- Enter
                if currentCompletion then
                    clear()
                    uncomplete()
                    redraw()
                end
                line = nil
                pos = 0
                break
            elseif (modifier == 0 and param == keys.left) or (modifier == 1 and param == keys.b) then
                -- Left
                if pos > 0 then
                    clear()
                    pos = pos - 1
                    recomplete()
                    redraw()
                end

            elseif (modifier == 0 and param == keys.right) or (modifier == 1 and param == keys.f) then
                -- Right
                if pos < #line then
                    -- Move right
                    clear()
                    pos = pos + 1
                    recomplete()
                    redraw()
                else
                    -- Accept autocomplete
                    acceptCompletion()
                end

            elseif modifier == 2 and param == keys.b then
                -- Word left
                local nNewPos = prevWord()
                if nNewPos ~= pos then
                    clear()
                    pos = nNewPos
                    recomplete()
                    redraw()
                end

            elseif modifier == 2 and param == keys.f then
                -- Word right
                local nNewPos = nextWord()
                if nNewPos ~= pos then
                    clear()
                    pos = nNewPos
                    recomplete()
                    redraw()
                end

            elseif (modifier == 0 and (param == keys.up or param == keys.down)) or (modifier == 1 and (param == keys.p or param == keys.n)) then
                -- Up or down
                if currentCompletion then
                    -- Cycle completions
                    clear()
                    if param == keys.up or param == keys.p then
                        currentCompletion = currentCompletion - 1
                        if currentCompletion < 1 then
                            currentCompletion = #completions
                        end
                    elseif param == keys.down or param == keys.n then
                        currentCompletion = currentCompletion + 1
                        if currentCompletion > #completions then
                            currentCompletion = 1
                        end
                    end
                    redraw()

                elseif history then
                    -- Cycle history
                    clear()
                    if param == keys.up or param == keys.p then
                        -- Up
                        if historyPos == nil then
                            if #history > 0 then
                                historyPos = #history
                            end
                        elseif historyPos > 1 then
                            historyPos = historyPos - 1
                        end
                    elseif param == keys.down or param == keys.n then
                        -- Down
                        if historyPos == #history then
                            historyPos = nil
                        elseif historyPos ~= nil then
                            historyPos = historyPos + 1
                        end
                    end
                    if historyPos then
                        line = history[historyPos]
                        pos = #line
                    else
                        line = ""
                        pos = 0
                    end
                    uncomplete()
                    redraw()

                end

            elseif modifier == 0 and param == keys.backspace then
                -- Backspace
                if pos > 0 then
                    clear()
                    line = string.sub(line, 1, pos - 1) .. string.sub(line, pos + 1)
                    pos = pos - 1
                    recomplete()
                    redraw()
                end

            elseif (modifier == 0 and param == keys.home) or (modifier == 1 and param == keys.a) then
                -- Home
                if pos > 0 then
                    clear()
                    pos = 0
                    recomplete()
                    redraw()
                end

            elseif modifier == 0 and param == keys.delete then
                -- Delete
                if pos < #line then
                    clear()
                    line = string.sub(line, 1, pos) .. string.sub(line, pos + 2)
                    recomplete()
                    redraw()
                end

            elseif (modifier == 0 and param == keys["end"]) or (modifier == 1 and param == keys.e) then
                -- End
                if pos < #line then
                    clear()
                    pos = #line
                    recomplete()
                    redraw()
                end

            elseif modifier == 1 and param == keys.u then
                -- Delete from cursor to beginning of line
                if pos > 0 then
                    clear()
                    line = line:sub(pos + 1)
                    pos = 0
                    recomplete()
                    redraw()
                end

            elseif modifier == 1 and param == keys.k then
                -- Delete from cursor to end of line
                if pos < #line then
                    clear()
                    line = line:sub(1, pos)
                    pos = #line
                    recomplete()
                    redraw()
                end

            elseif modifier == 2 and param == keys.d then
                -- Delete from cursor to end of next word
                if pos < #line then
                    local nNext = nextWord()
                    if nNext ~= pos then
                        clear()
                        line = line:sub(1, pos) .. line:sub(nNext + 1)
                        recomplete()
                        redraw()
                    end
                end

            elseif modifier == 1 and param == keys.w then
                -- Delete from cursor to beginning of previous word
                if pos > 0 then
                    local nPrev = prevWord(pos)
                    if nPrev ~= pos then
                        clear()
                        line = line:sub(1, nPrev) .. line:sub(pos + 1)
                        pos = nPrev
                        recomplete()
                        redraw()
                    end
                end

            elseif modifier == 0 and param == keys.tab then
                -- Tab (accept autocomplete)
                acceptCompletion()

            end
        elseif event == "key_up" then
            -- Update the status of the modifier flag
            if param == keys.leftCtrl or param == keys.rightCtrl or param == keys.leftAlt or param == keys.rightAlt then
                downKeys[param] = false
                updateModifier()
            end
        elseif event == "term_resize" then
            -- Terminal resized
            w, h = term.getSize()
            redraw()

        end
    end

    local cx, cy = term.getCursorPos()
    term.setCursorBlink(false)
    if cy >= h then
        term.scroll(1)
        term.setCursorPos(1, cy)
    else
        term.setCursorPos(1, cy + 1)
    end

    return line
end
