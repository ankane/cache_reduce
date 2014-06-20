# CacheReduce

A simple, powerful pattern for caching data

:warning: Work in progress - interface not finalized

## How It Works

1. Cache step - data is cached in small buckets by time
  - Break time range into small buckets
  - Read values from cache
  - Caclulate missing values
  - Cache new values, except the current period

2. Reduce step - group buckets and reduce

Since the current period is always calculated, CacheReduce provides real-time results.

## Examples

### Searches

```ruby
class SearchesCount
  include CacheReduce::Magic

  def value(time_range)
    Search.where(created_at: time_range).count
  end
end
```

Count all searches

```ruby
SearchesCount.all(time_range: time_range)
```

Count searches by day

```ruby
SearchesCount.by_day(time_range: time_range)
```

### New Users

Use the preload method for faster cache warming.

```ruby
class NewUsersCount
  include CacheReduce::Magic

  def preload(time_range)
    @users = User.group_by_hour(:created_at, range: time_range).count
  end

  def value(time_range)
    @users[time_range.first]
  end
end
```

And:

```ruby
NewUsersCount.all(time_range: time_range)
NewUsersCount.by_day(time_range: time_range)
```

### Visitors

Reduce ids instead of numbers - great for creating funnels

```ruby
class VisitorIds
  include CacheReduce::Magic

  def value(time_range)
    Visit.where(created_at: time_range).uniq.pluck(:user_id)
  end

  def reduce(values)
    values.flatten
  end
end
```

### Events

Pass your own arguments

```ruby
class EventCount
  include CacheReduce::Magic

  def initialize(name)
    @name = name
  end

  def key
    ["event", @name]
  end

  def value(time_range)
    Ahoy::Event.where(name: @name, time: time_range).count
  end

end
```

### Reducers

Built-in methods

- all
- by_day
- by_hour

Built-in operations

- sum
- flatten

## Installation

Add this line to your application’s Gemfile:

```ruby
gem 'cache_reduce'
```

## TODO

- more reducer methods - `by_week`, `by_month`, etc.
- custom cache period, not just hours
- more data stores
- better interface
- better readme

## Contributing

Everyone is encouraged to help improve this project. Here are a few ways you can help:

- [Report bugs](https://github.com/ankane/cache_reduce/issues)
- Fix bugs and [submit pull requests](https://github.com/ankane/cache_reduce/pulls)
- Write, clarify, or fix documentation
- Suggest or add new features
