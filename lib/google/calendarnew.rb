require 'google/apis/calendar_v3'
require 'googleauth'

APPLICATION_NAME = 'Calendar API'.freeze
SCOPE = Google::Apis::CalendarV3::AUTH_CALENDAR

module Google
  #
  # Calendar is the main object you use to interact with events.
  # use it to find, create, update and delete them.
  #
  class Calendar
    attr_reader :id, :connection

    #
    # Setup and connect to the specified Google Calendar.
    #  the +params+ paramater accepts
    # * :client_id => the client ID that you received from Google after registering your application with them (https://console.developers.google.com/). REQUIRED
    # * :client_secret => the client secret you received from Google after registering your application with them. REQUIRED
    # * :redirect_url => the url where your users will be redirected to after they have successfully permitted access to their calendars. Use 'urn:ietf:wg:oauth:2.0:oob' if you are using an 'application'" REQUIRED
    # * :calendar_id => the id of the calendar you would like to work with (see Readme.rdoc for instructions on how to find yours)
    # * :refresh_token => if a user has already given you access to their calendars, you can specify their refresh token here and you will be 'logged on' automatically (i.e. they don't need to authorize access again). OPTIONAL
    #
    # See Readme.rdoc or readme_code.rb for an explication on the OAuth2 authorization process.
    #
    # ==== Example
    # Google::Calendar.new(:client_id => YOUR_CLIENT_ID,
    #                      :client_secret => YOUR_SECRET,
    #                      :calendar => YOUR_CALENDAR_ID,
    #                      :redirect_url => "urn:ietf:wg:oauth:2.0:oob" # this is what Google uses for 'applications'
    #                     )
    #
    def initialize(params = {}, connection = nil)
      # @connection = Connection.new(
      #   impersonator: params[:impersonator]
      # )
      @impersonator = params[:impersonator]
      @client = client
      @id = params[:calendar]
    end

    def client
      auth = Google::Auth.get_application_default(SCOPE)
      c = auth.dup
      c.sub = @impersonator
      c.fetch_access_token!
      c
    end

    def exist?
      service = Google::Apis::CalendarV3::CalendarService.new
      service.client_options.application_name = APPLICATION_NAME
      service.authorization = @client
      begin
        service.get_calendar(@id)
      rescue Exception => e
        return false if e.to_s.include?('notFound')
        ap e
        exit
      end
      true
    end

    #
    # The URL you need to send a user in order to let them grant you access to their calendars.
    #
    # def authorize_url
    #   @connection.authorize_url
    # end

    #
    # The single use auth code that google uses during the auth process.
    #
    # def auth_code
    #   @connection.auth_code
    # end

    #
    # The current access token.  Used during a session, typically expires in a hour.
    #
    # def access_token
    #   @connection.access_token
    # end

    #
    # The refresh token is used to obtain a new access token.  It remains valid until a user revokes access.
    #
    # def refresh_token
    #   @connection.refresh_token
    # end

    #
    # Convenience method used to streamline the process of logging in with a auth code.
    #
    # def login_with_auth_code(auth_code)
    #   @connection.login_with_auth_code(auth_code)
    # end

    #
    # Convenience method used to streamline the process of logging in with a refresh token.
    #
    # def login_with_refresh_token(refresh_token)
    #   ap @connection
    #   @connection# .login_with_refresh_token(refresh_token)
    # end

    #
    # Find all of the events associated with this calendar.
    #  Returns:
    #   an empty array if nothing found.
    #   an array with one element if only one found.
    #   an array of events if many found.
    #
    def events
      event_lookup
    end

    def events_all(show_deleted = true)
      event_lookup_all(show_deleted)
    end

    #
    # This is equivalent to running a search in the Google calendar web application.
    # Google does not provide a way to specify what attributes you would like to
    # search (i.e. title), by default it searches everything.
    # If you would like to find specific attribute value (i.e. title=Picnic), run a query
    # and parse the results.
    #  Returns:
    #   an empty array if nothing found.
    #   an array with one element if only one found.
    #   an array of events if many found.
    #
    def find_events(query)
      event_lookup("?q=#{query}")
    end

    #
    # Find all of the events associated with this calendar that start in the given time frame.
    # The lower bound is inclusive, whereas the upper bound is exclusive.
    # Events that overlap the range are included.
    #
    # the +options+ parameter accepts
    # :max_results => the maximum number of results to return defaults to 25 the largest number Google accepts is 2500
    # :order_by => how you would like the results ordered, can be either 'startTime' or 'updated'. Defaults to 'startTime'. Note: it must be 'updated' if expand_recurring_events is set to false.
    # :expand_recurring_events => When set to true each instance of a recurring event is returned. Defaults to true.
    #
    #  Returns:
    #   an empty array if nothing found.
    #   an array with one element if only one found.
    #   an array of events if many found.
    #
    def find_events_in_range(start_min, start_max, options = {})
      formatted_start_min = encode_time(start_min)
      formatted_start_max = encode_time(start_max)
      query = "?timeMin=#{formatted_start_min}&timeMax=#{formatted_start_max}#{parse_options(options)}"
      event_lookup(query)
    end

    #
    # Find all events that are occurring at the time the method is run or later.
    #
    # the +options+ parameter accepts
    # :max_results => the maximum number of results to return defaults to 25 the largest number Google accepts is 2500
    # :order_by => how you would like the results ordered, can be either 'startTime' or 'updated'. Defaults to 'startTime'. Note: it must be 'updated' if expand_recurring_events is set to false.
    # :expand_recurring_events => When set to true each instance of a recurring event is returned. Defaults to true.
    #
    #  Returns:
    #   an empty array if nothing found.
    #   an array with one element if only one found.
    #   an array of events if many found.
    #
    def find_future_events(options = {})
      formatted_start_min = encode_time(Time.now)
      query = "?timeMin=#{formatted_start_min}#{parse_options(options)}"
      event_lookup(query)
    end

    #
    # Attempts to find the event specified by the id
    #  Returns:
    #   an empty array if nothing found.
    #   an array with one element if only one found.
    #   an array of events if many found.
    #
    def find_event_by_id(id)
      return nil unless id
      event_lookup("/#{id}")
    end

    #
    # Creates a new event and immediately inserts it.
    # Returns the event
    #
    # ==== Examples
    #   # Use a block
    #   cal.create_event do |e|
    #     e.title = "A New Event"
    #     e.where = "Room 101"
    #   end
    #
    #   # Don't use a block (need to call insert manually)
    #   event  = cal.create_event
    #   event.title = "A New Event"
    #   event.where = "Room 101"
    #   event.insert
    #
    def create_event(&blk)
      setup_event(Event.new, &blk)
    end

    #
    # Looks for the specified event id.
    # If it is found it, updates it's vales and returns it.
    # If the event is no longer on the server it creates a new one with the specified values.
    # Works like the create_event method.
    #
    def find_or_create_event_by_id(id, &blk)
      if id.nil?
        setup_event(Event.new, &blk)
      else
        setup_event(find_event_by_id(id)[0] || Event.new, &blk)
      end
    end

    #
    # inserts the specified event.
    # This is a callback used by the Event class.
    #
    def self.insert_event(cal_id, impersonator, event)
      auth = Google::Auth.get_application_default(SCOPE)
      c = auth.dup
      c.sub = impersonator
      c.fetch_access_token!

      service = Google::Apis::CalendarV3::CalendarService.new
      service.client_options.application_name = APPLICATION_NAME
      service.authorization = c
      event.start = { date_time: DateTime.parse(event.start.dup.utc.to_s).rfc3339.to_s, time_zone: 'America/Chicago' }
      event.end = { date_time: DateTime.parse(event.end.dup.utc.to_s).rfc3339.to_s, time_zone: 'America/Chicago' } if event.end

      result = service.insert_event(cal_id, event)
      result


      # begin
      #   service.insert_event(cal_id, event)
      # rescue Exception => e
      #   # return false if e.to_s.include?('notFound')
      #   return 'Duplicate Warning' if e.to_s.include?('duplicate')
      #   # raise e if e.to_s.include?('Google::Apis::RateLimitError:')
      #   # puts "CALENDARNEW CLASS"
      #   # ap e
      #   # ap event
      #   # raise "INSERT_EVENT EXCEPTION:  #{e}\n\n #{event}"
      # end
    end

    def self.update_event(cal_id, impersonator, event)
      auth = Google::Auth.get_application_default(SCOPE)
      c = auth.dup
      c.sub = impersonator
      c.fetch_access_token!

      service = Google::Apis::CalendarV3::CalendarService.new
      service.client_options.application_name = APPLICATION_NAME
      service.authorization = c
      event.start = { date_time: DateTime.parse(event.start.dup.utc.to_s).rfc3339.to_s, time_zone: 'America/Chicago' }
      event.end = { date_time: DateTime.parse(event.end.dup.utc.to_s).rfc3339.to_s, time_zone: 'America/Chicago' }
      begin
        service.update_event(cal_id, event.id, event)
      rescue Exception => e
        # return false if e.to_s.include?('notFound')
        ap e
        exit
      end
      true
    end

    #
    # Deletes the specified event.
    # This is a callback used by the Event class.
    #
    def delete_event(event)
      send_events_request("/#{event.id}", :delete)
    end

    protected

    #
    # Utility method used to centralize the parsing of common query parameters.
    #
    def parse_options(options) # :nodoc
      options[:max_results] ||=  25
      options[:order_by] ||= 'startTime' # other option is 'updated'
      options[:expand_recurring_events] ||= true
      "&orderBy=#{options[:order_by]}&maxResults=#{options[:max_results]}&singleEvents=#{options[:expand_recurring_events]}"
    end

    #
    # Utility method to centralize time encoding.
    #
    def encode_time(time) #:nodoc:
      time.utc.strftime('%FT%TZ')
    end

    #
    # Utility method used to centralize event lookup.
    #
    def event_lookup(query_string = '') #:nodoc:
      response = send_events_request(query_string, :get)
      events = Event.build_from_google_feed(JSON.parse(response.body), self) || []
      return events if events.empty?
      events.length > 1 ? events : [events[0]]
    rescue Google::HTTPNotFound => msg
      puts msg
      return nil
    end

    def event_lookup_all(show_deleted) #:nodoc:
      events = []
      service = Google::Apis::CalendarV3::CalendarService.new
      service.client_options.application_name = APPLICATION_NAME
      service.authorization = @client

      page_token = nil
      begin
        response = service.list_events(@id, max_results: 2500, show_deleted: show_deleted)

        response.items.each do |e|
         events << e
        end
        if response.next_page_token != page_token
          page_token = response.next_page_token
        else
          page_token = nil
        end
      end while !page_token.nil?

      #       loop do
      #   query_string = "?maxResults=2500&showDeleted=#{show_deleted}"
      #   query_string << "&pageToken=#{page_token}" if page_token
      #   query_string << "&synctoken=#{sync_token}" if sync_token
      #   response = send_events_request(query_string, :get)
      #   json_body = JSON.parse(response.body)
      #   # puts json_body
      #   page_token = json_body['nextPageToken']
      #   sync_token = json_body['nextSyncToken']
      #   last_events = Event.build_from_google_feed(json_body, self)
      #   events.push *last_events
      #   break if page_token.nil?
      # end

      # mine
      # /calendars/activeand.co_9r5783gqvaeohdarasseashufc%40group.calendar.google.com/events&pageToken=CigKGnI2cG0wMWM1Z2t0dTdxODlycGVxN3QwbzZzGAEggIDA86b_7twUGg0IABIAGKjYg8X768MC
      # /calendars/activeand.co_9r5783gqvaeohdarasseashufc%40group.calendar.google.com/events?pageToken=CigKGnI2cG0wMWM1Z2t0dTdxODlycGVxN3QwbzZzGAEggIDA86b_7twUGg0IABIAGKjYg8X768MC
      # return events if events.empty?
      # events.length > 1 ? events : [events[0]]
      return events
    rescue Google::HTTPNotFound => err
      puts err
      return nil
    end

    #
    # Utility method used to centralize event setup
    #
    def setup_event(event) #:nodoc:
      event.calendar = self
      yield(event) if block_given?
      event.insert
      event
    end

    #
    # Wraps the `send` method. Send an event related request to Google.
    #
    def send_events_request(path_and_query_string, method, content = '')
      service = Google::Apis::CalendarV3::CalendarService.new
      service.client_options.application_name = APPLICATION_NAME
      service.authorization = @client

      result = service.insert_event(@id, event)
      # puts("/calendars/#{CGI::escape @id}/events#{path_and_query_string}", method, content)
      # @connection.send("/calendars/#{CGI.escape @id}/events#{path_and_query_string}", method, content)

    end
  end
end
