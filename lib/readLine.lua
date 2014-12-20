function read(replaceChar, history)
	term.setCursorBlink(true)

	local line = ""
	local pos = 0
	local historyPos = nil
	if replaceChar then
		replaceChar = string.sub(replaceChar, 1, 1)
	end

	local w = term.getSize()
	local sx = term.getCursorPos()

	local function redraw(customReplaceChar)
		local scroll = 0
		if sx + pos >= w then
			scroll =(sx + pos)- w
		end

		local cx,cy = term.getCursorPos()
		term.setCursorPos(sx, cy)
		local sReplace = customReplaceChar or replaceChar
		if sReplace then
			term.write(string.rep(sReplace, math.max(string.len(line)- scroll, 0)))
		else
			term.write(string.sub(line, scroll + 1))
		end
		term.setCursorPos(sx + pos - scroll, cy)
	end

	local mappings = {
		-- Clear line before cursor
		[keys.u] = function()
			redraw(" ")
			historyPos = nil
			line = line:sub(pos + 1)
			pos = 0
			redraw()
		end,

		-- Clear line after cursor
		[keys.k] = function()
			redraw(" ")
			historyPos = nil
			line = line:sub(1, pos)
			pos = #line
			redraw()
		end,

		-- Exit
		[keys.e] = function()
			line = nil

			return true
		end,

		-- Ctrl+Left
		[keys.a] = function()
			local len = #line
			if len == 0 then return end

			local oldPos = pos
			local newPos = 0

			while true do
				local foundPos = line:find("%s", newPos + 1)
				if foundPos == nil or foundPos >= oldPos then
					break
				else
					newPos = foundPos
				end
			end

			pos = newPos
			redraw()
		end,

		-- Ctrl+Right
		[keys.d] = function()
			pos = (line:find("%s", pos + 1)) or #line
			redraw()
		end,
	}

	local timers = {}

	while true do
		local event, param = os.pullEvent()
		if event == "char" then
			local char = param:lower()
			if mappings[keys[char]] then timers[keys[char]] = nil end

			-- Typed key
			line = string.sub(line, 1, pos).. param .. string.sub(line, pos + 1)
			pos = pos + 1
			redraw()

		elseif event == "paste" then
			-- Pasted text
			line = string.sub(line, 1, pos).. param .. string.sub(line, pos + 1)
			pos = pos + string.len(param)
			redraw()

		elseif event == "key" then
			if mappings[param] then
				timers[param] = os.startTimer(0)
			elseif param == keys.enter then
				break
			elseif param == keys.left then
				if pos > 0 then
					pos = pos - 1
					redraw()
				end

			elseif param == keys.right then
				if pos < string.len(line)then
					redraw(" ")
					pos = pos + 1
					redraw()
				end

			elseif param == keys.up or param == keys.down then
				redraw(" ")
				if param == keys.up then
					-- Up
					if historyPos == nil then
						if #history > 0 then
							historyPos = #history
						end
					elseif historyPos > 1 then
						historyPos = historyPos - 1
					end
				else
					-- Down
					if historyPos == #history then
						historyPos = nil
					elseif historyPos ~= nil then
						historyPos = historyPos + 1
					end
				end
				if historyPos then
					line = history[historyPos]
					pos = string.len(line)
				else
					line = ""
					pos = 0
				end
				redraw()
			elseif param == keys.backspace then
				if pos > 0 then
					redraw(" ")
					line = string.sub(line, 1, pos - 1).. string.sub(line, pos + 1)
					pos = pos - 1
					redraw()
				end
			elseif param == keys.home then
				redraw(" ")
				pos = 0
				redraw()
			elseif param == keys.delete then
				if pos < string.len(line)then
					redraw(" ")
					line = string.sub(line, 1, pos).. string.sub(line, pos + 2)
					redraw()
				end
			elseif param == keys["end"] then
				redraw(" ")
				pos = string.len(line)
				redraw()
			end
		elseif event == "timer" then
			local toCall = nil
			for key, timer in pairs(timers) do
				if timer == param then
					toCall = mappings[key]
					timers[key] = nil
					break
				end
			end

			if toCall and toCall() then
				break
			end
		elseif event == "term_resize" then
			w = term.getSize()
			redraw()

		end
	end

	local cx, cy = term.getCursorPos()
	term.setCursorBlink(false)
	term.setCursorPos(w + 1, cy)
	print()

	return line
end