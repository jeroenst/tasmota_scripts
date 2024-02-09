#-
 - Example of I2C driver written in Berry
 -
 - Support for MPU6886 device found in M5Stack
 - Alternative to xsns_85_mpu6886.ino 
 -#

 class DSMR
	var ser
	var electricity_kw_using, electricity_kw_providing
	var electricity_kwh_used_1, electricity_kwh_used_2
	var electricity_kwh_provided_1, electricity_kwh_provided_2
	var gas_m3, gas_datetime
	var sermsg, serline
  
	def init()
		# gpio_rx:4 gpio_tx:5
		ser = serial(4, 5, 115200, serial.SERIAL_8N1)
	end

	def process_dmsr(serline)
	end

	def read_dsmr()
		import string
		if (ser.available() > 0)
			sermsg += ser.read().asstring()
			for i:0..size(sermsg)-1
				if ((sermsg[i] == 10) || (sermsg[i] == 13))
					process_dmsr(serline)
					serline = ""
				else serline += a[i]
			end
		end
	end
  
	#- trigger a read every second -#
	def every_50ms()
	  self.read_dsmr()
	end
  
	#- display sensor value in the web UI -#
	def web_sensor()
	  import string
	  var msg = string.format(
			   "{s}DSMR electricity using{m}%.3f kW{e}"..
			   "{s}DSMR electricity providing%.3f kW{e}"..
			   "{s}DSMR electricity used 1{m}%.3f kWh{e}"..
			   "{s}DSMR electricity used 2{m}%.3f kWh{e}"..
			   "{s}DSMR electricity provided 1{m}%.3f kWh{e}"..
			   "{s}DSMR electricity provided 2{m}%.3f kWh{e}"..
			   "{s}DMSR gas{m}%.3f m3{e}"..
			   "{s}DSMR gas datetime{m}%s{e}"..
			   electricity_kw_using, electricity_kw_providing, 
			   electricity_kwh_used_1, electricity_kwh_used_2, 
			   electricity_kwh_provided_1, electricity_kwh_provided_2, 
			   gas_m3, gas_datetime)
	  tasmota.web_send_decimal(msg)
	end
  
	#- add sensor value to teleperiod -#
	def json_append()
	  if !self.wire return nil end  #- exit if not initialized -#
	  import string
	  var ax = int(self.accel[0] * 1000)
	  var ay = int(self.accel[1] * 1000)
	  var az = int(self.accel[2] * 1000)
	  var msg = string.format(",\"DSMR\":{\"EU\":%.3f,\"EP\":%.3f,\"EU1\":%.3f,\"EU2\":%.3f,\"EP1\":%.3f,\"EP2\":%.3f,\"G\":%.3f,\"GDT\":%s}",
								electricity_kw_using, electricity_kw_providing, 
								electricity_kwh_used_1, electricity_kwh_used_2, 
								electricity_kwh_provided_1, electricity_kwh_provided_2, 
								gas_m3, gas_datetime)
		tasmota.response_append(msg)
	end
  
  end
  mpu6886 = MPU6886()
  tasmota.add_driver(mpu6886)