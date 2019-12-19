describe 'Portfolios RBAC API' do
  let!(:portfolio1) { create(:portfolio) }
  let(:access_obj) { instance_double(Insights::API::Common::RBAC::Access, :owner_scoped? => false, :accessible? => true) }

  let(:group1) { instance_double(RBACApiClient::GroupOut, :name => 'group1', :uuid => "123") }
  let(:rs_class) { class_double("Insights::API::Common::RBAC::Service").as_stubbed_const(:transfer_nested_constants => true) }
  let(:api_instance) { double }

  before do
    allow(rs_class).to receive(:call).with(RBACApiClient::GroupApi).and_yield(api_instance)
    allow(Insights::API::Common::RBAC::Service).to receive(:paginate).with(api_instance, :list_groups, {:scope => "principal"}).and_return([group1])
    allow(Insights::API::Common::RBAC::Service).to receive(:paginate).with(api_instance, :list_groups, {}).and_return([group1])
  end

  describe "POST /portfolios" do
    let(:access_obj) { instance_double(Insights::API::Common::RBAC::Access, :accessible? => accessible) }
    let(:params) { {:name => 'Demo', :description => 'Desc 1' } }

    before do
      allow(Insights::API::Common::RBAC::Access).to receive(:new).with('portfolios', 'create').and_return(access_obj)
      allow(access_obj).to receive(:process).and_return(access_obj)
    end

    context "when the permission exists" do
      let(:accessible) { true }

      it "returns a 200" do
        post "#{api('1.0')}/portfolios", :headers => default_headers, :params => params
        expect(response).to have_http_status(200)
      end
    end

    context "when it is not accessible" do
      let(:accessible) { false }

      it "returns a 403" do
        post "#{api('1.0')}/portfolios", :headers => default_headers, :params => params
        expect(response).to have_http_status(403)
      end
    end
  end

  describe "DELETE /portfolios/{id}" do
    let(:access_obj) { instance_double(Insights::API::Common::RBAC::Access, :accessible? => accessible) }

    before do
      allow(Insights::API::Common::RBAC::Access).to receive(:new).with('portfolios', 'delete').and_return(access_obj)
      allow(access_obj).to receive(:process).and_return(access_obj)
    end

    context "when the permission exists" do
      let(:accessible) { true }

      before do
        create(:access_control_entry, :group_uuid => group1.uuid, :permission => 'delete', :aceable => portfolio1)
      end

      it "returns a 200" do
        delete "#{api("1.0")}/portfolios/#{portfolio1.id}", :headers => default_headers
        expect(response).to have_http_status(200)
      end
    end

    context "when it is not accessible" do
      let(:accessible) { false }

      it "returns a 403" do
        delete "#{api("1.0")}/portfolios/#{portfolio1.id}", :headers => default_headers
        expect(response).to have_http_status(403)
      end
    end
  end

  describe "GET /portfolios" do
    let(:access_obj) { instance_double(Insights::API::Common::RBAC::Access, :accessible? => accessible, :owner_scoped? => owner_scoped) }
    let(:accessible) { true }
    let(:owner_scoped) { true }

    before do
      allow(Insights::API::Common::RBAC::Roles).to receive(:assigned_role?).with(catalog_admin_role).and_return(false)
      allow(Insights::API::Common::RBAC::Access).to receive(:new).with('portfolios', 'read').and_return(access_obj)
      allow(access_obj).to receive(:process).and_return(access_obj)
    end

    context "when the permission exists" do
      before do
        create(:access_control_entry, :group_uuid => group1.uuid, :permission => 'read', :aceable => portfolio1)
        get "#{api('1.0')}/portfolios", :headers => default_headers
      end

      it "returns a 200" do
        expect(response).to have_http_status(200)
      end

      it "returns the portfolio id in the data" do
        result = JSON.parse(response.body)
        expect(result['data'][0]['id']).to eq(portfolio1.id.to_s)
      end
    end

    context "when it is not accessible" do
      let(:accessible) { false }

      it 'returns status code 403' do
        get "#{api('1.0')}/portfolios", :headers => default_headers

        expect(response).to have_http_status(403)
      end
    end

    context "when it is not owner scoped" do
      let(:owner_scoped) { false }

      before do
        get "#{api('1.0')}/portfolios", :headers => default_headers
      end

      it "returns a 200" do
        expect(response).to have_http_status(200)
      end

      it "returns the portfolio id in the data" do
        result = JSON.parse(response.body)
        expect(result['data'][0]['id']).to eq(portfolio1.id.to_s)
      end
    end

    context "with filtering" do
      let(:portfolio2) { create(:portfolio) }

      before do
        permission = 'read'
        create(:access_control_entry, :group_uuid => group1.uuid, :permission => permission, :aceable => portfolio1)
        create(:access_control_entry, :group_uuid => group1.uuid, :permission => permission, :aceable => portfolio2)
        allow(Insights::API::Common::RBAC::Access).to receive(:new).with('portfolios', permission).and_return(access_obj)
        allow(access_obj).to receive(:process).and_return(access_obj)
        get "#{api('1.0')}/portfolios?filter[name]=#{portfolio1.name}", :headers => default_headers
      end

      it 'returns a 200' do
        expect(response).to have_http_status(200)
      end

      it 'only returns the portfolio we filtered for' do
        result = JSON.parse(response.body)

        expect(result['meta']['count']).to eq 1
        expect(result['data'][0]['name']).to eq(portfolio1.name)
      end
    end
  end

  describe "POST /portfolios/:id/copy" do
    before do
      allow(Insights::API::Common::RBAC::Roles).to receive(:assigned_role?).with(catalog_admin_role).and_return(false)
    end

    context "when user does not have RBAC update portfolios access" do
      let(:block_access_obj) { instance_double(Insights::API::Common::RBAC::Access, :accessible? => false) }

      before do
        allow(Insights::API::Common::RBAC::Access).to receive(:new).with('portfolios', 'read').and_return(access_obj)
        allow(Insights::API::Common::RBAC::Access).to receive(:new).with('portfolios', 'create').and_return(access_obj)
        allow(access_obj).to receive(:process).and_return(access_obj)

        allow(Insights::API::Common::RBAC::Access).to receive(:new).with('portfolios', 'update').and_return(block_access_obj)
        allow(block_access_obj).to receive(:process).and_return(block_access_obj)
      end

      it 'returns a 403' do
        post "#{api("1.0")}/portfolios/#{portfolio1.id}/copy", :headers => default_headers
        expect(response).to have_http_status(403)
      end
    end

    context "when user has RBAC update portfolios access" do
      let(:portfolio_access_obj) { instance_double(Insights::API::Common::RBAC::Access, :accessible? => true, :owner_scoped? => true) }
      before do
        create(:access_control_entry, :group_uuid => group1.uuid, :permission => 'read', :aceable => portfolio1)
        create(:access_control_entry, :group_uuid => group1.uuid, :permission => 'update', :aceable => portfolio1)
        allow(Insights::API::Common::RBAC::Access).to receive(:new).with('portfolios', 'read').and_return(access_obj)
        allow(Insights::API::Common::RBAC::Access).to receive(:new).with('portfolios', 'create').and_return(access_obj)
        allow(access_obj).to receive(:process).and_return(access_obj)

        allow(Insights::API::Common::RBAC::Access).to receive(:new).with('portfolios', 'update').and_return(portfolio_access_obj)
        allow(portfolio_access_obj).to receive(:process).and_return(portfolio_access_obj)
      end

      it 'returns a 200' do
        post "#{api("1.0")}/portfolios/#{portfolio1.id}/copy", :headers => default_headers
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "POST /portfolios/:id/share" do
    context "when the permissions array is malformed" do
      it "errors on a blank array" do
        params = {:permissions => [], :group_uuids => ['1'] }
        post "#{api}/portfolios/#{portfolio1.id}/share", :headers => default_headers, :params => params

        expect(response).to have_http_status(:bad_request)
        expect(first_error_detail).to match(/contains fewer than min items/)
      end

      it "errors when the object is not an array" do
        params = {:permissions => 1, :group_uuids => ['1'] }
        post "#{api}/portfolios/#{portfolio1.id}/share", :headers => default_headers, :params => params

        expect(response).to have_http_status(:bad_request)
        expect(first_error_detail).to match(/expected array, but received Integer/)
      end
    end

    context "when the permissions array is proper" do
      describe "#share" do
        let(:permissions) { %w[update] }

        it "goes through validation" do
          post "#{api}/portfolios/#{portfolio1.id}/share", :headers => default_headers, :params => {
            :permissions => permissions,
            :group_uuids => [group1.uuid]
          }

          expect(response).to have_http_status(:no_content)
        end
      end
    end
  end

  describe "POST /portfolios/:id/unshare" do
    context "when the permissions array is proper" do
      let(:permissions) { %w[update] }

      before do
        create(:access_control_entry, :group_uuid => group1.uuid, :permission => 'update', :aceable => portfolio1)
      end

      it "goes through validation" do
        post "#{api}/portfolios/#{portfolio1.id}/unshare", :headers => default_headers, :params => {
          :permissions => permissions,
          :group_uuids => [group1.uuid]
        }

        expect(response).to have_http_status(:no_content)
      end
    end
  end
end
