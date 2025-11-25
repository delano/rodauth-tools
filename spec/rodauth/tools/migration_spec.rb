# spec/rodauth/tools/migration_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rodauth::Tools::Migration do
  describe '#initialize' do
    it 'accepts features as an array' do
      generator = described_class.new(features: %i[base verify_account])
      expect(generator.features).to eq(%i[base verify_account])
    end

    it 'converts features to symbols' do
      generator = described_class.new(features: %w[base otp])
      expect(generator.features).to eq(%i[base otp])
    end

    it 'accepts custom prefix' do
      generator = described_class.new(features: [:base], prefix: 'user')
      expect(generator.prefix).to eq('user')
    end

    it 'accepts database adapter' do
      generator = described_class.new(features: [:base], db_adapter: :postgresql)
      expect(generator.db_adapter).to eq(:postgresql)
    end

    it 'raises error when no features specified' do
      expect do
        described_class.new(features: [])
      end.to raise_error(ArgumentError, /No features specified/)
    end
  end

  describe '#migration_name' do
    it 'generates migration name with default prefix' do
      generator = described_class.new(features: %i[base verify_account])
      expect(generator.migration_name).to eq('create_rodauth_base_verify_account')
    end

    it 'generates migration name with custom prefix' do
      generator = described_class.new(features: [:base], prefix: 'user')
      expect(generator.migration_name).to eq('create_rodauth_user_base')
    end

    it 'generates migration name for single feature' do
      generator = described_class.new(features: [:otp])
      expect(generator.migration_name).to eq('create_rodauth_otp')
    end
  end

  describe '#generate' do
    it 'generates migration for base feature' do
      generator = described_class.new(features: [:base])
      migration = generator.generate

      expect(migration).to include('create_table(:accounts)')
      expect(migration).to include('primary_key :id')
      expect(migration).to include('foreign_key :status_id')
      expect(migration).to include('String :password_hash')
    end

    it 'generates migration for verify_account feature' do
      generator = described_class.new(features: [:verify_account])
      migration = generator.generate

      expect(migration).to include('create_table(:account_verification_keys)')
    end

    it 'generates migration for multiple features' do
      generator = described_class.new(features: %i[base remember])
      migration = generator.generate

      expect(migration).to include('create_table(:accounts)')
      expect(migration).to include('create_table(:account_remember_keys)')
    end

    it 'uses custom table prefix' do
      generator = described_class.new(features: [:base], prefix: 'user')
      migration = generator.generate

      expect(migration).to include('create_table(:users)')
    end

    context 'with invalid features' do
      it 'raises error for unknown feature' do
        expect do
          described_class.new(features: [:unknown_feature])
        end.to raise_error(ArgumentError, /No migration template/)
      end
    end
  end

  describe 'all available features' do
    let(:all_features) do
      %i[
        base remember verify_account verify_login_change
        reset_password email_auth otp otp_unlock sms_codes
        recovery_codes webauthn lockout active_sessions
        account_expiration password_expiration single_session
        audit_logging disallow_password_reuse jwt_refresh
      ]
    end

    it 'has Sequel templates for all 19 features' do
      all_features.each do |feature|
        expect do
          described_class.new(features: [feature])
        end.not_to raise_error
      end
    end

    it 'generates migrations for all features' do
      all_features.each do |feature|
        generator = described_class.new(features: [feature])
        migration = generator.generate
        expect(migration).not_to be_empty
      end
    end
  end
end
