# Input List
# 0 = Thermostat Livingroom

# Output List
# 0 = Heat
# 1 = Pump CH

import mqtt
import string
import json

class HeatPumpController : Driver
    var remote_heat_request
    var outside_temperature
    var inlet_temperature
    var outlet_temperature
    var backupheater_temperature
    var water_pressure
    var water_flowrate
    var compressor_frequency
    var energy_state
    var emergency_stop_active
    var remote_heat_mode
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
    
    # Store switch states for UI display
    var switchinput_livingroom

    # init(): Constructor equivalent in Tasmota Berry. 
    # Sets initial states, defines MQTT subscriptions, and launches cyclic timers.
    def init()
        tasmota.log("HP-Ctrl: Initializing Heat Pump Controller...", 2)
        
        self.remote_heat_request = false
        self.outside_temperature = nil
        self.inlet_temperature = nil
        self.outlet_temperature = nil
        self.backupheater_temperature = nil
        self.water_pressure = nil
        self.water_flowrate = nil
        self.compressor_frequency = nil
        self.energy_state = nil
        self.emergency_stop_active = false
        self.remote_heat_mode = "switch"
        self.operation_mode = "Idle"
        self.modbus_queue = []
        self.send_index = 0
        self.remote_heating_request = false
        self.circuit1_shift = nil
        self.output_power = nil
        self.pump_run = false
        self.mqtt_connected_old = false
        self.circuit1_setpoint = nil
        
        # Initialize UI switch labels
        self.switchinput_livingroom = "Off"
        
        # Mapping for SG Ready / Energy states read from Modbus
        self.energy_state_map = [
            "Not Use", "Forced Off (SG1)", "Normal Operation", 
            "On-Recommendation (SG2)", "On-Command (SG1+2)", 
            "On-Command Step 2", "On-Recommendation Step 1", 
            "Energy Saving", "Super Energy Saving"
        ]

        # MQTT Subscriptions
        mqtt.subscribe("0002/TASMOTA-HEATPUMP/berrycmd/heatrequest", def (t, i, p) self.remote_heat_request = (p == "1") end)
        mqtt.subscribe("0002/TASMOTA-HEATPUMP/berrycmd/energystate", def (t, i, p) self.mqtt_energy_state(p) end)
        mqtt.subscribe("0002/TASMOTA-HEATPUMP/berrycmd/circuit1shift", def (t, i, p) self.mqtt_circuit1_shift(p) end)
        mqtt.subscribe("0002/TASMOTA-HEATPUMP/berrycmd/silentmode", def (t, i, p) self.mqtt_silent_mode(p) end)
        mqtt.subscribe("0002/TASMOTA-HEATPUMP/berrycmd/remotestop", def (t, i, p) self.mqtt_emergency_stop(p) end)
        mqtt.subscribe("0002/TASMOTA-HEATPUMP/berrycmd/heatmode", def (t, i, p) self.mqtt_heat_mode(p) end)
        
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

        # Update UI labels for switches
        self.switchinput_livingroom = thermostat_livingroom ? "On" : "Off"

        # Temporary variables for logic
        var heatpump_heating = false
        var valve_livingroom = false
        
        # If thermostat livingroom is on, start heating
        if (thermostat_livingroom) 
            valve_livingroom = true
            heatpump_heating = true 
        end

        if (self.emergency_stop_active)
            heatpump_heating = false
        end

        if (heatpump_heating) self.operation_mode = "Heating"
        else self.operation_mode = "Idle" end

        var waterpump_central_heating = (heatpump_heating || self.pump_run)

        # Apply Relay outputs
        if (outputs[0] != heatpump_heating) tasmota.set_power(0, heatpump_heating) end
        if (outputs[1] != waterpump_central_heating) tasmota.set_power(1, waterpump_central_heating) end
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
            '{"deviceaddress": 1, "functioncode": 4, "startaddress": 16, "type": "int16", "count": 9}',
            '{"deviceaddress": 1, "functioncode": 4, "startaddress": 34, "type": "int16", "count": 18}'
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

    def mqtt_emergency_stop(payload)
        var value = int(payload) == 1
        self.emergency_stop_active = value
        if (size(self.modbus_queue) < 10)
            var command = string.format('{"deviceaddress": 1, "functioncode": 5, "startaddress": 5, "type": "bit", "count": 1, "values": [%d]}', value)
            self.modbus_queue.push(command)
        end
    end

    def mqtt_heat_mode(payload)
        if (payload == "heat")
          self.remote_heat_mode = "heat"
        end
        if (payload == "stop")
          self.remote_heat_mode = "stop"
        end
        if (payload == "switch")
          self.remote_heat_mode = "switch"
        end
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
                    self.energy_state = val[9]
                end
                if (fc == 4 && sa == 0 && size(val) >= 14)
                    self.inlet_temperature = val[2]
                    self.outlet_temperature = val[3]
                    self.backupheater_temperature = val[4]
                    self.water_flowrate = val[8] != 50 ? val[8] : 0
                    self.outside_temperature = val[12]
                    self.water_pressure = val[13]
                end
                if (fc == 4 && sa == 16 && size(val) >= 9)
                    self.compressor_frequency = val[8]
                end
                if (fc == 4 && sa == 34 && size(val) >= 16)
                    self.output_power = val[15]
                end
            end
        end
    end

    # web_sensor(): Injects HTML for real-time status display in the Web UI
    def web_sensor()
        var html = "<hr>"
        var mode_color = (self.operation_mode == "Heating") ? "#ffa500" : "white"
        
        html += string.format("{s}Operation Mode{m}<span style='color:%s;font-weight:bold'>%s</span>{e}", mode_color, self.operation_mode)

        html += string.format("{s}Thermostat Livingroom{m}%s{e}", self.switchinput_livingroom)
        html += string.format("{s}Remote Heat Request{m}%s{e}", self.remote_heat_request ? "On" : "Off")
        
        # Energy State
        if (self.energy_state != nil)
            var state_text = (self.energy_state >= 0 && self.energy_state < size(self.energy_state_map)) ? self.energy_state_map[self.energy_state] : "Unknown"
            html += string.format("{s}Energy State{m}%s (%d){e}", state_text, self.energy_state)
        else
            html += "{s}Energy State{m}-{e}"
        end
        
        var em_style = (self.emergency_stop_active) ? "color:red;font-weight:bold" : ""
        var em_label = (self.emergency_stop_active) ? "ACTIVE" : "Inactive"
        html += string.format("{s}Emergency Stop{m}<span style='%s'>%s</span>{e}", em_style, em_label)

        mode_color = (self.remote_heat_mode == "stop") ? "red" : (self.remote_heat_mode == "heat") ? "#ffa500" : "white"
        em_style = (mode_color != "white") ? "color:" + mode_color + ";font-weight:bold" : ""
        html += string.format("{s}Remote Heat Mode{m}<span style='%s'>%s</span>{e}", em_style, self.remote_heat_mode)

        # Temperatures & Sensors with "-" fallback
        html += string.format("{s}Circuit 1 Setpoint{m}%s{e}", self.circuit1_setpoint != nil ? string.format("%d °C", self.circuit1_setpoint * 0.1) : "-")
        html += string.format("{s}Circuit1 Shift{m}%s{e}", self.circuit1_shift != nil ? string.format("%d °C", self.circuit1_shift) : "-")
        html += string.format("{s}Inlet Temperature{m}%s{e}", self.inlet_temperature != nil ? string.format("%.1f °C", self.inlet_temperature * 0.1) : "-")
        html += string.format("{s}Outlet Temperature{m}%s{e}", self.outlet_temperature != nil ? string.format("%.1f °C", self.outlet_temperature * 0.1) : "-")
        html += string.format("{s}Water Pressure{m}%s{e}", self.water_pressure != nil ? string.format("%.1f bar", self.water_pressure * 0.1) : "-")
        html += string.format("{s}Water Flowrate{m}%s{e}", self.water_flowrate != nil ? string.format("%.1f l/min", self.water_flowrate * 0.1) : "-")
        html += string.format("{s}Compressor{m}%s{e}", self.compressor_frequency != nil ? string.format("%d Hz", self.compressor_frequency) : "-")
        html += string.format("{s}Output Power{m}%s{e}", self.output_power != nil ? string.format("%d W", self.output_power) : "-")
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
            self.mqtt_heat_mode("switch")
            self.remote_heat_request = false
            self.mqtt_energy_state(2)
        end    
    end
end

var controller = HeatPumpController()
tasmota.add_driver(controller)
