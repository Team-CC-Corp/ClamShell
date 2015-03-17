local argparse = grin.getPackageAPI("Team-CC-Corp/Grin", "argparse")

local parser = argparse.new()
parser
    :switch"d"
parser
    :switch"e"
parser
    :switch"f"
parser
    :argument"file"

local options = parser:parse({}, ...)
if not options then
    return
end

assert(options.file, "Usage: test [options] [file]")

if options.d then
    grin.assert(fs.isDir(shell.resolve(options.file)), "Not a directory", 0)
end
if options.f then
    grin.assert(fs.exists(shell.resolve(options.file)) and not fs.isDir(shell.resolve(options.file)), "Not a file", 0)
end
if options.e then
    grin.assert(fs.exists(shell.resolve(options.file)), "Does not exist", 0)
end
