-- Test script
local T = {}

function T.test()
    -- Print to Hammerspoon console
    print("\n=== 电池信息 ===")

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

    print(string.format("电量百分比: %d%%", percentage))
    print(string.format("充电状态: %s",
                        isCharging and "充电中" or "使用电池"))
    print(string.format("电源类型: %s", powerSource))

    if timeRemaining >= 0 then
        print(string.format("剩余时间: %d 分钟", timeRemaining))
    else
        print("剩余时间: 计算中...")
    end

    print(string.format("电流: %d mA", amperage))
    print(string.format("电压: %.2f V", voltage / 1000))
    print(string.format("充电周期: %d 次", cycles))
    print(string.format("当前容量: %d mAh", capacity))
    print(string.format("最大容量: %d mAh", maxCapacity))
    print(string.format("设计容量: %d mAh", designCapacity))

    if type(health) == "number" then
        print(string.format("电池健康度: %d%%", health))
    elseif health then
        print(string.format("电池健康度: %s", tostring(health)))
    else
        print("电池健康度: 不可用")
    end

    if healthCondition then
        print(string.format("健康状况: %s", tostring(healthCondition)))
    else
        print("健康状况: 不可用")
    end

    print("================\n")

    -- Show alert with key info
    local status = isCharging and "充电中" or "使用电池"
    local healthStr =
        type(health) == "number" and string.format("%d%%", health) or
            tostring(health or "N/A")
    hs.alert.show(string.format("🔋 %d%% - %s\n电源: %s\n健康度: %s",
                                percentage, status, powerSource, healthStr))
end

return T
