local start = os.clock()
local success = shell.run(...)
local finish = os.clock()

print(finish - start)

if not success then error() end
