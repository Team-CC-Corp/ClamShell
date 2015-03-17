local args = {...}

if #args > 0 then
    for i,v in ipairs(args) do
        local fh = assert(fs.open(shell.resolve(v), "r"), "File not found: " .. v)
        print(fh.readAll())
        fh.close()
    end
else
    while true do
        local line = read()
        if not line then
            return
        end
        print(line)
    end
end
