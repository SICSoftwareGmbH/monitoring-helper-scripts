#!/usr/bin/env ruby
# Read list of all hosts from InfluxDB and checks if dashboard exists for host,
# if a dashboard is missing a new one is created based on a template.
#
# Author: Florian Schwab <florian.schwab@sic.software>

require 'optparse'
require 'net/http'
require 'net/https'
require 'json'
require 'influxdb'

# CLI
class CLI
  def initialize
    @options = {}

    OptionParser.new do |opts|
      opts.on('--template [TEMPLATE]') { |v| @options[:template] = v }
      opts.on('--host-var [HOST_VAR]') { |v| @options[:host_var] = v }
      opts.on('--chronograf-url [URL]') { |v| @options[:chronograf_url] = v }
      opts.on('--influxdb-url [URL]') { |v| @options[:influxdb_url] = v }
      opts.on('--influxdb-db [DB]') { |v| @options[:influxdb_db] = v }
      opts.on('--influxdb-username [USERNAME]') { |v| @options[:influxdb_username] = v }
      opts.on('--influxdb-password [PASSWORD]') { |v| @options[:influxdb_password] = v }
    end.parse!

    @args = ARGV
  end

  def execute
    case @args[0]
    when 'create-missing'
      create_missing_dashboards(@options[:template])
    when 'create'
      create_dashboard(@options[:template], @args[1])
    when 'update'
      update_dashboard(@options[:template], @args[1], @args[2])
    else
      print("Invalid action '#{@args[0]}'\n")
    end
  end

  private

  def create_missing_dashboards(template)
    (sensu_hosts - chronograf_hosts).each do |host|
      create_dashboard(template, host)
    end
  end

  def create_dashboard(template, host)
    data = dashboard_from_template(template, host, host)

    if dashboard_create(data)
      print("Dashboard created: #{host}\n")
    else
      print("Failed to create dashboard: #{host}\n")
    end
  end

  def update_dashboard(template, id, host)
    data = dashboard_from_template(template, host, host)

    dashboard_update(id, data)

    print("Dashboard updated (#{id}): #{host}\n")
  end

  def influxdb
    @influxdb ||= InfluxDB::Client.new(@options[:influxdb_db],
                                       url: @options[:influxdb_url],
                                       username: @options[:influxdb_username],
                                       password: @options[:influxdb_password])
  end

  def sensu_hosts
    query = 'SHOW TAG VALUES ON "' + @options[:influxdb_db] + '" WITH KEY = "sensu_entity_name"'

    influxdb.query(query).map do |key|
      key['values'].select { |v| v['key'] == 'sensu_entity_name' }
                   .map { |v| v['value'] }
    end.inject(:+).uniq
  end

  def chronograf_uri(*path)
    URI.parse(File.join(@options[:chronograf_url], '/chronograf/v1', *path))
  end

  def chronograf_dashboards
    JSON.parse(Net::HTTP.get(chronograf_uri('dashboards')))['dashboards']
  end

  def chronograf_hosts
    chronograf_dashboards.map do |d|
      tmpls = d['templates'].select { |t| t['tempVar'] == @options[:host_var] }

      tmpls.map do |t|
        t['values'].map { |v| v['value'] }
      end.inject(:+)
    end.inject(:+)
  end

  def dashboard_data(id)
    JSON.parse(Net::HTTP.get(chronograf_uri('dashboards', id)))
  end

  def dashboard_from_template(dashboard_id, name, host)
    d = dashboard_data(dashboard_id)

    d['name'] = name
    d['templates'].select { |t| t['tempVar'] == @options[:host_var] }
                  .first['values']
                  .first['value'] = host

    d
  end

  def dashboard_create(data)
    res = Net::HTTP.post(chronograf_uri('dashboards'), data.to_json)

    res.code == '201'
  end

  def dashboard_update(id, data)
    res = Net::HTTP.post(chronograf_uri('dashboards', id), data.to_json)

    res.code == '200'
  end
end

CLI.new.execute
