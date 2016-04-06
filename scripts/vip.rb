require 'yaml'

require 'pry'

$LOAD_PATH.unshift(File.expand_path('../../lib', __FILE__))
require 'taxonomist'
include Taxonomist

user_id = 1
list_id = 714925948638875648

user = Models::User[user_id]
twitter = Twitter::Client::Authed.new(
  api_key: ENV.fetch('TWITTER_API_KEY'),
  api_secret: ENV.fetch('TWITTER_API_SECRET'),
  access_token: user.access_token,
  access_token_secret: user.access_token_secret,
)
friends = Hash[
  Models::User.where(twitter_id: user.friend_ids.to_a).map { |u|
    [ u.twitter_id, u ]
  }
]

vips = user.interactions.flat_map {|_, interactions|
  interactions
    .sort_by(&:last)
    .reverse
    .map(&:first)
    .map(&:to_i)
    .map {|id| friends[id] }
    .compact
    .take(0.1 * interactions.size)
}.uniq

mods = YAML.load_file(File.expand_path('../vip.private', __FILE__))
whitelist = friends.values.select {|friend|
  Array(mods['whitelist']).include?(friend.screen_name)
}

vips.concat(whitelist)
vips.delete_if {|vip| mods['blacklist'].include?(vip.screen_name) }

list_members = twitter.lists_members(list_id: list_id)
                      .map {|user| friends[user['id']] }

additions = vips - list_members
removals = list_members - vips

Pry.start

twitter.lists_members_create_all(list_id: list_id,
                                 user_ids: additions.map(&:twitter_id))
twitter.lists_members_destroy_all(list_id: list_id,
                                  user_ids: removals.map(&:twitter_id))
