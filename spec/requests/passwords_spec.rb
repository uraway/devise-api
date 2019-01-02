require 'rails_helper'

include ActiveSupport::Testing::TimeHelpers

RSpec.describe '/v1/passwords', type: :request do
  let(:user) { FactoryBot.create(:user) }

  describe 'POST /v1/passwords' do
    context 'when user exists' do
      it 'sends reset password instructions' do
        params = { user: { email: user.email } }

        post '/v1/passwords', params: params
        expect(response).to be_successful
        expect(ActionMailer::Base.deliveries.size).to eq(1)
      end
    end

    context 'when user does not exist' do
      it 'does not send reset password instructions and get successful response' do
        params = { user: { email: 'doesnotexist@example.com' } }

        post '/v1/passwords', params: params
        expect(response).to be_successful
        expect(ActionMailer::Base.deliveries.size).to eq(0)
      end
    end
  end

  describe 'PUT /v1/passwords' do
    before do
      @raw, enc = Devise.token_generator.generate(User, :reset_password_token)
      user.reset_password_token   = enc
      user.reset_password_sent_at = Time.now.utc
      user.save(validate: false)
    end

    context 'when params have a new password and a valid token' do
      it 'resets password' do
        travel_to(Time.current + 5.hours)
        params = { user: { password: 'newpass', reset_password_token: @raw } }
        put '/v1/passwords', params: params
        expect(User.first.valid_password? 'newpass').to eq true
      end
    end

    context 'when params have invalid token' do
      it 'does not reset password with wrong token' do
        params = { user: { password: 'newpass', reset_password_token: 'wrongtoken' } }
        put '/v1/passwords', params: params
        expect(User.first.valid_password? 'newpass').to eq false
      end

      it 'does not reset password with expired token' do
        travel_to(Time.current + 7.hours)
        params = { user: { password: 'newpass', reset_password_token: @raw } }
        put '/v1/passwords', params: params
        expect(User.first.valid_password? 'newpass').to eq false
      end
    end

    context 'when params have invalid password_confirmation' do
      it 'does not reset password' do
        params = { user: { password: 'newpass', password_confirmation: 'wrongpass', reset_password_token: @raw } }
        put '/v1/passwords', params: params
        expect(User.first.valid_password? 'newpass').to eq false
      end
    end
  end
end
