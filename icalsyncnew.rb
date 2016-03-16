require 'time'
require 'open-uri'
require 'pry'
require 'ostruct'
require 'awesome_print'
require 'fileutils'
require 'logger'

require_relative 'lib/google_calendarnew'
require_relative 'lib/base32/base32'
require_relative 'lib/ical_to_gcal'
require_relative 'config'

module Act
  # Sync
  class Sync
    def initialize(calendar_id, ical_file = nil, debug = false, organizers = nil, impersonator = nil)
      @client_id = RbConfig::CLIENT_ID
      @secret = RbConfig::SECRET
      @token_file = File.expand_path RbConfig::TOKEN_FILE # remove this file to re-generate token
      @calendar_id = calendar_id
      @ical_file = ical_file
      @debug = debug
      @organizers = parse_organizers(organizers)
      @logger = create_logger
      @impersonator = impersonator

      #
      # Create an instance of google calendar.
      #
      fail 'missing option calendar_id' if @calendar_id.nil?

      # check_token
      check_calendar_id
    end

    def create_logger
      user = @organizers[0] unless @organizers.nil?
      cal_log = 'logs/' + user.split('@')[0] + '/' + @ical_file.split('/')[-1]
      dirname = File.dirname(cal_log)
      FileUtils.mkdir_p(dirname) unless File.directory?(dirname)
      Logger.new(File.open(cal_log + '.log', 'a'))
    end

    def check_calendar_id
      fail "#{@calendar_id} does not exist" unless g_cal.exist?
    end

    def parse_organizers(orgs)
      return nil if orgs.nil?
      orgs.split(',')
    end

    #
    # Return a Google Calendar Instance
    #
    def g_cal
      @g_cal ||= Google::Calendar.new(
        calendar: @calendar_id,
        impersonator: @impersonator
      )
    end

    def g_cal_active_events
      g_cal.events_all.select { |e| e.status != 'cancelled' }
    end

    def flatten(a)
      (a.respond_to? :join) ? a.join : a
    end

    def normalize(s)
      flatten(s)
    end

    #
    # Generate an id compatile with Google API
    #
    def gen_id(i_cal_evt)
      Base32.encode(i_cal_evt.uid.to_s + i_cal_evt.recurrence_id.to_s + i_cal_evt.sequence.to_s)
    end

    #
    # Find an event by ID
    #
    def find_g_event_by_id(events, id)
      events.find { |e| e.id == id }
    end

    #
    # Return a ICS Calendar Instance
    #
    def get_i_cal
      fail 'missing ICS file' if @ical_file.nil?
      begin
        file_content = open(@ical_file, &:read)
        icals = Icalendar.parse(file_content)
        puts "Can't proccess ICS file with multiple calendars" && exit(1) if icals.size > 1
        icals.first
      rescue StandardError
        raise ArgumentError.new("Cannot open #{@ical_file}")
      end
    end

    #
    # Test for equality between ICal and GCal instance
    # Used to determine if an event was updated
    #
    def events_are_equal?(a, b)
      return false if a.id != b.id
      return false if a.summary != b.summary
      return false if a.status != b.status
      return false if a.description != b.description
      return false if a.location != b.location
      return false if a.transparency != b.transparency
      return false if a.start != b.start
      return false if a.end != b.end
      # a.attendees ||= []
      # b.attendees ||= []
      # if a.attendees && b.attendees
      # return false if a.attendees.size != b.attendees.size
      # a.attendees.sort! { |m, n| m['email'] <=> n['email'] }
      # b.attendees.sort! { |m, n| m['email'] <=> n['email'] }
      # a.attendees.zip(b.attendees).each do |m, n|
      # return false if m['email'] != n['email']
      # return false if m['responseStatus'] != n['responseStatus']
      # end
      # else # one nil and not the other
      # return false
      # end
      true
    end

    #
    # Check oauth2.0 refresh token.
    # If token_file do not exist, request a new token and ask user for authentication
    #
    def check_token
      if File.exist?(@token_file)
        refresh_token = open(@token_file, &:read).chomp
        g_cal.login_with_refresh_token(refresh_token)
      else
        # A user needs to approve access in order to work with their calendars.
        puts 'Visit the following web page in your browser and approve access.'
        puts g_cal.authorize_url
        puts "\nCopy the code that Google returned and paste it here:"

        # Pass the ONE TIME USE access code here to login and get a refresh token that you can use for access from now on.
        refresh_token = g_cal.login_with_auth_code($stdin.gets.chomp)

        # Save token to TOKEN_FILE
        File.open(@token_file, 'w') { |f| f.write(refresh_token) }
        puts "Token saved to #{@token_file}"
      end
    end

    #
    # Remove all events instance in GCal. Internally set status to 'cancelled' by google.
    #
    def purge
      i = 0
      debug 'Purge events on GCal... '
      g_cal.events_all.each do |e|
        next if e.status == 'cancelled'
        debug "Delete: #{e}"
        e.delete
        i += 1
      end
      debug "Done. #{i} event(s) deleted."
      i
    end

    def parse_rrule(rr)
      return nil if rr.nil? || rr.empty?
      # ap rr
      rrules = []
      rr.each do |r|
        rrule = {}
        # rrule << 'FREQ=' + r.frequency unless r.frequency.nil?
        rrule[:freq] = r.frequency unless r.frequency.nil?
        rrule[:until] = r.until unless r.until.nil?
        rrule[:count] = r.count.to_s unless r.count.nil?
        rrule[:interval] = r.interval.to_s unless r.interval.nil?
        raise 'BY SECOND?\n' + r unless r.by_second.nil?
        raise r unless r.by_minute.nil?
        raise r unless r.by_hour.nil?
        rrule[:byday] = r.by_day.join(',') unless r.by_day.nil?
        raise r unless r.by_month_day.nil? || r.by_month_day.count <= 1
        rrule[:bymonthday] = r.by_month_day.join(',') unless r.by_month_day.nil?
        raise r unless r.by_year_day.nil?
        raise r unless r.by_week_number.nil?
        raise r unless r.by_month.nil? || r.by_month.count <= 1
        rrule[:bymonth] = r.by_month.join(',') unless r.by_month.nil?
        rrule[:bysetpos] = r.by_set_position.join(',') unless r.by_set_position.nil?
        raise r unless r.week_start.nil?
        rrules << 'RRULE:' + rrule.collect { |k, v| "#{k}=#{v}" }.join(';').upcase
      end
      # ap rrules
      rrules
    end

    def parse_organizer(org)
      return nil if org.nil?
      ical_str = org.to_ical('string')
      ical_str.delete!('"')
      organizer = []
      parsed = ical_str.split(';')
      parsed.each do |o|
        /mailto:(.*?)(?:;|\Z)/.match(o) do |m|
          e = m.captures[0] && m.captures[0].downcase
          organizer << e.downcase unless e.include?('\"')
        end
      end
      organizer
    end

    def parse_attendees(att)
      return nil if att.nil? || att.empty?
      skip_list = ['local@host.local']
      response_status_values = {
        'NEEDS-ACTION' => 'needsAction',
        'ACCEPTED' => 'accepted',
        'DECLINED' => 'declined',
        'TENTATIVE' => 'tentative'
      }
      parsed = att.map do |a|
        ical_str = a.to_ical('string')
        ical_str.delete!('"')
        attendee = {}
        # /EMAIL=(.*?)(?:;|\Z)/.match(ical_str) do |m|
        /mailto:(.*?)(?:;|\Z)/.match(ical_str) do |m|
          e = m.captures[0] && m.captures[0].downcase
          next unless e.include?('@wiu.edu')
          next if skip_list.any? { |word| e.include?(word) }
          attendee[:email] = e unless e.include?('\"')
        end
        # email required for google
        next unless attendee[:email]
        /CN=(.*?)(?:;|\Z)/.match(ical_str) do |m|
          attendee[:displayname] = m.captures[0]
        end
        /PARTSTAT=(.*?)(?:;|\Z)/.match(ical_str) do |m|
          value = response_status_values[m.captures[0]]
          attendee[:responsestatus] = value
        end
        attendee[:responsestatus] = 'needsAction' if attendee[:responsestatus].nil?
        attendee
      end
      parsed.any? ? parsed.compact : nil
    end

    #
    # Create GCal event from ICal event
    #
    def g_evt_from_i_evt(i_evt, g_evt)
      g_evt ||= Google::Event.new
      g_evt.id = gen_id i_evt
      g_evt.summary = normalize(i_evt.summary) # if i_evt.respond_to? :summary
      g_evt.attendees = parse_attendees(i_evt.attendee)
      g_evt.description = normalize(i_evt.description)
      g_evt.start = Time.parse(i_evt.dtstart.value_ical)
      g_evt.end = Time.parse(i_evt.dtend.value_ical) if i_evt.dtend
      g_evt.recurrence = parse_rrule(i_evt.rrule)
      g_evt.transparency = normalize i_evt.transp.downcase
      g_evt.status = i_evt.status ? normalize(i_evt.status.downcase) : 'confirmed'
      g_evt.location = normalize i_evt.location
      g_evt
    end

    #
    # Verbose output
    #
    def debug(s)
      return unless @debug
      @logger.info s
      puts s
    end

    #
    # Debugging function
    #
    def compare_debug(a, b)
      puts '---'
      puts "id #{a.id}"
      puts "id #{b.id}"
      puts "desc #{a.description}"
      puts "desc #{b.description}"
      puts "status #{a.status}"
      puts "status #{b.status}"
      puts "title #{a.title}"
      puts "title #{b.title}"
      puts "start_time #{a.start_time}"
      puts "start_time #{b.start_time}"
      puts "end_time #{a.end_time}"
      puts "end_time #{b.end_time}"
      # puts "attendess a #{a.attendees}"
      # puts "attendess b #{b.attendees}"
      # puts "attendees a - b:#{a.attendees - b.attendees}" if a.attendees && b.attendees
      # puts "attendees a count :#{a.attendees.size}" if a.attendees
      # puts "attendees b count :#{b.attendees.size}" if b.attendees
      puts '---'
    end

    #
    # Core funcion
    #
    def sync
      idem = created = updated = restored = removed = cancelled_ics = 0
      # load Google events from API, including deleted.
      g_events = g_cal.events_all

      @ical = get_i_cal
      @ical.events.each do |i_evt|
        organizer = parse_organizer(i_evt.organizer)

        # unless organizers option is empty or event has no organizer
        unless @organizers.nil? || organizer.nil?
          # if arrays don't include any matching organizers, skip event
          next if (@organizers & organizer).empty?
        end

        mock = g_evt_from_i_evt(i_evt, Google::Event.new) # mock object for comparison
        cancelled_ics += 1 if mock.status == 'cancelled'
        # Pick a Google event by ID from google events
        # and remove it from the list
        g_evt = g_events.find { |e| e.id == mock.id }
        g_events.reject! { |e| e.id == g_evt.id } if g_evt
        begin
          if g_evt # Event found
            if !events_are_equal?(mock, g_evt)
              if g_evt.status == 'cancelled'
                debug("Restored:\n")
                restored += 1
              else
                debug("Updated:\n")
                updated += 1
              end
              g_evt_from_i_evt(i_evt, g_evt)
              debug g_evt
              Google::Calendar.update_event(@calendar_id, @impersonator, g_evt)
              # unless g_evt.recurrence.nil?
              #   ap g_evt.recurrence
              #   exit
              # end
              # unless g_evt.attendees.nil?
              #   ap g_evt.attendees
              #   exit
              # end
            else
              idem += 1
            end
          else # Element not found, create
            created += 1
            g_evt = g_evt_from_i_evt(i_evt, g_evt)
            g_evt.calendar = g_cal
            # g_evt.insert
            Google::Calendar.insert_event(@calendar_id, @impersonator, g_evt)
            debug "Created:\n #{g_evt}"

            # unless g_evt.recurrence.nil?
            #   ap g_evt.recurrence
            #   exit
            # end
            # unless g_evt.attendees.nil?
            #   ap g_evt.attendees
            #   exit
            # end
          end
        rescue Google::HTTPRequestFailed => msg
          p msg
          raise msg
        end
      end

      # Delete remaining Google events
      g_events.each do |e|
        next unless e.status != 'cancelled'
        debug "Delete: #{e}"
        e.delete
        removed += 1
      end

      debug "ICAL size: #{@ical.events.size}"
      debug "Idem size: #{idem}"
      debug "Created size: #{created}"
      debug "Updated size: #{updated}"
      debug "Restored size: #{restored}"
      debug "Removed size: #{removed}"
      debug "Cancelled size: #{cancelled_ics}"
      debug "Idem + Created + Updated + Restored: #{idem + created + updated + restored}"
      { idem: idem, created: created, updated: updated, restored: restored, removed: removed,
        cancelled_ics: cancelled_ics, sum: idem + created + updated + restored }
    end
  end
end
