describe Api::V1::IssuesController do

  # TODO: loading this feed each test is slow
  before(:all) do
    load_feed(feed_version_name: :feed_version_example_issues, import_level: 1)
  end
  after(:all) {
    DatabaseCleaner.clean_with :truncation, { except: ['spatial_ref_sys'] }
  }
  let(:user) { create(:user) }
  let(:auth_token) { JwtAuthToken.issue_token({user_id: user.id}) }
  before(:each) do
    @request.env['HTTP_AUTHORIZATION'] = "Bearer #{auth_token}"
  end

  context 'GET index' do
    it 'returns all issues as json' do
      get :index
      expect_json_types({ issues: :array })
      expect_json({ issues: -> (issues) {
        expect(issues.length).to be > 0
      }})
    end

    it 'returns issues with correct issue_type' do
      get :index, issue_type: 'stop_rsp_distance_gap,route_color,fake'
      expect_json({ issues: -> (issues) {
        expect(issues.length).to be > 0
      }})
    end

    it 'returns empty with no correct issue_type' do
      get :index, issue_type: 'route_color,fake'
      expect_json({ issues: -> (issues) {
        expect(issues.length).to eq 0
      }})
    end

    it 'returns issues by category' do
      Issue.create!(issue_type: 'route_name', details: 'a fake issue')
      get :index, category: 'route_geometry'
      expect_json({ issues: -> (issues) {
        expect(issues.length).to be > 0
        expect(Issue.count).to be > issues.length
      }})
    end

    it 'returns issues with feed' do
      changeset = create(:changeset)
      Issue.new(created_by_changeset: changeset, issue_type: 'stop_position_inaccurate').save!
      get :index, of_feed_entities: 'f-9qs-example'
      expect_json({ issues: -> (issues) {
        expect(issues.length).to eq 8
      }})
    end
  end

  context 'GET show' do
    it 'returns a 404 when not found' do
      get :show, id: 0
      expect(response.status).to eq 404
    end
  end

  context 'POST create' do
    before(:each) do
      @issue1 = {
        "details": "This is a test issue",
        "issue_type": 'rsp_line_only_stop_points',
        "entities_with_issues": [
          {
            "onestop_id": "s-9qt0rnrkjt-amargosavalleydemo",
            "entity_attribute": "geometry"
          },
          {
            "onestop_id": "r-9qt1-50-f8249d-e5d0eb",
            "entity_attribute": "geometry"
          }
        ]
      }
    end

    it 'creates an issue when no equivalent exists' do
      post :create, issue: @issue1
      expect(response.status).to eq 202
      expect(Issue.count).to eq 9 # was 8
      expect(EntityWithIssues.count).to eq 13 # was 11
    end

    it 'does not create issue when an equivalent one exists' do
      issue2 = {
        "details": "This is a test issue",
        "created_by_changeset_id": Changeset.last.id,
        "issue_type": 'stop_rsp_distance_gap',
        "entities_with_issues": [
          {
            "onestop_id": "s-9qscwx8n60-nyecountyairportdemo",
            "entity_attribute": "geometry"
          },
          {
            "onestop_id": "r-9qscy-30-a41e99-fcca25",
            "entity_attribute": "geometry"
          }
        ]
      }
      post :create, issue: issue2
      expect(response.status).to eq 409
      expect(Issue.count).to be > 0
    end

    it 'requires auth token to create issue' do
      @request.env['HTTP_AUTHORIZATION'] = nil
      post :create, issue: @issue1
      expect(response.status).to eq(401)
    end
  end

  context 'POST update' do
    it 'updates an existing issue' do
      issue = Issue.first
      details = "This is a test of updating"
      post :update, id: issue.id, issue: {details: details}
      expect(issue.reload.details).to eq details
    end

    it 'avoids deleting EntitiesWithIssues when param not supplied' do
      issue = Issue.first
      expect(issue.entities_with_issues.count).to eq(1)
      details = "This is a test of updating"
      post :update, id: issue.id, issue: {details: details}
      expect(issue.reload.entities_with_issues.size).to eq(1)
    end

    it 'creates specified EntitiesWithIssues and deletes existing EntitiesWithIssues' do
      issue = Issue.first
      details = "This is a test of updating",
      entities_with_issues = [{
          "onestop_id": 's-9qscwx8n60-nyecountyairportdemo',
          "entity_attribute": 'geometry'
      }]
      post :update, id: issue.id, issue: {details: details, entities_with_issues: entities_with_issues}
      expect(issue.reload.entities_with_issues.size).to eq 1
      expect(issue.reload.entities_with_issues.first.entity.onestop_id).to eq 's-9qscwx8n60-nyecountyairportdemo'
    end
  end

  context 'POST destroy' do
    it 'should delete issue' do
      issue = Issue.create!(details: "This is a test issue", created_by_changeset_id: 1, issue_type: "stop_rsp_distance_gap")
      issue.entities_with_issues.create(entity: Stop.find_by_onestop_id!('s-9qscwx8n60-nyecountyairportdemo'), entity_attribute: "geometry")
      post :destroy, id: issue.id
      expect(Issue.exists?(issue.id)).to eq(false)
    end

    it 'should require auth token to delete issue' do
      @request.env['HTTP_AUTHORIZATION'] = nil
      issue = Issue.create!(details: "This is a test issue", created_by_changeset_id: 1, issue_type: "stop_rsp_distance_gap")
      issue.entities_with_issues.create(entity: Stop.find_by_onestop_id!('s-9qscwx8n60-nyecountyairportdemo'), entity_attribute: "geometry")
      post :destroy, id: issue.id
      expect(response.status).to eq(401)
    end
  end
end
