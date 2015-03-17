local argparse = grin.getPackageAPI("Team-CC-Corp/Grin", "argparse")

local parser = argparse.new()
parser
    :argument"pattern"
parser
    :argument"files"
    :count"*"

local options = parser:parse({}, ...)
if not options then
    return
end

assert(options.pattern, "Usage: glep <pattern> [files]")

local files
if options.files and #options.files > 0 then
    files = {}
    for i,v in ipairs(options.files) do
        fh = grin.assert(fs.open(shell.resolve(v), "r"), "File not found: " .. v, 0)
        table.insert(files, fh)
    end
else
    files = {stdin}
end

for i,fh in ipairs(files) do
    while true do
        local line = fh.readLine()
        if not line then
            break
        end

        if line:find(options.pattern) then
            print(line)
        end
    end

    fh.close()
end
