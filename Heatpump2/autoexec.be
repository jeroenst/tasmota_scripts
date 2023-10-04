# Input List
# 0 = Thermostat
# 3 = Cool/Heat Switch

# Output List
# 0 = Cool
# 1 = Heat

var mode_heat_old = false
var initialized = false
var activatewaittimer = 10000
var deactivatewaittimer = 5000

def control_house_climate()
	var inputs = tasmota.get_switches()
	var outputs = tasmota.get_power()
	var thermostat_active = inputs[0]
	var mode_cool = inputs[3]
	var standby = false;

	var hour = tasmota.time_dump(tasmota.rtc()['local'])['hour']

	if (hour >= 1 && hour < 10)
		standby = true
	end

	if (!thermostat_active || standby)
		activatewaittimer = 0
		if (deactivatewaittimer < 300)
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
	
	tasmota.set_timer(1000,control_house_climate)
end


tasmota.set_timer(10000,control_house_climate)
