from datetime import datetime, timedelta
from threading import Thread

from .. import db
from ..models import interaction as interaction
from ..models.user import User
from graph_fetcher import GraphFetcher
from friend_hydrator import FriendHydrator
from update_interactions import UpdateInteractions


class UpdateUser:
    STALE = timedelta(weeks=1)

    # TODO Add jitter
    @classmethod
    def is_stale(cls, user):
        return user.updated_at is None or \
            datetime.now() - user.updated_at > cls.STALE

    def __init__(self, user):
        self.user = user
        self.twitter = self.user.twitter

        self.graph_fetcher = GraphFetcher(self.twitter)
        self.hydrator = FriendHydrator(self.twitter)
        self.interaction_updater = UpdateInteractions(self.twitter)

    def run(self):
        if self.is_stale(self.user):
            GraphFetcher(self.twitter).run(self.user)
            FriendHydrator(self.twitter).run(self.user)

        self.create_users()

        stale_friends = [friend for friend in self.user.friends
                         if self.is_stale(friend)]

        threads = []
        threads.append(self.async(self.graph_fetcher.run, *stale_friends))
        threads.append(self.async(self.hydrator.run, *stale_friends))
        for i in [interaction.Mention, interaction.Favorite, interaction.DM]:
            threads.append(self.async(self.interaction_updater.run,
                                      i,
                                      self.user))

        for thread in threads:
            thread.join()

    def create_users(self):
        '''Since we need two levels of friendships for analysis, friends of the
        target user need to exist in the DB to store their friend_ids.
        '''
        existing_ids = [friend.twitter_id for friend in self.user.friends]
        new_users = [User(twitter_id=id) for id in self.user.friend_ids
                     if id not in existing_ids]
        db.session.add_all(new_users)
        db.session.commit()

    def async(self, task, *args):
        thread = Thread(target=task, args=args)
        thread.daemon = True
        thread.start()
        return thread
