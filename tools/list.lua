local argparse = grin.getPackageAPI("Team-CC-Corp/Grin", "argparse")

local parser = argparse.new()
parser
    :switch"a"
parser
    :switch"l"
parser
    :argument"dirs"
    :count"*"

local options = parser:parse({}, ...)
if not options then
    return
end


if not options.dirs or #options.dirs == 0 then
    options.dirs = {""}
end

for i,dir in ipairs(options.dirs) do
    local dir = shell.resolve(dir)
    if not (stdout.isPiped or options.l) then
        if #options.dirs > 1 then
            if term.isColor() then
                term.setTextColor(colors.yellow)
            end
            print(dir..":")
        end

        local tDirs, tFiles = {}, {}
        for i,entry in ipairs(fs.list(dir)) do
            if entry:sub(1,1) ~= "." or options.a then
                if fs.isDir(fs.combine(dir, entry)) then
                    table.insert(tDirs, entry)
                else
                    table.insert(tFiles, entry)
                end
            end
        end
        table.sort(tDirs)
        table.sort(tFiles)
        if term.isColor() then
            textutils.pagedTabulate( colors.green, tDirs, colors.white, tFiles )
        else
            textutils.pagedTabulate( tDirs, tFiles )
        end

        if #options.dirs > i then
            print()
        end
    else
        local tDir = {}
        for i,entry in ipairs(fs.list(dir)) do
            if entry:sub(1,1) ~= "." or options.a then
                table.insert(tDir, entry)
            end
        end
        table.sort(tDir)
        print(table.concat(tDir, "\n"))
        if #options.dirs > i then
            print()
        end
    end
end
