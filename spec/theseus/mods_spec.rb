# frozen_string_literal: true

RSpec.describe Theseus::Mods do
  def mods(body) = %(<mods:mods xmlns:mods="http://www.loc.gov/mods/v3">#{body}</mods:mods>)

  it "reads the handle from a real v1 CoreFile record, without the resolver host" do
    expect(described_class.handle("neu:cj82kh734", fixture("core_file_mods.xml"))).to eq("2047/D20201656")
  end

  it "answers nil for a record with no handle (a real v1 Community, with no XML declaration)" do
    expect(described_class.handle("neu:466", fixture("community_mods.xml"))).to be_nil
  end

  it "reads a handle from MODS in the default namespace" do
    xml = %(<mods xmlns="http://www.loc.gov/mods/v3"><identifier type="hdl">2047/D1</identifier></mods>)
    expect(described_class.handle("neu:x", xml)).to eq("2047/D1")
  end

  it "ignores other identifier types" do
    xml = mods(%(<mods:identifier type="uri">http://example.org/1</mods:identifier>))
    expect(described_class.handle("neu:x", xml)).to be_nil
  end

  it "treats the same handle twice as one" do
    xml = mods(%(<mods:identifier type="hdl">http://hdl.handle.net/2047/D1</mods:identifier>) +
               %(<mods:identifier type="hdl">2047/D1</mods:identifier>))
    expect(described_class.handle("neu:x", xml)).to eq("2047/D1")
  end

  it "refuses two different handles" do
    xml = mods(%(<mods:identifier type="hdl">2047/D1</mods:identifier>) +
               %(<mods:identifier type="hdl">2047/D2</mods:identifier>))
    expect { described_class.handle("neu:x", xml) }
      .to raise_error(Theseus::FindingError, /ambiguous_v1_handle/)
  end

  it "refuses XML that is not well formed" do
    expect { described_class.parse!("neu:x", "<mods:mods") }
      .to raise_error(Theseus::FindingError, /invalid_mods/)
  end

  it "refuses a document that is not MODS" do
    expect { described_class.parse!("neu:x", "<html/>") }
      .to raise_error(Theseus::FindingError, /not MODS/)
  end
end
