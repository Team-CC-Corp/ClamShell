local argparse = grin.getPackageAPI("Team-CC-Corp/Grin", "argparse")

local parser = argparse.new()
parser
    :switch"n"
parser
    :argument"args"
    :count"*"

local options = parser:parse({args={}}, ...)
if not options then
    return
end

if options.n then
    write(table.concat(options.args, " "))
else
    print(table.concat(options.args, " "))
end
