#-
 - European/Dutch Smartmeter P1 Driver (ESMR/DSMR) written in Berry
 -
 - https://www.netbeheernederland.nl/_upload/Files/Slimme_meter_15_a727fce1f1.pdf
 - https://domoticx.com/p1-poort-slimme-meter-hardware/
 -
 - https://smart-stuff.nl/product/p1-dongel-slimme-meter-esp32/
 -
 -#

 class ESMR
	var serialport
	var electricity_kw_using, electricity_kw_providing
	var electricity_kwh_used_1, electricity_kwh_used_2
	var electricity_kwh_provided_1, electricity_kwh_provided_2
	var electricity_voltage_l1, electricity_voltage_l2, electricity_voltage_l3
	var electricity_current_l1, electricity_current_l2, electricity_current_l3
	var electricity_kw_using_l1, electricity_kw_using_l2, electricity_kw_using_l3
	var electricity_kw_providing_l1, electricity_kw_providing_l2, electricity_kw_providing_l3
	var gas_m3, gas_datetime
	var sermsg, serline
  
	def init()
		# gpio_rx:4 gpio_tx:5
		serialport = serial(4, 5, 115200, serial.SERIAL_8N1)
	end

	def process_emsr(serline)
		var value = string.split(serline,"(")[1]
		value = string.split(value,")")[0]
		value = string.split(value,"*")[0]
		var value2 = string.split(serline,"(")[2]
		value2 = string.split(value2,"*")[0];

		if (string.count(serline, "1-0:1.8.1") == 1) electricity_kwh_used_1 = number(value)
		if (string.count(serline, "1-0:2.8.1") == 1) electricity_kwh_provided_1 = number(value)
		if (string.count(serline, "1-0:1.8.2") == 1) electricity_kwh_used_2 = number(value)
		if (string.count(serline, "1-0:2.8.1") == 1) electricity_kwh_provided_1 = number(value)
		if (string.count(serline, "1-0:2.8.2") == 1) electricity_kwh_provided_2 = number(value)

		if (string.count(serline, "1-0:1.7.0") == 1) electricity_kw_using = number(value)
		if (string.count(serline, "1-0:2.7.0") == 1) electricity_kw_providing = number(value)

		if (string.count(serline, "1-0:21.7.0") == 1) electricity_kw_using_l1 = number(value)
		if (string.count(serline, "1-0:41.7.0") == 1) electricity_kw_using_l2 = number(value)
		if (string.count(serline, "1-0:61.7.0") == 1) electricity_kw_using_l3 = number(value)

		if (string.count(serline, "1-0:22.7.0") == 1) electricity_kw_providing_l1 = number(value)
		if (string.count(serline, "1-0:42.7.0") == 1) electricity_kw_providing_l2 = number(value)
		if (string.count(serline, "1-0:62.7.0") == 1) electricity_kw_providing_l3 = number(value)

		if (string.count(serline, "1-0:32.7.0") == 1) electricity_voltage_l1 = number(value)
		if (string.count(serline, "1-0:52.7.0") == 1) electricity_voltage_l2 = number(value)
		if (string.count(serline, "1-0:72.7.0") == 1) electricity_voltage_l3 = number(value)

		if (string.count(serline, "1-0:31.7.0") == 1) electricity_current_l1 = number(value)
		if (string.count(serline, "1-0:51.7.0") == 1) electricity_current_l2 = number(value)
		if (string.count(serline, "1-0:71.7.0") == 1) electricity_current_l3 = number(value)

		if (string.count(serline, "0-1:24.2.1") == 1) gas_datetime = value1
		if (string.count(serline, "0-1:24.2.1") == 1) gas_m3 = number(value2)
	end

	def read_esmr()
		import string
		if (serialport.available() > 0)
			serialmsg += serialport.read().asstring()
			var lastlineendpos = 0
			var serialline = ""
			for i:0..size(serialmsg)-1
				if ((serialmsg[i] == 10) || (serialmsg[i] == 13))
					if (serialline != "") process_esmr(serialline)
					serialline = ""
					lastlineendpos = i
				else serialline += serialmsg[i]
			end
			if (i > 0) serialmsg = string.split(serialmsg, i)[1]
		end
	end
  
	#- trigger a read every second -#
	def every_50ms()
		self.read_esmr()
	end
  
	#- display sensor value in the web UI -#
	def web_sensor()
		import string
		var msg = string.format(
			"{s}electricity used 1{m}%.3f kWh{e}"..
			"{s}electricity used 2{m}%.3f kWh{e}"..
			"{s}electricity provided 1{m}%.3f kWh{e}"..
			"{s}electricity provided 2{m}%.3f kWh{e}"..
			"{s}electricity using{m}%.3f kW{e}"..
			"{s}electricity using L1{m}%.3f kW{e}"..
			"{s}electricity using L2{m}%.3f kW{e}"..
			"{s}electricity using L3{m}%.3f kW{e}"..
			"{s}electricity providing{m}%.3f kW{e}"..
			"{s}electricity providing L1{m}%.3f kW{e}"..
			"{s}electricity providing L2{m}%.3f kW{e}"..
			"{s}electricity providing L3{m}%.3f kW{e}"..
			"{s}electricity voltage L1{m}%.3f V{e}"..
			"{s}electricity voltage L2{m}%.3f V{e}"..
			"{s}electricity voltage L3{m}%.3f V{e}"..
			"{s}electricity current L1{m}%.3f A{e}"..
			"{s}electricity current L2{m}%.3f A{e}"..
			"{s}electricity current L3{m}%.3f A{e}"..
			"{s}gas{m}%.3f m3{e}"..
			"{s}gas datetime{m}%s{e}"..
			electricity_kwh_used_1, electricity_kwh_used_2, 
			electricity_kwh_provided_1, electricity_kwh_provided_2, 
			electricity_kw_using, electricity_kw_using_l1, electricity_kw_using_l2, electricity_kw_using_l3, 
			electricity_kw_providing, electricity_kw_providing_l1, electricity_kw_providing_l2, electricity_kw_providing_l3, 
			electricity_voltage_l1, electricity_voltage_l2, electricity_voltage_l3,
			electricity_current_l1, electricity_current_l2, electricity_current_l3, 
			gas_m3, gas_datetime)
		tasmota.web_send_decimal(msg)
	end
  
	#- add sensor value to teleperiod -#
	def json_append()
		import string
		var msg = string.format(
			",\"ESMR\":{\"EU1\":%.3f,\"EU2\":%.3f,\"EP1\":%.3f,\"EP2\":%.3f,"..
			"\"EU\":%.3f,\"EUL1\":%.3f,\"EUL2\":%.3f,\"EUL3\":%.3f,"..
			"\"EP\":%.3f,\"EPL1\":%.3f,\"EPL2\":%.3f,\"EPL3\":%.3f,"..
			"\"EVL1\":%.3f,\"EVL2\":%.3f,\"EVL3\":%.3f,"..
			"\"ECL1\":%.3f,\"ECL2\":%.3f,\"ECL3\":%.3f,"..
	  		"\"G\":%.3f,\"GDT\":%s}",
			electricity_kwh_used_1, electricity_kwh_used_2, 
			electricity_kwh_provided_1, electricity_kwh_provided_2, 
			electricity_kw_using, electricity_kw_using_l1, electricity_kw_using_l2, electricity_kw_using_l3, 
			electricity_kw_providing, electricity_kw_providing_l1, electricity_kw_providing_l2, electricity_kw_providing_l3, 
			electricity_voltage_l1, electricity_voltage_l2, electricity_voltage_l3,
			electricity_current_l1, electricity_current_l2, electricity_current_l3, 
			gas_m3, gas_datetime)
		tasmota.response_append(msg)
	end
end

esmr = esmr()
tasmota.add_driver(esmr)