local start = os.clock()
local success = shell.run(...)
local finish = os.clock()

if not success then error() end
