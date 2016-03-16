require 'dotenv'
require_relative 'icalsyncnew'
require 'optparse'

options = OpenStruct.new
OptionParser.new do |opts|
  opts.banner = 'Usage: icalsync [options]'

  opts.on('-f', '--file [ICS_FILE]', 'ICS file to sync: local server path or http[s] url') do |o|
    options.ics_file = o
  end

  opts.on('-c', '--calendar-id CAL_ID', 'Google calendar ID') do |o|
    options.calendar_id = o
  end

  opts.on('-p', '--purge', 'Force removing all Google calendar events and exit') do |o|
    options.purge = o
  end

  opts.on('-o', '--organizers a@here.cm, b@here.com', 'Only sync ical events with these organizers (comma separated list)') do |o|
    options.organizers = o
  end

  opts.on('-i', '--impersonator EMAIL_TO_IMPERSONATE', 'Account to impersonate') do |o|
    options.impersonator = o
  end

  opts.on('-v', '--verbose', 'Verbose output') do |o|
    options.debug = o
  end
end.parse!

Dotenv.load

sync = Act::Sync.new(options.calendar_id, options.ics_file, options.debug, options.organizers, options.impersonator)
if options.purge
  sync.purge
  exit
end
sync.sync
