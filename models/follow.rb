class Follow < ApplicationRecord
  belongs_to :follower,   polymorphic: true
  belongs_to :followable, polymorphic: true

  before_validation :set_type

  scope :followed_by, -> (follower) { where(
    follower_type: follower.class.table_name.classify,
    follower_id: follower.id)
  }

  scope :following, -> (followable) { where(
    followable_type: followable.class.table_name.classify,
    followable_id: followable.id)
  }

  class << self
    def update_counter(model, counter)
      column_name, _ = counter.first
      model.class.update_counters model.id, counter if model.respond_to?(column_name)
    end

    def follow!(follower, followable)
      unless follows?(follower, followable)
        followee_type = followable.class.name.downcase

        self.create! do |follow|
          follow.follower = follower
          follow.followable = followable
        end
        update_counter(follower, "#{followee_type}_followees_count": +1)
        update_counter(followable, followers_count: +1)
        true
      else
        false
      end
    end

    def unfollow!(follower, followable)
      if follows?(follower, followable)
        followee_type = followable.class.name.downcase

        follow_for(follower, followable).destroy_all
        update_counter(follower, "#{followee_type}_followees_count": -1)
        update_counter(followable, followers_count: -1)
        true
      else
        false
      end
    end

    def follows?(follower, followable)
      !follow_for(follower, followable).empty?
    end

    def followers_relation(followable, klass, opts = {})
      rel = klass.where(id:
        self.select(:follower_id).
          where(follower_type: klass.table_name.classify).
          where(followable_type: followable.class.to_s).
          where(followable_id: followable.id)
      )

      if opts[:pluck]
        rel.pluck(opts[:pluck])
      else
        rel
      end
    end

    def followers(followable, klass, opts = {})
      followers_relation(followable, klass, opts)
    end

    def followables_relation(follower, klass, opts = {})
      rel = klass.where(id:
        self.select(:followable_id).
          where(followable_type: klass.table_name.classify).
          where(follower_type: follower.class.to_s).
          where(follower_id: follower.id)
      )
      if opts[:pluck]
        rel.pluck(opts[:pluck])
      else
        rel
      end
    end

    def followables(follower, klass, opts = {})
      followables_relation(follower, klass, opts)
    end

    def remove_followers(followable)
      self.where(followable_type: followable.class.name.classify).
           where(followable_id: followable.id).destroy_all
    end

    def remove_followables(follower)
      self.where(follower_type: follower.class.name.classify).
           where(follower_id: follower.id).destroy_all
    end

    private

    def follow_for(follower, followable)
      followed_by(follower).following(followable)
    end
  end

  private

  def set_type
    self.followable_type = followable.class.name
  end
end
