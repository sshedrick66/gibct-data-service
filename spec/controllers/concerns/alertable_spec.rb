class FakesController < ApplicationController
  include Alertable
end

class MyFakesCsvFile < CsvFile
end
 
describe FakesController, type: :controller do
  let(:label) { "a message" }
  let(:label_only) { "<p>a message</p>" }
  let(:errors) { %w(a b) }
  let(:errors_only) { "<ul><li>a</li><li>b</li></ul>" }
  let(:label_and_errors) { label_only + errors_only }

  describe "when alerting" do
    it "returns an empty string with no arguments" do
      expect(FakesController.pretty_error).to eq("")
    end

    it "returns a label with no error list" do
      expect(FakesController.pretty_error(label)).to eq(label_only)
    end

    it "returns a list with one item per error wuth no label" do
      expect(FakesController.pretty_error("", errors)).to eq(errors_only)
    end

    it "returns a label and error list" do
      expect(FakesController.pretty_error(label, errors)).to eq(label_and_errors)
    end
  end

  describe "get_csv_file_types" do
    before(:all) do
      Rails.application.eager_load!
    end

    it "gets a list of *CsvFile classes" do
      expect(DashboardsController.get_csv_file_types.length).to be > 0
      expect(FakesController.get_csv_file_types).to include(["My Fakes", "MyFakesCsvFile"])
    end
  end
end