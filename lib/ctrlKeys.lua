function waitFor(char, raw)
    local timer
    while true do
        local e, param = (raw and os.pullEvent or os.pullEventRaw)()
        if e == "key" and param == keys[char] then
            timer = os.startTimer(0)
        elseif e == "char" and param:lower() == char then
            timer = nil
        elseif e == "timer" and param == timer then
            return
        end
    end
end