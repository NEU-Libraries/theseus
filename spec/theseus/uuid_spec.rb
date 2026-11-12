# frozen_string_literal: true

RSpec.describe Theseus::UUID do
  # Python: uuid.uuid5(uuid.NAMESPACE_URL, "info:fedora/neu:cj82kh734")
  it "matches a reference version 5 UUID" do
    expect(described_class.work_key("neu:cj82kh734")).to eq("f63bc21b-ea4e-5c1b-8cf4-f03512be8cc1")
  end

  it "gives each pid its own key" do
    expect(described_class.work_key("neu:a")).not_to eq(described_class.work_key("neu:b"))
  end
end
