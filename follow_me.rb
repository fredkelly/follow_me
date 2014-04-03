#!/usr/bin/env ruby

require 'twitter'
require 'highline/import'
require 'yaml'

class Hash
  def symbolize_keys
    inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
  end
end

# time printing helper
def format_time(time)
  hours = time/3600
  minutes = (time/60 - hours*60)
  seconds = (time - (minutes*60 + hours*3600))

  sprintf("%02d:%02d:%02d\n", hours, minutes, seconds)
end

@config = YAML::load_file(File.dirname(__FILE__) + '/config.yml')
@twitter = Twitter::Client.new(@config['twitter'].symbolize_keys)

@followed_ids = YAML::load_file(File.dirname(__FILE__) + '/followed.yml').reverse

if ARGV.first == '-f'
  
  query = ask('Please enter a search query..')
  type = ask('Query type? (mixed, recent or popular)..', Symbol) {|q| q.validate = lambda { |p| ['mixed', 'recent', 'popular'].include?(p) } }
  
  user_ids = @twitter.search(query, count: 100, result_type: type).results.map{|tweet| tweet.user.id}.uniq
  
  limit = ask("Found #{user_ids.size}, please enter a limit (int)..").to_i
  followed = []
  
  # follow user_ids
  user_ids[0..limit-1].each do |id|
    puts "Following #{id}.."
    begin
      followed += @twitter.follow(id)
      puts "followed"
    rescue Twitter::Error::TooManyRequests => error
      print "waiting for #{format_time(error.rate_limit.reset_in)}.."
      sleep(error.rate_limit.reset_in)
      retry
    rescue Twitter::Error => error
      puts "error (#{error}), skipping.."
    end
  end
  
  # save followed
  File.open('./followed.yml', 'w') do |file|
    YAML.dump((@followed_ids + followed.map(&:id)).uniq, file)
  end
  
  puts "Started following (#{followed.size}): #{followed.map(&:name).join(',')}." unless followed.empty?
  puts "Sorry, didn't follow anyone this time." if followed.empty?

elsif ARGV.first == '-u'
  
  limit = ask("How many users do you wish to unfollow (enter #{@followed_ids.size} for all)?").to_i
  unfollowed = []
  
  # CHECK IF THEY ARE FOLLOWING FIRST!!!
  
  # unfollow user_ids
  @followed_ids[0..limit-1].each do |id|
    print "Checking #{id}.."
    begin
      unless @twitter.friendship?(id, @twitter.current_user.id)
        unfollowed += @twitter.unfollow(id)
        puts "unfollowed"
      else
        puts "keeping :)"
      end
    rescue Twitter::Error::TooManyRequests => error
      print "waiting #{format_time(error.rate_limit.reset_in)} seconds.."
      sleep(error.rate_limit.reset_in)
      retry
    rescue Twitter::Error
      puts "error, skipping.."
    end
  end
  
  # save remaining followed
  File.open('./followed.yml', 'w') do |file|
    YAML.dump(@followed_ids - unfollowed.map(&:id), file)
  end
  
  puts "Stopped following (#{unfollowed.size}): #{unfollowed.map(&:name).join(',')}." unless unfollowed.empty?
  puts "Sorry, didn't unfollow anyone this time." if unfollowed.empty?

else
  puts "Please use either -f or -u to follow/unfollow."
end
