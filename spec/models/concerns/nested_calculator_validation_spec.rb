# frozen_string_literal: true

require 'spec_helper'

shared_examples "a parent model that has a Calculator" do |parent_name|
  context "when the associated Calculator is valid" do
    let(:valid_parent) do
      build(parent_name, calculator: Calculator::FlatRate.new(preferred_amount: 10))
    end

    it "is valid" do
      expect(valid_parent).to be_valid
    end
  end

  context "when the associated Calculator is invalid" do
    let(:invalid_parent) do
      build(parent_name, calculator: Calculator::FlexiRate.new(preferred_first_item: "invalid"))
    end

    before do
      invalid_parent.valid?
    end

    it "is invalid" do
      expect(invalid_parent).not_to be_valid
    end

    it "adds custom error messages to base" do
      error_messages = invalid_parent.errors.full_messages
      expect(error_messages).to include(/^Calculator First Item: Invalid input./)
    end

    it "has the correct number of errors messages" do
      error_messages = invalid_parent.errors.full_messages
      expect(error_messages.count).to eq 1
    end

    it "does not include the generic Calculator error message" do
      error_messages = invalid_parent.errors.full_messages
      expect(error_messages).not_to include(/^Calculator is invalid$/)
    end

    it "does not include error message that begins with 'Calculator preferred'" do
      error_messages = invalid_parent.errors.full_messages
      expect(error_messages).not_to include(/^Calculator preferred/)
    end

    context "with multiple errors" do
      let(:invalid_parent) do
        build(parent_name,
          calculator: Calculator::FlexiRate.new(
            preferred_first_item: "invalid",
            preferred_additional_item: "invalid",
          ))
      end

      it "adds custom error messages to base" do
        error_messages = invalid_parent.errors.full_messages
        expect(error_messages[0]).to match(/^Calculator First Item: Invalid input./)
        expect(error_messages[1]).to match(/^Calculator Additional Item Cost: Invalid input./)
      end

      it "has the correct number of errors messages" do
        error_messages = invalid_parent.errors.full_messages
        expect(error_messages.count).to eq 2
      end
    end
  end

  context "when number localization is enabled and the associated Calculator is invalid" do
    let(:localized_parent) do
      build(parent_name, calculator: Calculator::FlatRate.new(preferred_amount: "invalid"))
    end

    before do
      allow(Spree::Config).to receive(:enable_localized_number?).and_return true
      localized_parent.valid?
    end

    it "adds custom error messages to base" do
      error_messages = localized_parent.errors.full_messages
      expect(error_messages).to include(/^Calculator Amount: has an invalid format./)
    end
  end
end
