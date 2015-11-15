require_relative "job"

require_relative "hydrate_users"
require_relative "update_friend_graph"

module Taxonomist
  module Jobs
    class UpdateUser < Job
      def run(user_id)
        super

        user_info = self.twitter.users_show(user_id: self.user.twitter_id)
        friend_ids = self.twitter.friends_ids(user_id: self.user.twitter_id)

        DB.transaction do
          self.user.update(raw: user_info,
                           friend_ids: Sequel.pg_array(friend_ids))

          existing_ids = Models::User.where(twitter_id: friend_ids)
                                     .select_map(:twitter_id)
          (friend_ids - existing_ids).each do |id|
            Models::User.create(twitter_id: id)
          end

          Jobs::HydrateUsers.enqueue(user_id, friend_ids)
          Jobs::UpdateFriendGraph.enqueue(user_id)
          destroy
        end
      rescue Twitter::RateLimitedError => e
        self.class.enqueue(user_id, run_at: e.reset_at)
      end
    end
  end
end
