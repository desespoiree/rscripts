if not game.IsLoaded then
    game.Loaded:Wait()
end

local crashFns = {"Crash", "HardCrash", "GPUCrash", "RAMCrash", "KillClient", "SetFPS"}

for _, elem in getgc(true)  do
    if
        typeof(elem) == "table"
        and rawget(elem, "Detected")
        and typeof(elem.Detected) == "function"
        and rawget(elem, "RLocked")
    then
        hookfunction(Detected, function(action, reason, nocrash)
            --print(`Detected: Action: {action}, Reason: {reason}, Crashing: {not nocrash}`)
            return true
        end)

        print("Hooked 'Detected' Function")
    elseif
        typeof(elem) == "function"
     then
        local name = debug.info(elem, "n")

        if not table.find(crashFns, name) then
            continue
        end

        hookfunction(elem, function()end)
        print(`Hooked Lag/Crash function : {name}`)
    end
end
