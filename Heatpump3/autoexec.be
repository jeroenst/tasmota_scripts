# Input List
# 0 = Thermostat Livingroom
# 1 = Thermostat Bathroom
# 2 = Cool/Heat Switch
# 3 = Boiler Element Active
# 4 = BUH Active

# Output List
# 0 = Heat
# 1 = Cool
# 2 = Valve Livingroom
# 3 = Valve Bathroom
# 4 = Pump Central Heating
# 5 = Boiler Heating Element
# 6 = SG1
# 7 = SG2

import mqtt
import string

var remote_heat_request = false;
var outside_temperature = nil;

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
        if (remote_heat_request)
            print ("Heat Remote")
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

    if (hp_heat || hp_cool)
        pump_ch = true;
    end    

    if (outputs[0] != hp_heat) 
        tasmota.set_power(0, hp_heat)
    end
    if (outputs[1] != hp_cool)
        tasmota.set_power(1, hp_cool)
    end
    if (outputs[2] != valve_livingroom)
        tasmota.set_power(2, valve_livingroom)
    end
    if (outputs[3] != valve_bathroom)
        tasmota.set_power(3, valve_bathroom)
    end
    if (outputs[4] != pump_ch)
        tasmota.set_power(4, pump_ch)
    end
end
tasmota.set_timer(5000,controlheatpump)

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
tasmota.set_timer(5000,sendmodbus)


def mqttheatrequest(topic, idx, data, databytes)
	if (data == "1") 
		remote_heat_request = true;
		print ("Remote Heat Request Active")
	else 
		print ("Remote Heat Request Inactive")
		remote_heat_request = false;
	end
end
mqtt.subscribe("home/TASMOTA-HEATPUMP/berrycmd/heatrequest",mqttheatrequest)


def modbusreceived(value, trigger)
    if (value['DeviceAddress'] == 1)
        if (value['FunctionCode'] == 4)
            if (value['StartAddress'] == 0)
                if (value['Count'] >= 13)
                    print(string.format("Outside Temperature=%.1f",value["Values"][12]*0.1));
                    outside_temperature = value["Values"][12]
                end
            end
        end
    end
end
tasmota.add_rule("ModbusReceived", modbusreceived)


class showsensor
	#- display sensor value in the web UI -#
	def web_sensor()
		import string
		var msg = "{s}Outside Temperature{m}- °C{e}"
		if (outside_temperature != nil)
			msg = string.format(
		          "{s}Outside Temperature{m}%.1f °C{e}",
		           outside_temperature * 0.1)
		end
		tasmota.web_send_decimal(msg)
	end
end
drv = showsensor()
tasmota.add_driver(drv)
