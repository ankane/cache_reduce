require "cache_reduce/version"

module CacheReduce
  module Magic

    def all(options = {})
      reduce(fetch(options).values)
    end

    %i[hour day week month year].each do |period|
      define_method "by_#{period}" do |options = {}|
        by_period(period, options)
      end
    end

    protected

    def preload(time_range)
    end

    def value(time_range)
      raise "Must define value"
    end

    def reduce(values)
      values.sum
    end

    def key
      self.class.name.underscore
    end

    def cache_store
      @cache_store ||= CacheStore.new
    end

    def fetch(options = {})
      time_range = options[:time_range]

      hours = [time_range.first.beginning_of_hour]
      while hour = hours.last + 1.hour and time_range.cover?(hour)
        hours << hour
      end

      # TODO handle advanced objects as keys
      key = self.key
      key = key.join("/") if key.is_a?(Array)
      keys = hours.map{|h| [key, "hour", h.to_i].join("/") }
      values = options[:recache] ? {} : cache_store.read(keys)

      # TODO smarter groups
      range_start = nil
      hours.each_with_index do |hour, i|
        range_start = hour
        break if !values[keys[i]]
      end

      preload(range_start...hours.last + 1.hour)

      result = {}
      hours.each_with_index do |hour, i|
        key = keys[i]
        result[hour] =
          if values[key]
            values[key]
          else
            v = value(hour...hour + 1.hour)
            if true # hour.end_of_hour < Time.now
              cache_store.write(key, v)
            end
            v
          end
      end

      result
    end

    # from groupdate
    def round_time(period, time)
      time_zone = Time.zone
      day_start = 0
      week_start = 6 # sunday
      time = time.to_time.in_time_zone(time_zone) - day_start.hours

      time =
        case period
        when :second
          time.change(usec: 0)
        when :minute
          time.change(sec: 0)
        when :hour
          time.change(min: 0)
        when :day
          time.beginning_of_day
        when :week
          # same logic as MySQL group
          weekday = (time.wday - 1) % 7
          (time - ((7 - week_start + weekday) % 7).days).midnight
        when :month
          time.beginning_of_month
        else # year
          time.beginning_of_year
        end

      time + day_start.hours
    end

    def by_period(period, options = {})
      result = fetch(options)
      time_range = result.keys.first..result.keys.last

      days = [round_time(period, time_range.first)]
      while day = days.last + 1.send(period) and time_range.cover?(day)
        days << day
      end
      grouped = result.group_by{|k, v| round_time(period, k) }

      final = {}
      days.each do |day|
        final[day] = reduce((grouped[day] || []).map(&:last))
      end
      final
    end

  end

  class CacheStore

    # TODO update interface
    # key, period, hours
    def read(keys)
      # puts "READ: #{keys}"
      values = {}
      redis.mget(*keys).each_with_index do |value, i|
        key = keys[i]
        value = redis.get(key)
        values[key] = value ? JSON.parse("[" + value + "]")[0] : nil
      end
      values
    end

    def write(key, value)
      # puts "WRITE: #{key} #{value}"
      redis.set(key, value.to_json)
    end

    def redis
      @redis ||= Redis.new
    end

  end
end
