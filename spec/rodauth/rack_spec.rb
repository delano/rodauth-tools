# spec/rodauth/rack_spec.rb
#
# frozen_string_literal: true

RSpec.describe Rodauth::Tools do
  it 'has a version number' do
    expect(Rodauth::Tools::VERSION).not_to be_nil
  end

  it 'has an Error class' do
    expect(Rodauth::Tools::Error).to be < StandardError
  end
end
