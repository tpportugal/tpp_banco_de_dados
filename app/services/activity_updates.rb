class ActivityUpdates
  include Singleton

  def self.updates_since(since=24.hours.ago)
    updates = changesets_created(since) + changesets_updated(since) + changesets_applied(since) + feeds_imported(since) + feeds_versions_fetched(since) + issues_created(since)
    updates.sort_by { |update| update[:at_datetime] }.reverse
  end

  private

  def self.changesets_created(since)
    changesets = Changeset.where("created_at > ?", since).includes(:user)
    updates = changesets.map do |changeset|
      {
        id: "c-#{changeset.id}-criado",
        entity_type: 'changeset',
        entity_id: changeset.id,
        entity_action: 'criado',
        by_user_id: changeset.user.try(:id),
        note: "Changeset ##{changeset.id} criado. Inclui notas: #{changeset.notes}",
        at_datetime: changeset.created_at
      }
    end
    updates  || []
  end

  def self.changesets_updated(since)
    # exclude the creation and application of changesets
    changesets = Changeset.where{
      (updated_at > since) &
      (updated_at != created_at) &
      ((updated_at != applied_at) | (applied_at == nil))
    }.includes(:user)
    updates = changesets.map do |changeset|
      {
        id: "c-#{changeset.id}-atualizado",
        entity_type: 'changeset',
        entity_id: changeset.id,
        entity_action: 'atualizado',
        by_user_id: changeset.user.try(:id),
        note: "Changeset ##{changeset.id} atualizado. Inclui notas: #{changeset.notes}",
        at_datetime: changeset.updated_at
      }
    end
    updates || []
  end

  def self.changesets_applied(since)
    changesets = Changeset.where("applied_at > ?", since).includes(:user)
    updates = changesets.map do |changeset|
      {
        id: "c-#{changeset.id}-aplicado",
        entity_type: 'changeset',
        entity_id: changeset.id,
        entity_action: 'aplicado',
        by_user_id: changeset.user.try(:id),
        note: "Changeset ##{changeset.id} aplicado. Inclui notas: #{changeset.notes}",
        at_datetime: changeset.applied_at
      }
    end
    updates || []
  end

  def self.feeds_imported(since)
    feed_version_imports = FeedVersionImport.where("created_at > ? AND success IS NOT NULL", since)
    updates = feed_version_imports.map do |feed_version_import|
      success_word = feed_version_import.success ? 'com successo' : 'sem successo'
      note = "
        Versão da Feed #{feed_version_import.feed.onestop_id}
        com a hash SHA1 de #{feed_version_import.feed_version.sha1}
        importada #{success_word} no nível #{feed_version_import.import_level}
      ".squish
      {
        id: "fvi-#{feed_version_import.id}-criada",
        entity_type: 'feed',
        entity_id: feed_version_import.feed.onestop_id,
        entity_action: 'importada',
        note: note,
        at_datetime: feed_version_import.created_at
      }
    end
    updates || []
  end

  def self.feeds_versions_fetched(since)
    feed_versions = FeedVersion.where("created_at > ?", since)
    updates = feed_versions.map do |feed_version|
      note = "
        Nova versão da feed #{feed_version.feed.onestop_id}
        com a hash SHA1 de #{feed_version.sha1} buscada.
        Calendário vai de #{feed_version.earliest_calendar_date}
        a #{feed_version.latest_calendar_date}.
      ".squish
      {
        id: "fv-#{feed_version.sha1}-criada",
        entity_type: 'feed',
        entity_id: feed_version.feed.onestop_id,
        entity_action: 'buscada',
        note: note,
        at_datetime: feed_version.created_at
      }
    end
    updates || []
  end

  def self.issues_created(since)
    issue_types = [:feed_version_maintenance_extend, :feed_version_maintenance_import]
    issues = Issue.where(issue_type: issue_types).where('created_at > ?', since)
    updates = issues.map do |issue|
      {
        id: "issue-#{issue.id}-criado",
        entity_type: 'issue',
        entity_id: issue.id,
        entity_action: issue.issue_type,
        note: issue.details,
        at_datetime: issue.created_at
      }
    end
    updates || []
  end

end
