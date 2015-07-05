require 'rubygems'
require 'active_support/core_ext/numeric/time'
require 'watir-webdriver'
require 'headless'
require 'active_support/all'
require 'rest-client'
require 'mail'

class SearchQuery
  def b;  @browser;  end
  def h;  @headless;  end

  def initialize(browser = nil)
    @parsers = ["LanParser"]
    @headles = nil
    @browser = nil
    @trip_duration = 10
    @scope = 200
    @dest = ["SCL-MVD", "SCL-LAX"]
    @alert_price = Hash.new
    @prices = Hash.new
    open_file
    config_email
    #@headless = Headless.new
    #h.start
    #@browser = Watir::Browser.start 'www.google.com'
  end

  def open_file
    @dest = []
    File.open("dest.txt") do |file|
      file.each do |line|
        dest,price = line.gsub("\n", "").split(",")
        price = 150 if price.blank?
        @dest << dest
        @alert_price[dest] = price
      end
    end
  end

  def config_email
    options = { :address              => "smtp.gmail.com",
                :port                 => 587,
                :domain               => 'localhost:3000',
                :user_name            => ENV['GMAIL_USERNAME'],
                :password             => ENV['GMAIL_PASSWORD'],
                :authentication       => 'plain',
                :enable_starttls_auto => true  }

    Mail.defaults do
      delivery_method :smtp, options
    end
  end

  def send_email(msg)
    Mail.deliver do
      to ENV["EMAIL_FARE"]
      from ENV["GMAIL_USERNAME"]
      subject 'price alert'
      body msg
    end
  end

  def start
    @parsers.each do |parser|
      c = Object.const_get(parser)
      c = c.new
      @dest.each do |dest|
        dest_s = dest.split("-")
        next if dest_s.size < 2
        for i in 0..(dest_s.size - 2)
          iterate(c, dest_s[i], dest_s[i + 1])
        end
      end
    end
    p @prices
  end

  def analize
    sorted = @prices.sort_by{|k,v| v.price }
    values = []
    sorted[0..5].each do |val|
      p val.to_s
      p val[1].to_s
      values << val[1].to_s
    end
    send_email(values.join("\n"))
  end

  def iterate(c, orig, dest)
    s_d = Date.today + 10.days
    e_d = s_d + @trip_duration.days
    while Date.today + @scope > s_d
      values = c.get_values(orig, dest, s_d, e_d)
      send_email("ORIG #{orig}-#{dest}: #{s_d} #{e_d} #{values}") if values[0] < (@alert_price["#{orig}-#{dest}"] || 120)
      add_price(*values)
      s_d = s_d + c.step_days.days
      e_d = s_d + @trip_duration.days
      sleep 0.2
    end
  end

  def add_price(price, url, orig, dest, date1, date2)
    return if price.blank?
    if @prices["#{orig}-#{dest}"].blank?
      @prices["#{orig}-#{dest}"] = PriceResult.new(price,url,orig,dest,date1,date2)
    else
      @prices["#{orig}-#{dest}"].update(price,url,orig,dest,date1,date2)
    end
  end
end

class PriceResult
  def to_s
    "#{@price} ####  #{@url} #### #{@orig}-#{@dest} #{@date1} #{@date2}"
  end
  def price; @price; end
  def initialize(price, url, orig, dest, date1, date2)
    @price = price
    @url = url
    @orig = orig
    @dest = dest
    @date1 = date1
    @date2 = date2
  end
  def update(price,url,orig,dest,date1,date2)
    return if price.blank?
    if @price.blank? || @price > price
      @price = price
      @url = url
      @orig = orig
      @dest = dest
      @date1 = date1
      @date2 = date2
    end
  end
end

class PriceParser
  @browser = nil
  @headless = nil
  @step_days = 1

  def b;  @browser;  end
  def h;  @headless;  end
  def initialize(browser = nil)
    if browser
      @browser = browser
    else
      #@headless = Headless.new
      #h.start
      #@browser = Watir::Browser.start 'www.google.com'
    end
  end
end

class LanParser < PriceParser
  def step_days; return @step_days; end
  def initialize(url = nil)
    super
    @step_days = 7
  end
  def get_values(orig, dest, date1, date2)
    json = JSON.parse(RestClient.get get_url(orig, dest, date1, date2)) rescue nil
    price = 999999999999
    url = get_public_url(orig, dest, date1, date2)
    query =  json['data']['recomendations']['data'] rescue []
    query.each do |data|
      price2 = data['fare']['passengerMap']['adult']['amount'].to_i rescue price
      if price2 < price
        price = price2
        date1 = data['departure']['destination']['date']
        date2 = data['regress']['destination']['date']
      end
    end
    return price, url, orig, dest, date1, date2
  end
  def parse_date(date)
    return date.strftime("%d/%m/%Y")
  end
  def get_url(orig, dest, date, end_date = nil)
    end_date  = date + 10.days if end_date.blank?
    url = "http://booking.lan.com/ws/booking/quoting/fares_calendar/2.6/rest/get_calendar/%7B%22language%22:%22es%22,%22country%22:%22cl%22,%22portal%22:%22personas%22,%22application%22:%22compra_normal%22,%22section%22:%22step2%22,%22origin%22:%22#{orig}%22,%22destination%22:%22#{dest}%22,%22departureDate%22:%22#{date.strftime("%Y-%m-%d")}%22,%22returnDate%22:%22#{end_date.strftime("%Y-%m-%d")}%22,%22cabin%22:%22Y%22,%22adults%22:%221%22,%22children%22:%220%22,%22infants%22:%220%22,%22roundTrip%22:true%7D"
    return url
  end
  def get_public_url(orig, dest, date, end_date = nil)
    end_date  = date + 10.days if end_date.blank?
    url = "http://booking.lan.com/es_cl/apps/personas/compra?fecha1_dia=#{date.day}&fecha1_anomes=#{date.strftime("%Y-%m")}&fecha2_dia=#{end_date.day}&fecha2_anomes=#{end_date.strftime("%Y-%m")}&otras_ciudades=&num_segmentos_interfaz=2&tipo_paso1=caja&rand_check=7345.031360164285&from_city2=#{dest}&to_city2=#{orig}&auAvailability=1&ida_vuelta=ida_vuelta&vuelos_origen=Santiago%20de%20Chile,%20Chile%20(SCL)&from_city1=#{orig}&vuelos_destino=Bogot%C3%A1,%20Colombia%20(BOG)&to_city1=#{dest}&flex=1&vuelos_fecha_salida=10/JUL/2015&vuelos_fecha_salida_ddmmaaaa=#{parse_date(date)}&vuelos_fecha_regreso=26/JUL/2015&vuelos_fecha_regreso_ddmmaaaa=#{end_date.strftime("%d/%m/%Y")}&cabina=Y&nadults=1&nchildren=0&ninfants=0"
    return url
  end
end
a = SearchQuery.new
a.start
a.analize
