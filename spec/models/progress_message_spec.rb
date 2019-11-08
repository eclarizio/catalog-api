describe ProgressMessage, :type => :model do
  let(:order1) { create(:order) }
  let(:order2) { create(:order) }
  let(:order_item1) { create(:order_item, :order => order1) }
  let(:order_item2) { create(:order_item, :order => order2) }
  let!(:progress_message1) { create(:progress_message, :order_item_id => order_item1.id) }
  let!(:progress_message2) { create(:progress_message, :order_item_id => order_item2.id) }

  around do |example|
    Insights::API::Common::Request.with_request(default_request) { example.call }
  end

  context "by_owner" do
    let(:results) { ProgressMessage.by_owner }

    before do
      order2.update!(:owner => "not_jdoe")
    end

    it "only has one result" do
      expect(results.size).to eq 1
    end

    it "filters by the owner" do
      expect(results.first.id).to eq progress_message1.id
    end
  end
end
