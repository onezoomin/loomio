class Event < ActiveRecord::Base
  include HasTimeframe
  include PrettyUrlHelper

  KINDS = %w[new_discussion discussion_title_edited discussion_description_edited discussion_edited discussion_moved
             new_comment new_motion new_vote motion_close_date_edited motion_name_edited motion_description_edited
             motion_edited motion_closing_soon motion_closed motion_closed_by_user motion_outcome_created
             motion_outcome_updated membership_requested invitation_accepted user_added_to_group user_joined_group
             new_coordinator membership_request_approved comment_liked comment_replied_to user_mentioned invitation_accepted]

  BULK_MAIL_KINDS = %w(new_comment motion_closing_soon motion_closed motion_outcome_created
                       new_discussion new_motion new_vote)

  NOTIFICATION_KINDS = %w(comment_liked motion_closing_soon comment_replied_to user_mentioned membership_requested
                          membership_request_approved user_added_to_group motion_closed motion_closing_soon
                          motion_outcome_created invitation_accepted new_coordinator)

  SINGLE_MAIL_KINDS = %w(comment_replied_to user_mentioned)

  has_many :notifications, dependent: :destroy
  belongs_to :eventable, polymorphic: true
  belongs_to :discussion
  belongs_to :user

  scope :sequenced, -> { where('sequence_id is not null').order('sequence_id asc') }
  scope :chronologically, -> { order('created_at asc') }

  after_create :call_thread_item_created
  after_destroy :call_thread_item_destroyed

  validates_inclusion_of :kind, :in => KINDS
  validates_presence_of :eventable

  acts_as_sequenced scope: :discussion_id, column: :sequence_id, skip: lambda {|e| e.discussion.nil? || e.discussion_id.nil? }

  def active_model_serializer
    "Events::#{eventable.class.to_s.split('::').last}Serializer".constantize
  rescue NameError
    Events::BaseSerializer
  end

  def notify!(user, persist: true)
    notifications.build(
      user:               user,
      actor:              notification_actor,
      url:                notification_url,
      translation_values: notification_translation_values
    ).tap { |n| n.save if persist }
  end

  def users_to_notify # overridden for events which have more complicated rules for notifying users
    User.none
  end

  private

  # defines the avatar which appears next to the notification
  def notification_actor
    @notification_actor ||= user || eventable.author
  end

  # defines the link that clicking on the notification takes you to
  def notification_url
    @notification_url ||= case eventable
    when Membership, MembershipRequest then polymorphic_url eventable.group
    else                                    polymorphic_url eventable
    end
  end

  # defines the values that are passed to the translation for notification text
  # by default we infer the values needed from the eventable class,
  # but these can be overridden in the event subclasses if need be
  def notification_translation_values
    { name: notification_actor&.name }.tap do |hash|
      case eventable
      when Comment, CommentVote then hash[:discussion] = eventable.discussion.title
      when Motion               then hash[:proposal]   = eventable.name
      when Discussion           then hash[:discussion] = eventable.title
      when Group                then hash[:group]      = eventable.full_name
      when Membership           then hash[:group]      = eventable.group.full_name
      end
    end
  end

  def call_thread_item_created
    discussion.thread_item_created!(self) if discussion_id.present?
  end

  def call_thread_item_destroyed
    discussion.thread_item_destroyed!(self) if discussion_id.present?
  end
end
