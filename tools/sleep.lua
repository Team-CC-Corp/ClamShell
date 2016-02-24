local argparse = grin.getPackageAPI("Team-CC-Corp/Grin", "argparse")

local parser = argparse.new()
parser
    :argument"time"
    :count"*"

local options = parser:parse({}, ...)
if not options then return end

if not options.time or #options.time == 0 then
    error("No time specified", 0)
end

local time = 0
for _, t in ipairs(options.time) do
    local localT = tonumber(t)
    if not localT then
        error(string.format("%q", options.time) .. " is not a number", 0)
    end

    time = time + localT
end

sleep(time)
