-- Test script
local T = {}

function T.test()
    -- Print to Hammerspoon console
    print("\n=== Battery information ===")

    local percentage = hs.battery.percentage() or 0
    local isCharging = hs.battery.isCharging()
    local powerSource = hs.battery.powerSource() or "Unknown"
    local timeRemaining = hs.battery.timeRemaining() or -1
    local amperage = hs.battery.amperage() or 0
    local voltage = hs.battery.voltage() or 0
    local cycles = hs.battery.cycles() or 0
    local capacity = hs.battery.capacity() or 0
    local maxCapacity = hs.battery.maxCapacity() or 0
    local designCapacity = hs.battery.designCapacity() or 0
    local health = hs.battery.health()
    local healthCondition = hs.battery.healthCondition()

    print(string.format("Charge: %d%%", percentage))
    print(string.format("Charging state: %s",
                        isCharging and "Charging" or "On battery"))
    print(string.format("Power source: %s", powerSource))

    if timeRemaining >= 0 then
        print(string.format("Time remaining: %d min", timeRemaining))
    else
        print("Time remaining: Calculating...")
    end

    print(string.format("Current: %d mA", amperage))
    print(string.format("Voltage: %.2f V", voltage / 1000))
    print(string.format("Charge cycles: %d", cycles))
    print(string.format("Current capacity: %d mAh", capacity))
    print(string.format("Maximum capacity: %d mAh", maxCapacity))
    print(string.format("Design capacity: %d mAh", designCapacity))

    if type(health) == "number" then
        print(string.format("Battery health: %d%%", health))
    elseif health then
        print(string.format("Battery health: %s", tostring(health)))
    else
        print("Battery health: Unavailable")
    end

    if healthCondition then
        print(string.format("Health condition: %s", tostring(healthCondition)))
    else
        print("Health condition: Unavailable")
    end

    print("================\n")

    -- Show alert with key info
    local status = isCharging and "Charging" or "On battery"
    local healthStr =
        type(health) == "number" and string.format("%d%%", health) or
            tostring(health or "N/A")
    hs.alert.show(string.format("🔋 %d%% - %s\nPower: %s\nHealth: %s",
                                percentage, status, powerSource, healthStr))
end

return T
