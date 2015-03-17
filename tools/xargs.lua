local argparse = grin.getPackageAPI("Team-CC-Corp/Grin", "argparse")

local parser = argparse.new()
parser
    :argument"command"
parser
    :argument"args"
    :count"*"

local options = parser:parse({args={}}, ...)
if not options then
    return
end

grin.assert(options.command and shell.resolveProgram(options.command), "Expected command", 0)

while true do
    local line = read()
    if not line then
        break
    end
    table.insert(options.args, line)
end

shell.run(options.command, unpack(options.args))
