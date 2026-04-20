# Input List
# 0 = Thermostat Livingroom
# 1 = Thermostat Bathroom
# 2 = Heat Switch
# 3 = Cool Switch

# Output List
# 0 = Cool
# 1 = Heat
# 2 = DHW
# 3 = Valve Livingroom
# 4 = Valve Bathroom
# 5 = Pump CH
# 6 = Heat/Cool input Thermostat

import mqtt
import string
import json

class HeatPumpController
    var remote_heat_request
    var outside_temperature
    var inlet_temperature
    var outlet_temperature
    var backupheater_temperature
    var boiler_temperature
    var water_pressure
    var compressor_frequency
    var energy_state
    var emergency_stop_active
    var operation_mode
    var modbus_queue
    var send_index
    var energy_state_map
    
    # Store switch states for UI display
    var switchinput_livingroom
    var switchinput_bathroom
    var switchinput_mode_selector
    var remote_heating_request

    # init(): Constructor equivalent in Tasmota Berry. 
    # Sets initial states, defines MQTT subscriptions, and launches cyclic timers.
    def init()
        tasmota.log("HP-Ctrl: Initializing Heat Pump Controller...", 2)
        
        self.remote_heat_request = false
        self.outside_temperature = nil
        self.inlet_temperature = nil
        self.outlet_temperature = nil
        self.backupheater_temperature = nil
        self.boiler_temperature = nil
        self.water_pressure = nil
        self.compressor_frequency = nil
        self.energy_state = nil
        self.emergency_stop_active = false
        self.operation_mode = "Idle"
        self.modbus_queue = []
        self.send_index = 0
        
        # Initialize UI switch labels
        self.switchinput_livingroom = "Off"
        self.switchinput_bathroom = "Off"
        self.switchinput_mode_selector = "Off"
        
        # Mapping for SG Ready / Energy states read from Modbus
        self.energy_state_map = [
            "Not Use", "Forced Off (SG1)", "Normal Operation", 
            "On-Recommendation (SG2)", "On-Command (SG1+2)", 
            "On-Command Step 2", "On-Recommendation Step 1", 
            "Energy Saving", "Super Energy Saving"
        ]

        # MQTT Subscriptions
        mqtt.subscribe("home/TASMOTA-HEATPUMP/berrycmd/heatrequest", def (t, i, p) 
            self.remote_heat_request = (p == "1") 
        end)

        mqtt.subscribe("home/TASMOTA-HEATPUMP/berrycmd/energystate", def (t, i, p) self.mqtt_energy_state(p) end)
        mqtt.subscribe("home/TASMOTA-HEATPUMP/berrycmd/emergencystop", def (t, i, p) self.mqtt_emergency_stop(p) end)
        
        tasmota.add_rule("ModbusReceived", def (value) self.modbus_received(value) end)
        
        tasmota.set_timer(10000, def () self.control_loop() end)
        tasmota.set_timer(2000, def () self.modbus_loop() end)
    end

    # control_loop(): Evaluates logical conditions every 10 seconds.
    # Reads physical switches and sets the relay outputs.
    def control_loop()
        tasmota.set_timer(10000, def () self.control_loop() end)
        
        var inputs = tasmota.get_switches()
        var outputs = tasmota.get_power()
        
        if (!mqtt.connected())
            self.emergency_stop = false
            self.remote_heat_request = false
        end

        # Read physical switch states
        var thermostat_livingroom = inputs[0]
        var thermostat_bathroom   = inputs[1]
        var heating_mode_switch   = inputs[2]
        var cooling_mode_switch   = inputs[3]

        # Update UI labels for switches
        self.switchinput_livingroom = thermostat_livingroom ? "On" : "Off"
        self.switchinput_bathroom = thermostat_bathroom ? "On" : "Off"
        if (heating_mode_switch) self.switchinput_mode_selector = "Heat"
        elif (cooling_mode_switch) self.switchinput_mode_selector = "Cool"
        else self.switchinput_mode_selector = "Off" end

        # Temporary variables for logic
        var heatpump_heating = false
        var heatpump_cooling = false
        var heatpump_dhw = true
        var valve_livingroom = false
        var valve_bathroom = false
        var thermostat_hc_input = false

        # Main logic based on the 3-way switch
        if (heating_mode_switch)
            thermostat_hc_input = false 
            if (thermostat_livingroom) 
                valve_livingroom = true
                heatpump_heating = true 
            end
            if (thermostat_bathroom) 
                valve_bathroom = true
                heatpump_heating = true 
            end
            if (self.remote_heat_request) 
                heatpump_heating = true 
            end
        elif (cooling_mode_switch)
            thermostat_hc_input = true 
            if (thermostat_livingroom) 
                valve_livingroom = true
                heatpump_cooling = true 
            end
        end

        if (self.emergency_stop_active)
            heatpump_heating = false
            heatpump_cooling = false
            heatpump_dhw = false
        end

        if (heatpump_heating) self.operation_mode = "Heating"
        elif (heatpump_cooling) self.operation_mode = "Cooling"
        else self.operation_mode = "Idle" end

        var waterpump_central_heating = (heatpump_heating || heatpump_cooling)

        # Apply Relay outputs
        if (outputs[0] != heatpump_cooling)      tasmota.set_power(0, heatpump_cooling) end
        if (outputs[1] != heatpump_heating)      tasmota.set_power(1, heatpump_heating) end
        if (outputs[2] != heatpump_dhw)      tasmota.set_power(2, heatpump_dhw) end
        if (outputs[3] != valve_livingroom)       tasmota.set_power(3, valve_livingroom) end
        if (outputs[4] != valve_bathroom)         tasmota.set_power(4, valve_bathroom) end
        if (outputs[5] != waterpump_central_heating)   tasmota.set_power(5, waterpump_central_heating) end
        if (outputs[6] != thermostat_hc_input)    tasmota.set_power(6, thermostat_hc_input) end
    end

    # modbus_loop(): Orchestrates Modbus traffic (polls registers or sends commands)
    def modbus_loop()
        tasmota.set_timer(2000, def () self.modbus_loop() end)

        if (size(self.modbus_queue) > 0)
            var command = self.modbus_queue.pop(0)
            tasmota.cmd("modbussend " + command)
            return
        end
        var poll_commands = [
            '{"deviceaddress": 1, "functioncode": 1, "startaddress": 0, "type": "bit", "count": 6}',
            '{"deviceaddress": 1, "functioncode": 2, "startaddress": 0, "type": "bit", "count": 17}',
            '{"deviceaddress": 1, "functioncode": 3, "startaddress": 0, "type": "int16", "count": 10}',
            '{"deviceaddress": 1, "functioncode": 4, "startaddress": 0, "type": "int16", "count": 15}',
            '{"deviceaddress": 1, "functioncode": 4, "startaddress": 16, "type": "int16", "count": 9}'
        ]
        tasmota.cmd("modbussend " + poll_commands[self.send_index])
        self.send_index = (self.send_index + 1) % size(poll_commands)
    end

    def mqtt_energy_state(payload)
        var value = int(payload)
        if (value >= 0 && value <= 8 && size(self.modbus_queue) < 10)
            var command = string.format('{"deviceaddress": 1, "functioncode": 6, "startaddress": 9, "values": [%d]}', value)
            self.modbus_queue.push(command)
        end
    end

    def mqtt_emergency_stop(payload)
        var state = (payload == "1") ? 1 : 0
        if (size(self.modbus_queue) < 10)
            var command = string.format('{"deviceaddress": 1, "functioncode": 5, "startaddress": 4, "values": [%d]}', state)
            self.modbus_queue.push(command)
        end
    end

    # modbus_received(): Parses incoming Modbus JSON responses
    def modbus_received(data)
        if (data != nil && data['DeviceAddress'] == 1)
            var fc = data['FunctionCode']
            var sa = data['StartAddress']
            var val = data['Values']
            if (val != nil)
                if (fc == 1 && sa == 0 && size(val) >= 5) self.emergency_stop_active = (val[4] == 1) end
                if (fc == 3 && sa == 0 && size(val) >= 10) self.energy_state = val[9] end
                if (fc == 4 && sa == 0 && size(val) >= 14)
                    self.inlet_temperature = val[2]
                    self.outlet_temperature = val[3]
                    self.backupheater_temperature = val[4]
                    self.boiler_temperature = val[5]
                    self.outside_temperature = val[12]
                    self.water_pressure = val[13]
                end
                if (fc == 4 && sa == 16 && size(val) >= 8)
                    self.compressor_frequency = val[8]
                end
            end
        end
    end

    # web_sensor(): Injects HTML for real-time status display in the Web UI
    def web_sensor()
        var html = ""
        var mode_color = "white"
        if (self.operation_mode == "Heating") mode_color = "#ffa500" end
        if (self.operation_mode == "Cooling") mode_color = "#00aaff" end
        
        # --- Physical Inputs Section ---
        html += "<hr>"
        html += string.format("{s}Mode Selector{m}%s{e}", self.switchinput_mode_selector)
        html += string.format("{s}Thermostat Living{m}%s{e}", self.switchinput_livingroom)
        html += string.format("{s}Thermostat Bath{m}%s{e}", self.switchinput_bathroom)
        html += string.format("{s}Remote Heat{m}%s{e}", self.remote_heat_request ? "On" : "Off")

        html += string.format("{s}Operation Mode{m}<span style='color:%s;font-weight:bold'>%s</span>{e}", mode_color, self.operation_mode)
        

        # --- Temperatures & Sensors ---
        if (self.outside_temperature != nil) html += string.format("{s}Outside Temp{m}%.1f °C{e}", self.outside_temperature * 0.1) end
        if (self.inlet_temperature != nil) html += string.format("{s}Inlet Temp{m}%.1f °C{e}", self.inlet_temperature * 0.1) end
        if (self.outlet_temperature != nil) html += string.format("{s}Outlet Temp{m}%.1f °C{e}", self.outlet_temperature * 0.1) end
        if (self.backupheater_temperature != nil) html += string.format("{s}Backup Heater{m}%.1f °C{e}", self.backupheater_temperature * 0.1) end
        if (self.boiler_temperature != nil) html += string.format("{s}Boiler Temp{m}%.1f °C{e}", self.boiler_temperature * 0.1) end
        if (self.water_pressure != nil) html += string.format("{s}Water Pressure{m}%.1f bar{e}", self.water_pressure * 0.1) end
        if (self.compressor_frequency != nil) html += string.format("{s}Compressor Frequency{m}%.d Hz{e}", self.compressor_frequency) end
        
        var state_text = (self.energy_state != nil && self.energy_state >= 0 && self.energy_state < size(self.energy_state_map)) ? self.energy_state_map[self.energy_state] : "Unknown"
        html += string.format("{s}Energy State{m}%s (%d){e}", state_text, self.energy_state)
        
        var em_style = (self.emergency_stop_active == true) ? "color:red;font-weight:bold" : ""
        var em_label = self.emergency_stop_active == nil ? "Unknown" : (self.emergency_stop_active ? "ACTIVE" : "Inactive")
        html += string.format("{s}Emergency Stop{m}<span style='%s'>%s</span>{e}", em_style, em_label)
        
        tasmota.web_send_decimal(html)
    end
end

var controller = HeatPumpController()
tasmota.add_driver(controller)
