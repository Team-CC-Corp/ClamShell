local argparse = grin.getPackageAPI("ElvishJerricco/Grin", "argparse")

local parser = argparse.new()
parser
    :argument"pattern"
parser
    :argument"file"

local options = parser:parse({}, ...)
if not options then
    return
end

assert(options.pattern, "Usage: glep <pattern> [file]")

local fh
if options.file then
    fh = grin.assert(fs.open(shell.resolve(options.file), "r"), "File not found: " .. options.file, 0)
else
    fh = stdin
end

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