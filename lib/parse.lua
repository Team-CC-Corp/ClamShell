local function createLookup(tbl)
	for _, v in ipairs(tbl) do
		tbl[v] = true
	end
	return tbl
end

local commandSymbols = createLookup { "|", ">", "{", "}", "=", "\"", "'", ";", "$", "(", ")" }
local stringSymbols = createLookup { "|", ">", "{", "}", "\"", "'", ";", "$", "(", ")" }
local keywords = createLookup { "for", "while", "if", "elseif", "else" }

local x = function(text)
	local line, char, pointer = 1, 1, 1

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

		print(text)
		print((" "):rep(pointer - 1) .. "^")
		error(line..":"..char..":"..resumable..":"..err, 0)
	end

	local function eatWhitespace()
		local c = peek()
		while c == "\n" or c == "\t" or c == " " do
			get()
			c = peek()
		end
	end

	local function expect(char)
		local c = peek()
		if c ~= char then
			generateError(("Expected %q, got %q"):format(char, c))
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

	local command, statement

	local function dollar()
		get()

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
		eatWhitespace()

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

			return { table.concat(buffer) }
		elseif c == '"' then
			get()
			local start = pointer
			local buffer, n = {}, 0
			local out, outN = {}, 0

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

			return out
		elseif c == "$" then
			return dollar()
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
			if keywords[str] then
				return { { tag = "keyword", str} }
			else
				return { str }
			end
		end
	end

	command = function(initial)
		if not initial then
			initial = string(commandSymbols, "command")
			if type(initial[1]) == "table" and initial[1].tag == "keyword" then
				generateError("Unexpected keyword", 0)
			end
		end

		local command = { tag = "command", initial }
		local n = 1

		while true do
			eatWhitespace()

			local c = peek()
			if c == "" or stringSymbols[c] then
				break
			end

			n = n + 1
			command[n] = string(stringSymbols, "argument")
		end

		return command
	end

	local function block()
		local block, n = {}, 0
		while true do
			while consume(';') do end

			local c = peek()
			if c == '' or c == '}' then
				break
			end

			n = n + 1
			block[n] = statement()
		end

		while consume(';') do end

		return block
	end

	statement = function()
		local first = string(commandSymbols, "command")
		eatWhitespace()

		if type(first[1]) == "table" and first[1].tag == "keyword" then
			local keyword = first[1][1]

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
				eatWhitespace()
				expect("=")

				local command = command()

				expect("{")

				local body = block()

				expect("}")
				eatWhitespace()

				return { tag = "for", var, command, body }
			else
				print("Unexpected keyword " .. keyword)
			end
		elseif peek() == '=' then
			get()
			eatWhitespace()

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


x [["foobar $foo bar $(echo)"]]
x [['foobar']]
x [[if echo { cat "foobar"; echo } else { echo; echo; }]]
x [[while echo { cat "foobar" } ]]
x [[for var = foo { cat $var } ]]
x [[foobar-baz=another baz]]
x [[echo $foobar]]
