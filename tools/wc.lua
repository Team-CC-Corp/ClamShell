local argparse = grin.getPackageAPI("Team-CC-Corp/Grin", "argparse")

local parser = argparse.new()
parser
    :switch "bytes"
    :shortcut "c"
parser
    :switch "words"
    :shortcut "w"
parser
    :switch "lines"
    :shortcut "l"
parser
    :switch "max-line-length"
    :shortcut "L"
parser
    :argument "file"
    :count "*"

local options = parser:parse({}, ...)
if not options then
    return
end

local doBytes, doWords, doLines, doMax = options.bytes, options.words, options.lines, options['max-line-length']
if not doBytes and not doWords and not doLines and not doMax then
    doBytes = true
    doWords = true
    doLines = true
end

local function countLines(read)
    local lines, words, bytes, max = 0, 0, 0, 0

    for line in read do
        lines = lines + 1
        bytes = bytes + #line
        local _, wordCount = line:gsub("%S+", "")
        words = words + wordCount
        max = math.max(max, #line)
    end

    return lines, words, bytes, max
end

if options.file and #options.file > 0 then
    local tLines, tWords, tBytes, tMax = 0, 0, 0, 0
    for _, file in ipairs(options.file) do
        local lFile = shell.resolve(file)
        if not fs.exists(lFile) then
            error("No such file " .. file, 0)
        end

        local handle = fs.open(lFile, "r")
        local lines, words, bytes, max = countLines(handle.readLine)
        handle.close()

        tLines = tLines + lines
        tWords = tWords + words
        tBytes = tBytes + bytes
        tMax = math.max(tMax, bytes)

        if doLines then write(lines .. " ") end
        if doWords then write(words .. " ") end
        if doBytes then write(bytes .. " ") end
        if doMax then write(max .. " ") end
        print(file)
    end

    if #options.file > 1 then
        if doLines then write(tLines .. " ") end
        if doWords then write(tWords .. " ") end
        if doBytes then write(tBytes .. " ") end
        if doMax then write(tMax .. " ") end
        print("total")
    end
else
    local lines, words, bytes, max = countLines(read)

    if doLines then write(lines .. " ") end
    if doWords then write(words .. " ") end
    if doBytes then write(bytes .. " ") end
    if doMax then write(max .. " ") end
    print()
end
