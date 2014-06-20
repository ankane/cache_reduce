require "cache_reduce/version"

module CacheReduce
  module Magic

    def all(options = {})
      reduce(fetch(options).values)
    end

    def by_day(options = {})
      result = fetch(options)
      time_range = result.keys.first..result.keys.last
      days = [time_range.first.beginning_of_day]
      while day = days.last + 1.day and time_range.cover?(day)
        days << day
      end
      grouped = result.group_by{|k, v| k.beginning_of_day }

      final = {}
      days.each do |day|
        final[day] = reduce((grouped[day] || []).map(&:last))
      end
      final
    end

    def by_hour(options = {})
      fetch(options)
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
      values = options[:fresh] ? {} : cache_store.read(keys)

      # TODO smarter groups
      range_start = nil
      hours.each_with_index do |hour, i|
        value = values[keys[i]]
        if !value
          range_start = hour
          break
        end
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
            if hour.end_of_hour < Time.now
              cache_store.write(key, v)
            end
            v
          end
      end

      result
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
