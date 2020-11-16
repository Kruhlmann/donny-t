# frozen_string_literal: true

require 'discordrb'
require 'twitter'

class Donny
  def initialize(options)
    @queue = []
    @last_message_time = 0
    @cooldown = 0.5
    @discord_token = options[:discord_key]
    @twitter_token = options[:twitter_key]
    @twitter_secret = options[:twitter_secret]
    @twitter_bearer_token = options[:twitter_bearer_token]
    @twitter_client = create_twitter_client
    @discord_client = create_discord_client
    @tweet_cache = []
  end

  def start
    start_queue
    start_cache
    start_discord_bot
  end

  def create_twitter_client
    Twitter::REST::Client.new do |config|
      config.consumer_key = @twitter_token
      config.consumer_secret = @twitter_secret
      config.bearer_token = @twitter_bearer_token
    end
  end

  def create_discord_client
    Discordrb::Bot.new token: @discord_token
  end

  def start_discord_bot
    @discord_client.message do |event|
      @queue.unshift(event) if event.message.to_s.include? @discord_client.bot_user.id.to_s
    end
    @discord_client.run
  end

  def auto_paginate_tweets(collection = [], max_id = nil, &block)
    response = yield(max_id)
    raise StandardError if response.nil?

    collection += response
    response.empty? ? collection.flatten : auto_paginate_tweets(collection, response.last.id - 1, &block)
  rescue StandardError => e
    puts("Encountered error #{e}. Sleeping for 5 seconds.")
    sleep 5
    retry
  rescue Twitter::Error::TooManyRequests => e
    puts "Rate limited by twitter. Sleeping for #{e.rate_limit.reset_in} seconds"
    sleep e.rate_limit.reset_in + 1
    retry
  end

  def update_tweet_cache
    @tweet_cache = []
    auto_paginate_tweets do |max_id|
      options = { count: 200, include_rts: true }
      options[:max_id] = max_id unless max_id.nil?
      @tweet_cache += @twitter_client.user_timeline('realdonaldtrump', options)
    end
  end

  def send_newest_message
    event = @queue.pop

    if @tweet_cache.length == 0
      event.respond('The corrupt dems and sleepy Joe are using shenanigans to stop me from tweeting. Give me a minute.')
    else
      puts("Sending random tweet from a pool of #{@tweet_cache.length}")
      tweet = @tweet_cache.sample
      event.respond(tweet.text)
    end
  end

  def process_queue_item
    now = Time.now.to_f
    return if @queue.empty? || now - @last_message_time < @cooldown

    send_newest_message
    @last_message_time = now
  end

  def start_cache
    Thread.new do
      loop do
        update_tweet_cache
        sleep 15 * 60
      end
    end
  end

  def start_queue
    Thread.new do
      loop do
        process_queue_item
        sleep 0.1
      end
    end
  end
end
