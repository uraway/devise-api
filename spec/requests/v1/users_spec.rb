require 'rails_helper'

describe 'GET /v1/users' do
  let(:path) { '/v1/users' }

  it 'should get index' do
    get_user path
    expect(response).to be_success
    expect(response.status).to eq 200
  end
end
