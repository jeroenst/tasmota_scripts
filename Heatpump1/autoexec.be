# Input List
# 0 = Thermostat Livingroom
# 1 = Thermostat Kitchen
# 2 = Thermostat Appartment
# 3 = Gas Request from HeatPump
# 6 = Cool/Heat Switch
# 7 = Gas Boiler Override Switch

# Output List
# 0 = valve/pump livingroom
# 1 = valve/pump kitchen
# 2 = valve/pump appartment
# 3 = Gas Boiler Request Heat (when gas_override is active)
# 4 = Heatpump Request Heat
# 5 = Heatpump Request Cool
# 6 = Heatpump Request DHW

var deactivate_timeout = 3600

var gas_override_old = false
var mode_heat_old = false
var initialized = false
var pump_run = false

var deactivatewaittimer_kitchen = deactivate_timeout
var deactivatewaittimer_livingroom = deactivate_timeout
var deactivatewaittimer_appartment = deactivate_timeout

# run_pump enables the pump once a day to prevent them getting stuck
def run_pump()
    if (pump_run)
        tasmota.set_timer(86400000,run_pump) 
        pump_run = false
    else
        tasmota.set_timer(30000,run_pump)
        pump_run = true
    end
end

def control_house_climate()
    var inputs = tasmota.get_switches()
    var outputs = tasmota.get_power()
    var thermostat_livingroom = inputs[0]
    var thermostat_kitchen = inputs[1]
    var thermostat_appartment = inputs[2]
    var gas_request = inputs[3]
    var mode_heat = !inputs[6]
    var gas_override = inputs[7]

    var thermostat_active = false
    var invalid_mode = false

    if (gas_override != gas_override_old || !initialized)
        if (gas_override)
            print ("Gas Boiler Override Activated")
        else
            print ("Gas Boiler Override Deactivated")
        end
        gas_override_old = gas_override
    end

    if ((gas_override && !mode_heat))
        invalid_mode = true
    else 
        invalid_mode = false
    end
        
    if (mode_heat != mode_heat_old || !initialized)
        if (mode_heat)
            print ("Heating Mode Activated")
        else
            if (!invalid_mode) 
                print ("Cooling Mode Activated")
            else
                print ("Invalid Mode Selected (Cool and Gas)")
            end
        end
        mode_heat_old = mode_heat
    end

    if ((thermostat_livingroom == mode_heat) && !invalid_mode)
        thermostat_active = true
		deactivatewaittimer_livingroom = 0
        if (outputs[0] == false) 
            print ("Livingroom Valve/Pump Active")
            tasmota.set_power(0, true)
        end
    else
		if (pump_run)
			if (outputs[0] == false)
				print ("Livingroom Pump Run")
				tasmota.set_power(0, true)
			end
		else 
			if (outputs[0] == true) 
				if (deactivatewaittimer_livingroom < deactivate_timeout)
					if (deactivatewaittimer_livingroom == 0)
						print ("Livingroom Thermostat Deactivated, starting timer")
					end
					deactivatewaittimer_livingroom = deactivatewaittimer_livingroom + 1
					thermostat_active = true
				else	
					print ("Livingroom Valve/Pump Inactive")
					tasmota.set_power(0, false)
				end
			end
		end
	end
    

    if ((thermostat_kitchen == mode_heat) && !invalid_mode)
        thermostat_active = true
		deactivatewaittimer_kitchen = 0
        if (outputs[1] == false) 
            print ("Kitchen Valve/Pump Active")
            tasmota.set_power(1, true)
        end
    else
		if (pump_run)
			if (outputs[1] == false)
				print ("Kitchen Pump Run")
				tasmota.set_power(1, true)
			end
		else 
			if (outputs[1] == true) 
				if (deactivatewaittimer_kitchen < deactivate_timeout)
					if (deactivatewaittimer_kitchen == 0)
						print ("Kitchen Thermostat Deactivated, starting timer")
					end
					deactivatewaittimer_kitchen = deactivatewaittimer_kitchen + 1
					thermostat_active = true
				else	
					print ("Kitchen Valve/Pump Inactive")
					tasmota.set_power(1, false)
				end
			end
		end
    end
    
    if ((thermostat_appartment == mode_heat) && !invalid_mode)
        thermostat_active = true
		deactivatewaittimer_appartment = 0
        if (outputs[2] == false) 
            print ("Appartment Valve/Pump Active")
            tasmota.set_power(2, true)
        end
    else
		if (pump_run)
			if (outputs[2] == false)
				print ("Appartment Pump Run")
				tasmota.set_power(2, true)
			end
		else 
			if (outputs[2] == true) 
				if (deactivatewaittimer_appartment < deactivate_timeout)
					if (deactivatewaittimer_appartment == 0)
						print ("Appartment Thermostat Deactivated, starting timer")
					end
					deactivatewaittimer_appartment = deactivatewaittimer_appartment + 1
					thermostat_active = true
				else
					print ("Appartment Valve/Pump Inactive")
					tasmota.set_power(2, false)
				end
			end
		end
    end
    
    if (thermostat_active)
        if (gas_override)
            if (outputs[4] == true) 
                tasmota.set_power(4, false)
            end
            if (outputs[5] == true) 
                tasmota.set_power(5, false)
            end
            if (mode_heat)
                if (outputs[3] == false) 
                    print ("Requesting heat from Gas Boiler")
                    tasmota.set_power(3, true)
                end
            end
        else
            if (mode_heat)
                if (outputs[5] == true) 
                    print ("Stopping cool from Heat Pump")
                    tasmota.set_power(5, false)
                end 
                if (outputs[4] == false) 
                    print ("Requesting heat from Heat Pump")
                    tasmota.set_power(4, true)
                end
                if (gas_request)
                    if (outputs[3] == false) 
                        print ("Requesting heat from Gas Boiler (initiated by heatpump)")
                        tasmota.set_power(3, true)
                    end    
                else
                    if (outputs[3] == true) 
                        print ("Stopping heat from Gas Boiler")
                        tasmota.set_power(3, false)
                    end
                end
            else
                if (outputs[3] == true) 
                    print ("Stopping heat from Gas Boiler")
                    tasmota.set_power(3, false)
                end
                if (outputs[4] == true) 
                    print ("Stopping heat from Heat Pump")
                   tasmota.set_power(4, false)
                end
                if (outputs[5] == false) 
                    print ("Requesting cool from Heat Pump")
                    tasmota.set_power(5, true)
                end
            end
        end
    else
        if (outputs[4] == true) 
            print ("Stopping heat from Heat Pump")
            tasmota.set_power(4, false)
        end
        if (outputs[5] == true) 
            print ("Stopping cool from Heat Pump")
            tasmota.set_power(5, false)
        end
        if (outputs[3] == true) 
            print ("Stopping heat from Gas Boiler")
            tasmota.set_power(3, false)
        end
    end
    
    #print(outputs)

    gpio.pin_mode(2,gpio.OUTPUT)
    var led = gpio.digital_read(2)
    if (led == 1) led = 0
    else led = 1
    end
    gpio.digital_write(2,led)
    tasmota.set_timer(1000,control_house_climate)

    initialized=true
end

tasmota.set_timer(10000,control_house_climate)
run_pump()