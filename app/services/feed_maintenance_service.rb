class FeedMaintenanceService
  include Singleton

  DEFAULT_EXTEND_FROM_DATE = 1.month
  DEFAULT_EXTEND_TO_DATE = 1.year
  DEFAULT_EXPIRED_ON_DATE = 1.week

  def self.find_next_feed_version(feed, date)
    # Find a feed_version where:
    #   1. newer than active_feed_version
    #   2. service begins on or later than active_feed_version
    #   3. service begins on or before specified date
    active_feed_version = feed.active_feed_version
    return unless active_feed_version
    return unless active_feed_version.imported_at

    next_fv = feed.feed_versions
      .where('created_at > ?', active_feed_version.created_at)
      .where('earliest_calendar_date >= ?', active_feed_version.earliest_calendar_date)
      .where('earliest_calendar_date <= ?', date)
      .reorder(earliest_calendar_date: :desc, created_at: :desc)
      .first

    return unless next_fv

    # Feed import policy settings
    policy = feed.import_policy
    days_since_last_import = (next_fv.created_at.to_date - active_feed_version.imported_at.to_date)
    if policy == 'manual'
      return
    elsif policy.nil?
      return next_fv
    elsif policy == 'immediately'
      return next_fv
    elsif policy == 'daily'
      return next_fv if days_since_last_import >= 1
    elsif policy == 'weekly'
      return next_fv if days_since_last_import >= 7
    elsif policy == 'monthly'
      return next_fv if days_since_last_import >= 30 # todo: use calendar month
    elsif policy == 'yearly'
      return next_fv if days_since_last_import >= 365 # todo: use calendar year
    end
  end

  def self.enqueue_next_feed_versions(date, import_level: nil, max_imports: nil)
    # Find feed versions that can be updated
    queue = []
    Feed.find_each do |feed|
      # Enqueue FeedEater job for feed.find_next_feed_version
      # Use the previous import_level, or default to 2
      import_level ||= feed.active_feed_version.try(:import_level) || 2
      # Find the next feed_version
      next_feed_version = find_next_feed_version(feed, date)
      next unless next_feed_version
      # Return if it's been imported before
      next if next_feed_version.feed_version_imports.last
      # Enqueue
      queue << [next_feed_version, import_level]
    end
    # The maximum number of feeds to enqueue
    max_imports ||= queue.size
    log "enqueue_next_feed_versions: found #{queue.size} feeds to update; max_imports = #{max_imports}"
    # Sort by last_imported_at, asc.
    queue = queue.sort_by { |next_feed_version, _| next_feed_version.feed.last_imported_at }.first(max_imports)
    # Enqueue
    queue.each do |next_feed_version, import_level|
      self.enqueue_next_feed_version(next_feed_version, import_level)
    end
  end

  def self.enqueue_next_feed_version(feed_version, import_level)
    feed = feed_version.feed
    log "enqueue_next_feed_versions: adding #{feed.onestop_id} #{feed_version.sha1} #{import_level}"
    # Create issue
    self.create_feed_version_issue(feed_version, :feed_version_maintenance_import)
    # Enqueue
    FeedEaterWorker.perform_async(
      feed.onestop_id,
      feed_version.sha1,
      import_level
    )
  end

  def self.extend_expired_feed_versions(expired_on_date: nil)
    expired_on_date ||= (DateTime.now + DEFAULT_EXPIRED_ON_DATE)
    feed_versions = FeedVersion.where_active.where('latest_calendar_date <= ?', expired_on_date)
    feed_versions.each do |feed_version|
      self.extend_expired_feed_version(feed_version)
    end
  end

  def self.extend_expired_feed_version(feed_version, extend_from_date: nil, extend_to_date: nil)
    previously_extended = (feed_version.tags || {})["extend_from_date"]
    extend_from_date ||= (feed_version.latest_calendar_date - DEFAULT_EXTEND_FROM_DATE)
    extend_to_date ||= (feed_version.latest_calendar_date + DEFAULT_EXTEND_TO_DATE)
    if previously_extended
      # Do nothing
      # log "  already extended, skipping"
    else
      self.extend_feed_version(feed_version, extend_from_date, extend_to_date)
    end
  end

  def self.extend_feed_version(feed_version, extend_from_date, extend_to_date)
    feed = feed_version.feed
    ssp_total = feed_version.imported_schedule_stop_pairs.count
    ssp_updated = feed_version.imported_schedule_stop_pairs.where('service_end_date >= ?', extend_from_date).count
    log "Feed: #{feed.onestop_id}"
    log "  active_feed_version: #{feed_version.sha1}"
    log "    latest_calendar_date: #{feed_version.latest_calendar_date}"
    log "    ssp total: #{ssp_total}"
    log "  extending:"
    log "    extend_from_date: #{extend_from_date}"
    log "    extend_to_date: #{extend_to_date}"
    log "    ssp to update: #{ssp_updated}"
    self.create_feed_version_issue(feed_version, :feed_version_maintenance_extend)
    feed_version.extend_schedule_stop_pairs_service_end_date(extend_from_date, extend_to_date)
  end

  def self.destroy_feed(feed)
    log "destroy_feed: #{feed.onestop_id}"
    # Find entities, in order
    entity_order = [:RouteStopPattern, :StopEgress, :StopPlatform, :Stop, :Route, :Operator]
    onestop_ids = Set.new
    changes = []
    entity_order.each do |entity_type|
      feed.entities_imported_from_feed.where(entity_type: entity_type).find_each do |eiff|
        entity = eiff.entity
        next unless eiff.entity
        next if entity.imported_from_feeds.where('feed_id != ?', feed.id).count > 0
        next if onestop_ids.include?(entity.onestop_id)
        onestop_ids << entity.onestop_id
        log "  destroy: #{entity.onestop_id}"
        changes << to_change(entity, action: :destroy)
      end
    end
    changes << to_change(feed, action: :destroy)
    # Apply changeset
    log "  changeset: create"
    changeset = Changeset.new
    changeset.change_payloads.new(payload: {changes: changes})
    changeset.save!
    log "  changeset: id #{changeset.id}"
    log "  changeset: apply"
    changeset.apply!
    # Delete SSPs
    log "  deleting SSPs"
    feed.imported_schedule_stop_pairs.delete_all
    log "  ... done"
  end

  private

  def self.create_feed_version_issue(feed_version, issue_type)
    # Create issue
    issue = Issue.create!(
      details: "#{issue_type}: #{feed_version.feed.onestop_id} #{feed_version.sha1}",
      issue_type: issue_type,
    )
    issue.entities_with_issues.create!(entity: feed_version)
  end

  def self.to_change(entity, action: :createUpdate, attrs: {})
    {
      :action => action,
      entity.class.name.camelize(:lower) => attrs.merge(onestopId: entity.onestop_id)
    }
  end
end
