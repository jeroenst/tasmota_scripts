# Input List
# 0 = Thermostat Livingroom
# 1 = Thermostat Bathroom
# 2 = Cool/Heat Switch
# 3 = Boiler Element Active
# 4 = BUH Active

# Output List
# 0 = Cool
# 1 = Heat
# 2 = Valve Livingroom
# 3 = Valve Bathroom
# 4 = Pump Central Heating
# 5 = Boiler Heating Element
# 6 = SG1
# 7 = SG2

import mqtt

def controlheatpump()
    var inputs = tasmota.get_switches()
    var outputs = tasmota.get_power()
    var thermostat_livingroom = inputs[0]
    var thermostat_bathroom = inputs[1]
    var switch_cool = inputs[2]
    
    tasmota.set_timer(10000,controlheatpump)

    var hp_heat = false
    var hp_cool = false
    var valve_livingroom = false
    var valve_bathroom = false
    var pump_ch = false

    if (!switch_cool)
        if (thermostat_livingroom)
            print ("Heat Livingroom")
            valve_livingroom = true
            hp_heat = true
        end
        if (thermostat_bathroom)
            print ("Heat Bathroom")
            valve_bathroom = true
            hp_heat = true
        end
    else
        if (!thermostat_livingroom)
            print ("Cool Livingroom")
            valve_livingroom = true
            hp_cool = true
        end
    end

    if (!valve_livingroom && !valve_bathroom)
        print ("No heat or cool request")
    end

    if (valve_livingroom || valve_bathroom)
        pump_ch = true;
    end    

    tasmota.set_power(0, hp_heat)
    tasmota.set_power(1, hp_cool)
    tasmota.set_power(2, valve_livingroom)
    tasmota.set_power(3, valve_bathroom)
    tasmota.set_power(4, pump_ch)
end

var sendmodbusindex = 0
def sendmodbus()
    tasmota.set_timer(2000,sendmodbus)
    if (sendmodbusindex == 0)
        tasmota.cmd ('modbussend { "deviceaddress": 1, "functioncode": 1, "startaddress":  0, "type": "bit", "count": 5 }')
    end
    if (sendmodbusindex == 1)
        tasmota.cmd ('modbussend { "deviceaddress": 1, "functioncode": 2, "startaddress":  0, "type": "bit", "count": 17 }')
    end
    if (sendmodbusindex == 2)
        tasmota.cmd ('modbussend { "deviceaddress": 1, "functioncode": 3, "startaddress":  0, "type": "int16", "count": 10 }')
    end
    if (sendmodbusindex == 3)
        tasmota.cmd ('modbussend { "deviceaddress": 1, "functioncode": 4, "startaddress":  0, "type": "int16", "count": 13 }')
    end
    if (sendmodbusindex == 4)
        tasmota.cmd ('modbussend { "deviceaddress": 1, "functioncode": 4, "startaddress":  18, "type": "int16", "count":  7}')
        sendmodbusindex = 0
    else
        sendmodbusindex = sendmodbusindex + 1
    end
end

tasmota.set_timer(5000,controlheatpump)
tasmota.set_timer(5000,sendmodbus)
