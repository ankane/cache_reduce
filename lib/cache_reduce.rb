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
      hours = TimeRange.new(range: options[:time_range]).expand_start(:hour).step(:hour)

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

    def by_period(period, options = {})
      result = fetch(options)
      time_range = result.keys.first..result.keys.last

      grouped = result.group_by{|k, v| TimeRange.bucket(period, k) }

      final = {}
      TimeRange.new(range: time_range).expand_start(:day).step(:day) do |day|
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
