describe Api::V1::FeedVersionsController do
  context 'GET index' do
    it 'returns all FeedVersions when no parameters provided' do
      create_list(:feed_version, 2)
      get :index, total: true
      expect_json_types({ feed_versions: :array })
      expect_json({
        feed_versions: -> (feed_versions) {
          expect(feed_versions.length).to eq 2
        },
        meta: {
          total: 2
        }
      })
    end

    it 'filters by SHA1 hash' do
      create_list(:feed_version, 2)
      sha1 = FeedVersion.first.sha1
      get :index, sha1: sha1
      expect_json_types({ feed_versions: :array })
      expect_json({
        feed_versions: -> (feed_versions) {
          expect(feed_versions.length).to eq 1
          expect(feed_versions.first[:sha1]).to eq sha1
        }
      })
    end

    it 'filters by feed Onestop ID' do
      feed1 = create(:feed)
      feed2 = create(:feed)
      feed1_version1 = create(:feed_version, feed: feed1)
      feed2_version1 = create(:feed_version, feed: feed2)
      get :index, feed_onestop_id: feed2.onestop_id
      expect_json_types({ feed_versions: :array })
      expect_json({
        feed_versions: -> (feed_versions) {
          expect(feed_versions.length).to eq 1
          expect(feed_versions.first[:sha1]).to eq feed2_version1.sha1
        }
      })
    end
  end

  context 'PUT update' do
    before(:each) do
      allow(Figaro.env).to receive(:transitland_datastore_auth_token) { 'THISISANAPIKEY' }
      @request.env['HTTP_AUTHORIZATION'] = 'Token token=THISISANAPIKEY'
      @feed_version = create(:feed_version, import_level: 0)
    end

    it 'requires auth key to update' do
      @request.env['HTTP_AUTHORIZATION'] = nil
      put :update, id: @feed_version.sha1
      expect(response.status).to eq(401)
    end

    it 'allows import_level to be changed' do
      import_level = 5
      put :update, id: @feed_version.sha1, feed_version: {import_level: import_level}
      expect(response.status).to eq(200)
      expect_json(import_level: import_level)
      expect(@feed_version.reload.import_level).to eq(import_level)
    end

    it 'disallows editing other attributes' do
      sha1 = @feed_version.sha1
      put :update, id: @feed_version.sha1, feed_version: {sha1: 'asdf'}
      expect(@feed_version.reload.sha1).to eq(sha1)
    end
  end
end