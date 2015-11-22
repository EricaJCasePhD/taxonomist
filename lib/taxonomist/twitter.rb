require "faraday"
require "faraday_middleware"

module Taxonomist
  class Twitter
    class RateLimitedError < StandardError
      attr_reader :reset_at

      def initialize(reset_at:)
        @reset_at = reset_at
      end
    end

    attr_reader *%i[ api_key api_secret client ]

    def initialize(api_key:, api_secret:)
      @api_key, @api_secret = api_key, api_secret
    end

    class Authed < Twitter
      attr_reader *%i[ access_token access_token_secret ]

      def initialize(api_key:, api_secret:,
                     access_token:, access_token_secret:)
        super(api_key: api_key, api_secret: api_secret)

        @access_token, @access_token_secret = access_token, access_token_secret

        @client = Faraday.new("https://api.twitter.com/1.1") do |conn|
          conn.request :oauth, consumer_key: api_key,
                               consumer_secret: api_secret,
                               token: access_token,
                               token_secret: access_token_secret
          conn.request :json

          conn.response :raise_error
          conn.response :json, :content_type => /\bjson$/

          conn.adapter Faraday.default_adapter
        end
      end

      def friends_ids(user_id:)
        resp = get("friends/ids.json", user_id: user_id)
        cursored(resp.body["ids"], resp)
      end

      def lists_ownerships(user_id:)
        resp = get("lists/ownerships.json", user_id: user_id)
        cursored(resp.body["lists"], resp)
      end

      def users_lookup(user_ids:)
        user_ids = user_ids.join(?,)
        get("users/lookup.json", user_id: user_ids).body
      end

      def users_show(user_id:)
        get("users/show.json", user_id: user_id).body
      end

      private

      def get(endpoint, **kwargs)
        client.get(endpoint, **kwargs)
      rescue Faraday::ClientError => e
        response = e.response
        if response.status == 429
          reset_at = Time.at(response.headers['x-rate-limit-reset'].to_i)
          raise RateLimitedError.new(reset_at: reset_at)
        end
        raise
      end

      def cursored(obj, resp)
        obj.extend(Cursored)
        obj.next_cursor = resp.body["next_cursor"]
        obj.previous_cursor = resp.body["previous_cursor"]
        obj
      end

      module Cursored
        attr_accessor *%i[ next_cursor previous_cursor ]
      end
    end
  end
end
