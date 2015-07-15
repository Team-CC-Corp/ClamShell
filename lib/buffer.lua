function new(original)
    if not original then original = term.current() end
    local text = {}
    local textColor = {}
    local backColor = {}

    local cursorX = 1
    local cursorY = 1

    local lineOffset = 0
    local cursorYOffset = cursorY

    local cursorBlink = false
    local curTextColor = "0"
    local curBackColor = "f"

    local sizeX, sizeY = original.getSize()
    local color = original.isColor()

    local bubble = false
    local friendlyClear = false
    local original = original
    local maxScrollback = 100

    local redirect = {}

    local function trim()
        if maxScrollback > -1 then
            while lineOffset > maxScrollback do
                table.remove(text, 1)
                table.remove(textColor, 1)
                table.remove(backColor, 1)
                lineOffset = lineOffset - 1
            end
        end
        cursorYOffset = lineOffset + cursorY
    end
    function redirect.write(writeText)
        writeText = tostring(writeText)
        local pos = cursorX
        if cursorY > sizeY or cursorY < 1 then
            cursorX = pos + #writeText
            return
        end
        if pos + #writeText <= 1 then
            --skip entirely.
            cursorX = pos + #writeText
            return
        elseif pos < 1 then
            --adjust text to fit on screen starting at one.
            writeText = string.sub(writeText, math.abs(cursorX) + 2)
            cursorX = 1
        elseif pos > sizeX then
            --if we're off the edge to the right, skip entirely.
            cursorX = pos + #writeText
            return
        else
            writeText = writeText
        end

        local lineText = text[cursorYOffset]
        local lineColor = textColor[cursorYOffset]
        local lineBack = backColor[cursorYOffset]
        local preStop = cursorX - 1
        local preStart = math.min(1, preStop)
        local postStart = cursorX + string.len(writeText)
        local postStop = sizeX
        local sub, rep = string.sub, string.rep

        text[cursorYOffset] = sub(lineText, preStart, preStop)..writeText..sub(lineText, postStart, postStop)
        textColor[cursorYOffset] = sub(lineColor, preStart, preStop)..rep(curTextColor, #writeText)..sub(lineColor, postStart, postStop)
        backColor[cursorYOffset] = sub(lineBack, preStart, preStop)..rep(curBackColor, #writeText)..sub(lineBack, postStart, postStop)
        cursorX = pos + string.len(writeText)

        if bubble then original.write(writeText) end
    end

    function redirect.blit(writeText, writeFore, writeBack)
        local pos = cursorX
        if cursorY > sizeY or cursorY < 1 then
            cursorX = pos + #writeText
            return
        end
        if pos + #writeText <= 1 then
            --skip entirely.
            cursorX = pos + #writeText
            return
        elseif pos < 1 then
            --adjust text to fit on screen starting at one.
            writeText = string.sub(writeText, math.abs(cursorX) + 2)
            cursorX = 1
        elseif pos > sizeX then
            --if we're off the edge to the right, skip entirely.
            cursorX = pos + #writeText
            return
        else
            writeText = writeText
        end

        local lineText = text[cursorYOffset]
        local lineColor = textColor[cursorYOffset]
        local lineBack = backColor[cursorYOffset]
        local preStop = cursorX - 1
        local preStart = math.min(1, preStop)
        local postStart = cursorX + string.len(writeText)
        local postStop = sizeX
        local sub, rep = string.sub, string.rep

        text[cursorYOffset] = sub(lineText, preStart, preStop)..writeText..sub(lineText, postStart, postStop)
        textColor[cursorYOffset] = sub(lineColor, preStart, preStop)..writeFore..sub(lineColor, postStart, postStop)
        backColor[cursorYOffset] = sub(lineBack, preStart, preStop)..writeBack..sub(lineBack, postStart, postStop)
        cursorX = pos + string.len(writeText)

        if bubble then original.blit(writeText, writeFore, writeBack) end
    end

    function redirect.clear()
        if friendlyClear then
            lineOffset = lineOffset + sizeY
            friendlyClear = false

            trim()
        end

        for i=lineOffset + 1, sizeY+lineOffset do
            text[i] = string.rep(" ", sizeX)
            textColor[i] = string.rep(curTextColor, sizeX)
            backColor[i] = string.rep(curBackColor, sizeX)
        end

        if bubble then original.clear() end
    end
    function redirect.clearLine()
        text[cursorYOffset] = string.rep(" ", sizeX)
        textColor[cursorYOffset] = string.rep(curTextColor, sizeX)
        backColor[cursorYOffset] = string.rep(curBackColor, sizeX)

        if bubble then original.clearLine() end
    end

    function redirect.getCursorPos()
        return cursorX, cursorY
    end

    function redirect.setCursorPos(x, y)
        cursorX = math.floor(tonumber(x)) or cursorX
        cursorY = math.floor(tonumber(y)) or cursorY

        cursorYOffset = cursorY + lineOffset

        if bubble then original.setCursorPos(x, y) end
    end

    function redirect.setCursorBlink(b)
        cursorBlink = b
        if bubble then original.setCursorBlink(b) end
    end

    function redirect.getSize()
        return sizeX, sizeY
    end

    function redirect.scroll(n)
        n = tonumber(n) or 1
        if n > 0 then
            lineOffset = lineOffset + n
            for i = sizeY + lineOffset - n + 1, sizeY + lineOffset do
                text[i] = string.rep(" ", sizeX)
                textColor[i] = string.rep(curTextColor, sizeX)
                backColor[i] = string.rep(curBackColor, sizeX)
            end

            trim()
        elseif n < 0 then
            for i = sizeY + cursorYOffset, math.abs(n) + 1 + cursorYOffset, -1 do
                if text[i + n] then
                    text[i] = text[i + n]
                    textColor[i] = textColor[i + n]
                    backColor[i] = backColor[i + n]
                end
            end

            for i = cursorYOffset, math.abs(n) + cursorYOffset do
                text[i] = string.rep(" ", sizeX)
                textColor[i] = string.rep(curTextColor, sizeX)
                backColor[i] = string.rep(curBackColor, sizeX)
            end
        end

        if bubble then original.scroll(n) end
    end

    function redirect.setTextColor(clr)
        if clr and clr <= 32768 and clr >= 1 then
            if color then
                curTextColor = string.format("%x", math.floor(math.log(clr) / math.log(2)))
            elseif clr == 1 or clr == 32768 then
                curTextColor = string.format("%x", math.floor(math.log(clr) / math.log(2)))
            else
                return nil, "Colour not supported"
            end
        end
        if bubble then original.setTextColour(clr) end
    end
    redirect.setTextColour = redirect.setTextColor

    function redirect.setBackgroundColor(clr)
        if clr and clr <= 32768 and clr >= 1 then
            if color then
                curBackColor = string.format("%x", math.floor(math.log(clr) / math.log(2)))
            elseif clr == 32768 or clr == 1 then
                curBackColor = string.format("%x", math.floor(math.log(clr) / math.log(2)))
            else
                return nil, "Colour not supported"
            end
        end

        if bubble then original.setBackgroundColour(clr) end
    end
    redirect.setBackgroundColour = redirect.setBackgroundColor

    function redirect.isColor() return color == true end
    redirect.isColour = redirect.isColor

    function redirect.getTextColor() return 2 ^ tonumber(curTextColor, 16) end
    function redirect.getBackgroundColor() return 2 ^ tonumber(curBackColor, 16) end
    redirect.getTextColour = redirect.getTextColor
    redirect.getBackgroundColour = redirect.getBackgroundColor

    function redirect.render(inputBuffer)
        for i = 1, sizeY do
            text[i + lineOffset] = inputBuffer.text[i]
            textColor[i + lineOffset] = inputBuffer.textColor[i]
            backColor[i + lineOffset] = inputBuffer.backColor[i]
        end
    end

    function redirect.draw(offset)
        local original = original
        local lineOffset = lineOffset + (offset or 0)
        for i=1, sizeY do
            original.setCursorPos(1,i)
            local yOffset = lineOffset + i
            original.blit(text[yOffset], textColor[yOffset], backColor[yOffset])
        end

        original.setCursorPos(cursorX, cursorY)
        original.setTextColor(2 ^ tonumber(curTextColor, 16))
        original.setBackgroundColor(2 ^ tonumber(curBackColor, 16))
        original.setCursorBlink(cursorBlink)
    end

    function redirect.bubble(b) bubble = b end
    function redirect.friendlyClear(b) friendlyClear = b end

    function redirect.trim(max)
        while lineOffset > max do
            table.remove(text, 1)
            table.remove(textColor, 1)
            table.remove(backColor, 1)
            lineOffset = lineOffset - 1
        end
        cursorYOffset = cursorY + lineOffset
    end
    function redirect.totalHeight() return lineOffset end

    function redirect.maxScrollback(n)
        if n ~= nil then maxScrollback = n end
        return maxScrollback
    end

    function redirect.updateSize()
        local _, y = original.getSize()
        sizeY = y
    end

    redirect.clear()
    return redirect
end
