if not game.IsLoaded then
    game.Loaded:Wait()
end

local debugMod = false

local function log(x)
    if not debugMod then
        return
    end

    print(x)
end

local crashFns = {"Crash", "HardCrash", "GPUCrash", "RAMCrash", "KillClient", "SetFPS"}

for _, elem in getgc(true)  do
    if
        typeof(elem) == "table"
        and rawget(elem, "Detected")
        and typeof(elem.Detected) == "function"
        and rawget(elem, "RLocked")
    then

        hookfunction(elem.Detected, function(action, reason, nocrash)
            log(`Detected: Action: {action}, Reason: {reason}, Crashing: {not nocrash}`)
            return true
        end)

        log("Hooked Detected Function")
    elseif
        typeof(elem) == "function"
     then
        local name = debug.info(elem, "n")

        if not table.find(crashFns, name) then
            continue
        end

        hookfunction(elem, function()end)
        log(`Hooked Lag/Crash function : {name}`)
    end
end
