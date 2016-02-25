-- Yep. This is some horrible code. Move on please

local function createLookup(...)
	local out = {}

	for _, tbl in ipairs({...}) do
		for _, v in ipairs(tbl) do
			out[v] = true
		end
	end
	return out
end
local symbols = {
	"{", "}", ";",        -- Blocks
	"\"", "'", "\\", "$", -- Strings
	"|", ">", "&",        -- Piping
	"(", ")",             -- Generic
}

local commandSymbols = createLookup(symbols, {"="})
local stringSymbols = createLookup(symbols)

local terminators = createLookup { "{", "}", ";", ")" }
local pipe = createLookup { "|", ">", "&" }

local keywords = createLookup { "for", "while", "if", "elseif", "else" }

return function(text, filename, fancyHandling)
	local line, char, pointer = 1, 1, 1
	filename = filename or "stdin"

	local function get()
		local c = text:sub(pointer,pointer)
		if c == '\n' then
			char = 1
			line = line + 1
		else
			char = char + 1
		end
		pointer = pointer + 1
		return c
	end

	local function peek(n)
		n = n or 0
		return text:sub(pointer+n,pointer+n)
	end

	local function generateError(err, resumable)
		if resumable == true or (resumable == nil and pointer > #text) then
			resumable = 1
		else
			resumable = 0
		end

		local count, current = 0, ""
		for contents in text:gmatch("[^\r\n]+") do
			count = count + 1
			if count == line then
				current = contents
			end
		end

		if fancyHandling then
			error(line..":"..char..":"..resumable..":"..err, 0)
		else
			print()
			print(current)
			print((" "):rep(char - 1) .. "^")
			error(filename .. ":" .. line..":"..char..": "..err, 0)
		end
	end

	local function eatWhitespace()
		local c = peek()
		while c == "\n" or c == "\t" or c == " " do
			get()
			c = peek()
		end
	end

	local function expect(char)
		if peek() ~= char then
			generateError(("Expected %q"):format(char))
		end

		get()
		eatWhitespace()
	end

	local function consume(str)
		if text:sub(pointer, pointer + #str - 1) == str then
			for i = 1, #str do get() end

			eatWhitespace()
			return true
		else
			return false
		end
	end

	local command, statement, expression

	local function dollar()
		expect("$")

		local start = pointer
		local c = peek()

		if c == '(' then
			get()
			local res = command()
			expect(')')

			return res
		else
			while c == '_' or (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') do
				get()
				c = peek()
			end

			if start == pointer then
				generateError("Expected variable name")
			end

			return { tag = "variable", text:sub(start, pointer - 1) }
		end
	end

	local function string(symbols, name)
		local c = peek()

		if c == "'" then
			get()
			local start = pointer
			local buffer, n = {}, 0

			while true do
				c = peek()
				if c == '\n' then
					generateError("Unexpected new line, expected \"'\"")
				elseif c == '' then
					generateError("Unexpected new line, expected \"'\"")
				elseif c == '\\' then
					get()
					c = peek()
				elseif c == "'" then
					get()
					break
				end

				n = n + 1
				buffer[n] = c

				get()
			end

			eatWhitespace()

			return { tag = "string", table.concat(buffer) }
		elseif c == '"' then
			get()
			local start = pointer
			local buffer, n = {}, 0
			local out, outN = { tag = "compound" }, 0

			while true do
				c = peek()
				if c == '\n' then
					generateError("Unexpected new line, expected \"\"\"")
				elseif c == '' then
					generateError("Unexpected eof, expected \"\"\"")
				elseif c == '"' then
					get()
					break
				elseif c == '$' then
					if n > 0 then
						outN = outN + 1
						out[outN] = table.concat(buffer)
						buffer = {}
						n = 0
					end

					outN = outN + 1
					out[outN] = dollar()
				else
					if c == '\\' then
						get()
						c = peek()
					end

					n = n + 1
					buffer[n] = c
					get()
				end
			end

			if n > 0 then
				outN = outN + 1
				out[outN] = table.concat(buffer)
			end

			eatWhitespace()

			if outN == 0 then
				return { tag = "string", "" }
			elseif outN == 1 then
				local val = out[1]
				if type(val) == "string" then
					return { tag = "string", val }
				else
					return out[1]
				end
			else
				return out
			end
		elseif c == "$" then
			local token = dollar()
			eatWhitespace()
			return token
		else
			local start = pointer

			while not symbols[c] and c ~= "\n" and c ~= "\t" and c ~= " " and c ~= "" do
				get()
				c = peek()
			end

			if start == pointer then
				generateError("Expected " .. name)
			end

			local str = text:sub(start, pointer - 1)
			eatWhitespace()

			if keywords[str] then
				return { tag = "keyword", str }
			else
				return { tag = "string", str }
			end
		end
	end

	local function parsePipe(current)
		if consume(">>") then
			return { tag = "append", current, string(stringSymbols, "filename") }
		elseif consume(">") then
			return { tag = "write", current, string(stringSymbols, "filename") }
		elseif consume("||") then
			return { tag = "or", current, expression() }
		elseif consume("&&") then
			return { tag = "and", current, expression() }
		elseif consume("|") then
			return { tag = "pipe", current, expression() }
		else
			generateError("Expected pipe")
		end
	end

	expression = function()
		if consume("(") then
			local cmd = command()
			expect(')')

			local c = peek()
			if c == "" or terminators[c] then
				return cmd
			elseif pipe[c] then
				return parsePipe(current)
			else
				return cmd
			end
		else
			return command()
		end
	end

	command = function(initial)
		if not initial then
			initial = string(commandSymbols, "command")
			if initial.tag == "keyword" then
				generateError("Unexpected keyword", 0)
			end
		end

		local current = { tag = "command", initial }
		local n = 1

		while true do
			local c = peek()
			if c == "" or terminators[c] then
				break
			elseif pipe[c] then
				return parsePipe(current)
			end

			n = n + 1
			current[n] = string(stringSymbols, "argument")
		end

		return current
	end

	local function block()
		local block, n = {}, 0

		local c = peek()
		if c == '' or c == '}' then
			return block
		end

		while true do
			n = n + 1
			block[n] = statement()

			local c = peek()
			if c == '' or c == '}' then
				break
			elseif c == ';' then
				get()
				eatWhitespace()
			else
				generateError("Expected ;")
			end

			-- Allow trailing ; on block
			c = peek()
			if c == '' or c == '}' then break end
		end

		return block
	end

	statement = function()
		if peek() == "(" then return expression() end

		local first = string(commandSymbols, "command")

		if first.tag == "keyword" then
			local keyword = first[1]

			if keyword == "if" then
				local conditional = command()
				expect("{")
				local body = block()
				expect("}")

				local tag, n = { tag = "if", conditional, body }, 2

				while true do
					if consume("else") then
						expect("{")
						local body = block()
						expect("}")

						n = n + 1
						tag[n] = { tag = "else", body }

						break
					elseif consume("elseif") then
						local conditional = command()
						expect("{")
						local body = block()
						expect("}")

						n = n + 1
						tag[n] = { tag = "elseif", conditional, body }
					else
						break
					end
				end

				return tag
			elseif keyword == "while" then
				local command = command()
				expect("{")
				local body = block()
				expect("}")

				return { tag = "while", command, body }
			elseif keyword == "for" then
				local var = string(commandSymbols, "string")
				expect("=")
				local command = command()
				expect("{")
				local body = block()
				expect("}")

				return { tag = "for", var, command, body }
			else
				print("Unexpected keyword " .. keyword)
			end
		elseif consume("=") then
			return {
				tag = "set",
				first,
				string(stringSymbols, "value"),
			}
		else
			return command(first)
		end
	end

	eatWhitespace()
	local body = block()
	eatWhitespace()

	if pointer < #text then
		generateError("Expected EOF")
	end

	return body
end
