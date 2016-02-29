--- Expect a type with a message
--- @param value The value to check
-- @tparam string expected The name of the type
-- @tparam string desc The descrition of the value
-- @tparam int? level Level to report at
function expect(value, expected, desc, level)
    local t = type(value)
    if t ~= expected then
        error(desc .. ": Expected " .. expected .. " got " .. t, (level or 1) + 1)
    end
end

--- Apply a function to every element in a table.
-- @tparam 'a[] tbl The table to pass
-- @tparam ('a->'b') selector Function to call on each element
-- @param ... Additional arguments to pass to selector
-- @treturn 'b[] Converted table
function map(tbl, selector, ...)
    local out = {}
    for i = 1, #tbl do
        out[i] = selector(tbl[i], ...)
    end

    return out
end
