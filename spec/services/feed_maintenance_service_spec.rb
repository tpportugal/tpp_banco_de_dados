describe FeedMaintenanceService do
  before(:each) do
    @feed_version = create(:feed_version,
      earliest_calendar_date: '2016-01-01',
      latest_calendar_date: '2016-06-01'
    )
    @feed_version.feed.update!(active_feed_version: @feed_version)
  end

  context '.find_next_feed_version' do
    let(:date) { DateTime.now }
    let(:date_earliest) { date - 2.month }
    let(:date_earlier) { date - 1.month }
    let(:date_later) { date + 1.month }
    let(:feed) { create(:feed) }

    it 'import_policy default' do
      fv1 = create(:feed_version, feed: feed, earliest_calendar_date: date_earliest, imported_at: date)
      fv2 = create(:feed_version, feed: feed, earliest_calendar_date: date_earlier, created_at: date + 1.hour)
      feed.import_policy = nil
      feed.active_feed_version = fv1
      feed.save!
      expect(FeedMaintenanceService.find_next_feed_version(feed, date)).to eq(fv2)
    end

    it 'import_policy daily' do
      fv1 = create(:feed_version, feed: feed, earliest_calendar_date: date_earliest, imported_at: date)
      fv2 = create(:feed_version, feed: feed, earliest_calendar_date: date_earlier, created_at: date + 5.hour)
      fv3 = create(:feed_version, feed: feed, earliest_calendar_date: date_earlier, created_at: date + 5.day)
      feed.import_policy = 'daily'
      feed.active_feed_version = fv1
      feed.save!
      expect(FeedMaintenanceService.find_next_feed_version(feed, date)).to eq(fv3)
    end

    it 'import_policy weekly' do
      fv1 = create(:feed_version, feed: feed, earliest_calendar_date: date_earliest, imported_at: date)
      fv2 = create(:feed_version, feed: feed, earliest_calendar_date: date_earlier, created_at: date + 5.hour)
      fv3 = create(:feed_version, feed: feed, earliest_calendar_date: date_earlier, created_at: date + 5.day)
      fv4 = create(:feed_version, feed: feed, earliest_calendar_date: date_earlier, created_at: date + 10.day)
      feed.import_policy = 'weekly'
      feed.active_feed_version = fv1
      feed.save!
      expect(FeedMaintenanceService.find_next_feed_version(feed, date)).to eq(fv4)
    end

    it 'returns the next_feed_version' do
      fv1 = create(:feed_version, feed: feed, earliest_calendar_date: date_earliest)
      fv2 = create(:feed_version, feed: feed, earliest_calendar_date: date_earlier)
      feed.update!(active_feed_version: fv1)
      expect(FeedMaintenanceService.find_next_feed_version(feed, date)).to eq(fv2)
    end

    it 'returns feed_version if same service range but newer than active_feed_version' do
      fv1 = create(:feed_version, feed: feed, earliest_calendar_date: date_earlier)
      fv2 = create(:feed_version, feed: feed, earliest_calendar_date: date_earlier)
      feed.update!(active_feed_version: fv1)
      expect(FeedMaintenanceService.find_next_feed_version(feed, date)).to eq(fv2)
    end

    it 'returns feed_version ignoring feed_versions that begin in the future' do
      fv1 = create(:feed_version, feed: feed, earliest_calendar_date: date_earliest)
      fv2 = create(:feed_version, feed: feed, earliest_calendar_date: date_earlier)
      fv3 = create(:feed_version, feed: feed, earliest_calendar_date: date_later)
      feed.update!(active_feed_version: fv1)
      expect(FeedMaintenanceService.find_next_feed_version(feed, date)).to eq(fv2)
    end

    it 'returns most recently created feed_version if more than 1 result' do
      fv1 = create(:feed_version, feed: feed, earliest_calendar_date: date_earliest)
      fv2 = create(:feed_version, feed: feed, earliest_calendar_date: date_earlier)
      fv3 = create(:feed_version, feed: feed, earliest_calendar_date: date_earlier)
      feed.update!(active_feed_version: fv1)
      expect(FeedMaintenanceService.find_next_feed_version(feed, date)).to eq(fv3)
    end

    it 'returns nil if no active_feed_version' do
      expect(FeedMaintenanceService.find_next_feed_version(feed, DateTime.now)).to be_nil
    end

    it 'returns nil if active_feed_version is most recent' do
      fv0 = create(:feed_version, feed: feed, earliest_calendar_date: date_earlier)
      fv1 = create(:feed_version, feed: feed, earliest_calendar_date: date)
      feed.update!(active_feed_version: fv1)
      expect(FeedMaintenanceService.find_next_feed_version(feed, DateTime.now)).to be_nil
    end

    it 'returns nil if earliest_calendar_date is less than active_feed_version' do
      fv1 = create(:feed_version, feed: feed, earliest_calendar_date: date_earlier)
      fv2 = create(:feed_version, feed: feed, earliest_calendar_date: date_earliest)
      feed.update!(active_feed_version: fv1)
      expect(FeedMaintenanceService.find_next_feed_version(feed, date)).to be_nil
    end
  end

  context '.extend_expired_feed_version' do
    it 'extends a feed' do
      FeedMaintenanceService.extend_expired_feed_version(
        @feed_version,
        extend_from_date: '2016-05-01',
        extend_to_date: '2016-12-31'
      )
      @feed_version.reload
      expect(@feed_version.tags['extend_from_date']).to eq('2016-05-01')
      expect(@feed_version.tags['extend_to_date']).to eq('2016-12-31')
    end

    it 'defaults to -1 month, +1 year' do
      FeedMaintenanceService.extend_expired_feed_version(
        @feed_version
      )
      @feed_version.reload
      expect(@feed_version.tags['extend_from_date']).to eq('2016-05-01')
      expect(@feed_version.tags['extend_to_date']).to eq('2017-06-01')
    end

    it 'skips previously extended feed_versions' do
      @feed_version.tags ||= {}
      @feed_version.tags['extend_from_date'] = '2016-05-01'
      @feed_version.tags['extend_to_date'] = '2016-07-01'
      @feed_version.save!
      updated_at = @feed_version.reload.updated_at
      FeedMaintenanceService.extend_expired_feed_version(
        @feed_version
      )
      @feed_version.reload
      expect(@feed_version.tags['extend_to_date']).to eq('2016-07-01')
    end

    it 'creates an issue for the feed_version' do
      expect(EntityWithIssues.where(entity: @feed_version).count).to eq(0)
      FeedMaintenanceService.extend_expired_feed_version(
        @feed_version,
        extend_from_date: '2016-05-01',
        extend_to_date: '2016-12-31'
      )
      expect(EntityWithIssues.where(entity: @feed_version).count).to eq(1)
      expect(EntityWithIssues.where(entity: @feed_version).first.issue.issue_type).to eq(:feed_version_maintenance_extend)
    end
  end

  context '.enqueue_next_feed_versions' do
    let(:date) { DateTime.now }
    before(:each) do
      @feed = create(:feed)
      @fv1 = create(:feed_version, feed: @feed, earliest_calendar_date: date - 2.months)
      @fv2 = create(:feed_version, feed: @feed, earliest_calendar_date: date - 1.months)
    end

    it 'enqueues next_feed_version' do
      @feed.update!(active_feed_version: @fv1)
      expect {
        FeedMaintenanceService.enqueue_next_feed_versions(date)
      }.to change(FeedEaterWorker.jobs, :size).by(1)
    end

    it 'does not enqueue if no next_feed_version' do
      @fv2.delete
      @feed.update!(active_feed_version: @fv1)
      expect {
        FeedMaintenanceService.enqueue_next_feed_versions(date)
      }.to change(FeedEaterWorker.jobs, :size).by(0)
    end

    it 'allows max_imports' do
      @feed.update!(active_feed_version: @fv1)
      expect {
        FeedMaintenanceService.enqueue_next_feed_versions(date, max_imports: 0)
      }.to change(FeedEaterWorker.jobs, :size).by(0)
    end

    it 'skips if manual_import tag is true' do
      @feed.update!(active_feed_version: @fv1, tags: {manual_import:"true"})
      expect {
        FeedMaintenanceService.enqueue_next_feed_versions(date)
      }.to change(FeedEaterWorker.jobs, :size).by(0)
    end

    it 'does not enqueue if next_feed_version has a feed_version_import attempt' do
      create(:feed_version_import, feed_version: @fv2)
      @feed.update!(active_feed_version: @fv1)
      expect {
        FeedMaintenanceService.enqueue_next_feed_versions(date)
      }.to change(FeedEaterWorker.jobs, :size).by(0)
    end

    it 'creates an issue for the feed_version' do
      @feed.update!(active_feed_version: @fv1)
      expect(EntityWithIssues.where(entity: @fv2).count).to eq(0)
      FeedMaintenanceService.enqueue_next_feed_versions(date)
      expect(EntityWithIssues.where(entity: @fv2).count).to eq(1)
      expect(EntityWithIssues.where(entity: @fv2).first.issue.issue_type).to eq(:feed_version_maintenance_import)
    end
  end

  context 'destroy_feed' do
    before(:each) { @feed, @feed_version = load_feed(feed_version_name: :feed_version_example, import_level: 2) }
    it 'deletes a feed and associated entities' do
      expect(@feed.imported_routes.count).to be > 0
      expect(@feed.imported_stops.count).to be > 0
      expect(@feed.imported_route_stop_patterns.count).to be > 0
      expect(@feed.imported_operators.count).to be > 0
      FeedMaintenanceService.destroy_feed(@feed)
      expect(@feed.imported_routes.count).to eq(0)
      expect(@feed.imported_stops.count).to eq(0)
      expect(@feed.imported_route_stop_patterns.count).to eq(0)
      expect(@feed.imported_operators.count).to eq(0)
      expect(Feed.exists?(@feed.id)).to be_falsy
    end

    it 'does not delete entities also associated with a different feed' do
      feed_version1 = create(:feed_version)
      stop1 = @feed.imported_stops.first
      stop2 = @feed.imported_stops.second
      feed_version1.feed.entities_imported_from_feed.create!(entity: stop1, feed_version: feed_version1)
      FeedMaintenanceService.destroy_feed(@feed)
      expect(Stop.exists?(stop1.id)).to be_truthy
      expect(Stop.exists?(stop2.id)).to be_falsy
    end
  end
end
