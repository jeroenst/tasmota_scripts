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
# 4 = SG1
# 5 = SG2

import mqtt

def controlheatpump()
    var inputs = tasmota.get_switches()
    var outputs = tasmota.get_power()
    var thermostat_livingroom = inputs[0]
    var thermostat_bathroom = inputs[1]
    var switch_cool = inputs[2]
    
    tasmota.set_timer(10000,controlheatpump)

    var heat = 0
    var cool = 0
    var valve_livingroom = 0
    var valve_bathroom = 0
#    var smartgrid1 = outputs[4]
#    var smartgrid2 = outputs[5]

    if (!switch_cool)
        if (thermostat_livingroom)
            print ("Heat Livingroom")
            valve_livingroom = 1
            heat = 1
        end
        if (thermostat_bathroom)
            print ("Heat Bathroom")
            valve_bathroom = 1
            heat = 1
        end
    else
        if (!thermostat_livingroom)
            print ("Cool Livingroom")
            valve_livingroom = 1
            cool = 1
        end
    end
    if (!valve_livingroom && !valve_bathroom)
        print ("No heat or cool request")
    end
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
