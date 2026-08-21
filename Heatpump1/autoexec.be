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

import mqtt
import string
import json

class HeatPumpController : Driver
    var outside_temperature
    var inlet_temperature
    var outlet_temperature
    var backupheater_temperature
    var boiler_temperature
    var water_pressure
    var water_flowrate
    var compressor_frequency
    var energy_state
    var remote_stop_active
    var operation_mode
    var modbus_queue
    var send_index
    var energy_state_map
    var remote_heating_request
    var circuit1_shift
    var output_power
    var pump_run
    var mqtt_connected_old
    var circuit1_setpoint
    var lowwatertemp_heating
    var dhw_setpoint
    
    # Store switch states for UI display
    var switchinput_livingroom
    var switchinput_kitchen
    var switchinput_appartment
    var switchinput_cool_mode
    var switchinput_gas_mode

    # init(): Constructor equivalent in Tasmota Berry. 
    # Sets initial states, defines MQTT subscriptions, and launches cyclic timers.
    def init()
        tasmota.log("HP-Ctrl: Initializing Heat Pump Controller...", 2)
        
        self.outside_temperature = nil
        self.inlet_temperature = nil
        self.outlet_temperature = nil
        self.backupheater_temperature = nil
        self.water_pressure = nil
        self.water_flowrate = nil
        self.compressor_frequency = nil
        self.energy_state = nil
        self.remote_stop_active = false
        self.operation_mode = "Idle"
        self.modbus_queue = []
        self.send_index = 0
        self.circuit1_shift = nil
        self.output_power = nil
        self.pump_run = false
        self.mqtt_connected_old = false
        self.circuit1_setpoint = nil
        self.lowwatertemp_heating = false
        self.dhw_setpoint = nil
        
        # Initialize UI switch labels
        self.switchinput_livingroom = "Off"
        self.switchinput_kitchen = "Off"
        self.switchinput_appartment = "Off"
        self.switchinput_cool_mode = "-"
        self.switchinput_gas_mode = "-"
        
        # Mapping for SG Ready / Energy states read from Modbus
        self.energy_state_map = [
            "Not Use", "Forced Off (SG1)", "Normal Operation", 
            "On-Recommendation (SG2)", "On-Command (SG1+2)", 
            "On-Command Step 2", "On-Recommendation Step 1", 
            "Energy Saving", "Super Energy Saving"
        ]

        # MQTT Subscriptions
        mqtt.subscribe("0006/TASMOTA-HEATPUMP/berrycmd/energystate", def (t, i, p) self.mqtt_energy_state(p) end)
        mqtt.subscribe("0006/TASMOTA-HEATPUMP/berrycmd/circuit1shift", def (t, i, p) self.mqtt_circuit1_shift(p) end)
        mqtt.subscribe("0006/TASMOTA-HEATPUMP/berrycmd/silentmode", def (t, i, p) self.mqtt_silent_mode(p) end)
        mqtt.subscribe("0006/TASMOTA-HEATPUMP/berrycmd/remotestop", def (t, i, p) self.mqtt_remote_stop(p) end)
        
        tasmota.add_rule("ModbusReceived", def (value) self.modbus_received(value) end)
        
        tasmota.set_timer(10000, def () self.control_loop() end)
        tasmota.set_timer(1000, def () self.modbus_loop() end)
        self.run_pump()
    end

    # control_loop(): Evaluates logical conditions every 10 seconds.
    # Reads physical switches and sets the relay outputs.
    def control_loop()
        tasmota.set_timer(10000, def () self.control_loop() end)
        
        var inputs = tasmota.get_switches()
        var outputs = tasmota.get_power()
        
        if (!mqtt.connected() && self.mqtt_connected_old)
          # After 10 minutes of disconnection from mqtt call mqtt_disconnect_timer
          tasmota.set_timer(600000, def () self.mqtt_disconnect_timer() end, 1)
        end
        if (mqtt.connected  && !self.mqtt_connected_old)
          tasmota.remove_timer(1)
        end
        self.mqtt_connected_old = mqtt.connected()
        
        # Read physical switch states
        var thermostat_livingroom = inputs[0]
        var thermostat_kitchen    = inputs[1]
        var thermostat_appartment = inputs[2]
        var heatpump_gas_request  = inputs[3]
        var cool_mode_switch      = inputs[6]
        var gas_mode_switch       = inputs[7]

        # Update UI labels for switches
        self.switchinput_livingroom = thermostat_livingroom ? "On" : "Off"
        self.switchinput_kitchen = thermostat_kitchen ? "On" : "Off"
        self.switchinput_appartment = thermostat_appartment ? "On" : "Off"
        self.switchinput_gas_mode = gas_mode_switch ? "On" : "Off"
        self.switchinput_cool_mode = cool_mode_switch ? "Cool" : "Heat"

        # Temporary variables for logic
        var heatpump_heating = false
        var heatpump_cooling = false
        var valve_livingroom = false
        var valve_kitchen = false
        var valve_appartment = false
        var gas_boiler = false
        
        # Main logic based on the 3-way switch
        if (gas_mode_switch)
            if (thermostat_livingroom) 
                valve_livingroom = true
                gas_boiler = true 
            end
            if (thermostat_kitchen) 
                valve_kitchen = true
                gas_boiler = true 
            end
            if (thermostat_appartment) 
                valve_appartment = true
                gas_boiler = true 
            end
        else
            if (!cool_mode_switch)
                if (thermostat_livingroom) 
                    valve_livingroom = true
                    heatpump_heating = true 
                    if (thermostat_kitchen) 
                end
                    valve_kitchen = true
                    heatpump_heating = true 
                end
                if (thermostat_appartment) 
                    valve_appartment = true
                    heatpump_heating = true 
                end
            elif (cool_mode_switch)
                if (!thermostat_livingroom) 
                    valve_livingroom = true
                    heatpump_cooling = true 
                end
                if (!thermostat_kitchen) 
                    valve_kitchen = true
                    heatpump_cooling = true 
                end
                if (!thermostat_appartment) 
                    valve_appartment = true
                    heatpump_cooling = true 
                end
            end
        end

        if (self.remote_stop_active)
            heatpump_heating = false
            heatpump_cooling = false
            valve_livingroom = false
            valve_kitchen = false
            valve_appartment = false
        end

        if (self.pump_run)
            valve_livingroom = true
            valve_kitchen = true
            valve_appartment = true
        end

        if (heatpump_heating) self.operation_mode = "Heating"
        elif (heatpump_cooling) self.operation_mode = "Cooling"
        else self.operation_mode = "Idle" end

        # To prevent to low water temperature preventing defrost during low outside temperature
        # start heating when inlettemperature is < 18 if the water is still warm enough the heatpump wil not start
        # this overrides emergency stop because a stop could create an emergency
        if (self.inlet_temperature < 18 && self.outside_temperature < 10)
            self.lowwatertemp_heating = true
        end

        if (self.inlet_temperature > 25) 
            self.lowwatertemp_heating = false
        end

        if (self.lowwatertemp_heating)
            heatpump_heating = true
            heatpump_cooling = false
            valve_livingroom = false
            valve_kitchen = false
            valve_appartment = false
        end

        if (heatpump_gas_request)
            gas_boiler = true
        end

        # Apply Relay outputs
        if (outputs[0] != valve_livingroom)      tasmota.set_power(0, valve_livingroom) end
        if (outputs[1] != valve_kitchen)         tasmota.set_power(1, valve_kitchen) end
        if (outputs[2] != valve_appartment)      tasmota.set_power(2, valve_appartment) end
        if (outputs[3] != gas_boiler)            tasmota.set_power(3, gas_boiler) end
        if (outputs[4] != heatpump_heating)      tasmota.set_power(4, heatpump_heating) end
        if (outputs[5] != heatpump_cooling)      tasmota.set_power(5, heatpump_cooling) end
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
            '{"deviceaddress": 1, "functioncode": 4, "startaddress": 0, "type": "int16", "count": 13}',
            '{"deviceaddress": 1, "functioncode": 4, "startaddress": 16, "type": "int16", "count": 9}',
        ]
        tasmota.cmd("modbussend " + poll_commands[self.send_index])
        self.send_index = (self.send_index + 1) % size(poll_commands)
    end

    def mqtt_energy_state(payload)
        var value = int(payload)
        if (value >= 0 && value <= 8 && size(self.modbus_queue) < 10)
            var command = string.format('{"deviceaddress": 1, "functioncode": 6, "startaddress": 9, "type": "int16", "count": 1, "values": [%d]}', value)
            self.modbus_queue.push(command)
        end
    end

    def mqtt_circuit1_shift(payload)
        var value = int(payload)
        if (value >= -20 && value <= 20 && size(self.modbus_queue) < 10)
            var command = string.format('{"deviceaddress": 1, "functioncode": 6, "startaddress": 4, "type": "int16", "count": 1, "values": [%d]}', value)
            self.modbus_queue.push(command)
        end
    end

    def mqtt_silent_mode(payload)
        var value = int(payload) == 1
        if (size(self.modbus_queue) < 10)
            var command = string.format('{"deviceaddress": 1, "functioncode": 5, "startaddress": 2, "type": "bit", "count": 1, "values": [%d]}', value)
            self.modbus_queue.push(command)
        end
    end

    def mqtt_remote_stop(payload)
        var value = int(payload) == 1
        self.remote_stop_active = value
    end

    # modbus_received(): Parses incoming Modbus JSON responses
    def modbus_received(data)
        if (data != nil && data['DeviceAddress'] == 1)
            var fc = data['FunctionCode']
            var sa = data['StartAddress']
            var val = data['Values']
            if (val != nil)
                if (fc == 3 && sa == 0 && size(val) >= 10)
                    self.circuit1_setpoint = val[2]
                    self.circuit1_shift = val[4]
                    self.dhw_setpoint = val[8]
                    self.energy_state = val[9]
                end
                if (fc == 4 && sa == 0 && size(val) >= 13)
                    self.inlet_temperature = val[2]
                    self.outlet_temperature = val[3]
                    self.backupheater_temperature = val[4]
                    self.boiler_temperature = val[5]
                    self.water_flowrate = val[8] != 50 ? val[8] : 0
                    self.outside_temperature = val[12]
                end
                if (fc == 4 && sa == 16 && size(val) >= 9)
                    self.compressor_frequency = val[8]
                end
            end
        end
    end

    # web_sensor(): Injects HTML for real-time status display in the Web UI
    def web_sensor()
        var html = "<hr>"
        var mode_color = (self.operation_mode == "Heating") ? "#ffa500" : ((self.operation_mode == "Cooling") ? "#00aaff" : "white")
        html += string.format("{s}Operation Mode{m}<span style='color:%s;font-weight:bold'>%s</span>{e}", mode_color, self.operation_mode)

        var em_style = (self.remote_stop_active) ? "color:red;font-weight:bold" : ""
        var em_label = (self.remote_stop_active) ? "ACTIVE" : "Inactive"
        html += string.format("{s}Remote Stop{m}<span style='%s'>%s</span>{e}", em_style, em_label)


        html += string.format("{s}Cool Mode Switch{m}%s{e}", self.switchinput_cool_mode)
        html += string.format("{s}Gas Mode Switch{m}%s{e}", self.switchinput_gas_mode)
        html += string.format("{s}Thermostat Livingroom{m}%s{e}", self.switchinput_livingroom)
        html += string.format("{s}Thermostat Kitchen{m}%s{e}", self.switchinput_kitchen)
        html += string.format("{s}Thermostat Appartment{m}%s{e}", self.switchinput_appartment)
        html += string.format("{s}Low Water Temp Heat Request{m}%s{e}", self.lowwatertemp_heating ? "On" : "Off")
        
        # Energy State
        if (self.energy_state != nil)
            var state_text = (self.energy_state >= 0 && self.energy_state < size(self.energy_state_map)) ? self.energy_state_map[self.energy_state] : "Unknown"
            html += string.format("{s}Energy State{m}%s (%d){e}", state_text, self.energy_state)
        else
            html += "{s}Energy State{m}-{e}"
        end
        
        # Temperatures & Sensors with "-" fallback
        html += string.format("{s}Circuit 1 Setpoint{m}%s{e}", self.circuit1_setpoint != nil ? string.format("%.1f °C", self.circuit1_setpoint * 0.1) : "-")
        html += string.format("{s}Circuit1 Shift{m}%s{e}", self.circuit1_shift != nil ? string.format("%d °C", self.circuit1_shift) : "-")
        html += string.format("{s}Inlet Temperature{m}%s{e}", self.inlet_temperature != nil ? string.format("%.1f °C", self.inlet_temperature * 0.1) : "-")
        html += string.format("{s}Outlet Temperature{m}%s{e}", self.outlet_temperature != nil ? string.format("%.1f °C", self.outlet_temperature * 0.1) : "-")
        html += string.format("{s}Water Flowrate{m}%s{e}", self.water_flowrate != nil ? string.format("%.1f l/min", self.water_flowrate * 0.1) : "-")
        html += string.format("{s}Compressor{m}%s{e}", self.compressor_frequency != nil ? string.format("%d Hz", self.compressor_frequency) : "-")
        html += string.format("{s}Outside Temperature{m}%s{e}", self.outside_temperature != nil ? string.format("%.1f °C", self.outside_temperature * 0.1) : "-")

        tasmota.web_send_decimal(html)
    end

    # run_pump enables the pump once a day to prevent them getting stuck
    def run_pump()
        if (self.pump_run)
            tasmota.set_timer(86400000, def () self.run_pump() end)
            self.pump_run = false
        else
            tasmota.set_timer(30000, def () self.run_pump() end)
            self.pump_run = true
        end
    end
    
    def mqtt_disconnected_timer()
        if (!mqtt.connected())
            self.mqtt_emergency_stop(0)
            self.mqtt_dhw_stop(0)
            self.mqtt_heatcool_mode("switch")
            self.remote_heat_request = false
            self.mqtt_energy_state(2)
        end    
    end
end

var controller = HeatPumpController()
tasmota.add_driver(controller)
