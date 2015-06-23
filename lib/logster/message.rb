require 'digest/sha1'

module Logster
  class Message
    LOGSTER_ENV = "_logster_env".freeze
    ALLOWED_ENV = %w{
      HTTP_HOST
      REQUEST_URI
      REQUEST_METHOD
      HTTP_USER_AGENT
      HTTP_ACCEPT
      HTTP_REFERER
      HTTP_X_FORWARDED_FOR
      HTTP_X_REAL_IP
      hostname
      process_id
    }

    attr_accessor :timestamp, :severity, :progname, :message, :key, :backtrace, :count, :env, :protected

    def initialize(severity, progname, message, timestamp = nil, key = nil)
      @timestamp = timestamp || get_timestamp
      @severity = severity
      @progname = progname
      @message = message
      @key = key || SecureRandom.hex
      @backtrace = nil
      @count = 1
      @protected = false
    end

    def to_h
      {
        message: @message,
        progname: @progname,
        severity: @severity,
        timestamp: @timestamp,
        key: @key,
        backtrace: @backtrace,
        count: @count,
        env: @env,
        protected: @protected
      }
    end

    def to_json(opts = nil)
      JSON.fast_generate(to_h, opts)
    end

    def self.from_json(json)
      parsed = ::JSON.parse(json)
      msg = new( parsed["severity"],
            parsed["progname"],
            parsed["message"],
            parsed["timestamp"],
            parsed["key"] )
      msg.backtrace = parsed["backtrace"]
      msg.env = parsed["env"]
      msg.count = parsed["count"]
      msg
    end

    def self.hostname
      @hostname ||= `hostname`.strip! rescue "<unknown>"
    end

    def populate_from_env(env)
      env ||= {}
      env["hostname"] ||= self.class.hostname
      env["process_id"] ||= Process.pid
      @env = Message.populate_from_env(env)
    end

    # in its own method so it can be overridden
    def grouping_hash
      return { message: self.message, severity: self.severity, backtrace: self.backtrace }
    end

    # todo - memoize?
    def grouping_key
      gkey = Digest::SHA1.hexdigest JSON.fast_generate grouping_hash
      puts gkey
      gkey
    end

    def is_similar?(other)
      self.grouping_key == other.grouping_key
    end

    def self.populate_from_env(env)
      env[LOGSTER_ENV] ||= begin
          unless env.include? "rack.input"
            # Not a web request
            return env
          end
          scrubbed = {}
          request = Rack::Request.new(env)
          params = {}
          request.params.each do |k,v|
            if k.include? "password"
              params[k] = "[redacted]"
            else
              params[k] = v && v[0..100]
            end
          end
          scrubbed["params"] = params if params.length > 0
          ALLOWED_ENV.map{ |k|
           scrubbed[k] = env[k] if env[k]
          }
          scrubbed
      end
    end

    def <=>(other)
      time = self.timestamp <=> other.timestamp
      return time if time && time != 0

      self.key <=> other.key
    end

    def =~(pattern)
      case pattern
        when Hash
          IgnorePattern.new(nil, pattern).matches? self
        when String
          IgnorePattern.new(pattern, nil).matches? self
        when Regexp
          IgnorePattern.new(pattern, nil).matches? self
        when IgnorePattern
          pattern.matches? self
        else
          nil
      end
    end

    protected

    def get_timestamp
      (Time.new.to_f * 1000).to_i
    end
  end
end
