local function basicRead(replaceChar, history)
	term.setCursorBlink(true)

	local sLine = ""
	local nHistoryPos
	local nPos = 0
	if replaceChar then
		replaceChar = string.sub(replaceChar, 1, 1)
	end

	local w = term.getSize()
	local sx = term.getCursorPos()

	local function redraw(_sCustomReplaceChar)
		local nScroll = 0
		if sx + nPos >= w then
			nScroll =(sx + nPos)- w
		end

		local cx,cy = term.getCursorPos()
		term.setCursorPos(sx, cy)
		local sReplace = _sCustomReplaceChar or replaceChar
		if sReplace then
			term.write(string.rep(sReplace, math.max(string.len(sLine)- nScroll, 0)))
		else
			term.write(string.sub(sLine, nScroll + 1))
		end
		term.setCursorPos(sx + nPos - nScroll, cy)
	end

	while true do
		local sEvent, param = os.pullEvent()
		if sEvent == "char" then
			-- Typed key
			sLine = string.sub(sLine, 1, nPos).. param .. string.sub(sLine, nPos + 1)
			nPos = nPos + 1
			redraw()

		elseif sEvent == "paste" then
			-- Pasted text
			sLine = string.sub(sLine, 1, nPos).. param .. string.sub(sLine, nPos + 1)
			nPos = nPos + string.len(param)
			redraw()

		elseif sEvent == "key" then
			if param == keys.enter then
				-- Enter
				break

			elseif param == keys.left then
				-- Left
				if nPos > 0 then
					nPos = nPos - 1
					redraw()
				end

			elseif param == keys.right then
				-- Right
				if nPos < string.len(sLine)then
					redraw(" ")
					nPos = nPos + 1
					redraw()
				end

			elseif param == keys.up or param == keys.down then
				-- Up or down
				if history then
					redraw(" ")
					if param == keys.up then
						-- Up
						if nHistoryPos == nil then
							if #history > 0 then
								nHistoryPos = #history
							end
						elseif nHistoryPos > 1 then
							nHistoryPos = nHistoryPos - 1
						end
					else
						-- Down
						if nHistoryPos == #history then
							nHistoryPos = nil
						elseif nHistoryPos ~= nil then
							nHistoryPos = nHistoryPos + 1
						end
					end
					if nHistoryPos then
						sLine = history[nHistoryPos]
						nPos = string.len(sLine)
					else
						sLine = ""
						nPos = 0
					end
					redraw()
				end
			elseif param == keys.backspace then
				-- Backspace
				if nPos > 0 then
					redraw(" ")
					sLine = string.sub(sLine, 1, nPos - 1).. string.sub(sLine, nPos + 1)
					nPos = nPos - 1
					redraw()
				end
			elseif param == keys.home then
				-- Home
				redraw(" ")
				nPos = 0
				redraw()
			elseif param == keys.delete then
				-- Delete
				if nPos < string.len(sLine)then
					redraw(" ")
					sLine = string.sub(sLine, 1, nPos).. string.sub(sLine, nPos + 2)
					redraw()
				end
			elseif param == keys["end"] then
				-- End
				redraw(" ")
				nPos = string.len(sLine)
				redraw()
			end

		elseif sEvent == "term_resize" then
			-- Terminal resized
			w = term.getSize()
			redraw()

		end
	end

	local cx, cy = term.getCursorPos()
	term.setCursorBlink(false)
	term.setCursorPos(w + 1, cy)
	print()

	return sLine
end

function read(rep, history)
	parallel.waitForAny(function()
		ret = basicRead(rep, history)
	end, function()
		local ctrlKeys = grin.getPackageAPI(__package, "ctrlKeys")
		ctrlKeys.waitFor("d")
		print()
	end, function()
		while true do
			local e, change = os.pullEvent("scroll")
			print(e, change)
		end
	end)
	return ret
end