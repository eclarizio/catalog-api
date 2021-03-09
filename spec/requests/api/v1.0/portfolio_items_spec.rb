describe "v1.0 - PortfolioItemRequests", :type => [:request, :inventory, :v1] do
  let(:catalog_access) { instance_double(Insights::API::Common::RBAC::Access, :scopes => %w[admin]) }
  before do
    allow(Insights::API::Common::RBAC::Access).to receive(:new).and_return(catalog_access)
    allow(catalog_access).to receive(:process).and_return(catalog_access)
    allow(catalog_access).to receive(:accessible?).with("portfolios", "create").and_return(true)
    allow(catalog_access).to receive(:accessible?).with("portfolios", "read").and_return(true)
  end

  let(:service_offering_ref) { "998" }
  let(:service_offering_source_ref) { "568" }
  let(:order) { create(:order) }
  let!(:portfolio) { create(:portfolio) }
  let!(:portfolio_items) { portfolio.portfolio_items << portfolio_item }
  let(:portfolio_id) { portfolio.id.to_s }
  let(:portfolio_item) do
    create(:portfolio_item, :service_offering_ref        => service_offering_ref,
                            :service_offering_source_ref => service_offering_source_ref,
                            :description                 => "default description",
                            :long_description            => "longer than description",
                            :distributor                 => "Distributor CO",
                            :portfolio                   => portfolio)
  end
  let(:portfolio_item_id)    { portfolio_item.id.to_s }
  let(:topo_ex)              { Catalog::CatalogInventoryError.new("kaboom") }

  describe "GET /portfolio_items/:portfolio_item_id" do
    before do
      get "#{api_version}/portfolio_items/#{portfolio_item_id}", :headers => default_headers
    end

    context 'the portfolio_item exists' do
      it 'returns status code 200' do
        expect(response).to have_http_status(200)
      end

      it 'returns the portfolio_item we asked for' do
        expect(json["id"]).to eq portfolio_item_id
      end

      it 'portfolio item references parent portfolio' do
        expect(json["portfolio_id"]).to eq portfolio_id
      end
    end

    context 'the portfolio_item does not exist' do
      let(:portfolio_item_id) { 0 }

      it "can't be requested" do
        expect(response).to have_http_status(404)
      end
    end
  end

  describe "GET /portfolios/:portfolio_id/portfolio_items" do
    before do
      portfolio_item_policy_scope = PortfolioItemPolicy::Scope.new(nil, PortfolioItem)
      allow(PortfolioItemPolicy::Scope).to receive(:new).and_return(portfolio_item_policy_scope)
      allow(portfolio_item_policy_scope).to receive(:resolve).and_return(PortfolioItem.all)

      get "#{api_version}/portfolios/#{portfolio_id}/portfolio_items", :headers => default_headers
    end

    context "when the portfolio exists" do
      it 'returns all associated portfolio_items' do
        expect(json).not_to be_empty
        expect(json['meta']['count']).to eq 1
        portfolio_item_ids = portfolio_items.map { |x| x.id.to_s }.sort
        expect(json['data'].map { |x| x['id'] }.sort).to eq portfolio_item_ids
      end
    end

    context "when the portfolio does not exist" do
      let(:portfolio_id) { portfolio.id + 100 }

      it 'returns a 404' do
        expect(first_error_detail).to match(/Couldn't find Portfolio/)
        expect(response.status).to eq(404)
      end
    end
  end

  describe 'DELETE admin tagged /portfolio_items/:portfolio_item_id' do
    subject do
      delete "#{api_version}/portfolio_items/#{portfolio_item_id}", :headers => default_headers
    end

    context 'when v1.0 :portfolio_item_id is valid' do
      before do |example|
        subject unless example.metadata[:subject_inside]
      end

      it_behaves_like "action that tests authorization", :destroy?, PortfolioItem

      it 'discards the record' do
        expect(response).to have_http_status(:ok)
      end

      it 'is still present in the db, just with deleted_at set' do
        expect(PortfolioItem.with_discarded.find_by(:id => portfolio_item_id).discarded_at).to_not be_nil
      end

      it 'returns the restore_key in the body' do
        expect(json["restore_key"]).to eq Digest::SHA1.hexdigest(PortfolioItem.with_discarded.find(portfolio_item_id).discarded_at.to_s)
      end
    end
  end

  describe 'POST /portfolio_items/{portfolio_item_id}/undelete' do
    let(:restore) do
      post "#{api_version}/portfolio_items/#{portfolio_item_id}/undelete",
           :params  => {:restore_key => restore_key},
           :headers => default_headers
    end
    let(:restore_key) { Digest::SHA1.hexdigest(portfolio_item.discarded_at.to_s) }
    subject { restore }

    context "when restoring a portfolio_item that has been discarded" do
      before do |example|
        portfolio_item.discard
        subject unless example.metadata[:subject_inside]
      end

      it_behaves_like "action that tests authorization", :restore?, PortfolioItem

      it "returns a 200" do
        expect(response).to have_http_status :ok
      end

      it "returns the restored portfolio_item" do
        expect(json["id"]).to eq portfolio_item_id.to_s
        expect(json["name"]).to eq portfolio_item.name
      end
    end

    context 'when attempting to restore with the wrong restore_key' do
      let(:restore_key) { "MrMaliciousRestoreKey" }

      before do |example|
        portfolio_item.discard
        subject unless example.metadata[:subject_inside]
      end

      it_behaves_like "action that tests authorization", :restore?, PortfolioItem

      it "returns a 403" do
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when attempting to restore a portfolio_item that not been discarded' do
      it "returns a 404" do
        restore
        expect(response).to have_http_status :not_found
      end
    end
  end

  describe 'GET portfolio items' do
    context "v1.0" do
      before do
        portfolio_item_policy_scope = PortfolioItemPolicy::Scope.new(nil, PortfolioItem)
        allow(PortfolioItemPolicy::Scope).to receive(:new).and_return(portfolio_item_policy_scope)
        allow(portfolio_item_policy_scope).to receive(:resolve).and_return(PortfolioItem.all)
      end

      it "success" do
        portfolio_item
        get "#{api_version}/portfolio_items", :headers => default_headers
        expect(response).to have_http_status(200)
        expect(JSON.parse(response.body)['data'].count).to eq(1)
      end
    end
  end

  context "when adding portfolio items" do
    let(:add_to_portfolio_svc) { double(Api::V1x0::ServiceOffering::AddToPortfolioItem) }
    let(:params) { {:service_offering_ref => service_offering_ref, :portfolio_id => portfolio.id.to_s} }
    let(:permitted_params) { ActionController::Parameters.new(params).permit(:service_offering_ref, :portfolio_id) }

    subject do
      post "#{api_version}/portfolio_items", :params => params, :headers => default_headers
    end

    before do
      allow(Api::V1x0::ServiceOffering::AddToPortfolioItem).to receive(:new).with(permitted_params).and_return(add_to_portfolio_svc)
    end

    context "when a portfolio_id is not included in the parameters" do
      let(:params) { {:service_offering_ref => service_offering_ref} }

      before do
        subject
      end

      it "returns a 400" do
        expect(response).to have_http_status(:bad_request)
      end

      it "returns a required parameter error in the body" do
        expect(first_error_detail).to match(/missing required parameters: portfolio_id/)
      end
    end

    context "when inventory doesn't have the service offering ref" do
      before do |example|
        allow(add_to_portfolio_svc).to receive(:process).and_raise(topo_ex)

        subject unless example.metadata[:subject_inside]
      end

      it_behaves_like "action that tests authorization", :create?, PortfolioItem

      it "returns not found when inventory doesn't have the service_offering_ref" do
        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context "when inventory does have the service offering ref" do
      before do |example|
        allow(add_to_portfolio_svc).to receive(:process).and_return(add_to_portfolio_svc)
        allow(add_to_portfolio_svc).to receive(:item).and_return(portfolio_item)

        subject unless example.metadata[:subject_inside]
      end

      it_behaves_like "action that tests authorization", :create?, PortfolioItem

      it "returns the new portfolio item when inventory has the service_offering_ref" do
        expect(response).to have_http_status(:ok)
        expect(json["id"]).to eq portfolio_item.id.to_s
        expect(json["owner"]).to eq portfolio_item.owner
      end
    end
  end

  context "when passing in read-only parameters" do
    let(:params) { {:service_offering_ref => service_offering_ref, :portfolio_id => portfolio.id.to_s, :owner => "me"} }

    before { post "#{api_version}/portfolio_items", :params => params, :headers => default_headers }

    it "returns a 400" do
      expect(response).to have_http_status(400)
    end

    it "returns a required parameter error in the body" do
      expect(first_error_detail).to match(/unpermitted.*owner/)
    end
  end

  context "v1.0 provider control parameters" do
    let(:url) { "#{api_version}/portfolio_items/#{portfolio_item.id}/provider_control_parameters" }

    it "fetches plans" do
      stub_request(:get, catalog_inventory_url("sources/568/container_projects"))
        .to_return(:status => 200, :body => {:data => [:name => 'fred']}.to_json, :headers => {"Content-type" => "application/json"})

      get url, :headers => default_headers

      expect(response.content_type).to eq("application/json")
      expect(response).to have_http_status(:ok)
    end

    xit "raises error" do
      stub_request(:get, catalog_inventory_url("sources/568/container_projects"))
        .to_return(:status => 404, :body => "", :headers => {"Content-type" => "application/json"})

      get url, :headers => default_headers

      expect(response).to have_http_status(:service_unavailable)
    end
  end

  describe "patching portfolio items" do
    subject do
      patch "#{api_version}/portfolio_items/#{portfolio_item.id}", :params => params, :headers => default_headers
    end

    context "when passing in valid attributes" do
      let(:params) { {:name => 'PatchPortfolio', :description => 'PatchDescription'} }

      before do |example|
        stub_request(:get, approval_url("workflows/PatchWorkflowRef"))
          .to_return(:status => 200, :body => "", :headers => {"Content-type" => "application/json"})

        subject unless example.metadata[:subject_inside]
      end

      it_behaves_like "action that tests authorization", :update?, PortfolioItem

      it 'returns a 200' do
        expect(response).to have_http_status(:ok)
      end

      it 'patches the record' do
        expect(json).to include(params.stringify_keys)
      end
    end

    context "when passing in read-only attributes" do
      let(:params) { {:name => 'PatchPortfolio', :service_offering_ref => "27"} }

      before do |example|
        subject unless example.metadata[:subject_inside]
      end

      it_behaves_like "action that tests authorization", :update?, PortfolioItem

      it 'returns a 400' do
        expect(response).to have_http_status(:bad_request)
        expect(first_error_detail).to match(/found unpermitted parameter: :service_offering_ref/)
      end
    end

    context "when passing partial attributes" do
      let(:params) { {:name => 'Curious George'} }

      before do |example|
        subject unless example.metadata[:subject_inside]
      end

      it_behaves_like "action that tests authorization", :update?, PortfolioItem

      it 'returns a 200' do
        expect(response).to have_http_status(:ok)
      end
    end

    context "when passing in nullable attributes" do
      let(:params) { {:name => 'PatchPortfolio', :description => nil, :long_description => nil, :distributor => nil} }

      before do |example|
        subject unless example.metadata[:subject_inside]
      end

      it_behaves_like "action that tests authorization", :update?, PortfolioItem

      it 'returns a 200' do
        expect(response).to have_http_status(:ok)
      end

      it 'updates the field that is null' do
        expect(json["description"]).to be_nil
        expect(json["distributor"]).to be_nil
        expect(json["long_description"]).to be_nil
      end
    end
  end

  describe "copying portfolio items" do
    let(:portfolio_item_orderable) { instance_double(Api::V1x1::Catalog::PortfolioItemOrderable, :result => true) }

    subject do
      post "#{api_version}/portfolio_items/#{portfolio_item.id}/copy", :params => params, :headers => default_headers
    end

    before do |example|
      allow(Api::V1x1::Catalog::PortfolioItemOrderable).to receive(:new).and_return(portfolio_item_orderable)
      allow(portfolio_item_orderable).to receive(:process).and_return(portfolio_item_orderable)
      subject unless example.metadata[:subject_inside]
    end

    context "when copying into the same portfolio" do
      let(:params) { {:portfolio_id => portfolio_id} }

      it_behaves_like "action that tests authorization", :copy?, PortfolioItem

      it "returns a 200" do
        expect(response).to have_http_status(:ok)
      end

      it "returns a copy of the portfolio_item" do
        expect(json["description"]).to eq portfolio_item.description
        expect(json["owner"]).to eq portfolio_item.owner
      end

      it "modifies the name to not collide" do
        expect(json["name"]).to_not eq portfolio_item.name
        expect(json["name"]).to match(/^Copy of.*/)
      end

      context "when payload has new portfolio item name" do
        let(:params) { {:portfolio_id => portfolio_id, :portfolio_item_name => 'new_portfolio_item_name'} }

        it "returns portfolio item with new name" do
          expect(json["name"]).to eq("new_portfolio_item_name")
        end
      end
    end

    context "when copying into a different portfolio" do
      let(:params) { {:portfolio_id => new_portfolio.id.to_s} }
      let(:new_portfolio) { create(:portfolio) }

      it_behaves_like "action that tests authorization", :copy?, PortfolioItem

      it "returns a 200" do
        expect(response).to have_http_status(:ok)
      end

      it "returns a copy of the portfolio_item" do
        expect(json["description"]).to eq portfolio_item.description
        expect(json["owner"]).to eq portfolio_item.owner
        expect(json["name"]).to eq portfolio_item.name
      end
    end

    context "when copying into a different portfolio in a different tenant" do
      let(:params) { {:portfolio_id => not_my_portfolio.id.to_s} }
      let(:not_my_portfolio) { create(:portfolio, :tenant => create(:tenant, :external_tenant => "xyz")) }

      it_behaves_like "action that tests authorization", :copy?, PortfolioItem

      it 'returns a 400' do
        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe '#next_name' do
    context "when querying the next name on a portfolio item" do
      before { get "#{api_version}/portfolio_items/#{portfolio_item.id}/next_name", :headers => default_headers }

      it "returns a 200" do
        expect(response).to have_http_status(:ok)
      end

      it "returns a json object with the next name" do
        expect(json["next_name"]).to eq 'Copy of ' + portfolio_item.name
      end
    end
  end

  context "tagging endpoints" do
    let(:rbac_access) { instance_double(Catalog::RBAC::Access) }

    before do
      allow(Catalog::RBAC::Access).to receive(:new).and_return(rbac_access)
      allow(rbac_access).to receive(:resource_check).with("update", portfolio.id, Portfolio).and_return(true)
      allow(rbac_access).to receive(:approval_workflow_check).and_return(true)
    end

    it_behaves_like "controller that supports tagging endpoints" do
      let(:object_instance) { portfolio_item }
    end
  end
end
