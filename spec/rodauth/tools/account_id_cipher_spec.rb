# spec/rodauth/tools/account_id_cipher_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rodauth::Tools::AccountIdCipher do
  let(:secret) { 'a' * 32 }
  let(:cipher) { described_class.new(secret) }

  # Boundary ids across the 32-bit split point and the 64-bit domain edges.
  let(:boundary_ids) do
    [0, 1, 2, 3, 42, 1000, (2**31) - 1, 2**31, (2**32) - 1, 2**32,
     2**53, 2**62, (2**63) - 1, (2**64) - 1]
  end

  describe '#initialize' do
    it 'accepts a secret of at least 32 bytes' do
      expect { described_class.new('a' * 32) }.not_to raise_error
    end

    it 'raises ArgumentError for a secret shorter than 32 bytes' do
      expect { described_class.new('a' * 31) }.to raise_error(ArgumentError, /32 bytes/)
    end

    it 'raises ArgumentError for a nil secret' do
      expect { described_class.new(nil) }.to raise_error(ArgumentError)
    end

    it 'exposes the minimum secret length' do
      expect(described_class::MIN_SECRET_BYTES).to eq(32)
    end
  end

  describe '#encode / #decode round-trip' do
    it 'round-trips every boundary id across the 64-bit domain' do
      boundary_ids.each do |id|
        expect(cipher.decode(cipher.encode(id))).to eq(id)
      end
    end

    it 'coerces #to_i-style integer input' do
      expect(cipher.decode(cipher.encode(Integer('7')))).to eq(7)
    end
  end

  describe '#encode output format' do
    it 'is always exactly 13 characters wide' do
      widths = boundary_ids.map { |id| cipher.encode(id).length }.uniq
      expect(widths).to eq([described_class::WIDTH])
    end

    it 'uses only the Crockford Base32 alphabet' do
      allowed = described_class::ALPHABET.chars.to_set
      boundary_ids.each do |id|
        expect(cipher.encode(id).chars.to_set).to be_subset(allowed)
      end
    end

    it 'never contains an underscore (URL- and cookie-separator-safe)' do
      expect(boundary_ids.map { |id| cipher.encode(id) }.none? { |t| t.include?('_') }).to be(true)
    end

    it 'maps adjacent ids to unrelated tokens (no visible sequence)' do
      expect(cipher.encode(2)).not_to eq(cipher.encode(3))
      expect(cipher.encode(1000)[0, 4]).not_to eq(cipher.encode(1001)[0, 4])
    end
  end

  describe '#encode is a bijection' do
    it 'produces no collisions across a large contiguous range' do
      seen = {}
      collision = false
      (0..20_000).each do |i|
        token = cipher.encode(i)
        collision ||= seen.key?(token)
        seen[token] = i
      end
      expect(collision).to be(false)
    end
  end

  describe '#decode with malformed input' do
    [nil, '', 'too-short', 'x' * 14, '!!!!!!!!!!!!!', 12_345, :symbol].each do |bad|
      it "returns nil for #{bad.inspect}" do
        expect(cipher.decode(bad)).to be_nil
      end
    end

    it 'returns nil for a 13-char string containing a non-alphabet character' do
      # 'I', 'L', 'O', 'U' are excluded from Crockford Base32
      expect(cipher.decode('IIIIIIIIIIIII')).to be_nil
    end
  end

  describe 'key dependence' do
    it 'produces different ciphertext under a different secret' do
      other = described_class.new('b' * 32)
      expect(cipher.encode(2)).not_to eq(other.encode(2))
    end

    it 'does not decode a token minted under a different secret back to the id' do
      other = described_class.new('b' * 32)
      expect(cipher.decode(other.encode(2))).not_to eq(2)
    end
  end
end
