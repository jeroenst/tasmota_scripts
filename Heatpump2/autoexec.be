# Input List
# 0 = Thermostat
# 1 = Timeclock
# 3 = Cool/Heat Switch

# Output List
# 0 = Cool
# 1 = Heat

import json
import string

var mode_heat_old = false
var initialized = false
var activatewaittimer = 10000
var deactivatewaittimer = 5000
var standby = 0

def control_house_climate()
	var inputs = tasmota.get_switches()
	var outputs = tasmota.get_power()
	var thermostat_active = inputs[0]
	var mode_cool = inputs[3]

	tasmota.set_timer(1000,control_house_climate)

	# If outside temperature is freezing ignore standby and run heatpump
	# if it is not freezing go to standby if input 1 is low.
	# if dewpoint higher than 16 the stop heatpump when cooling mode is active
	var outside_temperature = nil;
	var outside_dewpoint = nil;
	var sensors=json.load(tasmota.read_sensors())
	if (sensors.find("SHT4X", {}) )
		outside_temperature=sensors['SHT4X']['Temperature']
		outside_dewpoint = sensors['SHT4X']['DewPoint']
		
		if (outside_temperature < 0) 
			standby = 0
		end
		if (outside_temperature > 1)
			standby = !inputs[1]
		end

		if (mode_cool)
			if (outside_dewpoint > 15)
				standby = 1;
			end
			if (outside_dewpoint < 14)
				standby = !inputs[1]
			end		
		end
	else
		standby = !inputs[1]
	end


	if (!thermostat_active || standby)
		activatewaittimer = 0
		if (deactivatewaittimer < 300 && !standby)
			if (deactivatewaittimer == 0)
				print ("Thermostat Off, Deactivate Timer Start")
			end
			deactivatewaittimer = deactivatewaittimer + 1
		else
			if (outputs[0] || outputs[1] || !initialized)
				if (standby) 
					print ("Standby Mode, Heatpump Off")
				else
					print ("Thermostat Off, Heatpump Off")
				end
				tasmota.set_power(0, false)
				tasmota.set_power(1, false)
			end
		end
	elif (!mode_cool && (outputs[0] || !outputs[1]) || !initialized)
		deactivatewaittimer = 0
		if (activatewaittimer < 720)
			if (activatewaittimer == 0)
				print ("Thermostat On, Activate Timer Start")
			end
			activatewaittimer = activatewaittimer + 1
		else
			print ("Thermostat On, Heatpump Heat")
			tasmota.set_power(0, false)
			tasmota.set_power(1, true)
		end
	elif (mode_cool && (!outputs[0] || outputs[1]) || !initialized)
		deactivatewaittimer = 0
		if (activatewaittimer < 600)
			if (activatewaittimer == 0)
				print ("Thermostat On, Activate Timer Start")
			end
			activatewaittimer = activatewaittimer + 1
		else
			print ("Thermostat On, Heatpump Cool")
			tasmota.set_power(0, true)
			tasmota.set_power(1, false)
		end
 	end

	initialized=true
	
    print (string.format("Outside (Temperature:%.1f, Dewpoint:%.1f), Thermostat Active:%d, Mode Cool:%d, Standby:%d, Heating:%d, Cooling:%d, ActivateTimer:%d, Deactivatetimer:%d", outside_temperature, outside_dewpoint, thermostat_active, mode_cool, standby, outputs[1], outputs[0], activatewaittimer, deactivatewaittimer))

end


tasmota.set_timer(10000,control_house_climate)
